import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import 'package:party_app/models/party_detail_image.dart';
import 'package:party_app/utils/local_media.dart';

/// 파티 상세 본문의 **세로형 상세 이미지**를 그린다.
///
/// 규칙은 하나다 — **가로폭에 맞추고, 세로는 원본 비율대로 길어진다.**
/// 고정 높이로 자르지 않고 BoxFit.cover로 잘라먹지도 않는다. 그래서 이
/// 위젯이 만드는 높이는 이미지 비율에 따라 화면 몇 개 분량이 될 수 있고,
/// 상세 스크롤이 그만큼 길어지는 것이 의도된 동작이다.
///
/// ── 메모리 ────────────────────────────────────────────────────────────
/// 초장문 이미지를 원본 해상도로 디코드하면 저사양 기기에서 그대로 OOM이다.
/// [PartyDetailImage.decodeWidthFor]가 화면 폭과 총 픽셀 상한을 함께 적용해
/// cacheWidth를 계산하고, 그 값으로만 디코드한다(줄이기만 하므로 원본이 더
/// 작으면 아무 일도 일어나지 않는다). 텍스트 가독성을 위해 화면 폭 자체는
/// 물리 픽셀 그대로 쓴다 — 화면 폭보다 더 줄이는 것은 총 픽셀 상한에 걸릴
/// 때뿐이다.
class PartyDetailImageView extends StatelessWidget {
  /// 이미 업로드된 이미지(상세 화면·수정 화면 복원).
  final PartyDetailImage? image;

  /// 아직 업로드하지 않은 로컬 파일(등록 화면 미리보기). 있으면 이쪽을 그린다.
  final XFile? localFile;

  /// [localFile]의 원본 픽셀 크기 — 자리를 미리 잡고 디코드 폭을 계산한다.
  final double? localWidth;
  final double? localHeight;

  /// 부모의 좌우 여백을 무시하고 **화면 가로폭 전체**로 그릴지.
  ///
  /// 파티 상세 본문은 `Padding(all(20))` 안에 있는데, 상세 이미지는 상단
  /// 갤러리처럼 화면 끝까지 닿아야 "상세페이지 이미지"로 보인다. 음수 여백은
  /// Flutter가 허용하지 않으므로, 높이를 직접 계산한 [SizedBox] 안에서
  /// [OverflowBox]로 폭만 화면 전체로 되돌린다. 원본 크기를 모르면 높이를
  /// 계산할 수 없으므로 이 옵션은 조용히 무시되고 본문 폭 그대로 그린다.
  final bool fullBleed;

  /// [fullBleed]일 때 무시할 부모의 좌우 여백 합(예: all(20)이면 40).
  final double horizontalPadding;

  const PartyDetailImageView({
    super.key,
    this.image,
    this.localFile,
    this.localWidth,
    this.localHeight,
    this.fullBleed = false,
    this.horizontalPadding = 0,
  });

  double? get _sourceWidth => localFile != null ? localWidth : image?.width;
  double? get _sourceHeight => localFile != null ? localHeight : image?.height;

  double? get _aspectRatio {
    final w = _sourceWidth;
    final h = _sourceHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  @override
  Widget build(BuildContext context) {
    final file = localFile;
    final url = image?.url;
    if (file == null && (url == null || url.isEmpty)) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final contentWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : media.size.width;
        final aspect = _aspectRatio;

        // 화면 끝까지 넓힐지 — 높이를 직접 계산할 수 있을 때만 가능하다.
        final bleed = fullBleed && aspect != null && horizontalPadding > 0;
        final drawWidth = bleed
            ? contentWidth + horizontalPadding
            : contentWidth;

        final decodeWidth = PartyDetailImage.decodeWidthFor(
          viewWidth: drawWidth,
          devicePixelRatio: media.devicePixelRatio,
          imageWidth: _sourceWidth,
          imageHeight: _sourceHeight,
        );

        // BoxFit.contain — 저장된 크기가 원본과 미세하게 어긋나 있어도 절대
        // 잘리지 않게 한다("전체가 처음부터 끝까지 보여야 한다"가 이 기능의
        // 요구사항이다). 비율이 정확히 맞으면 fill과 결과가 같다.
        Widget picture = file != null
            ? LocalMedia.image(
                file,
                width: double.infinity,
                fit: aspect != null ? BoxFit.contain : BoxFit.fitWidth,
                cacheWidth: decodeWidth,
                errorBuilder: (context, error, stackTrace) =>
                    _error('이미지를 불러올 수 없어요'),
              )
            : Image.network(
                url!,
                width: double.infinity,
                fit: aspect != null ? BoxFit.contain : BoxFit.fitWidth,
                cacheWidth: decodeWidth,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: const Color(0xFFF3F3F6),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFFF6FA0),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  debugPrint(
                    '[PartyDetailImageView] 로드 실패 url=$url error=$error',
                  );
                  return _error('상세 이미지를 불러올 수 없어요');
                },
              );

        if (aspect != null) {
          picture = AspectRatio(aspectRatio: aspect, child: picture);
        }

        if (!bleed) return picture;

        // 부모(본문 여백) 폭에 맞는 상자를 두고, 그 안에서만 폭을 화면 전체로
        // 되돌린다. 높이는 우리가 계산한 값으로 고정되므로 세로 방향으로
        // 넘치지 않는다.
        final drawHeight = drawWidth / aspect;
        return SizedBox(
          height: drawHeight,
          child: OverflowBox(
            minWidth: drawWidth,
            maxWidth: drawWidth,
            minHeight: drawHeight,
            maxHeight: drawHeight,
            child: picture,
          ),
        );
      },
    );
  }

  Widget _error(String message) => Container(
    color: const Color(0xFFF3F3F6),
    padding: const EdgeInsets.symmetric(vertical: 28),
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.image_not_supported_outlined,
          size: 26,
          color: Colors.black38,
        ),
        const SizedBox(height: 6),
        Text(
          message,
          style: const TextStyle(fontSize: 12, color: Colors.black45),
        ),
      ],
    ),
  );
}
