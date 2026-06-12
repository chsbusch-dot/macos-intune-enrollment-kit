#!/usr/bin/env bash
#
# set-computer-name.sh
#
# Sets ComputerName, HostName, and LocalHostName deterministically from the
# hardware serial number. Reads the serial via ioreg, NOT system_profiler:
# system_profiler emits a line on stderr and returns non-zero, which the Intune
# script runner records as a failure, so a recurring naming script using it
# fails on every cycle forever. ioreg is quiet and deterministic.
#
# Idempotent and safe to re-run. Exits 0 on success.
#
# Deploy as an Intune shell script (run as root).

set -uo pipefail

# Edit this for your org. Final name will be "<PREFIX>-<SERIAL>".
PREFIX="MAC"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"; }

serial="$(ioreg -c IOPlatformExpertDevice -d 2 2>/dev/null \
    | awk -F'"' '/IOPlatformSerialNumber/{print $4; exit}')"

if [[ -z "${serial}" ]]; then
    log "ERROR: could not read serial number from ioreg"
    exit 1
fi

desired="${PREFIX}-${serial}"
# LocalHostName must be DNS-safe: letters, digits, hyphens only.
local_name="$(printf '%s' "${desired}" | tr -c 'A-Za-z0-9-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')"

current_computer="$(scutil --get ComputerName 2>/dev/null || true)"

if [[ "${current_computer}" == "${desired}" ]]; then
    log "Name already set to ${desired}, nothing to do"
    exit 0
fi

scutil --set ComputerName  "${desired}"
scutil --set HostName       "${desired}"
scutil --set LocalHostName  "${local_name}"

log "Set ComputerName/HostName to ${desired}, LocalHostName to ${local_name}"
exit 0
