import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Io
import QtQuick
import QtQuick.Effects

PanelWindow {
    id: root

    // Track the current active window title
    property string activeWindowTitle: ""
    property string activeWindowClass: ""
    property string activeWindowIcon: ""

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 48
    margins {
        top: 8
        left: 8
        right: 8
    }

    color: "transparent"

    // Simple function to get icon path from window class
    function getIconForClass(windowClass) {
        if (!windowClass)
            return "";
        
        // Handle common problematic cases
        if (windowClass === "brave-browser") return "image://icon/brave";
        if (windowClass === "com.github.th_ch.youtube_music") return "image://icon/youtube-music";
        if (windowClass.startsWith("org.")) return `image://icon/${windowClass.split('.').pop()}`;
        
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

        // Left section - Workspaces
        Row {
            id: leftSection
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
                leftMargin: 16
            }
            spacing: 12

            // Workspaces with animations
            Row {
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    model: Hyprland.workspaces

                    Rectangle {
                        id: workspaceButton
                        width: modelData.active ? 40 : 12
                        height: 28
                        radius: 14

                        property bool isActive: modelData.active
                        property bool hasWindows: modelData.active || modelData.hasFullscreen

                        color: isActive ? "#cba6f7" : (hasWindows ? "#45475a" : "#313244")
                        border.color: isActive ? "#b4befe" : (hasWindows ? "#6c7086" : "transparent")
                        border.width: isActive ? 2 : 1

                        Behavior on width {
                            NumberAnimation {
                                duration: 250
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

                        // Active indicator or window count
                        Item {
                            anchors.centerIn: parent

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.parent.isActive ? 20 : 6
                                height: parent.parent.isActive ? 20 : 6
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

                                // Workspace number for active workspace
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.id
                                    color: "#cdd6f4"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    visible: parent.parent.parent.isActive
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                console.log("Switching to workspace:", modelData.id);
                                // Try different dispatch formats
                                // Try the correct Hyprland dispatch format
                                Hyprland.dispatch("workspace " + modelData.id);
                            }

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
        }

        // Active window title
        Row {
            id: activeWindowRow
            spacing: 8
            anchors {
                centerIn: parent
            }
            Rectangle {
                width: Math.min(activeWindowContent.implicitWidth + 20, 320)
                height: 28
                radius: 14
                color: "#313244"
                border.color: "#45475a"
                border.width: 1
                visible: root.activeWindowTitle !== ""

                Row {
                    id: activeWindowContent
                    anchors.centerIn: parent
                    spacing: 8

                    // Fancy icon container with background and effects
                    Rectangle {
                        id: iconContainer
                        width: 24
                        height: 24
                        radius: 8
                        color: "#45475a"
                        border.color: "#6c7086"
                        border.width: 1
                        visible: root.activeWindowIcon !== ""
                        anchors.verticalCenter: parent.verticalCenter

                        // Subtle gradient background
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: "#585b70"
                            }
                            GradientStop {
                                position: 0.2
                                color: "#45475a"
                            }
                        }

                        Image {
                            id: activeWindowIconImage
                            width: 20
                            height: 20
                            source: root.activeWindowIcon
                            anchors.centerIn: parent
                            smooth: true
                            opacity: 1

                            // Scale animation on icon change
                            Behavior on source {
                                SequentialAnimation {
                                    NumberAnimation {
                                        target: activeWindowIconImage
                                        property: "scale"
                                        to: 0.8
                                        duration: 100
                                        easing.type: Easing.InQuad
                                    }
                                    NumberAnimation {
                                        target: activeWindowIconImage
                                        property: "scale"
                                        to: 1.0
                                        duration: 150
                                        easing.type: Easing.OutBack
                                    }
                                }
                            }
                        }

                        // Very subtle glow effect
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: "#6c708620"
                            shadowBlur: 0.1
                            shadowVerticalOffset: 0.5
                        }

                        // Hover effect
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: {
                                parent.scale = 1.1;
                                parent.border.color = "#b4befe";
                            }
                            onExited: {
                                parent.scale = 1.0;
                                parent.border.color = "#6c7086";
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on border.color {
                            ColorAnimation {
                                duration: 200
                            }
                        }
                    }

                    Text {
                        id: activeWindowText
                        text: root.activeWindowTitle
                        color: "#cdd6f4"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 200)
                        anchors.verticalCenter: parent.verticalCenter

                        // Fade animation on text change
                        Behavior on text {
                            SequentialAnimation {
                                NumberAnimation {
                                    target: activeWindowText
                                    property: "opacity"
                                    to: 0.6
                                    duration: 100
                                }
                                NumberAnimation {
                                    target: activeWindowText
                                    property: "opacity"
                                    to: 1.0
                                    duration: 150
                                }
                            }
                        }
                    }
                }
            }
        }

        // Right section - System info
        Row {
            id: rightSection
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
                rightMargin: 16
            }
            spacing: 12

            // System tray
            Row {
                spacing: 8

                Repeater {
                    model: SystemTray.items

                    Rectangle {
                        width: 24
                        height: 24
                        radius: 6
                        color: "transparent"

                        Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
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

            // Network indicator (placeholder)
            Rectangle {
                width: 36
                height: 28
                radius: 14
                color: "#313244"
                border.color: "#45475a"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "󰤨"
                    color: "#a6e3a1"
                    font.pixelSize: 16
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: parent.color = "#45475a"
                    onExited: parent.color = "#313244"
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }

            // Battery indicator (placeholder)
            Rectangle {
                width: 36
                height: 28
                radius: 14
                color: "#313244"
                border.color: "#45475a"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "󰁹"
                    color: "#f9e2af"
                    font.pixelSize: 16
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: parent.color = "#45475a"
                    onExited: parent.color = "#313244"
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }

            // Date and time
            Rectangle {
                width: timeColumn.implicitWidth + 16
                height: 28
                radius: 14
                color: "#313244"
                border.color: "#45475a"
                border.width: 1

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
    }
}
