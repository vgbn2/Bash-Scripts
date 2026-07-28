#!/bin/bash

# SET YOUR ALERT TEMPERATURE HERE (in degrees Celsius)
THRESHOLD=73

while true; do
    # Extract the current temperature of your NVIDIA GPU
    CURRENT_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)

    # Fallback to CPU sensor if NVIDIA stats are idling
    if [ -z "$CURRENT_TEMP" ]; then
        CURRENT_TEMP=$(sensors | grep -i "package id 0" | awk '{print $4}' | tr -d '+°C' | cut -d. -f1)
    fi

    # Check if temperature exceeds threshold
    if [ "$CURRENT_TEMP" -gt "$THRESHOLD" ]; then
        # Send visual desktop notification
        notify-send -u critical "⚠️ HARDWARE THERMAL ALERT" "Your hardware has hit ${CURRENT_TEMP}°C! Consider capping your FPS."

        # Play an audio system alert tone (system sound path)
        paplay /usr/share/sounds/sound-theme-freedesktop/stereo/alarm-clock-elapsed.oga 2>/dev/null
    fi

    # Wait 10 seconds before checking hardware states again
    sleep 10
done
