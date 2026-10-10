# Manual Test Checklist (per release)

Executed manually per release — replaces integration tests (§7.1).

- [ ] 1. Android + iOS: register headphones, verify band transitions walking away/toward.
- [ ] 2. Adapter off/on mid-session on each mobile platform → recoverable UI.
- [ ] 3. Permission revoke mid-session (Android) → unauthorized state, re-grant recovers. Revocation is detected on the next `startScan` attempt, not pushed proactively — trigger one (e.g. switch tabs) after revoking to see the state change.
- [ ] 4. Web (Chrome): manual pair, RSSI polling updates radar; Safari shows unsupported message. Switch to another tab and back: the radar stops scanning while hidden and resumes on return (FR-19, Tier C). Also check the Settings screen: changing the environment factor persists across a reload.
- [ ] 5. Wear OS (Samsung Galaxy Watch): install the debug APK with `flutter run --dart-define=WEAR_OS=true` (or `adb install`). (a) Foreground tracking of one device. (b) Raise the wrist / let the face dim: radar should show ambient (balanced scan); lift it again and the lowLatency scan resumes. Confirm in logs that the ambient event arrives. (c) Lower the wrist for longer, then return: the "Updates were paused in the background — resuming" banner appears and clears at the next observation. Check whether a simple wrist raise also triggers that banner (open question: ambient transitions may fire hide/show events too); if it does, the notice needs narrowing. Verified only by compilation until run on the watch (#25).
- [ ] 6. 20+ simultaneous devices on Android: radar remains ≥ 30 fps (visual check + DevTools).
- [ ] 7. Linux: two simultaneous devices both update RSSI continuously (exercises the parallel BlueZ stream merge, which has no automated coverage).

Release: ____________  Tester: ____________  Date: ____________
