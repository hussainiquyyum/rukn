# Rukn Remote: iOS companion app plan

## Context

Rukn is a menu-bar Mac app (Swift, AppKit/SwiftUI, macOS 14+, not sandboxed, GPL-3.0-or-later). It has no account system, no telemetry, and no network listener today; its only listener is the fan-control XPC helper. You want an iPhone app that controls the Mac from anywhere. It must:
- only talk to one authorized Mac and one authorized phone,
- stay consistent with Rukn's "local-first, no account, no hidden network" stance,
- pick up the new Mac features you add later with little extra work.

Decisions made so far:
- **Connectivity:** private mesh VPN (Tailscale / WireGuard style). No router ports opened and no Rukn-run server.
- **v1 scope:** status and toggles.
- **Distribution:** public release (App Store), not just personal use.

## Architecture

```
iPhone (RuknRemote, SwiftUI)  <-- mTLS over the mesh VPN (or LAN) -->  Mac (Rukn "Remote" feature)
        |                                                                    |
 Keychain + Secure Enclave key                                  RemoteServer (NWListener)
        |                                                                    |
 UI generated from schema                          Capability registry -> existing services / Defaults
```

### 1. Shared protocol package: `RuknRemoteKit`
- New SwiftPM library target, built for macOS 14 and iOS 17. It holds only Codable models and framing, with no AppKit or UIKit.
- It carries a protocol version and an explicit compatibility rule, so an old phone app and a new Mac still work together.
- Message types:
  - `hello` with version and capabilities
  - `snapshot` (full state)
  - `subscribe` / `event` (live updates)
  - `command` / `ack` / `error`
- Transport is Network.framework: TLS 1.3 plus a length-prefixed (or WebSocket) frame. No third-party dependencies, matching the repo today.

### 2. Mac side: new opt-in feature `Remote`
- Add a case to `AppFeature` (`Sources/Rukn/Core/FeatureCatalog.swift:16`), **off by default and not part of presets**. Uninstalled means no listener is started.
- Lives in `Sources/Rukn/Services/Remote/`:
  - `RemoteServer`: `NWListener` with mutual TLS.
  - `RemotePairing`: QR / short-code flow and the trust store.
  - `RemoteCapabilityRegistry`: the allowlist of things the phone may read or change.
  - `RemoteAuditLog`: in-memory log of connections and commands.
- Settings UI at `Sources/Rukn/UI/Settings/RemoteSettings.swift`, following the one-file-per-feature pattern. It has the on/off switch, a pair-new-device button, a list of paired devices with revoke, a per-capability allow list, "allow on LAN as well" (default: mesh/VPN interface only), and a connection log.
- **Settings schema for future features:** `RemoteCapabilityRegistry` maps each remote-controllable item to its `DefaultsKey`, with type, range, label and category. Ranges and allowed values already exist in `Defaults.swift:1071`.
  - Reuse `SettingsBackupSupport.exportKeys()` and `machineStateKeys` (`Core/SettingsBackupSupport.swift:102`). Machine-state keys must never be remotely settable.
  - The phone renders its UI from this schema, so a new Mac feature only needs a registry entry. That is how the later features get supported without an iOS release each time.
- Actions that are not simple settings (lock screen, sleep display, empty Trash, eject) are explicit named commands that call the same code the menu bar toggles call.
- **Hard rule:** the registry is an allowlist. There is no arbitrary shell, script, AppleScript, keystroke injection or file access over this channel.

