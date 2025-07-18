import QtQuick
import QtQuick.Layouts
import "../services"

PopoutWrapper {
    id: root
    
    popoutWidth: 160
    popoutHeight: 132
    
    Column {
        anchors.fill: parent
        spacing: 4
        
        Rectangle {
            width: parent.width
            height: 32
            radius: 4
            color: "transparent"
            
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "󰒲  Suspend"
                color: "#cdd6f4"
                font.pixelSize: 12
                font.family: "Symbols Nerd Font"
            }
            
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: parent.color = "#313244"
                onExited: parent.color = "transparent"
                onClicked: {
                    PowerManager.suspend()
                    root.popoutVisible = false
                }
            }
        }
        
        Rectangle {
            width: parent.width
            height: 32
            radius: 4
            color: "transparent"
            
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "󰜉  Reboot"
                color: "#cdd6f4"
                font.pixelSize: 12
                font.family: "Symbols Nerd Font"
            }
            
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: parent.color = "#313244"
                onExited: parent.color = "transparent"
                onClicked: {
                    PowerManager.reboot()
                    root.popoutVisible = false
                }
            }
        }
        
        Rectangle {
            width: parent.width
            height: 32
            radius: 4
            color: "transparent"
            
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "󰐥  Shutdown"
                color: "#f38ba8"
                font.pixelSize: 12
                font.family: "Symbols Nerd Font"
            }
            
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: parent.color = "#313244"
                onExited: parent.color = "transparent"
                onClicked: {
                    PowerManager.shutdown()
                    root.popoutVisible = false
                }
            }
        }
    }
}