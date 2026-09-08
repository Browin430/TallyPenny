package dev.flowmoney.flowmoney

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var widgetChannel: MethodChannel
    private var pendingOpenVoice = false

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingOpenVoice = intent?.action == ACTION_OPEN_VOICE
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WIDGET_CHANNEL,
        )
        widgetChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeInitialVoiceRequest" -> {
                    result.success(pendingOpenVoice)
                    pendingOpenVoice = false
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action != ACTION_OPEN_VOICE) return
        if (::widgetChannel.isInitialized) {
            widgetChannel.invokeMethod("openVoice", null)
        } else {
            pendingOpenVoice = true
        }
    }

    companion object {
        const val ACTION_OPEN_VOICE = "dev.flowmoney.flowmoney.OPEN_VOICE"
        private const val WIDGET_CHANNEL = "dev.flowmoney.flowmoney/widget"
    }
}
