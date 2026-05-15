#!/bin/bash
set -euo pipefail

# Learning session log organizer
# Fires on every Stop event. Checks for active learning session marker.
# If active and not recently logged, blocks Claude to write learning log.

MARKER="$CLAUDE_PROJECT_DIR/.k8s-learning-session"
LOGGED="$CLAUDE_PROJECT_DIR/.k8s-learning-logged"

# No active learning session → approve immediately (zero overhead)
if [ ! -f "$MARKER" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Check cooldown: if logged within last 60 seconds, approve (prevents loop)
NOW=$(date +%s)
if [ -f "$LOGGED" ]; then
  LAST=$(cat "$LOGGED" 2>/dev/null || echo "0")
  DIFF=$((NOW - LAST))
  if [ "$DIFF" -lt 60 ]; then
    echo '{"decision": "approve"}'
    exit 0
  fi
fi

# Active session, not recently logged → block and instruct
echo "$NOW" > "$LOGGED"

STAGE=$(cat "$MARKER")
DATE=$(date +%Y-%m-%d)
LOG_DIR=".claude-plugin/logs"
LOG_FILE="${LOG_DIR}/${STAGE}-session-${DATE}.md"

# Use jq for clean JSON if available, fallback to printf
if command -v jq &>/dev/null; then
  jq -n \
    --arg logFile "$LOG_FILE" \
    --arg stage "$STAGE" \
    '{
      decision: "block",
      reason: "Organize learning log",
      systemMessage: ("Active K8s learning session (" + $stage + "). Before stopping, organize the learning log:\n\n1. Summarize key concepts discussed and Q&A from this exchange\n2. Append the summary to " + $logFile + " (create the file if it does not exist)\n3. Use a timestamped heading (## HH:MM) for this entry\n4. Format: bullet points for key concepts, indented sub-bullets for Q&A pairs\n\nAfter writing the log entry, you may stop.")
    }'
else
  printf '{"decision":"block","reason":"Organize learning log","systemMessage":"Active K8s learning session (%s). Before stopping, organize the learning log: (1) Summarize key concepts and Q&A from this exchange. (2) Append to %s (create if needed). (3) Use a timestamped heading (## HH:MM). (4) Bullet points for concepts, indented Q&A. After writing, you may stop."}' "$STAGE" "$LOG_FILE"
fi

exit 0
