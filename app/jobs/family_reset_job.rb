class FamilyResetJob < ApplicationJob
  queue_as :low_priority

  def perform(family, load_sample_data_for_email: nil)
    # Delete all family data except users
    ActiveRecord::Base.transaction do
      # Delete investment transactions first (positions have restrict_with_error)
      investment_ids = family.accounts.where(accountable_type: "Investment").pluck(:accountable_id)
      InvestmentTransaction.where(investment_id: investment_ids).delete_all

      # Delete accounts and related data
      family.accounts.destroy_all
      family.categories.destroy_all
      family.tags.destroy_all
      family.merchants.destroy_all
      family.plaid_items.destroy_all
      family.imports.destroy_all
      family.budgets.destroy_all
    end

    if load_sample_data_for_email.present?
      Demo::Generator.new.generate_new_user_data_for!(family.reload, email: load_sample_data_for_email)
    else
      family.sync_later
    end
  end
end
