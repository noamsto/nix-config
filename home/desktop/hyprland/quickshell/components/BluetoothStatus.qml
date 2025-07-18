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
    
    // Bluetooth popout as a separate PanelWindow
    PanelWindow {
        id: bluetoothPopout
        visible: root.popoutVisible
        
        anchors.left: true
        anchors.top: true
        anchors.bottom: true
        
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        
        margins.left: 68  // To the right of bar (60 + 8)
        margins.top: 512  // Position for bluetooth icon (adjust as needed)
        margins.right: 0
        margins.bottom: 0
        
        implicitWidth: visible ? 260 : 0
        implicitHeight: visible ? 200 : 0
        
        color: "transparent"
        
        Rectangle {
            anchors.fill: parent
            anchors.margins: 12
            color: "transparent"
            
            Rectangle {
                anchors.fill: parent
                anchors.margins: -12
                color: "#1e1e2e"
                radius: 12
                border.color: "#585b70"
                border.width: 1
                opacity: 0.95
                z: -1
                
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#00000060"
                    shadowBlur: 0.8
                    shadowVerticalOffset: 4
                    shadowHorizontalOffset: 2
                }
            }
            
            BluetoothPopout {
                id: popoutContent
                implicitWidth: parent.width
                implicitHeight: parent.height
            }
        }
    }
    
    
    Rectangle {
        id: bluetoothButton
        anchors.centerIn: parent
        width: 32
        height: 32
        radius: 8
        color: "transparent"
        border.color: Bluetooth.available ? "#45475a" : "#313244"
        border.width: 1
        
        Text {
            anchors.centerIn: parent
            text: Bluetooth.getBluetoothIcon()
            font.family: "Symbols Nerd Font"
            font.pixelSize: 18
            color: Bluetooth.getBluetoothColor()
        }
        
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            
            onEntered: {
                parent.color = "#313244"
                parent.scale = 1.1
                root.popoutVisible = true
            }
            
            onExited: {
                parent.color = "transparent"
                parent.scale = 1.0
                root.popoutVisible = false
            }
            
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    Bluetooth.toggleBluetooth()
                }
                // Left click handling now managed by parent MouseArea
            }
        }
        
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
        
        Behavior on scale {
            NumberAnimation { duration: 100 }
        }
    }
    
    // Connected devices indicator
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 6
        height: 6
        radius: 3
        color: "#89b4fa"
        visible: Bluetooth.hasConnectedDevices
        
        Text {
            anchors.centerIn: parent
            text: Bluetooth.connectedDevices.length.toString()
            font.pixelSize: 5
            font.weight: Font.Bold
            color: "#11111b"
        }
    }
}