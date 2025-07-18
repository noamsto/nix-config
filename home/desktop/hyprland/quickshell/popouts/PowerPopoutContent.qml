import QtQuick
import QtQuick.Layouts
import "../services"

Item {
    id: root
    
    implicitWidth: 160
    implicitHeight: 120
    
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
                    // Close popout - will be handled by parent
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
                    // Close popout - will be handled by parent
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
                    // Close popout - will be handled by parent
                }
            }
        }
    }
}