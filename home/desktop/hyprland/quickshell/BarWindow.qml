import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import "./components"
import "./services"

PanelWindow {
    id: root

    // Track the current active window title
    property string activeWindowTitle: ""
    property string activeWindowClass: ""
    property string activeWindowIcon: ""

    // Popout management
    function checkPopout(y) {
        const spacing = 8;

        // Network status
        const networkY = bottomSection.y + networkStatus.y;
        if (y >= networkY && y <= networkY + networkStatus.height) {
            console.log("Network popout triggered at y:", y);
            popoutManager.setPopout("network", networkY + networkStatus.height / 2);
            return;
        }

        // Battery status
        const batteryY = bottomSection.y + batteryStatus.y;
        if (y >= batteryY && y <= batteryY + batteryStatus.height) {
            console.log("Battery popout triggered at y:", y);
            popoutManager.setPopout("battery", batteryY + batteryStatus.height / 2);
            return;
        }

        // Volume control
        const volumeY = bottomSection.y + volumeControl.y;
        if (y >= volumeY && y <= volumeY + volumeControl.height) {
            console.log("Volume popout triggered at y:", y);
            popoutManager.setPopout("volume", volumeY + volumeControl.height / 2);
            return;
        }

        // Bluetooth status
        const bluetoothY = bottomSection.y + bluetoothStatus.y;
        if (y >= bluetoothY && y <= bluetoothY + bluetoothStatus.height) {
            console.log("Bluetooth popout triggered at y:", y);
            popoutManager.setPopout("bluetooth", bluetoothY + bluetoothStatus.height / 2);
            return;
        }

        // Power control
        const powerY = bottomSection.y + powerControl.y;
        if (y >= powerY && y <= powerY + powerControl.height) {
            console.log("Power popout triggered at y:", y);
            popoutManager.setPopout("power", powerY + powerControl.height / 2);
            return;
        }

        // No match - close popout
        popoutManager.close();
    }

    anchors {
        left: true
        top: true
        bottom: true
    }

    implicitWidth: 60
    margins {
        left: 8
        top: 8
        bottom: 8
        right: -19
    }

    color: "transparent"

    // Simple function to get icon path from window class
    function getIconForClass(windowClass) {
        if (!windowClass)
            return "";

        // Handle common problematic cases
        if (windowClass === "brave-browser")
            return "image://icon/brave";
        if (windowClass === "com.github.th_ch.youtube_music")
            return "image://icon/youtube-music";
        if (windowClass.startsWith("org."))
            return `image://icon/${windowClass.split('.').pop()}`;

        // Default: use class name as-is
        return `image://icon/${windowClass.toLowerCase()}`;
    }

    // Get initial active window state
    Component.onCompleted: {
        console.log("Bar initialized, waiting for Hyprland events");
        // Initial window state will be populated by the socket events
    }

    // Listen to Hyprland events for active window changes
    Socket {
        path: `/run/user/${Quickshell.env("USER_ID") || "1000"}/hypr/${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}/.socket2.sock`
        connected: true

        parser: SplitParser {
            property var activeWindowRegex: new RegExp("activewindow>>(.+),(.*)")

            onRead: msg => {
                console.log("Hyprland event:", msg);
                const match = activeWindowRegex.exec(msg);
                if (match != null) {
                    console.log("Active window changed - Class:", match[1], "Title:", match[2]);
                    root.activeWindowClass = match[1] || "";
                    root.activeWindowTitle = match[2] || "";
                    root.activeWindowIcon = getIconForClass(match[1]);
                }
            }
        }
    }

    Rectangle {
        id: barBackground
        anchors.fill: parent
        color: "#1e1e2e"
        radius: 12

        // Single background layer to avoid white corners
        border.color: "#585b70"
        border.width: 1
        opacity: 0.95

        // Top section
        Column {
            id: topSection
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 8
            }
            spacing: 12

            // Workspaces (vertical)
            Column {
                id: workspacesSection
                spacing: 8
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: Hyprland.workspaces
                    Rectangle {
                        id: workspaceButton
                        width: 40
                        height: modelData.active ? 40 : 18
                        radius: 16
                        anchors.horizontalCenter: parent.horizontalCenter
                        property bool isActive: modelData.active
                        property bool hasWindows: modelData.active || modelData.hasFullscreen
                        color: isActive ? "#cba6f7" : (hasWindows ? "#45475a" : "#313244")
                        border.color: isActive ? "#b4befe" : (hasWindows ? "#6c7086" : "transparent")
                        border.width: isActive ? 2 : 1
                        Behavior on height {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }
                        }
                        Behavior on border.color {
                            ColorAnimation {
                                duration: 200
                            }
                        }
                        Item {
                            anchors.centerIn: parent
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.parent.isActive ? 22 : 8
                                height: parent.parent.isActive ? 22 : 8
                                radius: width / 2
                                color: parent.parent.isActive ? "#11111b" : "#cdd6f4"
                                opacity: parent.parent.hasWindows || parent.parent.isActive ? 1.0 : 0.4
                                Behavior on width {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on height {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.id
                                    color: "#cdd6f4"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    visible: parent.parent.parent.isActive
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Hyprland.dispatch("workspace " + modelData.id)
                            hoverEnabled: true
                            onEntered: parent.scale = 1.1
                            onExited: parent.scale = 1.0
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 100
                            }
                        }
                    }
                }
            }

            // Active window display
            WindowTitle {
                id: activeWindow
                windowClass: root.activeWindowClass
                windowTitle: root.activeWindowTitle
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.activeWindowClass !== ""
            }

            // System tray
            Column {
                spacing: 8
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: SystemTray.items
                    Rectangle {
                        width: 36
                        height: 36
                        radius: 8
                        color: "transparent"
                        anchors.horizontalCenter: parent.horizontalCenter
                        Image {
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            source: modelData.icon || ""
                            smooth: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function (mouse) {
                                if (mouse.button === Qt.LeftButton) {
                                    modelData.activate();
                                } else if (mouse.button === Qt.RightButton) {
                                    modelData.contextMenu();
                                }
                            }
                            hoverEnabled: true
                            onEntered: parent.color = "#313244"
                            onExited: parent.color = "transparent"
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }
                }
            }
        }

        // Bottom section
        Column {
            id: bottomSection
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: 8
            }
            spacing: 8

            // Network status indicator
            NetworkStatus {
                id: networkStatus
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Battery status indicator
            BatteryStatus {
                id: batteryStatus
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Volume control
            VolumeControl {
                id: volumeControl
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Bluetooth status
            BluetoothStatus {
                id: bluetoothStatus
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Power control
            PowerControl {
                id: powerControl
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Date and time
            Rectangle {
                width: 48
                height: 44
                radius: 14
                color: "#313244"
                border.color: "#45475a"
                border.width: 1
                anchors.horizontalCenter: parent.horizontalCenter
                Column {
                    id: timeColumn
                    anchors.centerIn: parent
                    spacing: -2
                    Text {
                        id: timeText
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatTime(new Date(), "hh:mm")
                        color: "#cdd6f4"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    Text {
                        id: dateText
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDate(new Date(), "MMM dd")
                        color: "#9399b2"
                        font.pixelSize: 9
                    }
                }
                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: {
                        timeText.text = Qt.formatTime(new Date(), "hh:mm");
                        dateText.text = Qt.formatDate(new Date(), "MMM dd");
                    }
                }
            }
        }
        // Subtle drop shadow effect
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#00000040"
            shadowBlur: 0.6
            shadowVerticalOffset: 2
        }

        // Remove the global mouse area - we'll handle hover on individual components
    }

    // Popout manager removed - using individual popouts in components
}
