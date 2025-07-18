import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../services"
import "../popouts"

Item {
    id: root

    implicitWidth: 36
    implicitHeight: 36

    property bool popoutVisible: false

    // Network popout as a separate PanelWindow
    PanelWindow {
        id: networkPopout
        visible: root.popoutVisible

        anchors.left: true
        anchors.top: true
        anchors.bottom: true

        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        margins.left: 68  // To the right of bar (60 + 8)
        margins.top: 380  // Higher up to align with network icon
        margins.right: 0
        margins.bottom: 0

        implicitWidth: visible ? (popoutContent.implicitWidth + 24) : 0  // Dynamic width: content + margins
        implicitHeight: visible ? (popoutContent.implicitHeight + 24) : 0  // Dynamic height: content + margins

        color: "transparent"

        NetworkPopoutContent {
            id: popoutContent
            anchors.centerIn: parent

            Rectangle {
                anchors.fill: parent
                anchors.margins: -12  // Expand background 12px around content
                color: "#1e1e2e"
                radius: 12
                border.color: "#585b70"
                border.width: 1
                opacity: 0.95
                z: -1  // Behind content

                // Drop shadow
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#00000060"
                    shadowBlur: 0.8
                    shadowVerticalOffset: 4
                    shadowHorizontalOffset: 2
                }
            }
        }
    }

    Rectangle {
        id: networkButton
        anchors.centerIn: parent
        width: 32
        height: 32
        radius: 8
        color: "transparent"
        border.color: Network.connected ? "#45475a" : "#313244"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: Network.getNetworkIcon(Network.active?.strength ?? 0)
            color: Network.getNetworkColor(Network.active?.strength ?? 0)
            font.pixelSize: 18
            font.family: "Symbols Nerd Font"
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                parent.color = "#313244";
                parent.scale = 1.1;
                root.popoutVisible = true;
            }
            onExited: {
                parent.color = "transparent";
                parent.scale = 1.0;
                root.popoutVisible = false;
            }
            onClicked:
            // Click handling for network actions
            {}
        }

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 100
            }
        }
    }

    // Connection type indicator
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 6
        height: 6
        radius: 3
        color: Network.connectionType === "wifi" ? "#f9e2af" : "#a6e3a1"
        visible: Network.connected

        Text {
            anchors.centerIn: parent
            text: Network.connectionType === "wifi" ? "W" : "E"
            font.pixelSize: 5
            font.weight: Font.Bold
            color: "#11111b"
        }
    }
}
