#!/usr/bin/env bash
#
# provision-dock.sh
#
# Sets a standard Dock layout using PlistBuddy only (no third-party tools like
# dockutil). Runs under the Intune agent as root, then drops to the logged-in
# user to edit their Dock plist and restart the Dock, because the Dock is
# per-user and editing it as root writes to the wrong domain.
#
# Idempotent: it rewrites the persistent-apps array from scratch each run, so
# re-running converges to the same layout.
#
# Deploy as an Intune shell script (run as root). Edit DOCK_APPS for your org.

set -uo pipefail

# Apps to pin, in order. Use full paths to the .app bundles.
DOCK_APPS=(
    "/Applications/Google Chrome.app"
    "/Applications/Microsoft Outlook.app"
    "/Applications/Microsoft Teams.app"
    "/System/Applications/System Settings.app"
)

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"; }

console_user="$(stat -f%Su /dev/console 2>/dev/null)"
if [[ -z "${console_user}" || "${console_user}" == "root" || "${console_user}" == "loginwindow" ]]; then
    log "No regular user logged in (console user: '${console_user:-none}'); skipping"
    exit 0
fi
uid="$(id -u "${console_user}")"
plist="/Users/${console_user}/Library/Preferences/com.apple.dock.plist"

# Helper: run a command as the console user inside their GUI session.
as_user() { launchctl asuser "${uid}" sudo -u "${console_user}" "$@"; }

pb() { /usr/libexec/PlistBuddy "$@"; }

# Reset the persistent-apps array.
pb -c "Delete :persistent-apps" "${plist}" 2>/dev/null || true
pb -c "Add :persistent-apps array" "${plist}"

i=0
for app in "${DOCK_APPS[@]}"; do
    if [[ ! -d "${app}" ]]; then
        log "WARN: ${app} not found, skipping"
        continue
    fi
    pb -c "Add :persistent-apps:${i} dict" "${plist}"
    pb -c "Add :persistent-apps:${i}:tile-type string file-tile" "${plist}"
    pb -c "Add :persistent-apps:${i}:tile-data dict" "${plist}"
    pb -c "Add :persistent-apps:${i}:tile-data:file-label string $(basename "${app}" .app)" "${plist}"
    pb -c "Add :persistent-apps:${i}:tile-data:file-type integer 41" "${plist}"
    pb -c "Add :persistent-apps:${i}:tile-data:file-data dict" "${plist}"
    pb -c "Add :persistent-apps:${i}:tile-data:file-data:_CFURLString string file://${app}/" "${plist}"
    pb -c "Add :persistent-apps:${i}:tile-data:file-data:_CFURLStringType integer 15" "${plist}"
    ((i++))
done

chown "${console_user}" "${plist}"

# Restart the Dock in the user's session so changes take effect.
as_user killall Dock 2>/dev/null || true

log "Provisioned Dock with ${i} app(s) for ${console_user}"
exit 0
