class InvestmentImport < Import
  before_validation :set_default_amount_type_strategy

  def import!
    transaction do
      mappings.each(&:create_mappable!)

      # Group rows by investment and ticker to pre-create positions
      positions_cache = {}

      investment_txns = rows.map do |row|
        mapped_investment = if account
          account.accountable
        else
          mapped_account = mappings.accounts.mappable_for(row.account)
          mapped_account.accountable
        end

        raise "Account must be an Investment account" unless mapped_investment.is_a?(Investment)

        # Normalize the transaction type from various brokerage formats
        raw_type = row.transaction_type.to_s
        normalized_type = InvestmentTransaction.normalize_transaction_type(raw_type)

        # Build metadata with original type if it was mapped to "other"
        metadata = {}
        if normalized_type == :other && raw_type.present?
          metadata["original_type"] = raw_type.upcase
        end

        # Determine amount based on transaction type (sign derived from type, not CSV)
        # IRR needs: outflows (buys) negative, inflows (sells/dividends) positive
        amount = derive_amount_from_type(row.amount, normalized_type)

        # Find or create position for this ticker (skip for deposits/withdrawals)
        position = nil
        if row.ticker.present? && !%i[deposit withdrawal].include?(normalized_type)
          cache_key = "#{mapped_investment.id}:#{row.ticker}"
          position = positions_cache[cache_key] ||= mapped_investment.investment_positions.find_or_create_by!(ticker: row.ticker) do |pos|
            pos.inception_date = row.date_iso
          end
        end

        InvestmentTransaction.new(
          investment: mapped_investment,
          investment_position: position,
          ticker: row.ticker,
          transaction_type: normalized_type,
          source: :csv,
          quantity: row.qty,
          price_per_unit: row.price,
          amount: amount,
          transaction_date: row.date_iso,
          currency: row.currency.presence || mapped_investment.account.currency,
          external_id: row.external_id.presence,
          notes: row.notes.presence,
          metadata: metadata.presence
        )
      end

      InvestmentTransaction.import!(investment_txns)

      # Update account balances based on position market values
      update_account_balances(positions_cache.values)
    end
  end

  def update_account_balances(positions)
    # Group positions by investment and update each account's balance
    positions.group_by(&:investment).each do |investment, _|
      account = investment.account
      next unless account

      # Calculate total market value from all positions
      total_value = investment.total_market_value_amount
      account.update!(balance: total_value)
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
end
