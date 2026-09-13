import 'dart:math' as math;

/// 파티 상세 본문 전용 **세로형 상세 이미지 1장**.
///
/// 캔바·미리캔버스로 만든 "상세페이지 이미지"를 그대로 올려, 파티 상세에서
/// 가로폭 전체 + 원본 비율 그대로 처음부터 끝까지 보여주기 위한 것이다.
///
/// ── 기존 대표 사진/동영상과 왜 섞지 않는가 ────────────────────────────
/// 대표 미디어(`images`/`videoUrl`/`coverMediaType` …)는 **카드 썸네일과 상단
/// 갤러리**의 정본이다. 거기에 세로 20:1짜리 이미지를 끼워 넣으면 배열 순서가
/// 곧 대표 판정인 로직(party_register_screen의 coverImageUrl 재정렬,
/// MediaGallery의 initialPage)이 전부 흔들린다. 그래서 이 이미지는 그 배열에
/// 절대 들어가지 않고 **필드 하나**로만 산다.
///
/// ── 왜 detailBlocks가 아닌가 ──────────────────────────────────────────
/// 블록형 상세페이지(`detailBlocks`)는 "직접 상세페이지 만들기"를 고른
/// 호스트만 쓰고, 그 모드를 고르면 평문 소개(description)가 렌더링되지
/// 않는다(party_detail_screen의 detailDescriptionMode 분기). 상세 이미지는
/// **어떤 소개 방식을 골랐든** 그 아래 붙어야 하므로 두 갈래 어디에도 속하지
/// 않는 독립 필드가 맞다.
class PartyDetailImage {
  /// 파티 문서 필드명 — 읽는 쪽/쓰는 쪽이 문자열을 각자 적지 않게 한 곳에 둔다.
  /// 서버 미디어 정리(functions/contentCleanup.js의 party.imageFields)에도
  /// 같은 이름이 들어가 있어야 파티를 지울 때 R2 원본까지 함께 사라진다.
  static const urlField = 'detailImageUrl';
  static const widthField = 'detailImageWidth';
  static const heightField = 'detailImageHeight';

  /// R2 키 접두사 — 기존 파티 이미지 경로(`party_images/{uid}/…`) 안의
  /// 하위 폴더를 쓴다. 대표 사진과 한 폴더에 섞이지 않아, 나중에 사람이
  /// 버킷을 들여다볼 때 무엇이 상세 이미지인지 바로 구분된다.
  static const storageFolder = 'party_images/detail';

  /// 받아들이는 파일 최대 크기. 세로로 아무리 길어도 되지만 용량은 막는다 —
  /// 상세를 여는 모든 참가자가 매번 내려받는 파일이다.
  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxFileMegabytes = 10;

  /// 지원 확장자. 동영상은 받지 않는다(상세 본문 전용 정지 이미지다).
  static const allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  // ── 디코드 상한 ────────────────────────────────────────────────────
  // 초장문 이미지를 원본 해상도로 메모리에 올리면 저사양 기기에서 그대로
  // OOM이다. 예: 1080×20000 이미지는 RGBA로 약 86MB — 화면 하나를 여는
  // 데 쓸 수 있는 양이 아니다.
  //
  // 그래서 두 상한을 **함께** 건다:
  //   1) 가로폭 상한 — 화면 가로폭(물리 픽셀)보다 크게 디코드해봐야 보이지
  //      않는다. 다만 글자가 뭉개지면 안 되므로 화면 폭 그대로를 쓰되
  //      [maxDecodeWidth]까지만 올린다(태블릿·데스크톱 폭 대비).
  //   2) 총 픽셀 상한 — 세로가 길면 가로폭 상한만으로는 총량이 안 잡힌다.
  //      비율을 유지한 채 총 픽셀이 [maxDecodePixels]를 넘지 않는 가로폭으로
  //      한 번 더 줄인다.
  //
  // cacheWidth는 **줄이기만** 한다 — 원본이 더 작으면 Flutter가 그 이상으로
  // 확대 디코드하지 않으므로 화질이 나빠지는 방향의 변화는 없다.
  static const maxDecodeWidth = 1440;

  /// 약 12M 픽셀 ≒ RGBA 48MB. 세로 20:1짜리 이미지에서도 이 선을 넘지 않는다.
  static const maxDecodePixels = 12000000;

