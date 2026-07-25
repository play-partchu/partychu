import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:party_app/screens/video_trim_screen.dart';
import 'package:party_app/screens/video_crop_screen.dart';
import 'package:party_app/screens/photo_crop_screen.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 대표 미디어(cover) 선택 결과 — 업로드 완료 후 부모 화면이 최종 URL로
/// 변환해서 Firestore에 쓴다. null이면 사용자가 명시적으로 고르지 않은
/// 것이므로, 부모는 첫 번째 업로드 미디어를 기본값으로 사용해야 한다.
class PartyCoverPick {
  /// 기존(이미 업로드되어 있던) 사진을 대표로 골랐을 때 그 URL.
  final String? existingImageUrl;

  /// 기존 동영상을 대표로 골랐을 때 true.
  final bool isExistingVideo;

  /// 새로 고른 "사진" 파일들 중 몇 번째(0-based, 동영상 제외 순번)를
  /// 대표로 골랐는지 — 업로드 후 결과 imageUrls 리스트의 같은 인덱스가 최종 URL.
  final int? newImageOrdinal;

  /// 새로 고른 파일이 동영상이고 그것을 대표로 골랐으면 true.
  final bool isNewVideo;

  const PartyCoverPick({
    this.existingImageUrl,
    this.isExistingVideo = false,
    this.newImageOrdinal,
    this.isNewVideo = false,
  });
}

enum _CoverKind { existingImage, existingVideo, newFile }

class _CoverRef {
  final _CoverKind kind;
  final int index;
  const _CoverRef(this.kind, [this.index = 0]);
}

/// 파티 사진·동영상 편집 컴포넌트 — 대표 미디어(cover) 직접 선택 지원.
///
/// 사용: `GlobalKey<PartyMediaEditorState>` 로 접근.
/// 저장 시 `s.existingImageUrls`, `s.newMediaFiles`, `s.existingVideoUrl`,
/// `s.coverPick` 등을 읽어 병합·저장.
class PartyMediaEditor extends StatefulWidget {
  final List<String> initialImageUrls;
  final String? initialVideoUrl;
  final String? initialVideoUid;
  final String? initialVideoThumbnailUrl;

  /// 기존에 저장되어 있던 대표 미디어 정보 — 수정 화면 진입 시 그대로 선택된
  /// 상태로 복원하기 위함. 'image' | 'video' | null.
  final String? initialCoverMediaType;

  /// initialCoverMediaType == 'image'일 때, initialImageUrls 중 어느 것이
  /// 대표였는지 식별하기 위한 URL.
  final String? initialCoverImageUrl;

  /// 기본 카드에서 동영상이 노출될 위치(초점)/확대 배율 — 수정 화면 진입 시
  /// 이전에 저장된 값으로 복원하기 위함. 저장된 값이 없으면 기본값
  /// (0.5/0.5/1.0 — 중앙, 추가 확대 없음)을 그대로 쓴다. 작은/큰 카드는
  /// 별도 필드(videoCropX/Y/Scale)를 쓰며 이 위젯에서 건드리지 않는다.
  final double initialBasicCardFocalX;
  final double initialBasicCardFocalY;
  final double initialBasicCardScale;

  /// 기본 카드에서 "사진"이 노출될 위치(초점)/확대 배율 — 사진별로 값이
  /// 다를 수 있어(파티에 사진이 여러 장 가능) 동영상처럼 값 하나가 아니라
  /// 이미지 식별자(기존 사진은 URL, 새로 고른 로컬 파일은 그 파일의 경로)를
  /// 키로 하는 맵으로 관리한다. 값이 없는 사진은 기본값(0.5/0.5/1.0 — 중앙,
  /// 추가 확대 없음)을 쓴다.
  final Map<String, Map<String, double>> initialPhotoCrops;

  /// 대표(동영상) 미디어의 기본카드 크롭을 사용자가 이미 확정한 적이 있는지 —
  /// cropX/Y/Scale이 기본값(0.5/0.5/1.0)과 같아도 "확정했는데 우연히
  /// 중앙"인지 "아직 한 번도 안 정함"인지 값만으로는 구분할 수 없어 별도로
  /// 관리한다. 기존 파티 수정 진입 시 Firestore에 해당 필드가 저장돼 있었으면
  /// true로 넘겨준다.
  final bool initialVideoCropConfirmed;

