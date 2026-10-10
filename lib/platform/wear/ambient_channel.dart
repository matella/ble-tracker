import 'package:flutter/services.dart';

/// Ambient mode from the Wear OS host activity (MainActivity.kt). Emits `true`
/// when the watch enters ambient (wrist down, face showing) and `false` when it
/// exits. Thin and untested, like the other platform `*Impl` wrappers: the
/// behaviour is covered by WearScanner's tests and the manual checklist.
Stream<bool> wearAmbientChannel() =>
    const EventChannel('ble_tracker/ambient')
        .receiveBroadcastStream()
        .map((event) => event as bool);
