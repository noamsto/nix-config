import QtQuick
import QtQuick.Layouts
import "../services"

PopoutWrapper {
    id: root
    
    popoutWidth: 240
    popoutHeight: 160
    
    ColumnLayout {
        anchors.fill: parent
        spacing: 12
        
        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            
            Text {
                text: Audio.getVolumeIcon()
                font.family: "Symbols Nerd Font"
                font.pixelSize: 20
                color: Audio.getVolumeColor()
            }
            
            Text {
                text: "Volume"
                font.pixelSize: 16
                font.weight: Font.Medium
                color: "#cdd6f4"
                Layout.fillWidth: true
            }
            
            Text {
                text: Audio.muted ? "Muted" : `${Math.round(Audio.volume)}%`
                font.pixelSize: 14
                font.weight: Font.Medium
                color: Audio.getVolumeColor()
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#45475a"
        }
        
        // Volume control
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Text {
                text: "Volume Control"
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
                    
                    // Volume down button
                    Rectangle {
                        width: 32
                        height: 32
                        radius: 6
                        color: "#45475a"
                        border.color: "#6c7086"
                        border.width: 1
                        
                        Text {
                            anchors.centerIn: parent
                            text: "󰝞"
                            font.family: "Symbols Nerd Font"
                            font.pixelSize: 16
                            color: "#cdd6f4"
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.color = "#585b70"
                            onExited: parent.color = "#45475a"
                            onClicked: Audio.decreaseVolume(5)
                        }
                    }
                    
                    // Volume slider
                    Rectangle {
                        Layout.fillWidth: true
                        height: 8
                        radius: 4
                        color: "#45475a"
                        
                        Rectangle {
                            id: volumeBar
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * (Audio.volume / 100)
                            radius: 4
                            color: Audio.getVolumeColor()
                            
                            Behavior on width {
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                const newVolume = (mouse.x / parent.width) * 100;
                                Audio.setVolume(newVolume);
                            }
                        }
                    }
                    
                    // Volume up button
                    Rectangle {
                        width: 32
                        height: 32
                        radius: 6
                        color: "#45475a"
                        border.color: "#6c7086"
                        border.width: 1
                        
                        Text {
                            anchors.centerIn: parent
                            text: "󰝝"
                            font.family: "Symbols Nerd Font"
                            font.pixelSize: 16
                            color: "#cdd6f4"
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.color = "#585b70"
                            onExited: parent.color = "#45475a"
                            onClicked: Audio.increaseVolume(5)
                        }
                    }
                }
            }
        }
        
        // Device information
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            
            Text {
                text: "Audio Device"
                font.pixelSize: 14
                font.weight: Font.Medium
                color: "#cdd6f4"
            }
            
            Rectangle {
                Layout.fillWidth: true
                height: 50
                radius: 8
                color: "#313244"
                border.color: "#45475a"
                border.width: 1
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    
                    Text {
                        text: Audio.deviceIcon
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: 20
                        color: "#89b4fa"
                    }
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        
                        Text {
                            text: Audio.deviceName || "Default Device"
                            font.pixelSize: 13
                            color: "#cdd6f4"
                            elide: Text.ElideRight
                        }
                        
                        Text {
                            text: Audio.available ? "Ready" : "Not Available"
                            font.pixelSize: 11
                            color: Audio.available ? "#a6e3a1" : "#f38ba8"
                        }
                    }
                    
                    // Mute button
                    Rectangle {
                        width: 32
                        height: 32
                        radius: 6
                        color: Audio.muted ? "#f38ba8" : "#45475a"
                        border.color: Audio.muted ? "#f38ba8" : "#6c7086"
                        border.width: 1
                        
                        Text {
                            anchors.centerIn: parent
                            text: Audio.muted ? "󰝟" : "󰕿"
                            font.family: "Symbols Nerd Font"
                            font.pixelSize: 16
                            color: Audio.muted ? "#11111b" : "#cdd6f4"
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.color = Audio.muted ? "#f38ba8" : "#585b70"
                            onExited: parent.color = Audio.muted ? "#f38ba8" : "#45475a"
                            onClicked: Audio.toggleMute()
                        }
                    }
                }
            }
        }
    }
}