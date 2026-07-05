package com.gbsc.cherry.data

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.util.concurrent.Executors

/**
 * Single source of truth for settings + trip history.
 * Initialised once from [com.gbsc.cherry.App] and shared by the UI and the capture service.
 */
object Repo {

    private const val TAG = "Repo"
    private val json = Json { ignoreUnknownKeys = true; prettyPrint = false }
    // Single-threaded writer: launches run FIFO, so a stale settings/history snapshot
    // can never be written after a newer one, and writes never interleave.
    private val ioScope =
        CoroutineScope(SupervisorJob() + Executors.newSingleThreadExecutor().asCoroutineDispatcher())

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

    private var settingsSaveJob: Job? = null

    fun updateSettings(transform: (AppSettings) -> AppSettings) {
        val updated = transform(_settings.value)
        _settings.value = updated
        // Debounce: slider drags call this dozens of times per second. The in-memory
        // state above is always immediate; the file write happens once the value has
        // been stable for a moment, and always snapshots the LATEST settings.
        settingsSaveJob?.cancel()
        settingsSaveJob = ioScope.launch {
            delay(SETTINGS_SAVE_DEBOUNCE_MS)
            val snapshot = _settings.value
            runCatching { writeAtomically(settingsFile, json.encodeToString(snapshot)) }
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
            runCatching { writeAtomically(historyFile, json.encodeToString(list)) }
                .onFailure { Log.w(TAG, "saveHistory failed", it) }
        }
    }

    /** Write to a sibling temp file, then rename over the target, so a crash or kill
     *  mid-write can never leave truncated/corrupt JSON that resets everything on load. */
    private fun writeAtomically(file: File, content: String) {
        val tmp = File(file.parentFile, file.name + ".tmp")
        tmp.writeText(content)
        if (!tmp.renameTo(file)) {
            // renameTo should always succeed within filesDir; fall back just in case.
            file.writeText(content)
            tmp.delete()
        }
    }

    private const val MAX_HISTORY = 500
    private const val SETTINGS_SAVE_DEBOUNCE_MS = 300L
}
