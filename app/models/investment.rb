class Investment < ApplicationRecord
  include Accountable

  has_many :investment_positions, dependent: :destroy
  has_many :investment_transactions, dependent: :destroy

  SUBTYPES = {
    "brokerage" => { short: "Brokerage", long: "Brokerage" },
    "pension" => { short: "Pension", long: "Pension" },
    "retirement" => { short: "Retirement", long: "Retirement" },
    "401k" => { short: "401(k)", long: "401(k)" },
    "roth_401k" => { short: "Roth 401(k)", long: "Roth 401(k)" },
    "403b" => { short: "403(b)", long: "403(b)" },
    "tsp" => { short: "TSP", long: "Thrift Savings Plan" },
    "529_plan" => { short: "529 Plan", long: "529 Plan" },
    "hsa" => { short: "HSA", long: "Health Savings Account" },
    "mutual_fund" => { short: "Mutual Fund", long: "Mutual Fund" },
    "ira" => { short: "IRA", long: "Traditional IRA" },
    "roth_ira" => { short: "Roth IRA", long: "Roth IRA" },
    "angel" => { short: "Angel", long: "Angel" }
  }.freeze

  def portfolio_metrics
    {
      total_invested: total_invested_amount,
      total_market_value: total_market_value_amount,
      cagr_percent: portfolio_cagr,
      inception_date: inception_date,
      last_updated: last_calculated_at
    }
  end

  def positions_with_cagr
    investment_positions.order(cagr_percent: :desc)
  end

  def total_invested_amount
    investment_transactions
      .where(transaction_type: [:buy, :deposit])
      .sum(:amount)
      .abs
  end

  def total_market_value_amount
    total_invested_amount
  end

  def portfolio_cagr
    return nil if investment_transactions.empty?

    all_transactions = investment_transactions.order(:transaction_date)
    return nil if all_transactions.length < 2

    cash_flows = all_transactions.map do |txn|
      {
        date: txn.transaction_date,
        amount: txn.amount  # Stored with correct sign: negative for buys, positive for sells
      }
    end

    ending_value = investment_positions.sum { |pos| pos.current_market_value || 0 }

    InvestmentMetrics::CagrCalculator.calculate(
      cash_flows: cash_flows,
      ending_value: ending_value,
      inception_date: all_transactions.first.transaction_date
    )
  end

  def inception_date
    investment_transactions.order(:transaction_date).first&.transaction_date
  end

  def last_calculated_at
    investment_positions.maximum(:cagr_calculated_at) || Time.current
  end

  def portfolio_benchmark_cagr
    return nil if investment_transactions.empty?

    all_transactions = investment_transactions.order(:transaction_date)
    return nil if all_transactions.length < 2

    cash_flows = all_transactions.map do |txn|
      {
        date: txn.transaction_date,
        amount: txn.amount  # Stored with correct sign: negative for buys, positive for sells
      }
    end

    InvestmentMetrics::BenchmarkCalculator.calculate_benchmark_return(
      cash_flows: cash_flows,
      benchmark_ticker: benchmark_ticker || "SPY"
    )
  end

  def portfolio_alpha
    cagr = portfolio_cagr
    benchmark = portfolio_benchmark_cagr

    return nil if cagr.nil? || benchmark.nil?

    (cagr - benchmark).round(2)
  end

  def benchmark_ticker_display
    benchmark_ticker || "SPY"
  end

  class << self
    def color
      "#1570EF"
    end

    def classification
      "asset"
    end

    def icon
      "chart-line"
    end
  end
end
