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
- libqalculate (for calculator)
- zig (build only)

### Arch Linux

```bash
pacman -S gtk4 gtk4-layer-shell webkitgtk-6.0 wl-clipboard libqalculate zig
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

Waylight runs as a daemon for instant startup. Add these to your config:

### Hyprland

```conf
# Start daemon on login
exec-once = waylight

# Toggle with keybind
bind = SUPER, SPACE, exec, waylight --toggle
```

### Sway

```conf
# Start daemon on login
exec waylight

# Toggle with keybind
bindsym $mod+space exec waylight --toggle
```

## Commands

| Command | Action |
|---------|--------|
| `waylight` | Start daemon |
| `waylight --toggle` | Toggle visibility |
| `waylight --quit` | Stop daemon |

## Keybinds

| Key | Action |
|-----|--------|
| `Enter` | Launch selected app / Copy calculator result |
| `Escape` | Hide window |
| `Arrow Up/Down` | Navigate results |

## License

MIT
