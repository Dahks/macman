# macman

A fast, zero-animation app switcher for macOS. Intercepts hotkeys at the HID level via `CGEventTap` before the system sees them.

## Requirements

- macOS 13+
- Accessibility permission (System Settings > Privacy & Security > Accessibility — grant to your terminal app)

## Run

```bash
swift build && swift run
```

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
