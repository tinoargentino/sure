class InvestmentTransaction < ApplicationRecord
  belongs_to :investment
  belongs_to :investment_position, optional: true

  enum :transaction_type, {
    buy: 0,
    sell: 1,
    dividend: 2,
    fee: 3,
    stock_split: 4,
    deposit: 5,
    withdrawal: 6,
    capital_gain: 7,
    tax_withheld: 8,
    interest: 9,
    other: 99
  }

  enum :source, { csv: 0, api: 1, manual: 2 }

  # Mapping from common brokerage transaction codes to our types
  TRANSACTION_TYPE_MAPPINGS = {
    # Standard
    "buy" => :buy,
    "sell" => :sell,
    "dividend" => :dividend,
    "fee" => :fee,
    "stock_split" => :stock_split,
    "deposit" => :deposit,
    "withdrawal" => :withdrawal,
    # Robinhood codes
    "cdiv" => :dividend,        # Cash dividend
    "sdiv" => :dividend,        # Special dividend
    "mdiv" => :dividend,        # Monthly/Mutual fund dividend
    "scap" => :capital_gain,    # Short-term capital gain distribution
    "lcap" => :capital_gain,    # Long-term capital gain distribution
    "dtax" => :tax_withheld,    # Dividend tax withheld
    "int" => :interest,         # Interest earned
    "mint" => :fee,             # Margin interest (it's a cost)
    "spl" => :stock_split,      # Stock split
    "ach" => :deposit,          # ACH transfer (could be withdrawal too, check amount sign)
    "rtp" => :deposit,          # Real-time payment
    # Corporate actions - map to other for manual review
    "mrgs" => :other,           # Merger shares
    "soff" => :other,           # Spin-off
    "spr" => :other,            # Spin-off rights
    "conv" => :other,           # Conversion
    "misc" => :other            # Miscellaneous
  }.freeze

  # Transaction types that represent cash inflows (positive for IRR)
  INFLOW_TYPES = %i[sell dividend capital_gain interest].freeze

  # Transaction types that represent cash outflows (negative for IRR)
  OUTFLOW_TYPES = %i[buy fee tax_withheld].freeze

  # Transaction types with no cash flow
  NO_CASHFLOW_TYPES = %i[stock_split other].freeze

  validates :transaction_date, :amount, presence: true
  validates :ticker, presence: true, unless: proc { |t| t.deposit? || t.withdrawal? }
  validates :external_id, uniqueness: { scope: :investment_id }, allow_nil: true

  before_save :derive_position, if: :should_derive_position?

  scope :for_ticker, ->(ticker) { where(ticker: ticker) }

  # Check if this transaction needs manual review
  def needs_review?
    other?
  end

  # Get the original transaction type if stored in metadata
  def original_type
    metadata&.dig("original_type")
  end

  # Class method to normalize transaction type from various sources
  def self.normalize_transaction_type(raw_type)
    return :other if raw_type.blank?

    normalized = raw_type.to_s.downcase.strip
    TRANSACTION_TYPE_MAPPINGS[normalized] || :other
  end

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
