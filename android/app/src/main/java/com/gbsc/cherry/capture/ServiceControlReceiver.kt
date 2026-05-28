package com.gbsc.cherry.capture

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ServiceControlReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ScreenCaptureService.ACTION_STOP) {
            ScreenCaptureService.stop(context)
        }
    }
}
