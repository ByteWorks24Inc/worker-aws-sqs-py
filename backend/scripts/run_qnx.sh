#!/bin/bash

# -----------------------------
# CONFIG
# -----------------------------
SOURCE_FILE="$1"
OUTPUT_FILE="/tmp/qnx_exec_$$"

# -----------------------------
# VALIDATION
# -----------------------------
if [ ! -f "$SOURCE_FILE" ]; then
    echo "Error: C file not found"
    exit 1
fi

# -----------------------------
# (OPTIONAL) LOAD QNX ENV
# -----------------------------
if [ -f "/home/utej/qnx800/qnxsdp-env.sh" ]; then
    source /home/utej/qnx800/qnxsdp-env.sh
fi

# -----------------------------
# LIMITS (important)
# -----------------------------
ulimit -t 5        # max CPU time (seconds)
ulimit -v 50000    # max memory (KB)

# -----------------------------
# COMPILE
# -----------------------------
gcc "$SOURCE_FILE" -o "$OUTPUT_FILE"

if [ $? -ne 0 ]; then
    echo "Compilation Error"
    exit 1
fi

# -----------------------------
# RUN WITH TIMEOUT + NO BUFFER
# -----------------------------
timeout 5s stdbuf -o0 "$OUTPUT_FILE"

EXIT_CODE=$?

# -----------------------------
# HANDLE TIMEOUT
# -----------------------------
if [ $EXIT_CODE -eq 124 ]; then
    echo ""
    echo "⚠️ Execution timed out (possible infinite loop)"
fi

# -----------------------------
# CLEANUP
# -----------------------------
rm -f "$OUTPUT_FILE"
