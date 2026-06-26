package com.example.readr

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class ShutdownReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Handle standard shutdown and some OEM specific ones
        if (intent.action == Intent.ACTION_SHUTDOWN || 
            intent.action == "android.intent.action.QUICKBOOT_POWEROFF" ||
            intent.action == "com.htc.intent.action.QUICKBOOT_POWEROFF") {
            
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                try {
                    if (notificationManager.isNotificationPolicyAccessGranted) {
                        // Set DND to OFF (Allow all)
                        notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
                    }
                } catch (e: Exception) {
                    // Best effort cleanup during shutdown
                }
            }
        }
    }
}
