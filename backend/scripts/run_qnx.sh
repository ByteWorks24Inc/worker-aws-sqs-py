#!/bin/bash

# =========================================================
# QNX / C EXECUTION SCRIPT (FINAL STABLE VERSION)
# =========================================================

# -----------------------------
# CONFIG
# -----------------------------
SOURCE_FILE="$1"
JOB_ID=$(basename "$SOURCE_FILE" .c)
EXEC_FILE="/tmp/qnx_exec_${JOB_ID}_$$"
OUTPUT_FILE="/tmp/qnx_output_${JOB_ID}.txt"
COMPILE_ERR="/tmp/qnx_compile_${JOB_ID}.txt"
LOG_PREFIX="[QNX-RUNNER]"

# -----------------------------
# LOG FUNCTION
# -----------------------------
log() {
    echo "$LOG_PREFIX $1"
}

# -----------------------------
# VALIDATION
# -----------------------------
log "Validating input..."

if [ -z "$SOURCE_FILE" ]; then
    echo "Error: No source file provided"
    exit 1
fi

if [ ! -f "$SOURCE_FILE" ]; then
    echo "Error: C file not found"
    exit 1
fi

log "Source file: $SOURCE_FILE"

# -----------------------------
# LOAD QNX ENV (OPTIONAL)
# -----------------------------
QNX_ENV="/home/utej/qnx800/qnxsdp-env.sh"

if [ -f "$QNX_ENV" ]; then
    log "Loading QNX environment..."
    source "$QNX_ENV"
else
    log "QNX environment not found, using local GCC"
fi

# -----------------------------
# LIMIT RESOURCES
# -----------------------------
log "Applying execution limits..."

ulimit -t 5        # CPU time (seconds)
ulimit -v 50000    # Memory (KB)
ulimit -f 1000     # Max output file size (~1MB, safer)

# -----------------------------
# CLEANUP OLD FILES
# -----------------------------
rm -f "$EXEC_FILE" "$OUTPUT_FILE" "$COMPILE_ERR"

# -----------------------------
# COMPILER SELECTION
# -----------------------------
if command -v qcc >/dev/null 2>&1; then
    COMPILER="qcc"
else
    COMPILER="gcc"
fi

# -----------------------------
# COMPILE
# -----------------------------
log "Compiling..."

$COMPILER -g "$SOURCE_FILE" -o "$EXEC_FILE" 2> "$COMPILE_ERR"
COMPILE_EXIT=$?

if [ $COMPILE_EXIT -ne 0 ]; then
    echo ""
    echo "========== COMPILATION ERROR =========="
    cat "$COMPILE_ERR"
    echo "======================================="
    rm -f "$EXEC_FILE"
    exit 1
fi

log "Compilation successful"

# -----------------------------
# EXECUTION (SAFE STREAMING)
# -----------------------------
log "Starting execution..."

timeout 5s stdbuf -o0 "$EXEC_FILE" > "$OUTPUT_FILE" 2>&1
EXIT_CODE=$?

echo ""
echo "========== PROGRAM OUTPUT =========="

# Show first 200 lines only
head -n 200 "$OUTPUT_FILE"

echo "==================================="

TOTAL_LINES=$(wc -l < "$OUTPUT_FILE")

if [ "$TOTAL_LINES" -gt 200 ]; then
    echo ""
    echo "...output truncated ($TOTAL_LINES lines total)"
fi

# -----------------------------
# HANDLE EXIT STATUS
# -----------------------------
if [ $EXIT_CODE -eq 124 ]; then
    echo ""
    echo "⚠️ Execution timed out (possible infinite loop)"

elif [ $EXIT_CODE -eq 153 ]; then
    echo ""
    echo "⚠️ Output limit exceeded (program printed too much data)"

elif [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "⚠️ Program exited with error code $EXIT_CODE"
fi

# -----------------------------
# CLEANUP
# -----------------------------
log "Cleaning up..."

rm -f "$EXEC_FILE" "$COMPILE_ERR"
# (keeping output file optional for debugging)

log "Execution finished"
