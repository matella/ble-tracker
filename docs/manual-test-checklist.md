# Manual Test Checklist (per release)

Executed manually per release — replaces integration tests (§7.1).

- [ ] 1. Android + iOS: register headphones, verify band transitions walking away/toward.
- [ ] 2. Adapter off/on mid-session on each mobile platform → recoverable UI.
- [ ] 3. Permission revoke mid-session (Android) → unauthorized state, re-grant recovers.
- [ ] 4. Web (Chrome): manual pair, RSSI polling updates radar; Safari shows unsupported message.
- [ ] 5. Wear OS: foreground tracking of one device; background resume shows paused-state notice.
- [ ] 6. 20+ simultaneous devices on Android: radar remains ≥ 30 fps (visual check + DevTools).

Release: ____________  Tester: ____________  Date: ____________
