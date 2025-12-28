class CreateInvestmentTransactions < ActiveRecord::Migration[7.2]
  def change
    create_table :investment_transactions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :investment_id, null: false
      t.uuid :investment_position_id
      t.integer :transaction_type, null: false
      t.integer :source, default: 0, null: false

      t.string :ticker
      t.decimal :quantity, precision: 19, scale: 8
      t.decimal :price_per_unit, precision: 19, scale: 8
      t.bigint :amount, null: false

      t.date :transaction_date, null: false
      t.string :external_id
      t.string :currency, null: false

      t.text :notes

      t.timestamps
    end

    add_index :investment_transactions, [:investment_id, :transaction_date]
    add_index :investment_transactions, [:investment_position_id]
    add_index :investment_transactions, [:investment_id, :external_id], unique: true, where: "external_id IS NOT NULL"
    add_foreign_key :investment_transactions, :investments, column: :investment_id
    add_foreign_key :investment_transactions, :investment_positions, column: :investment_position_id
  end
end
