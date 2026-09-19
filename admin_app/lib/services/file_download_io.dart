import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

// Android — 채널 이름은 android/.../MainActivity.kt의 CHANNEL과 같아야 한다.
const _channel = MethodChannel('kr.co.partychu.admin/file_download');

/// 바이트를 기기의 다운로드 폴더에 저장한다(Android 10+는 권한 없이 공용
/// 다운로드 폴더, 9 이하는 앱 전용 다운로드 폴더).
Future<void> saveBytesAsFile(List<int> bytes, String filename, String mimeType) async {
  await _channel.invokeMethod<String>('saveToDownloads', {
    'bytes': Uint8List.fromList(bytes),
    'filename': filename,
    'mimeType': mimeType,
  });
}

/// 설치된 브라우저(사용자가 고른 기본 브라우저)로 연다 — 특정 브라우저를 지정하지
/// 않고, 앱 안의 Custom Tab도 쓰지 않는다.
void openUrlInNewWindow(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
}
