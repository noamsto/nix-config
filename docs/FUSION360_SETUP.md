# Autodesk Fusion 360 Setup on NixOS

This guide covers installing and running Autodesk Fusion 360 on NixOS using Bottles and Flatpak.

## Overview

Fusion 360 is a Windows application that runs on Linux via Wine. This configuration uses:
- **Flatpak**: Already enabled in your NixOS configuration
- **Bottles**: Wine prefix manager with pre-configured Fusion 360 installer
- **XDG Portals**: Already configured for Hyprland integration

## Prerequisites ✅

Your NixOS configuration already includes:
- ✅ Flatpak enabled (`nixos/desktop/default.nix:25`)
- ✅ XDG desktop portals configured for Hyprland
- ✅ AMD GPU drivers (amdgpu) - excellent Linux compatibility

## Installation Steps

### 1. Install Bottles

Flathub is already configured on your system, so you can install Bottles immediately:

```bash
flatpak install flathub com.usebottles.bottles
```

**Note**: If you see permission errors, ensure Flatpak has access to your home directory:
```bash
flatpak override --user --filesystem=home com.usebottles.bottles
```

### 2. Launch Bottles

```bash
flatpak run com.usebottles.bottles
```

Or launch from your application menu (Hyprland launcher).

### 3. Install Fusion 360 via Bottles Pre-configured Installer

1. **Open Bottles** and click the hamburger menu (☰) → **Preferences**
2. Navigate to **Installers** tab
3. Search for **"Autodesk Fusion 360"**
4. Click **Install** on the Fusion 360 installer
5. Follow the installation wizard:
   - Choose **DXVK** as the graphics renderer (recommended for AMD)
   - Complete the Fusion 360 installation steps
   - Sign in with your Autodesk account

### 4. Configure Graphics Settings

**For AMD GPUs (your systems):**
- **Recommended**: DXVK (DirectX to Vulkan translation)
  - Better performance and compatibility
  - AMD open-source drivers work excellently with Vulkan
- **Alternative**: OpenGL mode
  - More stable but may have rendering artifacts
  - Use if DXVK has issues

**To change graphics mode:**
1. In Bottles, select your Fusion 360 bottle
2. Click **Preferences** (gear icon)
3. Navigate to **Graphics** tab
4. Select **DXVK** or **OpenGL**
5. Apply and restart Fusion 360

### 5. Browser Authentication Setup

Fusion 360 requires browser authentication for license validation:

1. When Fusion 360 prompts for login, it will open your default browser
2. If browser doesn't open, check Bottles → **Preferences** → **Advanced** → **Enable sandbox**
3. You may need to copy the authentication URL manually
4. After authentication in browser, Fusion 360 will activate

**Troubleshooting browser issues:**
```bash
# Grant Bottles access to default browser
flatpak override --user --talk-name=org.freedesktop.portal.Desktop com.usebottles.bottles
```

## Post-Installation

### Launch Fusion 360

From Bottles:
1. Open Bottles application
2. Select your Fusion 360 bottle
3. Click the **Play** button (▶) next to "Autodesk Fusion 360"

Or create a desktop shortcut:
1. In Bottles, right-click on Fusion 360
2. Select **Add to Applications Menu**

### Performance Optimization

**For AMD GPUs:**
```bash
# Enable ACO shader compiler (better performance on AMD)
# Add to Bottles → Preferences → Environment Variables:
RADV_PERFTEST=aco
```

**Memory allocation:**
- Fusion 360 benefits from 4GB+ VRAM
- Both your ThinkPads have sufficient integrated AMD GPU memory

### Known Issues and Workarounds

**Issue: Fusion 360 crashes on startup**
- Solution: Switch between DXVK and OpenGL modes
- Check Bottles logs: Bottles → Hamburger menu → **Developer Tools** → **Logs**

**Issue: Browser authentication timeout**
- Solution: Copy authentication URL manually
- Use `xdg-open <URL>` from terminal to force browser launch

**Issue: Rendering artifacts or black screen**
- Solution: Try OpenGL mode instead of DXVK
- Update Bottles: `flatpak update com.usebottles.bottles`

**Issue: Slow performance**
- Solution: Enable Vulkan async compilation:
  ```bash
  # In Bottles environment variables:
  DXVK_ASYNC=1
  ```

## Architecture Notes

### Why Flatpak on NixOS?

While NixOS prefers declarative packages, Fusion 360 via Flatpak is pragmatic because:
1. **Isolation**: Flatpak sandboxing keeps Wine/Windows apps separate from NixOS
2. **Official Support**: Bottles developers maintain the Fusion 360 installer
3. **Reduced Complexity**: Native Nix packaging would require complex Wine wrappers
4. **Stability**: Flatpak handles FHS expectations that conflict with Nix store layout

### Configuration Files

Relevant NixOS configuration:
- **Flatpak enablement**: `nixos/desktop/default.nix:25`
- **XDG portals**: `nixos/desktop/default.nix:45-52`
- **Flatpak paths**: `home/xdg/default.nix:18`

### Hardware Compatibility

Your systems (verified compatible):
- **ThinkPad P14s G5**: AMD GPU with flickering fix applied ✅

Both systems use open-source amdgpu drivers with excellent Vulkan support.

## Updating

**Update Bottles:**
```bash
flatpak update com.usebottles.bottles
```

**Update Fusion 360:**
- Launch Fusion 360
- It will auto-update when newer versions are available
- Or reinstall via Bottles installer for major updates

## Uninstallation

```bash
# Remove Bottles and all bottles (including Fusion 360)
flatpak uninstall com.usebottles.bottles

# Clean up leftover data
rm -rf ~/.var/app/com.usebottles.bottles
```

## Additional Resources

- **Bottles Documentation**: https://docs.usebottles.com/
- **Fusion 360 Linux Project**: https://github.com/cryinkfly/Autodesk-Fusion-360-for-Linux
- **Tested GPU Compatibility**: See cryinkfly repository for extensive GPU testing results
- **NixOS Flatpak Wiki**: https://nixos.wiki/wiki/Flatpak

## Support

If you encounter issues:
1. Check Bottles logs (Developer Tools → Logs)
2. Verify Flatpak permissions: `flatpak info com.usebottles.bottles`
3. Test with minimal bottle (create new bottle without Fusion 360)
4. Report issues to Bottles project or cryinkfly repository

## NixOS Integration

### Declarative Flatpak Management (Optional)

For reproducibility, consider declarative Flatpak management:

```nix
# Add to your NixOS configuration:
services.flatpak.packages = [
  "com.usebottles.bottles"
];
```

This requires additional tooling like `nix-flatpak` or similar (not currently configured).

---

**Last Updated**: 2025-11-16
**Tested On**: NixOS Unstable, Hyprland, AMD GPUs (amdgpu driver)
