# macman

A fast, zero-animation app switcher for macOS. Intercepts hotkeys at the HID level via `CGEventTap` before the system sees them.

## Requirements

- macOS 13+
- Accessibility permission (System Settings > Privacy & Security > Accessibility — grant to your terminal app)

## Setup

```bash
./macman.sh install   # Build release binary and copy to /usr/local/bin
./macman.sh start     # Start as background service (runs on login)
```

Grant Accessibility permission to `/usr/local/bin/macman` when prompted.

## Service management

```bash
./macman.sh stop      # Stop the service
./macman.sh restart   # Restart the service
./macman.sh update    # Rebuild, install, and restart
./macman.sh log       # Tail the log file
```

For development, run directly with `swift build && swift run`.

## Keybindings

### Switcher (MRU order)

| Shortcut | Action |
|---|---|
| `Cmd + <` | Open switcher / cycle forward |
| `Cmd + >` | Cycle backward |
| Release `Cmd` | Switch to selected app |
| `Escape` | Cancel |

### Direct jump (launch order)

| Shortcut | Action |
|---|---|
| `Cmd + Ctrl + 1-9` | Jump to app by launch order |
| `Cmd + Ctrl + °` | Toggle app overview |
