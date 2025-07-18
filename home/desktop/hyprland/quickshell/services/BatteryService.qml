import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
    id: root

    property real percentage: 0
    property bool charging: false
    property bool present: false
    property string status: "Unknown"
    property int timeRemaining: 0
    property real voltage: 0
    property string health: "Unknown"

    // Check for battery presence
    FileView {
        id: batteryPresent
        path: "/sys/class/power_supply/BAT0/present"
        onLoaded: {
            root.present = text().trim() === "1";
            if (root.present) {
                batteryInfo.reload();
            }
        }
    }

    // Get battery information
    FileView {
        id: batteryInfo
        path: "/sys/class/power_supply/BAT0/uevent"
        onLoaded: {
            const lines = text().split("\
");
            const data = {};
            
            for (const line of lines) {
                const [key, value] = line.split("=");
                if (key && value) {
                    data[key] = value;
                }
            }

            // Parse battery data
            if (data.POWER_SUPPLY_CAPACITY) {
                root.percentage = parseInt(data.POWER_SUPPLY_CAPACITY) / 100;
            }
            
            if (data.POWER_SUPPLY_STATUS) {
                root.status = data.POWER_SUPPLY_STATUS;
                root.charging = data.POWER_SUPPLY_STATUS === "Charging";
            }
            
            if (data.POWER_SUPPLY_VOLTAGE_NOW) {
                root.voltage = parseInt(data.POWER_SUPPLY_VOLTAGE_NOW) / 1000000; // Convert to volts
            }
            
            if (data.POWER_SUPPLY_HEALTH) {
                root.health = data.POWER_SUPPLY_HEALTH;
            }
        }
    }

    // Get AC adapter status
    FileView {
        id: acAdapter
        path: "/sys/class/power_supply/ADP1/online"
        onLoaded: {
            // Alternative method to check charging status
            if (!root.charging) {
                root.charging = text().trim() === "1";
            }
        }
    }

    // Update battery info periodically
    Timer {
        interval: 10000 // Update every 10 seconds
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            batteryPresent.reload();
            if (root.present) {
                batteryInfo.reload();
                acAdapter.reload();
            }
        }
    }

    // Helper functions
    function getBatteryIcon() {
        if (!present) return "󰂑"; // No battery
        
        const perc = Math.floor(percentage * 10);
        
        if (charging) {
            if (percentage >= 0.9) return "󰂅"; // Charging full
            if (perc >= 8) return "󰂋"; // Charging 90%
            if (perc >= 7) return "󰂊"; // Charging 80%
            if (perc >= 6) return "󰂉"; // Charging 70%
            if (perc >= 5) return "󰂈"; // Charging 60%
            if (perc >= 4) return "󰂇"; // Charging 50%
            if (perc >= 3) return "󰂆"; // Charging 40%
            if (perc >= 2) return "󰂄"; // Charging 30%
            if (perc >= 1) return "󰂃"; // Charging 20%
            return "󰂂"; // Charging 10%
        } else {
            if (percentage >= 0.9) return "󰁹"; // Full
            if (perc >= 8) return "󰂂"; // 90%
            if (perc >= 7) return "󰂁"; // 80%
            if (perc >= 6) return "󰂀"; // 70%
            if (perc >= 5) return "󰁿"; // 60%
            if (perc >= 4) return "󰁾"; // 50%
            if (perc >= 3) return "󰁽"; // 40%
            if (perc >= 2) return "󰁼"; // 30%
            if (perc >= 1) return "󰁻"; // 20%
            return "󰁺"; // 10%
        }
    }

    function getBatteryColor() {
        if (!present) return "#585b70";
        if (charging) return "#a6e3a1";
        if (percentage > 0.5) return "#a6e3a1";
        if (percentage > 0.2) return "#f9e2af";
        return "#f38ba8";
    }

    function formatTimeRemaining() {
        if (timeRemaining <= 0) return "";
        const hours = Math.floor(timeRemaining / 60);
        const minutes = timeRemaining % 60;
        return `${hours}h ${minutes}m`;
    }

    function getBatteryTooltip() {
        if (!present) return "No battery detected";
        
        let tooltip = `Battery: ${Math.round(percentage * 100)}%`;
        tooltip += `\
Status: ${status}`;
        if (charging) {
            tooltip += "\
Charging";
        }
        if (timeRemaining > 0) {
            tooltip += `\
Time remaining: ${formatTimeRemaining()}`;
        }
        if (voltage > 0) {
            tooltip += `\
Voltage: ${voltage.toFixed(2)}V`;
        }
        return tooltip;
    }
}"

