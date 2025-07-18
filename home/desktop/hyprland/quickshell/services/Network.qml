pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property list<AccessPoint> networks: []
    readonly property AccessPoint active: networks.find(n => n.active) ?? null
    readonly property bool connected: active !== null
    readonly property string connectionType: {
        if (!active) return "none"
        if (active.ssid) return "wifi"
        return "ethernet"
    }

    reloadableId: "network"

    // Monitor NetworkManager state changes
    Process {
        running: true
        command: ["nmcli", "m"]
        stdout: SplitParser {
            onRead: msg => {
                console.log("NetworkManager state changed:", msg);
                getNetworks.running = true;
            }
        }
    }

    // Get network information
    Process {
        id: getNetworks
        running: true
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,TYPE", "d", "w"]
        environment: ({
                LANG: "C",
                LC_ALL: "C"
            })
        stdout: StdioCollector {
            onStreamFinished: {
                const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
                const rep = new RegExp("\\\\:", "g");
                const rep2 = new RegExp(PLACEHOLDER, "g");

                const networks = text.trim().split("\n").map(n => {
                    const net = n.replace(rep, PLACEHOLDER).split(":");
                    return {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]) || 0,
                        frequency: parseInt(net[2]?.replace(" MHz", "")) || 0,
                        ssid: net[3] || "",
                        bssid: net[4]?.replace(rep2, ":") || "",
                        type: net[5] || "wifi"
                    };
                }).filter(n => n.ssid || n.active); // Filter out empty entries

                const rNetworks = root.networks;

                // Remove destroyed networks
                const destroyed = rNetworks.filter(rn => !networks.find(n => 
                    n.frequency === rn.frequency && n.ssid === rn.ssid && n.bssid === rn.bssid
                ));
                for (const network of destroyed)
                    rNetworks.splice(rNetworks.indexOf(network), 1).forEach(n => n.destroy());

                // Add or update networks
                for (const network of networks) {
                    const match = rNetworks.find(n => 
                        n.frequency === network.frequency && n.ssid === network.ssid && n.bssid === network.bssid
                    );
                    if (match) {
                        match.lastIpcObject = network;
                    } else {
                        rNetworks.push(apComp.createObject(root, {
                            lastIpcObject: network
                        }));
                    }
                }
            }
        }
    }

    // Get ethernet connection info
    Process {
        id: getEthernet
        running: true
        command: ["nmcli", "-g", "DEVICE,TYPE,STATE", "d", "status"]
        environment: ({
                LANG: "C",
                LC_ALL: "C"
            })
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                for (const line of lines) {
                    const [device, type, state] = line.split(":");
                    if (type === "ethernet" && state === "connected") {
                        // Add ethernet connection as a network entry
                        const ethNetwork = {
                            active: true,
                            strength: 100,
                            frequency: 0,
                            ssid: "",
                            bssid: device,
                            type: "ethernet"
                        };
                        
                        const rNetworks = root.networks;
                        const existing = rNetworks.find(n => n.type === "ethernet" && n.bssid === device);
                        if (!existing) {
                            rNetworks.push(apComp.createObject(root, {
                                lastIpcObject: ethNetwork
                            }));
                        }
                        break;
                    }
                }
            }
        }
    }

    // Refresh network info periodically
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            getNetworks.running = true;
            getEthernet.running = true;
        }
    }

    component AccessPoint: QtObject {
        required property var lastIpcObject
        readonly property string ssid: lastIpcObject.ssid
        readonly property string bssid: lastIpcObject.bssid
        readonly property int strength: lastIpcObject.strength
        readonly property int frequency: lastIpcObject.frequency
        readonly property bool active: lastIpcObject.active
        readonly property string type: lastIpcObject.type
    }

    Component {
        id: apComp
        AccessPoint {}
    }

    // Helper functions
    function getNetworkIcon(strength) {
        if (connectionType === "ethernet") {
            return "󰈀"; // Ethernet icon
        } else if (connectionType === "wifi") {
            if (strength >= 80) return "󰤨";
            if (strength >= 60) return "󰤥";
            if (strength >= 40) return "󰤢";
            if (strength >= 20) return "󰤟";
            return "󰤯";
        }
        return "󰤭"; // No connection
    }

    function getNetworkColor(strength) {
        if (connectionType === "ethernet") return "#a6e3a1";
        if (connectionType === "wifi") {
            if (strength >= 60) return "#a6e3a1";
            if (strength >= 30) return "#f9e2af";
            return "#f38ba8";
        }
        return "#585b70"; // Disconnected
    }
}

