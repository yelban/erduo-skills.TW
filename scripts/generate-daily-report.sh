#!/bin/bash
set -e

PROJECT_DIR="/Users/orz99/zoo/erduo-skills.TW"
LOG_DIR="$PROJECT_DIR/logs"
DATE=$(date +%Y-%m-%d)

mkdir -p "$LOG_DIR"

{
  echo "=== Start: $(date) ==="
  cd "$PROJECT_DIR"

  claude -p "生成今天的日報" \
    --output-format json \
    --max-turns 25

  echo "=== End: $(date) ==="
} 2>&1 | tee "$LOG_DIR/$DATE-report.log"
