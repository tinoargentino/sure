require "test_helper"

class InvestmentImportTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @investment_account = accounts(:investment)
    @import = InvestmentImport.new(
      family: @family,
      account: @investment_account,
      col_sep: ",",
      number_format: "1,234.56"
    )
  end

  test "validates inclusion of type" do
    assert InvestmentImport::TYPES.include?("InvestmentImport")
  end

  test "defines required columns" do
    required = @import.required_column_keys
    assert_includes required, :date
    assert_includes required, :transaction_type
    assert_includes required, :amount
  end

  test "defines column keys" do
    columns = @import.column_keys
    assert_includes columns, :date
    assert_includes columns, :ticker
    assert_includes columns, :transaction_type
    assert_includes columns, :quantity
    assert_includes columns, :price
    assert_includes columns, :amount
    assert_includes columns, :currency
    assert_includes columns, :external_id
    assert_includes columns, :notes
  end

  test "includes account column when no account specified" do
    import = InvestmentImport.new(family: @family)
    assert_includes import.column_keys, :account
  end

  test "excludes account column when account specified" do
    assert_not_includes @import.column_keys, :account
  end

  test "defines mapping steps" do
    import_without_account = InvestmentImport.new(family: @family)
    mapping_steps = import_without_account.mapping_steps
    assert_includes mapping_steps, Import::AccountMapping
  end

  test "defines mapping steps without account when specified" do
    mapping_steps = @import.mapping_steps
    assert_empty mapping_steps
  end

  test "provides CSV template" do
    template = @import.csv_template
    assert_not_nil template
    assert template.headers.include?("date")
    assert template.headers.include?("transaction_type")
    assert template.first.count.positive?
  end

  test "provides dry run summary" do
    @import.raw_file_str = "date,ticker,transaction_type,quantity,price,amount,currency\n2024-01-15,AAPL,BUY,10,150,-1500,USD"
    summary = @import.dry_run
    assert_key summary, :transactions
  end
end
