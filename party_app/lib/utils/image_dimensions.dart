import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// 로컬 이미지 파일의 (width, height)를 추가 패키지 없이 dart:ui로 계산한다.
/// 실패해도 예외를 던지지 않고 null을 반환한다 — 상세페이지 블록은 크기
/// 정보 없이도 기본 비율로 표시할 수 있어야 하므로 이 실패가 저장 자체를
/// 막아서는 안 된다.
Future<(double, double)?> decodeImageDimensions(File file) async {
  try {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = (frame.image.width.toDouble(), frame.image.height.toDouble());
    frame.image.dispose();
    return size;
  } catch (e) {
    debugPrint('[ImageDimensions] 이미지 크기 계산 실패: $e');
    return null;
  }
}
