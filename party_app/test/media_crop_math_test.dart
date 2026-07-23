import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/utils/video_crop.dart';

/// 기본카드([CroppedMedia]/[videoCropAlignment])가 그리는 최종 위치를,
/// [matrixForCrop]/[cropFromMatrix]와는 독립적으로(Flutter의 Alignment 공식을
/// 직접 다시 풀어서) 계산해 두 값이 항상 일치하는지 확인한다. 편집 화면과
/// 실제 카드가 각자 크롭 공식을 따로 구현하다가 서로 어긋났던 사고가 다시
/// 생기면 이 테스트가 바로 실패해야 한다.
void main() {
  group('CoverGeometry.of', () {
    test('가로 방향이 더 좁은 원본(세로 사진) → 세로에 여유(slack)가 생긴다', () {
      final cover = CoverGeometry.of(
        naturalWidth: 1080,
        naturalHeight: 1920,
        frameWidth: 174,
        frameHeight: 130,
      );
      expect(cover.width, closeTo(174, 0.001)); // 가로는 정확히 프레임에 맞음
      expect(cover.height, greaterThan(130)); // 세로는 남아서 이동 가능
    });

    test('원본이 프레임과 똑같은 비율이면 여유가 전혀 없다(양쪽 다 정확히 일치)', () {
      final cover = CoverGeometry.of(
        naturalWidth: 348,
        naturalHeight: 260,
        frameWidth: 174,
        frameHeight: 130,
      );
      expect(cover.width, closeTo(174, 0.001));
      expect(cover.height, closeTo(130, 0.001));
    });
  });

  group('matrixForCrop / cropFromMatrix 왕복', () {
    const cases = [
      (0.5, 0.5, 1.0), // 중앙, 확대 없음 — 회귀 없음 보장 케이스
      (0.0, 0.0, 1.0), // 좌상단 끝
      (1.0, 1.0, 1.0), // 우하단 끝
      (0.3, 0.8, 1.6), // 임의 위치 + 추가 확대
      (0.9, 0.1, 3.0),
    ];

    for (final (cropX, cropY, cropScale) in cases) {
      test('cropX=$cropX cropY=$cropY cropScale=$cropScale 왕복 시 동일한 값', () {
        final cover = CoverGeometry.of(
          naturalWidth: 1080,
          naturalHeight: 1920,
          frameWidth: 174,
          frameHeight: 130,
        );
        final matrix = matrixForCrop(
          cover: cover,
          frameWidth: 174,
          frameHeight: 130,
          cropX: cropX,
          cropY: cropY,
          cropScale: cropScale,
        );
        final result = cropFromMatrix(
          matrix: matrix,
          cover: cover,
          frameWidth: 174,
          frameHeight: 130,
        );
        expect(result.cropX, closeTo(cropX, 0.001));
        expect(result.cropY, closeTo(cropY, 0.001));
        expect(result.cropScale, closeTo(cropScale, 0.001));
      });
    }
  });

  group('편집 화면 렌더링(matrixForCrop) == 기본카드 렌더링(Alignment 공식) 동등성', () {
    // 기본카드(CroppedMedia/videoCropAlignment)가 실제로 그리는 자식의
    // top-left/크기를, matrixForCrop과는 완전히 독립적으로 다시 계산한다.
    // Flutter의 `Alignment` 공식: 스케일 1일 때
    //   childTopLeft = (frameSize - childSize) * cropFrac
    // 그 위에 Transform.scale(scale, alignment: cropAlignment)를 적용하면
    // (앵커 = frameSize * cropFrac 지점을 고정한 채 확대):
    //   newTopLeft = anchor + scale * (baseTopLeft - anchor)
    //   newSize    = scale * childSize
    ({double topLeftX, double topLeftY, double width, double height})
    cardRenderedRect({
      required double naturalW,
      required double naturalH,
      required double frameW,
      required double frameH,
      required double cropX,
      required double cropY,
      required double cropScale,
    }) {
      final coverScale = [
        frameW / naturalW,
        frameH / naturalH,
      ].reduce((a, b) => a > b ? a : b);
      final childW = naturalW * coverScale;
      final childH = naturalH * coverScale;
      final baseTopLeftX = (frameW - childW) * cropX;
      final baseTopLeftY = (frameH - childH) * cropY;
      final anchorX = frameW * cropX;
      final anchorY = frameH * cropY;
      final s = cropScale < 1.0 ? 1.0 : cropScale;
      return (
        topLeftX: anchorX + s * (baseTopLeftX - anchorX),
        topLeftY: anchorY + s * (baseTopLeftY - anchorY),
        width: s * childW,
        height: s * childH,
      );
    }

    // 편집 화면(matrixForCrop)이 실제로 그리는 자식의 top-left/크기를
    // TransformationController에 들어갈 Matrix4에서 직접 읽어낸다.
    ({double topLeftX, double topLeftY, double width, double height})
    editorRenderedRect({
      required double naturalW,
      required double naturalH,
      required double frameW,
      required double frameH,
      required double cropX,
      required double cropY,
      required double cropScale,
    }) {
      final cover = CoverGeometry.of(
        naturalWidth: naturalW,
        naturalHeight: naturalH,
        frameWidth: frameW,
        frameHeight: frameH,
      );
      final matrix = matrixForCrop(
        cover: cover,
        frameWidth: frameW,
        frameHeight: frameH,
        cropX: cropX,
        cropY: cropY,
        cropScale: cropScale,
      );
      final s = matrix.getMaxScaleOnAxis();
      final t = matrix.getTranslation();
      return (
        topLeftX: t.x,
        topLeftY: t.y,
        width: s * cover.width,
        height: s * cover.height,
      );
    }

    const scenarios = [
      // (naturalW, naturalH, frameW, frameH, cropX, cropY, cropScale)
      (1080.0, 1920.0, 174.0, 130.0, 0.5, 0.5, 1.0), // 세로 사진, 중앙
      (1080.0, 1920.0, 174.0, 130.0, 0.0, 0.0, 1.0), // 세로 사진, 맨 위
      (1080.0, 1920.0, 174.0, 130.0, 0.5, 1.0, 1.0), // 세로 사진, 맨 아래
      (1920.0, 1080.0, 174.0, 130.0, 0.5, 0.5, 1.0), // 가로 사진, 중앙
      (1920.0, 1080.0, 174.0, 130.0, 1.0, 0.5, 2.0), // 가로 사진, 오른쪽 끝 + 확대
      // 편집 화면 프레임을 실제 카드보다 크게 보여주는 경우(_cardFrameSize
      // 처럼 비율만 같고 절대 크기가 다른 상황)도 동일해야 한다.
      (1080.0, 1920.0, 348.0, 260.0, 0.2, 0.7, 1.4),
    ];

    for (final s in scenarios) {
      final (naturalW, naturalH, frameW, frameH, cropX, cropY, cropScale) = s;
      test(
        'natural=${naturalW}x$naturalH frame=${frameW}x$frameH '
        'crop=($cropX,$cropY,$cropScale)',
        () {
          final card = cardRenderedRect(
            naturalW: naturalW,
            naturalH: naturalH,
            frameW: frameW,
            frameH: frameH,
            cropX: cropX,
            cropY: cropY,
            cropScale: cropScale,
          );
          final editor = editorRenderedRect(
            naturalW: naturalW,
            naturalH: naturalH,
            frameW: frameW,
            frameH: frameH,
            cropX: cropX,
            cropY: cropY,
            cropScale: cropScale,
          );
          expect(editor.topLeftX, closeTo(card.topLeftX, 0.01));
          expect(editor.topLeftY, closeTo(card.topLeftY, 0.01));
          expect(editor.width, closeTo(card.width, 0.01));
          expect(editor.height, closeTo(card.height, 0.01));
        },
      );
    }
  });

  group('videoCropAlignment', () {
    test('0.5/0.5는 정확히 중앙(Alignment.center)과 같다', () {
      expect(videoCropAlignment(0.5, 0.5), Alignment.center);
    });
    test('0/0은 좌상단, 1/1은 우하단', () {
      expect(videoCropAlignment(0, 0), Alignment.topLeft);
      expect(videoCropAlignment(1, 1), Alignment.bottomRight);
    });
  });
}
