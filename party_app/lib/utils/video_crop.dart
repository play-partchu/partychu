import 'dart:math' as math;

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 동영상 대표 카드 노출 위치(크롭) 공용 유틸
//
// cropX/cropY(0.0~1.0, 초점 위치 — 0.5/0.5가 중앙)와 cropScale(1.0 이상,
// cover 기준 추가 확대 배율)을 받아 카드 미디어 영역에 적용한다.
//
// 구현 방식: 자식 위젯은 반드시 BoxFit.cover이면서 alignment도
// videoCropAlignment(cropX, cropY)로 맞춰 박스를 꽉 채운 상태로 넘겨야
// 한다(자식이 그 자체로 이미 올바른 위치에 크롭돼 있어야 함 — 예:
// `Image.network(url, fit: BoxFit.cover, alignment: videoCropAlignment(x, y))`).
// 이 위젯은 그 위에 같은 cropAlignment를 중심으로 한 Transform.scale만
// "추가 확대(cropScale > 1.0)"용으로 덧붙인다.
//
// ⚠️ 자식의 alignment를 Alignment.center로 고정해버리면 cropScale == 1.0일
// 때 Transform.scale이 항등변환이라 cropX/cropY가 아무 시각적 효과도 내지
// 못하는 회귀가 생긴다(과거 버그) — 반드시 자식 쪽 alignment부터 맞출 것.
// cropScale == 1.0이고 cropX/cropY == 0.5/0.5(중앙)이면 항상 기존
// "BoxFit.cover 중앙 정렬"과 픽셀 단위로 완전히 동일하다 — 크롭 값이 없는
// 기존 데이터의 회귀를 원천적으로 막아준다.
// ─────────────────────────────────────────────────────────────────────────────

/// cropX/cropY(0.0~1.0)를 Transform.scale이 요구하는 Alignment(-1.0~1.0)로 변환.
Alignment videoCropAlignment(double cropX, double cropY) =>
    Alignment(cropX * 2 - 1, cropY * 2 - 1);

/// [child]는 이미 대상 박스를 BoxFit.cover(중앙 정렬)로 꽉 채운 상태여야 한다.
/// (예: `Image.network(url, fit: BoxFit.cover)` 또는
/// `FittedBox(fit: BoxFit.cover, child: SizedBox(width:.., height:.., child: VideoPlayer(c)))`)
class CroppedMedia extends StatelessWidget {
  final double cropX;
  final double cropY;
  final double cropScale;
  final Widget child;

