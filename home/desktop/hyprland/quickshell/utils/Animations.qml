pragma Singleton

import QtQuick

QtObject {
    id: root
    
    // Animation durations
    readonly property int fast: 100
    readonly property int medium: 200
    readonly property int slow: 300
    readonly property int slower: 500
    
    // Easing types
    readonly property int easeOut: Easing.OutCubic
    readonly property int easeIn: Easing.InCubic
    readonly property int easeInOut: Easing.InOutCubic
    readonly property int easeBack: Easing.OutBack
    readonly property int easeElastic: Easing.OutElastic
    readonly property int easeBounce: Easing.OutBounce
    
    // Common animation functions
    function fadeIn(target, duration = medium) {
        return createFadeAnimation(target, 0, 1, duration);
    }
    
    function fadeOut(target, duration = medium) {
        return createFadeAnimation(target, 1, 0, duration);
    }
    
    function scaleIn(target, duration = medium) {
        return createScaleAnimation(target, 0, 1, duration);
    }
    
    function scaleOut(target, duration = medium) {
        return createScaleAnimation(target, 1, 0, duration);
    }
    
    function slideIn(target, direction = "up", duration = medium) {
        return createSlideAnimation(target, direction, true, duration);
    }
    
    function slideOut(target, direction = "up", duration = medium) {
        return createSlideAnimation(target, direction, false, duration);
    }
    
    // Animation creators
    function createFadeAnimation(target, from, to, duration) {
        return Qt.createQmlObject(`
            import QtQuick 2.15
            NumberAnimation {
                target: ${target}
                property: "opacity"
                from: ${from}
                to: ${to}
                duration: ${duration}
                easing.type: Easing.OutCubic
            }
        `, target);
    }
    
    function createScaleAnimation(target, from, to, duration) {
        return Qt.createQmlObject(`
            import QtQuick 2.15
            NumberAnimation {
                target: ${target}
                property: "scale"
                from: ${from}
                to: ${to}
                duration: ${duration}
                easing.type: Easing.OutBack
            }
        `, target);
    }
    
    function createSlideAnimation(target, direction, slideIn, duration) {
        const property = (direction === "up" || direction === "down") ? "y" : "x";
        const distance = 20;
        const from = slideIn ? 
            (direction === "up" || direction === "left" ? -distance : distance) : 0;
        const to = slideIn ? 0 : 
            (direction === "up" || direction === "left" ? -distance : distance);
        
        return Qt.createQmlObject(`
            import QtQuick 2.15
            NumberAnimation {
                target: ${target}
                property: "${property}"
                from: ${from}
                to: ${to}
                duration: ${duration}
                easing.type: Easing.OutCubic
            }
        `, target);
    }
    
    // Predefined animation behaviors
    function createHoverBehavior(target) {
        return Qt.createQmlObject(`
            import QtQuick 2.15
            Behavior on scale {
                NumberAnimation {
                    duration: ${fast}
                    easing.type: Easing.OutCubic
                }
            }
        `, target);
    }
    
    function createColorBehavior(target) {
        return Qt.createQmlObject(`
            import QtQuick 2.15
            Behavior on color {
                ColorAnimation {
                    duration: ${medium}
                    easing.type: Easing.OutCubic
                }
            }
        `, target);
    }
    
    function createOpacityBehavior(target) {
        return Qt.createQmlObject(`
            import QtQuick 2.15
            Behavior on opacity {
                NumberAnimation {
                    duration: ${medium}
                    easing.type: Easing.OutCubic
                }
            }
        `, target);
    }
}