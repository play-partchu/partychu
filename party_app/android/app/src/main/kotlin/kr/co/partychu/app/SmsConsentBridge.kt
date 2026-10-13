package kr.co.partychu.app

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.util.Log
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * SMS User Consent API 브리지 — NICE 인증번호 문자 **1건**을 사용자 동의로 받는다.
 *
 * ── 왜 이 API인가 ────────────────────────────────────────────────────────
 * 본인확인은 NICE 표준창을 WebView로 띄우는 구조라, 인증번호 입력칸이 우리
 * 앱에 없다. 그래서 Flutter 자동완성(`AutofillHints.oneTimeCode`)을 붙일
 * 대상이 없다.
 *
 * SMS Retriever API는 **쓸 수 없다** — 문자 본문에 앱 고유 11자 해시가
 * 들어 있어야 매칭되는데, 그 문자는 NICE/통신사가 보내므로 우리 해시가
 * 들어갈 수 없다.
 *
 * SMS User Consent API는 해시도, `READ_SMS` 권한도 요구하지 않는다. 대신
 * **시스템이 사용자에게 동의 다이얼로그를 띄우고**, 사용자가 허용한 문자
 * 1건만 앱에 전달한다. 사용자가 거부하면 아무것도 오지 않는다.
 *
 * ── 무엇을 하지 않는가 ──────────────────────────────────────────────────
 * ⚠️ **문자 본문과 인증번호를 로그에 남기지 않는다.** 아래 [Log] 호출은
 *    모두 실패 사유만 남긴다 — 본문이 섞일 수 있는 경로가 없다.
 *
 * ⚠️ 받은 문자를 WebView에 주입하지 않는다. Dart로 넘기면 거기서
 *    인증번호만 뽑아 "복사" 버튼으로 보여 주고, 실제 입력은 사용자가 한다
 *    (`SmsConsentService` · `SmsCodeCopyBanner`). NICE 인증 페이지의 DOM과
 *    인증 로직에는 손대지 않는다.
 *
 * ── 수명 ────────────────────────────────────────────────────────────────
 * `start`는 약 5분짜리 수신 창을 연다. 본인확인 화면이 페이지를 넘길 때마다
 * 다시 불러 창을 갱신하고, 화면을 닫을 때 `stop`으로 리시버를 떼고 상태를
 * 비운다.
 */
class SmsConsentBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(this)
    }

    private var receiver: BroadcastReceiver? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                start()
                result.success(true)
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── 수신 창 열기 ────────────────────────────────────────────────────

    private fun start() {
        registerReceiver()
        // null = 발신번호를 가리지 않는다. 통신사·NICE의 발신번호가 고정이
        // 아니어서 특정 번호로 묶으면 문자를 놓친다.
        SmsRetriever.getClient(activity)
            .startSmsUserConsent(null)
            .addOnFailureListener { e ->
                // 사유만 남긴다 — 문자 본문은 이 시점에 존재하지도 않는다.
                Log.w(TAG, "SMS 동의 수신 요청 실패: ${e.javaClass.simpleName}")
                notifyUnavailable("start-failed")
            }
    }

    private fun stop() {
        receiver?.let {
            try {
                activity.unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // 이미 떼어진 경우 — 정상이다.
            }
        }
        receiver = null
    }

    fun dispose() {
        stop()
        channel.setMethodCallHandler(null)
    }

    private fun registerReceiver() {
        stop()
        val created = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != SmsRetriever.SMS_RETRIEVED_ACTION) return
                handleRetrieved(intent.extras)
            }
        }
        val filter = IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION)
        // 브로드캐스트는 Play 서비스(다른 앱)가 보내므로 Android 13+에서는
        // RECEIVER_EXPORTED를 명시해야 한다. SEND_PERMISSION으로 발신자를
        // Play 서비스로 제한하므로 임의 앱이 가짜 문자를 밀어 넣을 수는 없다.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(
                created,
                filter,
                SmsRetriever.SEND_PERMISSION,
                null,
                Context.RECEIVER_EXPORTED,
            )
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            activity.registerReceiver(created, filter, SmsRetriever.SEND_PERMISSION, null)
        }
        receiver = created
    }

    private fun handleRetrieved(extras: Bundle?) {
        if (extras == null) {
            notifyUnavailable("no-extras")
            return
        }
        val status = parcelable(extras, SmsRetriever.EXTRA_STATUS, Status::class.java)
        when (status?.statusCode) {
            CommonStatusCodes.SUCCESS -> {
                val consent =
                    parcelable(extras, SmsRetriever.EXTRA_CONSENT_INTENT, Intent::class.java)
                if (consent == null) {
                    notifyUnavailable("no-consent-intent")
                    return
                }
                try {
                    // 시스템 동의 다이얼로그. 사용자가 허용하면 onActivityResult로
                    // 문자 1건이 돌아온다.
                    activity.startActivityForResult(consent, REQUEST_CODE)
                } catch (e: Exception) {
                    Log.w(TAG, "동의 화면 실행 실패: ${e.javaClass.simpleName}")
                    notifyUnavailable("consent-start-failed")
                }
            }
            CommonStatusCodes.TIMEOUT -> notifyUnavailable("timeout")
            else -> notifyUnavailable("status-${status?.statusCode ?: -1}")
        }
    }

    // ── 동의 결과 ───────────────────────────────────────────────────────

    /** MainActivity가 넘겨 준다. 우리 요청이면 true. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        if (resultCode != Activity.RESULT_OK || data == null) {
            // 사용자가 거부했거나 닫았다 — 수동 입력 흐름 그대로 간다.
            notifyUnavailable("declined")
            return true
        }
        val message = data.getStringExtra(SmsRetriever.EXTRA_SMS_MESSAGE)
        if (message.isNullOrBlank()) {
            notifyUnavailable("empty-message")
            return true
        }
        // ⚠️ 여기서 message를 로그에 찍지 않는다. 인증번호가 들어 있다.
        channel.invokeMethod("onSmsReceived", message)
        return true
    }

    private fun notifyUnavailable(reason: String) {
        channel.invokeMethod("onUnavailable", reason)
    }

    private fun <T> parcelable(extras: Bundle, key: String, type: Class<T>): T? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            extras.getParcelable(key, type)
        } else {
            @Suppress("DEPRECATION")
            type.cast(extras.getParcelable<android.os.Parcelable>(key))
        }

    private companion object {
        const val CHANNEL = "kr.co.partychu.app/sms_consent"
        const val TAG = "PartychuSmsConsent"

        /** 다른 플러그인의 요청 코드와 겹치지 않도록 고른 값. */
        const val REQUEST_CODE = 0x5C01
    }
}
