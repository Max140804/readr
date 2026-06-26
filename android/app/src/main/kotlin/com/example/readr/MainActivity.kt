package com.example.readr

import android.app.NotificationManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val i = Intent(context, MainActivity::class.java)
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        i.putExtra("trigger_lock_in", true)
        context.startActivity(i)
    }
}

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.readr/dnd"

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("trigger_lock_in", false)) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, CHANNEL).invokeMethod("triggerLockIn", null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            when (call.method) {
                "checkOverlayPermission" -> {
                    result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(this) else true)
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "isNotificationPolicyAccessGranted" -> {
                    result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) notificationManager.isNotificationPolicyAccessGranted else true)
                }
                "gotoPolicySettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                    }
                    result.success(null)
                }
                "getCurrentInterruptionFilter" -> {
                    result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) notificationManager.currentInterruptionFilter else 1)
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
                    } else result.success(false)
                }
                "wasStartedByAlarm" -> {
                    val wasStarted = intent.getBooleanExtra("trigger_lock_in", false)
                    if (wasStarted) {
                        intent.putExtra("trigger_lock_in", false)
                    }
                    result.success(wasStarted)
                }
                "scheduleNativeAlarm" -> {
                    val timeInMillis = call.argument<Long>("timeInMillis")
                    val id = call.argument<Int>("id") ?: 888
                    if (timeInMillis != null) {
                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        val intent = Intent(this, AlarmReceiver::class.java)
                        val pendingIntent = PendingIntent.getBroadcast(
                            this, id, intent, 
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
                        } else {
                            alarmManager.setExact(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent)
                        }
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "timeInMillis is null", null)
                    }
                }
                "cancelNativeAlarm" -> {
                    val id = call.argument<Int>("id") ?: 888
                    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val intent = Intent(this, AlarmReceiver::class.java)
                    val pendingIntent = PendingIntent.getBroadcast(
                        this, id, intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    alarmManager.cancel(pendingIntent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
