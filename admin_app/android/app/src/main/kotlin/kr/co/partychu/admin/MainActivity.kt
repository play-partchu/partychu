package kr.co.partychu.admin

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 관리자 앱 — CRM 내보내기(xlsx/csv)를 **기기의 다운로드 폴더**에 저장하는
 * 채널 하나만 더한다. 웹은 브라우저 다운로드를 그대로 쓰므로 이 코드와 무관하다.
 *
 * Dart 쪽: lib/services/file_download_io.dart (채널 이름이 같아야 한다).
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val filename = call.argument<String>("filename")
                val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                if (bytes == null || filename.isNullOrBlank()) {
                    result.error("bad-args", "bytes/filename이 필요합니다.", null)
                    return@setMethodCallHandler
                }
                try {
                    result.success(saveToDownloads(bytes, filename, mimeType))
                } catch (e: Exception) {
                    result.error("save-failed", e.message, null)
                }
            }
    }

    /** 저장한 위치(사람이 읽을 수 있는 경로)를 돌려준다. */
    private fun saveToDownloads(bytes: ByteArray, filename: String, mimeType: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+: MediaStore — 저장소 권한 없이 공용 다운로드 폴더에 쓴다.
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, filename)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("다운로드 폴더에 파일을 만들 수 없습니다.")
            try {
                resolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("파일을 열 수 없습니다.")
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
            return "다운로드/$filename"
        }
        // Android 9 이하: 공용 폴더에 쓰려면 권한이 필요하므로 앱 전용 다운로드
        // 폴더(권한 불필요)에 둔다.
        val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir
        val file = File(dir, filename)
        file.writeBytes(bytes)
        return file.absolutePath
    }

    companion object {
        private const val CHANNEL = "kr.co.partychu.admin/file_download"
    }
}
