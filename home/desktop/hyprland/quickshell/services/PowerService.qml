import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
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

    // Check system capabilities
    property bool canShutdown: true
    property bool canReboot: true
    property bool canSuspend: true
    property bool canHibernate: true
    property bool canLock: true
    property bool canLogout: true

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
}"

