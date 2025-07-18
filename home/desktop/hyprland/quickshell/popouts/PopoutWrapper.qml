import QtQuick
import QtQuick.Effects
import Quickshell

PanelWindow {
    id: root
    
    property alias contentItem: contentContainer
    property real popoutWidth: 260
    property real popoutHeight: 320
    property bool popoutVisible: false
    property real animationDuration: 200
    property real targetY: 0  // Target Y position for vertical alignment
    
    anchors.left: true
    anchors.top: true
    anchors.bottom: true
    
    margins.left: 72  // Bar width (56) + gap (16)
    margins.right: 0
    margins.top: 0
    margins.bottom: 0
    
    color: "transparent"
    
    implicitWidth: popoutVisible ? popoutWidth : 0
    implicitHeight: popoutVisible ? popoutHeight : 0
    
    visible: popoutVisible
    
    // Animate appearance
    Behavior on implicitWidth {
        NumberAnimation {
            duration: animationDuration
            easing.type: Easing.OutCubic
        }
    }
    
    Behavior on implicitHeight {
        NumberAnimation {
            duration: animationDuration
            easing.type: Easing.OutCubic
        }
    }
    
    Rectangle {
        id: background
        anchors.left: parent.left
        y: targetY
        width: popoutWidth
        height: popoutHeight
        color: "#1e1e2e"
        radius: 12
        border.color: "#585b70"
        border.width: 1
        opacity: 0.95
        
        // Drop shadow
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#00000060"
            shadowBlur: 0.8
            shadowVerticalOffset: 4
            shadowHorizontalOffset: 2
        }
    }
    
    Item {
        id: contentContainer
        anchors.fill: background
        anchors.margins: 12
        clip: true
    }
    
    // Auto-hide on click outside
    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.popoutVisible = false;
        }
    }
    
    function show() {
        popoutVisible = true;
    }
    
    function hide() {
        popoutVisible = false;
    }
    
    function toggle() {
        popoutVisible = !popoutVisible;
    }
}