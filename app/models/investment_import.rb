class InvestmentImport < Import
  before_validation :set_default_amount_type_strategy

  def import!
    transaction do
      mappings.each(&:create_mappable!)

      trades = []
      skipped_rows = []

      rows.each do |row|
        mapped_account = if account
          account
        else
          mappings.accounts.mappable_for(row.account)
        end

        raise "Account must be an Investment account" unless mapped_account.investment?

        # Normalize the transaction type from various brokerage formats
        raw_type = row.transaction_type.to_s
        normalized_type = normalize_transaction_type(raw_type)

        # Only create trades for buy/sell - skip dividends, fees, etc. for now
        unless %i[buy sell].include?(normalized_type)
          skipped_rows << { row: row, type: normalized_type, reason: "Only buy/sell supported" }
          next
        end

        # Skip rows without ticker
        unless row.ticker.present?
          skipped_rows << { row: row, type: normalized_type, reason: "No ticker" }
          next
        end

        # Find or create security
        security = find_or_create_security(ticker: row.ticker)
        next unless security

        # Determine qty sign: positive for buy, negative for sell
        qty = row.qty.to_d.abs
        qty = -qty if normalized_type == :sell

        # Price should always be positive
        price = row.price.to_d.abs

        # Amount: negative for buys (money out), positive for sells (money in)
        amount = derive_amount_from_type(row.amount, normalized_type)

        # Build trade name
        name = Trade.build_name(normalized_type.to_s, qty, row.ticker)

        trades << Trade.new(
          security: security,
          qty: qty,
          price: price,
          currency: row.currency.presence || mapped_account.currency,
          entry: Entry.new(
            account: mapped_account,
            date: row.date_iso,
            amount: amount,
            name: name,
            currency: row.currency.presence || mapped_account.currency,
            import: self
          )
        )
      end

      Trade.import!(trades, recursive: true) if trades.any?

      # Sync each account to update holdings and balances
      sync_accounts(trades)

      # Log skipped rows for debugging
      if skipped_rows.any?
        Rails.logger.info "InvestmentImport: Skipped #{skipped_rows.count} rows (dividends, fees, etc.)"
      end
    end
  end

  def sync_accounts(trades)
    # Get unique accounts and trigger sync to update holdings
    accounts = trades.map { |t| t.entry.account }.uniq
    accounts.each do |acct|
      acct.sync_later
    end
  end

  def mapping_steps
    base = []
    base << Import::AccountMapping if account.nil?
    base
  end

  def required_column_keys
    # Note: amount is NOT required - stock splits and other types have no cash flow
    # For splits, quantity is the key field (shares awarded)
    %i[date transaction_type]
  end

  def column_keys
    base = %i[date ticker transaction_type qty price amount currency external_id notes]
    base.unshift(:account) if account.nil?
    base
  end

  def dry_run
    mappings = { transactions: rows.count }

    mappings.merge(
      accounts: Import::AccountMapping.for_import(self).creational.count
    ) if account.nil?

    mappings
  end

  def csv_template
    # Amount signs are derived from transaction_type, so amounts can be positive or negative
    # The system uses absolute value and applies correct sign based on type
    template = <<-CSV
      date*,ticker,transaction_type*,quantity,price,amount,currency,external_id,notes,account
      2024-01-15,VTSAX,BUY,100,85.50,8550.00,USD,,Vanguard Total Stock Market Fund,My Brokerage
      2024-03-10,AAPL,BUY,10,175.00,1750.00,USD,,Apple Inc. shares,My Brokerage
      2024-06-20,AAPL,SELL,5,195.00,975.00,USD,,Partial sale,My Brokerage
      2024-07-15,GOOGL,SPL,190,,,USD,,20:1 stock split (190 shares awarded),My Brokerage
      2024-12-15,VTSAX,DIVIDEND,,,123.45,USD,,Annual dividend,My Brokerage
      2024-12-20,VTSAX,SCAP,,,50.00,USD,,Short-term capital gain distribution,My Brokerage
    CSV

    csv = CSV.parse(template, headers: true)
    csv.delete("account") if account.present?
    csv
  end

  def generate_rows_from_csv
    rows.destroy_all

    mapped_rows = csv_rows.map do |row|
      {
        account: row[account_col_label].to_s,
        date: row[date_col_label].to_s,
        ticker: row[ticker_col_label].to_s,
        transaction_type: row[transaction_type_col_label].to_s,
        qty: sanitize_number(row[qty_col_label]).to_s,
        price: sanitize_number(row[price_col_label]).to_s,
        amount: sanitize_number(row[amount_col_label]).to_s,
        currency: (row[currency_col_label] || default_currency).to_s,
        external_id: row[external_id_col_label].to_s,
        notes: row[notes_col_label].to_s
      }
    end

    rows.insert_all!(mapped_rows)
  end

  private

    # Derive amount sign from transaction type (not from CSV convention)
    # IRR calculation needs: outflows negative, inflows positive
    def derive_amount_from_type(raw_amount, transaction_type)
      return 0 if raw_amount.blank?

      abs_amount = raw_amount.to_d.abs

      case transaction_type
      when :buy, :deposit
        -abs_amount  # Outflow: money you paid
      when :sell, :dividend, :withdrawal
        abs_amount   # Inflow: money you received
      when :stock_split, :other
        0            # No cash flow
      else
        -abs_amount  # Default to outflow for unknown types
      end
    end

    def set_default_amount_type_strategy
      self.amount_type_strategy ||= "signed_amount"
    end

    # Maps various brokerage transaction type formats to standardized symbols
    # Robinhood: CDIV (cash dividend), SCAP (short-term cap gain), SPL (split), etc.
    # Generic: BUY, SELL, DIVIDEND, SPLIT, etc.
    def normalize_transaction_type(raw_type)
      return :other if raw_type.blank?

      case raw_type.to_s.upcase.strip
      when "BUY", "BOUGHT", "PURCHASE", "ACH", "DEPOSIT"
        :buy
      when "SELL", "SOLD", "SALE"
        :sell
      when "DIVIDEND", "DIV", "CDIV", "QUALIFIED DIVIDEND", "ORDINARY DIVIDEND"
        :dividend
      when "SPLIT", "SPL", "STOCK SPLIT", "REVERSE SPLIT"
        :stock_split
      when "SCAP", "SHORT-TERM CAPITAL GAIN", "SHORT TERM CAPITAL GAIN", "STCG"
        :capital_gain
      when "LCAP", "LONG-TERM CAPITAL GAIN", "LONG TERM CAPITAL GAIN", "LTCG"
        :capital_gain
      when "FEE", "FEES", "COMMISSION"
        :fee
      when "INTEREST", "INT"
        :interest
      when "TAX", "TAX WITHHELD", "WITHHOLDING"
        :tax_withheld
      when "TRANSFER IN", "JOURNAL", "ACAT"
        :deposit
      when "TRANSFER OUT", "WITHDRAWAL"
        :withdrawal
      else
        :other
      end
    end

    def find_or_create_security(ticker:)
      return nil unless ticker.present?

      # Avoids resolving the same security over and over again (resolver potentially makes network calls)
      @security_cache ||= {}

      cache_key = ticker.upcase.strip

      security = @security_cache[cache_key]

      return security if security.present?

      security = Security::Resolver.new(cache_key).resolve

      @security_cache[cache_key] = security

      security
    end
end
