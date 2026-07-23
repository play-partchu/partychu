import 'package:flutter/foundation.dart';

/// 기본 카드(PartyStandardCard)에 노출되는 파티 제목의 최대 글자 수 — 등록/수정
/// 화면의 제목 입력 미리보기 강조 색 경계와 반드시 같은 값을 써야 한다.
const int kPartyCardTitleVisibleLength = 12;

/// 기본 카드에 보여줄 제목 — [kPartyCardTitleVisibleLength]자를 넘으면 그 뒤를
/// 말줄임표로 잘라 보여준다(저장되는 값/상세화면 표시는 항상 전체 문자열).
String truncatePartyTitleForCard(String title) {
  if (title.length <= kPartyCardTitleVisibleLength) return title;
  return '${title.substring(0, kPartyCardTitleVisibleLength)}...';
}

/// 파티 데이터에서 대표 썸네일 URL을 선택합니다.
/// 우선순위: mainImageUrl → imageUrls.first → images.first → videoThumbnailUrl → null
String? getPartyThumbnailUrl(
  Map<String, dynamic> party, {
  String tag = 'PartyCard',
}) {
  final mainImageUrl = party['mainImageUrl'] as String?;
  final imageUrlsList = List<String>.from(party['imageUrls'] as List? ?? []);
  final imagesList = List<String>.from(party['images'] as List? ?? []);
  final videoThumbUrl = party['videoThumbnailUrl'] as String?;

  final selected = (mainImageUrl?.isNotEmpty == true)
      ? mainImageUrl
      : imageUrlsList.isNotEmpty
      ? imageUrlsList.first
      : imagesList.isNotEmpty
      ? imagesList.first
      : (videoThumbUrl?.isNotEmpty == true)
      ? videoThumbUrl
      : null;

  debugPrint(
    '[$tag] "${party['title']}" '
    'mainImageUrl=$mainImageUrl '
    'imageUrls=$imageUrlsList '
    'images=$imagesList '
    'videoThumbnailUrl=$videoThumbUrl '
    '→ selectedImage=$selected',
  );

  return selected;
}

/// 파티 등록자가 직접 고른 "대표 미디어" — 등록/수정 화면에서 사용자가 선택한
/// 사진 또는 동영상을 그대로 메인 목록/상세화면에 반영하기 위한 결과 객체.
class PartyCoverMedia {
  /// 'image' 또는 'video'.
  final String type;

  /// type이 'image'일 때 표시할 정지 이미지 URL.
  final String? imageUrl;

  /// type이 'video'일 때 재생할 URL(HLS 등).
  final String? videoUrl;

  /// type이 'video'일 때 Cloudflare Stream UID.
  final String? videoUid;

  /// 항상 채워지는 정지 썸네일 URL — 영상 자동재생을 지원하지 않는
  /// 카드(작은 카드 등)에서 이 값을 그대로 정지 이미지로 쓰면 된다.
  final String thumbnailUrl;

  /// 작은/큰 카드에서 동영상이 잘리는 위치(초점)와 확대 배율 — 값이 없는
  /// 기존 데이터는 항상 0.5/0.5/1.0(중앙, 추가 확대 없음)으로 기존
  /// BoxFit.cover 중앙 정렬과 동일하게 보인다. 기본 카드는 아래
  /// [basicCardVideoFocalX] 등 별도 필드를 쓴다 — 기본 카드 미디어 영역만
  /// 폭 비율이 달라(카드폭×130) 작은/큰 카드와 같은 값을 공유하면 잘리는
  /// 지점이 안 맞기 때문에, 기본 카드 전용 크롭 위치를 따로 저장한다.
  final double videoCropX;
  final double videoCropY;
  final double videoCropScale;

  /// 기본 카드(PartyStandardCard) 전용 크롭 초점/확대 배율 — 등록/수정
  /// 화면에서 기본 카드 비율 미리보기로 직접 지정한 값. 값이 없으면
  /// 0.5/0.5/1.0(중앙, 추가 확대 없음).
  final double basicCardVideoFocalX;
  final double basicCardVideoFocalY;
  final double basicCardVideoScale;

  /// 기본 카드 전용 "사진" 크롭 초점/확대 배율 — 파티에 사진이 여러 장일 수
  /// 있어 동영상처럼 필드 하나로 공유할 수 없다. 등록/수정 화면에서
  /// `basicCardPhotoCrops`(이미지 URL별 맵)로 저장해두고, 여기서는 현재
  /// 대표로 뽑힌 [imageUrl] 하나에 대한 값만 꺼내 담는다. 값이 없으면
  /// 0.5/0.5/1.0(중앙, 추가 확대 없음).
  final double basicCardPhotoFocalX;
  final double basicCardPhotoFocalY;
  final double basicCardPhotoScale;

  const PartyCoverMedia({
    required this.type,
    this.imageUrl,
    this.videoUrl,
    this.videoUid,
    required this.thumbnailUrl,
    this.videoCropX = 0.5,
    this.videoCropY = 0.5,
    this.videoCropScale = 1.0,
    this.basicCardVideoFocalX = 0.5,
    this.basicCardVideoFocalY = 0.5,
    this.basicCardVideoScale = 1.0,
    this.basicCardPhotoFocalX = 0.5,
    this.basicCardPhotoFocalY = 0.5,
    this.basicCardPhotoScale = 1.0,
  });

  bool get isVideo => type == 'video';
}

