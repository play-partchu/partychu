import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// 로컬 이미지 파일의 (width, height)를 추가 패키지 없이 dart:ui로 계산한다.
/// 실패해도 예외를 던지지 않고 null을 반환한다 — 상세페이지 블록은 크기
/// 정보 없이도 기본 비율로 표시할 수 있어야 하므로 이 실패가 저장 자체를
/// 막아서는 안 된다.
Future<(double, double)?> decodeImageDimensions(XFile file) async {
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

/// [probeImageFile]의 결과 — 원본 픽셀 크기.
typedef ImageProbe = ({double width, double height});

/// 로컬 이미지 파일이 **정상적으로 디코드되는 파일인지** 확인하면서 원본
/// 픽셀 크기를 읽는다. 읽지 못하면(형식을 모름·깨진 파일·확장자만 이미지)
/// null — 호출부는 null을 "업로드하면 안 되는 파일"로 다룬다.
///
/// [decodeImageDimensions]와 달리 **픽셀을 전부 디코드하지 않는다.**
/// 캔바에서 뽑은 세로 20000px짜리 상세페이지 이미지는 원본 그대로 디코드하면
/// 그 자체로 수십 MB를 잡아 고르는 순간 앱이 죽을 수 있다. 그래서
///   1) 헤더만 읽어 크기를 얻고([ui.ImageDescriptor.encoded]),
///   2) 아주 작은 배율(32px)로 한 번만 디코드해 "실제로 그려지는 파일"인지
///      확인한다.
/// 2단계가 없으면 헤더만 멀쩡한 손상 파일이 업로드된 뒤 상세에서만 깨진다.
Future<ImageProbe?> probeImageFile(XFile file) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    // 웹의 XFile.path는 파일 경로가 아니라 blob URL이라 fromFilePath가 통하지
    // 않는다 — 바이트로 읽어 같은 버퍼를 만든다. 이후 단계(헤더만 읽기 →
    // 32px로 시험 디코드)는 앱과 완전히 같다.
    buffer = kIsWeb
        ? await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes())
        : await ui.ImmutableBuffer.fromFilePath(file.path);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width.toDouble();
    final height = descriptor.height.toDouble();
    if (width <= 0 || height <= 0) return null;

    final codec = await descriptor.instantiateCodec(targetWidth: 32);
    final frame = await codec.getNextFrame();
    frame.image.dispose();
    codec.dispose();

    return (width: width, height: height);
  } catch (e) {
    debugPrint('[ImageDimensions] 이미지 검사 실패: $e');
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}
