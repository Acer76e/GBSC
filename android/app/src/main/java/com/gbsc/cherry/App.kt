package com.gbsc.cherry

import android.app.Application
import com.gbsc.cherry.data.Repo

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        Repo.init(this)
    }
}
