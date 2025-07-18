pragma Singleton

import Quickshell
import Quickshell.Services.UPower
import QtQuick

Singleton {
    id: root

    property real percentage: UPower.displayDevice.percentage
    property bool charging: UPower.displayDevice.state === UPowerDevice.Charging
    property bool present: UPower.displayDevice.isLaptopBattery
    
    // Debug properties
    onPercentageChanged: console.log("Battery percentage:", percentage)
    onChargingChanged: console.log("Battery charging:", charging)
    onPresentChanged: console.log("Battery present:", present)
    property string status: {
        switch (UPower.displayDevice.state) {
            case UPowerDevice.Charging: return "Charging"
            case UPowerDevice.Discharging: return "Discharging"
            case UPowerDevice.Empty: return "Empty"
            case UPowerDevice.FullyCharged: return "Full"
            case UPowerDevice.PendingCharge: return "Pending Charge"
            case UPowerDevice.PendingDischarge: return "Pending Discharge"
            default: return "Unknown"
        }
    }
    property int timeRemaining: charging ? UPower.displayDevice.timeToFull : UPower.displayDevice.timeToEmpty
    property real voltage: UPower.displayDevice.voltage
    property string health: {
        switch (UPower.displayDevice.health) {
            case UPowerDevice.HealthGood: return "Good"
            case UPowerDevice.HealthDead: return "Dead"
            case UPowerDevice.HealthCold: return "Cold"
            case UPowerDevice.HealthOverheat: return "Overheat"
            case UPowerDevice.HealthOverVoltage: return "Over Voltage"
            case UPowerDevice.HealthUnspecFailure: return "Unspecified Failure"
            default: return "Unknown"
        }
    }

    reloadableId: "battery"

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
        tooltip += `\nStatus: ${status}`;
        if (charging) {
            tooltip += "\nCharging";
        }
        if (timeRemaining > 0) {
            tooltip += `\nTime remaining: ${formatTimeRemaining()}`;
        }
        if (voltage > 0) {
            tooltip += `\nVoltage: ${voltage.toFixed(2)}V`;
        }
        return tooltip;
    }
}

