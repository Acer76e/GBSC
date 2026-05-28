package com.gbsc.cherry.capture

import android.content.Intent
import kotlinx.coroutines.flow.MutableStateFlow

/** Stashes the MediaProjection permission grant so the service can pick it up. */
object ProjectionHolder {
    var resultCode: Int = 0
    var data: Intent? = null
    val isRunning = MutableStateFlow(false)

    fun clear() {
        resultCode = 0
        data = null
    }
}
