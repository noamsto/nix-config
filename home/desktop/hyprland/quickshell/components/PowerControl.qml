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
    
    // Power popout as a separate PanelWindow
    PanelWindow {
        id: powerPopout
        visible: root.popoutVisible
        
        anchors.left: true
        anchors.top: true
        anchors.bottom: true
        
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        
        margins.left: 68  // To the right of bar (60 + 8)
        margins.top: 556  // Position for power icon (adjust as needed)
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
            
            PowerPopoutContent {
                id: popoutContent
                anchors.centerIn: parent
            }
        }
    }
    
    Rectangle {
        id: powerButton
        anchors.centerIn: parent
        width: 32
        height: 32
        radius: 8
        color: "transparent"
        border.color: "#45475a"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: "󰐥"
            color: "#f38ba8"
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
                // Click handling for power actions
            }
        }

        Behavior on color { 
            ColorAnimation { duration: 150 } 
        }
        
        Behavior on scale {
            NumberAnimation { duration: 100 }
        }
    }
}