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
    
    // Volume popout as a separate PanelWindow
    PanelWindow {
        id: volumePopout
        visible: root.popoutVisible
        
        anchors.left: true
        anchors.top: true
        anchors.bottom: true
        
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        
        margins.left: 68  // To the right of bar (60 + 8)
        margins.top: 468  // Position for volume icon (adjust as needed)
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
            
            VolumePopout {
                id: popoutContent
                implicitWidth: parent.width
                implicitHeight: parent.height
            }
        }
    }
    
    
    Rectangle {
        id: volumeButton
        anchors.centerIn: parent
        width: 32
        height: 32
        radius: 8
        color: "transparent"
        border.color: Audio.available ? "#45475a" : "#313244"
        border.width: 1
        
        Text {
            anchors.centerIn: parent
            text: Audio.getVolumeIcon()
            font.family: "Symbols Nerd Font"
            font.pixelSize: 18
            color: Audio.getVolumeColor()
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
                    Audio.toggleMute()
                }
                // Left click handling now managed by parent MouseArea
            }
            
            onWheel: function(wheel) {
                const delta = wheel.angleDelta.y > 0 ? 5 : -5
                if (delta > 0) {
                    Audio.increaseVolume(5)
                } else {
                    Audio.decreaseVolume(5)
                }
            }
        }
        
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
        
        Behavior on scale {
            NumberAnimation { duration: 100 }
        }
    }
    
    // Volume level indicator
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: 16
        height: 2
        radius: 1
        color: "#45475a"
        visible: Audio.available && !Audio.muted
        
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * (Audio.volume / 100)
            radius: 1
            color: Audio.getVolumeColor()
            
            Behavior on width {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}