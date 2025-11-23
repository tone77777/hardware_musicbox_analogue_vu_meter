#!/bin/sh

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/start_vu_meter.log"
PIDFILE="$SCRIPT_DIR/vu_meter.pid"
PROGRAM="$SCRIPT_DIR/bin/vu"

# Default shared memory file (can be overridden)
SHM_FILE="${1:-/dev/shm/squeezelite-b8:27:eb:d3:0b:23}"

# Redirect all output to log file (for startup debugging)
exec >> "$LOG_FILE" 2>&1

# Function to log with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_message "=== Starting VU meter wrapper ==="
log_message "Script directory: $SCRIPT_DIR"
log_message "Shared memory file: $SHM_FILE"
log_message "User: $(whoami)"

# Check if program exists
if [ ! -f "$PROGRAM" ]; then
    log_message "ERROR: Program not found: $PROGRAM"
    log_message "Please compile it first with: make"
    exit 1
fi

# Make sure program is executable
chmod +x "$PROGRAM" 2>/dev/null

# Check if shared memory file exists
if [ ! -f "$SHM_FILE" ]; then
    log_message "WARNING: Shared memory file not found: $SHM_FILE"
    log_message "Squeezelite may not be running. The program will wait and exit if file doesn't appear."
fi

# Check if already running
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        log_message "Found existing VU meter process (PID: $OLD_PID)"
        log_message "Stopping existing process gracefully..."
        kill -TERM "$OLD_PID" 2>/dev/null
        
        # Wait for graceful shutdown (up to 5 seconds)
        count=5
        while kill -0 "$OLD_PID" 2>/dev/null && [ $count -gt 0 ]; do
            sleep 1
            count=$((count - 1))
        done
        
        # Check if still running
        if kill -0 "$OLD_PID" 2>/dev/null; then
            log_message "Process did not stop gracefully, forcing stop..."
            kill -KILL "$OLD_PID" 2>/dev/null
            sleep 1
            log_message "Process stopped (force kill)"
        else
            log_message "Process stopped gracefully"
        fi
    else
        log_message "Removing stale PID file"
        rm -f "$PIDFILE"
    fi
fi

# Change to script directory
cd "$SCRIPT_DIR" || {
    log_message "ERROR: Failed to change to directory: $SCRIPT_DIR"
    exit 1
}

# Start the program in background with quiet mode (no screen output)
log_message "Starting VU meter in quiet mode..."
log_message "Command: $PROGRAM -q $SHM_FILE"
"$PROGRAM" -q "$SHM_FILE" &
NEW_PID=$!

# Save PID
echo "$NEW_PID" > "$PIDFILE"
log_message "VU meter started with PID: $NEW_PID"

# Wait a moment to check if it's still running
sleep 2
if ! kill -0 "$NEW_PID" 2>/dev/null; then
    log_message "ERROR: VU meter process died immediately after starting"
    log_message "Check if WiringPi is available and GPIO 18 is free"
    rm -f "$PIDFILE"
    exit 1
fi

log_message "=== VU meter wrapper finished setup ==="
log_message "Program is running in background (quiet mode, GPIO output only)"

