import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/models/party_detail_decoration_intensity.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/utils/video_crop.dart';
import 'package:party_app/widgets/party_detail_decoration.dart';
import 'package:party_app/widgets/party_detail_theme.dart';

/// 정보 카드 아이콘 이름 → 실제 아이콘. 모델(`party_detail_block.dart`)은
/// Flutter 의존성 없는 순수 Dart를 유지해야 하므로, 문자열→아이콘 매핑은
/// 위젯 계층인 여기서만 한다. 모르는/누락된 이름은 안전한 기본 아이콘으로.
IconData partyDetailInfoCardIconData(String? name) {
  switch (name) {
    case 'location':
      return Icons.location_on_outlined;
    case 'schedule':
      return Icons.schedule;
    case 'payment':
      return Icons.payments_outlined;
    case 'badge':
      return Icons.badge_outlined;
    case 'dress':
      return Icons.checkroom_outlined;
    case 'gift':
      return Icons.card_giftcard_outlined;
    case 'warning':
      return Icons.warning_amber_outlined;
    default:
      return Icons.info_outline;
  }
}

// ── "화려하게" 전용 카드/텍스트 강조 변형 ────────────────────────────────
// [PartyDetailBlockPreview.richAutoDecorations]가 true일 때만 쓰인다 —
// 블록마다(블록 id 기반 시드) 하나씩 결정적으로 골라, 한 페이지 안에서도
// 같은 기법만 반복되지 않게 섞는다("다시 꾸미기"로 variantSeed가 바뀌면
// 조합도 함께 바뀐다). false일 때는 항상 [plain]/기존 렌더링과 동일하다.
enum _RichCardVariant { plain, accentStripe, sparkleCorner, hero }

enum _RichTextEmphasisVariant {
  boldColorAccent,
  underlineAccent,
  colorHighlight,
  badgePill,
  quoteStyle,
}

/// 선택된 디자인 테마로 블록 리스트를 그리는 미리보기 렌더러 — 블록 에디터
/// 안의 실시간 미리보기와, 실제 파티 상세화면(`party_detail_screen.dart`)
/// 렌더링을 함께 담당하도록 순수 `List<PartyDetailBlock>` + [theme] 값만
/// 입력으로 받는다(에디터 draft 클래스에 의존하지 않는다). 미리보기와 실제
/// 상세화면이 같은 이 위젯·같은 [PartyDetailThemeData]를 그대로 쓰므로 두
/// 곳에서 같은 테마가 다르게 보일 일이 없다.
///
/// [localImageOverrides]/[localVideoOverrides]는 아직 업로드되지 않은
/// 사진/동영상 블록을 로컬 파일로 미리 보여주기 위한 것으로, 에디터 내부
/// 미리보기에서만 쓰인다(blockId → 로컬 File).
///
/// [onImageTap]이 주어지면 사진 블록을 탭했을 때 호출된다(상세화면의
/// 전체화면 보기 진입용). null이면 사진 블록은 탭 동작이 없다(에디터
/// 내부 미리보기의 기존 동작 유지). 동영상 블록은 탭하면 그 자리에서
/// 재생/일시정지된다(전체화면 콜백 없음).
///
/// 블록마다 `KeyedSubtree(key: ValueKey(block.id))`로 감싸, 테마만 바뀌는
/// 리빌드(색상 프로퍼티 변경)에서도 FAQ 아코디언 펼침 상태나 동영상 재생
/// 컨트롤러가 불필요하게 초기화되지 않는다.
///
/// 이 위젯은 스스로 스크롤하지 않는(`Column`만 반환하는) 고정 크기
/// 위젯이므로, 호출부의 `ListView`/`SingleChildScrollView` 안에 그대로
/// 넣어도 중첩 스크롤 문제가 생기지 않는다. 블록 하나의 렌더링이 실패해도
/// (예상치 못한 예외) 그 블록만 조용히 생략하고 나머지는 정상 표시한다.
class PartyDetailBlockPreview extends StatelessWidget {
  final List<PartyDetailBlock> blocks;
  final PartyDetailThemeKey theme;
  final Map<String, XFile> localImageOverrides;
  final Map<String, XFile> localVideoOverrides;
  final void Function(PartyDetailBlock block)? onImageTap;

