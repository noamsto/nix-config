import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../services"

PopoutWrapper {
    id: root
    
    popoutWidth: 280
    popoutHeight: 240
    
    ColumnLayout {
        anchors.fill: parent
        spacing: 12
        
        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            
            Text {
                text: Bluetooth.getBluetoothIcon()
                font.family: "Symbols Nerd Font"
                font.pixelSize: 20
                color: Bluetooth.getBluetoothColor()
            }
            
            Text {
                text: "Bluetooth"
                font.pixelSize: 16
                font.weight: Font.Medium
                color: "#cdd6f4"
                Layout.fillWidth: true
            }
            
            Text {
                text: !Bluetooth.available ? "Not Available" : 
                      !Bluetooth.enabled ? "Disabled" : 
                      Bluetooth.hasConnectedDevices ? "Connected" : "Enabled"
                font.pixelSize: 12
                color: !Bluetooth.available ? "#585b70" : 
                       !Bluetooth.enabled ? "#f38ba8" : 
                       Bluetooth.hasConnectedDevices ? "#a6e3a1" : "#f9e2af"
            }
            
            // Toggle button
            Rectangle {
                width: 24
                height: 24
                radius: 4
                color: Bluetooth.enabled ? "#89b4fa" : "#45475a"
                border.color: Bluetooth.enabled ? "#89b4fa" : "#6c7086"
                border.width: 1
                visible: Bluetooth.available
                
                Text {
                    anchors.centerIn: parent
                    text: Bluetooth.enabled ? "󰄐" : "󰄑"
                    font.family: "Symbols Nerd Font"
                    font.pixelSize: 12
                    color: Bluetooth.enabled ? "#11111b" : "#cdd6f4"
                }
                
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: parent.scale = 1.1
                    onExited: parent.scale = 1.0
                    onClicked: Bluetooth.toggleBluetooth()
                }
                
                Behavior on scale {
                    NumberAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#45475a"
        }
        
        // Not available message
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12
            visible: !Bluetooth.available
            
            Item {
                Layout.fillHeight: true
            }
            
            Text {
                text: "󰂲"
                font.family: "Symbols Nerd Font"
                font.pixelSize: 48
                color: "#585b70"
                Layout.alignment: Qt.AlignHCenter
            }
            
            Text {
                text: "Bluetooth Not Available"
                font.pixelSize: 14
                font.weight: Font.Medium
                color: "#9399b2"
                Layout.alignment: Qt.AlignHCenter
            }
            
            Text {
                text: "Make sure Bluetooth is supported\nand properly configured"
                font.pixelSize: 12
                color: "#6c7086"
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
            }
            
            Item {
                Layout.fillHeight: true
            }
        }
        
        // Disabled message
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12
            visible: Bluetooth.available && !Bluetooth.enabled
            
            Item {
                Layout.fillHeight: true
            }
            
            Text {
                text: "󰂲"
                font.family: "Symbols Nerd Font"
                font.pixelSize: 48
                color: "#f38ba8"
                Layout.alignment: Qt.AlignHCenter
            }
            
            Text {
                text: "Bluetooth Disabled"
                font.pixelSize: 14
                font.weight: Font.Medium
                color: "#cdd6f4"
                Layout.alignment: Qt.AlignHCenter
            }
            
            Text {
                text: "Click the toggle button to enable Bluetooth"
                font.pixelSize: 12
                color: "#9399b2"
                Layout.alignment: Qt.AlignHCenter
            }
            
            Item {
                Layout.fillHeight: true
            }
        }
        
        // Device list
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8
            visible: Bluetooth.available && Bluetooth.enabled
            
            Text {
                text: "Devices"
                font.pixelSize: 14
                font.weight: Font.Medium
                color: "#cdd6f4"
            }
            
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                
                ListView {
                    model: Bluetooth.devices
                    spacing: 4
                    
                    delegate: Rectangle {
                        width: parent.width
                        height: 56
                        radius: 8
                        color: modelData.connected ? "#45475a" : "transparent"
                        border.color: modelData.connected ? "#6c7086" : "transparent"
                        border.width: 1
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12
                            
                            // Device icon
                            Text {
                                text: Bluetooth.getDeviceIcon(modelData)
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: 20
                                color: modelData.connected ? "#89b4fa" : "#6c7086"
                            }
                            
                            // Device info
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                
                                Text {
                                    text: modelData.name || "Unknown Device"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: "#cdd6f4"
                                    elide: Text.ElideRight
                                }
                                
                                Text {
                                    text: modelData.connected ? "Connected" : 
                                          modelData.paired ? "Paired" : "Available"
                                    font.pixelSize: 11
                                    color: modelData.connected ? "#a6e3a1" : 
                                           modelData.paired ? "#f9e2af" : "#9399b2"
                                }
                            }
                            
                            // Connect/Disconnect button
                            Rectangle {
                                width: 32
                                height: 32
                                radius: 6
                                color: modelData.connected ? "#f38ba8" : "#89b4fa"
                                border.color: modelData.connected ? "#f38ba8" : "#89b4fa"
                                border.width: 1
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.connected ? "󰤄" : "󰤇"
                                    font.family: "Symbols Nerd Font"
                                    font.pixelSize: 14
                                    color: "#11111b"
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: parent.scale = 1.1
                                    onExited: parent.scale = 1.0
                                    onClicked: {
                                        if (modelData.connected) {
                                            Bluetooth.disconnectDevice(modelData.address);
                                        } else {
                                            Bluetooth.connectDevice(modelData.address);
                                        }
                                    }
                                }
                                
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 100
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.color = "#313244"
                            onExited: parent.color = modelData.connected ? "#45475a" : "transparent"
                        }
                    }
                }
            }
            
            // Empty state
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
                visible: Bluetooth.devices.length === 0
                
                Item {
                    Layout.fillHeight: true
                }
                
                Text {
                    text: "󰂱"
                    font.family: "Symbols Nerd Font"
                    font.pixelSize: 32
                    color: "#6c7086"
                    Layout.alignment: Qt.AlignHCenter
                }
                
                Text {
                    text: "No Devices Found"
                    font.pixelSize: 13
                    color: "#9399b2"
                    Layout.alignment: Qt.AlignHCenter
                }
                
                Text {
                    text: "Make sure your devices are\nin pairing mode"
                    font.pixelSize: 11
                    color: "#6c7086"
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                }
                
                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }
}