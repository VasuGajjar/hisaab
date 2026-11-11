package finance.vasugajjar.tracker.tracker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build

/**
 * Capture notifications: one per payment, worded by Store.captureNotice() in
 * Dart. Category buttons go to [CaptureActionReceiver] (no UI); Add details
 * and a tap on the body open the app on that payment.
 */
object Notices {
    const val GROUP = "captures"

    /** Notification id for a transaction; 1 is the daily check-in. */
    private fun nid(txn: Int) = 1000 + txn

    private fun channel(nm: NotificationManager, id: String) {
        if (Build.VERSION.SDK_INT < 26) return
        nm.createNotificationChannel(
            when (id) {
                "unread" -> NotificationChannel(id, "Couldn't read SMS", NotificationManager.IMPORTANCE_LOW)
                else -> NotificationChannel(id, "Captured payments", NotificationManager.IMPORTANCE_HIGH)
            },
        )
    }

    private fun builder(ctx: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(ctx, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx).setPriority(if (channel == "unread") Notification.PRIORITY_LOW else Notification.PRIORITY_HIGH)
        }

    fun open(ctx: Context, route: String, code: Int): PendingIntent = PendingIntent.getActivity(
        ctx, code,
        Intent(ctx, MainActivity::class.java)
            .putExtra("route", route)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /**
     * [m]: id, title, text, channel, route, actions [{label, cat | ignore | undo + rule | route}],
     * timeout (ms), or cancel: true to take it down.
     */
    fun post(ctx: Context, m: Map<*, *>) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        val txn = (m["id"] as Number).toInt()
        if (m["cancel"] == true) return nm.cancel(nid(txn))
        val ch = m["channel"] as? String ?: "capture"
        channel(nm, ch)
        val icon = Icon.createWithResource(ctx, R.drawable.ic_stat_hisaab)
        val b = builder(ctx, ch)
            .setSmallIcon(R.drawable.ic_stat_hisaab)
            .setContentTitle(m["title"] as String)
            .setContentText(m["text"] as String)
            .setStyle(Notification.BigTextStyle().bigText(m["text"] as String))
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setGroup(GROUP)
            .setCategory(Notification.CATEGORY_STATUS)
            // Amounts and payees stay off the lock screen.
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(
                builder(ctx, ch).setSmallIcon(R.drawable.ic_stat_hisaab)
                    .setContentTitle("Payment captured").setContentText("Unlock to file it").build(),
            )
        // Request codes from 8008 up: clear of the check-in's (10-12), unique per payment and button.
        val code = nid(txn) * 8
        (m["route"] as? String)?.let { b.setContentIntent(open(ctx, it, code)) }
        (m["timeout"] as? Number)?.let { if (Build.VERSION.SDK_INT >= 26) b.setTimeoutAfter(it.toLong()) }
        (m["actions"] as? List<*>).orEmpty().take(3).forEachIndexed { i, raw ->
            val a = raw as Map<*, *>
            val pi = (a["route"] as? String)?.let { open(ctx, it, code + 1 + i) } ?: PendingIntent.getBroadcast(
                ctx, code + 1 + i,
                Intent(ctx, CaptureActionReceiver::class.java)
                    .putExtra("id", txn)
                    .putExtra("cat", a["cat"] as? String)
                    .putExtra("ignore", a["ignore"] == true)
                    .putExtra("undo", a["undo"] == true)
                    .putExtra("rule", a["rule"] as? String),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            b.addAction(Notification.Action.Builder(icon, a["label"] as String, pi).build())
        }
        nm.notify(nid(txn), b.build())
    }

    /** The daily check-in replaces them, so the shade never holds stale prompts. */
    fun clearCaptures(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.activeNotifications.filter { it.notification.group == GROUP }.forEach { nm.cancel(it.id) }
    }
}

/** A capture notification's category, Not an expense or Undo button: filed without opening the app. */
class CaptureActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = mapOf(
            "id" to intent.getIntExtra("id", 0),
            "cat" to intent.getStringExtra("cat"),
            "ignore" to intent.getBooleanExtra("ignore", false),
            "undo" to intent.getBooleanExtra("undo", false),
            "rule" to intent.getStringExtra("rule"),
        )
        Capture.ui?.let {
            it.invokeMethod("action", action)
            return
        }
        val ctx = context.applicationContext
        val pending = goAsync()
        Capture.runHeadless(ctx, "actionMain", { call, result ->
            when (call.method) {
                "pending" -> result.success(action)
                "notifyCapture" -> {
                    Notices.post(ctx, call.arguments as Map<*, *>)
                    result.success(null)
                }
                else -> return@runHeadless false
            }
            true
        }) { pending.finish() }
    }
}
