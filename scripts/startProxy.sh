#!/bin/bash
# startProxy.sh
# Starts the Minecraft Proxy server in the background and persists output to logs

# Get the script's directory and move to proxy root
SCRIPT_DIR="$(dirname "$0")"
cd "$SCRIPT_DIR/../proxy"

# Define log file
LOG_FILE="proxy_output.log"

echo "=================================================="
echo "Starting Minecraft Proxy..."
echo "Date: $(date)"
echo "Logs will be written to: $(pwd)/$LOG_FILE"
echo "=================================================="

# Stop any existing processes (optional, requires searching nicely)
# Check if it is running? (Simplistic check)
# ps aux | grep "src/index.js" | grep -v grep

# Start with nohup
nohup npm start > "$LOG_FILE" 2>&1 &
PID=$!

echo "Proxy is running with PID: $PID"
echo "To follow the logs, run: tail -f proxy/$LOG_FILE"
echo "To stop the proxy, run: kill $PID"
