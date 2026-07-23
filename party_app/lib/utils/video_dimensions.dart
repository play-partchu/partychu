import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// 로컬 동영상 파일에서 한 번의 초기화로 함께 얻는 정보 — 재생 시간(30초
/// 초과 여부 판단용)과 화면 표시 비율(회전 보정 반영, `media_gallery.dart`의
/// `_GalleryVideoItem._displaySize()`와 동일한 계산 방식).
class VideoLocalInfo {
  final Duration duration;
  final double? aspectRatio;

  const VideoLocalInfo({required this.duration, this.aspectRatio});
}

/// 실패해도 예외를 던지지 않고 null을 반환한다 — 상세페이지 블록은 비율
/// 정보 없이도 기본 비율로 표시할 수 있어야 하므로 이 실패가 저장 자체를
/// 막아서는 안 된다.
Future<VideoLocalInfo?> decodeVideoLocalInfo(File file) async {
  VideoPlayerController? ctrl;
  try {
    ctrl = VideoPlayerController.file(file);
    await ctrl.initialize();
    final raw = ctrl.value.size;
    double? aspectRatio;
    if (raw.width > 0 && raw.height > 0) {
      final rotated =
          ctrl.value.rotationCorrection == 90 || ctrl.value.rotationCorrection == 270;
      final width = rotated ? raw.height : raw.width;
      final height = rotated ? raw.width : raw.height;
      aspectRatio = width / height;
    }
    return VideoLocalInfo(duration: ctrl.value.duration, aspectRatio: aspectRatio);
  } catch (e) {
    debugPrint('[VideoDimensions] 동영상 정보 계산 실패: $e');
    return null;
  } finally {
    await ctrl?.dispose();
  }
}
