#!/usr/bin/env bash
#
# falcon-preflight.sh
#
# Guard to run BEFORE deploying the CrowdStrike Falcon app, so the installer
# does not race the MDM system-extension approval. If Falcon installs before
# the approval profile applies, macOS blocks the system extension and the
# install lands in a broken state that needs manual recovery.
#
# This script waits (bounded) for two things:
#   1. MDM enrollment to be complete and User Approved.
#   2. A system-extension management profile to be present.
#
# If either is not satisfied within the timeout, it exits non-zero so the
# Intune runner retries on its next cycle instead of installing into a bad
# state. If both are satisfied, it exits 0 and your deployment can proceed.
#
# This is a reference pattern. Tune TIMEOUT and the profile check to match how
# your tenant scopes the Falcon approval and non-removable profiles.

set -uo pipefail

TIMEOUT=600       # seconds to wait overall
INTERVAL=20       # seconds between checks

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"; }

mdm_ready() {
    local out
    out="$(profiles status -type enrollment 2>/dev/null)"
    grep -qi "MDM enrollment: Yes" <<<"${out}" && grep -qi "User Approved" <<<"${out}"
}

# Looks for any system-extension management payload in the installed profiles.
# Adjust the grep to match your specific approval profile identifier if you
# want a stricter check than "some sysext policy exists".
sysext_policy_present() {
    profiles show 2>/dev/null | grep -qi "com.apple.system-extension-policy"
}

elapsed=0
while (( elapsed < TIMEOUT )); do
    if mdm_ready && sysext_policy_present; then
        log "Preflight OK: MDM User Approved and system-extension policy present"
        exit 0
    fi
    log "Preflight not ready (mdm/profile pending); waiting ${INTERVAL}s"
    sleep "${INTERVAL}"
    (( elapsed += INTERVAL ))
done

log "Preflight TIMED OUT after ${TIMEOUT}s; deferring install for Intune to retry"
exit 1
