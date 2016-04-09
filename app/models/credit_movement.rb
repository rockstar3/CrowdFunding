class CreditMovement < ActiveRecord::Base
  class NilPayee < RuntimeError; end
  class NilPayer < RuntimeError; end
  class ClassMismatch < RuntimeError; end

  # metadata - to allow additional data to be stored with this credit movement
  serialize :metadata, Hash

  belongs_to :payer, polymorphic: true # The person/transaction giving
  belongs_to :payee, polymorphic: true # The person/transaction receiving

  has_one    :transaction
  has_many   :reward_distributions

  state_machine :initial => :pending do
    event :complete do
      transition :pending => :completed, :unless => :lacking_credits_for_project?
      transition :pending => same
    end
  end

  validates :payee, presence: true
  validates :payer, presence: true
  validates :quantity_of_credits, presence: true, numericality: true

  scope :completed,         where(state: 'completed')
  scope :from_transactions, where(payer_type: 'Transaction')
  scope :from_users,        where(payer_type: 'User')
  scope :to_projects,       where(payee_type: 'Project')
  scope :not_refunded,      where(refunded_credit_movement_id: nil)

  def self.this_month
    where("credit_movements.created_at >= ?", Time.now.at_beginning_of_month.to_s(:db))
  end

  def active_admin_comments
    ActiveAdmin::Comment.where(:resource_type => self.class.to_s, :resource_id => self.id.to_s).pluck('body').join('\n\n')
  end

  # Updates reward distributions from the fund project form
  #
  # funding_tier_ids - The funding tier ids chosen
  # reward_choices - The map of reward choices in the form of:
  #
  #   { "<FUNDING_TIER_ID>" => [
  #       {"reward_id" => "3", "Size" => "4", "Color" => "Red"},
  #       ...
  #     ],
  #     ...
  #   }
  def reward_distributions_from_form(funding_tier_ids, reward_choices=nil)
    return if funding_tier_ids.blank?
    raise NilPayee, "You must set the payee before you can set the reward distributions" if self.payee.nil?
    raise NilPayer, "You must set the payer before you can set the reward distributions" if self.payer.nil?
    raise ClassMismatch, "In order to set reward distributions, you must be working with a 'Project' based payee" unless self.payee.is_a?(Project)

    payee.funding_tiers.find(funding_tier_ids).each do |tier|
      rd = reward_distributions.build(
        funding_tier_id: tier.id,
        project: self.payee,
        user: self.payer,
        credit_movement: self
      )
      # build reward choices selection
      funding_tier_choices = reward_choices && reward_choices[tier.id.to_s]
      if funding_tier_choices.present?
        funding_tier_choices.each do |reward_id, choices|
          choices.each do |choice|
            reward = tier.rewards.find(reward_id)
            rd.reward_distribution_rewards.build(
              reward: reward,
              options: JSON.generate(choice)
            )
          end
        end
      end
    end
  end

  def user
    if payer.is_a?(User)
      payer
    elsif payee.is_a?(User)
      payee
    else
      raise 'No user is associated with this transaction'
    end
  end

  def project
    if payer.is_a?(Project)
      payer
    elsif payee.is_a?(Project)
      payee
    else
      raise 'No project is associated with this transaction'
    end
  end

  def owner
    payer if pledge_for_project?
  end

  def pledge_for_project?
    payer.is_a?(User) && payee.instance_of?(Project)
  end

  def too_few_credits?
    self.payer.credit_bank && (self.payer.credit_bank.current < self.quantity_of_credits)
  end

  def lacking_credits_for_project?
    pledge_for_project? && too_few_credits?
  end

  def mark_reward_distributions_complete!
    reward_distributions(true).each(&:complete!)
  end

  def refund_and_destroy(user)
    fail "Already Refunded with #{refunded_credit_movement_id}" if refunded?
    CreditMovement.transaction do
      reward_distributions.each(&:destroy)
      cm = CreditMovement.create!(payer: payee,
                                  payee: payer,
                                  quantity_of_credits: quantity_of_credits,
                                  comments: "Refund created by #{user.name}")
      project.mailer.delay.refunded_project_email(cm.id, user.id)
      update_attribute(:refunded_credit_movement_id, cm.id)
      destroy_funding_activities
    end
  end

  def non_tax_deductible_amount
    if reward_distributions(true).any?
      total = 0
      reward_distributions.each do |distribution|
        total += distribution.funding_tier.non_tax_deductible
      end
      total
    else
      return 0
    end
  end

  def custom_contributed_amount
    total = 0
    reward_distributions.completed.each do |distribution|
      total += (distribution.funding_tier.try(:dollars) || 0)
    end
    quantity_of_credits - total
  end

  def refunded?
    refunded_credit_movement_id.present?
  end

  def destroy_funding_activities
    Activity.where(user_id: payer_id, project_id: payee_id, action: :funded).map(&:destroy)
  end
end
