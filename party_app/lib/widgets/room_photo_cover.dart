import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:party_app/screens/full_screen_image_viewer.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 장소대여 상세 > 룸 선택 카드 맨 위의 대표 사진.
///
/// 예전에는 카드 왼쪽 56px 썸네일이 전부였고 탭해도 룸 선택만 됐다 — 공간을
/// 사실상 볼 수 없었고, 두 번째 사진부터는 어디에도 나오지 않았다.
///
/// 여기서는 카드 폭을 다 쓰는 16:9 사진(높이는 [maxHeight]까지)을 그리고,
/// 누르면 앱 공용 전체화면 뷰어([FullScreenImageViewer.gallery])를 연다 —
/// 원본 비율·핀치 확대·확대 후 이동·좌우 넘기기·'1 / 4' 표시는 그 뷰어가
/// 이미 갖고 있다. `fullscreenDialog`로 열어 앱바 왼쪽이 닫기(X)가 된다.
///
/// 사진 탭은 **뷰어만** 연다. 룸 선택은 카드의 나머지 영역이 예전 그대로 맡는다.
class RoomPhotoCover extends StatelessWidget {
  /// 룸 문서의 `roomImages` 그대로. 비어 있으면 호출하지 않는다.
  final List<String> images;

  /// 넓은 화면(태블릿·웹 프레임 밖)에서 사진이 카드 정보를 밀어내지 않도록
  /// 높이 상한을 둔다. 모바일 폭(≈270px 안쪽 폭)에서는 16:9가 먼저 걸린다.
  final double maxHeight;

  const RoomPhotoCover({super.key, required this.images, this.maxHeight = 240});

  void _open(BuildContext context) {
    Navigator.push(
      context,
      webFramedRoute<void>(
        (_) => FullScreenImageViewer.gallery(imageUrls: images),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(constraints.maxWidth * 9 / 16, maxHeight);
        return Semantics(
          button: true,
          label: images.length > 1
              ? '룸 사진 ${images.length}장 크게 보기'
              : '룸 사진 크게 보기',
          child: GestureDetector(
            onTap: () => _open(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: double.infinity,
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      images.first,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const ColoredBox(color: Color(0xFFF3EFFA)),
                      errorBuilder: (_, e, st) => const ColoredBox(
                        color: Color(0xFFFFE0EE),
                        child: Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: Colors.black26,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                    // 눌러서 크게 볼 수 있다는 표시.
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _pill(
                        child: const Icon(
                          Icons.zoom_out_map_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        padding: const EdgeInsets.all(6),
                      ),
                    ),
                    if (images.length > 1)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: _pill(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.photo_library_outlined,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${images.length}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _pill({required Widget child, required EdgeInsets padding}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
