# Waylight

A fast application launcher for Wayland.

![waylight](https://github.com/OlaHulleberg/waylight/assets/screenshot.png)

## Features

- Application launcher with fuzzy search
- Built-in calculator (type math expressions like `2+2` or `sqrt(16)`)
- Copies calculator results to clipboard on Enter
- Smooth animations
- Works on any wlroots-based compositor (Hyprland, Sway, etc.)

## Dependencies

- gtk4
- gtk4-layer-shell
- webkitgtk-6.0
- wl-clipboard
- zig (build only)

### Arch Linux

```bash
pacman -S gtk4 gtk4-layer-shell webkitgtk-6.0 wl-clipboard zig
```

## Building

```bash
git clone https://github.com/OlaHulleberg/waylight
cd waylight
zig build -Doptimize=ReleaseFast
```

## Installation

```bash
sudo cp zig-out/bin/waylight /usr/local/bin/
```

Or use the PKGBUILD for Arch Linux.

## Usage

Add a keybind to launch waylight:

### Hyprland

```conf
bind = SUPER, SPACE, exec, waylight
```

### Sway

```conf
bindsym $mod+space exec waylight
```

## Keybinds

| Key | Action |
|-----|--------|
| `Enter` | Launch selected app / Copy calculator result |
| `Escape` | Close |
| `Arrow Up/Down` | Navigate results |

## License

MIT
