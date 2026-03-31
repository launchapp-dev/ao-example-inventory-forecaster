#!/usr/bin/env bash
# validate-sales-data.sh
# Validates CSV structure of all sales data files before ingestion.
# Exits non-zero if any file fails validation.

set -euo pipefail

SALES_DIR="data/sales-history"
REQUIRED_COLUMNS="date,sku,quantity,unit_price,channel,region"
ERRORS=0

echo "=== Sales Data Validation ==="
echo "Scanning: $SALES_DIR"
echo ""

if [ ! -d "$SALES_DIR" ]; then
  echo "ERROR: Sales data directory not found: $SALES_DIR"
  exit 1
fi

CSV_FILES=$(find "$SALES_DIR" -name "*.csv" -type f | sort)

if [ -z "$CSV_FILES" ]; then
  echo "WARNING: No CSV files found in $SALES_DIR"
  echo "Add sales CSV files to $SALES_DIR before running the pipeline."
  exit 0
fi

for FILE in $CSV_FILES; do
  echo "Validating: $FILE"

  # Check file is non-empty
  if [ ! -s "$FILE" ]; then
    echo "  ERROR: File is empty"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Check header row
  HEADER=$(head -1 "$FILE" | tr -d '\r')
  if [ "$HEADER" != "$REQUIRED_COLUMNS" ]; then
    echo "  ERROR: Header mismatch"
    echo "    Expected: $REQUIRED_COLUMNS"
    echo "    Got:      $HEADER"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Count data rows (excluding header)
  ROW_COUNT=$(tail -n +2 "$FILE" | grep -c '.' || true)
  echo "  OK: $ROW_COUNT data rows"

  # Basic sanity: check for empty quantity or price fields
  EMPTY_FIELDS=$(tail -n +2 "$FILE" | awk -F',' '$3=="" || $4==""' | wc -l | tr -d ' ')
  if [ "$EMPTY_FIELDS" -gt 0 ]; then
    echo "  WARNING: $EMPTY_FIELDS rows with empty quantity or unit_price"
  fi

  # Check date format (expect YYYY-MM-DD)
  INVALID_DATES=$(tail -n +2 "$FILE" | awk -F',' '{ if ($1 !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) print NR+1": "$1 }' | head -5)
  if [ -n "$INVALID_DATES" ]; then
    echo "  WARNING: Non-ISO date formats detected (first 5):"
    echo "$INVALID_DATES" | sed 's/^/    /'
  fi

  # Check SKU format
  INVALID_SKUS=$(tail -n +2 "$FILE" | awk -F',' '{ if ($2 !~ /^WH-[A-Z]+-[0-9]+$/) print NR+1": "$2 }' | head -5)
  if [ -n "$INVALID_SKUS" ]; then
    echo "  WARNING: Non-standard SKU formats detected (first 5):"
    echo "$INVALID_SKUS" | sed 's/^/    /'
  fi
done

echo ""
echo "=== Validation Summary ==="
FILE_COUNT=$(echo "$CSV_FILES" | wc -l | tr -d ' ')
echo "Files checked: $FILE_COUNT"
echo "Errors: $ERRORS"

if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS file(s) have structural errors. Fix before proceeding."
  exit 1
fi

echo "PASSED: All sales data files are valid."
