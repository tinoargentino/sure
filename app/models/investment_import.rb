class InvestmentImport < Import
  def import!
    transaction do
      mappings.each(&:create_mappable!)

      investment_txns = rows.map do |row|
        mapped_investment = if account
          account.accountable
        else
          mapped_account = mappings.accounts.mappable_for(row.account)
          mapped_account.accountable
        end

        raise "Account must be an Investment account" unless mapped_investment.is_a?(Investment)

        InvestmentTransaction.new(
          investment: mapped_investment,
          ticker: row.ticker,
          transaction_type: row.transaction_type,
          source: :csv,
          quantity: row.quantity,
          price_per_unit: row.price,
          amount: row.signed_amount,
          transaction_date: row.date_iso,
          currency: row.currency.presence || mapped_investment.account.currency,
          external_id: row.external_id,
          notes: row.notes
        )
      end

      InvestmentTransaction.import!(investment_txns)
    end
  end

  def mapping_steps
    base = []
    base << Import::AccountMapping if account.nil?
    base
  end

  def required_column_keys
    %i[date transaction_type amount]
  end

  def column_keys
    base = %i[date ticker transaction_type quantity price amount currency external_id notes]
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
    template = <<-CSV
      date*,ticker,transaction_type*,quantity,price,amount*,currency,external_id,notes,account
      2024-01-15,VTSAX,BUY,100,85.50,-8550.00,USD,,Vanguard Total Stock Market Fund,My Brokerage
      2024-03-10,AAPL,BUY,10,175.00,-1750.00,USD,,Apple Inc. shares,My Brokerage
      2024-06-20,AAPL,SELL,5,195.00,975.00,USD,,Partial sale,My Brokerage
      2024-12-15,VTSAX,DIVIDEND,,,123.45,USD,,Annual dividend,My Brokerage
    CSV

    csv = CSV.parse(template, headers: true)
    csv.delete("account") if account.present?
    csv
  end

  private

  def generate_rows_from_csv
    rows.destroy_all

    mapped_rows = csv_rows.map do |row|
      {
        account: row[account_col_label].to_s,
        date: row[date_col_label].to_s,
        ticker: row[ticker_col_label].to_s,
        transaction_type: row[transaction_type_col_label].to_s,
        quantity: sanitize_number(row[qty_col_label]).to_s,
        price: sanitize_number(row[price_col_label]).to_s,
        amount: sanitize_number(row[amount_col_label]).to_s,
        currency: (row[currency_col_label] || default_currency).to_s,
        external_id: row[external_id_col_label].to_s,
        notes: row[notes_col_label].to_s
      }
    end

    rows.insert_all!(mapped_rows)
  end
end
