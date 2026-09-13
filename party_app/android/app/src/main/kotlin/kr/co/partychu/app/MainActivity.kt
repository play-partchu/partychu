package kr.co.partychu.app

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// ── 왜 FlutterActivity가 아니라 FlutterFragmentActivity인가 ─────────────
// flutter_naver_login 2.1.1은 onAttachedToActivity에서 액티비티를 **검사 없이**
// FlutterFragmentActivity로 캐스팅한다(FlutterNaverLoginPlugin.kt:151).
// FlutterActivity면 ClassCastException이 나는데, GeneratedPluginRegistrant가
// 플러그인마다 catch (Exception)로 감싸고 있어 앱은 죽지 않고 로그 한 줄
// ("Error registering plugin flutter_naver_login")만 남긴다. 그 결과 플러그인이
// 반쯤만 초기화돼 네이버 인증 화면은 뜨지만 로그인이 끝나지 않았다.
// 다시 FlutterActivity로 되돌리면 같은 증상이 조용히 재발한다.
// (구글·카카오 플러그인은 액티비티 타입을 캐스팅하지 않아 영향이 없다.)
//
// ── 캡처 보호 채널 ──────────────────────────────────────────────────────
// 승인제 파티 신청자의 제출 사진처럼 화면에 떠 있는 동안만 캡처를 막아야
// 하는 구간을 위해, Flutter가 FLAG_SECURE를 켜고 끌 수 있게 열어 둔다.
//
// FLAG_SECURE는 창 전체에 걸리므로 앱 시작 때 한 번 걸어 두면 파티 상세나
// 영수증 캡처 같은 정상적인 사용까지 막힌다. 그래서 켜고 끄는 시점은 Dart의
// ScreenCaptureGuard가 정하고, 여기서는 시키는 대로만 한다.
//
// 이 플래그 하나로 스크린샷·화면 녹화가 OS 차원에서 막히고 최근앱 미리보기도
// 비워지므로, Android에는 iOS 쪽의 감지 이벤트에 해당하는 것이 없다 —
// 이벤트 채널은 Dart가 플랫폼을 가리지 않고 붙을 수 있도록 자리만 만들어 둔다.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        logNaverLoginSetup()

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

    /// 네이버 로그인 설정 진단 — **디버그 빌드에서만** 한 번 찍는다.
    ///
    /// 네이버 개발자센터에 등록한 값과 앱이 실제로 들고 있는 값이 어긋나면
    /// 인증 화면까지는 뜨고 마지막에 실패한다. 그 대조에 필요한 것만 남긴다:
    /// 실제 패키지명, 매니페스트 meta-data가 런타임에 풀리는지.
    /// 시크릿은 값을 절대 찍지 않고 존재 여부만 남긴다.
    ///
    /// logcat 필터: adb logcat -s PartychuNaver
    private fun logNaverLoginSetup() {
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debuggable) return
        try {
            @Suppress("DEPRECATION")
            val meta = packageManager
                .getApplicationInfo(packageName, PackageManager.GET_META_DATA)
                .metaData
            val clientId = meta?.getString("com.naver.sdk.clientId")
            val hasSecret = !meta?.getString("com.naver.sdk.clientSecret").isNullOrEmpty()
            val clientName = meta?.getString("com.naver.sdk.clientName")
            Log.i(
                LOG_TAG,
                "packageName=" + packageName +
                    " activity=" + javaClass.name +
                    " clientId=" + (clientId ?: "(없음)") +
                    " clientSecret=" + (if (hasSecret) "있음" else "(없음)") +
                    " clientName=" + (clientName ?: "(없음)")
            )
        } catch (e: Exception) {
            Log.w(LOG_TAG, "네이버 설정 진단 실패", e)
        }
    }

    private companion object {
        const val CHANNEL = "kr.co.partychu.app/screen_capture_guard"
        const val EVENT_CHANNEL = "kr.co.partychu.app/screen_capture_guard/events"
        const val LOG_TAG = "PartychuNaver"
    }
}
