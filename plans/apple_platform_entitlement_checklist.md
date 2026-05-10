# Apple Platform Entitlement Audit

Date: 2026-05-10

Scope: current `Spotier.xcodeproj` app and Network Extension targets.

## Targets

- `Spotier`: macOS app target with bundle ID `com.alick.spotier`.
- `SpotierNE`: macOS Network Extension target with bundle ID `com.alick.spotier.SpotierNE`.
- No iOS app target exists in the current project.
- No tvOS app target exists in the current project.

## Entitlements

- `Spotier/Spotier.entitlements` includes `com.apple.developer.networking.networkextension` with `packet-tunnel-provider`.
- `SpotierNE/SpotierNE.entitlements` includes `com.apple.developer.networking.networkextension` with `packet-tunnel-provider`.
- Both app and extension use App Group `group.com.alick.spotier`.
- Both app and extension use App Sandbox.
- Both app and extension allow network client and server access.
- The project no longer has a LaunchDaemon copy phase or privileged helper copy phase.
- `ServiceManagement.framework` remains linked because `SettingsView` uses `SMAppService.mainApp` for login item management, not a privileged helper.

## Privacy Notes

- Spotier is a user-controlled packet tunnel app. VPN packets pass through the local Network Extension provider.
- The app writes selected tunnel configuration to the shared App Group container as `config.toml`.
- The extension serves runtime status to the app through `NETunnelProviderSession.sendProviderMessage`.
- Logs are local app/runtime logs stored in the App Group log file and OSLog; no server upload path is documented in the current code.
- App Store privacy metadata still needs a final product policy review before submission because privacy labels depend on distribution behavior, analytics, and support workflows outside this source audit.

## Apple Documentation Checked

- Network Extension entitlement: `com.apple.developer.networking.networkextension` with packet tunnel provider capability.
- App Groups entitlement: `com.apple.security.application-groups`.
- App Sandbox network access entitlements: `com.apple.security.network.client` and `com.apple.security.network.server`.
- Privacy manifest guidance for documenting data use before App Store submission.
