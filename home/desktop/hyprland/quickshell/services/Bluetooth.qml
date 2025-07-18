pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property bool enabled: _enabled
    readonly property bool available: _available
    readonly property list<BluetoothDevice> devices: []
    readonly property list<BluetoothDevice> connectedDevices: devices.filter(d => d.connected)
    readonly property bool hasConnectedDevices: connectedDevices.length > 0

    property bool _enabled: false
    property bool _available: false

    reloadableId: "bluetooth"

    // Check if bluetooth is available and enabled
    Process {
        id: checkBluetooth
        running: true
        command: ["bluetoothctl", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split('\n');
                root._available = true;
                for (const line of lines) {
                    if (line.includes('Powered:')) {
                        root._enabled = line.includes('yes');
                        break;
                    }
                }
                if (root._enabled) {
                    getDevices.running = true;
                }
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root._available = false;
            }
        }
    }

    // Get bluetooth devices
    Process {
        id: getDevices
        running: false
        command: ["bluetoothctl", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split('\n').filter(line => line.trim());
                const currentDevices = [];
                
                for (const line of lines) {
                    const match = line.match(/Device\s+([^\s]+)\s+(.+)/);
                    if (match) {
                        currentDevices.push({
                            address: match[1],
                            name: match[2],
                            connected: false,
                            paired: false,
                            trusted: false,
                            type: "unknown"
                        });
                    }
                }
                
                // Update device list
                const rDevices = root.devices;
                
                // Remove devices that no longer exist
                const destroyed = rDevices.filter(rd => !currentDevices.find(cd => cd.address === rd.address));
                for (const device of destroyed) {
                    rDevices.splice(rDevices.indexOf(device), 1).forEach(d => d.destroy());
                }
                
                // Add or update devices
                for (const device of currentDevices) {
                    const match = rDevices.find(rd => rd.address === device.address);
                    if (match) {
                        match.lastIpcObject = device;
                    } else {
                        rDevices.push(deviceComp.createObject(root, {
                            lastIpcObject: device
                        }));
                    }
                }
                
                // Get detailed info for each device
                for (const device of currentDevices) {
                    getDeviceInfo(device.address);
                }
            }
        }
    }

    // Get detailed device information
    function getDeviceInfo(address) {
        const deviceInfoProcess = Qt.createQmlObject(`
            import Quickshell.Io
            Process {
                command: ["bluetoothctl", "info", "${address}"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const lines = text.split('\\n');
                        const deviceUpdate = {
                            address: "${address}",
                            name: "",
                            connected: false,
                            paired: false,
                            trusted: false,
                            type: "unknown"
                        };
                        
                        for (const line of lines) {
                            const trimmed = line.trim();
                            if (trimmed.startsWith('Name:')) {
                                deviceUpdate.name = trimmed.substring(5).trim();
                            } else if (trimmed.startsWith('Connected:')) {
                                deviceUpdate.connected = trimmed.includes('yes');
                            } else if (trimmed.startsWith('Paired:')) {
                                deviceUpdate.paired = trimmed.includes('yes');
                            } else if (trimmed.startsWith('Trusted:')) {
                                deviceUpdate.trusted = trimmed.includes('yes');
                            } else if (trimmed.startsWith('Icon:')) {
                                deviceUpdate.type = trimmed.substring(5).trim();
                            }
                        }
                        
                        // Update the device in our list
                        const device = root.devices.find(d => d.address === "${address}");
                        if (device) {
                            device.lastIpcObject = deviceUpdate;
                        }
                    }
                }
                running: true
            }
        `, root);
    }

    // Refresh bluetooth info periodically
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            checkBluetooth.running = true;
        }
    }

    component BluetoothDevice: QtObject {
        required property var lastIpcObject
        readonly property string address: lastIpcObject.address
        readonly property string name: lastIpcObject.name
        readonly property bool connected: lastIpcObject.connected
        readonly property bool paired: lastIpcObject.paired
        readonly property bool trusted: lastIpcObject.trusted
        readonly property string type: lastIpcObject.type
    }

    Component {
        id: deviceComp
        BluetoothDevice {}
    }

    // Helper functions
    function getBluetoothIcon() {
        if (!available) return "󰂲";
        if (!enabled) return "󰂲";
        if (hasConnectedDevices) return "󰂯";
        return "󰂯";
    }

    function getBluetoothColor() {
        if (!available) return "#585b70";
        if (!enabled) return "#585b70";
        if (hasConnectedDevices) return "#89b4fa";
        return "#9399b2";
    }

    function getDeviceIcon(device) {
        if (!device) return "󰂯";
        
        switch (device.type) {
            case "audio-headphones":
            case "audio-headset":
                return "󰋋";
            case "input-mouse":
                return "󰍽";
            case "input-keyboard":
                return "󰌌";
            case "phone":
                return "󰄜";
            case "computer":
                return "󰚄";
            default:
                return "󰂯";
        }
    }

    // Control functions
    function toggleBluetooth() {
        const toggleProcess = Qt.createQmlObject(`
            import Quickshell.Io
            Process {
                command: ["bluetoothctl", "power", "${enabled ? "off" : "on"}"]
                running: true
                onExited: function(exitCode) {
                    const timer = Qt.createQmlObject('import QtQuick; Timer { interval: 1000; running: true; onTriggered: checkBluetooth.running = true }', root);
                }
            }
        `, root);
    }

    function connectDevice(address) {
        const connectProcess = Qt.createQmlObject(`
            import Quickshell.Io
            Process {
                command: ["bluetoothctl", "connect", "${address}"]
                running: true
                onExited: function(exitCode) {
                    const timer = Qt.createQmlObject('import QtQuick; Timer { interval: 1000; running: true; onTriggered: getDeviceInfo("${address}") }', root);
                }
            }
        `, root);
    }

    function disconnectDevice(address) {
        const disconnectProcess = Qt.createQmlObject(`
            import Quickshell.Io
            Process {
                command: ["bluetoothctl", "disconnect", "${address}"]
                running: true
                onExited: function(exitCode) {
                    const timer = Qt.createQmlObject('import QtQuick; Timer { interval: 1000; running: true; onTriggered: getDeviceInfo("${address}") }', root);
                }
            }
        `, root);
    }

    function pairDevice(address) {
        const pairProcess = Qt.createQmlObject(`
            import Quickshell.Io
            Process {
                command: ["bluetoothctl", "pair", "${address}"]
                running: true
                onExited: function(exitCode) {
                    const timer = Qt.createQmlObject('import QtQuick; Timer { interval: 1000; running: true; onTriggered: getDeviceInfo("${address}") }', root);
                }
            }
        `, root);
    }
}