module InvestmentMetrics
  class BenchmarkCalculator
    # Historical prices for common benchmark ETFs (approximate monthly close prices)
    # TODO: Integrate with price API for real-time and historical data
    BENCHMARK_PRICES = {
      "SPY" => {
        "2023-01-01" => 384.0, "2023-02-01" => 403.0, "2023-03-01" => 407.0,
        "2023-04-01" => 409.0, "2023-05-01" => 416.0, "2023-06-01" => 429.0,
        "2023-07-01" => 451.0, "2023-08-01" => 452.0, "2023-09-01" => 437.0,
        "2023-10-01" => 426.0, "2023-11-01" => 449.0, "2023-12-01" => 467.0,
        "2024-01-01" => 472.0, "2024-02-01" => 497.0, "2024-03-01" => 512.0,
        "2024-04-01" => 506.0, "2024-05-01" => 524.0, "2024-06-01" => 545.0,
        "2024-07-01" => 551.0, "2024-08-01" => 554.0, "2024-09-01" => 568.0,
        "2024-10-01" => 575.0, "2024-11-01" => 590.0, "2024-12-01" => 600.0,
        "2025-01-01" => 605.0, "2025-02-01" => 610.0, "2025-03-01" => 615.0,
        "2025-04-01" => 620.0, "2025-05-01" => 628.0, "2025-06-01" => 635.0,
        "2025-07-01" => 642.0, "2025-08-01" => 650.0, "2025-09-01" => 655.0,
        "2025-10-01" => 662.0, "2025-11-01" => 670.0, "2025-12-01" => 675.0,
        "current" => 594.50
      },
      "QQQ" => {
        "2023-01-01" => 270.0, "2023-02-01" => 295.0, "2023-03-01" => 310.0,
        "2023-04-01" => 320.0, "2023-05-01" => 340.0, "2023-06-01" => 365.0,
        "2023-07-01" => 380.0, "2023-08-01" => 375.0, "2023-09-01" => 360.0,
        "2023-10-01" => 355.0, "2023-11-01" => 385.0, "2023-12-01" => 405.0,
        "2024-01-01" => 410.0, "2024-02-01" => 435.0, "2024-03-01" => 445.0,
        "2024-04-01" => 430.0, "2024-05-01" => 455.0, "2024-06-01" => 480.0,
        "2024-07-01" => 490.0, "2024-08-01" => 475.0, "2024-09-01" => 485.0,
        "2024-10-01" => 495.0, "2024-11-01" => 510.0, "2024-12-01" => 525.0,
        "2025-01-01" => 530.0, "2025-02-01" => 535.0, "2025-03-01" => 540.0,
        "2025-04-01" => 545.0, "2025-05-01" => 555.0, "2025-06-01" => 565.0,
        "2025-07-01" => 575.0, "2025-08-01" => 585.0, "2025-09-01" => 590.0,
        "2025-10-01" => 600.0, "2025-11-01" => 610.0, "2025-12-01" => 620.0,
        "current" => 525.50
      },
      "VTI" => {
        "2023-01-01" => 195.0, "2023-02-01" => 205.0, "2023-03-01" => 207.0,
        "2023-04-01" => 208.0, "2023-05-01" => 212.0, "2023-06-01" => 220.0,
        "2023-07-01" => 230.0, "2023-08-01" => 228.0, "2023-09-01" => 220.0,
        "2023-10-01" => 215.0, "2023-11-01" => 228.0, "2023-12-01" => 238.0,
        "2024-01-01" => 240.0, "2024-02-01" => 252.0, "2024-03-01" => 260.0,
        "2024-04-01" => 256.0, "2024-05-01" => 265.0, "2024-06-01" => 275.0,
        "2024-07-01" => 280.0, "2024-08-01" => 282.0, "2024-09-01" => 290.0,
        "2024-10-01" => 293.0, "2024-11-01" => 300.0, "2024-12-01" => 305.0,
        "2025-01-01" => 308.0, "2025-02-01" => 312.0, "2025-03-01" => 316.0,
        "2025-04-01" => 320.0, "2025-05-01" => 325.0, "2025-06-01" => 330.0,
        "2025-07-01" => 335.0, "2025-08-01" => 338.0, "2025-09-01" => 340.0,
        "2025-10-01" => 345.0, "2025-11-01" => 350.0, "2025-12-01" => 355.0,
        "current" => 339.67
      },
      "IWM" => {
        "2023-01-01" => 185.0, "2023-02-01" => 193.0, "2023-03-01" => 175.0,
        "2023-04-01" => 176.0, "2023-05-01" => 175.0, "2023-06-01" => 188.0,
        "2023-07-01" => 197.0, "2023-08-01" => 190.0, "2023-09-01" => 178.0,
        "2023-10-01" => 168.0, "2023-11-01" => 180.0, "2023-12-01" => 197.0,
        "2024-01-01" => 195.0, "2024-02-01" => 202.0, "2024-03-01" => 210.0,
        "2024-04-01" => 198.0, "2024-05-01" => 207.0, "2024-06-01" => 202.0,
        "2024-07-01" => 222.0, "2024-08-01" => 212.0, "2024-09-01" => 220.0,
        "2024-10-01" => 218.0, "2024-11-01" => 238.0, "2024-12-01" => 230.0,
        "2025-01-01" => 232.0, "2025-02-01" => 228.0, "2025-03-01" => 225.0,
        "2025-04-01" => 230.0, "2025-05-01" => 235.0, "2025-06-01" => 240.0,
        "2025-07-01" => 245.0, "2025-08-01" => 248.0, "2025-09-01" => 250.0,
        "2025-10-01" => 255.0, "2025-11-01" => 260.0, "2025-12-01" => 265.0,
        "current" => 226.50
      },
      "DIA" => {
        "2023-01-01" => 332.0, "2023-02-01" => 336.0, "2023-03-01" => 331.0,
        "2023-04-01" => 340.0, "2023-05-01" => 337.0, "2023-06-01" => 343.0,
        "2023-07-01" => 358.0, "2023-08-01" => 352.0, "2023-09-01" => 338.0,
        "2023-10-01" => 332.0, "2023-11-01" => 356.0, "2023-12-01" => 373.0,
        "2024-01-01" => 378.0, "2024-02-01" => 390.0, "2024-03-01" => 397.0,
        "2024-04-01" => 384.0, "2024-05-01" => 395.0, "2024-06-01" => 395.0,
        "2024-07-01" => 410.0, "2024-08-01" => 412.0, "2024-09-01" => 420.0,
        "2024-10-01" => 425.0, "2024-11-01" => 442.0, "2024-12-01" => 448.0,
        "2025-01-01" => 450.0, "2025-02-01" => 455.0, "2025-03-01" => 460.0,
        "2025-04-01" => 465.0, "2025-05-01" => 470.0, "2025-06-01" => 475.0,
        "2025-07-01" => 480.0, "2025-08-01" => 485.0, "2025-09-01" => 488.0,
        "2025-10-01" => 492.0, "2025-11-01" => 498.0, "2025-12-01" => 505.0,
        "current" => 437.50
      },
      "AGG" => {
        "2023-01-01" => 100.0, "2023-02-01" => 98.0, "2023-03-01" => 100.0,
        "2023-04-01" => 100.0, "2023-05-01" => 98.0, "2023-06-01" => 97.0,
        "2023-07-01" => 97.0, "2023-08-01" => 95.0, "2023-09-01" => 93.0,
        "2023-10-01" => 91.0, "2023-11-01" => 95.0, "2023-12-01" => 99.0,
        "2024-01-01" => 98.0, "2024-02-01" => 97.0, "2024-03-01" => 98.0,
        "2024-04-01" => 95.0, "2024-05-01" => 96.0, "2024-06-01" => 96.0,
        "2024-07-01" => 98.0, "2024-08-01" => 100.0, "2024-09-01" => 102.0,
        "2024-10-01" => 100.0, "2024-11-01" => 99.0, "2024-12-01" => 98.0,
        "2025-01-01" => 98.0, "2025-02-01" => 99.0, "2025-03-01" => 99.0,
        "2025-04-01" => 100.0, "2025-05-01" => 100.0, "2025-06-01" => 101.0,
        "2025-07-01" => 101.0, "2025-08-01" => 102.0, "2025-09-01" => 102.0,
        "2025-10-01" => 103.0, "2025-11-01" => 103.0, "2025-12-01" => 104.0,
        "current" => 98.50
      }
    }.freeze

    SUPPORTED_BENCHMARKS = BENCHMARK_PRICES.keys.freeze

    class << self
      def supported_benchmarks
        SUPPORTED_BENCHMARKS
      end

      def benchmark_price_on(ticker, date)
        ticker = ticker.upcase
        prices = BENCHMARK_PRICES[ticker]
        return nil unless prices

        date_str = date.to_s

        # Exact match
        return prices[date_str] if prices[date_str]

        # Find surrounding dates and interpolate
        sorted_dates = prices.keys.reject { |k| k == "current" }.map { |d| Date.parse(d) }.sort

        before_date = sorted_dates.select { |d| d <= date }.last
        after_date = sorted_dates.select { |d| d >= date }.first

        return prices["current"] if before_date.nil? && after_date.nil?
        return prices[before_date.to_s] if after_date.nil?
        return prices[after_date.to_s] if before_date.nil?
        return prices[before_date.to_s] if before_date == after_date

        # Linear interpolation
        before_price = prices[before_date.to_s]
        after_price = prices[after_date.to_s]

        days_total = (after_date - before_date).to_i
        days_from_before = (date - before_date).to_i

        ratio = days_from_before.to_f / days_total
        before_price + (after_price - before_price) * ratio
      end

      def current_price(ticker)
        ticker = ticker.upcase
        prices = BENCHMARK_PRICES[ticker]
        return nil unless prices

        prices["current"]
      end

      def calculate_benchmark_return(cash_flows:, benchmark_ticker: "SPY", current_date: Date.current)
        return nil if cash_flows.empty?

        benchmark_ticker = benchmark_ticker.upcase
        return nil unless BENCHMARK_PRICES.key?(benchmark_ticker)

        # Calculate how many benchmark shares each cash flow would have bought
        benchmark_shares = 0.0

        cash_flows.each do |cf|
          next if cf[:amount].nil? || cf[:amount] == 0

          benchmark_price = benchmark_price_on(benchmark_ticker, cf[:date])
          next if benchmark_price.nil? || benchmark_price <= 0

          if cf[:amount] < 0
            # Buy: negative cash flow = buying shares
            shares_bought = cf[:amount].abs / benchmark_price
            benchmark_shares += shares_bought
          else
            # Sell/dividend: positive cash flow = selling shares proportionally
            shares_sold = cf[:amount] / benchmark_price
            benchmark_shares -= shares_sold
            benchmark_shares = 0 if benchmark_shares < 0
          end
        end

        return nil if benchmark_shares <= 0

        # Current value of benchmark position
        current_benchmark_price = benchmark_price_on(benchmark_ticker, current_date)
        benchmark_ending_value = benchmark_shares * current_benchmark_price

        # Calculate IRR for benchmark using same cash flows
        inception_date = cash_flows.first[:date]

        CagrCalculator.calculate(
          cash_flows: cash_flows,
          ending_value: benchmark_ending_value,
          inception_date: inception_date,
          current_date: current_date
        )
      end
    end
  end
end
