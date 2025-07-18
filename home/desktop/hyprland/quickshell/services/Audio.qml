pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property real volume: _volume
    readonly property bool muted: _muted
    readonly property string deviceName: _deviceName
    readonly property string deviceIcon: _deviceIcon
    readonly property bool available: _available

    property real _volume: 0.0
    property bool _muted: false
    property string _deviceName: ""
    property string _deviceIcon: ""
    property bool _available: false

    reloadableId: "audio"

    // Get current volume and mute state
    Process {
        id: getVolume
        running: true
        command: ["pactl", "get-sink-volume", "@DEFAULT_SINK@"]
        stdout: SplitParser {
            onRead: msg => {
                const volumeMatch = msg.match(/(\d+)%/);
                if (volumeMatch) {
                    root._volume = parseInt(volumeMatch[1]);
                }
            }
        }
        onExited: getMuteState.running = true
    }

    // Get mute state
    Process {
        id: getMuteState
        running: true
        command: ["pactl", "get-sink-mute", "@DEFAULT_SINK@"]
        stdout: SplitParser {
            onRead: msg => {
                root._muted = msg.trim() === "Mute: yes";
            }
        }
        onExited: getDeviceInfo.running = true
    }

    // Get device information
    Process {
        id: getDeviceInfo
        running: true
        command: ["pactl", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split('\n');
                for (const line of lines) {
                    if (line.includes('Default Sink:')) {
                        const sinkName = line.split(':')[1].trim();
                        root._deviceName = sinkName;
                        root._available = true;
                        break;
                    }
                }
                root._deviceIcon = getDeviceIcon(root._deviceName);
            }
        }
    }

    // Monitor PulseAudio events
    Process {
        running: true
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: msg => {
                if (msg.includes("sink") || msg.includes("server")) {
                    refreshTimer.restart();
                }
            }
        }
    }

    // Refresh audio info periodically and on events
    Timer {
        id: refreshTimer
        interval: 100
        onTriggered: {
            getVolume.running = true;
        }
    }

    // Regular refresh
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            getVolume.running = true;
        }
    }

    // Helper functions
    function getDeviceIcon(deviceName) {
        if (!deviceName) return "󰕿";
        
        const name = deviceName.toLowerCase();
        if (name.includes("headphone") || name.includes("headset")) {
            return "󰋋";
        } else if (name.includes("bluetooth")) {
            return "󰂯";
        } else if (name.includes("usb")) {
            return "󰂃";
        } else if (name.includes("hdmi")) {
            return "󰽟";
        }
        return "󰓃"; // Default speaker icon
    }

    function getVolumeIcon() {
        if (muted) return "󰸈";
        if (volume >= 70) return "󰕾";
        if (volume >= 30) return "󰖀";
        if (volume > 0) return "󰕿";
        return "󰸈";
    }

    function getVolumeColor() {
        if (muted) return "#585b70";
        if (volume >= 70) return "#a6e3a1";
        if (volume >= 30) return "#f9e2af";
        return "#f38ba8";
    }

    // Control functions
    function setVolume(newVolume) {
        const clampedVolume = Math.max(0, Math.min(100, newVolume));
        const setVolumeProcess = Qt.createQmlObject(`
            import Quickshell.Io
            Process {
                command: ["pactl", "set-sink-volume", "@DEFAULT_SINK@", "${clampedVolume}%"]
                running: true
                onExited: refreshTimer.restart()
            }
        `, root);
    }

    function toggleMute() {
        const toggleProcess = Qt.createQmlObject(`
            import Quickshell.Io
            Process {
                command: ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]
                running: true
                onExited: refreshTimer.restart()
            }
        `, root);
    }

    function increaseVolume(step = 5) {
        setVolume(volume + step);
    }

    function decreaseVolume(step = 5) {
        setVolume(volume - step);
    }
}