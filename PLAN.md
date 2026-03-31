# Inventory Demand Forecaster — Build Plan

## Overview

A demand forecasting pipeline for retail/warehouse inventory management. Ingests historical sales
data from CSV/JSON files, detects seasonal patterns and trends, generates per-SKU demand forecasts,
calculates reorder points and safety stock levels, and produces purchase order recommendations with
markdown reports.

## Architecture

### Agents

| Agent | Model | Role |
|---|---|---|
| **data-ingester** | claude-haiku-4-5 | Parses and normalizes sales CSV/JSON files into a unified format |
| **trend-analyzer** | claude-sonnet-4-6 | Detects seasonal patterns, trends, and correlations using sequential-thinking |
| **demand-forecaster** | claude-sonnet-4-6 | Generates per-SKU demand forecasts, calculates reorder points and safety stock |
| **procurement-reviewer** | claude-opus-4-6 | Decision gate — reviews forecasts and classifies reorder urgency |
| **report-generator** | claude-haiku-4-5 | Produces markdown reports with forecast tables, charts, and PO recommendations |

### MCP Servers

- **filesystem** — read/write sales data, forecasts, config files, reports
- **sequential-thinking** — structured reasoning for trend analysis and forecast validation

### Phase Pipeline

```
ingest-sales-data (command: validate + parse CSVs)
       │
  normalize-data (agent: data-ingester)
       │
  analyze-trends (agent: trend-analyzer + sequential-thinking)
       │
  generate-forecasts (agent: demand-forecaster)
       │
  review-reorder-urgency (agent: procurement-reviewer, decision)
       │                    ├─ immediate → generate-purchase-orders
       │                    ├─ scheduled → generate-purchase-orders
       │                    └─ monitor → generate-monitoring-report
       │
  generate-purchase-orders (agent: demand-forecaster)
       │
  generate-monitoring-report (agent: report-generator)
       │
  compile-forecast-report (agent: report-generator)
```

### Workflow Routing

- **review-reorder-urgency** is the key decision phase:
  - `immediate`: SKUs at critical stock levels, rush POs needed
  - `scheduled`: SKUs approaching reorder points, standard POs
  - `monitor`: All SKUs healthy, no POs needed — generate monitoring report only
- On `rework` from review: goes back to generate-forecasts (max 2 rework attempts)

### Secondary Workflow: weekly-forecast-refresh

Scheduled weekly to re-run the full pipeline on latest sales data:
- Phases: ingest-sales-data → normalize-data → analyze-trends → generate-forecasts → review-reorder-urgency → ...
- Uses the same agents and decision routing as the primary workflow

### Secondary Workflow: sku-health-audit

On-demand audit of SKU forecast accuracy and inventory health:
- Phases: scan-inventory → compare-actuals-vs-forecast → compile-accuracy-report

## Directory Structure

```
examples/inventory-forecaster/
├── .ao/workflows/
│   ├── agents.yaml
│   ├── phases.yaml
│   ├── workflows.yaml
│   ├── mcp-servers.yaml
│   └── schedules.yaml
├── config/
│   ├── forecasting-params.yaml      # Lead times, safety stock multipliers, seasonality config
│   ├── sku-categories.yaml          # SKU classification (A/B/C tiers by revenue)
│   └── supplier-catalog.yaml        # Supplier info, MOQs, lead times per supplier
├── data/
│   ├── sales-history/               # Input: raw sales CSV/JSON files
│   │   ├── sales-2025-q3.csv
│   │   └── sales-2025-q4.csv
│   ├── normalized/                  # Processed: unified sales records
│   │   └── unified-sales.json
│   ├── forecasts/                   # Generated demand forecasts per SKU
│   │   └── forecast-latest.json
│   ├── reorder-points/              # Calculated reorder points and safety stock
│   │   └── reorder-points.json
│   └── audit-log.json               # Append-only log of forecast runs
├── output/
│   ├── purchase-orders/             # Generated PO recommendations
│   │   └── po-{date}.json
│   ├── reports/                     # Markdown forecast and audit reports
│   │   ├── forecast-{date}.md
│   │   └── accuracy-{date}.md
│   └── alerts/                      # Urgent reorder alerts
│       └── alert-{date}.json
├── scripts/
│   ├── validate-sales-data.sh       # Validates CSV structure, checks for required columns
│   ├── generate-forecast-diff.sh    # Compares current vs previous forecast
│   └── scan-inventory.sh            # Scans current stock levels for audit
├── CLAUDE.md                        # Agent context document
└── README.md                        # Project overview and usage
```

