import QtQuick
import QtQuick.Layouts
import "../services"

Rectangle {
    id: root
    
    anchors.fill: parent
    anchors.margins: 12
    color: "#1e1e2e"
    radius: 12
    border.color: "#585b70"
    border.width: 1
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12
        
        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            
            Text {
                text: Battery.getBatteryIcon()
                font.family: "Symbols Nerd Font"
                font.pixelSize: 20
                color: Battery.getBatteryColor()
            }
            
            Text {
                text: "Battery"
                font.pixelSize: 16
                font.weight: Font.Medium
                color: "#cdd6f4"
                Layout.fillWidth: true
            }
            
            Text {
                text: `${Math.round(Battery.percentage * 100)}%`
                font.pixelSize: 14
                font.weight: Font.Medium
                color: Battery.getBatteryColor()
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#45475a"
        }
        
        // Battery level visualization
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            
            Text {
                text: "Battery Level"
                font.pixelSize: 14
                font.weight: Font.Medium
                color: "#cdd6f4"
            }
            
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: batteryLevelRow.implicitHeight + 16
                radius: 8
                color: "#313244"
                border.color: "#45475a"
                border.width: 1
                
                RowLayout {
                    id: batteryLevelRow
                    anchors.centerIn: parent
                    width: parent.width - 16
                    spacing: 8
                    
                    // Battery icon
                    Text {
                        text: Battery.getBatteryIcon()
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: 24
                        color: Battery.getBatteryColor()
                    }
                    
                    // Battery progress bar
                    Rectangle {
                        Layout.fillWidth: true
                        height: 8
                        radius: 4
                        color: "#45475a"
                        
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * Battery.percentage
                            radius: 4
                            color: Battery.getBatteryColor()
                            
                            Behavior on width {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                    
                    // Percentage text
                    Text {
                        text: `${Math.round(Battery.percentage * 100)}%`
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        color: "#cdd6f4"
                    }
                }
            }
        }
        
        // Battery status information
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            
            Text {
                text: "Status Information"
                font.pixelSize: 14
                font.weight: Font.Medium
                color: "#cdd6f4"
            }
            
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: statusInfoColumn.implicitHeight + 16
                radius: 8
                color: "#313244"
                border.color: "#45475a"
                border.width: 1
                
                ColumnLayout {
                    id: statusInfoColumn
                    anchors.centerIn: parent
                    width: parent.width - 16
                    spacing: 4
                    
                    RowLayout {
                        Layout.fillWidth: true
                        
                        Text {
                            text: "Status:"
                            font.pixelSize: 12
                            color: "#9399b2"
                        }
                        
                        Text {
                            text: Battery.status
                            font.pixelSize: 12
                            color: Battery.charging ? "#a6e3a1" : "#f9e2af"
                            Layout.fillWidth: true
                        }
                        
                        Text {
                            text: Battery.charging ? "󰂄" : "󰂃"
                            font.family: "Symbols Nerd Font"
                            font.pixelSize: 12
                            color: Battery.charging ? "#a6e3a1" : "#f9e2af"
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        
                        Text {
                            text: "Health:"
                            font.pixelSize: 12
                            color: "#9399b2"
                        }
                        
                        Text {
                            text: Battery.present ? Battery.health : "Unknown"
                            font.pixelSize: 12
                            color: Battery.present ? "#a6e3a1" : "#9399b2"
                            Layout.fillWidth: true
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        
                        Text {
                            text: "Time:"
                            font.pixelSize: 12
                            color: "#9399b2"
                        }
                        
                        Text {
                            text: Battery.timeRemaining > 0 ? Battery.formatTimeRemaining() : "Calculating..."
                            font.pixelSize: 12
                            color: "#cdd6f4"
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }
}