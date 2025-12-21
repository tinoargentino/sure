require "test_helper"

class InvestmentTransactionTest < ActiveSupport::TestCase
  setup do
    @investment = accounts(:investment).accountable
    @position = investment_positions(:vtsax)
    @transaction = investment_transactions(:vtsax_buy)
  end

  test "validates presence of transaction date" do
    txn = InvestmentTransaction.new(investment: @investment)
    assert_not txn.valid?
    assert txn.errors[:transaction_date].present?
  end

  test "validates presence of amount" do
    txn = InvestmentTransaction.new(
      investment: @investment,
      transaction_date: Date.today
    )
    assert_not txn.valid?
    assert txn.errors[:amount].present?
  end

  test "validates presence of ticker for buy transactions" do
    txn = InvestmentTransaction.new(
      investment: @investment,
      transaction_date: Date.today,
      amount: 1000,
      transaction_type: :buy
    )
    assert_not txn.valid?
    assert txn.errors[:ticker].present?
  end

  test "allows null ticker for deposit transactions" do
    txn = InvestmentTransaction.new(
      investment: @investment,
      transaction_date: Date.today,
      amount: 1000,
      transaction_type: :deposit
    )
    assert txn.valid?
  end

  test "derives position from ticker on save" do
    txn = InvestmentTransaction.new(
      investment: @investment,
      transaction_date: 1.day.ago.to_date,
      amount: 5000,
      transaction_type: :buy,
      ticker: "NEWSTOCK",
      quantity: 10,
      price_per_unit: 500,
      source: :csv,
      currency: "USD"
    )

    assert_difference "InvestmentPosition.count", 1 do
      txn.save!
    end

    assert_equal "NEWSTOCK", txn.investment_position.ticker
  end

  test "scopes transactions by ticker" do
    aapl_txns = InvestmentTransaction.for_ticker("AAPL")
    assert aapl_txns.any? { |t| t.ticker == "AAPL" }
  end

  test "enums are set correctly" do
    assert_equal 0, InvestmentTransaction.transaction_types[:buy]
    assert_equal 1, InvestmentTransaction.transaction_types[:sell]
    assert_equal 2, InvestmentTransaction.transaction_types[:dividend]
  end
end
