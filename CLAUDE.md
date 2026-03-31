# Inventory Demand Forecaster — Agent Context

This is a retail inventory demand forecasting pipeline. It ingests historical sales data,
detects seasonal patterns, generates 90-day demand forecasts per SKU, calculates reorder
points, and produces purchase order recommendations for warehouse procurement teams.

## What This Project Does

The `demand-forecast` workflow:
1. **ingest-sales-data** (command): Validates CSV structure with validate-sales-data.sh
2. **normalize-data** (data-ingester): Parses all CSVs in data/sales-history/ into unified-sales.json
3. **analyze-trends** (trend-analyzer): Detects seasonal patterns, growth trends, anomalies per SKU
4. **generate-forecasts** (demand-forecaster): Produces 90-day forecasts + EOQ reorder points
5. **review-reorder-urgency** (procurement-reviewer): Decision gate — approves or rejects forecast
6. **generate-purchase-orders** (demand-forecaster): Finalizes PO JSON per supplier (if orders needed)
7. **generate-monitoring-report** (report-generator): Health dashboard (always runs)
8. **compile-forecast-report** (report-generator): Full markdown report for warehouse managers

## Routing Logic

The `review-reorder-urgency` phase is the decision gate:
- `immediate` → advance to generate-purchase-orders (rush orders needed NOW)
- `scheduled` → advance to generate-purchase-orders (standard batch orders)
- `monitor` → skip to generate-monitoring-report (all inventory healthy, no orders)
- `rework` → go back to generate-forecasts (max 2 rework attempts)

## Data Flow

```
data/sales-history/*.csv
  → data/normalized/unified-sales.json          (normalize-data)
  → data/forecasts/trend-analysis.json          (analyze-trends)
  → data/forecasts/forecast-latest.json         (generate-forecasts)
  → data/reorder-points/reorder-points.json     (generate-forecasts)
  → output/purchase-orders/po-draft-{date}.json (generate-forecasts)
  → output/purchase-orders/po-{supplier}-{date}.json (generate-purchase-orders)
  → output/reports/monitoring-{date}.md         (generate-monitoring-report)
  → output/reports/forecast-{date}.md           (compile-forecast-report)
```

## SKU Categories and Business Rules

SKUs follow the format `WH-[CATEGORY]-[NUMBER]`:
- **WH-TOOL-***: Tools — low seasonality, 14-day lead time (Acme Tool Supply)
- **WH-ELEC-***: Electronics — high seasonality, Q4 spike +40%, 21-day lead time (Volt Electronics)
- **WH-SAFE-***: Safety equipment — **CRITICAL**, flat demand, NEVER stockout, 7-day lead time
- **WH-OUTD-***: Outdoor gear — high seasonality, summer spike +60%, 28-day lead time

Critical rule: WH-SAFE-* SKUs must always have a minimum of 3 months of supply.
The procurement-reviewer must NEVER approve a "monitor" verdict when any WH-SAFE-* SKU
is at or below its reorder point.

## Forecast Methodology

- Base demand: average daily units over historical period
- Seasonal adjustment: multiply by category seasonal factors (from sku-categories.yaml)
- Trend adjustment: apply monthly growth/decline rate
- Confidence intervals: ±10% (high), ±20% (medium), ±35% (low)
- Safety stock: safety_stock_multiplier × σ_demand × √lead_time_days
- Reorder point: (avg_daily_demand × lead_time_days) + safety_stock
- EOQ: √(2 × annual_demand × order_cost / holding_cost_rate)

Parameters are in config/forecasting-params.yaml.

## Configuration Files

- `config/forecasting-params.yaml` — Core algorithm parameters (EOQ costs, multipliers, thresholds)
- `config/sku-categories.yaml` — Category definitions, seasonality profiles, lead times
- `config/supplier-catalog.yaml` — Supplier names, MOQs, lead times, payment terms

## Output Files

- `output/purchase-orders/po-draft-{date}.json` — Draft PO consolidated across all suppliers
- `output/purchase-orders/po-{supplier}-{date}.json` — One finalized PO file per supplier
- `output/reports/forecast-{date}.md` — Full forecast report for warehouse managers
- `output/reports/monitoring-{date}.md` — Inventory health dashboard
- `output/reports/accuracy-{date}.md` — Forecast accuracy audit (sku-health-audit workflow only)
- `data/audit-log.json` — Append-only run history (never truncate or overwrite)

## Extending This Pipeline

- **Add Slack notifications**: Add `@modelcontextprotocol/server-slack` to mcp-servers.yaml and
  a `notify-procurement` phase that posts a summary after compile-forecast-report
- **Connect to real ERP**: Replace current-stock.json with a `@modelcontextprotocol/server-postgres`
  query to fetch live inventory counts from your warehouse database
- **Add more SKU categories**: Edit config/sku-categories.yaml with prefix and seasonality settings
- **Add external signals**: Use `@modelcontextprotocol/server-fetch` in trend-analyzer to pull
  holiday calendar data or weather forecasts for outdoor gear predictions
