import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../services"

Item {
    id: root
    
    implicitWidth: 240
    implicitHeight: columnLayout.implicitHeight
    
    ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        width: 240
        spacing: 12
        
        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            
            Text {
                id: headerIcon
                text: Network.getNetworkIcon(Network.active?.strength || 0)
                font.family: "Symbols Nerd Font"
                font.pixelSize: 20
                color: Network.getNetworkColor(Network.active?.strength || 0)
            }
            
            Text {
                text: "Network"
                font.pixelSize: 16
                font.weight: Font.Medium
                color: "#cdd6f4"
                Layout.fillWidth: true
            }
            
            Text {
                text: Network.connected ? "Connected" : "Disconnected"
                font.pixelSize: 12
                color: Network.connected ? "#a6e3a1" : "#f38ba8"
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#45475a"
        }
        
        // Current connection info
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: Network.connected
            
            Text {
                text: "Current Connection"
                font.pixelSize: 14
                font.weight: Font.Medium
                color: "#cdd6f4"
            }
            
            Rectangle {
                Layout.fillWidth: true
                height: 60
                radius: 8
                color: "#313244"
                border.color: "#45475a"
                border.width: 1
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    
                    Text {
                        text: Network.getNetworkIcon(Network.active?.strength || 0)
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: 24
                        color: Network.getNetworkColor(Network.active?.strength || 0)
                    }
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        
                        Text {
                            text: Network.connectionType === "wifi" ? 
                                  (Network.active?.ssid || "WiFi") : 
                                  "Ethernet"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: "#cdd6f4"
                        }
                        
                        Text {
                            text: Network.connectionType === "wifi" ? 
                                  `Signal: ${Network.active?.strength || 0}%` : 
                                  "Wired Connection"
                            font.pixelSize: 12
                            color: "#9399b2"
                        }
                    }
                }
            }
        }
        
        // Available networks
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8
            visible: Network.connectionType === "wifi"
            
            Text {
                text: "Available Networks"
                font.pixelSize: 14
                font.weight: Font.Medium
                color: "#cdd6f4"
            }
            
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                
                ListView {
                    model: Network.networks
                    spacing: 4
                    
                    delegate: Rectangle {
                        width: parent.width
                        height: 44
                        radius: 6
                        color: modelData.active ? "#45475a" : "transparent"
                        border.color: modelData.active ? "#6c7086" : "transparent"
                        border.width: 1
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 12
                            
                            Text {
                                text: Network.getNetworkIcon(modelData.strength)
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: 16
                                color: Network.getNetworkColor(modelData.strength)
                            }
                            
                            Text {
                                text: modelData.ssid
                                font.pixelSize: 13
                                color: "#cdd6f4"
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            
                            Text {
                                text: modelData.active ? "󰗠" : ""
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: 12
                                color: "#a6e3a1"
                                visible: modelData.active
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.color = "#313244"
                            onExited: parent.color = modelData.active ? "#45475a" : "transparent"
                            onClicked: {
                                // TODO: Implement network connection
                                console.log("Connect to network:", modelData.ssid);
                            }
                        }
                    }
                }
            }
        }
    }
}