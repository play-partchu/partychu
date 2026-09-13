package kr.co.partychu.app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// 승인제 파티 신청자의 제출 사진처럼 **화면에 떠 있는 동안만** 캡처를 막아야
// 하는 구간을 위해, Flutter가 `FLAG_SECURE`를 켜고 끌 수 있게 열어 둔다.
//
// `FLAG_SECURE`는 창 전체에 걸리므로 앱 시작 때 한 번 걸어 두면 파티 상세나
// 영수증 캡처 같은 정상적인 사용까지 막힌다. 그래서 켜고 끄는 시점은 Dart의
// `ScreenCaptureGuard`가 정하고, 여기서는 시키는 대로만 한다.
//
// 이 플래그 하나로 스크린샷·화면 녹화가 OS 차원에서 막히고 최근앱 미리보기도
// 비워지므로, Android에는 iOS 쪽의 감지 이벤트에 해당하는 것이 없다 —
// 이벤트 채널은 Dart가 플랫폼을 가리지 않고 붙을 수 있도록 자리만 만들어 둔다.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        // 돌려주는 값은 "지금 화면이 캡처되고 있는가"다.
                        // Android는 OS가 막으므로 가릴 일이 없어 항상 false.
                        result.success(false)
                    }
                    "disable" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) = Unit
                    override fun onCancel(arguments: Any?) = Unit
                }
            )
    }

    private companion object {
        const val CHANNEL = "kr.co.partychu.app/screen_capture_guard"
        const val EVENT_CHANNEL = "kr.co.partychu.app/screen_capture_guard/events"
    }
}
