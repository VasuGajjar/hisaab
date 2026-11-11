package finance.vasugajjar.tracker.tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** State shared by the activity and the SMS receiver. */
object Capture {
    const val CHANNEL = "hisaab/capture"
    private const val PREFS = "capture"

    /** The running app's channel; null when no UI engine is up. */
    var ui: MethodChannel? = null

    /**
     * Mentions an amount: "Rs.450", "INR 450", "₹450", "debited by 450". A cheap
     * first pass so personal texts don't start Dart; the app decides which are
     * bank payments (sms.dart: bankOf, parseSms).
     */
    private val money = Regex("(?i)(rs\\.?|inr|₹)\\s*\\d|(debited|credited)\\s+(by|for|with)\\s+\\d")

    fun mentionsMoney(body: String) = money.containsMatchIn(body)

    /** Whether the app wants SMS: off before onboarding and with SMS off in the app. */
    fun on(ctx: Context): Boolean = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("on", false)

    fun setOn(ctx: Context, on: Boolean) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("on", on).apply()

    /**
     * Starts Dart's [entry] with no UI and shuts it down when it calls "done".
     * [handle] answers its other calls (returns false for ones it doesn't know).
     * A receiver gets ~10 s, so it's stopped after 9 regardless.
     */
    fun runHeadless(ctx: Context, entry: String, handle: (MethodCall, MethodChannel.Result) -> Boolean, finish: () -> Unit) {
        val main = Handler(Looper.getMainLooper())
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(ctx)
        loader.ensureInitializationCompleteAsync(ctx, null, main) {
            val engine = FlutterEngine(ctx)
            var ended = false
            val end = Runnable {
                if (!ended) {
                    ended = true
                    engine.destroy()
                    finish()
                }
            }
            main.postDelayed(end, 9_000)
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
                if (call.method == "done") {
                    result.success(null)
                    main.post(end)
                } else if (!handle(call, result)) {
                    result.notImplemented()
                }
            }
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), entry))
        }
    }
}

/**
 * SMS as they arrive. Ones with no amount in them are dropped here; the rest
 * go to the app, which keeps only those naming a bank (in the sender ID or the
 * text) and reading as a payment. With the app running the SMS goes to it;
 * else a UI-less engine runs Dart's captureMain() to file it, then shuts down.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION || !Capture.on(context)) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        val sender = parts.firstOrNull()?.originatingAddress ?: return
        val body = parts.joinToString("") { it.messageBody ?: "" }
        if (!Capture.mentionsMoney(body)) return
        val sms = mapOf(
            "sender" to sender,
            "body" to body,
            // Receive time, as the inbox's date column has it, so a later inbox read matches.
            "at" to System.currentTimeMillis(),
        )
        Capture.ui?.let {
            it.invokeMethod("sms", sms)
            return
        }
        // A miss isn't lost: the app reads the inbox again on launch.
        val pending = goAsync()
        val ctx = context.applicationContext
        Capture.runHeadless(ctx, "captureMain", { call, result ->
            when (call.method) {
                "pending" -> result.success(sms)
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
