# macOS Intune enrollment kit

Hard-won reference material for standing up a reliable macOS fleet on Microsoft Intune: the configuration profiles you actually need, clean versions of the deployment scripts that survive contact with the Intune script runner, and the failure modes that cost the most time to diagnose.

This is not a one-click installer. macOS MDM is too tenant-specific for that. It is the set of pieces that, once in place and in the right order, make enrollment land the way you expect. It includes a [compliance smoke test](smoke-test/) that verifies the end state the rest of the kit produces.

## What is in here

```
scripts/
  set-computer-name.sh     Deterministic device naming that does not fail the Intune runner
  provision-dock.sh        Dock layout via PlistBuddy, applied in the logged-in user context
  falcon-preflight.sh      Guard that holds EDR install until approval profiles have landed
smoke-test/
  mac-compliance-check.sh  Post-enrollment audit: PASS/WARN/FAIL, with a --json mode
docs/
  profiles.md              The configuration profiles you need, and how to scope them
```

## The failure modes this kit exists to prevent

### A reboot silently removes your EDR

If the CrowdStrike Falcon system-extension **approval** profile and the **non-removable** profile are not both applied to the device, a reboot can tear the system extension out. The app stays on disk, `falconctl` reports the sensor as unknown, and the endpoint is unprotected without any obvious error. The fix is structural, not a reinstall: both profiles must be assigned to the group the device is actually in, and they must survive reboot. Reinstalling Falcon without them just reproduces the teardown on the next boot. See [docs/profiles.md](docs/profiles.md).

### Company Portal looks like it crashes on sign-in

This is almost always a missing **Platform SSO** profile rather than a crash. The user signs in, the SSO handoff has nothing to register into because no `com.apple.extensiblesso` payload is assigned, and the flow dead-ends in a way that reads as a crash. No crash report is ever generated. The fix is a Settings Catalog Platform SSO policy with the right extension identifier and team identifier, assigned to the device group, followed by `sudo profiles renew -type enrollment` on the Mac. Details and exact values in [docs/profiles.md](docs/profiles.md).

### A recurring Intune script fails forever on a clean machine

A device-naming or inventory script that shells out to `system_profiler` will emit a line on stderr and return a non-zero exit code, which the Intune script runner records as a failure. On a recurring cadence (for example every 900 seconds) it fails on every cycle indefinitely. The `set-computer-name.sh` here reads the serial from `ioreg` instead, which is quiet and deterministic, and exits cleanly.

### EDR install races the approval profile

If the Falcon installer runs before the system-extension approval profile has applied, macOS blocks the extension and the install lands in a broken state. `falcon-preflight.sh` holds the install until enrollment is complete and the approval is present, and exits non-zero (so Intune retries) rather than installing into a state that needs manual recovery.

## How the pieces fit

1. Device enrolls (DEP / Automated Device Enrollment, User Approved MDM).
2. Core configuration profiles apply: System Extension approval and non-removable for Falcon, Platform SSO, FileVault with recovery-key escrow, PPPC for the Intune agent, managed OneDrive preferences. See [docs/profiles.md](docs/profiles.md).
3. Scripts run: naming, Dock provisioning, and the Falcon preflight guard ahead of the Falcon app deployment.
4. Run the [smoke test](smoke-test/) to confirm the end state.

## Conventions

- Scripts are written to run as root under the Intune agent. Where an action has to happen in the user context (the Dock), the script resolves the current console user and drops privileges explicitly.
- Anything tenant-specific (your tenant ID, your OneDrive KFM GUID, your naming prefix, your profile identifiers) is a placeholder or a variable at the top of the file. Nothing in this repo carries a real tenant value.
- Scripts are idempotent and safe to re-run.

## License

MIT. See [LICENSE](./LICENSE).
