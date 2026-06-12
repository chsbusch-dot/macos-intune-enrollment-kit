# Configuration profiles

The profiles below are the ones that, in practice, decide whether a macOS enrollment is solid or quietly broken. All values here are vendor identifiers that are the same for every tenant. Anything tenant-specific (your tenant ID, group names, KFM GUID) is shown as a placeholder.

Assign each profile to the device group your Macs are actually in. A profile assigned to the wrong group, or to users instead of devices, is the most common reason a correctly built profile still no-ops on the endpoint.

## 1. CrowdStrike Falcon: system extension approval

Without this, macOS will not load the Falcon system extension, and a reboot can remove it entirely.

- Type: System Extensions (Settings Catalog, or a System Extensions profile).
- Allowed system extension: the CrowdStrike Falcon extension, allowed by team identifier.
- Also configure the related PPPC (Privacy Preferences Policy Control) and the network/content-filter and full-disk-access grants Falcon needs, so the user is not prompted and cannot deny them.

## 2. CrowdStrike Falcon: non-removable

Pairs with the approval profile. This is what stops the extension being torn out on reboot or by a user action. Both this and the approval profile must be present and must survive reboot. If you ever see `falconctl` report the sensor as unknown after a reboot while `Falcon.app` is still on disk, check that both of these are still assigned and the device has not fallen out of the assignment group.

## 3. Platform SSO (Extensible SSO)

This is the profile whose absence makes Company Portal look like it crashes on sign-in.

- Type: Settings Catalog, macOS, Single Sign-On Extension (Platform SSO).
- Extension identifier: `com.microsoft.CompanyPortalMac.ssoextension`
- Team identifier: `UBF8T346G9`
- Authentication method: Password, or Secure Enclave key, per your design.
- On current Company Portal builds, enable registration during Setup Assistant if you want PSSO to register at first login.

After assigning, on the device run:

```bash
sudo profiles renew -type enrollment
```

Then confirm registration:

```bash
app-sso platform -s
```

A registered device shows a non-null device configuration. Note that on recent macOS the on-disk SSO configuration directory cannot be read even as root because of SIP, so `app-sso platform -s` is the authoritative check, not the filesystem.

## 4. FileVault with recovery key escrow

- Type: Endpoint protection / FileVault, with personal recovery key (PRK) escrow to MDM.
- Verify on device with `fdesetup status` (should report FileVault is On) and confirm the recovery key is visible in the portal.

## 5. PPPC for the Intune agent

Privacy Preferences Policy Control granting the Microsoft Intune agent the access it needs so management actions are not blocked by TCC prompts.

## 6. Managed OneDrive preferences (Known Folder Move)

- Type: a configuration profile delivering managed preferences for `com.microsoft.OneDrive`.
- Set silent account configuration and Known Folder Move opt-in for your tenant.
- Tenant ID: `<YOUR_TENANT_GUID>` (this is your Entra tenant GUID; do not commit the real value to a public repo).
- The KFM opt-in key (for example `KFMSilentOptIn`) keyed to your tenant GUID is what the smoke test looks for in `/Library/Managed Preferences/com.microsoft.OneDrive.plist`.

## Order matters

The Falcon approval and non-removable profiles need to be applied before the Falcon app is deployed, or the system extension gets blocked at install time and lands broken. The `falcon-preflight.sh` script in this kit exists to enforce that ordering when you cannot guarantee it through assignment timing alone.
