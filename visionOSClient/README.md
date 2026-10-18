# Native visionOS client

SillVision is a native visionOS 2+ app, built from the shared iPad client source
and StreamProtocol package. Each spatial scene presents its own selected Mac window
or Desktop stream with the full Sill controls. The updated host supports up to four
independent scenes; hold a window preview and choose Open as own window. Immersive
spaces and audio are not included. This is a development contribution toward issue #119.

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

## Deep links

Open the native visionOS app with `sill://` or `sill://open` (an optional trailing
slash is accepted). These launch links leave the current connection, selected
source and pending pairing confirmation unchanged. They accept no query,
fragment, credentials or port.

Existing `sill://pair?...` links still show the pairing confirmation before any
pairing action. Invalid pairing links still report a pairing error. Launch links
do not connect to a Mac or run remote commands.

## Implementation and compatibility

`SillVisionApp` → `VisionSessionView` → shared `ContentView` is the active UI.
It retains discovery, Apps, thumbnails/window actions, Mac menus, text scale,
settings, pairing, tour and clipboard controls. The native toolbar can sit above
or to the left of the picture, with system hover reveal or explicit visibility. visionOS adaptations are guarded in the shared
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
so iPhone/iPad regression review is needed. Legacy clients retain their shared
source. Vision clients opt into connection-owned capture and encoder pipelines;
see [independent sessions](../docs/independent-sessions.md) for admission, input,
physical window fitting, and Virtual Display limitations. An older host can serve
the primary scene, but opening or restoring an independent scene requires the new host.

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


### Spatial windows and toolbar (0.17 candidate)

Each “Open as own window” scene owns the full Sill interface and a separate client. A scene value
contains only a random UUID; its paired-host seed remains in memory for at most 60 seconds. A
restored auxiliary scene without that seed shows discovery and requires a manual Mac selection.
Only the owning UIKit scene's disconnect notification stops its client. Ordinary SwiftUI
appear/disappear and a sibling taking focus do not disconnect another stream.

A new host pipeline finishes its first catalog read before publishing its window list. The client
retains the selected source through early empty catalogs for up to ten seconds, then shows a
connection error if the window remains unavailable. A later explicit app/window choice cancels
that pending selection. Choosing an app with an existing window selects it immediately, including
when its catalog is unchanged; selections made during a stream switch wait for it to finish.

Toolbar position and Always show toolbar are saved per scene. The centered frosted pill has
no visible symbol or text; gaze reveals its toolbar, and tapping it provides an accessible
explicit reveal that lasts until remote control. Always show is available only in Settings.
The old manually-hidden preference is no longer read, so a restored scene always retains its
glance target. Toolbar/stream geometry stays fixed as the compositor reveals or hides controls.

On visionOS 26+, a scene-local `HoverEffectGroup` activates from the toolbar/pill. An explicit
no-op hover effect on the content surface and surrounding layout uses `preservesGroup`: looking
back at the picture keeps an already revealed group active without revealing an inactive one.
An accepted remote click, key, text insertion or scroll starts a control episode and changes
that scene's group identity, allowing the toolbar to collapse. Pointer hover/movement and
source selection do not dismiss it. Gaze state never enters app code. Looking outside this
app can end the group after a one-second exit delay; open tools and VoiceOver keep it visible.
On visionOS 2–25, the persistence API is unavailable: gaze reveal has the one-second exit grace,
and tapping the pill still keeps it visible until remote control. These are supported-system
behaviors awaiting real-headset acceptance, not a claim of tracked gaze or infinite persistence.

The left toolbar is a native leading ornament, so its controls remain interactive outside the
streamed window boundary. Its height equals the horizontal toolbar's offered width; the preview
strip receives the space remaining after fixed controls. Its window actions use a native popover
inside the ornament rather than an in-window anchor overlay. Top controls stay in layout, with
194 points of scene chrome including the glance target and stream padding. The left ornament
reserves only the stream's 16-point padding. Sidebar text size uses a native popover. The guided
tour temporarily uses the top arrangement so its spotlight and cards share the scene coordinate
space; completing or dismissing it restores the saved left-side preference.

The login scene starts at 580 × 480 points with a reusable Sill logo. The native size bridge uses
only its own UIWindowScene and requests a bounded preferred size once per connected Mac-window
selection. Mac-window sizing freezes the catalog's point size before sending the source request;
a secondary scene carries its parent's pre-launch snapshot through the opaque in-memory seed. The first Desktop after connecting gets a comfortable 1200 × 800 point default; later Desktop
picks keep the current native size because the protocol has no source-bound Desktop dimensions.
It never reuses a previous window's encoded size. Later video/catalog changes and manual scene resizing do not
retrigger fitting. Tiny and
extreme-aspect sources can have letterboxing within the system's minimum window size. A new
connection/source selection starts a new sizing decision. Geometry requests remain system
preferences and can be declined.

Debug visual checks can use `-SillToolbar top|left`, `-SillToolbarAutomatic 0|1` with the existing layout harness. The pure sizing check is
`Tests/checks/vision-window-size/run.sh`. Gaze, multiwindow focus, window sizing and physical input
still require Vision Pro acceptance.