  /// "간편 자동 꾸미기" 미리보기에서 문단을 탭해 스타일/이모지를 바로
  /// 고치기 위한 콜백(선택). 주어지면 블록 전체를 `GestureDetector`로 감싼다.
  /// **실제 상세페이지(`party_detail_screen.dart`)에서는 절대 넘기지
  /// 않는다** — 일반 사용자가 상세페이지에서 문단을 탭했을 때 편집 UI가
  /// 뜨면 안 되므로, 이 콜백은 "간편 자동 꾸미기" 미리보기 화면에서만 쓴다.
  final void Function(PartyDetailBlock block)? onBlockTap;

  /// 에러 로그 식별용(선택). 에디터 내부 미리보기에는 아직 문서가 없어 null.
  final String? partyId;

  /// 자동 꾸미기 강도 — 배경 장식/사진 카드 프레임/블록 구분 장식/첫 사진
  /// 강조에 얼마나 힘을 줄지(`lib/widgets/party_detail_decoration.dart`).
  final PartyDetailDecorationIntensity intensity;

  /// "다시 꾸미기" 변형 시드(기본 0) — "간편 자동 꾸미기"에서만 쓰인다.
  /// 이 값이 바뀌면 배경 장식/구분 장식의 선택이 함께 바뀐다(문단 분류
  /// 자체는 원문 기반이라 그대로 유지됨 — `auto_description_classifier.dart`
  /// 참고). 블록 에디터로 만든 상세페이지는 항상 기본값 0을 쓴다.
  final int variantSeed;

  /// "간편 자동 꾸미기"의 "화려하게" 전용 텍스트/카드 강화(강조 기법·폰트
  /// 차등·카드 변형)를 켠다. **"간편 자동 꾸미기" 두 호출부(파티 등록
  /// 미리보기, 실제 상세화면)에서만** `intensity == rich`일 때 true로
  /// 넘긴다 — "직접 상세페이지 만들기"(블록 에디터)는 이 파라미터를 절대
  /// 넘기지 않으므로 항상 false이고, 그 화면에서 어떤 강도를 골라도 이
  /// 강화의 영향을 받지 않는다(기존 배경/사진 프레임/구분 장식은 그대로
  /// `intensity`만으로 계속 동작).
  final bool richAutoDecorations;

  const PartyDetailBlockPreview({
    super.key,
    required this.blocks,
    this.theme = PartyDetailThemeKey.partychu,
    this.localImageOverrides = const {},
    this.localVideoOverrides = const {},
    this.onImageTap,
    this.onBlockTap,
    this.partyId,
    this.intensity = PartyDetailDecorationIntensity.standard,
    this.variantSeed = 0,
    this.richAutoDecorations = false,
  });

  /// 장식 배치용 결정적 시드 — 같은 파티(+테마+salt+variantSeed)는
  /// 새로고침해도 항상 같은 배치를 낸다(완전 랜덤이 아님). 에디터
  /// 미리보기는 아직 문서 id가 없어 partyId가 null일 수 있어 고정
  /// 문자열로 대체한다.
  int _seed(String salt) =>
      Object.hash(partyId ?? 'preview', theme.name, variantSeed, salt);

