#!/bin/bash
# Playwright MCP launcher with session isolation
# Each invocation gets a unique user-data-dir to prevent browser conflicts
# when multiple Claude Code sessions run in parallel.

SLOT="${PLAYWRIGHT_SLOT:-auto}"
BASE_DIR="/tmp/playwright-mcp-sessions"
mkdir -p "$BASE_DIR"

# Cleanup: remove dirs older than 24 hours
find "$BASE_DIR" -maxdepth 1 -type d -name "pw-*" -mmin +1440 -exec rm -rf {} + 2>/dev/null

if [ "$SLOT" = "auto" ]; then
  # Auto mode: generate unique dir from PID + timestamp
  SESSION_DIR="$BASE_DIR/pw-$$-$(date +%s)"
else
  # Slot mode: use fixed numbered slot (for named instances)
  SESSION_DIR="$BASE_DIR/pw-slot-$SLOT"
fi

mkdir -p "$SESSION_DIR"

exec npx @playwright/mcp@latest --isolated --user-data-dir "$SESSION_DIR" "$@"
