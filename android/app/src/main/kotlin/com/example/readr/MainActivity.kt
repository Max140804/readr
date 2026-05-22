package com.example.readr

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.readr/dnd"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            when (call.method) {
                "isNotificationPolicyAccessGranted" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        result.success(notificationManager.isNotificationPolicyAccessGranted)
                    } else {
                        result.success(true)
                    }
                }
                "gotoPolicySettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                        startActivity(intent)
                        result.success(null)
                    } else {
                        result.success(null)
                    }
                }
                "setInterruptionFilter" -> {
                    val filter = call.argument<Int>("filter")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && filter != null) {
                        try {
                            notificationManager.setInterruptionFilter(filter)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("DND_ERROR", e.message, null)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "getCurrentInterruptionFilter" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        result.success(notificationManager.currentInterruptionFilter)
                    } else {
                        result.success(1) // INTERRUPTION_FILTER_ALL
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