  /// true(기본값)면 "썸네일 위치조정" 버튼을 보여주고, 대표 미디어의 크롭을
  /// 정하지 않으면 선택 완료를 막는다. 장소대여 등록/수정처럼 "기본 카드"
  /// 개념이 없는 화면은 false로 꺼서 버튼 자체를 숨기고 필수 검증도 건너뛴다
  /// (showSpotifySection과 동일한 패턴).
  final bool showVideoCropButton;

  /// 동영상 압축 시작/종료 시 호출 — 부모 화면의 버튼 비활성화 등에 사용
  final void Function(bool isCompressing)? onCompressingChanged;

  /// 사진 추가/삭제, 동영상 추가/삭제, 대표 미디어 선택 등 내부 상태가
  /// 바뀔 때마다 호출 — 부모 화면이 "작성 중인 내용이 바뀌었는지"를
  /// 판단(예: 뒤로가기 이탈 방지 확인창)하는 데 사용한다.
  final VoidCallback? onMediaChanged;

  /// 이 위젯이 별도 화면(예: 미디어 등록 픽커 화면)으로 push되어 매번 새
  /// State로 다시 만들어지는 경우, 부모가 들고 있는 "지금까지 고른 새 파일"
  /// 스냅샷을 여기로 되돌려줘서 화면을 다시 열 때마다 선택 내용이 사라지지
  /// 않게 한다. 기존처럼 항상 마운트된 채로 쓰는 곳(수정 화면 등)은 비워둔다.
  final List<XFile> initialNewMedia;

  /// 위와 동일한 이유로, 부모가 들고 있는 "지금까지 고른 대표 미디어" 스냅샷.
  /// non-null이면 [initialCoverMediaType]/[initialCoverImageUrl]보다 우선한다.
  final PartyCoverPick? initialCoverPick;

  /// 사진 업로드 최대 개수 — 화면마다 다르다(파티 8장, 장소대여 10장 등).
  final int maxImages;

  const PartyMediaEditor({
    super.key,
    this.initialImageUrls = const [],
    this.initialVideoUrl,
    this.initialVideoUid,
    this.initialVideoThumbnailUrl,
    this.initialCoverMediaType,
    this.initialCoverImageUrl,
    this.initialBasicCardFocalX = 0.5,
    this.initialBasicCardFocalY = 0.5,
    this.initialBasicCardScale = 1.0,
    this.initialPhotoCrops = const {},
    this.initialVideoCropConfirmed = false,
    this.showVideoCropButton = true,
    this.onCompressingChanged,
    this.onMediaChanged,
    this.initialNewMedia = const [],
    this.initialCoverPick,
    this.maxImages = 5,
  });

  @override
  PartyMediaEditorState createState() => PartyMediaEditorState();
}

