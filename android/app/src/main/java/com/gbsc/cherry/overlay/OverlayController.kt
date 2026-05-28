package com.gbsc.cherry.overlay

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import com.gbsc.cherry.R
import com.gbsc.cherry.data.CardPosition

data class OverlayData(
    val signature: String,
    val fareText: String,
    val miValue: String, val miColor: Int, val showMi: Boolean,
    val hrValue: String, val hrColor: Int, val showHr: Boolean,
    val minValue: String, val minColor: Int, val showMin: Boolean,
    val ratingValue: String, val ratingColor: Int, val showRating: Boolean,
    val tripText: String, val showTrip: Boolean,
    val profitText: String?, val profitColor: Int, val showProfit: Boolean,
    val borderColor: Int,
    val position: CardPosition,
    val offsetYdp: Int,
)

class OverlayController(private val context: Context) {

    private val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val main = Handler(Looper.getMainLooper())
    private var root: View? = null
    private var added = false
    private var dismissedSignature: String? = null

    private fun dp(value: Int): Int =
        (value * context.resources.displayMetrics.density).toInt()

    private fun layoutParams(position: CardPosition, offsetYdp: Int): WindowManager.LayoutParams {
        val type = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        val horizontal = when (position) {
            CardPosition.LEFT -> Gravity.START
            CardPosition.CENTER -> Gravity.CENTER_HORIZONTAL
            CardPosition.RIGHT -> Gravity.END
        }
        params.gravity = Gravity.TOP or horizontal
        params.y = dp(offsetYdp)
        params.x = if (position == CardPosition.CENTER) 0 else dp(8)
        return params
    }

    fun show(data: OverlayData) = main.post {
        if (dismissedSignature == data.signature) return@post
        if (dismissedSignature != null && dismissedSignature != data.signature) {
            dismissedSignature = null
        }
        val view = ensureView()
        bind(view, data)
        val params = layoutParams(data.position, data.offsetYdp)
        if (!added) {
            runCatching { wm.addView(view, params); added = true }
        } else {
            runCatching { wm.updateViewLayout(view, params) }
        }
        view.visibility = View.VISIBLE
    }

    fun hide() = main.post {
        root?.visibility = View.GONE
    }

    fun destroy() = main.post {
        root?.let { v -> runCatching { wm.removeView(v) } }
        root = null
        added = false
    }

    private fun ensureView(): View {
        root?.let { return it }
        val v = LayoutInflater.from(context).inflate(R.layout.overlay_card, null)
        v.findViewById<TextView>(R.id.btn_close).setOnClickListener {
            dismissedSignature = (v.tag as? String)
            v.visibility = View.GONE
        }
        root = v
        return v
    }

    private fun bind(v: View, d: OverlayData) {
        v.tag = d.signature

        val bg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(18).toFloat()
            setColor(0xF2111111.toInt())
            setStroke(dp(6), d.borderColor)
        }
        v.background = bg
        v.setPadding(dp(16), dp(12), dp(16), dp(12))

        v.findViewById<TextView>(R.id.tv_fare).text = d.fareText

        v.findViewById<LinearLayout>(R.id.block_mi).visibility = vis(d.showMi)
        v.findViewById<TextView>(R.id.tv_mi_value).apply { text = d.miValue }
        v.findViewById<View>(R.id.bar_mi).setBackgroundColor(d.miColor)

        v.findViewById<LinearLayout>(R.id.block_hr).visibility = vis(d.showHr)
        v.findViewById<TextView>(R.id.tv_hr_value).apply { text = d.hrValue }
        v.findViewById<View>(R.id.bar_hr).setBackgroundColor(d.hrColor)

        v.findViewById<LinearLayout>(R.id.block_min).visibility = vis(d.showMin)
        v.findViewById<TextView>(R.id.tv_min_value).apply { text = d.minValue }
        v.findViewById<View>(R.id.bar_min).setBackgroundColor(d.minColor)

        v.findViewById<LinearLayout>(R.id.block_rating).visibility = vis(d.showRating)
        v.findViewById<TextView>(R.id.tv_rating_value).apply { text = d.ratingValue }
        v.findViewById<View>(R.id.bar_rating).setBackgroundColor(d.ratingColor)

        v.findViewById<TextView>(R.id.tv_trip).apply {
            visibility = vis(d.showTrip)
            text = d.tripText
        }

        v.findViewById<TextView>(R.id.tv_profit).apply {
            if (d.showProfit && d.profitText != null) {
                visibility = View.VISIBLE
                text = d.profitText
                setTextColor(d.profitColor)
            } else {
                visibility = View.GONE
            }
        }
    }

    private fun vis(show: Boolean) = if (show) View.VISIBLE else View.GONE
}
