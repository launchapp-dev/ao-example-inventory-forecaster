#!/usr/bin/env bash
# generate-forecast-diff.sh
# Compares the latest forecast against the previous one and prints a summary of changes.
# Used by compile-forecast-report to show forecast movement.

set -euo pipefail

FORECAST_DIR="data/forecasts"

echo "=== Forecast Diff Report ==="

# Find the two most recent forecast files (exclude trend-analysis.json)
FORECASTS=$(ls -t "$FORECAST_DIR"/forecast-*.json 2>/dev/null | head -2 || true)

if [ -z "$FORECASTS" ]; then
  echo "No previous forecasts found. This appears to be the first run."
  echo '{}'
  exit 0
fi

LATEST=$(echo "$FORECASTS" | head -1)
PREVIOUS=$(echo "$FORECASTS" | tail -1)

if [ "$LATEST" = "$PREVIOUS" ]; then
  echo "Only one forecast file found. No comparison available."
  echo '{}'
  exit 0
fi

echo "Latest:   $LATEST"
echo "Previous: $PREVIOUS"
echo ""

python3 - <<'PYEOF'
import json, sys, os

forecast_dir = "data/forecasts"
files = sorted([f for f in os.listdir(forecast_dir)
                if f.startswith("forecast-") and f.endswith(".json")], reverse=True)

if len(files) < 2:
    print("Only one forecast on file — no diff available.")
    print(json.dumps({"diff_available": False}))
    sys.exit(0)

latest_path = os.path.join(forecast_dir, files[0])
prev_path = os.path.join(forecast_dir, files[1])

with open(latest_path) as f:
    latest = json.load(f)
with open(prev_path) as f:
    previous = json.load(f)

latest_skus = {s["sku"]: s for s in latest.get("skus", [])}
prev_skus = {s["sku"]: s for s in previous.get("skus", [])}

diff = {
    "diff_available": True,
    "latest_date": latest.get("generated_at", ""),
    "previous_date": previous.get("generated_at", ""),
    "new_skus": [],
    "removed_skus": [],
    "changes": []
}

for sku, data in latest_skus.items():
    if sku not in prev_skus:
        diff["new_skus"].append(sku)
        continue
    prev = prev_skus[sku]
    old_f = prev.get("forecast_90d_units", 0)
    new_f = data.get("forecast_90d_units", 0)
    if old_f == 0:
        pct = None
    else:
        pct = round((new_f - old_f) / old_f * 100, 1)

    if pct is not None and abs(pct) >= 5.0:
        diff["changes"].append({
            "sku": sku,
            "prev_forecast": old_f,
            "new_forecast": new_f,
            "change_pct": pct,
            "direction": "up" if pct > 0 else "down",
            "prev_urgency": prev.get("urgency", "unknown"),
            "new_urgency": data.get("urgency", "unknown")
        })

for sku in prev_skus:
    if sku not in latest_skus:
        diff["removed_skus"].append(sku)

diff["changes"].sort(key=lambda x: abs(x["change_pct"]), reverse=True)
print(json.dumps(diff, indent=2))
PYEOF