class PartyMediaEditorState extends State<PartyMediaEditor>
    with AutomaticKeepAliveClientMixin<PartyMediaEditor> {
  // 이 위젯은 부모 화면의 긴 ListView 안에 놓이는데, 기본적으로 슬리버 리스트는
  // 화면 밖으로 스크롤되면 자식 State를 폐기했다가 다시 보일 때 새로 만든다
  // (initState 재실행 → widget.initial*로 다시 덮어써서 사용자가 방금 고른
  // 새 사진/동영상이 사라지고 기존 미디어로 되돌아가는 버그의 원인이었다).
  // AutomaticKeepAliveClientMixin으로 스크롤에 상관없이 이 State를 계속
  // 살려둬서, 기존 데이터는 최초 진입(initState) 때만 불러오고 이후 사용자가
  // 선택한 내용은 어떤 재빌드에도 덮어써지지 않게 한다.
  @override
  bool get wantKeepAlive => true;

  // 내부에서 setState가 일어날 때마다(사진/동영상 추가·삭제, 대표 미디어
  // 선택 등) 부모에게도 알린다 — 개별 호출부를 일일이 손대지 않고 한 곳에서
  // 잡아낸다.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.onMediaChanged?.call();
  }

  // ── 내부 상태 ──────────────────────────────────────────────────────────────
  late final List<String> _existingImageUrls;
  String? _existingVideoUrl;
  String? _existingVideoUid;
  String? _existingVideoThumbnailUrl;
  final List<XFile> _selectedMedia = [];
  bool _isCompressing = false;

  /// 대표 미디어 선택 — null이면 아직 고르지 않음(기본값: 첫 업로드 미디어 사용).
  _CoverRef? _cover;

  // 기본 카드에서 동영상이 노출될 위치(초점)/확대 배율 — 카드 노출 위치
  // 조정 화면(VideoCropScreen)에서만 바뀐다.
  double _basicCardFocalX = 0.5;
  double _basicCardFocalY = 0.5;
  double _basicCardScale = 1.0;

  // 기본 카드에서 "사진"이 노출될 위치(초점)/확대 배율 — 사진 식별자(기존
  // 사진은 URL, 새 로컬 파일은 경로) 별로 저장한다. 사진 크롭 편집 화면
  // (PhotoCropScreen)에서만 바뀐다.
  final Map<String, Map<String, double>> _photoCrops = {};

  // 대표(동영상) 크롭을 사용자가 확정한 적이 있는지 — [initialVideoCropConfirmed]
  // 참고. 크롭 편집 화면에서 결과를 받으면 true로 바뀌고, 기존 동영상을
  // 삭제하면(새 동영상은 다시 크롭해야 하므로) false로 되돌아간다.
  bool _videoCropConfirmed = false;

  // ── 외부에서 읽는 공개 접근자 ───────────────────────────────────────────────
  List<String> get existingImageUrls => List.unmodifiable(_existingImageUrls);
  String? get existingVideoUrl => _existingVideoUrl;
  String? get existingVideoUid => _existingVideoUid;
  String? get existingVideoThumbnailUrl => _existingVideoThumbnailUrl;
  List<XFile> get newMediaFiles => List.unmodifiable(_selectedMedia);
  bool get isCompressing => _isCompressing;
  bool get hasVideo =>
      _existingVideoUrl != null || _selectedMedia.any((f) => _isVideo(f.path));
  double get basicCardFocalX => _basicCardFocalX;
  double get basicCardFocalY => _basicCardFocalY;
  double get basicCardScale => _basicCardScale;
  Map<String, Map<String, double>> get photoCrops =>
      Map.unmodifiable(_photoCrops);
  bool get videoCropConfirmed => _videoCropConfirmed;

  /// 지금 등록/수정 흐름이 최종적으로 대표로 쓸 미디어 — 사용자가 명시적으로
  /// 고른 게 있으면 그것, 없으면 실제 등록 시 최종 결정 로직(사진 우선 →
  /// 없으면 동영상, 그중에서도 기존 미디어 → 새로 고른 파일 순)과 동일한
  /// 순서로 추정한다. 미디어가 하나도 없으면 null.
  _CoverRef? _effectiveCoverRef() {
    if (_cover != null) return _cover;
    if (_existingImageUrls.isNotEmpty) {
      return const _CoverRef(_CoverKind.existingImage, 0);
    }
    final firstNewImageIdx = _selectedMedia.indexWhere(
      (f) => !_isVideo(f.path),
    );
    if (firstNewImageIdx >= 0) {
      return _CoverRef(_CoverKind.newFile, firstNewImageIdx);
    }
    if (_existingVideoUrl != null) {
      return const _CoverRef(_CoverKind.existingVideo);
    }
    final firstNewVideoIdx = _selectedMedia.indexWhere(
      (f) => _isVideo(f.path),
    );
    if (firstNewVideoIdx >= 0) {
      return _CoverRef(_CoverKind.newFile, firstNewVideoIdx);
    }
    return null;
  }

  /// 대표로 쓰일 미디어(사진이든 동영상이든)의 기본카드 썸네일 위치가
  /// 확정됐는지 — "썸네일 위치조정" 필수 검증에 쓰인다. 미디어가 아예 없으면
  /// 조정할 대상 자체가 없으므로 true(통과).
  bool get isThumbnailCropConfirmed {
    final ref = _effectiveCoverRef();
    if (ref == null) return true;
    if (ref.kind == _CoverKind.existingVideo) return _videoCropConfirmed;
    if (ref.kind == _CoverKind.existingImage) {
      return _photoCrops.containsKey(_existingImageUrls[ref.index]);
    }
    final file = _selectedMedia[ref.index];
    if (_isVideo(file.path)) return _videoCropConfirmed;
    return _photoCrops.containsKey(file.path);
  }

  /// 사용자가 명시적으로 고른 대표 미디어 — null이면 부모가 첫 번째
  /// 업로드 미디어를 기본값으로 써야 한다.
  PartyCoverPick? get coverPick {
    final c = _cover;
    if (c == null) return null;
    switch (c.kind) {
      case _CoverKind.existingImage:
        if (c.index < 0 || c.index >= _existingImageUrls.length) return null;
        return PartyCoverPick(existingImageUrl: _existingImageUrls[c.index]);
      case _CoverKind.existingVideo:
        return _existingVideoUrl != null
            ? const PartyCoverPick(isExistingVideo: true)
            : null;
      case _CoverKind.newFile:
        if (c.index < 0 || c.index >= _selectedMedia.length) return null;
        final file = _selectedMedia[c.index];
        if (_isVideo(file.path)) {
          return const PartyCoverPick(isNewVideo: true);
        }
        // 새 이미지들 중 몇 번째(0-based)인지 계산 — 업로드 루프가 _selectedMedia
        // 순서 그대로(동영상 제외) 이미지를 올리므로, 이 순번이 곧 업로드 결과
        // imageUrls 리스트의 같은 인덱스가 된다.
        final ordinal = _selectedMedia
            .take(c.index)
            .where((f) => !_isVideo(f.path))
            .length;
        return PartyCoverPick(newImageOrdinal: ordinal);
    }
  }

  // ── 초기화 ─────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _existingImageUrls = List.from(widget.initialImageUrls);
    _existingVideoUrl = widget.initialVideoUrl;
    _existingVideoUid = widget.initialVideoUid;
    _existingVideoThumbnailUrl = widget.initialVideoThumbnailUrl;
    _selectedMedia.addAll(widget.initialNewMedia);
    _basicCardFocalX = widget.initialBasicCardFocalX;
    _basicCardFocalY = widget.initialBasicCardFocalY;
    _basicCardScale = widget.initialBasicCardScale;
    _photoCrops.addAll(widget.initialPhotoCrops);
    _videoCropConfirmed = widget.initialVideoCropConfirmed;

    // 대표 미디어 복원 — 부모가 들고 있던 스냅샷(initialCoverPick)이 있으면
    // 그걸 우선하고, 없으면(최초 진입) 기존처럼 저장된 coverMediaType/
    // coverImageUrl로 복원한다.
    final pick = widget.initialCoverPick;
    if (pick != null) {
      _cover = _coverRefFromPick(pick);
    } else if (widget.initialCoverMediaType == 'video' &&
        _existingVideoUrl != null) {
      _cover = const _CoverRef(_CoverKind.existingVideo);
    } else if (widget.initialCoverMediaType == 'image' &&
        widget.initialCoverImageUrl != null) {
      final idx = _existingImageUrls.indexOf(widget.initialCoverImageUrl!);
      if (idx >= 0) _cover = _CoverRef(_CoverKind.existingImage, idx);
    }
  }

  /// [coverPick] getter의 역변환 — 부모가 들고 있던 [PartyCoverPick] 스냅샷을
  /// 방금 세팅한 _existingImageUrls/_selectedMedia 기준 _CoverRef로 되돌린다.
  _CoverRef? _coverRefFromPick(PartyCoverPick pick) {
    if (pick.isExistingVideo) return const _CoverRef(_CoverKind.existingVideo);
    if (pick.existingImageUrl != null) {
      final idx = _existingImageUrls.indexOf(pick.existingImageUrl!);
      return idx >= 0 ? _CoverRef(_CoverKind.existingImage, idx) : null;
    }
    if (pick.isNewVideo) {
      final idx = _selectedMedia.indexWhere((f) => _isVideo(f.path));
      return idx >= 0 ? _CoverRef(_CoverKind.newFile, idx) : null;
    }
    if (pick.newImageOrdinal != null) {
      var count = 0;
      for (var i = 0; i < _selectedMedia.length; i++) {
        if (_isVideo(_selectedMedia[i].path)) continue;
        if (count == pick.newImageOrdinal) {
          return _CoverRef(_CoverKind.newFile, i);
        }
        count++;
      }
    }
    return null;
  }

  // ── 유틸 ───────────────────────────────────────────────────────────────────
  /// 부모 화면도 State가 아직 없는 첫 프레임에 같은 기준으로 판단할 수 있게
  /// static으로 열어둔다(예: 미디어 등록 화면의 동영상 권유 카드).
  static bool isVideoPath(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp4') || p.endsWith('.mov');
  }

  bool _isVideo(String path) => isVideoPath(path);

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _selectCover(_CoverRef ref) => setState(() => _cover = ref);

  // 크롭 편집 화면의 미리보기 프레임 크기 — 기본카드 실제 미디어 영역
  // (PartyStandardCard: 카드 폭 × 130)과 "가로:세로 비율"만 정확히 맞추고,
  // 화면에 보여줄 때는 화면 폭 가까이로 크게 키운다. 실제 카드 픽셀
  // 크기(약 174×130) 그대로 보여주면 손가락 드래그·핀치를 하기엔 너무
  // 작아 사실상 조작이 불가능하다 — 비율만 같으면 어느 크기로 보여줘도
  // "잘리는 지점"은 동일하므로(카드가 크든 작든 cropX/cropY/cropScale은
  // 비율 기반 값), 크게 보여줘도 WYSIWYG는 그대로 유지된다.
  Size _cardFrameSize(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final cardW = (screenW - 42) / 2; // 좌우 여백 16*2 + 카드 사이 간격 10
    const cardH = 130.0;
    final displayW = screenW - 48;
    final displayH = displayW * cardH / cardW;
    return Size(displayW, displayH);
  }

  Future<void> _pushCropEditor({String? videoUrl, File? videoFile}) async {
    final frameSize = _cardFrameSize(context);
    final result = await Navigator.push<Map<String, double>>(
      context,
      webFramedRoute((_) => VideoCropScreen(
          videoUrl: videoUrl,
          videoFile: videoFile,
          frameWidth: frameSize.width,
          frameHeight: frameSize.height,
          initialCropX: _basicCardFocalX,
          initialCropY: _basicCardFocalY,
          initialCropScale: _basicCardScale,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == null) return;
    setState(() {
      _basicCardFocalX = result['cropX'] ?? 0.5;
      _basicCardFocalY = result['cropY'] ?? 0.5;
      _basicCardScale = result['cropScale'] ?? 1.0;
      _videoCropConfirmed = true;
    });
  }

  /// 사진 하나의 기본 카드 크롭을 조정한다. [cropKey]는 그 사진의 식별자 —
  /// 기존(네트워크) 사진은 URL을, 새로 고른 로컬 파일은 그 파일의 경로를
  /// 그대로 쓴다(둘 다 세션 내내 안정적으로 유지되는 값).
  Future<void> _pushPhotoCropEditor({
    String? imageUrl,
    File? imageFile,
    required String cropKey,
  }) async {
    final frameSize = _cardFrameSize(context);
    final existing = _photoCrops[cropKey];
    final result = await Navigator.push<Map<String, double>>(
      context,
      webFramedRoute((_) => PhotoCropScreen(
          imageUrl: imageUrl,
          imageFile: imageFile,
          frameWidth: frameSize.width,
          frameHeight: frameSize.height,
          initialCropX: existing?['x'] ?? 0.5,
          initialCropY: existing?['y'] ?? 0.5,
          initialCropScale: existing?['scale'] ?? 1.0,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == null) return;
    setState(() {
      _photoCrops[cropKey] = {
        'x': result['cropX'] ?? 0.5,
        'y': result['cropY'] ?? 0.5,
        'scale': result['cropScale'] ?? 1.0,
      };
    });
  }

  /// "썸네일 위치조정" 버튼 — 지금 대표로 쓰일 미디어([_effectiveCoverRef])의
  /// 크롭 편집 화면을 연다. 대표가 사진이면 [_pushPhotoCropEditor], 동영상이면
  /// [_pushCropEditor]로 위임한다.
  Future<void> _openThumbnailCropEditor() async {
    final ref = _effectiveCoverRef();
    if (ref == null) return;
    if (ref.kind == _CoverKind.existingVideo) {
      await _pushCropEditor(videoUrl: _existingVideoUrl);
      return;
    }
    if (ref.kind == _CoverKind.existingImage) {
      final url = _existingImageUrls[ref.index];
      await _pushPhotoCropEditor(imageUrl: url, cropKey: url);
      return;
    }
    final file = _selectedMedia[ref.index];
    if (_isVideo(file.path)) {
      await _pushCropEditor(videoFile: File(file.path));
    } else {
      await _pushPhotoCropEditor(imageFile: File(file.path), cropKey: file.path);
    }
  }

  /// 목록에서 미디어 하나가 삭제됐을 때, 대표 선택이 그 항목을 가리키고
  /// 있었으면 해제하고, 뒤쪽 인덱스를 가리키고 있었으면 한 칸 당겨준다.
  void _adjustCoverAfterRemoval(_CoverKind kind, int removedIdx) {
    final c = _cover;
    if (c == null || c.kind != kind) return;
    if (c.index == removedIdx) {
      _cover = null;
    } else if (c.index > removedIdx) {
      _cover = _CoverRef(kind, c.index - 1);
    }
  }

  // ── 미디어 선택 ────────────────────────────────────────────────────────────
  Future<void> pickMedia() async {
    final files = await ImagePicker().pickMultipleMedia();

    for (final file in files) {
      final isVid = _isVideo(file.path);

      if (isVid) {
        if (hasVideo) {
          _msg('동영상은 1개만 업로드 가능해요');
          continue;
        }

        final ctrl = VideoPlayerController.file(File(file.path));
        await ctrl.initialize();
        final secs = ctrl.value.duration.inSeconds;
        await ctrl.dispose();

        // 30초를 넘으면 업로드를 막는 대신, 앱 안에서 바로 30초 이내로 잘라낼
        // 수 있게 편집 화면으로 보낸다. 서버에 원본을 올리고 자르는 방식이
        // 아니라, 여기서 잘라낸 결과 파일만 이후 압축·업로드로 넘긴다.
        var videoToUpload = file;
        if (secs > 30) {
          if (!mounted) return;
          final trimmedPath = await Navigator.push<String>(
            context,
            webFramedRoute((_) => VideoTrimScreen(sourceFile: File(file.path)),
              fullscreenDialog: true,
            ),
          );
          debugPrint('[MediaEditor] 부모 화면에서 전달받은 편집 파일 경로: $trimmedPath');
          if (trimmedPath == null) continue; // 사용자가 편집을 취소함
          videoToUpload = XFile(trimmedPath);
        }

        if (!mounted) return;
        setState(() => _isCompressing = true);
        widget.onCompressingChanged?.call(true);
        debugPrint('[MediaEditor] 압축 시작 — 대상 파일: ${videoToUpload.path}');
        final compressed = await _compressVideo(videoToUpload);
        debugPrint(
          '[MediaEditor] 압축 완료 — 결과: '
          '${compressed?.path ?? "실패(압축본 없음) → 편집/원본 파일을 그대로 사용"}',
        );
        if (!mounted) return;
        setState(() => _isCompressing = false);
        widget.onCompressingChanged?.call(false);
        // 압축은 어디까지나 최적화일 뿐 — 실패해도 사용자가 방금 고르거나
        // 편집한 영상 자체를 등록 화면에서 잃어버리면 안 된다. 압축이
        // 실패하면 압축 전 파일(편집본 또는 원본)을 그대로 등록 흐름에 태운다.
        final finalVideo = compressed ?? videoToUpload;
        debugPrint(
          '[MediaEditor] 미리보기 상태(_selectedMedia)에 추가 — path=${finalVideo.path}',
        );
        setState(() => _selectedMedia.add(finalVideo));
      } else {
        final imgCnt =
            _existingImageUrls.length +
            _selectedMedia.where((f) => !_isVideo(f.path)).length;
        if (imgCnt >= widget.maxImages) {
          _msg('사진은 최대 ${widget.maxImages}장까지 업로드 가능해요');
          continue;
        }
        setState(() => _selectedMedia.add(file));
      }
    }
  }

  Future<XFile?> _compressVideo(XFile file) async {
    final srcExists = File(file.path).existsSync();
    debugPrint(
      '[MediaEditor] _compressVideo 입력 파일 exists=$srcExists path=${file.path}',
    );
    if (!srcExists) {
      debugPrint('[MediaEditor] 압축 대상 파일이 존재하지 않음 — 압축 건너뜀');
      return null;
    }
    try {
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );
      final resultPath = info?.path;
      debugPrint('[MediaEditor] VideoCompress 결과 path=$resultPath');
      return resultPath != null ? XFile(resultPath) : null;
    } catch (e) {
      debugPrint('[MediaEditor] 압축 오류: $e');
      return null;
    }
  }

  // ── 빌드 ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 필수 호출
    final hasExisting =
        _existingImageUrls.isNotEmpty || _existingVideoUrl != null;
    final totalMediaCount =
        _existingImageUrls.length +
        (_existingVideoUrl != null ? 1 : 0) +
        _selectedMedia.length;

    Widget closeDot(VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, size: 16, color: Colors.white),
      ),
    );

    Widget badge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    // 모든 타일이 공유하는 "대표 선택" 오버레이 — 핑크 테두리 + 체크 아이콘 + 배지.
    Widget coverOverlay(bool isSelected) => isSelected
        ? const Positioned(
            top: 4,
            left: 4,
            child: Icon(Icons.check_circle, color: Color(0xFFFF6FA0), size: 20),
          )
        : const SizedBox.shrink();

    BoxDecoration tileDecoration(
      bool isSelected, {
      Color base = Colors.black12,
    }) => BoxDecoration(
      color: base,
      borderRadius: BorderRadius.circular(8),
      border: isSelected
          ? Border.all(color: const Color(0xFFFF6FA0), width: 3)
          : null,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 압축 중 표시
          if (_isCompressing)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF7C5CBF),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '동영상 압축 중...',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // ① 기존 이미지 (네트워크) ──────────────────────────────────
              ..._existingImageUrls.asMap().entries.map((e) {
                final idx = e.key;
                final url = e.value;
                final isSelected =
                    _cover?.kind == _CoverKind.existingImage &&
                    _cover!.index == idx;
                return GestureDetector(
                  onTap: () =>
                      _selectCover(_CoverRef(_CoverKind.existingImage, idx)),
                  child: Stack(
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: tileDecoration(isSelected),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.black26,
                            ),
                          ),
                        ),
                      ),
                      coverOverlay(isSelected),
                      if (isSelected)
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: badge('대표', const Color(0xFFFF6FA0)),
                        ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: closeDot(
                          () => setState(() {
                            _photoCrops.remove(url);
                            _existingImageUrls.removeAt(idx);
                            _adjustCoverAfterRemoval(
                              _CoverKind.existingImage,
                              idx,
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              // ② 기존 동영상 ─────────────────────────────────────────────
              if (_existingVideoUrl != null)
                ...(() {
                  final isSelected = _cover?.kind == _CoverKind.existingVideo;
                  return [
                    GestureDetector(
                      onTap: () => _selectCover(
                        const _CoverRef(_CoverKind.existingVideo),
                      ),
                      child: Stack(
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: tileDecoration(
                              isSelected,
                              base: Colors.black,
                            ),
                            child: _existingVideoThumbnailUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      _existingVideoThumbnailUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Center(
                                        child: Icon(
                                          Icons.videocam,
                                          size: 28,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  )
                                : const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.videocam,
                                          size: 28,
                                          color: Colors.white,
                                        ),
                                        Text(
                                          '동영상',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                          // 재생 아이콘 — 동영상 타일임을 항상 알 수 있게.
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill,
                              color: Colors.white70,
                              size: 22,
                            ),
                          ),
                          coverOverlay(isSelected),
                          Positioned(
                            bottom: 4,
                            left: 4,
                            child: isSelected
                                ? badge('대표', const Color(0xFFFF6FA0))
                                : badge(
                                    'Stream',
                                    Colors.deepOrange.withValues(alpha: 0.85),
                                  ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: closeDot(
                              () => setState(() {
                                _existingVideoUrl = null;
                                _existingVideoUid = null;
                                _existingVideoThumbnailUrl = null;
                                _videoCropConfirmed = false;
                                if (_cover?.kind == _CoverKind.existingVideo) {
                                  _cover = null;
                                }
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ];
                })(),

              // ③ 새로 선택한 로컬 파일 ──────────────────────────────────
              ..._selectedMedia.asMap().entries.map((entry) {
                final i = entry.key;
                final file = entry.value;
                final isVid = _isVideo(file.path);
                final isSelected =
                    _cover?.kind == _CoverKind.newFile && _cover!.index == i;
                return GestureDetector(
                  onTap: () => _selectCover(_CoverRef(_CoverKind.newFile, i)),
                  child: Stack(
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: tileDecoration(isSelected),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: isVid
                              ? const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.videocam,
                                        size: 28,
                                        color: Colors.white,
                                      ),
                                      Text(
                                        '동영상',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Image.file(File(file.path), fit: BoxFit.cover),
                        ),
                      ),
                      coverOverlay(isSelected),
                      if (isSelected)
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: badge('대표', const Color(0xFFFF6FA0)),
                        )
                      else if (isVid)
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: badge(
                            'Stream',
                            Colors.deepOrange.withValues(alpha: 0.85),
                          ),
                        ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: closeDot(
                          () => setState(() {
                            _photoCrops.remove(file.path);
                            if (isVid) _videoCropConfirmed = false;
                            _selectedMedia.removeAt(i);
                            _adjustCoverAfterRemoval(_CoverKind.newFile, i);
                          }),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              // ④ 추가 버튼 ───────────────────────────────────────────────
              GestureDetector(
                onTap: pickMedia,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 28),
                      SizedBox(height: 4),
                      Text('사진/동영상', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 힌트 문구 — "대표 사진 먼저 선택"을 아래 "썸네일 위치조정(필수)"
          // 버튼보다 먼저 눈에 띄게 알려준다. 미디어가 1개뿐이어도(예전엔
          // totalMediaCount > 1일 때만 보였다) 사용자가 탭해서 명시적으로
          // 고르기 전까진 계속 보여야, 곧바로 "썸네일 위치조정"부터 눌러
          // 헷갈리는 일이 없다.
          if (!hasExisting && _selectedMedia.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '사진 최대 ${widget.maxImages}장 · 동영상 최대 30초\n'
              '대표 미디어를 선택하면 목록에 그 사진(또는 영상)이 표시돼요.',
              style: const TextStyle(fontSize: 11, color: Colors.black38),
            ),
          ] else if (totalMediaCount >= 1) ...[
            const SizedBox(height: 10),
            if (_cover == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.touch_app, size: 16, color: Color(0xFFFF6FA0)),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '위 사진·동영상 중 대표로 쓸 것을 먼저 탭해서 선택해주세요. 선택하지 않으면 첫 번째로 등록한 미디어가 자동으로 대표가 돼요.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFFF6FA0),
                          fontWeight: FontWeight.bold,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              const Text(
                '사진·동영상을 탭하면 대표 미디어를 바꿀 수 있어요.',
                style: TextStyle(fontSize: 11, color: Colors.black38),
              ),
          ],

          // 썸네일 위치조정 — 기본카드에 실제로 노출될 대표 미디어의 크롭을
          // 정하는 단일 진입점. 사진/동영상 구분 없이 이 버튼 하나로 통일하고,
          // 정하지 않으면 "선택 완료"를 막는다(PartyMediaPickerScreen 참고).
          if (widget.showVideoCropButton && totalMediaCount > 0) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openThumbnailCropEditor,
                icon: Icon(
                  isThumbnailCropConfirmed
                      ? Icons.check_circle_outline
                      : Icons.crop,
                  size: 18,
                  color: isThumbnailCropConfirmed
                      ? const Color(0xFFFF6FA0)
                      : const Color(0xFFE53935),
                ),
                label: Text(
                  isThumbnailCropConfirmed ? '썸네일 위치조정 완료' : '썸네일 위치조정 (필수)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isThumbnailCropConfirmed
                      ? const Color(0xFFFF6FA0)
                      : const Color(0xFFE53935),
                  side: BorderSide(
                    color: isThumbnailCropConfirmed
                        ? const Color(0xFFFF6FA0)
                        : const Color(0xFFE53935),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
