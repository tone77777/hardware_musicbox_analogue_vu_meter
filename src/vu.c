/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.

to compile: 
gcc -o vu vu.c -lasound -lwiringPi  -lm]
to run: sudo ./vu /dev/shm/squeezelite-b8:27:eb:d3:0b:23
*/

#define VUMETER_DEFAULT_SAMPLE_WINDOW 1024 * 2

// Standalone C function to calculate average VU from stereo PCM data
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h>
#include <wiringPi.h>
#include <string.h>

// Set the interval (in milliseconds) between VU calculations
#define VU_INTERVAL_MS 30
// Set the scaling factor for the VU output
#define VU_SCALE_FACTOR 2.5

#define GPIO_PIN 18
#define PWM_RANGE 2000
#define PWM_CLOCK 192
#define MAX_PWM 500

// Function to set GPIO PWM level (0-2000)
void set_gpio_level(int level) {
    if (level < 0) level = 0;
    if (level > MAX_PWM) level = MAX_PWM;
    pwmWrite(GPIO_PIN, level);
}

long long calculate_vu_average(const int16_t *buffer, size_t num_frames) {
    long long sample_accumulator[2] = {0, 0};
    int16_t sample;
    int32_t sample_sq;
    size_t i;

    for (i = 0; i < num_frames; i++) {
        sample = buffer[i * 2];
        sample_sq = sample * sample;
        sample_accumulator[0] += sample_sq;

        sample = buffer[i * 2 + 1];
        sample_sq = sample * sample;
        sample_accumulator[1] += sample_sq;
    }

    if (num_frames > 0) {
        sample_accumulator[0] /= num_frames;
        sample_accumulator[1] /= num_frames;
    }

    // Return the average of left and right
    return (sample_accumulator[0] + sample_accumulator[1]) / 2;
}

// Converts average squared value to normalized VU (0-100)
int convert_and_normalise(long long avg_sq) {
    double rms = sqrt((double)avg_sq);
    int vu_percent = (int)(rms * 100 / 32767);
    if (vu_percent > 100) vu_percent = 100;
    if (vu_percent < 0) vu_percent = 0;
    return vu_percent;
}

int is_playing() {
    FILE *fp = popen("pcp mode", "r");
    if (!fp) return 0;
    char buf[32];
    if (fgets(buf, sizeof(buf), fp) != NULL) {
        pclose(fp);
        // Remove trailing newline
        buf[strcspn(buf, "\r\n")] = 0;
        return strcmp(buf, "play") == 0;
    }
    pclose(fp);
    return 0;
}

void loop_vu(const char *filename, int debug_mode) {
    // WiringPi setup
    if (wiringPiSetupGpio() == -1) {
        printf("WiringPi setup failed\n");
        return;
    }
    pinMode(GPIO_PIN, PWM_OUTPUT);
    pwmSetMode(PWM_MODE_MS);
    pwmSetClock(PWM_CLOCK);
    pwmSetRange(PWM_RANGE);

    int last_values[3] = {-1, -1, -1};
    int silence_mode = 0;
    int value_index = 0;
    int consecutive_failures = 0;
    const int MAX_CONSECUTIVE_FAILURES = 10;  // Exit after 10 consecutive failures (~300ms * 10 = 3 seconds)

    while (1) {
        FILE *f = fopen(filename, "rb");
        if (!f) {
            consecutive_failures++;
            if (consecutive_failures >= MAX_CONSECUTIVE_FAILURES) {
                printf("ERROR: Could not open %s after %d attempts\n", filename, MAX_CONSECUTIVE_FAILURES);
                printf("Squeezelite may not be running or the shared memory file doesn't exist.\n");
                printf("Exiting gracefully...\n");
                set_gpio_level(0);  // Turn off VU meter
                return;  // Exit gracefully
            }
            // Only print error every few attempts to avoid spam
            if (consecutive_failures == 1 || consecutive_failures % 5 == 0) {
                printf("Warning: Could not open %s (attempt %d/%d)\n", 
                       filename, consecutive_failures, MAX_CONSECUTIVE_FAILURES);
            }
            set_gpio_level(0);
            usleep(VU_INTERVAL_MS * 1000);
            continue;
        }
        
        // Reset failure counter on successful open
        consecutive_failures = 0;

        fseek(f, 0, SEEK_END);
        long filesize = ftell(f);
        fseek(f, 0, SEEK_SET);
        size_t num_frames = filesize / 4;
        int16_t *buffer = malloc(filesize);
        if (!buffer) {
            printf("Memory allocation failed\n");
            fclose(f);
            set_gpio_level(0);
            usleep(VU_INTERVAL_MS * 1000);
            continue;
        }
        size_t read = fread(buffer, 1, filesize, f);
        fclose(f);
        if (read != filesize) {
            printf("File read error\n");
            free(buffer);
            set_gpio_level(0);
            usleep(VU_INTERVAL_MS * 1000);
            continue;
        }
        long long vu = calculate_vu_average(buffer, num_frames);
        int vu_normalised = convert_and_normalise(vu);
        int vu_scaled = (int)(vu_normalised * VU_SCALE_FACTOR);
        if (vu_scaled > 100) vu_scaled = 100;
        if (vu_scaled < 0) vu_scaled = 0;

        // Track last 3 values
        last_values[value_index] = vu_scaled;
        value_index = (value_index + 1) % 3;

        // Check if we have 3 values and they're all the same
        if (last_values[0] != -1 && last_values[1] != -1 && last_values[2] != -1) {
            if (last_values[0] == last_values[1] && last_values[1] == last_values[2]) {
                silence_mode = 1;
            } else {
                silence_mode = 0;
            }
        }

        // Use 0 if in silence mode, otherwise use the calculated value
        int output_vu = silence_mode ? 0 : vu_scaled;

        // Set GPIO level based on output value
        int pwm_level = output_vu * MAX_PWM / 100;
        set_gpio_level(pwm_level);

        // Output
        if (debug_mode) {
            printf("%d\n", output_vu);
        } else {
            printf("[%-100.*s] %3d\r", output_vu, "####################################################################################################", output_vu);
            fflush(stdout);
        }
        free(buffer);
        usleep(VU_INTERVAL_MS * 1000);
    }
    set_gpio_level(0); // Ensure off at exit
}

int main(int argc, char *argv[]) {
    int debug_mode = 0;
    const char *filename = NULL;
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-d") == 0) {
            debug_mode = 1;
        } else {
            filename = argv[i];
        }
    }
    if (!filename) {
        printf("Usage: %s [-d] <pcm_file>\n", argv[0]);
        return 1;
    }
    // Pass debug_mode to loop_vu
    loop_vu(filename, debug_mode);
    return 0;
}
