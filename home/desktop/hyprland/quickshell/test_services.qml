import QtQuick
import \"./services\"

Item {
    id: root
    width: 400
    height: 300
    
    Column {
        anchors.centerIn: parent
        spacing: 20
        
        Text {
            text: \"Network Status Test\"
            font.pixelSize: 16
            color: \"white\"
        }
        
        Text {
            text: `Connection: ${Network.connectionType}`
            color: \"white\"
        }
        
        Text {
            text: `Connected: ${Network.connected}`
            color: \"white\"
        }
        
        Text {
            text: `Strength: ${Network.active?.strength ?? 0}%`
            color: \"white\"
        }
        
        Text {
            text: \"Battery Status Test\"
            font.pixelSize: 16
            color: \"white\"
        }
        
        Text {
            text: `Battery Present: ${Battery.present}`
            color: \"white\"
        }
        
        Text {
            text: `Battery Level: ${Math.round(Battery.percentage * 100)}%`
            color: \"white\"
        }
        
        Text {
            text: `Charging: ${Battery.charging}`
            color: \"white\"
        }
        
        Text {
            text: `Status: ${Battery.status}`
            color: \"white\"
        }
        
        Text {
            text: \"Power Management Test\"
            font.pixelSize: 16
            color: \"white\"
        }
        
        Text {
            text: `Can Shutdown: ${PowerManager.canShutdown}`
            color: \"white\"
        }
        
        Text {
            text: `Can Suspend: ${PowerManager.canSuspend}`
            color: \"white\"
        }
        
        Text {
            text: `Can Hibernate: ${PowerManager.canHibernate}`
            color: \"white\"
        }
    }
}

