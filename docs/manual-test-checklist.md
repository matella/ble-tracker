# Manual Test Checklist (per release)

Executed manually per release — replaces integration tests (§7.1).

- [ ] 1. Android + iOS: register headphones, verify band transitions walking away/toward.
- [ ] 2. Adapter off/on mid-session on each mobile platform → recoverable UI.
- [ ] 3. Permission revoke mid-session (Android) → unauthorized state, re-grant recovers. Revocation is detected on the next `startScan` attempt, not pushed proactively — trigger one (e.g. switch tabs) after revoking to see the state change.
- [ ] 4. Web (Chrome): manual pair, RSSI polling updates radar; Safari shows unsupported message.
- [ ] 5. Wear OS: foreground tracking of one device; background resume continues tracking without crash. (A dedicated "updates paused" notice is not yet implemented — Tier B throttling UX ships with the ambient wiring, issue #22.)
- [ ] 6. 20+ simultaneous devices on Android: radar remains ≥ 30 fps (visual check + DevTools).
- [ ] 7. Linux: two simultaneous devices both update RSSI continuously (exercises the parallel BlueZ stream merge, which has no automated coverage).

Release: ____________  Tester: ____________  Date: ____________
