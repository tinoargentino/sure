# Investments & CAGR Feature Design

**Status**: Design Document (Pre-Implementation)
**Date**: December 2025
**Feature**: Investment Portfolio Tracking with CAGR Calculations

---

## Table of Contents

1. [Overview](#overview)
2. [Goals & Success Criteria](#goals--success-criteria)
3. [Data Model](#data-model)
4. [CSV Import & Validation](#csv-import--validation)
5. [CAGR Calculation Algorithm](#cagr-calculation-algorithm)
6. [Backend API Surface](#backend-api-surface)
7. [Frontend UI/UX](#frontend-uiux)
8. [Navigation Integration](#navigation-integration)
9. [Implementation Roadmap](#implementation-roadmap)
10. [Edge Cases & Considerations](#edge-cases--considerations)

---

## Overview

The Investments feature enables users to track their investment portfolio by uploading brokerage transaction data via CSV. The system will compute **Compound Annualized Growth Rate (CAGR)** both per ticker (symbol) and at the portfolio level, providing a clear view of investment performance.

### Key Design Principles

- **Leverage existing infrastructure**: Reuse the proven CSV import system from Transactions/Trades
- **Simple, focused scope**: Display CAGR as the primary metric; extend later if needed
- **Extensible architecture**: Support multiple brokerage CSV formats and future metrics
- **Rails conventions**: Follow established patterns (Hotwire, ViewComponent, Stimulus)
- **Zero external dependencies**: Use existing gems where possible

---

## Goals & Success Criteria

### Goals

1. Allow users to upload brokerage transaction CSVs
2. Parse and validate transactions with flexible schema mapping
3. Compute CAGR per ticker and portfolio-level
4. Display results in a clean, intuitive UI
5. Support future enhancements (more metrics, dividends, tax lots)

### Success Criteria

- **Data Accuracy**: CAGR calculations match industry-standard formulas (IRR-based)
- **UX Clarity**: Users understand their portfolio performance at a glance
- **Resilience**: Clear error messages for malformed/incomplete data
- **Performance**: Fast calculations even with thousands of transactions
- **Integration**: "Investments" appears naturally alongside existing sections

---

## Data Model

### Entity Relationship Diagram

```
Investment (Account subtype)
├── InvestmentPosition (one per ticker, scoped to account)
│   ├── ticker (string, required)
│   ├── quantity_current (decimal)
│   ├── cost_basis_total (money)
│   └── current_market_value (money) [future]
└── InvestmentTransaction
    ├── transaction_type (enum: buy, sell, dividend, fee, split)
    ├── ticker (string)
    ├── quantity (decimal) [null for non-trade transactions]
    ├── price_per_unit (money) [null for non-trade transactions]
    ├── amount (money)
    ├── transaction_date (date)
    ├── source (enum: csv, api, manual) [for audit trail]
    └── external_id (string) [for deduplication]

Portfolio (portfolio-level aggregate, computed)
├── total_investments (money)
├── total_cost_basis (money)
├── cagr_percent (decimal) [computed, ~4.2]
├── inception_date (date)
└── current_date (date) [as of calculation]
```

### Models

#### 1. **Investment** (Account Subtype)
Inherits from `Account` via Rails' `delegated_type`. Represents a brokerage account.

```ruby
class Investment < Account
  has_many :investment_positions, dependent: :destroy
  has_many :investment_transactions, dependent: :destroy

  def portfolio_metrics
    # Returns cached/computed metrics for the entire account
  end

  def positions_with_cagr
    # Returns positions sorted by CAGR (descending)
  end
end
```

**Attributes**:
- Inherits from `Account`: `name`, `family_id`, `accountable_id/type`, `currency`, `balance`, `last_synced_at`
- `broker` (string): "vanguard", "fidelity", "interactive_brokers", "other" [for UI hints]

#### 2. **InvestmentPosition**
Represents an open position in a single ticker within an account.

```ruby
class InvestmentPosition < ApplicationRecord
  belongs_to :investment
  has_many :investment_transactions, dependent: :restrict_with_error

  validates :ticker, presence: true, uniqueness: { scope: :investment_id }

  def cash_flows
    # Returns array of [date, signed_amount] tuples for CAGR calc
  end

  def cagr
    # Computes and caches CAGR
  end

  def current_quantity
    # Sum of buys - sum of sells
  end
end
```

**Attributes**:
- `investment_id` (uuid, FK)
- `ticker` (string): e.g., "VTSAX", "AAPL"
- `inception_date` (date): First transaction date for this ticker
- `cagr_percent` (decimal, nullable): Cached CAGR, null until calculated
- `cagr_calculated_at` (datetime): When was CAGR last updated
- `metadata` (jsonb, optional): Sector, asset class, etc. for future enhancements

#### 3. **InvestmentTransaction**
A single transaction (buy, sell, dividend, fee, etc.) in a position.

```ruby
class InvestmentTransaction < ApplicationRecord
  belongs_to :investment
  belongs_to :investment_position, optional: true  # Null for cash transactions

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
end
```

**Attributes**:
- `investment_id` (uuid, FK): Parent account
- `investment_position_id` (uuid, FK, nullable): Ticker position (null for cash txns)
- `transaction_type` (enum): buy, sell, dividend, fee, split, deposit, withdrawal
- `ticker` (string, nullable): E.g., "AAPL" (null for cash txns)
- `quantity` (decimal, nullable): For buys/sells, number of shares
- `price_per_unit` (money, nullable): For buys/sells, $/€/£ per share
- `amount` (money): Total transaction value (signed: negative for sells/withdrawals)
- `transaction_date` (date)
- `source` (enum): csv, api, manual
- `external_id` (string, nullable): Brokerage ID (for dedup)
- `currency` (string): Transaction currency (may differ from account)
- `notes` (text, optional): User-provided or extracted from CSV

#### 4. **InvestmentImport** (Optional, inherits from existing Import pattern)
Tracks a CSV import session, reusing the proven `Import` infrastructure.

```ruby
class InvestmentImport < Import
  # Reuses Import structure for 5-step workflow:
  # 1. Upload (validates file exists, readable, size OK)
  # 2. Configure (separator, decimal format, date format, etc.)
  # 3. Validate (check columns, data quality)
  # 4. Map (bind CSV columns to InvestmentTransaction fields)
  # 5. Publish (execute InvestmentImportJob)
end
```

This leverages the existing `Import::Configuration`, `Import::Mapping`, and `Import::Row` classes.

---

## CSV Import & Validation

### Supported CSV Formats

We will support a flexible, configurable format rather than hardcoding a specific brokerage schema.

#### Example 1: Simple Format (Minimal)
```csv
Date,Ticker,Type,Quantity,Price,Amount
2024-01-15,VTSAX,BUY,100,85.50,-8550.00
2024-03-10,AAPL,BUY,10,175.00,-1750.00
2024-06-20,AAPL,SELL,5,195.00,975.00
2024-12-15,VTSAX,DIV,0,0.00,123.45
```

#### Example 2: Brokerage Detailed Format
```csv
Date,Settlement Date,Reference Number,Description,Ticker,Transaction Type,Shares,Price,Amount,Fees
2024-01-15,2024-01-17,12345678,"BUY VTSAX",VTSAX,BUY,100,85.50,-8550.00,-10.00
2024-03-10,2024-03-12,12345679,"BUY AAPL",AAPL,BUY,10,175.00,-1750.00,0
2024-06-20,2024-06-22,12345680,"SELL 5x AAPL @ 195.00",AAPL,SELL,5,195.00,975.00,0
2024-12-15,,12345681,"DIVIDEND AAPL",AAPL,DIV,0,0.00,123.45,0
```

### Import Configuration (Step 2)

Users specify how to interpret the CSV:

```json
{
  "separator": ",",
  "date_format": "YYYY-MM-DD",
  "decimal_separator": ".",
  "thousands_separator": ",",
  "date_column": "Date",
  "ticker_column": "Ticker",
  "type_column": "Transaction Type",
  "quantity_column": "Quantity",
  "price_column": "Price",
  "amount_column": "Amount",
  "fee_column": null,
  "reference_column": null,
  "type_mapping": {
    "BUY": "buy",
    "SELL": "sell",
    "DIV": "dividend",
    "Dividend": "dividend",
    "CASH": "deposit",
    "FEE": "fee"
  },
  "skip_rows": 0
}
```

### Validation Rules (Step 3)

**Row-level validations**:
1. Date must be valid and parseable
2. Ticker must match pattern: `[A-Z0-9]{1,5}` (ISIN, cusip, etc. future support)
3. Type must map to known enum value
4. Quantity must be ≥ 0 and numeric
5. Price must be positive numeric or zero
6. Amount must be numeric (can be negative for sells)
7. For buy/sell: `abs(amount) ≈ quantity × price` (within 1% tolerance for rounding)

**Account-level validations**:
1. No duplicate external_ids (if provided)
2. Ticker consistency: once mapped to a position, all transactions for that ticker stay consistent
3. Quantity sanity: never sell more than owned (warn but allow, for short selling or data entry errors)

**Error handling**:
- Collect all validation errors per row, return summary to user
- UI shows row-by-row errors with suggested fixes
- Allow user to skip/ignore certain rows or fix in-UI before publishing

### Mapping & Cleaning (Steps 4-5)

Reuse existing `Import::Mapping` UI, customizing for investment fields:

1. **Column Binding**: User maps "Date" → `transaction_date`, "Ticker" → `ticker`, etc.
2. **Type Mapping**: User defines CSV values ("BUY") → enum ("buy")
3. **Row Preview**: Show first 5 rows with parsed/cleaned values
4. **Deduplication**: Check for existing transactions using `external_id` if available
5. **Publish**: Fire `InvestmentImportJob` to create `InvestmentTransaction` records and positions

### Extensibility

To support new brokerage formats:
1. Add brokerage preset templates (dropdown in Step 2): "Vanguard", "Fidelity", "Interactive Brokers", "Custom"
2. Preset populates default configuration (date format, column names, type mappings)
3. User can tweak if needed; custom presets can be saved per account

---

## CAGR Calculation Algorithm

### Overview

**CAGR (Compound Annualized Growth Rate)** measures investment return assuming gains are reinvested annually. We compute it using an **Internal Rate of Return (IRR) approach**, which is the industry-standard method for portfolios with irregular cash flows.

### Mathematical Foundation

Given a series of cash flows (investments/withdrawals) and an ending value, IRR is the discount rate `r` that satisfies:

$$\text{NPV} = \sum_{t=0}^{n} \frac{CF_t}{(1 + r)^{t_d}} = 0$$

Where:
- `CF_t` = cash flow at time `t` (negative for outflows like purchases, positive for inflows like sales)
- `t_d` = time in years from inception to cash flow
- `r` = IRR (annualized return)

### Algorithm: Modified Newton-Raphson IRR Solver

We'll use a robust numerical solver (Newton-Raphson with bisection fallback) to find `r`:

```pseudo
function calculate_cagr(cash_flows):
  """
  cash_flows: array of [date, amount] tuples, sorted by date
             amounts: negative = invested (outflow), positive = proceeds (inflow)
  returns: cagr_percent (float) or null if invalid
  """

  if len(cash_flows) < 2:
    return null  // Need at least start and end

  inception_date = cash_flows[0].date
  current_date = today()
  years = (current_date - inception_date).days / 365.25

  if years < 0.01:  // Less than ~3.6 days
    return null

  // Ending value = abs(sum of outflows) - sum of inflows + profit/loss
  // More precisely: current market value or closed-out position value

  ending_value = calculate_position_value()

  // Special case: position fully liquidated
  if all positions closed:
    ending_value = sum of sale proceeds + dividends received

  // Reframe as NPV problem:
  // 0 = sum of (CF_t / (1 + r)^t_years) where r is IRR

  return newton_raphson_irr(cash_flows, ending_value, inception_date)

function newton_raphson_irr(cash_flows, ending_value, inception_date):
  max_iterations = 100
  tolerance = 1e-6
  r = 0.1  // Initial guess: 10% return

  for iteration in 1..max_iterations:
    npv = calculate_npv(r, cash_flows, ending_value, inception_date)

    if abs(npv) < tolerance:
      return r * 100  // Convert to percentage

    npv_derivative = calculate_npv_derivative(r, cash_flows, ending_value, inception_date)

    if abs(npv_derivative) < 1e-10:
      break  // Cannot improve further

    r_new = r - (npv / npv_derivative)

    if abs(r_new - r) < tolerance:
      return r_new * 100

    r = r_new

  // Fallback: bisection if Newton-Raphson doesn't converge
  return bisection_irr(cash_flows, ending_value, inception_date)
```

### Implementation: Ruby Gem

We'll extract CAGR logic into a lightweight module to keep it testable:

```ruby
module InvestmentMetrics
  class CAGRCalculator
    def self.calculate(cash_flows:, ending_value:, inception_date:, current_date: Date.today)
      calc = new(cash_flows, ending_value, inception_date, current_date)
      calc.cagr
    end

    def initialize(cash_flows, ending_value, inception_date, current_date)
      @cash_flows = cash_flows.sort_by { |cf| cf[:date] }
      @ending_value = ending_value
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
      # Newton-Raphson implementation
    end

    def npv(rate)
      # Calculate NPV at given discount rate
    end
  end
end
```

### Portfolio-Level CAGR

For the overall portfolio, we sum cash flows across ALL tickers:

```ruby
def portfolio_cagr
  all_transactions = investment_transactions.order(:transaction_date)

  cash_flows = all_transactions.map do |txn|
    {
      date: txn.transaction_date,
      amount: -txn.amount  # Negative = cash out, positive = cash in
    }
  end

  # Ending value = sum of current position values (if open) + closed proceeds
  ending_value = positions.sum(&:current_market_value) + closed_proceeds

  InvestmentMetrics::CAGRCalculator.calculate(
    cash_flows: cash_flows,
    ending_value: ending_value,
    inception_date: all_transactions.first.transaction_date
  )
end
```

### Edge Cases & Handling

| Case | Behavior |
|------|----------|
| **Position never invested** | Return `null` (no data) |
| **Invested < 1 week** | Return `null` (time period too short) |
| **No cash flows, only dividends** | Return `null` (IRR undefined) |
| **Convergence failure** | Return `null` + log warning |
| **Negative returns (loss)** | Return negative percentage (e.g., -5.2%) |
| **Fully liquidated position** | Use proceeds as ending value |
| **Open position (no exit)** | Use estimated market value (future feature) |
| **Multiple currencies** | Convert all to account currency at transaction time |

### Performance Optimization

1. **Caching**: Store calculated CAGR in `InvestmentPosition#cagr_percent`, invalidate on new transactions
2. **Async Recalculation**: `InvestmentCAGRJob` recalculates nightly or on-demand via background job
3. **Incremental Updates**: If position has X transactions and 1 new transaction added, recalculate rather than full rebuild

---

## Backend API Surface

### REST Endpoints

#### **Investment Accounts**

```
GET    /investments              # List all investment accounts
POST   /investments              # Create new investment account
GET    /investments/:id          # Show account with portfolio metrics
PATCH  /investments/:id          # Update account (name, broker, etc.)
DELETE /investments/:id          # Delete account (soft delete)
```

#### **Positions & CAGR**

```
GET    /investments/:id/positions              # List all positions with CAGR
GET    /investments/:id/positions/:position_id # Show single position
```

#### **Portfolio Metrics**

```
GET    /investments/:id/metrics   # Portfolio-level metrics
```

**Response shape**:
```json
{
  "portfolio": {
    "id": "uuid",
    "name": "My Brokerage",
    "currency": "USD",
    "inception_date": "2024-01-15",
    "total_invested": 10250.00,
    "total_market_value": 11800.00,
    "cagr_percent": 15.2,
    "last_updated": "2025-12-21T10:30:00Z"
  },
  "positions": [
    {
      "id": "uuid",
      "ticker": "VTSAX",
      "quantity": 100,
      "average_cost": 85.50,
      "total_cost_basis": 8550.00,
      "cagr_percent": 12.5,
      "inception_date": "2024-01-15",
      "transactions_count": 3
    },
    {
      "id": "uuid",
      "ticker": "AAPL",
      "quantity": 5,
      "average_cost": 170.00,
      "total_cost_basis": 850.00,
      "cagr_percent": 22.1,
      "inception_date": "2024-03-10",
      "transactions_count": 3
    }
  ]
}
```

#### **CSV Import Workflow** (Reuses existing Import system)

```
POST   /imports                      # Create new import
POST   /imports/:id/upload           # Upload CSV file
POST   /imports/:id/configure        # Set separator, date format, etc.
GET    /imports/:id/rows             # Preview parsed rows
POST   /imports/:id/map              # Map CSV columns to fields
POST   /imports/:id/confirm          # Validate & summarize
POST   /imports/:id/publish          # Execute import (async job)
GET    /imports/:id                  # Show import status & results
```

#### **Transactions**

```
GET    /investments/:id/transactions                # List all transactions
GET    /investments/:id/positions/:position_id/txns # Transactions for one ticker
POST   /investments/:id/transactions                # Manually create transaction
DELETE /investments/:id/transactions/:txn_id        # Delete transaction (audit)
```

### Controller Architecture

**Controllers**:
- `InvestmentsController` - List, create, show, update, delete accounts
- `Investment::PositionsController` - List positions with CAGR
- `Investment::MetricsController` - Portfolio-level metrics
- `Investment::TransactionsController` - Transaction CRUD
- `InvestmentImportsController` - CSV import workflow (reuses Import pattern)

**Service Layer** (minimal, keep in models per convention):
- `InvestmentPosition#cash_flows` - Returns array for CAGR calc
- `InvestmentMetrics::CAGRCalculator` - Stateless IRR solver
- `InvestmentImportService` - Parse & validate CSV rows (separate concern)

---

## Frontend UI/UX

### Page Hierarchy

```
/investments
  ├── Dashboard (index)
  │   ├── Portfolio card (total invested, total value, CAGR)
  │   ├── Position list (ticker, quantity, CAGR, change %)
  │   └── Quick actions (+ Upload, + Manual)
  │
  ├── /investments/new
  │   └── New Account form (name, broker, currency)
  │
  ├── /investments/:id
  │   ├── Account header (name, broker, sync status)
  │   ├── Portfolio metrics card
  │   ├── Position list with CAGR (sortable, filterable)
  │   ├── Recent transactions (last 10)
  │   └── Actions (Upload CSV, View all transactions)
  │
  ├── /imports/new?type=investment
  │   ├── Step 1: Upload CSV file
  │   ├── Step 2: Configure (separator, date format, decimal format)
  │   ├── Step 3: Validate & preview rows
  │   ├── Step 4: Map columns (Date → date_column, Ticker → ticker, etc.)
  │   ├── Step 5: Confirm & import (async job)
  │   └── Results (success/error summary)
  │
  └── /investments/:id/transactions
      └── Full transaction list (filterable, downloadable)
```

### Components

#### 1. **InvestmentCard** (ViewComponent)
Portfolio summary at a glance.

```erb
<div class="card">
  <h3><%= @account.name %></h3>
  <div class="metrics">
    <div class="metric">
      <span class="label">Total Invested</span>
      <span class="value"><%= number_to_currency(@account.total_invested) %></span>
    </div>
    <div class="metric">
      <span class="label">Current Value</span>
      <span class="value"><%= number_to_currency(@account.current_value) %></span>
    </div>
    <div class="metric">
      <span class="label">CAGR</span>
      <span class="value <%= @account.cagr_class %>">
        <%= number_to_percentage(@account.portfolio_cagr, precision: 1) %>
      </span>
    </div>
  </div>
</div>
```

**Variants**: `size: :small` (index), `size: :large` (show), `interactive: true` (clickable)

#### 2. **PositionList** (ViewComponent)
Table of tickers with CAGR, sortable.

```erb
<table class="position-list">
  <thead>
    <tr>
      <th <%= link_to "Ticker", sort: "ticker" %>>
      <th <%= link_to "Quantity", sort: "quantity" %>>
      <th <%= link_to "Cost Basis", sort: "cost_basis" %>>
      <th <%= link_to "CAGR", sort: "cagr" %>>
      <th>Actions</th>
    </tr>
  </thead>
  <tbody>
    <% @positions.each do |position| %>
      <tr data-id="<%= position.id %>">
        <td><strong><%= position.ticker %></strong></td>
        <td><%= position.quantity %></td>
        <td><%= number_to_currency(position.cost_basis) %></td>
        <td class="<%= position.cagr_class %>">
          <%= number_to_percentage(position.cagr, precision: 1) %>
        </td>
        <td>
          <%= link_to "Transactions", position_transactions_path(position) %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
```

**Stimulus Controller**: `position-sorter` (client-side sorting with query params)

#### 3. **ImportWizard** (Reuse existing Import::Wizard)
5-step CSV import flow, customized for investments.

**Step 1 - Upload**: Standard file input, validates file type/size

**Step 2 - Configure**: Form for separator, decimal format, date format, type mappings
```erb
<form data-controller="import-config">
  <%= f.select :separator, [",", ";", "\t"] %>
  <%= f.select :decimal_separator, [".", ","] %>
  <%= f.select :date_format, ["YYYY-MM-DD", "MM/DD/YYYY", "DD/MM/YYYY"] %>

  <h4>Map Transaction Types</h4>
  <% ["BUY", "SELL", "DIV", "FEE"].each do |csv_value| %>
    <%= f.select "type_mapping[#{csv_value}]",
        [["buy", "buy"], ["sell", "sell"], ["dividend", "dividend"], ...] %>
  <% end %>
</form>
```

**Step 3 - Validate**: Preview parsed rows with color-coded validation status
```erb
<table class="import-preview">
  <thead>
    <tr>
      <th>Row</th>
      <th>Date</th>
      <th>Ticker</th>
      <th>Type</th>
      <th>Quantity</th>
      <th>Status</th>
    </tr>
  </thead>
  <tbody>
    <% @parsed_rows.each_with_index do |row, idx| %>
      <tr class="<%= row.valid? ? 'valid' : 'error' %>">
        <td><%= idx + 1 %></td>
        <td><%= row.date %></td>
        <td><%= row.ticker %></td>
        <td><%= row.type %></td>
        <td><%= row.quantity %></td>
        <td>
          <% if row.valid? %>
            <span class="badge-success">✓</span>
          <% else %>
            <span class="badge-error"><%= row.errors.first %></span>
          <% end %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
```

**Step 4 - Map**: Drag-and-drop column mapping (Stimulus-driven)
```erb
<div data-controller="column-mapper">
  <div class="mapping-group">
    <label>Date Column</label>
    <select data-column-mapper-target="dateColumn">
      <% @csv_headers.each do |header| %>
        <option><%= header %></option>
      <% end %>
    </select>
  </div>
  <!-- Repeat for Ticker, Type, Quantity, Price, Amount -->
</div>
```

**Step 5 - Confirm**: Summary + execute async job
```erb
<div class="import-summary">
  <h3><%= "transactions_to_import", count: @row_count %></h3>
  <ul>
    <li>New positions: <%= @new_positions_count %></li>
    <li>New transactions: <%= @row_count %></li>
    <li>Duplicates skipped: <%= @duplicate_count %></li>
  </ul>
  <%= f.submit "Import", data: { controller: "async-loader" } %>
</div>
```

#### 4. **TransactionList** (ViewComponent)
Detailed transaction history (optional, future).

```erb
<table class="transaction-list">
  <thead>
    <tr>
      <th>Date</th>
      <th>Ticker</th>
      <th>Type</th>
      <th>Quantity</th>
      <th>Price</th>
      <th>Amount</th>
    </tr>
  </thead>
  <tbody>
    <% @transactions.each do |txn| %>
      <tr>
        <td><%= l(txn.transaction_date) %></td>
        <td><%= txn.ticker %></td>
        <td><span class="badge"><%= t("investments.types.#{txn.transaction_type}") %></span></td>
        <td><%= txn.quantity %></td>
        <td><%= number_to_currency(txn.price_per_unit) %></td>
        <td class="<%= txn.amount.positive? ? 'positive' : 'negative' %>">
          <%= number_to_currency(txn.amount) %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
```

### Design System Integration

- **Colors**:
  - Green for positive returns/gains (CAGR > 0)
  - Red for negative returns (CAGR < 0)
  - Gray for neutral (pending calculation, no data)

- **Typography**:
  - Section titles use `text-xl font-bold text-primary`
  - Metric labels use `text-sm text-tertiary`
  - Metric values use `text-lg font-mono text-primary`

- **Spacing**:
  - Card padding: `p-6`
  - Section gap: `gap-4` (flex/grid)
  - Table row padding: `py-4 px-6`

### Mobile Responsiveness

- **Desktop**: 3-column layout (sidebar, main, chat)
- **Tablet**: 2-column (sidebar, main)
- **Mobile**: 1-column, bottom nav + hamburger menu
  - Position list collapses to ticker + CAGR only
  - Metrics shown as horizontal scrollable cards
  - Full transaction list hidden, accessible via "View More"

---

## Navigation Integration

### 1. Main Navigation Update

Update `/app/views/layouts/application.html.erb` to add Investments:

```erb
<% mobile_nav_items = [
  { name: "Home", path: root_path, icon: "pie-chart", ... },
  { name: "Transactions", path: transactions_path, icon: "credit-card", ... },
  { name: "Reports", path: reports_path, icon: "chart-bar", ... },
  { name: "Investments", path: investments_path, icon: "trending-up", ... },  # NEW
  { name: "Budgets", path: budgets_path, icon: "map", ... },
  { name: "Assistant", path: chats_path, icon: "icon-assistant", mobile_only: true }
] %>
```

### 2. Icon Selection

Use "trending-up" (or "line-chart") from Lucide to represent Investments.

### 3. Sidebar Account List Update

Add Investment accounts to the sidebar:

```erb
<div class="account-group">
  <h3><%= t("accounts.investment") %></h3>
  <ul>
    <% @current_family.accounts.where(accountable_type: "Investment").each do |account| %>
      <li class="<%= 'active' if current_page?(investments_path(account)) %>">
        <%= link_to account.name, investments_path(account) %>
      </li>
    <% end %>
  </ul>
</div>
```

### 4. Internationalization (i18n)

Add to `config/locales/en.yml`:

```yaml
en:
  investments:
    index: "Investments"
    new: "New Investment Account"
    edit: "Edit Investment Account"

    portfolio:
      title: "Portfolio"
      total_invested: "Total Invested"
      current_value: "Current Value"
      cagr: "CAGR"
      inception_date: "Since"

    positions:
      title: "Positions"
      ticker: "Ticker"
      quantity: "Quantity"
      cost_basis: "Cost Basis"
      cagr: "CAGR"
      inception_date: "Since"
      transactions_count: "Transactions"

    transactions:
      title: "Transactions"
      date: "Date"
      ticker: "Ticker"
      type: "Type"
      quantity: "Shares"
      price: "Price"
      amount: "Amount"

      types:
        buy: "Buy"
        sell: "Sell"
        dividend: "Dividend"
        fee: "Fee"
        split: "Split"
        deposit: "Deposit"
        withdrawal: "Withdrawal"

    import:
      title: "Import Transactions"
      step_1: "Upload CSV"
      step_2: "Configure"
      step_3: "Validate"
      step_4: "Map Columns"
      step_5: "Confirm"

      errors:
        invalid_date: "Invalid date format"
        invalid_ticker: "Invalid ticker symbol"
        invalid_quantity: "Quantity must be positive"
        amount_mismatch: "Calculated amount doesn't match"
        duplicate: "Duplicate transaction (already imported)"
```

---

## Implementation Roadmap

### Phase 1: Core Infrastructure (MVP)
**Goal**: Functional Investments section with CAGR calculation

- [ ] Create `Investment` account subtype (delegated type)
- [ ] Create `InvestmentPosition` model
- [ ] Create `InvestmentTransaction` model
- [ ] Build `InvestmentMetrics::CAGRCalculator` (IRR solver)
- [ ] Wire up associations and validations
- [ ] Add database migrations
- [ ] Create test fixtures

### Phase 2: Import Workflow
**Goal**: CSV import + parsing

- [ ] Create `InvestmentImport` (inherits from `Import`)
- [ ] Build import configuration UI (Step 2)
- [ ] Build row validation (Step 3)
- [ ] Build column mapping UI (Step 4)
- [ ] Create `InvestmentImportJob` (Sidekiq background job)
- [ ] Implement deduplication logic
- [ ] Build error handling & reporting

### Phase 3: Frontend & Navigation
**Goal**: User-facing UI

- [ ] Create `InvestmentsController` (index, show, new, create)
- [ ] Build `InvestmentCard` component
- [ ] Build `PositionList` component
- [ ] Create Investments views (index, show)
- [ ] Add nav items to main layout
- [ ] Update i18n files
- [ ] Mobile responsiveness

### Phase 4: Testing & Polish
**Goal**: Reliable, tested feature

- [ ] Unit tests for CAGR calculator
- [ ] Model tests (validations, associations)
- [ ] Controller tests
- [ ] System tests for import workflow
- [ ] Edge case testing (negative returns, fully liquidated, etc.)
- [ ] Performance testing (large import)
- [ ] Documentation & help text

### Phase 5: Future Enhancements (Post-MVP)
- [ ] Market value tracking (integrate with external APIs)
- [ ] Gain/loss reporting (realized & unrealized)
- [ ] Tax-lot tracking
- [ ] Dividend reinvestment simulation
- [ ] Sector/asset class breakdowns
- [ ] Benchmark comparison (vs S&P 500, etc.)
- [ ] API key exports (for third-party integrations)
- [ ] Automated sync with Plaid (if available)

---

## Edge Cases & Considerations

### Numerical Edge Cases

| Scenario | Handling |
|----------|----------|
| **Very small time period** (< 3 days) | Return `null`; display "Not enough history" |
| **Zero net cash flow** (bought and sold same amount) | Return `null`; display "No investment activity" |
| **Extreme returns** (e.g., 1000% or -99%) | Allow; flag if unrealistic for UI warning |
| **Convergence failure** in IRR solver | Return `null`; log error; alert operations team |
| **Non-positive ending value** | Treat as total loss; return negative CAGR |
| **Missing price/quantity data** | Mark row as error; require user fix before import |

### Currency & Localization

- All amounts stored in account's base currency
- Support display in user's preferred locale (number formatting, date format)
- For multi-currency transactions (future): convert at transaction date's exchange rate

### Data Integrity

1. **Soft deletes**: Never actually delete `InvestmentTransaction`; use `deleted_at` for audit trail
2. **Immutability**: Once imported, transactions are read-only (use deletion + re-import to fix)
3. **Audit logging**: Log who imported what, when (via `source` enum and timestamps)
4. **Reconciliation**: Provide "recalculate CAGR" button to verify against manually uploaded CSV

### Performance

- **Caching**: Store computed CAGR in `InvestmentPosition#cagr_percent`, invalidate on new transactions
- **Indexing**: Index on `(investment_id, transaction_date)` for range queries
- **Pagination**: Position list paginated at 25 per page; transaction list paginated at 100 per page
- **Async jobs**: Import processing & CAGR recalculation via Sidekiq

### Security

1. **Authorization**: Only family members can view/edit their accounts (scoped via `Current.family`)
2. **CSV validation**: Sanitize headers, limit file size (100 MB), validate encoding (UTF-8)
3. **Data privacy**: No logging of ticker symbols or amounts in debug logs
4. **API rate limiting**: Rack Attack limits per API key apply to import endpoints

### Future Extensibility

1. **Brokerage presets**: Add `InvestmentImportPreset` model for Vanguard, Fidelity, etc.
2. **Webhook syncing**: Accept POST from brokerages for real-time updates
3. **Market data integration**: Integrate with Yahoo Finance or Polygon.io for current prices
4. **Tax reporting**: Export to tax software (TurboTax, etc.) with realized gains/losses
5. **Portfolio optimization**: Suggest rebalancing based on target allocations
6. **Benchmarking**: Compare performance vs indexes

---

## Summary

This design provides a **minimal, focused MVP** for investment tracking with CAGR calculation, while maintaining **extensibility** for future enhancements. Key decisions:

1. **Reuse existing infrastructure** (Import system, Account types, ViewComponent patterns)
2. **IRR-based CAGR** with Newton-Raphson solver handles irregular cash flows correctly
3. **Flexible CSV parsing** supports multiple brokerage formats via configuration
4. **Clean separation of concerns**: Models for domain logic, controllers for routing, components for UI
5. **Integration into main nav** alongside Home, Transactions, Reports, Budgets
6. **Phased rollout**: Core models (Phase 1) → Import (Phase 2) → UI (Phase 3) → Polish (Phase 4)

---

**Next Steps**: User approval of design, then proceed to Phase 1 implementation.
