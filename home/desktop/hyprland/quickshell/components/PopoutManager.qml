import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../services"
import "../popouts"

Item {
    id: root
    
    property string currentName: ""
    property real currentCenter: 0
    property bool hasCurrent: false
    
    function setPopout(name, center) {
        currentName = name;
        currentCenter = center;
        hasCurrent = true;
    }
    
    function close() {
        hasCurrent = false;
        currentName = "";
    }
    
    visible: width > 0 && height > 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    
    // Position the popout container
    Item {
        id: container
        
        anchors.left: parent.right
        anchors.leftMargin: 8
        y: Math.max(8, Math.min(parent.height - implicitHeight - 8, currentCenter - implicitHeight / 2))
        
        implicitWidth: activePopout?.implicitWidth || 0
        implicitHeight: activePopout?.implicitHeight || 0
        
        readonly property Item activePopout: {
            const children = content.children;
            for (let i = 0; i < children.length; i++) {
                if (children[i].shouldBeActive) {
                    return children[i];
                }
            }
            return null;
        }
        
        Rectangle {
            anchors.fill: parent
            color: "#1e1e2e"
            radius: 12
            border.color: "#585b70"
            border.width: 1
            opacity: 0.95
            visible: parent.implicitWidth > 0 && parent.implicitHeight > 0
            
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
            id: content
            anchors.fill: parent
            anchors.margins: 12
            
            // Network popout
            Loader {
                id: networkLoader
                property bool shouldBeActive: root.currentName === "network"
                anchors.fill: parent
                active: shouldBeActive
                sourceComponent: NetworkPopoutContent { }
            }
            
            // Battery popout
            Loader {
                id: batteryLoader
                property bool shouldBeActive: root.currentName === "battery"
                anchors.fill: parent
                active: shouldBeActive
                sourceComponent: BatteryPopout { }
            }
            
            // Volume popout
            Loader {
                id: volumeLoader
                property bool shouldBeActive: root.currentName === "volume"
                anchors.fill: parent
                active: shouldBeActive
                sourceComponent: VolumePopout { }
            }
            
            // Bluetooth popout
            Loader {
                id: bluetoothLoader
                property bool shouldBeActive: root.currentName === "bluetooth"
                anchors.fill: parent
                active: shouldBeActive
                sourceComponent: BluetoothPopout { }
            }
            
            // Power popout
            Loader {
                id: powerLoader
                property bool shouldBeActive: root.currentName === "power"
                anchors.fill: parent
                active: shouldBeActive
                sourceComponent: PowerPopoutContent { }
            }
        }
        
        Behavior on implicitWidth {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
        
        Behavior on implicitHeight {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
        
        Behavior on y {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
    }
    
    // Auto-hide on click outside
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }
}