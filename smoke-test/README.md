# macOS Intune compliance smoke test

A single script that audits a freshly enrolled, Intune-managed Mac against the things enrollment is supposed to deliver, and prints a clear PASS / WARN / FAIL report. Built for the moment after a device finishes provisioning, when you want to know in one command whether everything actually landed instead of clicking through six panes in the Intune portal and three on the device.

It is part of the [macOS Intune enrollment kit](../) and verifies the end state the rest of the kit produces.

## What it checks

- **MDM enrollment** is present and User Approved (`profiles status`)
- **Configuration profiles** are installed, optionally asserting a list of identifiers you require
- **CrowdStrike Falcon** is installed, the system extension is activated, and the sensor reports operational (`systemextensionsctl`, `falconctl`)
- **Platform SSO** is registered with a non-null device configuration (`app-sso platform -s`)
- **FileVault** is on (`fdesetup status`)
- **OneDrive Known Folder Move** is configured via managed preferences

Detection uses stable vendor identifiers (the CrowdStrike bundle ID, the Microsoft SSO extension ID) rather than tenant-specific policy names, so the script is safe to run on any tenant without edits.

## Why these checks

Each one maps to a real failure mode on managed Macs:

- A **reboot can tear out the Falcon system extension** if the approval and non-removable system-extension profiles are not applied, leaving the app on disk but the EDR gone. The script checks the live extension state, not just that `Falcon.app` exists.
- **Company Portal appearing to crash on sign-in** is usually a missing Platform SSO profile: there is nothing for the sign-in to register into, so the handoff dead-ends. The script checks for an actual non-null device configuration, which is the authoritative signal that registration completed.
- Enrollment can report success while individual **profiles silently fail to apply** or a device falls out of an assignment group. Counting installed profiles (and optionally asserting required identifiers) catches that.

## Usage

```bash
sudo ./mac-compliance-check.sh
```

Machine-readable output for fleet rollup:

```bash
sudo ./mac-compliance-check.sh --json
```

The exit code equals the number of failing checks, so `0` means fully compliant. That makes it usable directly as an Intune shell script (alert on non-zero) or as the basis of a custom attribute.

### Asserting specific profiles

By default the script only confirms that at least one managed profile is installed. To assert that specific profiles are present, edit the `REQUIRED_PROFILES` array near the top:

```bash
REQUIRED_PROFILES=( "com.apple.extensiblesso" "com.apple.security.FDERecoveryKeyEscrow" )
```

Use payload identifiers (stable) rather than your portal display names, both so the check survives a profile rename and so you are not committing your internal naming scheme to a public repo.

## Notes

- Run with `sudo`. Several checks (`profiles show`, `falconctl stats`) need root; without it they degrade to warnings rather than failing outright.
- `app-sso platform -s` is the authoritative Platform SSO state check. On recent macOS the on-disk SSO configuration directory cannot be inspected directly even as root due to SIP, so do not bother trying to `ls` it.
- Tested against macOS with the Microsoft Intune MDM channel and CrowdStrike Falcon. The OneDrive KFM check is intentionally a warning rather than a hard fail, because the managed-preference key layout varies by deployment.

## License

MIT, same as the rest of the kit. See [LICENSE](../LICENSE).
