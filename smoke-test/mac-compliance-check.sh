#!/usr/bin/env bash
#
# mac-compliance-check.sh
#
# Post-enrollment smoke test for Intune-managed macOS endpoints.
# Verifies that a freshly enrolled Mac actually has the things enrollment
# is supposed to deliver: MDM enrollment, configuration profiles, CrowdStrike
# Falcon (sensor + system extension), Platform SSO registration, FileVault,
# and OneDrive Known Folder Move.
#
# Detection is by stable vendor identifiers, not org-specific policy names,
# so this is safe to run on any tenant.
#
# Usage:
#   sudo ./mac-compliance-check.sh           # human-readable report
#   sudo ./mac-compliance-check.sh --json     # machine-readable, for fleet rollup
#
# Exit code = number of FAILing checks (0 = fully compliant). Suitable as an
# Intune shell script or custom attribute.

set -uo pipefail

JSON=0
[[ "${1:-}" == "--json" ]] && JSON=1

# Stable identifiers (not tenant-specific)
FALCON_BUNDLE="com.crowdstrike.falcon"
SSO_EXTENSION="com.microsoft.CompanyPortalMac.ssoextension"

# Optional: list configuration-profile identifiers you require to be present.
# Leave empty to simply assert that at least one managed profile exists.
# Example (edit for your tenant, kept out of version control if sensitive):
#   REQUIRED_PROFILES=( "com.apple.extensiblesso" "com.apple.security.FDERecoveryKeyEscrow" )
REQUIRED_PROFILES=()

# ---------------------------------------------------------------------------
NAMES=(); STATES=(); DETAILS=()
record() { NAMES+=("$1"); STATES+=("$2"); DETAILS+=("$3"); }

is_root() { [[ "${EUID}" -eq 0 ]]; }

# --- MDM enrollment --------------------------------------------------------
check_mdm() {
    local out
    out="$(profiles status -type enrollment 2>/dev/null)"
    if grep -qi "MDM enrollment: Yes" <<<"${out}"; then
        if grep -qi "User Approved" <<<"${out}"; then
            record "MDM enrollment" PASS "Enrolled, User Approved"
        else
            record "MDM enrollment" WARN "Enrolled but not User Approved"
        fi
    else
        record "MDM enrollment" FAIL "Device is not MDM enrolled"
    fi
}

# --- Configuration profiles present ----------------------------------------
check_profiles() {
    if ! is_root; then
        record "Config profiles" WARN "Need root to read profiles; re-run with sudo"
        return
    fi
    local installed
    installed="$(profiles show 2>/dev/null)"
    local count
    count="$(grep -ci "attribute: profileIdentifier" <<<"${installed}")"
    if [[ "${count}" -eq 0 ]]; then
        record "Config profiles" FAIL "No managed configuration profiles installed"
        return
    fi
    if [[ "${#REQUIRED_PROFILES[@]}" -eq 0 ]]; then
        record "Config profiles" PASS "${count} profile(s) installed"
        return
    fi
    local missing=()
    local p
    for p in "${REQUIRED_PROFILES[@]}"; do
        grep -q "${p}" <<<"${installed}" || missing+=("${p}")
    done
    if [[ "${#missing[@]}" -eq 0 ]]; then
        record "Config profiles" PASS "${count} installed, all required present"
    else
        record "Config profiles" FAIL "Missing: ${missing[*]}"
    fi
}

# --- CrowdStrike Falcon -----------------------------------------------------
check_falcon() {
    if [[ ! -d "/Applications/Falcon.app" ]]; then
        record "Falcon installed" FAIL "/Applications/Falcon.app not found"
        return
    fi
    record "Falcon installed" PASS "Falcon.app present"

    # System extension activated (the thing a reboot can tear out if the
    # non-removable / approval profile is missing).
    local sysext
    sysext="$(systemextensionsctl list 2>/dev/null | grep -i "${FALCON_BUNDLE}")"
    if [[ -z "${sysext}" ]]; then
        record "Falcon sysext" FAIL "No CrowdStrike system extension registered"
    elif grep -qi "activated enabled" <<<"${sysext}"; then
        record "Falcon sysext" PASS "System extension activated"
    else
        record "Falcon sysext" WARN "Extension present but not fully activated: ${sysext}"
    fi

    # Sensor process and reported state.
    if is_root; then
        local stats
        stats="$(/Applications/Falcon.app/Contents/Resources/falconctl stats agent_info 2>/dev/null)"
        if grep -qi "version" <<<"${stats}"; then
            record "Falcon sensor" PASS "falconctl reports an operational sensor"
        else
            record "Falcon sensor" FAIL "falconctl did not report sensor state"
        fi
    else
        if pgrep -fi "falcon" >/dev/null 2>&1; then
            record "Falcon sensor" PASS "Falcon process running (run as root for full state)"
        else
            record "Falcon sensor" WARN "Cannot confirm sensor without root"
        fi
    fi
}