  @override
  Widget build(BuildContext context) {
    final palette = PartyDetailThemeRegistry.fromKey(theme);
    final rendered = <Widget>[];
    var sawFirstImage = false;
    for (final block in blocks) {
      Widget? widget;
      final isHero = !sawFirstImage && block.type == PartyDetailBlockType.image;
      try {
        widget = _buildBlock(context, palette, block, isHero: isHero);
      } catch (e, st) {
        debugPrint(
          '[PartyDetailBlockPreview]\n'
          'partyId: ${partyId ?? '(none)'}\n'
          'detailTheme: ${theme.name}\n'
          'blockId: ${block.id}\n'
          'type: ${block.type}\n'
          'error: $e\n'
          'stack: $st',
        );
        widget = null;
      }
      if (widget != null) {
        final tap = onBlockTap;
        if (tap != null) {
          widget = GestureDetector(onTap: () => tap(block), child: widget);
        }
        rendered.add(KeyedSubtree(key: ValueKey(block.id), child: widget));
        if (isHero) sawFirstImage = true;
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Positioned.fill(
            child: PartyDetailSectionBackground(
              theme: theme,
              intensity: intensity,
              seed: _seed('background'),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < rendered.length; i++) ...[
                  rendered[i],
                  if (i != rendered.length - 1) _gap(i, palette),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 블록 사이 간격 — 강도가 simple이거나, 2~3블록마다 한 번 오는 자리가
  /// 아니면 기존처럼 빈 여백만. 그 자리에 걸리면 여백 사이에 구분 장식을
  /// 끼워 넣는다(결정적 — i+seed 기반이라 매번 같은 자리에 같은 장식).
  Widget _gap(int i, PartyDetailThemeData palette) {
    final plainGap = SizedBox(height: palette.contentGap);
    if (intensity == PartyDetailDecorationIntensity.simple) return plainGap;
    // i=1(두 번째 블록 뒤)부터 2~3개 간격으로 한 번씩만 — 매 블록마다
    // 넣지 않는다는 요구사항.
    final period = 2 + (_seed('period-$i') % 2).abs(); // 2 또는 3
    if ((i + 1) % period != 0) return plainGap;
    return Column(
      children: [
        SizedBox(height: palette.contentGap / 2),
        PartyDetailBlockSeparator(
          theme: theme,
          intensity: intensity,
          seed: _seed('sep-$i'),
        ),
        SizedBox(height: palette.contentGap / 2),
      ],
    );
  }

  /// 블록 하나를 그린다. 표시할 내용이 없으면(텍스트/이미지 누락 등) null을
  /// 돌려줘 호출부가 그 블록을 조용히 건너뛰게 한다.
  Widget? _buildBlock(
    BuildContext context,
    PartyDetailThemeData palette,
    PartyDetailBlock block, {
    bool isHero = false,
  }) {
    switch (block.type) {
      case PartyDetailBlockType.heading:
        final text = block.text?.trim();
        if (text == null || text.isEmpty) return null;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            text,
            style: TextStyle(
              fontSize: richAutoDecorations ? 24 : 22,
              fontWeight: FontWeight.bold,
              letterSpacing: richAutoDecorations ? -0.3 : null,
              color: palette.headingColor,
              height: 1.3,
            ),
          ),
        );
      case PartyDetailBlockType.subheading:
        final text = block.text?.trim();
        if (text == null || text.isEmpty) return null;
        return _buildSubheading(palette, block, text);
      case PartyDetailBlockType.paragraph:
        final text = block.text?.trim();
        if (text == null || text.isEmpty) return null;
        return Text(
          text,
          style: TextStyle(
            fontSize: 15,
            height: richAutoDecorations ? 1.75 : 1.7,
            color: palette.bodyColor,
          ),
          softWrap: true,
        );
      case PartyDetailBlockType.image:
        return _buildImage(context, palette, block, isHero: isHero);
      case PartyDetailBlockType.divider:
        return Container(height: 1, color: palette.dividerColor);
      case PartyDetailBlockType.notice:
        return _buildNotice(palette, block);
      case PartyDetailBlockType.checklist:
        return _buildChecklist(palette, block);
      case PartyDetailBlockType.faq:
        return _buildFaq(palette, block);
      case PartyDetailBlockType.timeline:
        return _buildTimeline(palette, block);
      case PartyDetailBlockType.infoCard:
        return _buildInfoCard(palette, block);
      case PartyDetailBlockType.video:
        return _buildVideo(palette, block);
      case PartyDetailBlockType.imageGroup:
        return _buildImageGroup(palette, block);
      case PartyDetailBlockType.unknown:
        // 이 버전이 모르는 블록은 화면에 아무것도 그리지 않는다 — 데이터는
        // toMap()에서 그대로 보존되므로 미리보기에서만 조용히 생략된다.
        return null;
    }
  }

  Widget? _buildImage(
    BuildContext context,
    PartyDetailThemeData palette,
    PartyDetailBlock block, {
    bool isHero = false,
  }) {
    final localFile = localImageOverrides[block.id];
    final url = block.imageUrl;
    final hasUrl = url != null && url.isNotEmpty;
    if (localFile == null && !hasUrl) return null;

    // 크롭 값(imageCropScale)이 있으면 4:5 고정 프레임 + 핀치줌/드래그로
    // 맞춘 위치(cropX/cropY)·배율(cropScale)을 그대로 재현한다(에디터의
    // 위치 조정 화면과 수학적으로 동일한 lib/utils/video_crop.dart 재사용
    // — party_detail_block_editor_screen.dart 참고). 크롭 값이 없는 기존
    // 블록은 원본 비율 그대로 렌더링해 회귀 없이 하위 호환한다.
    final cropX = block.imageCropX;
    final cropY = block.imageCropY;
    final cropScale = block.imageCropScale;
    final hasCrop = cropX != null && cropY != null && cropScale != null;
    final aspectRatio = hasCrop
        ? 4 / 5
        : (block.imageWidth != null &&
              block.imageHeight != null &&
              block.imageHeight! > 0)
        ? block.imageWidth! / block.imageHeight!
        : 4 / 3;
    final alignment = hasCrop
        ? videoCropAlignment(cropX, cropY)
        : Alignment.center;

    Widget image;
    if (localFile != null) {
      image = LocalMedia.image(
        localFile,
        fit: BoxFit.cover,
        alignment: alignment,
        width: double.infinity,
      );
    } else {
      // 화면 가로폭 기준으로 디코드 해상도를 제한해 큰 원본 사진의 메모리
      // 사용량을 줄인다 — 원본이 더 작으면 Flutter가 그 이상으로 확대
      // 디코드하지 않으므로 화질 저하는 없다. 사진 자체에는 어떤 색상
      // 필터/오버레이도 적용하지 않는다(테마는 배경/여백에만 반영).
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final targetWidth = (MediaQuery.of(context).size.width * dpr).round();
      image = Image.network(
        url!,
        fit: BoxFit.cover,
        alignment: alignment,
        width: double.infinity,
        cacheWidth: targetWidth > 0 ? targetWidth : null,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: palette.cardBackground,
            alignment: Alignment.center,
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.primary,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          debugPrint(
            '[PartyDetailBlockPreview]\n'
            'partyId: ${partyId ?? '(none)'}\n'
            'detailTheme: ${theme.name}\n'
            'blockId: ${block.id}\n'
            'type: ${block.type}\n'
            'error: $error\n'
            'stack: $stackTrace',
          );
          return Container(
            color: palette.cardBackground,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.image_not_supported_outlined,
                  color: palette.mutedColor,
                  size: 26,
                ),
                const SizedBox(height: 4),
                Text(
                  '이미지를 불러올 수 없어요',
                  style: TextStyle(fontSize: 11, color: palette.mutedColor),
                ),
              ],
            ),
          );
        },
      );
    }

