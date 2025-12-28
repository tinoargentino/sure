module InvestmentMetrics
  class CagrCalculator
    def self.calculate(cash_flows:, ending_value:, inception_date:, current_date: Date.today)
      calc = new(cash_flows, ending_value, inception_date, current_date)
      calc.cagr
    end

    def initialize(cash_flows, ending_value, inception_date, current_date)
      @cash_flows = cash_flows.sort_by { |cf| cf[:date] }
      @ending_value = ending_value.to_f
      @inception_date = inception_date
      @current_date = current_date
    end

    def cagr
      return nil if invalid?

      irr = solve_irr
      irr ? (irr * 100).round(2) : nil
    end

    private

    def invalid?
      @cash_flows.length < 2 ||
        years < 0.01 ||
        @inception_date > @current_date
    end

    def years
      (@current_date - @inception_date).to_i / 365.25
    end

    def solve_irr
      newton_raphson_irr || bisection_irr
    end

    def newton_raphson_irr
      max_iterations = 100
      tolerance = 1e-6
      r = 0.1

      max_iterations.times do |_iteration|
        npv_value = npv(r)

        return r if npv_value.abs < tolerance

        npv_derivative = npv_derivative(r)
        return nil if npv_derivative.abs < 1e-10

        r_new = r - (npv_value / npv_derivative)

        return r_new if (r_new - r).abs < tolerance

        r = r_new
      end

      nil
    end

    def bisection_irr
      tolerance = 1e-6
      max_iterations = 100

      lower = -0.99
      upper = 10.0

      return nil if npv(lower) * npv(upper) > 0

      max_iterations.times do
        mid = (lower + upper) / 2.0
        npv_mid = npv(mid)

        return mid if npv_mid.abs < tolerance

        if npv(lower) * npv_mid < 0
          upper = mid
        else
          lower = mid
        end

        return mid if (upper - lower).abs < tolerance
      end

      (lower + upper) / 2.0
    end

    def npv(rate)
      @cash_flows.sum do |cf|
        years_from_inception = (cf[:date] - @inception_date).to_i / 365.25
        cf[:amount] / ((1 + rate) ** years_from_inception)
      end + (@ending_value / ((1 + rate) ** years))
    end

    def npv_derivative(rate)
      h = 1e-5
      (npv(rate + h) - npv(rate - h)) / (2 * h)
    end
  end
end