# --- Platform SSO -----------------------------------------------------------
check_psso() {
    local out
    out="$(app-sso platform -s 2>/dev/null)"
    if [[ -z "${out}" ]]; then
        record "Platform SSO" FAIL "app-sso returned nothing"
        return
    fi
    # A registered device has a non-null device configuration.
    if grep -qi "deviceConfiguration" <<<"${out}" && ! grep -qi "deviceConfiguration.*null" <<<"${out}"; then
        record "Platform SSO" PASS "Device registered (non-null device configuration)"
    elif grep -qi "${SSO_EXTENSION}" <<<"${out}"; then
        record "Platform SSO" WARN "SSO extension seen but device configuration looks null"
    else
        record "Platform SSO" FAIL "No Platform SSO registration found"
    fi
}

# --- FileVault --------------------------------------------------------------
check_filevault() {
    local out
    out="$(fdesetup status 2>/dev/null)"
    if grep -qi "FileVault is On" <<<"${out}"; then
        record "FileVault" PASS "Enabled"
    else
        record "FileVault" FAIL "${out:-status unavailable}"
    fi
}

# --- OneDrive Known Folder Move --------------------------------------------
check_kfm() {
    if [[ ! -d "/Applications/OneDrive.app" ]]; then
        record "OneDrive KFM" WARN "OneDrive.app not installed"
        return
    fi
    local managed="/Library/Managed Preferences/com.microsoft.OneDrive.plist"
    if [[ -f "${managed}" ]] && /usr/libexec/PlistBuddy -c "Print :KFMSilentOptIn" "${managed}" >/dev/null 2>&1; then
        record "OneDrive KFM" PASS "KFMSilentOptIn present in managed preferences"
    else
        record "OneDrive KFM" WARN "KFM managed preference not detected"
    fi
}

# ---------------------------------------------------------------------------
check_mdm
check_profiles
check_falcon
check_psso
check_filevault
check_kfm

fails=0; warns=0
for s in "${STATES[@]}"; do
    [[ "${s}" == "FAIL" ]] && ((fails++))
    [[ "${s}" == "WARN" ]] && ((warns++))
done

if [[ "${JSON}" -eq 1 ]]; then
    printf '{'
    printf '"hostname":"%s",' "$(scutil --get ComputerName 2>/dev/null || hostname)"
    printf '"checks":['
    for i in "${!NAMES[@]}"; do
        [[ "${i}" -gt 0 ]] && printf ','
        printf '{"name":"%s","status":"%s","detail":"%s"}' \
            "${NAMES[$i]}" "${STATES[$i]}" "${DETAILS[$i]//\"/\'}"
    done
    printf '],"fails":%d,"warns":%d}\n' "${fails}" "${warns}"
    exit "${fails}"
fi

bold=$'\033[1m'; red=$'\033[31m'; green=$'\033[32m'; yellow=$'\033[33m'; rst=$'\033[0m'
echo "${bold}macOS Intune compliance smoke test${rst}"
echo "Host: $(scutil --get ComputerName 2>/dev/null || hostname)   $(date)"
echo
for i in "${!NAMES[@]}"; do
    case "${STATES[$i]}" in
        PASS) c="${green}PASS${rst}";;
        WARN) c="${yellow}WARN${rst}";;
        FAIL) c="${red}FAIL${rst}";;
    esac
    printf "  [%s] %-18s %s\n" "${c}" "${NAMES[$i]}" "${DETAILS[$i]}"
done
echo
echo "  ${fails} failed, ${warns} warnings"
[[ "${fails}" -eq 0 ]] && echo "  ${green}Endpoint is compliant.${rst}" || echo "  ${red}Endpoint has compliance gaps.${rst}"
exit "${fails}"
