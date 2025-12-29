class Investment < ApplicationRecord
  include Accountable

  # Legacy associations - kept for backward compatibility during migration
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
      last_updated: Time.current
    }
  end

  # Returns positions grouped by security with calculated metrics
  def positions
    return [] unless account

    account.current_holdings.map do |holding|
      PositionPresenter.new(holding, self)
    end
  end

  def total_invested_amount
    return 0 unless account

    # Sum of all buy trades (positive qty = buy)
    account.trades.where("qty > 0").sum("price * qty")
  end

  def total_market_value_amount
    return 0 unless account

    # Use current holdings which already have amount calculated
    account.current_holdings.sum(:amount)
  end

  def portfolio_cagr
    entries = trade_entries
    return nil if entries.empty?

    cash_flows = entries.map do |entry|
      {
        date: entry.date,
        amount: entry.amount  # Entry amount: negative for buys, positive for sells
      }
    end

    ending_value = total_market_value_amount

    InvestmentMetrics::CagrCalculator.calculate(
      cash_flows: cash_flows,
      ending_value: ending_value,
      inception_date: entries.first.date
    )
  end

  def inception_date
    return nil unless account
    account.entries.where(entryable_type: "Trade").minimum(:date)
  end

  def portfolio_benchmark_cagr
    entries = trade_entries
    return nil if entries.empty?

    cash_flows = entries.map do |entry|
      {
        date: entry.date,
        amount: entry.amount
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

  private

    def trade_entries
      return [] unless account
      account.entries.where(entryable_type: "Trade").order(:date)
    end

    # Presenter class to wrap Holding with CAGR calculations
    class PositionPresenter
      attr_reader :holding, :investment

      delegate :ticker, :qty, :amount, :price, :security, to: :holding

      def initialize(holding, investment)
        @holding = holding
        @investment = investment
      end

      def current_quantity
        qty
      end

      def current_market_value
        amount
      end

      def estimated_current_price
        security&.current_price&.amount || price
      end

      def cagr
        return nil unless investment.account

        # Get all trades for this security
        trades_for_security = investment.account.entries
          .joins("INNER JOIN trades ON trades.id = entries.entryable_id AND entries.entryable_type = 'Trade'")
          .where(trades: { security_id: security.id })
          .order(:date)

        return nil if trades_for_security.empty?

        cash_flows = trades_for_security.map do |entry|
          { date: entry.date, amount: entry.amount }
        end

        InvestmentMetrics::CagrCalculator.calculate(
          cash_flows: cash_flows,
          ending_value: amount,
          inception_date: trades_for_security.first.date
        )
      end

      def cagr_percent
        cagr
      end

      def alpha
        position_cagr = cagr
        return nil if position_cagr.nil?

        # Get benchmark return for same cash flows
        trades_for_security = investment.account.entries
          .joins("INNER JOIN trades ON trades.id = entries.entryable_id AND entries.entryable_type = 'Trade'")
          .where(trades: { security_id: security.id })
          .order(:date)

        cash_flows = trades_for_security.map do |entry|
          { date: entry.date, amount: entry.amount }
        end

        benchmark_cagr = InvestmentMetrics::BenchmarkCalculator.calculate_benchmark_return(
          cash_flows: cash_flows,
          benchmark_ticker: investment.benchmark_ticker || "SPY"
        )

        return nil if benchmark_cagr.nil?

        (position_cagr - benchmark_cagr).round(2)
      end

      def inception_date
        return nil unless investment.account

        investment.account.entries
          .joins("INNER JOIN trades ON trades.id = entries.entryable_id AND entries.entryable_type = 'Trade'")
          .where(trades: { security_id: security.id })
          .minimum(:date)
      end

      def investment_transactions
        # For compatibility - return trades as a relation-like object
        investment.account.trades.where(security_id: security.id)
      end
    end
end
