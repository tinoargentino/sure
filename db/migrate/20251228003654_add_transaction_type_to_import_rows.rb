class AddTransactionTypeToImportRows < ActiveRecord::Migration[7.2]
  def change
    add_column :import_rows, :transaction_type, :string
    add_column :import_rows, :external_id, :string
  end
end
