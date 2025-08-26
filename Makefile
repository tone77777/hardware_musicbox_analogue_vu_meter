# Makefile for Hardware Music Box Analogue VU Meter

CC = gcc
CFLAGS = -Wall -Wextra -std=c99
LDFLAGS = -lasound -lwiringPi
TARGET = bin/vu
SOURCE = src/vu.c

# Default target
all: $(TARGET)

# Build the executable
$(TARGET): $(SOURCE)
	@mkdir -p bin
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCE) $(LDFLAGS)
	@echo "Built $(TARGET)"

# Clean build artifacts
clean:
	rm -rf bin/
	@echo "Cleaned build artifacts"

# Install (copy to system path)
install: $(TARGET)
	sudo cp $(TARGET) /usr/local/bin/
	@echo "Installed to /usr/local/bin/"

# Uninstall
uninstall:
	sudo rm -f /usr/local/bin/vu
	@echo "Uninstalled from /usr/local/bin/"

# Run the VU meter
run: $(TARGET)
	./$(TARGET)

# Show help
help:
	@echo "Available targets:"
	@echo "  all      - Build the VU meter (default)"
	@echo "  clean    - Remove build artifacts"
	@echo "  install  - Install to /usr/local/bin/"
	@echo "  uninstall- Remove from /usr/local/bin/"
	@echo "  run      - Build and run the VU meter"
	@echo "  help     - Show this help"

.PHONY: all clean install uninstall run help 