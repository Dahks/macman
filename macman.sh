#!/bin/bash
set -e

BINARY="/usr/local/bin/macman"
PLIST="$HOME/Library/LaunchAgents/com.dagur.macman.plist"

case "${1:-}" in
    install)
        echo "Building release..."
        swift build -c release
        cp .build/release/FastSwitcher "$BINARY"
        echo "Installed to $BINARY"
        ;;
    start)
        launchctl load "$PLIST"
        echo "Started"
        ;;
    stop)
        launchctl unload "$PLIST"
        echo "Stopped"
        ;;
    restart)
        launchctl unload "$PLIST" 2>/dev/null || true
        launchctl load "$PLIST"
        echo "Restarted"
        ;;
    update)
        echo "Building release..."
        swift build -c release
        cp .build/release/FastSwitcher "$BINARY"
        launchctl unload "$PLIST" 2>/dev/null || true
        launchctl load "$PLIST"
        echo "Updated and restarted"
        ;;
    log)
        tail -f /tmp/macman.log
        ;;
    kill-animations)
        echo "Disabling macOS animations..."
        defaults write -g NSAutomaticWindowAnimationsEnabled -bool false
        defaults write -g NSWindowResizeTime -float 0.001
        defaults write -g NSUseAnimatedFocusRing -bool NO
        defaults write com.apple.dock expose-animation-duration -float 0
        defaults write com.apple.dock autohide-time-modifier -float 0
        defaults write com.apple.dock autohide-delay -float 0
        defaults write com.apple.dock launchanim -bool false
        defaults write com.apple.finder DisableAllAnimations -bool true
        killall Dock
        killall Finder
        echo "Done. Most macOS animations disabled."
        ;;
    restore-animations)
        echo "Restoring macOS animations..."
        defaults delete -g NSAutomaticWindowAnimationsEnabled 2>/dev/null || true
        defaults delete -g NSWindowResizeTime 2>/dev/null || true
        defaults delete -g NSUseAnimatedFocusRing 2>/dev/null || true
        defaults delete com.apple.dock expose-animation-duration 2>/dev/null || true
        defaults delete com.apple.dock autohide-time-modifier 2>/dev/null || true
        defaults delete com.apple.dock autohide-delay 2>/dev/null || true
        defaults delete com.apple.dock launchanim 2>/dev/null || true
        defaults delete com.apple.finder DisableAllAnimations 2>/dev/null || true
        killall Dock
        killall Finder
        echo "Done. macOS animations restored to defaults."
        ;;
    *)
        echo "Usage: ./macman.sh {install|start|stop|restart|update|log|kill-animations|restore-animations}"
        exit 1
        ;;
esac
