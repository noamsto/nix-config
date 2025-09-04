#!/usr/bin/env bash

# Power status script for waybar with power-profiles-daemon support
# Shows CPU frequency, power profile, battery status and GPU power level

# Get current power profile from power-profiles-daemon
if command -v powerprofilesctl >/dev/null 2>&1; then
  PPD_PROFILE=$(powerprofilesctl get 2>/dev/null || echo "unknown")
else
  PPD_PROFILE="unknown"
fi

# Read current CPU frequency
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
  FREQ_KHZ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
  FREQ_MHZ=$((FREQ_KHZ / 1000))
else
  FREQ_MHZ="n/a"
fi

# Read CPU governor
CPU_GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")

# Read GPU performance level for AMD graphics
if [ -f /sys/class/drm/card1/device/power_dpm_force_performance_level ]; then
  GPU_LEVEL=$(cat /sys/class/drm/card1/device/power_dpm_force_performance_level)
else
  GPU_LEVEL="n/a"
fi

# Get battery information
BATTERY_LEVEL="n/a"
AC_CONNECTED=false

# Check battery percentage
for bat in BAT0 BAT1 BAT; do
  if [[ -f "/sys/class/power_supply/$bat/capacity" ]]; then
    BATTERY_LEVEL=$(cat "/sys/class/power_supply/$bat/capacity" 2>/dev/null || echo "n/a")
    break
  fi
done

# Check AC connection status
if [[ -f "/sys/class/power_supply/ADP1/online" ]]; then
  AC_STATUS=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo "0")
  [[ $AC_STATUS == "1" ]] && AC_CONNECTED=true
elif [[ -f "/sys/class/power_supply/AC/online" ]]; then
  AC_STATUS=$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo "0")
  [[ $AC_STATUS == "1" ]] && AC_CONNECTED=true
fi

# Determine profile display and icon based on PPD profile
case "$PPD_PROFILE" in
"performance")
  ICON=""
  PROFILE="performance"
  PROFILE_NAME="Performance"
  ;;
"balanced")
  ICON=""
  PROFILE="balanced"
  PROFILE_NAME="Balanced"
  ;;
"power-saver")
  ICON=""
  PROFILE="powersave"
  PROFILE_NAME="Power Saver"
  ;;
*)
  ICON=""
  PROFILE="unknown"
  PROFILE_NAME="Unknown"
  ;;
esac

# Add context indicator for automatic vs manual switching
POWER_STATUS="Battery ${BATTERY_LEVEL}%"
if [[ $AC_CONNECTED == true ]]; then
  POWER_STATUS="AC Connected"
fi

# Determine if we're in automatic mode (< 15% battery = power-saver)
AUTO_MODE_STATUS=""
if [[ $BATTERY_LEVEL != "n/a" && $BATTERY_LEVEL -lt 15 && $PPD_PROFILE == "power-saver" ]]; then
  AUTO_MODE_STATUS=" (Auto)"
elif [[ $AC_CONNECTED == true && $PPD_PROFILE == "performance" ]]; then
  AUTO_MODE_STATUS=" (Auto)"
elif [[ $AC_CONNECTED == false && $BATTERY_LEVEL -ge 15 && $PPD_PROFILE == "balanced" ]]; then
  AUTO_MODE_STATUS=" (Auto)"
else
  AUTO_MODE_STATUS=" (Manual)"
fi

# Create detailed tooltip
TOOLTIP="Power Profile: $PROFILE_NAME$AUTO_MODE_STATUS"
TOOLTIP+="\n━━━━━━━━━━━━━━━━━━━━━━━━"
TOOLTIP+="\nPower Status: $POWER_STATUS"
TOOLTIP+="\nCPU: ${CPU_GOV} @ ${FREQ_MHZ} MHz"
TOOLTIP+="\nGPU Power: $GPU_LEVEL"
TOOLTIP+="\n━━━━━━━━━━━━━━━━━━━━━━━━"
TOOLTIP+="\nClick to cycle power profiles"
TOOLTIP+="\nAuto: AC=Perf, Bat>15%=Bal, Bat<15%=Save"

# Output JSON for waybar
echo "{\"text\":\"$ICON\",\"tooltip\":\"$TOOLTIP\",\"class\":\"$PROFILE\"}"
