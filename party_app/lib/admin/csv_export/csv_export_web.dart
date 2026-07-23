import 'dart:convert';
// ignore: deprecated_member_use
import 'dart:html' as html;

/// 브라우저에서 CSV 파일 다운로드를 트리거한다.
/// UTF-8 BOM을 붙여 Excel에서 한글이 깨지지 않도록 처리.
void downloadCsv(String filename, String csvContent) {
  final bytes = utf8.encode('﻿$csvContent');
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