/// 파티의 최종 대표 미디어를 결정한다.
///
/// 우선순위:
/// 1) `coverMediaType`이 있으면(신규 데이터) 그 값을 그대로 신뢰한다
///    ('video'면 coverVideoUrl/coverVideoUid/coverThumbnailUrl,
///     'image'면 coverImageUrl).
/// 2) `coverMediaType`이 없는 기존 데이터는 하위호환 처리:
///    - 이미지가 하나도 없고 동영상만 있던 기존 규칙(isVideoOnly)을 그대로 유지
///    - 그 외에는 images[0] 우선 → videoThumbnailUrl → 기본 이미지 없음(null)
///      순서로 [getPartyThumbnailUrl]을 재사용한다(이 함수가 이미 그 순서를 구현).
PartyCoverMedia? getPartyCoverMedia(
  Map<String, dynamic> party, {
  String tag = 'PartyCover',
}) {
  final coverMediaType = party['coverMediaType'] as String?;
  final videoCropX = (party['videoCropX'] as num?)?.toDouble() ?? 0.5;
  final videoCropY = (party['videoCropY'] as num?)?.toDouble() ?? 0.5;
  final videoCropScale = (party['videoCropScale'] as num?)?.toDouble() ?? 1.0;
  final basicCardVideoFocalX =
      (party['basicCardVideoFocalX'] as num?)?.toDouble() ?? 0.5;
  final basicCardVideoFocalY =
      (party['basicCardVideoFocalY'] as num?)?.toDouble() ?? 0.5;
  final basicCardVideoScale =
      (party['basicCardVideoScale'] as num?)?.toDouble() ?? 1.0;
  final basicCardPhotoCrops =
      party['basicCardPhotoCrops'] as Map<String, dynamic>? ?? const {};

  // 사진 URL 하나에 대한 기본 카드 크롭 값을 꺼낸다 — 저장된 값이 없으면
  // 기존 BoxFit.cover 중앙 정렬과 동일한 0.5/0.5/1.0.
  (double, double, double) photoCropFor(String? url) {
    final raw = url != null ? basicCardPhotoCrops[url] as Map? : null;
    if (raw == null) return (0.5, 0.5, 1.0);
    return (
      (raw['x'] as num?)?.toDouble() ?? 0.5,
      (raw['y'] as num?)?.toDouble() ?? 0.5,
      (raw['scale'] as num?)?.toDouble() ?? 1.0,
    );
  }

  if (coverMediaType == 'video') {
    final videoUrl = party['coverVideoUrl'] as String?;
    if (videoUrl != null && videoUrl.isNotEmpty) {
      return PartyCoverMedia(
        type: 'video',
        videoUrl: videoUrl,
        videoUid: party['coverVideoUid'] as String?,
        thumbnailUrl: (party['coverThumbnailUrl'] as String?) ?? '',
        videoCropX: videoCropX,
        videoCropY: videoCropY,
        videoCropScale: videoCropScale,
        basicCardVideoFocalX: basicCardVideoFocalX,
        basicCardVideoFocalY: basicCardVideoFocalY,
        basicCardVideoScale: basicCardVideoScale,
      );
    }
  } else if (coverMediaType == 'image') {
    final imageUrl = party['coverImageUrl'] as String?;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final (photoFocalX, photoFocalY, photoScale) = photoCropFor(imageUrl);
      return PartyCoverMedia(
        type: 'image',
        imageUrl: imageUrl,
        thumbnailUrl: (party['coverThumbnailUrl'] as String?) ?? imageUrl,
        basicCardPhotoFocalX: photoFocalX,
        basicCardPhotoFocalY: photoFocalY,
        basicCardPhotoScale: photoScale,
      );
    }
  }

  // ── 하위호환: coverMediaType이 없는 기존 데이터 ──────────────────────────
  // 기존에도 "사진이 하나도 없고 동영상만 있는 경우"엔 동영상을 대표로 써왔으므로
  // (기존 isVideoOnly 판정) 그 동작을 그대로 유지한다.
  final videoUrl = party['videoUrl'] as String?;
  final mainImageUrl = party['mainImageUrl'] as String?;
  final imagesList = List<String>.from(party['images'] as List? ?? []);
  final imageUrlsList = List<String>.from(party['imageUrls'] as List? ?? []);
  final legacyVideoOnly =
      videoUrl != null &&
      videoUrl.isNotEmpty &&
      (mainImageUrl == null || mainImageUrl.isEmpty) &&
      imagesList.isEmpty &&
      imageUrlsList.isEmpty;
  if (legacyVideoOnly) {
    return PartyCoverMedia(
      type: 'video',
      videoUrl: videoUrl,
      videoUid: party['videoUid'] as String?,
      thumbnailUrl: (party['videoThumbnailUrl'] as String?) ?? '',
      videoCropX: videoCropX,
      videoCropY: videoCropY,
      videoCropScale: videoCropScale,
      basicCardVideoFocalX: basicCardVideoFocalX,
      basicCardVideoFocalY: basicCardVideoFocalY,
      basicCardVideoScale: basicCardVideoScale,
    );
  }

  final legacyImage = getPartyThumbnailUrl(party, tag: tag);
  if (legacyImage != null && legacyImage.isNotEmpty) {
    final (photoFocalX, photoFocalY, photoScale) = photoCropFor(legacyImage);
    return PartyCoverMedia(
      type: 'image',
      imageUrl: legacyImage,
      thumbnailUrl: legacyImage,
      basicCardPhotoFocalX: photoFocalX,
      basicCardPhotoFocalY: photoFocalY,
      basicCardPhotoScale: photoScale,
    );
  }
  return null;
}
