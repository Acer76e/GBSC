package com.gbsc.cherry.overlay

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
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
    val bgColor: Int,
    val textColor: Int,
    val subTextColor: Int,
    val alpha: Float,
    val fontBase: Int,
    val durationMs: Long,
    val position: CardPosition,
    val offsetYdp: Int,
)

class OverlayController(private val context: Context) {

    private val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val main = Handler(Looper.getMainLooper())
    private var root: View? = null
    private var added = false
    private var dismissedSignature: String? = null
    private var scheduledForSignature: String? = null

    private fun dp(value: Int): Int =
        (value * context.resources.displayMetrics.density).toInt()

    private fun layoutParams(position: CardPosition, offsetYdp: Int): WindowManager.LayoutParams {
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
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

        if (data.durationMs > 0 && scheduledForSignature != data.signature) {
            scheduledForSignature = data.signature
            val sig = data.signature
            main.postDelayed({
                if (root?.tag == sig) {
                    root?.visibility = View.GONE
                    dismissedSignature = sig
                }
            }, data.durationMs)
        }
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

    private fun TextView.style(color: Int, sizeSp: Float) {
        setTextColor(color)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
    }

    private fun bind(v: View, d: OverlayData) {
        v.tag = d.signature

        val bg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(18).toFloat()
            setColor(d.bgColor)
            setStroke(dp(6), d.borderColor)
        }
        v.background = bg
        v.alpha = d.alpha
        v.setPadding(dp(16), dp(12), dp(16), dp(12))

        val base = d.fontBase.toFloat()
        val valueSize = base * 1.95f
        val labelSize = base * 0.85f
        val smallSize = base * 1.05f

        v.findViewById<TextView>(R.id.tv_fare).apply {
            text = d.fareText; style(d.textColor, base * 1.85f)
        }
        v.findViewById<TextView>(R.id.btn_close).style(d.subTextColor, base * 1.5f)

        bindMetric(
            v, R.id.block_mi, R.id.tv_mi_value, R.id.tv_mi_label, R.id.bar_mi,
            d.showMi, d.miValue, d.miColor, d.textColor, d.subTextColor, valueSize, labelSize
        )
        bindMetric(
            v, R.id.block_hr, R.id.tv_hr_value, R.id.tv_hr_label, R.id.bar_hr,
            d.showHr, d.hrValue, d.hrColor, d.textColor, d.subTextColor, valueSize, labelSize
        )
        bindMetric(
            v, R.id.block_min, R.id.tv_min_value, R.id.tv_min_label, R.id.bar_min,
            d.showMin, d.minValue, d.minColor, d.textColor, d.subTextColor, valueSize, labelSize
        )
        bindMetric(
            v, R.id.block_rating, R.id.tv_rating_value, R.id.tv_rating_label, R.id.bar_rating,
            d.showRating, d.ratingValue, d.ratingColor, d.textColor, d.subTextColor, valueSize, labelSize
        )

        v.findViewById<TextView>(R.id.tv_trip).apply {
            visibility = if (d.showTrip) View.VISIBLE else View.GONE
            text = d.tripText
            style(d.subTextColor, smallSize)
        }

        v.findViewById<TextView>(R.id.tv_profit).apply {
            if (d.showProfit && d.profitText != null) {
                visibility = View.VISIBLE
                text = d.profitText
                style(d.profitColor, smallSize)
            } else {
                visibility = View.GONE
            }
        }
    }

    private fun bindMetric(
        v: View,
        blockId: Int, valueId: Int, labelId: Int, barId: Int,
        show: Boolean, value: String, barColor: Int,
        textColor: Int, subColor: Int, valueSize: Float, labelSize: Float,
    ) {
        v.findViewById<View>(blockId).visibility = if (show) View.VISIBLE else View.GONE
        v.findViewById<TextView>(valueId).apply { text = value; style(textColor, valueSize) }
        v.findViewById<TextView>(labelId).style(subColor, labelSize)
        v.findViewById<View>(barId).setBackgroundColor(barColor)
    }
}
