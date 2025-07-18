pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Power management functions
    function shutdown() {
        console.log("Shutting down system...");
        Quickshell.execDetached(["systemctl", "poweroff"]);
    }

    function reboot() {
        console.log("Rebooting system...");
        Quickshell.execDetached(["systemctl", "reboot"]);
    }

    function suspend() {
        console.log("Suspending system...");
        Quickshell.execDetached(["systemctl", "suspend"]);
    }

    function hibernate() {
        console.log("Hibernating system...");
        Quickshell.execDetached(["systemctl", "hibernate"]);
    }

    function lock() {
        console.log("Locking session...");
        Quickshell.execDetached(["loginctl", "lock-session"]);
    }

    function logout() {
        console.log("Logging out...");
        Quickshell.execDetached(["loginctl", "terminate-user", ""]);
    }

    // Check if hibernation is available
    property bool hibernationAvailable: false

    Process {
        running: true
        command: ["sh", "-c", "test -f /sys/power/state && grep -q mem /sys/power/state"]
        onExited: {
            root.hibernationAvailable = exitCode === 0;
        }
    }

    // Check system capabilities
    property bool canShutdown: true
    property bool canReboot: true
    property bool canSuspend: true
    property bool canHibernate: hibernationAvailable
    property bool canLock: true
    property bool canLogout: true

    Process {
        running: true
        command: ["loginctl", "show-session", "", "--property=CanPowerOff,CanReboot,CanSuspend,CanHibernate"]
        environment: ({
                LANG: "C",
                LC_ALL: "C"
            })
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text().split("\n");
                for (const line of lines) {
                    const [key, value] = line.split("=");
                    if (key && value) {
                        switch (key) {
                            case "CanPowerOff":
                                root.canShutdown = value === "yes";
                                break;
                            case "CanReboot":
                                root.canReboot = value === "yes";
                                break;
                            case "CanSuspend":
                                root.canSuspend = value === "yes";
                                break;
                            case "CanHibernate":
                                root.canHibernate = value === "yes" && root.hibernationAvailable;
                                break;
                        }
                    }
                }
            }
        }
    }

    // Power action data for UI
    readonly property var powerActions: [
        {
            id: "lock",
            name: "Lock",
            icon: "󰍁",
            action: lock,
            available: canLock,
            destructive: false
        },
        {
            id: "logout",
            name: "Logout",
            icon: "󰍃",
            action: logout,
            available: canLogout,
            destructive: true
        },
        {
            id: "suspend",
            name: "Suspend",
            icon: "󰤄",
            action: suspend,
            available: canSuspend,
            destructive: false
        },
        {
            id: "hibernate",
            name: "Hibernate",
            icon: "󰜗",
            action: hibernate,
            available: canHibernate,
            destructive: false
        },
        {
            id: "reboot",
            name: "Reboot",
            icon: "󰜉",
            action: reboot,
            available: canReboot,
            destructive: true
        },
        {
            id: "shutdown",
            name: "Shutdown",
            icon: "󰐥",
            action: shutdown,
            available: canShutdown,
            destructive: true
        }
    ]

    function executeAction(actionId) {
        const action = powerActions.find(a => a.id === actionId);
        if (action && action.available) {
            action.action();
        }
    }
}

