package finance.vasugajjar.tracker.tracker

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import java.util.Calendar

/**
 * The daily check-in: an inexact alarm (±10 min window, so no exact-alarm
 * permission) that runs Dart's reminderMain() to word the notification.
 */
object Reminder {
    private const val PREFS = "reminder"
    private const val CHANNEL = "reminder"
    private const val ID = 1

    /** Saves the time the app set ([on] false cancels) and schedules the next one. */
    fun set(ctx: Context, on: Boolean, hour: Int, minute: Int) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("on", on).putInt("hour", hour).putInt("minute", minute).apply()
        schedule(ctx)
    }

    fun schedule(ctx: Context) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val am = ctx.getSystemService(AlarmManager::class.java)
        val alarm = PendingIntent.getBroadcast(
            ctx, 0, Intent(ctx, ReminderReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        am.cancel(alarm)
        if (!p.getBoolean("on", false)) return
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, p.getInt("hour", 21))
            set(Calendar.MINUTE, p.getInt("minute", 30))
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis() + 60_000) add(Calendar.DAY_OF_YEAR, 1)
        }
        am.setWindow(AlarmManager.RTC_WAKEUP, next.timeInMillis, 10 * 60_000L, alarm)
    }

    /** Opens the app at [route] ("review", "add" or none). */
    private fun open(ctx: Context, route: String?, code: Int) = PendingIntent.getActivity(
        ctx, code,
        Intent(ctx, MainActivity::class.java)
            .putExtra("route", route)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** Posts what reminderMain() worded: [m] holds pending, title, text, lines, summary. */
    fun post(ctx: Context, m: Map<*, *>) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        val b = if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Daily check-in", NotificationManager.IMPORTANCE_DEFAULT))
            Notification.Builder(ctx, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }
        val pending = m["pending"] == true
        val lines = (m["lines"] as? List<*>).orEmpty().map { it.toString() }
        val icon = Icon.createWithResource(ctx, R.drawable.ic_stat_hisaab)
        b.setSmallIcon(R.drawable.ic_stat_hisaab)
            .setContentTitle(m["title"] as String)
            .setContentText(m["text"] as String)
            .setAutoCancel(true)
            .setContentIntent(open(ctx, if (pending) "review" else null, 10))
        if (lines.isEmpty()) {
            b.setStyle(Notification.BigTextStyle().bigText(m["text"] as String))
        } else {
            b.setStyle(Notification.InboxStyle().also { s ->
                lines.forEach { s.addLine(it) }
                s.setSummaryText(m["summary"] as String)
            })
        }
        if (pending) b.addAction(Notification.Action.Builder(icon, "Review now", open(ctx, "review", 11)).build())
        b.addAction(Notification.Action.Builder(icon, if (pending) "Add cash" else "Add cash spend", open(ctx, "add", 12)).build())
        Notices.clearCaptures(ctx) // folded into this one
        nm.notify(ID, b.build())
    }
}

/** The alarm, plus boot and app update, which clear alarms. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val ctx = context.applicationContext
        Reminder.schedule(ctx) // tomorrow's, or today's again after a reboot
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) return
        val pending = goAsync()
        Capture.runHeadless(ctx, "reminderMain", { call, result ->
            (call.method == "notify").also {
                if (it) {
                    Reminder.post(ctx, call.arguments as Map<*, *>)
                    result.success(null)
                }
            }
        }) { pending.finish() }
    }
}
