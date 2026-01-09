# Waylight - Project Guide

## Build

```bash
zig build -Doptimize=ReleaseFast
```

**Always build before committing.** Test with `zig-out/bin/waylight --toggle`.

## Dependencies

GTK4, gtk4-layer-shell, webkitgtk-6.0, wl-clipboard, libqalculate, plocate, fd

## Core Principles

- **Opinionated**: Focused feature set, deliberate UX choices
- **Instant**: Daemon architecture eliminates startup delay
- **Native**: Deep Wayland integration, system-level performance
- **Live**: Auto-reloads .desktop files via inotify
- **Simple**: Clear separation of concerns (providers, IPC, handlers)
