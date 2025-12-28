class AddBenchmarkTickerToInvestments < ActiveRecord::Migration[7.2]
  def change
    add_column :investments, :benchmark_ticker, :string, default: "SPY"
  end
end
