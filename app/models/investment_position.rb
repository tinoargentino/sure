class InvestmentPosition < ApplicationRecord
  belongs_to :investment
  has_many :investment_transactions, dependent: :restrict_with_error

  validates :ticker, presence: true, uniqueness: { scope: :investment_id }
  validates :investment_id, presence: true

  def cash_flows
    investment_transactions.order(:transaction_date).map do |txn|
      {
        date: txn.transaction_date,
        amount: -txn.amount
      }
    end
  end

  def cagr
    return nil if investment_transactions.empty?

    txns = investment_transactions.order(:transaction_date)
    return nil if txns.length < 2

    flows = cash_flows
    ending_value = current_market_value || 0

    InvestmentMetrics::CAGRCalculator.calculate(
      cash_flows: flows,
      ending_value: ending_value,
      inception_date: txns.first.transaction_date
    )
  end

  def current_quantity
    buys = investment_transactions.where(transaction_type: :buy).sum(:quantity) || 0
    sells = investment_transactions.where(transaction_type: :sell).sum(:quantity) || 0
    buys - sells
  end

  def cost_basis_total
    buy_txns = investment_transactions.where(transaction_type: :buy)
    buy_txns.sum(:amount).abs
  end

  def current_market_value
    0
  end

  def recalculate_cagr
    new_cagr = cagr
    update(cagr_percent: new_cagr, cagr_calculated_at: Time.current)
  end
end
