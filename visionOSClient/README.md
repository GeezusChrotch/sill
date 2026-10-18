# Native visionOS client

SillVision is a native visionOS 2+ app, built from the shared iPad client source
and StreamProtocol package. It presents one resizable spatial window with a single
selected Mac window or Desktop stream. It does not provide multiple independent
spatial streams, immersive spaces or audio. This is a partial contribution toward
the visionOS request in issue #119; separate Mac windows in space remain future work.

The owner reports the 0.14.0 (14) development build works well on Vision Pro.
That usability report is not exhaustive feature parity or device acceptance for
every input, network and application combination.

## Build

Use the repository's Xcode requirement (currently Xcode 27.1+ for the shared iOS
source) with the visionOS SDK installed. Open
`visionOSClient/SillVision.xcodeproj` and select the SillVision scheme. The project
links the package at `..` and compiles shared files from `../iOSClient`; keep this
folder in the repository rather than copying it out alone.

For a simulator build without signing, from the repository root:

```sh
xcodebuild -project visionOSClient/SillVision.xcodeproj -scheme SillVision \
  -destination 'generic/platform=visionOS Simulator' -configuration Debug \
  -derivedDataPath .build/visionos-simulator CODE_SIGNING_ALLOWED=NO ARCHS=arm64 build
```

The checked-in project needs no generator to build. If changing its structure,
`xcodegen generate --spec visionOSClient/project.yml` regenerates it from the spec.
Keep version/build values in the spec and project synchronized.

For a headset build, select your own development team and a unique bundle
identifier in Signing & Capabilities. No contributor signing identity or
provisioning profile is included. Development signing is for local testing;
App Store/TestFlight distribution requires the maintainer's release setup.

Build the Mac companion using the root README. Pair the headset on the same
network using the typed pairing code/address or a Sill pairing link; the native
client does not scan camera codes. A development-signed Mac host may require
fresh Screen Recording/Accessibility grants and pairing, since its identity and
keychain access can differ from the released app.

## Implementation and compatibility

`SillVisionApp` → `VisionSessionView` → shared `ContentView` is the active UI.
It retains discovery, Apps, thumbnails/window actions, Mac menus, text scale,
settings, pairing, tour and clipboard controls. Resizing selects the shared
landscape or portrait arrangement. visionOS adaptations are guarded in the shared
source; normal iPhone/iPad builds retain their platform behavior.

Touch mode maps hand taps to clicks and pans to scrolling. A stationary hold and
release right-clicks; hold then move starts a left drag. Mouse mode uses a relative
cursor with click-at-cursor and a one-time recenter after source changes. Physical
pointer input retains its separate route. Keyboard explicitly toggles capture; hold it for 0.5 seconds to open its tools
(including Paste Text and right-click at the last point). Source, local focus and scene changes cancel held input. Clipboard sharing starts
off and system Paste retains session/focus checks.

The host changes are part of this contribution:

- `WindowList.runningApps` optionally supplies running apps, including minimized
  or windowless ones. Older hosts fall back to the selectable-window inventory.
- The catalog conservatively admits offscreen windows only with known visible,
  nonminimized state and an unambiguous accessibility match. Explicit app launch
  can restore a minimized window or fall back to Desktop for a windowless app.
- `WindowList.editableFocus = 1` advertises optional kind 33 click confirmation.
  The visionOS client requests this only after a matching delivered click; a
  positive, current reply may open the keyboard. The host reads accessibility
  role/state and element identity, never field text. Older hosts keep explicit
  Keyboard control. This new wire allocation needs maintainer review alongside
  other in-flight protocol work; the protocol generation remains 1.

Existing message numbers and required payloads remain unchanged. New catalog
fields are optional. The shared catalog/host changes also affect iOS clients,
so iPhone/iPad regression review is needed. One host still has one shared active
source; additional client connections do not become independent window streams.

Earlier prototype views (`VisionAppLauncher`, `VisionHelp`, `VisionHostSettings`,
`VisionMacMenus`/`VisionMacMenuButton`, `VisionStreamSurface`) and their input
helpers remain compiled but are not referenced by the active root. They are
retained to keep this handoff focused and preserve their existing pure checks;
they do not describe the active UI or establish its behavior.

## Validation and remaining device checks

From the repository root:

```sh
Tests/checks/run-all.sh
swift build -c release
```

The runner automatically includes every `Tests/checks/*/run.sh`, including the new
app-inventory, client-catalog, editable-focus, vision-input, vision-controls,
vision-spatial-input and window-catalog checks. It also exercises modified
clipboard, hardware-keyboard and pointer-presence checks. The two older
vision-input/vision-controls checks cover retained prototype helpers; the active
shared input path has additional hardware-keyboard and vision-spatial-input
policy coverage. Pure checks do not synthesize real hand input or decode video.
CI builds the host and iOS/visionOS simulator targets unsigned.

The upstream DEBUG mock harness can render layouts without a Mac using launch
arguments such as `-SillLayout 1200x800`, `-SillDrawer 1` and `-SillSettings 1`.
Mock renders establish layout only. An isolated iPad reference may use
`SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG SILL_FLAT_REFERENCE'` if the local SDK
lacks the Duo hinge APIs; normal iOS builds retain those APIs.

Before release, verify real headset tap/scroll/hold/drag and cancellation, portrait
relative input, thumbnail holds/reorder, Bluetooth pointers/keyboards, keyboard
focus and dismissal around local fields, IME/dictation, clipboard consent, HEVC
playback and sustained latency, home/remote pairing and reconnect, old-host
fallback, and cross-Space/minimized-window selection. Check iPhone/iPad behavior
with both released and updated hosts. No exhaustive matrix of these combinations
has been completed, and no public visionOS release is claimed here.
