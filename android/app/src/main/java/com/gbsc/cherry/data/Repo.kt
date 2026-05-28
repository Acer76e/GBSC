package com.gbsc.cherry.data

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/**
 * Single source of truth for settings + trip history.
 * Initialised once from [com.gbsc.cherry.App] and shared by the UI and the capture service.
 */
object Repo {

    private const val TAG = "Repo"
    private val json = Json { ignoreUnknownKeys = true; prettyPrint = false }
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private lateinit var settingsFile: File
    private lateinit var historyFile: File

    private val _settings = MutableStateFlow(AppSettings())
    val settings: StateFlow<AppSettings> = _settings.asStateFlow()

    private val _history = MutableStateFlow<List<TripOffer>>(emptyList())
    val history: StateFlow<List<TripOffer>> = _history.asStateFlow()

    @Volatile private var initialised = false

    fun init(context: Context) {
        if (initialised) return
        initialised = true
        val dir = context.applicationContext.filesDir
        settingsFile = File(dir, "settings.json")
        historyFile = File(dir, "history.json")
        loadSettings()
        loadHistory()
    }

    private fun loadSettings() {
        runCatching {
            if (settingsFile.exists()) {
                _settings.value = json.decodeFromString(settingsFile.readText())
            }
        }.onFailure { Log.w(TAG, "loadSettings failed", it) }
    }

    private fun loadHistory() {
        runCatching {
            if (historyFile.exists()) {
                _history.value = json.decodeFromString(historyFile.readText())
            }
        }.onFailure { Log.w(TAG, "loadHistory failed", it) }
    }

    fun updateSettings(transform: (AppSettings) -> AppSettings) {
        val updated = transform(_settings.value)
        _settings.value = updated
        ioScope.launch {
            runCatching { settingsFile.writeText(json.encodeToString(updated)) }
                .onFailure { Log.w(TAG, "saveSettings failed", it) }
        }
    }

    fun addOffer(offer: TripOffer) {
        val updated = (listOf(offer) + _history.value).take(MAX_HISTORY)
        _history.value = updated
        persistHistory(updated)
    }

    fun deleteOffer(id: Long) {
        val updated = _history.value.filterNot { it.id == id }
        _history.value = updated
        persistHistory(updated)
    }

    fun clearHistory() {
        _history.value = emptyList()
        persistHistory(emptyList())
    }

    private fun persistHistory(list: List<TripOffer>) {
        ioScope.launch {
            runCatching { historyFile.writeText(json.encodeToString(list)) }
                .onFailure { Log.w(TAG, "saveHistory failed", it) }
        }
    }

    private const val MAX_HISTORY = 500
}
