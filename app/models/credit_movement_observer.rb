class CreditMovementObserver < ActiveRecord::Observer
  def after_create(credit_movement)
    credit_movement.reward_distributions.map(&:save!)
    credit_movement.complete!
  end

  def after_destroy(credit_movement)
    update_credit_banks(credit_movement)
  end

  def after_complete(cm, transition)
    update_credit_banks(cm)

    if cm.completed? && cm.pledge_for_project?
      cm.mark_reward_distributions_complete!
      Project.delay_until(1.minute.from_now).send_funded_email_to_leaders(cm.payee.id, cm.payer.name, cm.quantity_of_credits, cm.metadata)
      cm.project.mailer.delay_until(1.minute.from_now).confirmation_of_funding_email(cm.payer.email, cm.payer.name, cm.id)
      Project.delay_until(1.minute.from_now).log_activity(cm.payee_id, cm.payer_id, :funded, cm.quantity_of_credits.to_s)
    end
  end

  private

    def update_credit_banks(cm)
      if cm.payer && !cm.payer_type.in?(%w(Adjustment Transaction))
        cm.payer.update_credit_bank!
      end

      if cm.payee && !cm.payee_type.in?(%w(Adjustment Transaction))
        cm.payee.update_credit_bank!
      end
    end
end
