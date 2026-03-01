#!/bin/bash
#
# MaxVoice Launch Agent Installer
#
# Usage:
#   ./install.sh install    - Install and load launch agent
#   ./install.sh uninstall  - Unload and remove launch agent
#   ./install.sh status     - Check if launch agent is loaded
#

PLIST_NAME="com.maxweisel.maxvoice.plist"
PLIST_SOURCE="$(dirname "$0")/$PLIST_NAME"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME"
MARKER_FILE="$HOME/.maxvoice/.accessibility_failed"

install() {
    echo "Installing MaxVoice launch agent..."

    # Create LaunchAgents directory if needed
    mkdir -p "$HOME/Library/LaunchAgents"

    # Copy plist file
    cp "$PLIST_SOURCE" "$PLIST_DEST"
    echo "  Copied $PLIST_NAME to ~/Library/LaunchAgents/"

    # Remove any accessibility failure marker
    if [ -f "$MARKER_FILE" ]; then
        rm -f "$MARKER_FILE"
        echo "  Removed accessibility failure marker"
    fi

    # Load the agent
    launchctl load "$PLIST_DEST"
    echo "  Loaded launch agent"

    echo ""
    echo "MaxVoice will now start automatically on login."
    echo "To start it now, run: launchctl start com.maxweisel.maxvoice"
}

uninstall() {
    echo "Uninstalling MaxVoice launch agent..."

    # Unload if loaded
    launchctl unload "$PLIST_DEST" 2>/dev/null
    echo "  Unloaded launch agent"

    # Remove plist
    rm -f "$PLIST_DEST"
    echo "  Removed $PLIST_NAME"

    # Remove marker file
    rm -f "$MARKER_FILE"

    echo ""
    echo "MaxVoice launch agent has been removed."
}

status() {
    echo "MaxVoice Launch Agent Status"
    echo "============================"

    if [ -f "$PLIST_DEST" ]; then
        echo "Plist installed: Yes"
    else
        echo "Plist installed: No"
    fi

    if launchctl list | grep -q "com.maxweisel.maxvoice"; then
        echo "Agent loaded: Yes"
        launchctl list com.maxweisel.maxvoice 2>/dev/null
    else
        echo "Agent loaded: No"
    fi

    if [ -f "$MARKER_FILE" ]; then
        echo "Accessibility marker: Present (needs permission)"
    else
        echo "Accessibility marker: Not present"
    fi

    echo ""
    echo "Logs:"
    echo "  stdout: /tmp/maxvoice.log"
    echo "  stderr: /tmp/maxvoice.err"
}

case "$1" in
    install)
        install
        ;;
    uninstall)
        uninstall
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {install|uninstall|status}"
        exit 1
        ;;
esac
