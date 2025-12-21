require "test_helper"

class InvestmentMetrics::CAGRCalculatorTest < ActiveSupport::TestCase
  test "returns nil if less than 2 cash flows" do
    cagr = InvestmentMetrics::CAGRCalculator.calculate(
      cash_flows: [{ date: Date.today, amount: -1000 }],
      ending_value: 1100,
      inception_date: Date.today
    )
    assert_nil cagr
  end

  test "returns nil if time period less than 3.6 days" do
    start_date = Date.today
    end_date = start_date + 2.days

    cagr = InvestmentMetrics::CAGRCalculator.calculate(
      cash_flows: [
        { date: start_date, amount: -1000 },
        { date: end_date, amount: 0 }
      ],
      ending_value: 1100,
      inception_date: start_date,
      current_date: end_date
    )
    assert_nil cagr
  end

  test "returns nil if inception date is after current date" do
    cagr = InvestmentMetrics::CAGRCalculator.calculate(
      cash_flows: [
        { date: Date.today, amount: -1000 },
        { date: Date.today + 365.days, amount: 0 }
      ],
      ending_value: 1100,
      inception_date: Date.today + 1.year,
      current_date: Date.today
    )
    assert_nil cagr
  end

  test "calculates positive CAGR for profitable investment" do
    # Invest $1000, it grows to $1210 in 1 year (10% return)
    inception = Date.new(2024, 1, 1)
    current = Date.new(2025, 1, 1)

    cagr = InvestmentMetrics::CAGRCalculator.calculate(
      cash_flows: [{ date: inception, amount: -1000 }],
      ending_value: 1100,
      inception_date: inception,
      current_date: current
    )

    assert_not_nil cagr
    assert cagr > 0
  end

  test "calculates negative CAGR for loss" do
    inception = Date.new(2024, 1, 1)
    current = Date.new(2025, 1, 1)

    cagr = InvestmentMetrics::CAGRCalculator.calculate(
      cash_flows: [{ date: inception, amount: -1000 }],
      ending_value: 800,
      inception_date: inception,
      current_date: current
    )

    assert_not_nil cagr
    assert cagr < 0
  end

  test "handles multiple irregular cash flows" do
    inception = Date.new(2024, 1, 1)
    current = Date.new(2026, 1, 1)

    cagr = InvestmentMetrics::CAGRCalculator.calculate(
      cash_flows: [
        { date: Date.new(2024, 1, 1), amount: -5000 },
        { date: Date.new(2024, 6, 1), amount: -2500 },
        { date: Date.new(2025, 1, 1), amount: -1000 }
      ],
      ending_value: 10000,
      inception_date: inception,
      current_date: current
    )

    assert_not_nil cagr
  end

  test "rounds CAGR to 2 decimal places" do
    inception = Date.new(2024, 1, 1)
    current = Date.new(2025, 1, 1)

    cagr = InvestmentMetrics::CAGRCalculator.calculate(
      cash_flows: [{ date: inception, amount: -1000 }],
      ending_value: 1099,
      inception_date: inception,
      current_date: current
    )

    assert_not_nil cagr
    assert_equal cagr, cagr.round(2)
  end

  test "handles zero ending value" do
    inception = Date.new(2024, 1, 1)
    current = Date.new(2025, 1, 1)

    cagr = InvestmentMetrics::CAGRCalculator.calculate(
      cash_flows: [{ date: inception, amount: -1000 }],
      ending_value: 0,
      inception_date: inception,
      current_date: current
    )

    assert_not_nil cagr
    assert cagr < 0
  end

  test "handles large return percentages" do
    inception = Date.new(2024, 1, 1)
    current = Date.new(2025, 1, 1)

    cagr = InvestmentMetrics::CAGRCalculator.calculate(
      cash_flows: [{ date: inception, amount: -1000 }],
      ending_value: 5000,
      inception_date: inception,
      current_date: current
    )

    assert_not_nil cagr
    assert cagr > 400  # Should be around 400% for 5x return in 1 year
  end
end
