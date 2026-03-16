#!/bin/bash

############################################
# Usage:
# ./run_qnx.sh /path/to/main.c
############################################

C_FILE=$1

if [ -z "$C_FILE" ]; then
    echo "Usage: ./run_qnx.sh <path_to_c_file>"
    exit 1
fi

if [ ! -f "$C_FILE" ]; then
    echo "Error: C file not found"
    exit 1
fi

############################################
# CONFIGURATION
############################################

# Windows project path (WSL mount path)
WIN_PROJECT="/mnt/c/Users/Utej/ide-8.0-workspace/Demo"

# Windows path for cmd.exe
WIN_PROJECT_CMD="C:\\Users\\Utej\\ide-8.0-workspace\\Demo"

# QNX environment batch file
WIN_ENV_CMD="C:\\Users\\Utej\\qnx800\\env_full.bat"

# QNX VM details
VM_IP="192.168.174.128"
VM_USER="root"
VM_TARGET="/tmp/Demo"

# Deterministic binary path (avoid random find issues)
BINARY="$WIN_PROJECT/build/x86_64-debug/Demo"

LOGFILE="/tmp/qnx_execution.log"

############################################
# START
############################################

echo "===== QNX EXECUTION STARTED =====" > "$LOGFILE"

############################################
# 1️⃣ Replace Demo.c
############################################

echo "Replacing source file..." >> "$LOGFILE"

cp "$C_FILE" "$WIN_PROJECT/src/Demo.c" >> "$LOGFILE" 2>&1

if [ $? -ne 0 ]; then
    echo "Failed to copy source file" >> "$LOGFILE"
    cat "$LOGFILE"
    exit 1
fi

echo "Source replaced successfully" >> "$LOGFILE"

############################################
# 2️⃣ Build using Windows QNX toolchain
############################################

echo "Building project on Windows..." >> "$LOGFILE"

cmd.exe /C "cd /d $WIN_PROJECT_CMD && call $WIN_ENV_CMD && make clean && make" >> "$LOGFILE" 2>&1

if [ $? -ne 0 ]; then
    echo "Build failed" >> "$LOGFILE"
    cat "$LOGFILE"
    exit 1
fi

echo "Build successful" >> "$LOGFILE"

############################################
# 3️⃣ Verify binary exists
############################################

if [ ! -f "$BINARY" ]; then
    echo "Binary not found at expected location: $BINARY" >> "$LOGFILE"
    cat "$LOGFILE"
    exit 1
fi

echo "Binary located successfully" >> "$LOGFILE"

############################################
# 4️⃣ Copy binary to VM
############################################

echo "Copying binary to VM..." >> "$LOGFILE"

scp "$BINARY" $VM_USER@$VM_IP:$VM_TARGET >> "$LOGFILE" 2>&1

if [ $? -ne 0 ]; then
    echo "SCP failed" >> "$LOGFILE"
    cat "$LOGFILE"
    exit 1
fi

echo "Binary copied successfully" >> "$LOGFILE"

############################################
# 5️⃣ Execute safely on VM
############################################

echo "Executing program on VM..." >> "$LOGFILE"

OUTPUT=$(timeout 10s ssh $VM_USER@$VM_IP \
"chmod +x $VM_TARGET && timeout 5s $VM_TARGET 2>&1 | head -n 200")

echo "===== PROGRAM OUTPUT =====" >> "$LOGFILE"
echo "$OUTPUT" >> "$LOGFILE"

############################################
# 6️⃣ Done
############################################

echo "===== EXECUTION FINISHED =====" >> "$LOGFILE"

cat "$LOGFILE"
