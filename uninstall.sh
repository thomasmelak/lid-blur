#!/bin/bash
# Removes Lid Blur, its login item and its settings.
#   curl -fsSL https://raw.githubusercontent.com/thomasmelak/lid-blur/main/uninstall.sh | bash
set -euo pipefail

LABEL="com.thomasmelak.lidblur"

pkill -x LidBlur 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "/Applications/Lid Blur.app" "$HOME/Applications/Lid Blur.app"
defaults delete com.thomasmelak.LidBlur 2>/dev/null || true

echo "Lid Blur has been removed."
