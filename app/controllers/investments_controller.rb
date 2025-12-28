class InvestmentsController < ApplicationController
  include AccountableResource

  def index
    @accounts = Current.family.accounts.where(accountable_type: "Investment").alphabetically
  end

  def show
    @account = Current.family.accounts.find(params[:id])
    @investment = @account.accountable
    @positions = @investment.positions_with_cagr
    @portfolio_metrics = @investment.portfolio_metrics
    @recent_transactions = @investment.investment_transactions.order(transaction_date: :desc).limit(10)
  end

  def update_benchmark
    @account = Current.family.accounts.find(params[:id])
    @investment = @account.accountable

    benchmark = params[:benchmark_ticker].to_s.upcase.strip

    if InvestmentMetrics::BenchmarkCalculator.supported_benchmarks.include?(benchmark)
      @investment.update(benchmark_ticker: benchmark)
      redirect_to investment_path(@account), notice: "Benchmark updated to #{benchmark}"
    else
      supported = InvestmentMetrics::BenchmarkCalculator.supported_benchmarks.join(", ")
      redirect_to investment_path(@account), alert: "Unsupported benchmark. Supported: #{supported}"
    end
  end
end