  /// 디코드 결과의 **세로 픽셀** 상한.
  ///
  /// 메모리와 별개로 걸어야 하는 선이다. 디코드된 이미지는 GPU 텍스처로
  /// 올라가는데, 텍스처 한 변의 최대 크기는 기기마다 다르고(요즘 기기는
  /// 대개 8192~16384, 오래된 기기는 4096) 이 한계를 넘으면 메모리가
  /// 남아 있어도 그림이 통째로 안 그려질 수 있다. 총 픽셀 상한만으로는
  /// 이 실패를 못 막는다 — 아주 얇고 긴 이미지는 총 픽셀이 적어도 한 변이
  /// 길기 때문이다.
  ///
  /// 8192는 실기기 대다수가 지원하는 선이면서, 캔바 상세페이지의 흔한 크기
  /// (예: 860×5000)는 손대지 않는 값이다. 이보다 긴 이미지만 비율을 유지한
  /// 채 함께 줄어든다.
  static const maxDecodeHeight = 8192;

  /// 원본 크기를 모르는(=이 기능 이전에 저장됐거나 헤더를 못 읽은) 이미지에
  /// 쓰는 보수적인 가로폭. 총 픽셀을 계산할 근거가 없으므로 낮게 잡는다.
  static const fallbackDecodeWidth = 1080;

  final String url;

  /// 원본 픽셀 크기 — 있으면 상세에서 자리(AspectRatio)를 미리 잡아 이미지가
  /// 도착할 때 화면이 튀지 않고, 디코드 상한도 여기서 계산한다.
  final double? width;
  final double? height;

  const PartyDetailImage({required this.url, this.width, this.height});

  /// 파티 문서에서 읽는다. URL이 없으면(대다수 기존 파티) null — 호출부는
  /// null이면 아무것도 그리지 않는다.
  static PartyDetailImage? fromData(Map<String, dynamic> data) {
    final url = (data[urlField] as String?)?.trim() ?? '';
    if (url.isEmpty) return null;
    final w = (data[widthField] as num?)?.toDouble();
    final h = (data[heightField] as num?)?.toDouble();
    return PartyDetailImage(
      url: url,
      width: (w != null && w > 0) ? w : null,
      height: (h != null && h > 0) ? h : null,
    );
  }

  /// 파티 문서에 쓸 필드들.
  ///
  /// [image]가 null이면 **세 필드를 모두 빈 값으로 쓴다** — 필드를 아예 빼면
  /// 수정 화면에서 상세 이미지를 지웠는데 문서에는 예전 URL이 그대로 남는다
  /// (수정 저장은 update/merge라 빠진 키를 지우지 않는다).
  static Map<String, dynamic> toFirestore(PartyDetailImage? image) => {
    urlField: image?.url ?? '',
    widthField: image?.width,
    heightField: image?.height,
  };

  /// 가로:세로. 크기를 모르면 null.
  double? get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  /// 이 이미지를 [viewWidth](논리 픽셀) 폭으로 그릴 때 쓸 디코드 가로폭.
  /// `Image.cacheWidth`에 그대로 넣는다.
  static int decodeWidthFor({
    required double viewWidth,
    required double devicePixelRatio,
    double? imageWidth,
    double? imageHeight,
  }) {
    final byScreen = (viewWidth * devicePixelRatio).round();
    var target = math.min(
      byScreen > 0 ? byScreen : fallbackDecodeWidth,
      maxDecodeWidth,
    );

    if (imageWidth == null ||
        imageHeight == null ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      return math.min(target, fallbackDecodeWidth);
    }

    // 원본보다 크게 디코드할 이유가 없다.
    target = math.min(target, imageWidth.round());

    // 비율을 유지한 채 총 픽셀을 상한 아래로: w * (w / aspect) <= budget
    //  → w <= sqrt(budget * aspect)
    final aspect = imageWidth / imageHeight;
    final byPixels = math.sqrt(maxDecodePixels * aspect).floor();
    target = math.min(target, byPixels);

    // 세로 한 변도 상한 아래로: w / aspect <= maxDecodeHeight
    final byHeight = (maxDecodeHeight * aspect).floor();
    target = math.min(target, byHeight);

    return math.max(target, 1);
  }

  /// 이 파일명이 상세 이미지로 받아들일 수 있는 확장자인가.
  static bool hasAllowedExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return false;
    return allowedExtensions.contains(path.substring(dot + 1).toLowerCase());
  }

  static const pickGuideTitle = '상세 이미지 (선택)';
  static const pickGuideBody =
      '파티를 자세히 소개하는 세로형 이미지를 등록할 수 있어요.\n'
      '캔바·미리캔버스에서 만든 상세페이지 이미지도 사용할 수 있어요.';
  static const pickGuideLimit =
      '이미지 1장 · JPG/JPEG/PNG/WebP · 최대 ${maxFileMegabytes}MB (동영상 불가)';
}
