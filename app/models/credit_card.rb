class CreditCard < Transaction
  class CreditCardProcessingError < StandardError; end;

  attr_accessor :first_name,
                :last_name,
                :card_number,
                :ccv,
                :expire_month,
                :expire_year,
                :street1,
                :street2,
                :city,
                :state,
                :country,
                :postal_code,
                :store_address,
                :request_uri

  include LocationBehavior

  validates_presence_of :first_name,
                        :last_name,
                        :card_number,
                        :ccv,
                        :expire_month,
                        :expire_year,
                        :street1,
                        :city
  validates_presence_of :state,       :if => :usa_or_canada?
  validates_presence_of :country
  validates_presence_of :postal_code, :if => :usa_or_canada?
  validates_numericality_of :card_number, :ccv
  validate :country_not_equal_to_india #fraud issues

  def country_not_equal_to_india
    errors.add(:base, "There was a problem processing your card.") if country == "India"
  end

  before_create :set_income_to_quantity_of_credits
  before_create :set_card_type
  before_create :store_address_if_indicated

  before_validation :strip_out_space_from_card_number

  def credit_card_type
    card_number = self.card_number
    case card_number
      when /^4\d{12}(\d{3})?$/ then return "VISA"
      when /^3[47]\d{13}$/ then return "AMEX"
      when /^5\d{15}|36\d{14}$/ then return "MC"
      when /^6011\d{12}|650\d{13}$/ then return "DISC"
      else return "UNKNOWN"
    end
  end

  private

    def set_income_to_quantity_of_credits
      raise 'Credit movement is not set' if credit_movement.nil?
      self.income = self.quantity_of_credits = credit_movement.quantity_of_credits
    end

    def set_card_type
      self.card_type = credit_card_type
    end

    def store_address_if_indicated
      if store_address
        ma = user.mailing_address || user.build_mailing_address
        ma.address_1 = street1
        ma.city = city
        ma.state = state
        ma.postal_code = postal_code
        ma.country = country
        ma.save!
      end
    end

    # note: a failed transaction still results in the creation of a
    # transaction record (but with a 'failed' status), however, the other
    # callbacks (see Transaction.rb) do not fire
    def process_payment
      unless PaymentGateway.get(self).charge_card
        errors[:base] << self.payment_response
      end
    end

    def strip_out_space_from_card_number
      self.card_number.gsub!(' ', '') if self.card_number
    end
end