## Sample Data Design

### sales-2025-q4.csv
```
date,sku,quantity,unit_price,channel,region
2025-10-01,WH-TOOL-1001,45,29.99,online,northeast
2025-10-01,WH-ELEC-2050,12,149.99,retail,southeast
...
```

### config/forecasting-params.yaml
```yaml
forecast_horizon_days: 90
safety_stock_multiplier: 1.5
reorder_point_method: eoq         # eoq | fixed-period | min-max
seasonality_detection: true
confidence_threshold: 0.7
lead_time_buffer_days: 3
abc_classification:
  a_threshold: 0.80               # Top 80% of revenue
  b_threshold: 0.95               # Next 15%
  c_threshold: 1.00               # Bottom 5%
```

### config/sku-categories.yaml
```yaml
categories:
  tools:
    prefix: "WH-TOOL"
    seasonality: low
    default_lead_time_days: 14
  electronics:
    prefix: "WH-ELEC"
    seasonality: high              # Holiday spikes
    default_lead_time_days: 21
  safety:
    prefix: "WH-SAFE"
    seasonality: none
    default_lead_time_days: 7
    critical: true                 # Never allow stockout
  outdoor:
    prefix: "WH-OUTD"
    seasonality: high              # Summer peak
    default_lead_time_days: 28
```

### config/supplier-catalog.yaml
```yaml
suppliers:
  acme-tools:
    name: "Acme Tool Supply"
    skus: ["WH-TOOL-*"]
    min_order_quantity: 50
    lead_time_days: 14
    payment_terms: "net-30"
  volt-electronics:
    name: "Volt Electronics Inc."
    skus: ["WH-ELEC-*"]
    min_order_quantity: 25
    lead_time_days: 21
    payment_terms: "net-45"
  safeguard-co:
    name: "SafeGuard Supply Co."
    skus: ["WH-SAFE-*"]
    min_order_quantity: 100
    lead_time_days: 7
    payment_terms: "net-15"
    priority_supplier: true
  greenfield-outdoor:
    name: "Greenfield Outdoor Gear"
    skus: ["WH-OUTD-*"]
    min_order_quantity: 30
    lead_time_days: 28
    payment_terms: "net-30"
```

## Key Features Demonstrated

1. **Command phases** — `validate-sales-data.sh` for data validation, `generate-forecast-diff.sh` for diffs, `scan-inventory.sh` for audits
2. **Multi-agent pipeline** — 5 agents with distinct roles (ingestion, analysis, forecasting, review, reporting)
3. **Decision contracts** — `review-reorder-urgency` with verdicts: immediate/scheduled/monitor
4. **Output contracts** — structured forecasts, reorder points, PO recommendations
5. **Scheduled workflows** — weekly forecast refresh via cron
6. **Sequential-thinking** — trend analyzer uses structured reasoning for seasonal pattern detection
7. **Model variety** — Haiku (ingestion, reporting), Sonnet (analysis, forecasting), Opus (procurement review)

## Quality Bar

- Forecasts must include confidence intervals (high/medium/low)
- Purchase orders must respect supplier MOQs and lead times
- Safety-critical SKUs (WH-SAFE-*) must never recommend "monitor" — always reorder
- Reports must include comparison to previous forecast period
- All monetary values formatted consistently (2 decimal places, currency symbol)
