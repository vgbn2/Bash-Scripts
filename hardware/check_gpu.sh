#!/bin/bash

# Ensure GUI notifications work when triggered by cron
export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

LOG_FILE="$HOME/.gpu_health.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "=== GPU Health Check: $DATE ===" >> "$LOG_FILE"

# Test 1: NVIDIA Module Loaded
if ! lsmod | grep -q "^nvidia "; then
    echo "CRITICAL: NVIDIA kernel module is NOT loaded!" >> "$LOG_FILE"
    notify-send -u critical "GPU Warning" "NVIDIA kernel module is NOT loaded!" 2>/dev/null || true
    exit 1
fi

# Test 2: Check for Open Driver Variant
if dpkg -l 2>/dev/null | grep -q "nvidia-driver-.*-open"; then
    echo "WARNING: Open-source NVIDIA driver detected (nvidia-driver-open)." >> "$LOG_FILE"
    notify-send -u normal "GPU Notice" "Open-source NVIDIA driver detected. Recommend switching to proprietary." 2>/dev/null || true
fi

# Test 3: Check Vulkan Renderer for LLVMpipe Software Fallback
VULKAN_DEV=$(vulkaninfo --summary 2>/dev/null | grep "deviceName" | head -n 1)

if echo "$VULKAN_DEV" | grep -qi "llvmpipe"; then
    echo "CRITICAL: System is using CPU software rendering (llvmpipe)!" >> "$LOG_FILE"
    notify-send -u critical "GPU Critical" "Vulkan is running on CPU software rendering (llvmpipe)!" 2>/dev/null || true
    exit 1
else
    echo "SUCCESS: Vulkan renderer active -> $VULKAN_DEV" >> "$LOG_FILE"
fi

# Test 4: Query GPU Telemetry
nvidia-smi --query-gpu=driver_version,name,temperature.gpu,fan.speed --format=csv,noheader >> "$LOG_FILE" 2>&1
echo "Status: OK" >> "$LOG_FILE"
