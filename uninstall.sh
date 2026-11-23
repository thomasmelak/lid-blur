#!/bin/bash
# Removes Lid Blur, its login item and its settings.
#   curl -fsSL https://raw.githubusercontent.com/thomasmelak/lid-blur/main/uninstall.sh | bash
set -euo pipefail

LABEL="com.thomasmelak.lidblur"
BUNDLE_ID="com.thomasmelak.LidBlur"
APP_NAME="Lid Blur.app"

echo "==> Stopping Lid Blur"
pkill -x LidBlur 2>/dev/null || true

if command -v brew >/dev/null 2>&1 && brew list --cask lid-blur >/dev/null 2>&1; then
    echo "==> Removing the Homebrew cask"
    brew uninstall --cask --zap lid-blur || brew uninstall --cask lid-blur || true
fi

echo "==> Removing the login item"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"

echo "==> Removing the app"
for dir in /Applications "$HOME/Applications"; do
    if [ -d "$dir/$APP_NAME" ]; then
        rm -rf "${dir:?}/$APP_NAME"
        echo "    removed $dir/$APP_NAME"
    fi
done

echo "==> Removing settings"
defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"

echo
echo "Lid Blur has been removed."
