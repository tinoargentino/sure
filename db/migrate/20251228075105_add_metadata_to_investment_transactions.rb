class AddMetadataToInvestmentTransactions < ActiveRecord::Migration[7.2]
  def change
    add_column :investment_transactions, :metadata, :jsonb
  end
end
