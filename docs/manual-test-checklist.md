# Manual Test Checklist (per release)

Executed manually per release — replaces integration tests (§7.1).

- [ ] 1. Android + iOS: register headphones, verify band transitions walking away/toward.
- [ ] 2. Adapter off/on mid-session on each mobile platform → recoverable UI.
- [ ] 3. Permission revoke mid-session (Android) → unauthorized state, re-grant recovers. Revocation is detected on the next `startScan` attempt, not pushed proactively — trigger one (e.g. switch tabs) after revoking to see the state change.
- [ ] 4. Web (Chrome): manual pair, RSSI polling updates radar; Safari shows unsupported message. Switch to another tab and back: the radar stops scanning while hidden and resumes on return (FR-19, Tier C). Also check the Settings screen: changing the environment factor persists across a reload.
- [ ] 5. Wear OS: foreground tracking of one device; background resume continues tracking without crash. (The "updates paused" notice and real ambient wiring are not yet implemented — tracked in issue #25.)
- [ ] 6. 20+ simultaneous devices on Android: radar remains ≥ 30 fps (visual check + DevTools).
- [ ] 7. Linux: two simultaneous devices both update RSSI continuously (exercises the parallel BlueZ stream merge, which has no automated coverage).
- [ ] 8. Calibration (any platform with a real BLE device): stand 1 m from the device, tap Calibrate at 1 m on its detail sheet, confirm the saved reference (dBm at 1 m) is plausible and that the distance reads about 1 m afterwards. Reset returns the device to advertised TxPower.

Release: ____________  Tester: ____________  Date: ____________
