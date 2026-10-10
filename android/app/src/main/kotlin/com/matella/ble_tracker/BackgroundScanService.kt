package com.matella.ble_tracker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder

/**
 * Keeps the app process alive while BLE scanning runs in the background
 * (FR-19, Tier A). It does not scan itself: flutter_blue_plus keeps the scan
 * running in the Flutter engine, and this service stops the process from being
 * killed in the meantime. It is started and stopped by the Dart side through
 * MainActivity's `ble_tracker/background` channel.
 *
 * Shows a persistent notification, as Android requires for foreground services.
 * Stops itself when the task is swiped from recents, so the notification
 * cannot outlive a scan that is no longer running.
 */
class BackgroundScanService : Service() {

    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Background scanning",
            NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("BLE Tracker is scanning")
            .setContentText("Tracking nearby devices in the background")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .build()
        // Minimum SDK is 31, so the typed overload is always available.
        startForeground(
            NOTIFICATION_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
        )
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val CHANNEL_ID = "ble_scan"
        const val NOTIFICATION_ID = 1001
    }
}
