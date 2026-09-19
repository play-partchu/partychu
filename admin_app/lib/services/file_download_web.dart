// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

// 웹 — 예전 CrmExportService 안에 있던 코드를 그대로 옮겼다(동작 변화 없음).

/// 바이트를 브라우저 다운로드로 저장한다.
Future<void> saveBytesAsFile(List<int> bytes, String filename, String mimeType) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
  anchor.remove();
}

/// 새 탭으로 연다.
void openUrlInNewWindow(String url) => html.window.open(url, '_blank');
