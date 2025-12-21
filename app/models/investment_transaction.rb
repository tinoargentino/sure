class InvestmentTransaction < ApplicationRecord
  belongs_to :investment
  belongs_to :investment_position, optional: true

  enum transaction_type: {
    buy: 0,
    sell: 1,
    dividend: 2,
    fee: 3,
    split: 4,
    deposit: 5,
    withdrawal: 6
  }

  enum source: { csv: 0, api: 1, manual: 2 }

  validates :transaction_date, :amount, presence: true
  validates :ticker, presence: true, unless: proc { |t| t.deposit? || t.withdrawal? }
  validates :external_id, uniqueness: { scope: :investment_id }, allow_nil: true

  before_save :derive_position, if: :should_derive_position?

  scope :for_ticker, ->(ticker) { where(ticker: ticker) }

  private

  def should_derive_position?
    ticker.present? && investment_position_id.blank? && !deposit? && !withdrawal?
  end

  def derive_position
    self.investment_position = investment.investment_positions.find_or_create_by(ticker: ticker) do |pos|
      pos.inception_date = transaction_date
    end
  end
end
