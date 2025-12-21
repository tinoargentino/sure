require "test_helper"

class InvestmentPositionTest < ActiveSupport::TestCase
  setup do
    @investment = accounts(:investment).accountable
    @position = investment_positions(:vtsax)
  end

  test "validates presence of ticker" do
    position = InvestmentPosition.new(investment: @investment)
    assert_not position.valid?
    assert position.errors[:ticker].present?
  end

  test "validates uniqueness of ticker scoped to investment" do
    dup_position = InvestmentPosition.new(
      investment: @investment,
      ticker: "VTSAX",
      inception_date: 1.day.ago.to_date
    )
    assert_not dup_position.valid?
    assert dup_position.errors[:ticker].present?
  end

  test "calculates current quantity correctly" do
    assert_equal 100, @position.current_quantity
  end

  test "calculates cost basis total" do
    expected = 855000
    assert_equal expected, @position.cost_basis_total
  end

  test "returns cash flows for CAGR calculation" do
    flows = @position.cash_flows
    assert flows.any?
    assert flows.first.key?(:date)
    assert flows.first.key?(:amount)
  end

  test "cagr returns nil if insufficient transactions" do
    empty_position = InvestmentPosition.create!(
      investment: @investment,
      ticker: "EMPTY",
      inception_date: Date.today
    )
    assert_nil empty_position.cagr
  end
end
