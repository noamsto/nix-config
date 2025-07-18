# Hyprland Quickshell Bar

A modern, vertical status bar for Hyprland built with Quickshell.

## Features

- **Dynamic Workspace Indicators**: Shows active workspaces with visual feedback
- **System Tray Integration**: Displays system tray icons with click support
- **Network Status**: Real-time network connection status with signal strength
- **Battery Status**: Dynamic battery indicator with percentage and charging state
- **Power Management**: Power control menu with confirmation dialogs
- **Window Title Display**: Shows active window with enhanced icon mapping
- **Date/Time Display**: Current time and date

## Components

### Services
- **Network.qml**: NetworkManager integration for network status
- **Battery.qml**: Battery status monitoring via `/sys/class/power_supply/`
- **PowerManager.qml**: System power management via systemd/loginctl

### Components
- **NetworkStatus.qml**: Network status indicator with tooltip
- **BatteryStatus.qml**: Battery status indicator with tooltip
- **PowerControl.qml**: Power management menu with confirmations
- **WindowTitle.qml**: Enhanced window title display with icon mapping

## Dependencies

- Quickshell framework
- NetworkManager (for network status)
- UPower (optional, for enhanced battery info)
- systemd/loginctl (for power management)
- Nerd Font (for icons)

## Installation

1. Ensure Quickshell is installed
2. Copy the quickshell directory to your Hyprland configuration
3. Configure Hyprland to launch quickshell with the bar configuration

## Configuration

The bar uses the Catppuccin Mocha color scheme by default. Colors can be customized in the component files.

### Color Scheme
- Background: `#1e1e2e`
- Surface: `#313244`
- Border: `#585b70`
- Text: `#cdd6f4`
- Accent: `#cba6f7`
- Success: `#a6e3a1`
- Warning: `#f9e2af`
- Error: `#f38ba8`

## Usage

### Network Status
- Shows WiFi signal strength or ethernet connection
- Hover for detailed connection information
- Click for network actions (can be extended)

### Battery Status
- Displays battery percentage and charging state
- Color-coded based on battery level
- Hover for detailed battery information

### Power Management
- Click the power button to open the power menu
- Available actions: Lock, Logout, Suspend, Hibernate, Reboot, Shutdown
- Destructive actions require confirmation

### Window Title
- Shows icon and title of active window
- Enhanced icon mapping for common applications
- Hover for full window information

## Customization

### Adding New Applications to Icon Mapping

Edit `components/WindowTitle.qml` and add entries to the `iconMappings` object:

```javascript
const iconMappings = {
    "your-app-class": "icon-name",
    // ... other mappings
};
```

### Modifying Colors

Colors are defined in each component. To change the theme, update the color values in:
- `BarWindow.qml` (main bar)
- `components/*.qml` (individual components)

### Adding New Status Indicators

1. Create a new service in `services/`
2. Create a corresponding component in `components/`
3. Add the component to `BarWindow.qml`
4. Update `services/qmldir` if needed

## Testing

Use `test_services.qml` to verify that services are working correctly:

```bash
quickshell test_services.qml
```

## Troubleshooting

### Network Status Not Working
- Ensure NetworkManager is running: `systemctl status NetworkManager`
- Check `nmcli` command availability
- Verify user permissions for NetworkManager

### Battery Status Not Working
- Check if `/sys/class/power_supply/BAT0/` exists
- Verify UPower is installed and running
- Check battery device name (might be BAT1, etc.)

### Power Management Not Working
- Ensure systemd is running
- Check user permissions for systemctl/loginctl
- Verify polkit configuration

## Contributing

Contributions are welcome! Please:

1. Follow the existing code style
2. Test changes thoroughly
3. Update documentation as needed
4. Consider performance impact of changes

## License

This project follows the same license as the parent nix-config repository.
"}

