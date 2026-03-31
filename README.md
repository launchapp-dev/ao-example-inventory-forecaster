# Inventory Demand Forecaster

Demand forecasting pipeline — ingest historical sales CSV data, detect seasonal trends per SKU, generate 90-day demand forecasts, calculate reorder points and safety stock, and produce purchase order recommendations with full markdown reports.

## Workflow Diagram

```
data/sales-history/*.csv
         │
         ▼
┌─────────────────────┐
│  ingest-sales-data  │  (command) validate CSV structure
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│   normalize-data    │  (agent: data-ingester / Haiku)
│  Parse + unify CSVs │  → data/normalized/unified-sales.json
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│   analyze-trends    │  (agent: trend-analyzer / Sonnet + sequential-thinking)
│  Seasonal patterns  │  → data/forecasts/trend-analysis.json
│  Anomaly detection  │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ generate-forecasts  │  (agent: demand-forecaster / Sonnet)
│  EOQ, reorder pts   │  → data/forecasts/forecast-latest.json
│  Safety stock calc  │  → output/purchase-orders/po-draft-{date}.json
└─────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│              review-reorder-urgency (DECISION)              │  (agent: procurement-reviewer / Opus)
│  immediate → rush POs required NOW                          │
│  scheduled → standard PO batch this week                    │
│  monitor   → all healthy, no orders needed ──────────────┐  │
│  rework    → back to generate-forecasts (max 2×)         │  │
└─────────────────────────────────────────────────────────────┘
         │ (immediate/scheduled)                            │ (monitor)
         ▼                                                  │
┌─────────────────────┐                                     │
│ generate-purchase   │  (agent: demand-forecaster / Sonnet)│
│      -orders        │  → output/purchase-orders/po-*.json │
└─────────────────────┘                                     │
         │                                                  │
         ▼                                                  ▼
┌─────────────────────────────────────────────────────────────┐
│            generate-monitoring-report                       │  (agent: report-generator / Haiku)
│  Inventory health dashboard + trend highlights              │  → output/reports/monitoring-{date}.md
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────┐
│ compile-forecast-   │  (agent: report-generator / Haiku)
│      report         │  → output/reports/forecast-{date}.md
└─────────────────────┘
```

## Quick Start

```bash
cd examples/inventory-forecaster
ao daemon start

# Run the full demand forecasting pipeline
ao queue enqueue \
  --title "inventory-forecaster" \
  --description "Q1 2026 demand forecast run" \
  --workflow-ref demand-forecast

# Watch it run
ao daemon stream --pretty

# Run an accuracy audit (compare actuals vs previous forecast)
ao queue enqueue \
  --title "sku-health-audit" \
  --description "March 2026 accuracy audit" \
  --workflow-ref sku-health-audit
```

The pipeline runs automatically every Monday at 06:00 UTC via the `weekly-forecast-refresh` schedule.

## Agents

| Agent | Model | Role |
|---|---|---|
| **data-ingester** | claude-haiku-4-5 | Parses CSV/JSON sales files, normalizes records, validates schema |
| **trend-analyzer** | claude-sonnet-4-6 | Detects seasonal patterns, growth trends, anomalies using sequential-thinking |
| **demand-forecaster** | claude-sonnet-4-6 | Generates 90-day SKU forecasts, calculates EOQ/reorder points/safety stock |
| **procurement-reviewer** | claude-opus-4-6 | Decision gate — reviews forecast quality, classifies urgency, approves POs |
| **report-generator** | claude-haiku-4-5 | Produces markdown reports: forecast summaries, monitoring dashboards, accuracy audits |

## AO Features Demonstrated

| Feature | Where |
|---|---|
| **Command phases** | `ingest-sales-data` (validate-sales-data.sh), `scan-inventory` (scan-inventory.sh) |
| **Multi-agent pipeline** | 5 agents with distinct models and roles |
| **Decision contracts** | `review-reorder-urgency` with 4 verdicts: immediate/scheduled/monitor/rework |
| **Non-linear routing** | monitor verdict skips to generate-monitoring-report; rework loops back |
| **Rework loops** | Forecast rejected by reviewer → regenerate (max 2 attempts) |
| **Output contracts** | Structured JSON forecasts, reorder points, PO recommendations |
| **Scheduled workflows** | Weekly forecast refresh (Mondays 06:00 UTC), monthly accuracy audit |
| **Sequential-thinking** | trend-analyzer uses structured reasoning for ambiguous SKU patterns |
| **Model variety** | Haiku (ingestion/reporting), Sonnet (analysis/forecasting), Opus (review) |

## Directory Structure

```
inventory-forecaster/
├── .ao/workflows/
│   ├── agents.yaml              # 5 agent profiles
│   ├── phases.yaml              # 11 phases
│   ├── workflows.yaml           # 3 workflows
│   ├── mcp-servers.yaml         # filesystem + sequential-thinking
│   └── schedules.yaml           # weekly refresh, monthly audit
├── config/
│   ├── forecasting-params.yaml  # EOQ params, safety stock, confidence thresholds
│   ├── sku-categories.yaml      # Seasonality rules per category
│   └── supplier-catalog.yaml    # Suppliers, MOQs, lead times
├── data/
│   ├── sales-history/           # Input: raw sales CSV files (add yours here)
│   ├── normalized/              # Generated: unified-sales.json
│   ├── forecasts/               # Generated: trend-analysis.json, forecast-latest.json
│   ├── reorder-points/          # Generated: reorder-points.json, current-stock.json
│   └── audit/                   # Generated: inventory-scan files, accuracy comparisons
├── output/
│   ├── purchase-orders/         # Generated PO JSON files per supplier
│   └── reports/                 # Markdown reports (forecast, monitoring, accuracy)
├── scripts/
│   ├── validate-sales-data.sh   # CSV validation (header check, date/SKU format)
│   ├── generate-forecast-diff.sh # Forecast-to-forecast comparison
│   └── scan-inventory.sh        # Current stock scan for audit workflow
├── CLAUDE.md
└── README.md
```

## Requirements

**No external API keys required** — uses only:
- `@modelcontextprotocol/server-filesystem` (built-in, no key)
- `@modelcontextprotocol/server-sequential-thinking` (built-in, no key)

**Tools needed:**
- Node.js 18+ (for MCP servers via npx)
- Python 3.8+ (for data processing in command phases)
- AO daemon

## Adding Your Sales Data

Drop CSV files into `data/sales-history/` with this format:

```csv
date,sku,quantity,unit_price,channel,region
2026-01-15,WH-TOOL-1001,42,29.99,online,northeast
```

SKU format: `WH-[CATEGORY]-[NUMBER]` where category is `TOOL`, `ELEC`, `SAFE`, or `OUTD`.

## Customization

- **Add SKU categories**: Edit `config/sku-categories.yaml` with new prefix and seasonality profile
- **Add suppliers**: Edit `config/supplier-catalog.yaml` with MOQ and lead time
- **Adjust safety stock**: Change `safety_stock_multiplier` in `config/forecasting-params.yaml`
- **Change forecast horizon**: Change `forecast_horizon_days` (default: 90 days)
