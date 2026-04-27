#!/bin/bash

# =========================================================
# QNX / C EXECUTION SCRIPT (SAFE + DEBUGGABLE VERSION)
# =========================================================

# -----------------------------
# CONFIG
# -----------------------------
SOURCE_FILE="$1"
JOB_ID=$(basename "$SOURCE_FILE" .c)
EXEC_FILE="/tmp/qnx_exec_${JOB_ID}_$$"
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
# LIMIT RESOURCES (SANDBOX)
# -----------------------------
log "Applying execution limits..."

ulimit -t 5        # CPU time limit (seconds)
ulimit -v 50000    # Memory limit (KB)
ulimit -f 1000     # Max file size

# -----------------------------
# CLEAN OLD EXEC (if exists)
# -----------------------------
rm -f "$EXEC_FILE"

# -----------------------------
# COMPILE
# -----------------------------
log "Compiling..."

# Use qcc if available, else fallback to gcc
if command -v qcc >/dev/null 2>&1; then
    COMPILER="qcc"
else
    COMPILER="gcc"
fi

$COMPILER "$SOURCE_FILE" -o "$EXEC_FILE" 2> /tmp/compile_err.txt

if [ $? -ne 0 ]; then
    log "Compilation failed"
    cat /tmp/compile_err.txt
    rm -f "$EXEC_FILE"
    exit 1
fi

log "Compilation successful"

# -----------------------------
# EXECUTION (IMPORTANT PART)
# -----------------------------
log "Starting execution..."

# Use timeout + stdbuf to:
# - prevent infinite loop
# - force immediate output

EXEC_OUTPUT=$(timeout 5s stdbuf -o0 "$EXEC_FILE" 2>&1)
EXIT_CODE=$?

# -----------------------------
# HANDLE RESULTS
# -----------------------------
echo ""
echo "========== PROGRAM OUTPUT =========="

echo "$EXEC_OUTPUT"

echo "==================================="

# -----------------------------
# TIMEOUT / RUNTIME HANDLING
# -----------------------------
if [ $EXIT_CODE -eq 124 ]; then
    echo ""
    echo "⚠️ Execution timed out (possible infinite loop)"
elif [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "⚠️ Program exited with error code $EXIT_CODE"
fi

# -----------------------------
# CLEANUP
# -----------------------------
log "Cleaning up..."

rm -f "$EXEC_FILE"
rm -f /tmp/compile_err.txt

log "Execution finished"
