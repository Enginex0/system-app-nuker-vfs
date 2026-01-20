# System App Nuker (VFS Enhanced)

A WebUI-based Android debloater module with NoMount VFS support for undetectable system app removal.

[![Version](https://img.shields.io/badge/version-v1.1.9--vfs-blue)]()
[![License](https://img.shields.io/badge/license-Unlicense-green)]()

## Features

- **WebUI Interface** - Modern, responsive web interface for easy app management
- **Multiple Mounting Modes** - Automatic detection and fallback between mounting strategies
- **Undetectable VFS Mode** - NoMount VFS kernel-level hiding (completely undetectable by root detection)
- **Bootloop Protection** - Automatic recovery if module causes boot issues
- **App Categories** - Visual classification of apps (Essential, Caution, Safe, Google)
- **Raw Whiteout Support** - Hide arbitrary system paths beyond just apps
- **Import/Export** - Import package lists from text or Canta JSON format

## Mounting Modes

The module supports 4 mounting strategies (auto-detected in priority order):

| Priority | Mode | Detection | Description |
|----------|------|-----------|-------------|
| 1 | **NoMount VFS** | Undetectable | Kernel-level VFS hiding - requires NoMount module |
| 2 | **Mountify Module** | Low | Uses Mountify module for overlay mounting |
| 3 | **Standalone Mountify** | Low | Built-in mountify script (requires tmpfs xattr) |
| 4 | **Default/Magic Mount** | Detectable | Standard Magisk/KSU magic mount |

The module automatically upgrades to VFS mode when NoMount is available and falls back to other modes if kernel support changes.

## Requirements

- **Magisk**, **KernelSU**, or **APatch** root solution
- Android 8.0+ (API 26+)
- One of:
  - KernelSU WebUI / MMRL / KsuWebUIStandalone (for WebUI access)
  - Magisk action button support (automatic installer)

### For VFS Mode (Recommended)

- Kernel with `CONFIG_NOMOUNT=y` compiled
- [NoMount module](https://github.com/backslashxx/nomount) installed and enabled

## Installation

1. Download the module ZIP
2. Install via your root manager:
   - **Magisk**: Modules > Install from storage
   - **KernelSU**: Module > Install
   - **APatch**: Module > Install
3. Reboot
4. Access WebUI through your manager or KsuWebUIStandalone app

## Usage

### WebUI

The WebUI provides three main sections:

- **Home** - Browse and select system apps to remove ("nuke")
- **Restore** - View and restore previously removed apps
- **Whiteout** - Create raw whiteouts for arbitrary paths

### App Categories

Apps are color-coded by safety level:

| Category | Color | Description |
|----------|-------|-------------|
| Essential | Red | Critical system components - DO NOT REMOVE |
| Caution | Orange | May affect system functionality |
| Safe | Green | Non-essential bloatware, safe to remove |
| Google | Blue | Google services (required for Play Store) |
| Unknown | Gray | Unclassified apps |

### Configuration

Edit `/data/adb/system_app_nuker/config.sh`:

```bash
# Enable pm uninstall fallback if whiteouts fail
uninstall_fallback=false

# Disable-only mode (no whiteouts, just disable apps)
disable_only_mode=false

# Refresh app list on every boot
refresh_applist=true
```

## How It Works

1. **App Selection**: User selects apps via WebUI
2. **Whiteout Creation**: Module creates overlay whiteouts to hide app directories
3. **Mounting**: Based on detected mode:
   - **VFS**: NoMount module handles kernel-level redirection
   - **Overlay**: Standalone/Mountify handles overlay mounts
   - **Magic**: Manager handles standard module mounting
4. **Boot Protection**: If boot fails twice, module auto-disables and clears whiteouts

## Troubleshooting

### Module description shows [ERROR]

- **VFS mode configured but kernel support missing**: Flash a kernel with NoMount support or wait for auto-fallback
- **Mountify mode but module won't mount**: Enable mountify and add this module to modules.txt
- **tmpfs xattr support required**: Your kernel doesn't support tmpfs xattr for standalone mode

### Apps not hiding

1. Check mounting mode in module description
2. For KSU/APatch: Disable "unmount by default" for this module
3. Reboot after making changes

### Bootloop

The module has built-in protection - if it detects 2 failed boots:
1. Module auto-disables
2. Whiteouts are cleared
3. A backup of nuked apps is saved to `/data/adb/system_app_nuker/nuke_list.txt`

## Credits

### Original Authors

- **[ChiseWaguri](https://github.com/ChiseWaguri)** - Primary developer, System App Nuker
- **[Enginex0](https://github.com/Enginex0)** - Co-developer, VFS integration

### Components & Inspiration

- **[Mountify](https://github.com/backslashxx/mountify)** - Standalone mountify script adapted from this project
- **[NoMount](https://github.com/backslashxx/nomount)** - VFS-level hiding integration
- **[Tricky Addon](https://github.com/5ec1cff/TrickyAddon)** - Action script inspiration
- **[KsuWebUIStandalone](https://github.com/5ec1cff/KsuWebUIStandalone)** - WebUI framework

### Special Thanks

- All contributors who tested and provided feedback
- The Android root community for continuous innovation

## License

This project contains multiple licenses:

- **mountify.sh** - [The Unlicense](https://unlicense.org/) (Public Domain)
- **Other components** - See original repositories for their respective licenses

---

**Disclaimer**: Removing system apps can affect device functionality. Always know what you're removing. The authors are not responsible for any damage caused by using this module.