    final inner = AspectRatio(
      aspectRatio: aspectRatio,
      child: hasCrop
          ? CroppedMedia(
              cropX: cropX,
              cropY: cropY,
              cropScale: cropScale,
              child: image,
            )
          : image,
    );

    // 자동 꾸미기(2번: 사진 카드, 5번: 첫 사진 강조) — 이미 크롭까지 끝난
    // 이미지를 그대로 감싸기만 하므로 사진 위치/배율은 절대 바뀌지 않는다.
    Widget framed = PartyDetailPhotoFrame(
      theme: theme,
      intensity: intensity,
      isHero: isHero,
      child: inner,
    );

    final tap = onImageTap;
    if (tap != null && hasUrl) {
      framed = GestureDetector(onTap: () => tap(block), child: framed);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        framed,
        if ((block.caption ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            block.caption!,
            style: TextStyle(fontSize: 12, color: palette.mutedColor),
          ),
        ],
      ],
    );
  }

  /// 사진 콜라주(imageGroup) — 칸마다 항상 정사각형(1:1)으로 그리고, 유효
  /// 사진 개수(2~4)에 따라 가로 한 줄(2~3장) 또는 2×2 그리드(4장)로
  /// 배치한다. 칸별 크롭은 이미 확정된 값을 그대로 재현할 뿐이라(단일 사진
  /// 블록과 동일한 `CroppedMedia`) 위치/배율이 절대 바뀌지 않는다. 완성된
  /// 그리드 전체를 기존 `PartyDetailPhotoFrame`로 한 번만 감싸 카드 테두리·
  /// 그림자·포인트 색 바를 그대로 재사용한다(콜라주 전용 프레임을 새로 만들지
  /// 않음). 유효 사진이 2장 미만이면 표시할 콜라주가 아니므로 null.
  Widget? _buildImageGroup(
    PartyDetailThemeData palette,
    PartyDetailBlock block,
  ) {
    final payload = block.imageGroup;
    if (payload == null) return null;
    final valid = payload.items.where((item) {
      final hasUrl = item.imageUrl.isNotEmpty;
      final hasLocal = localImageOverrides.containsKey(item.id);
      return hasUrl || hasLocal;
    }).toList();
    if (valid.length < 2) return null;
    // 저장 시점에 이미 최대 4장으로 걸러지지만, 과거/외부 데이터 방어 차원에서
    // 렌더링에서도 다시 한번 4장으로 자른다.
    final items = valid.length > 4 ? valid.sublist(0, 4) : valid;

    Widget cell(PartyDetailImageGroupItem item) {
      final localFile = localImageOverrides[item.id];
      final cropX = item.cropX;
      final cropY = item.cropY;
      final cropScale = item.cropScale;
      final hasCrop = cropX != null && cropY != null && cropScale != null;
      final alignment = hasCrop
          ? videoCropAlignment(cropX, cropY)
          : Alignment.center;

      final image = localFile != null
          ? LocalMedia.image(localFile, fit: BoxFit.cover, alignment: alignment)
          : Image.network(
              item.imageUrl,
              fit: BoxFit.cover,
              alignment: alignment,
              errorBuilder: (context, error, stackTrace) => Container(
                color: palette.cardBackground,
                alignment: Alignment.center,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: palette.mutedColor,
                  size: 20,
                ),
              ),
            );
      final cropped = hasCrop
          ? CroppedMedia(
              cropX: cropX,
              cropY: cropY,
              cropScale: cropScale,
              child: image,
            )
          : image;
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: AspectRatio(aspectRatio: 1, child: cropped),
      );
    }

    const gap = SizedBox(width: 4, height: 4);
    Widget row(List<PartyDetailImageGroupItem> rowItems) => Row(
      children: [
        for (var i = 0; i < rowItems.length; i++) ...[
          if (i != 0) gap,
          Expanded(child: cell(rowItems[i])),
        ],
      ],
    );

    final grid = items.length <= 3
        ? row(items)
        : Column(
            children: [row(items.sublist(0, 2)), gap, row(items.sublist(2, 4))],
          );

    final framed = PartyDetailPhotoFrame(
      theme: theme,
      intensity: intensity,
      isHero: false,
      child: grid,
    );

    final caption = payload.caption?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        framed,
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            style: TextStyle(fontSize: 12, color: palette.mutedColor),
          ),
        ],
      ],
    );
  }

  Widget? _buildChecklist(
    PartyDetailThemeData palette,
    PartyDetailBlock block,
  ) {
    final payload = block.checklist;
    if (payload == null || payload.items.isEmpty) return null;
    final title = payload.title?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null && title.isNotEmpty) ...[
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: palette.headingColor,
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (final item in payload.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle, size: 18, color: palette.iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: palette.bodyColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget? _buildFaq(PartyDetailThemeData palette, PartyDetailBlock block) {
    final payload = block.faq;
    if (payload == null || payload.items.isEmpty) return null;
    return _FaqAccordion(
      palette: palette,
      title: payload.title,
      items: payload.items,
    );
  }

  Widget? _buildTimeline(PartyDetailThemeData palette, PartyDetailBlock block) {
    final payload = block.timeline;
    if (payload == null || payload.items.isEmpty) return null;
    final title = payload.title?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null && title.isNotEmpty) ...[
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: palette.headingColor,
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < payload.items.length; i++)
          _timelineRow(
            palette,
            payload.items[i],
            isLast: i == payload.items.length - 1,
          ),
      ],
    );
  }

  Widget _timelineRow(
    PartyDetailThemeData palette,
    PartyDetailTimelineItem item, {
    required bool isLast,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              item.time,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: palette.primary,
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: palette.timelineColor,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: palette.timelineColor.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.headingColor,
                    ),
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: palette.mutedColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildInfoCard(PartyDetailThemeData palette, PartyDetailBlock block) {
    final payload = block.infoCard;
    if (payload == null) return null;
    if (payload.title.trim().isEmpty && payload.text.trim().isEmpty)
      return null;

    final variant = richAutoDecorations
        ? _richVariant(_RichCardVariant.values, 'card-${block.id}')
        : _RichCardVariant.plain;
    final isHeroCard = variant == _RichCardVariant.hero;
    final iconSize = isHeroCard ? 44.0 : 36.0;

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _richCardDecoration(
        variant: variant,
        background: palette.cardBackground,
        palette: palette,
        border: Border.all(color: palette.cardBorder),
        shadow: palette.cardShadow,
        radius: isHeroCard ? 14 : 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: palette.iconBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              partyDetailInfoCardIconData(payload.icon),
              size: isHeroCard ? 22 : 18,
              color: palette.iconColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (payload.title.isNotEmpty)
                  Text(
                    payload.title,
                    style: TextStyle(
                      fontSize: richAutoDecorations
                          ? (isHeroCard ? 16 : 15)
                          : 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: richAutoDecorations ? 0.1 : null,
                      color: palette.headingColor,
                    ),
                  ),
                if (payload.title.isNotEmpty && payload.text.isNotEmpty)
                  const SizedBox(height: 4),
                if (payload.text.isNotEmpty)
                  Text(
                    payload.text,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: palette.mutedColor,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return _withSparkle(
      card,
      show: variant == _RichCardVariant.sparkleCorner,
      color: palette.primary,
    );
  }

  Widget? _buildNotice(PartyDetailThemeData palette, PartyDetailBlock block) {
    final text = block.text?.trim();
    if (text == null || text.isEmpty) return null;
    final variant = richAutoDecorations
        ? _richVariant(_RichCardVariant.values, 'card-${block.id}')
        : _RichCardVariant.plain;
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _richCardDecoration(
        variant: variant,
        background: palette.noticeBackground,
        palette: palette,
        shadow: palette.cardShadow,
        radius: variant == _RichCardVariant.hero ? 14 : 12,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.6,
          color: palette.noticeTextColor,
          fontWeight: richAutoDecorations ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
    return _withSparkle(
      card,
      show: variant == _RichCardVariant.sparkleCorner,
      color: palette.primary,
    );
  }

  /// "화려하게"일 때 subheading(배너 줄)에 [_RichTextEmphasisVariant] 중
  /// 하나를 블록 id 기반으로 결정적으로 골라 적용한다. false면 기존 렌더링과
  /// 동일하다.
  Widget _buildSubheading(
    PartyDetailThemeData palette,
    PartyDetailBlock block,
    String text,
  ) {
    final baseStyle = TextStyle(
      fontSize: richAutoDecorations ? 17 : 16,
      fontWeight: FontWeight.w700,
      color: palette.subheadingColor,
      height: 1.4,
      letterSpacing: richAutoDecorations ? 0.1 : null,
    );
    if (!richAutoDecorations) return Text(text, style: baseStyle);

    final variant = _richVariant(
      _RichTextEmphasisVariant.values,
      'emphasis-${block.id}',
    );
    switch (variant) {
      case _RichTextEmphasisVariant.boldColorAccent:
        return Text(
          text,
          style: baseStyle.copyWith(
            fontWeight: FontWeight.w800,
            color: palette.primary,
            letterSpacing: 0.2,
          ),
        );
      case _RichTextEmphasisVariant.underlineAccent:
        return Text(
          text,
          style: baseStyle.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: palette.primary,
            decorationThickness: 2,
          ),
        );
      case _RichTextEmphasisVariant.colorHighlight:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: palette.secondary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(text, style: baseStyle),
        );
      case _RichTextEmphasisVariant.badgePill:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: palette.iconBackground,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.cardBorder),
          ),
          child: Text(text, style: baseStyle),
        );
      case _RichTextEmphasisVariant.quoteStyle:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 18,
              margin: const EdgeInsets.only(top: 3, right: 8),
              color: palette.primary.withValues(alpha: 0.5),
            ),
            Icon(
              Icons.format_quote,
              size: 18,
              color: palette.primary.withValues(alpha: 0.35),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text,
                style: baseStyle.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          ],
        );
    }
  }

  /// [salt]로 시드를 계산해(기존 [_seed] 재사용 — variantSeed가 이미
  /// 포함돼 있어 "다시 꾸미기"마다 선택이 함께 바뀐다) [values] 중 하나를
  /// 결정적으로 고른다.
  T _richVariant<T>(List<T> values, String salt) =>
      values[_seed(salt).abs() % values.length];

  BoxDecoration _richCardDecoration({
    required _RichCardVariant variant,
    required Color background,
    required PartyDetailThemeData palette,
    required double radius,
    Border? border,
    List<BoxShadow>? shadow,
  }) {
    switch (variant) {
      case _RichCardVariant.plain:
      case _RichCardVariant.sparkleCorner:
        return BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(radius),
          border: border,
          boxShadow: shadow,
        );
      case _RichCardVariant.accentStripe:
        return BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(radius),
          border: Border(left: BorderSide(color: palette.primary, width: 4)),
          boxShadow: shadow,
        );
      case _RichCardVariant.hero:
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              background,
              Color.alphaBlend(
                palette.primary.withValues(alpha: 0.06),
                background,
              ),
            ],
          ),
          borderRadius: BorderRadius.circular(radius),
          border: border,
          boxShadow: shadow,
        );
    }
  }

  /// [show]가 true면 카드 우상단에 작은 반짝임 아이콘을 얹는다
  /// (`PartyDetailPhotoFrame`의 히어로 반짝임과 톤을 맞춘 것).
  Widget _withSparkle(Widget card, {required bool show, required Color color}) {
    if (!show) return card;
    return Stack(
      children: [
        card,
        Positioned(
          right: 10,
          top: 10,
          child: IgnorePointer(
            child: Icon(
              Icons.auto_awesome,
              size: 14,
              color: color.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildVideo(PartyDetailThemeData palette, PartyDetailBlock block) {
    final payload = block.video;
    final localFile = localVideoOverrides[block.id];
    final hasUrl = payload != null && payload.videoUrl.isNotEmpty;
    if (localFile == null && !hasUrl) return null;

    final caption = payload?.caption?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailVideoPlayer(
          block: block,
          localFile: localFile,
          accentColor: palette.primary,
          partyId: partyId,
          detailTheme: theme.name,
        ),
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            style: TextStyle(fontSize: 12, color: palette.mutedColor),
          ),
        ],
      ],
    );
  }
}

/// FAQ 아코디언 — 펼침/접힘 상태를 이 위젯 하나의 로컬 state로만 관리해,
/// 열고 닫아도 `PartyDetailBlockPreview`나 그 상위(`PartyDetailScreen`)가
/// 다시 빌드되지 않는다. 부모가 `KeyedSubtree(key: ValueKey(block.id))`로
/// 감싸주므로, 테마만 바뀌는 리빌드에서도 이 State(펼침 상태)는 그대로
/// 유지된다.
class _FaqAccordion extends StatefulWidget {
  final PartyDetailThemeData palette;
  final String? title;
  final List<PartyDetailFaqItem> items;

  const _FaqAccordion({required this.palette, this.title, required this.items});

  @override
  State<_FaqAccordion> createState() => _FaqAccordionState();
}

class _FaqAccordionState extends State<_FaqAccordion> {
  // 기본 상태는 접힘 — 요구사항대로 아무 항목도 미리 펼치지 않는다.
  final Set<String> _expandedIds = {};

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final title = widget.title?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null && title.isNotEmpty) ...[
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: palette.headingColor,
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (final item in widget.items) _faqTile(palette, item),
      ],
    );
  }

  Widget _faqTile(PartyDetailThemeData palette, PartyDetailFaqItem item) {
    final expanded = _expandedIds.contains(item.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: palette.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.cardBorder),
        boxShadow: palette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() {
              if (expanded) {
                _expandedIds.remove(item.id);
              } else {
                _expandedIds.add(item.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(
                    'Q',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: palette.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.question,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: palette.headingColor,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: palette.mutedColor,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: palette.mutedColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.answer,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: palette.bodyColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 동영상 블록 재생기 — 기존 `FeedVideoManager`(단일 재생 보장 + 전역
/// 음소거)와 `VisibilityDetector`(화면 밖으로 나가면 일시정지)를 그대로
/// 재사용한다. 무한 피드가 아닌 문서형 콘텐츠이므로 자동재생은 하지 않고
/// 탭해서 재생하는 방식(`media_gallery.dart`의 `_GalleryVideoItem`과 동일한
/// 정책)을 따른다. 부모가 `KeyedSubtree(key: ValueKey(block.id))`로
/// 감싸주므로, 테마만 바뀌는 리빌드에서는 재생 상태가 초기화되지 않는다.
///
/// [accentColor]는 재생 버튼 오버레이에만 쓰인다 — 동영상 원본 화면에는
/// 어떤 색상 필터/오버레이도 적용하지 않는다.
class _DetailVideoPlayer extends StatefulWidget {
  final PartyDetailBlock block;

  /// 아직 업로드되지 않은 경우의 로컬 미리보기 파일(에디터 전용).
  final XFile? localFile;

  final Color accentColor;
  final String? partyId;
  final String detailTheme;

  const _DetailVideoPlayer({
    required this.block,
    this.localFile,
    required this.accentColor,
    this.partyId,
    required this.detailTheme,
  });

  @override
  State<_DetailVideoPlayer> createState() => _DetailVideoPlayerState();
}

class _DetailVideoPlayerState extends State<_DetailVideoPlayer> {
  final Object _playToken = Object();
  VideoPlayerController? _ctrl;
  bool _loading = false;
  bool _hasError = false;
  bool _muted = true;

  bool get _isLocal => widget.localFile != null;

  String? get _source {
    if (widget.localFile != null) return widget.localFile!.path;
    final url = widget.block.video?.videoUrl;
    return (url != null && url.isNotEmpty) ? url : null;
  }

  @override
  void initState() {
    super.initState();
    _muted = FeedVideoManager.instance.muted;
    FeedVideoManager.instance.mutedNotifier.addListener(_onGlobalMuteChanged);
  }

  void _onGlobalMuteChanged() {
    final m = FeedVideoManager.instance.muted;
    if (m == _muted) return;
    setState(() => _muted = m);
    _ctrl?.setVolume(m ? 0 : 1);
  }

  Future<void> _start() async {
    if (_loading || _ctrl != null) return;
    final src = _source;
    if (src == null) return;

    setState(() {
      _loading = true;
      _hasError = false;
    });
    _muted = FeedVideoManager.instance.muted;
    unawaited(FeedVideoManager.instance.loadMutePreference());

    try {
      final ctrl = _isLocal
          ? LocalMedia.videoControllerForPath(src)
          : VideoPlayerController.networkUrl(Uri.parse(src));
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      ctrl.setVolume(_muted ? 0 : 1);
      _ctrl = ctrl;
      FeedVideoManager.instance.requestPlay(_playToken, _pauseSelf);
      ctrl.play();
      setState(() => _loading = false);
    } catch (e) {
      debugPrint(
        '[PartyDetailBlockPreview]\n'
        'partyId: ${widget.partyId ?? '(none)'}\n'
        'detailTheme: ${widget.detailTheme}\n'
        'blockId: ${widget.block.id}\n'
        'type: ${widget.block.type}\n'
        'error: $e\n'
        'stack: (동영상 초기화 실패)',
      );
      if (mounted) {
        setState(() {
          _hasError = true;
          _loading = false;
        });
      }
    }
  }

  void _pauseSelf() {
    _ctrl?.pause();
    if (mounted) setState(() {});
  }

  void _toggle() {
    final c = _ctrl;
    if (c == null) {
      _start();
      return;
    }
    if (c.value.isPlaying) {
      FeedVideoManager.instance.release(_playToken);
      c.pause();
    } else {
      FeedVideoManager.instance.requestPlay(_playToken, _pauseSelf);
      c.play();
    }
    setState(() {});
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    // VisibilityDetector 콜백은 dispose 이후에도 도착할 수 있다 — 반드시
    // mounted를 먼저 확인해 setState-after-dispose를 막는다.
    if (!mounted) return;
    if (info.visibleFraction <= 0 && _ctrl != null && _ctrl!.value.isPlaying) {
      _pauseSelf();
    }
  }

  @override
  void dispose() {
    FeedVideoManager.instance.mutedNotifier.removeListener(
      _onGlobalMuteChanged,
    );
    FeedVideoManager.instance.release(_playToken);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.block.video?.aspectRatio;
    final aspectRatio = (ratio != null && ratio > 0) ? ratio : 16 / 9;
    return VisibilityDetector(
      key: ValueKey(_playToken),
      onVisibilityChanged: _onVisibilityChanged,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final ctrl = _ctrl;
    final thumbnailUrl = widget.block.video?.thumbnailUrl;
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        // 영상 비율과 실제 렌더링 영역이 어긋나 상하/좌우에 여백이 생겨도
        // (회전 보정이 필요한 영상 등) 검은 배경 대신 이 그라데이션이 항상
        // 맨 아래에 깔려 있도록 별도 레이어로 둔다.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF6FA0), Color(0xFF8B5CF6)],
            ),
          ),
        ),
        if (ctrl != null && ctrl.value.isInitialized)
          VideoPlayer(ctrl)
        else if (!_isLocal && thumbnailUrl != null && thumbnailUrl.isNotEmpty)
          Image.network(
            thumbnailUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        if (_loading)
          const CircularProgressIndicator(color: Colors.white70)
        else if (_hasError)
          const Icon(Icons.error_outline, color: Colors.white54, size: 36)
        else if (ctrl == null || !ctrl.value.isPlaying)
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: widget.accentColor.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 30),
          ),
      ],
    );
  }
}
