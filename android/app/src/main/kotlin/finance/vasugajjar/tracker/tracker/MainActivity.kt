package finance.vasugajjar.tracker.tracker

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var saveResult: MethodChannel.Result? = null
    private var saveBytes: ByteArray? = null
    private var openResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, Capture.CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(granted(perms(call.arguments as? String)))
                "requestPermission" -> {
                    val want = perms(call.arguments as? String)
                    if (granted(want)) {
                        result.success(true)
                    } else {
                        permissionResult?.success(false)
                        permissionResult = result
                        lastAsked = want
                        requestPermissions(want, REQUEST_PERMISSION)
                    }
                }
                "capture" -> {
                    Capture.setOn(this, call.arguments<Boolean>() == true)
                    result.success(null)
                }
                "reminder" -> {
                    Reminder.set(this, call.argument<Boolean>("on")!!, call.argument<Int>("hour")!!, call.argument<Int>("minute")!!)
                    result.success(null)
                }
                "notifyCapture" -> {
                    Notices.post(this, call.arguments as Map<*, *>)
                    result.success(null)
                }
                "launchRoute" -> {
                    result.success(intent?.getStringExtra("route"))
                    intent?.removeExtra("route")
                }
                "saveFile" -> {
                    saveResult?.success(false)
                    saveResult = result
                    saveBytes = call.argument<ByteArray>("bytes")
                    startActivityForResult(
                        Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(call.argument<String>("type") ?: "text/csv")
                            .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name")),
                        REQUEST_SAVE,
                    )
                }
                "openFile" -> {
                    openResult?.success(null)
                    openResult = result
                    startActivityForResult(
                        Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*"),
                        REQUEST_OPEN,
                    )
                }
                "inbox" -> {
                    val since = call.argument<Number>("since")!!.toLong()
                    thread {
                        val rows = runCatching { readInbox(since) }
                        runOnUiThread {
                            rows.fold({ result.success(it) }, { result.error("inbox", it.message, null) })
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        Capture.ui = channel
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        Capture.ui = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** A notification action tapped while the app is open. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra("route")?.let { Capture.ui?.invokeMethod("route", it) }
    }

    /** "sms", or "notifications" (a runtime permission from Android 13). */
    private fun perms(kind: String?): Array<String> = when {
        kind == "notifications" && Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.POST_NOTIFICATIONS)
        kind == "notifications" -> emptyArray()
        else -> arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS)
    }

    private var lastAsked: Array<String> = emptyArray()

    private fun granted(p: Array<String>) = p.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_PERMISSION) return
        permissionResult?.success(granted(lastAsked))
        permissionResult = null
    }

    @Deprecated("Activity result API needs androidx; this activity doesn't use it")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val uri = data?.data?.takeIf { resultCode == RESULT_OK }
        when (requestCode) {
            REQUEST_SAVE -> {
                val result = saveResult ?: return
                val bytes = saveBytes
                saveResult = null
                saveBytes = null
                if (uri == null || bytes == null) return result.success(false)
                thread {
                    val ok = runCatching {
                        contentResolver.openOutputStream(uri, "wt")!!.use { it.write(bytes) }
                    }.isSuccess
                    runOnUiThread { result.success(ok) }
                }
            }
            REQUEST_OPEN -> {
                val result = openResult ?: return
                openResult = null
                if (uri == null) return result.success(null)
                thread {
                    val bytes = runCatching { contentResolver.openInputStream(uri)!!.use { it.readBytes() } }
                    runOnUiThread { bytes.fold({ result.success(it) }, { result.error("openFile", it.message, null) }) }
                }
            }
        }
    }

    /**
     * Inbox SMS received from [since] on that mention an amount, oldest
     * first. The app keeps the ones naming a bank.
     */
    private fun readInbox(since: Long): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            "${Telephony.Sms.DATE} >= ?",
            arrayOf(since.toString()),
            "${Telephony.Sms.DATE} ASC",
        )?.use { c ->
            while (c.moveToNext()) {
                val from = c.getString(0) ?: continue
                val body = c.getString(1) ?: continue
                if (Capture.mentionsMoney(body)) out += mapOf("sender" to from, "body" to body, "at" to c.getLong(2))
            }
        }
        return out
    }

    companion object {
        private const val REQUEST_PERMISSION = 7
        private const val REQUEST_SAVE = 8
        private const val REQUEST_OPEN = 9
    }
}