  const CroppedMedia({
    super.key,
    required this.cropX,
    required this.cropY,
    required this.cropScale,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scale = cropScale < 1.0 ? 1.0 : cropScale;
    if (scale == 1.0) return child; // 기존 렌더링과 완전히 동일 — 회귀 없음 보장
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: videoCropAlignment(cropX, cropY),
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 크롭 편집 화면(PhotoCropScreen/VideoCropScreen) 전용 공용 계산 — 편집 화면과
// 위 [CroppedMedia](최종 카드 렌더링)가 "같은 위치"를 만들어내도록 반드시 이
// 함수들만 거쳐서 계산한다. 편집 화면·카드가 각자 따로 크롭 공식을 다시
// 구현하다가 어긋나는 사고(과거 실제로 발생)를 막기 위한 단일 소스.
//
// 수학적 등가성: [CroppedMedia]는 "자식을 BoxFit.cover + alignment(cropX,cropY)
// 로 이미 위치시킨 상태에서, 같은 alignment를 중심으로 Transform.scale(cropScale)"
// 을 적용한다. 이는 "원본을 coverScale로 확대한 뒤(coverW×coverH), 그중
// (cropX,cropY) 지점이 프레임의 (cropX,cropY) 위치에 오도록 배치하고, 전체를
// cropScale배 추가 확대"하는 것과 정확히 같은 결과를 낸다(Flutter의
// `Alignment` 공식 `childTopLeft = (frameSize - childSize) * cropFrac`을
// Transform.scale의 anchor 변환에 대입해 유도됨). [matrixForCrop]/[cropFromMatrix]
// 는 이 등가 공식을 InteractiveViewer가 쓰는 Matrix4로 그대로 구현한 것이다.
// ─────────────────────────────────────────────────────────────────────────────

/// 원본(naturalWidth×naturalHeight)을 프레임(frameWidth×frameHeight)에
/// 여백 없이 꽉 채우는(BoxFit.cover) 배율과, 그 배율로 확대했을 때의 크기.
/// Flutter의 `Image(fit: BoxFit.cover)`/`FittedBox(fit: BoxFit.cover)`가
/// 내부적으로 쓰는 것과 동일한 공식(`max(frameW/naturalW, frameH/naturalH)`).
class CoverGeometry {
  final double scale;
  final double width;
  final double height;

  const CoverGeometry({
    required this.scale,
    required this.width,
    required this.height,
  });

  factory CoverGeometry.of({
    required double naturalWidth,
    required double naturalHeight,
    required double frameWidth,
    required double frameHeight,
  }) {
    final scale = math.max(
      frameWidth / naturalWidth,
      frameHeight / naturalHeight,
    );
    return CoverGeometry(
      scale: scale,
      width: naturalWidth * scale,
      height: naturalHeight * scale,
    );
  }
}

/// cropX/cropY(0~1)와 cropScale(1.0 이상, cover 기준 추가 확대)을 InteractiveViewer의
/// TransformationController에 넣을 [Matrix4]로 변환한다 — [CroppedMedia]와
/// 수학적으로 동일한 위치를 만들어낸다(이 파일 상단 설명 참고).
///
/// ⚠️ 이 매트릭스를 쓰는 `InteractiveViewer`는 반드시 `constrained: false`로
/// 설정해야 한다. 기본값(`true`)이면 자식이 뷰포트 크기로 강제로 clamp되어
/// [cover]가 계산한 실제 크기(coverW×coverH)로 렌더링되지 않고, 여기서 계산한
/// tx/ty가 완전히 무의미해진다 — 편집 화면에서 맞춘 위치와 실제 카드가 서로
/// 달랐던 실제 원인이 이것이었다.
Matrix4 matrixForCrop({
  required CoverGeometry cover,
  required double frameWidth,
  required double frameHeight,
  required double cropX,
  required double cropY,
  required double cropScale,
}) {
  final s = cropScale < 1.0 ? 1.0 : cropScale;
  final tx = cropX * (frameWidth - s * cover.width);
  final ty = cropY * (frameHeight - s * cover.height);
  return Matrix4.identity()
    ..setEntry(0, 0, s)
    ..setEntry(1, 1, s)
    ..setEntry(0, 3, tx)
    ..setEntry(1, 3, ty);
}

/// [matrixForCrop]의 역함수 — InteractiveViewer의 최종 TransformationController
/// 값을 다시 cropX/cropY/cropScale로 되돌린다.
CropValue cropFromMatrix({
  required Matrix4 matrix,
  required CoverGeometry cover,
  required double frameWidth,
  required double frameHeight,
}) {
  final s = matrix.getMaxScaleOnAxis();
  final translation = matrix.getTranslation();
  final denomX = frameWidth - s * cover.width;
  final denomY = frameHeight - s * cover.height;
  final cropX = denomX.abs() < 0.01 ? 0.5 : translation.x / denomX;
  final cropY = denomY.abs() < 0.01 ? 0.5 : translation.y / denomY;
  return CropValue(
    cropX: cropX.clamp(0.0, 1.0),
    cropY: cropY.clamp(0.0, 1.0),
    cropScale: s.clamp(1.0, 5.0),
  );
}

/// [matrixForCrop]/[cropFromMatrix]가 주고받는 정규화된 크롭 값 — 저장 필드와
/// 1:1로 대응한다(cropX/cropY: 0.0~1.0 초점 위치, cropScale: 1.0 이상 추가 확대).
class CropValue {
  final double cropX;
  final double cropY;
  final double cropScale;

  const CropValue({
    required this.cropX,
    required this.cropY,
    required this.cropScale,
  });
}
