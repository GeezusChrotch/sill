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
  can restore a minimized window or reopen a running app, retaining a bounded
  selection intent while its window appears.
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


### Spatial windows and toolbar (0.20 candidate)

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

During normal streaming, window previews and Desktop share the top bar. Apps, Mac menus,
text size, Touch/Mouse, Keyboard, Settings and a lock button occupy a vertical bar on the left.
Both bars are native ornaments outside the picture, so reveal and collapse do not resize the stream.
Both bars sit 12 points from the window. The lock is the last control, immediately after
Settings in the left bar's scrolling stack; there is no fixed top slot or large spacer.
Window previews scroll horizontally. Window actions and text size retain native popovers.
The guided tour temporarily retains its full inline toolbar so its spotlight targets share
the scene coordinate space.

In Auto, a visible frosted horizontal pill sits at the top and a vertical pill sits on the
left, centered inside each future bar's footprint. Looking at either pill activates the
shared hover group. Both bars fade over the pills in the same native ornament ZStacks;
the pills fade out as the bars appear. The pills have no icon, text or tap action. Their
nonzero frosted surfaces use native hover highlight, with explicit hover content shapes.
Actual gaze transitions remain a physical headset acceptance check.

The left bar's last lock button switches between pinned open and Auto. Its icon shows an
open lock in Auto and a closed lock when pinned. The choice persists per scene, with Auto
the default for a new scene. Build 23's forced appearance/background pinning is removed now
that visible glance targets are present. A stored pinned choice remains pinned until the
lock returns it to Auto. Open panels, window actions and VoiceOver keep both bars visible
while needed. Pinned open remains visible through remote input. There is no separate
Controls gear/tray, and ornament reveal does not change the picture's layout or aspect ratio.

On visionOS 26+, one scene-local `HoverEffectGroup` controls both bars. A no-op hover effect
on the content surface uses `preservesGroup`: looking back at the picture keeps an already
revealed group active without revealing an inactive one. In Auto, an accepted remote click,
key, text insertion or scroll starts a control episode and changes that scene's group identity,
allowing both bars to collapse together. Pointer hover/movement and preview selection do not
dismiss them. No gaze coordinates or gaze state enter app code. Looking outside this app can
end the group after a one-second exit delay. On visionOS 2–25, the persistence API is unavailable:
gaze reveal retains the one-second exit grace; the lock button can pin both bars open. Actual gaze
transitions and hidden-control hit testing remain real-headset acceptance checks.

The login scene starts at 580 × 480 points with a reusable Sill logo. The native size bridge uses
only its own UIWindowScene and requests a bounded preferred size once per connected Mac-window
selection. Mac-window sizing freezes the catalog's point size before sending the source request;
a secondary scene carries its parent's pre-launch snapshot through the opaque in-memory seed.
Desktop waits for valid HEVC dimensions received after the host acknowledges that selection,
then locks the native scene to the encoded Desktop aspect. This can wait until the next
keyframe, up to about four seconds. The matching host fences retired encoder output before
acknowledging a source switch, so the dimensions belong to Desktop. Older hosts without that
fence can briefly supply a stale shape until the next Desktop keyframe; the client does not
reuse its cached video dimensions.
Selected-window and Desktop scenes first release the previous uniform aspect lock. After
observing freeform geometry, they request the new size and wait until the actual scene bounds
match the source ratio within one point of fitted-picture slack. Only then do they request
uniform resizing with the explicit system-accepted size. The bridge confirms both actual bounds
and effective uniform restriction before recording success. Two bounded attempts handle request
refusals or delayed transitions; an unconfirmed size remains freeform and retries after activation
or a different source. Requests are canceled when the owning scene detaches, disconnects,
deactivates, or changes source. The picture fills a matching scene without fixed padding. Minimum, preferred and maximum sizes scale
uniformly. Login and selections awaiting valid dimensions allow freeform resizing. Later
window video/catalog changes preserve the selection snapshot; Desktop updates only when its
encoded dimensions change. Desktop capture does not follow the viewport, so neither path
creates a viewport-to-scene sizing loop. Geometry requests remain system preferences and can
be declined or constrained,
especially for extreme aspect ratios. Mac apps with their own window-size limits or a second
viewer of an already fitted window can still produce a source frame with different dimensions;
the renderer preserves the full image without cropping or stretching.

Debug visual checks can use `-SillControls 1` to pin both bars open or
`-SillToolbarAutomatic 0|1` with the existing layout harness. `-SillToolbar top|left` is no
longer read. The pure sizing check is
`Tests/checks/vision-window-size/run.sh`. Gaze, multiwindow focus, window sizing and physical input
still require Vision Pro acceptance.

`-SillNativeGeometry 1` is a separate DEBUG-only native scene diagnostic. It never connects or
browses and does not use LayoutHarness or a fixed scene frame. It runs none → 1440×900 window →
3840×2160 Desktop against the production scene-size bridge. Red represents scene space outside
the blue fitted source. `NATIVE_GEOMETRY` stdout records actual SwiftUI bounds, requested size,
and observed UIKit bounds/restrictions. This isolates scene resizing; its injected Desktop size
does not establish HEVC transport delivery, real stream layout, or headset acceptance. Normal
DEBUG sessions also log source-bound HEVC dimension acceptance and waiting for missing dimensions.

The last 30 geometry events are also saved to `Library/Caches/SillWindowGeometry.json` in all
build configurations. Each event contains only numeric timestamp, phase, ephemeral scene ordinal,
source kind, source/actual/requested dimensions, effective restriction, and an optional numeric
error code. Source kinds: 0 login, 1 window, 2 Desktop, 3 none. Phases: 1 release, 2 size request,
3 uniform lock, 4 confirmed, 5 declined, 6 awaiting dimensions, 7 retry exhaustion, 8 accepted
Desktop HEVC dimensions (transport event, scene ordinal 0). Writes run on a serial utility queue;
no video, titles, source identifiers, hosts, addresses, or user content are saved. This small cache
is diagnostic evidence for an installed headset test and is overwritten as events arrive.
