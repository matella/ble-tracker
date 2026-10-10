package com.matella.ble_tracker

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.wear.ambient.AmbientLifecycleObserver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI.
 *
 * - On Wear OS it reports ambient mode (watch face showing, wrist down) to Dart
 *   as a stream of booleans on [AMBIENT_CHANNEL]. On phones the observer is
 *   never registered, so that stream stays silent.
 * - On Android it starts and stops [BackgroundScanService] on request from Dart
 *   on [BACKGROUND_CHANNEL], so scanning can continue while the app is in the
 *   background (FR-19, Tier A).
 */
class MainActivity : FlutterActivity() {
    private var ambientSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AMBIENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    ambientSink = events
                }

                override fun onCancel(arguments: Any?) {
                    ambientSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL)
            .setMethodCallHandler { call, result ->
                val intent = Intent(this, BackgroundScanService::class.java)
                when (call.method) {
                    "start" -> {
                        startForegroundService(intent)
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH)) {
            lifecycle.addObserver(
                AmbientLifecycleObserver(
                    this,
                    object : AmbientLifecycleObserver.AmbientLifecycleCallback {
                        override fun onEnterAmbient(
                            ambientDetails: AmbientLifecycleObserver.AmbientDetails
                        ) {
                            ambientSink?.success(true)
                        }

                        override fun onExitAmbient() {
                            ambientSink?.success(false)
                        }
                    }
                )
            )
        }
    }

    companion object {
        /** Must match `wearAmbientChannel` in lib/platform/wear/ambient_channel.dart. */
        const val AMBIENT_CHANNEL = "ble_tracker/ambient"

        /** Must match `AndroidBackgroundScanHost` in lib/platform/android/background_scan_host.dart. */
        const val BACKGROUND_CHANNEL = "ble_tracker/background"
    }
}
