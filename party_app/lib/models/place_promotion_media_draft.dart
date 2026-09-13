import 'package:image_picker/image_picker.dart' show XFile;
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/widgets/party_media_editor.dart' show PartyCoverPick;

/// **저장 전에만 사는** 매장 이벤트 미디어 초안.
///
/// 플레이스·매장을 **처음 등록하는 중**에는 아직 문서가 없어서 이벤트 사진을
/// 곧바로 올릴 수 없다. 그래서 고른 파일을 여기 담아 두고, 장소 문서가 만들어진
/// 직후 [PlacePromotionSection.save]가 공용 업로더로 한 번에 올린다 — 메뉴 사진이
/// `PlaceMenu.localImagePath`로 하는 것과 **같은 방식**이다.
///
/// ⚠️ Firestore에 **절대 쓰지 않는다.** [PlacePromotion.toMap]이 이 값을 담지
///    않으므로 문서 구조는 그대로다.
///
/// 값의 모양은 공용 미디어 편집 화면이 돌려주는 스냅샷
/// ([PartyMediaSelection])을 그대로 옮긴 것이다. 새로 만든 규칙이 아니라, 파티·
/// 플레이스 등록이 이미 쓰는 그 스냅샷을 이벤트 한 건 단위로 들고 있는 것뿐이다.
class PlacePromotionMediaDraft {
  const PlacePromotionMediaDraft({
    this.newMediaPaths = const [],
    this.coverPick,
    this.photoCrops = const {},
  });

  /// 갤러리에서 고른 새 파일들의 로컬 경로 — 사진과 (최대 1개) 동영상이
  /// **고른 순서 그대로** 섞여 있다. 어느 쪽인지는 업로더가 가른다
  /// ([MediaUploadService.isVideoFile]와 같은 기준).
  ///
  /// 경로만 담는 이유는 이 상자가 다른 초안들과 함께 값으로만 오가기
  /// 때문이다. 경로에서 파일을 되찾는 일은 [newMedia]가 [LocalMedia]를 통해
  /// 하므로, 웹의 blob URL도 원본 이름·형식을 잃지 않는다.
  final List<String> newMediaPaths;

  /// 호스트가 고른 대표 미디어. null이면 고르지 않은 것이고, 그때는 공용
  /// 헬퍼([MediaUploadService.resolveCoverFields])의 기본값(사진 우선 →
  /// 없으면 동영상)이 그대로 적용된다.
  final PartyCoverPick? coverPick;

  /// 로컬 경로 → 기본 카드 크롭({x, y, scale}). 업로드가 끝나면
  /// [MediaUploadService.resolvePhotoCropKeys]가 최종 URL 키로 옮겨 담는다.
  final Map<String, Map<String, double>> photoCrops;

  bool get isEmpty => newMediaPaths.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// 경로에서 되살린 파일들 — 업로더에 넘기는 것도, 미리보기를 그리는 것도
  /// 전부 이 목록 하나를 쓴다.
  List<XFile> get newMedia => LocalMedia.resolveAll(newMediaPaths);

  /// 사진만 — 화면에 미리보기를 그릴 때 쓴다.
  List<XFile> get imageFiles =>
      [for (final f in newMedia) if (!isVideoFile(f)) f];

  XFile? get videoFile {
    for (final f in newMedia) {
      if (isVideoFile(f)) return f;
    }
    return null;
  }

  /// 어느 파일이 동영상인지는 **업로더의 판정 하나**를 그대로 부른다 —
  /// 여기서 확장자 목록을 다시 적으면 한쪽만 늘어났을 때 동영상을 사진으로
  /// 오인해 이미지 업로더로 보낸다.
  static bool isVideoFile(XFile file) => MediaUploadService.isVideoFile(file);
}
