#!/bin/sh

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/start_vu_meter.log"
PIDFILE="$SCRIPT_DIR/vu_meter.pid"
PROGRAM="$SCRIPT_DIR/bin/vu"

# Parse command line options
QUIET_MODE=1  # Default to quiet mode
SHM_FILE=""
SHOW_OUTPUT=0

while [ $# -gt 0 ]; do
    case "$1" in
        -v|--verbose)
            QUIET_MODE=0
            SHOW_OUTPUT=1
            shift
            ;;
        -d|--debug)
            QUIET_MODE=0
            SHOW_OUTPUT=1
            DEBUG_MODE=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS] [shared_memory_file]"
            echo "Options:"
            echo "  -v, --verbose    Show VU meter output (progress bar)"
            echo "  -d, --debug      Show VU meter output in debug mode (numbers)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Quiet mode (background)"
            echo "  $0 -v                                 # Show output"
            echo "  $0 -d /dev/shm/squeezelite-XX:XX:XX  # Debug mode with custom file"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Use -h or --help for usage information" >&2
            exit 1
            ;;
        *)
            SHM_FILE="$1"
            shift
            ;;
    esac
done

# Default shared memory file if not provided
if [ -z "$SHM_FILE" ]; then
    SHM_FILE="/dev/shm/squeezelite-b8:27:eb:d3:0b:23"
fi

# Blank/wipe the log file on each startup
> "$LOG_FILE"

# Save original stdout/stderr before redirecting
exec 3>&1 4>&2

# Function to log with timestamp (always to log file)
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Redirect script's own stdout/stderr to log file
# (Program output will use original stdout if verbose/debug)
exec 1>> "$LOG_FILE" 2>&1

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

# Start the program in background
if [ "$QUIET_MODE" -eq 1 ]; then
    log_message "Starting VU meter in quiet mode (no screen output)..."
    log_message "Command: $PROGRAM -q $SHM_FILE"
    # In quiet mode, redirect output to log file
    "$PROGRAM" -q "$SHM_FILE" >> "$LOG_FILE" 2>&1 &
    NEW_PID=$!
elif [ "$DEBUG_MODE" -eq 1 ]; then
    log_message "Starting VU meter in debug mode (showing numbers)..."
    log_message "Command: $PROGRAM -d $SHM_FILE"
    # In debug mode, output goes to original stdout (terminal)
    "$PROGRAM" -d "$SHM_FILE" >&3 2>&3 &
    NEW_PID=$!
else
    log_message "Starting VU meter in verbose mode (showing progress bar)..."
    log_message "Command: $PROGRAM $SHM_FILE"
    # In verbose mode, output goes to original stdout (terminal)
    "$PROGRAM" "$SHM_FILE" >&3 2>&3 &
    NEW_PID=$!
fi

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
if [ "$QUIET_MODE" -eq 1 ]; then
    log_message "Program is running in background (quiet mode, GPIO output only)"
    log_message "To see output, use: $0 -v or $0 -d"
    # Print to original stdout (terminal)
    echo "VU meter started in quiet mode. Check $LOG_FILE for details." >&3
else
    log_message "Program is running in background (output visible in terminal)"
    # Print to original stdout (terminal)
    echo "VU meter started. Output will be visible in this terminal." >&3
    if [ "$DEBUG_MODE" -eq 1 ]; then
        echo "Debug mode: VU values will be printed as numbers." >&3
    else
        echo "Verbose mode: VU meter will show progress bar." >&3
    fi
fi

