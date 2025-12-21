class InvestmentsController < ApplicationController
  include AccountableResource

  def index
    @accounts = Current.family.accounts.where(accountable_type: "Investment").ordered
  end

  def show
    @account = Current.family.accounts.find(params[:id])
    @investment = @account.accountable
    @positions = @investment.positions_with_cagr
    @portfolio_metrics = @investment.portfolio_metrics
    @recent_transactions = @investment.investment_transactions.order(transaction_date: :desc).limit(10)
  end
end