### 3. iOS app: `RuknRemote`
- SwiftUI, iOS 17+, a separate Xcode project under `iOS/` (the repo's real build is `build.sh`; `Package.swift` is for editor indexing only, so the iOS target needs its own build and CI job).
- Screens:
  - pairing (QR scanner)
  - Mac list with online/offline state
  - dashboard (status)
  - schema-driven toggles and sliders
  - settings (paired Macs, forget device)
- Private key in the Secure Enclave, pinned Mac certificate and settings in Keychain.
- Face ID or passcode gates the app, and gates sensitive commands (lock, fan control, quit protection).
- Later additions: App Intents (Shortcuts) and iOS 18 Control Center controls for the most common toggles. Widgets can follow.

### 4. Connectivity (mesh VPN, public-release implications)
- Both devices run Tailscale (free tier, user's own account). The phone reaches the Mac at its tailnet name or IP, and Rukn never sees the account. The same app also works over the LAN via Bonjour.
- The server listens on the VPN interface only by default, and a LAN toggle is optional. Security does not depend on the VPN: every connection needs a valid client certificate regardless of network.
- **Public-release friction to accept or solve later:** users must install and configure a third-party VPN on both devices. Keep the transport behind a small interface so a relay (end-to-end encrypted, outbound-only from both sides) or an embedded tailnet client can be added without changing the protocol or the security model.
- **Realistic limit:** a sleeping Mac is unreachable. Mitigations are the existing Keep Awake feature and a settings hint for "Wake for network access" (this works on the local network, not over the internet).

## Security design (the "nobody else can connect" requirement)

**Pairing (once per device):**
1. In Rukn on the Mac, the user presses Pair new device. The Mac shows a QR code that holds its certificate fingerprint, a **single-use token that expires in 2 minutes**, and address hints.
2. The phone scans it and connects with TLS pinned to that fingerprint. It sends its public key (generated in the Secure Enclave) and the token.
3. The Mac shows a 6-digit code that must match the phone, and the user **approves on the Mac**.
4. The Mac stores the phone's public key and the phone stores the Mac's certificate. Each side now trusts only the other.

**Every later connection:**
- Mutual TLS 1.3 with both certificates pinned. An unknown certificate is rejected during the handshake, before any application data is read.
- Rate limiting and temporary lockout on failed handshakes.
- No account, no tokens to steal, and no pairing secret reusable after step 3.

**Control and containment:**
- Allowlist of commands. Each capability has its own enable switch on the Mac, and risky ones are off by default.
- Per-device revocation on the Mac, effective immediately and dropping any open connection. Revocation also works if the phone is lost.
- Audit log on the Mac of who connected and what changed.
- The Mac keeps a "last remote change" notice, and optional local notifications for remote commands.

| Threat | Mitigation |
|---|---|
| Stranger on the same tailnet/LAN | Client cert required, pinned |
| Stolen phone | Face ID gate, revoke from Mac, no secrets on the Mac exposed |
| Replay or MITM at pairing | Short-lived single-use token, fingerprint pinning, code match approved on the Mac |
| Malicious paired phone | Allowlist only, no shell, per-capability switches |
| Protocol downgrade | Minimum TLS 1.3, versioned protocol |

## Feature scope

**v1 (realistic, low risk):**
- Status (read-only): battery and power, CPU, memory, temperatures, network, disk, fan RPM, AI Agents usage and limits.
- Toggles and values:
  - Keep Awake on/off/timer, display brightness, output volume and mute, output device
  - Quick toggles: appearance, hide desktop icons, lock screen, sleep display
  - Now Playing controls
  - Install/uninstall-free feature on/off for safe features only
- Mac-initiated notifications over the open connection (for example high temperature) while the app is open.

**Later:** Fan Control curves (high-risk, needs Face ID), clipboard and Shelf sending to the Mac (phone to Mac only, no reading the clipboard remotely), screenshot request with an on-Mac confirmation, and the new Mac features you are planning.

**Out of scope on purpose:** remote desktop or screen view, keystroke injection, shell or scripts, file browsing, reading the clipboard, camera or microphone access. These would turn a settings remote into a remote-access tool and make the security story much harder.

**Needs a server, so deferred:** push notifications when the app is closed (APNs). This conflicts with "no Rukn-operated service" unless made opt-in with minimal data.

## Risks to settle before building

1. **GPL vs App Store.** The Mac app is GPL-3.0-or-later, and part of it is Vorssaint's code, which you cannot relicense. GPL-3 apps are generally incompatible with App Store terms. Keep the iOS app and `RuknRemoteKit` as new, original code, and do not copy GPL files into them (Defaults ranges are described in the registry, not copied). Decide the license for those new targets, and consider a legal check.
2. **Tailscale dependency** for a public release (see above).
3. **Apple requirements:** Apple Developer Program for iOS, App Store privacy labels, Local Network usage description, and a review demo path for an app that needs a Mac to be useful.
4. **Support burden** of multiple Macs and phones, VPN troubleshooting, and the Mac firewall prompt.

## Phases

0. **Spike (about 1 week):** NWListener with mutual TLS on the Mac and a tiny test client over Tailscale. Verify the Mac stays reachable when the display sleeps, the firewall prompt, and cert pinning.
1. **Protocol and Mac server:** `RuknRemoteKit`, `RemoteServer`, pairing and trust store, capability registry with 3 or 4 capabilities, and a macOS command-line test client. Includes unit tests and `--selftest` coverage, and a `PRIVACY.md` entry (network connection 12, opt-in, no data leaves your devices).
2. **iOS MVP:** pairing, dashboard, schema-driven toggles, Keep Awake, volume, brightness, lock.
3. **Hardening:** audit log, revocation, rate limiting, Face ID gating, threat-model review, a security pass on pairing, and `SECURITY.md` / `PERMISSIONS.md` updates.
4. **Beta:** TestFlight and a Mac pre-release, with CI building the iOS target on the macOS runners.
5. **After v1:** App Intents and Control Center, widgets, new Mac features through the registry, and an optional relay.

## Critical files to change or add

- Add `Sources/RuknRemoteKit/` and update `Package.swift` (and `build.sh`, which assembles the real build).
- Add `Sources/Rukn/Services/Remote/` and `Sources/Rukn/UI/Settings/RemoteSettings.swift`.
- Edit `Sources/Rukn/Core/FeatureCatalog.swift` and `Sources/Rukn/App/FeatureRuntime.swift` to register the feature.
- Add `iOS/RuknRemote/`.
- Edit `docs/PRIVACY.md`, `docs/PERMISSIONS.md`, `SECURITY.md`, the README feature list, `CHANGELOG.md` `[Unreleased]`, and `.github/workflows/ci.yml`.

## Verification

- Unit tests (`./build.sh --test`): protocol encode/decode and version negotiation, capability allowlist, pairing token expiry and single-use, revocation.
- Security tests: a connection with no certificate, a wrong certificate, a revoked certificate and an expired token must all fail at handshake. Run a fuzz pass on the frame parser.
- End to end: pair a real iPhone with the Mac over Tailscale on cellular, flip Keep Awake and a slider, confirm the Mac changes, revoke the phone, confirm it is cut off immediately.
- Confirm that with the feature off, nothing listens (`lsof -iTCP -sTCP:LISTEN`).
