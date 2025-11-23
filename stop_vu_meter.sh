#!/bin/sh

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="$SCRIPT_DIR/vu_meter.pid"

# Function to log with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_message "Stopping VU meter..."

# Check if PID file exists
if [ ! -f "$PIDFILE" ]; then
    log_message "PID file not found: $PIDFILE"
    log_message "Trying to find process by name..."
    PID=$(pgrep -f "bin/vu" | head -1)
    if [ -z "$PID" ]; then
        log_message "No VU meter process found"
        exit 0
    fi
else
    PID=$(cat "$PIDFILE" 2>/dev/null)
fi

if [ -z "$PID" ]; then
    log_message "No PID found"
    exit 1
fi

# Check if process is running
if ! kill -0 "$PID" 2>/dev/null; then
    log_message "Process $PID is not running (stale PID file)"
    rm -f "$PIDFILE"
    exit 0
fi

log_message "Stopping process $PID gracefully..."
kill -TERM "$PID" 2>/dev/null

# Wait for graceful shutdown (up to 5 seconds)
count=5
while kill -0 "$PID" 2>/dev/null && [ $count -gt 0 ]; do
    sleep 1
    count=$((count - 1))
done

# Check if still running
if kill -0 "$PID" 2>/dev/null; then
    log_message "Process did not stop gracefully, forcing stop..."
    kill -KILL "$PID" 2>/dev/null
    sleep 1
    log_message "Process stopped (force kill)"
else
    log_message "Process stopped gracefully"
fi

# Remove PID file
rm -f "$PIDFILE"
log_message "Done"

