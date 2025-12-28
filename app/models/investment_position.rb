class InvestmentPosition < ApplicationRecord
  belongs_to :investment
  has_many :investment_transactions, dependent: :restrict_with_error

  validates :ticker, presence: true, uniqueness: { scope: :investment_id }
  validates :investment_id, presence: true

  def cash_flows
    # For IRR calculation:
    # - Investments (money out) should be NEGATIVE
    # - Returns (dividends, sells) should be POSITIVE
    # - Stock splits have NO cash flow (amount = 0), so they don't affect IRR
    #
    # Amounts are stored with correct sign: negative for buys, positive for sells/dividends
    investment_transactions.order(:transaction_date).map do |txn|
      {
        date: txn.transaction_date,
        amount: txn.amount
      }
    end
  end

  def cagr
    return nil if investment_transactions.empty?

    txns = investment_transactions.order(:transaction_date)

    flows = cash_flows
    ending_value = current_market_value || 0

    InvestmentMetrics::CagrCalculator.calculate(
      cash_flows: flows,
      ending_value: ending_value,
      inception_date: txns.first.transaction_date
    )
  end

  def current_quantity
    buys = investment_transactions.where(transaction_type: :buy).sum(:quantity) || 0
    sells = investment_transactions.where(transaction_type: :sell).sum(:quantity) || 0
    # Stock splits add shares (positive qty for regular split, negative for reverse split)
    splits = investment_transactions.where(transaction_type: :stock_split).sum(:quantity) || 0
    buys + splits - sells
  end

  def cost_basis_total
    buy_txns = investment_transactions.where(transaction_type: :buy)
    buy_txns.sum(:amount).abs
  end

  def current_market_value
    qty = current_quantity
    return 0 if qty.nil? || qty <= 0

    # Get estimated current price based on last purchase price
    # In production, this would fetch from Security/SecurityPrice
    estimated_price = estimated_current_price
    return 0 if estimated_price.nil? || estimated_price <= 0

    qty * estimated_price
  end

  def estimated_current_price
    # TODO: Integrate with real-time price API (Yahoo Finance, Alpha Vantage, etc.)
    # For now, use manually maintained prices for testing/development
    current_prices = {
      "TSLA" => 475.19,
      "GOOGL" => 313.51,
      "AAPL" => 273.40,
      "MSFT" => 487.71,
      "VTI" => 339.67
    }

    current_prices[ticker]
  end

  def recalculate_cagr
    new_cagr = cagr
    update(cagr_percent: new_cagr, cagr_calculated_at: Time.current)
  end

  def benchmark_cagr
    return nil if investment_transactions.empty?

    InvestmentMetrics::BenchmarkCalculator.calculate_benchmark_return(
      cash_flows: cash_flows,
      benchmark_ticker: investment.benchmark_ticker || "SPY"
    )
  end

  def alpha
    position_cagr = cagr
    spy_cagr = benchmark_cagr

    return nil if position_cagr.nil? || spy_cagr.nil?

    (position_cagr - spy_cagr).round(2)
  end

  # Record a stock split
  # split_ratio: e.g., "4:1" means 4 new shares for every 1 old share
  # For a 4:1 split, you receive 3 additional shares per share owned
  # For a reverse 1:4 split, you lose 3 shares per 4 shares owned
  def record_split(split_ratio:, split_date:)
    parts = split_ratio.to_s.split(":")
    return nil unless parts.length == 2

    new_shares = parts[0].to_f
    old_shares = parts[1].to_f
    return nil if old_shares <= 0

    # Calculate shares before the split
    shares_before_split = shares_on_date(split_date - 1.day)
    return nil if shares_before_split <= 0

    # Calculate additional shares from split
    # For 4:1 split: multiplier = 4, so you get (4-1) = 3 extra shares per share
    # For 1:4 reverse split: multiplier = 0.25, so you lose (1-0.25) = 0.75 shares per share
    multiplier = new_shares / old_shares
    additional_shares = shares_before_split * (multiplier - 1)

    investment_transactions.create!(
      investment: investment,
      ticker: ticker,
      transaction_type: :stock_split,
      quantity: additional_shares.round(4),
      price_per_unit: 0,
      amount: 0,
      transaction_date: split_date,
      currency: investment.account.currency,
      source: :manual
    )
  end

  # Calculate shares held on a specific date
  def shares_on_date(date)
    buys = investment_transactions.where(transaction_type: :buy).where("transaction_date <= ?", date).sum(:quantity) || 0
    sells = investment_transactions.where(transaction_type: :sell).where("transaction_date <= ?", date).sum(:quantity) || 0
    splits = investment_transactions.where(transaction_type: :stock_split).where("transaction_date <= ?", date).sum(:quantity) || 0
    buys + splits - sells
  end
end
