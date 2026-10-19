# Scene-set recovery checks

Run `Tests/checks/vision-scene-set/run.sh` from repository root. This compiles the production
journal, replay gate and native-session binding policy with synthetic descriptors. It checks:

- Durable decoding, bounds, duplicate UUID/native IDs, source/size/preferences and no secrets.
- Whole-set discard, subset closure, late old-session discard after primary rebind.
- SameUUID replay once per process, fresh-process retry, bound-scene deduplication.
- Forget/Disconnect before replay, ordinary trust-list refresh, cancellation, and stale-view saves.

The DEBUG native fixture uses the real app entry point and `openWindow` with no network clients:

```sh
xcrun simctl install SIMULATOR /path/to/Debug-xrsimulator/SillVision.app
xcrun simctl launch --console-pty SIMULATOR me.saffer.sill.vision -SillSceneSetFixture
xcrun simctl terminate SIMULATOR me.saffer.sill.vision
xcrun simctl launch --console-pty SIMULATOR me.saffer.sill.vision -SillSceneSetFixture
```

The journal seeds primary plus UUID `00000000-0000-4000-8000-000000000029` only when empty.
The typed scene has Mouse on, text scale1.25, Auto off. Both actual windows should reappear after
process restart; no third window should be created. Preserve app data between launches.

Hardware gates: actual force-quit callback grouping, independent window close, build28 upgrade,
trusted reconnect to two real sources, both confirmed sizes and preferences, keyboard off, spatial
placement constraints. Native-session callback grouping is not established by simctl terminate.
