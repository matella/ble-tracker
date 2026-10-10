package com.matella.ble_tracker

import android.content.pm.PackageManager
import android.os.Bundle
import androidx.wear.ambient.AmbientLifecycleObserver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * Hosts the Flutter UI. On Wear OS it also reports ambient mode (watch face
 * showing, wrist down) to Dart as a stream of booleans on [AMBIENT_CHANNEL].
 * On phones the observer is never registered, so the stream stays silent.
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
    }
}
