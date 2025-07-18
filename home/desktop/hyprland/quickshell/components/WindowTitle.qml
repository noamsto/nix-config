import QtQuick
import Quickshell.Hyprland

Rectangle {
    id: root
    
    width: 36
    height: 36
    radius: 18
    color: "#313244"
    border.color: "#45475a"
    border.width: 1
    
    property string windowClass: ""
    property string windowTitle: ""
    
    // Enhanced icon mapping function
    function getEnhancedIconForClass(windowClass) {
        if (!windowClass) return "";
        
        // Common application mappings
        const iconMappings = {
            // Browsers
            "brave-browser": "brave",
            "firefox": "firefox",
            "google-chrome": "google-chrome",
            "chromium": "chromium",
            "microsoft-edge": "microsoft-edge",
            
            // Development
            "code": "vscode",
            "code-oss": "vscode",
            "vscodium": "vscodium",
            "neovim": "neovim",
            "vim": "vim",
            "emacs": "emacs",
            "sublime_text": "sublime-text",
            "atom": "atom",
            "jetbrains-idea": "intellij-idea",
            "jetbrains-pycharm": "pycharm",
            "jetbrains-webstorm": "webstorm",
            
            // Media
            "vlc": "vlc",
            "mpv": "mpv",
            "spotify": "spotify",
            "com.github.th_ch.youtube_music": "youtube-music",
            "discord": "discord",
            "telegram": "telegram",
            "signal": "signal",
            "slack": "slack",
            "zoom": "zoom",
            
            // System
            "org.gnome.nautilus": "nautilus",
            "thunar": "thunar",
            "dolphin": "dolphin",
            "nemo": "nemo",
            "pcmanfm": "pcmanfm",
            "kitty": "kitty",
            "alacritty": "alacritty",
            "wezterm": "wezterm",
            "foot": "foot",
            "org.gnome.terminal": "gnome-terminal",
            "konsole": "konsole",
            
            // Office
            "libreoffice-writer": "libreoffice-writer",
            "libreoffice-calc": "libreoffice-calc",
            "libreoffice-impress": "libreoffice-impress",
            "thunderbird": "thunderbird",
            
            // Graphics
            "gimp": "gimp",
            "inkscape": "inkscape",
            "blender": "blender",
            "krita": "krita",
            "darktable": "darktable",
            
            // Games
            "steam": "steam",
            "lutris": "lutris",
            "heroic": "heroic",
            "minecraft": "minecraft",
            
            // Utilities
            "org.gnome.calculator": "gnome-calculator",
            "qalculate-gtk": "qalculate",
            "org.gnome.gedit": "gedit",
            "mousepad": "mousepad",
        };
        
        const lowerClass = windowClass.toLowerCase();
        
        // Check direct mappings first
        if (iconMappings[lowerClass]) {
            return `image://icon/${iconMappings[lowerClass]}`;
        }
        
        // Handle reverse domain notation (org.example.app -> app)
        if (lowerClass.includes('.')) {
            const parts = lowerClass.split('.');
            const appName = parts[parts.length - 1];
            if (iconMappings[appName]) {
                return `image://icon/${iconMappings[appName]}`;
            }
            return `image://icon/${appName}`;
        }
        
        // Handle common prefixes
        if (lowerClass.startsWith('org.')) {
            return `image://icon/${lowerClass.substring(4)}`;
        }
        if (lowerClass.startsWith('com.')) {
            return `image://icon/${lowerClass.substring(4)}`;
        }
        
        // Default fallback
        return `image://icon/${lowerClass}`;
    }
    
    // Truncate title for display
    function truncateTitle(title, maxLength = 20) {
        if (!title || title.length <= maxLength) return title;
        return title.substring(0, maxLength - 3) + "...";
    }
    
    // Main icon display
    Image {
        id: windowIcon
        anchors.centerIn: parent
        width: 24
        height: 24
        source: getEnhancedIconForClass(root.windowClass)
        smooth: true
        cache: true
        
        // Fallback to generic icon if app icon fails
        onStatusChanged: {
            if (status === Image.Error) {
                source = "image://icon/application-x-executable";
            }
        }
    }
    
    // Fallback text if no icon is available
    Text {
        id: fallbackText
        anchors.centerIn: parent
        text: root.windowClass ? root.windowClass.charAt(0).toUpperCase() : "?"
        color: "#cdd6f4"
        font.pixelSize: 14
        font.weight: Font.Bold
        visible: windowIcon.status === Image.Error || !windowIcon.source
    }
    
    // Hover interactions
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onEntered: {
            parent.color = "#45475a";
            if (root.windowTitle) {
                tooltip.visible = true;
            }
        }
        onExited: {
            parent.color = "#313244";
            tooltip.visible = false;
        }
        onClicked: {
            // Could implement window actions here
            console.log("Window clicked:", root.windowClass, root.windowTitle);
        }
    }
    
    Behavior on color { 
        ColorAnimation { duration: 150 } 
    }
    
    // Tooltip showing full window title
    Rectangle {
        id: tooltip
        visible: false
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(tooltipText.implicitWidth + 16, 120)
        height: tooltipText.implicitHeight + 12
        color: "#1e1e2e"
        border.color: "#585b70"
        border.width: 1
        radius: 8
        z: 1000
        
        Text {
            id: tooltipText
            anchors.centerIn: parent
            color: "#cdd6f4"
            font.pixelSize: 11
            text: {
                let tooltip = "";
                if (root.windowTitle) {
                    tooltip += `Title: ${root.windowTitle}`;
                }
                if (root.windowClass) {
                    if (tooltip) tooltip += "\\n";
                    tooltip += `Class: ${root.windowClass}`;
                }
                return tooltip || "No active window";
            }
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
    }
    
    // Update display when window changes
    onWindowClassChanged: {
        windowIcon.source = getEnhancedIconForClass(windowClass);
    }
}

