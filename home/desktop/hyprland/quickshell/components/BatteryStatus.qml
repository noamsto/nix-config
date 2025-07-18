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
    
    // Battery popout as a separate PanelWindow
    PanelWindow {
        id: batteryPopout
        visible: root.popoutVisible
        
        anchors.left: true
        anchors.top: true
        anchors.bottom: true
        
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        
        margins.left: 68  // To the right of bar (60 + 8)
        margins.top: 424  // Position for battery icon (adjust as needed)
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
            
            BatteryPopout {
                id: popoutContent
                implicitWidth: parent.width
                implicitHeight: parent.height
            }
        }
    }
    

    Rectangle {
        id: batteryButton
        anchors.centerIn: parent
        width: 32
        height: 32
        radius: 8
        color: "transparent"
        border.color: Battery.present ? "#45475a" : "#313244"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: Battery.getBatteryIcon()
            color: Battery.getBatteryColor()
            font.pixelSize: 18
            font.family: "Symbols Nerd Font"
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
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
            onClicked: {
                // Click handling for battery actions
            }
        }

        Behavior on color { 
            ColorAnimation { duration: 150 } 
        }
        
        Behavior on scale {
            NumberAnimation { duration: 100 }
        }
    }
    
    // Battery percentage indicator
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: 16
        height: 2
        radius: 1
        color: "#45475a"
        visible: Battery.present
        
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * Battery.percentage
            radius: 1
            color: Battery.getBatteryColor()
            
            Behavior on width {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
    
    // Charging indicator
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        width: 6
        height: 6
        radius: 3
        color: "#a6e3a1"
        visible: Battery.charging
        
        Text {
            anchors.centerIn: parent
            text: "⚡"
            font.pixelSize: 5
            color: "#11111b"
        }
    }
}