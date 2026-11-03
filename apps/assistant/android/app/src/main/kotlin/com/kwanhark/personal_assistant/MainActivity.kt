package com.kwanhark.personal_assistant

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 금고 모듈의 지문·얼굴 잠금(local_auth)은 FragmentActivity 가 필요하다.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 금고 모듈: 화면 캡처 막기 (금고가 켜 달라고 할 때만)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "account_vault/secure_screen")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val on = call.arguments as? Boolean ?: true
                    runOnUiThread {
                        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
