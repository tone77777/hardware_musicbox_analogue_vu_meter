# Hardware Music Box Analogue VU Meter: Antonio

A hardware-based VU (Volume Unit) meter project for audio visualization using analogue components and a Raspberry Pi.

## Important Notes

- **Root Required**: The program must run with `sudo` for GPIO access
- **Squeezelite Dependency**: Squeezelite must be running and creating the shared memory file
- **GPIO Pin**: Uses GPIO 13 (BCM numbering) for PWM output - make sure nothing else is using this pin
- **File Location**: The pi zero through pcp may be expecting the executable at `scripts/vu` - adjust paths as needed 

## Overview

This project implements a VU meter that displays audio levels using analogue hardware components, controlled by software running on a Raspberry Pi. The VU meter provides real-time visual feedback of audio input levels.

## Project Structure

```
hardware_musicbox_analogue_vu_meter/
├── src/                      # Source code
│   └── vu.c                 # C source code for VU meter
├── bin/                      # Compiled executables (not in git)
│   └── vu                   # Compiled VU meter
├── start_vu_meter.sh        # Startup script (for background/daemon mode)
├── stop_vu_meter.sh         # Stop script
├── README.md                # This file
├── Makefile                 # Build configuration
├── .gitignore              # Git ignore rules
└── LICENSE                 # Project license
```

## Features

- Real-time audio level monitoring from Squeezelite shared memory
- GPIO PWM output to drive analogue VU meter hardware
- Silent/quiet mode for background/daemon operation
- Automatic graceful shutdown if Squeezelite is not running
- Startup/stop scripts for easy management
- C-based implementation for performance

## Requirements

### Hardware
- Raspberry Pi (tested on Raspberry Pi Zero W with piCorePlayer)
- Squeezelite player running (creates shared memory file)
- Analogue VU meter connected to GPIO 13 (PWM output)
- Power supply

### Hardware Connection
GPIO 13 (PWM) ----[ 10kΩ ]-----+----> VU Meter (+)
|
[10µF capacitor]
|
GND ------> VU Meter (−)

**Note:** GPIO 13 is used for hardware PWM output. The PWM signal is filtered through a 10µF capacitor and 10kΩ resistor to create a smooth DC voltage for the VU meter.

### Software
- GCC compiler
- WiringPi library (`wiringpi-tcz` on piCorePlayer)
- Squeezelite player (must be running to create shared memory file)
- Math library (linked automatically with `-lm`)

## Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd hardware_musicbox_analogue_vu_meter
   ```

2. Build the VU meter software:
   ```bash
   make
   ```

   This will create `bin/vu` executable.

3. Make startup scripts executable:
   ```bash
   chmod +x start_vu_meter.sh stop_vu_meter.sh
   ```

## Usage

### How It Works

The VU meter reads raw PCM audio data from Squeezelite's shared memory file (`/dev/shm/squeezelite-<MAC-ADDRESS>`). It calculates the RMS (Root Mean Square) audio level and outputs a PWM signal on GPIO 13 proportional to the volume level.

### Finding Your Squeezelite Shared Memory File

First, find your Squeezelite player's MAC address and shared memory file:

```bash
ls -la /dev/shm/squeezelite-*
```

This will show files like: `/dev/shm/squeezelite-b8:27:eb:d3:0b:23`

### Running the VU Meter

#### Option 1: Interactive Mode (with screen output)

**Normal mode** (shows progress bar):
```bash
sudo ./bin/vu /dev/shm/squeezelite-b8:27:eb:d3:0b:23
```

**Debug mode** (shows VU values as numbers):
```bash
sudo ./bin/vu -d /dev/shm/squeezelite-b8:27:eb:d3:0b:23
```

#### Option 2: Background/Daemon Mode (recommended for startup)

**Using the startup script** (quiet mode, no screen output):
```bash
sudo ./start_vu_meter.sh
```

Or with a custom shared memory file:
```bash
sudo ./start_vu_meter.sh /dev/shm/squeezelite-<your-mac-address>
```

**Manually in quiet mode**:
```bash
sudo ./bin/vu -q /dev/shm/squeezelite-b8:27:eb:d3:0b:23 &
```

#### Stopping the VU Meter

```bash
sudo ./stop_vu_meter.sh
```

Or manually:
```bash
# Find the process
pgrep -f "bin/vu"

# Kill it
sudo kill <PID>
```

### Command-Line Options

```
Usage: vu [OPTIONS] <pcm_file>

Options:
  -d, --debug    Debug mode (print VU values as numbers)
  -q, --quiet    Quiet mode (no screen output, GPIO only)
  -h, --help     Show help message
```

### Adding to Startup (piCorePlayer)

To start the VU meter automatically on boot:

1. Edit `/opt/bootlocal.sh`:
   ```bash
   sudo vi /opt/bootlocal.sh
   ```

2. Add this line (adjust path as needed):
   ```bash
   /home/tc/scripts/hardware_musicbox_analogue_vu_meter/start_vu_meter.sh &
   ```

3. Make it persistent:
   ```bash
   sudo filetool.sh -b
   ```

### Behavior

- **Updates every 30ms**: Reads audio data and updates GPIO PWM output
- **Silence detection**: If audio level is constant for 3 samples, sets output to 0
- **Graceful shutdown**: If Squeezelite shared memory file is not found after 10 attempts (~3 seconds), exits gracefully
- **GPIO output**: PWM signal on GPIO 13, range 0-500 (0-100% VU level)

## Hardware Setup

### GPIO Configuration

- **GPIO Pin**: 13 (BCM numbering)
- **Mode**: PWM output
- **PWM Range**: 0-2000
- **PWM Clock**: 192
- **Max PWM Value**: 500 (25% of range = 100% VU level)

### VU Meter Connection

Connect your analogue VU meter to GPIO 13 through a low-pass filter:

```
GPIO 13 (PWM) ----[ 10kΩ resistor ]-----+----> VU Meter (+)
                                         |
                                    [10µF capacitor]
                                         |
GND -------------------------------------+----> VU Meter (−)
```

The resistor and capacitor form a low-pass filter that converts the PWM signal to a smooth DC voltage proportional to the audio level.

### Calibration

The VU meter uses a scaling factor of 2.5x (defined as `VU_SCALE_FACTOR` in the code). You can adjust this in `src/vu.c` if needed:

```c
#define VU_SCALE_FACTOR 2.5  // Adjust this to calibrate sensitivity
```

## Development

### Building from Source

```bash
make
```

Or manually:
```bash
gcc -Wall -Wextra -std=c99 -o bin/vu src/vu.c -lasound -lwiringPi -lm
```

### Debugging

**Enable debug output:**
```bash
sudo ./bin/vu -d /dev/shm/squeezelite-b8:27:eb:d3:0b:23
```

**Check if process is running:**
```bash
ps aux | grep vu
pgrep -f "bin/vu"
```

**Check startup log:**
```bash
cat start_vu_meter.log
```

**Common Issues:**

1. **"Could not open shared memory file"**: Squeezelite is not running or MAC address is wrong
2. **"WiringPi setup failed"**: WiringPi library not loaded (`tce-load -i wiringpi-tcz`)
3. **GPIO not working**: Need root privileges (`sudo`)
4. **No PWM output**: Check GPIO 13 is not used by another process

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Raspberry Pi Foundation for the hardware platform
- ALSA project for audio libraries
- Open source community for inspiration and tools

## Support

For issues and questions, please open an issue on the project repository. 