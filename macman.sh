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
    *)
        echo "Usage: ./macman.sh {install|start|stop|restart|update|log}"
        exit 1
        ;;
esac
