class CreateInvestmentPositions < ActiveRecord::Migration[7.2]
  def change
    create_table :investment_positions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :investment_id, null: false
      t.string :ticker, null: false
      t.date :inception_date, null: false
      t.decimal :cagr_percent, precision: 10, scale: 2
      t.datetime :cagr_calculated_at

      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :investment_positions, [:investment_id, :ticker], unique: true
    add_foreign_key :investment_positions, :investments, column: :investment_id
  end
end
