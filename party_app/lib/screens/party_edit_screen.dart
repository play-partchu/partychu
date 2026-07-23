import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:party_app/models/party_auto_description_style.dart';
import 'package:party_app/models/party_description_mode.dart';
import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/party_detail_decoration_intensity.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/models/party_constants.dart';
import 'package:party_app/models/spotify_track.dart';
import 'package:party_app/screens/party_detail_block_editor_screen.dart';
import 'package:party_app/screens/party_intro_screen.dart';
import 'package:party_app/screens/party_media_picker_screen.dart';
import 'package:party_app/screens/party_refund_policy_screen.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/widgets/party_form/fee_sheet.dart';
import 'package:party_app/widgets/party_form/gender_capacity_sheet.dart';
import 'package:party_app/widgets/party_form/party_detail_block_draft.dart';
import 'package:party_app/widgets/party_form/party_detail_description_mode_sheet.dart';
import 'package:party_app/widgets/party_form/party_title_field.dart';
import 'package:party_app/widgets/party_form/party_type_vibe_sheet.dart';
import 'package:party_app/widgets/party_form/section_summary_row.dart';
import 'package:party_app/widgets/party_media_editor.dart' show PartyCoverPick;

class PartyEditScreen extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const PartyEditScreen({super.key, required this.docId, required this.data});

  @override
  State<PartyEditScreen> createState() => _PartyEditScreenState();
}

class _PartyEditScreenState extends State<PartyEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final PartyTitleController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _capacityController;
  late final TextEditingController _maleFeeController;
  late final TextEditingController _femaleFeeController;
  final TextEditingController _earlyBirdPercentController =
      TextEditingController();
  // 환불 규정 — 호스트가 직접 등록하는 기간별 환불률 구간.
  List<RefundTier> _refundTiers = [];
  late Set<String> _partyTypes;
  late Set<String> _vibes;
  late List<String> _tags;
  late String _recruitStatus;
  late String _genderLimit;

  final List<String> _statuses = ['모집중', '마감', '취소'];

  // ── 미디어 — PartyMediaPickerScreen을 pop할 때만 갱신되는 스냅샷.
  List<String> _mediaExistingImageUrls = [];
  String? _mediaExistingVideoUrl;
  String? _mediaExistingVideoUid;
  String? _mediaExistingVideoThumbnailUrl;
  List<XFile> _mediaNewFiles = [];
  PartyCoverPick? _mediaCoverPick;
  double _mediaBasicCardFocalX = 0.5;
  double _mediaBasicCardFocalY = 0.5;
  double _mediaBasicCardScale = 1.0;
  Map<String, Map<String, double>> _mediaPhotoCrops = {};
  bool _mediaVideoCropConfirmed = false;

  // 사진만 등록된 파티에 붙일 수 있는 Spotify 미리듣기 트랙(선택 사항).
  SpotifyTrack? _selectedSpotifyTrack;

  // 상세 설명 방식 — 간편 자동 꾸미기(auto) / 직접 상세페이지 만들기(blocks)
  // 중 하나만 실제로 렌더링된다. initState에서 기존 파티 데이터로 초기화된다.
  PartyDescriptionMode _descriptionMode = PartyDescriptionMode.auto;
  PartyAutoDescriptionStyle _autoDescriptionStyle = const PartyAutoDescriptionStyle();

  // 파티 상세페이지 블록("직접 상세페이지 만들기"를 골랐을 때만 쓰인다) —
  // 모드를 auto로 바꿔도 지우지 않고 그대로 들고 있다가, 다시 blocks로
  // 돌아오면 이어서 편집할 수 있게 한다.
  List<PartyDetailBlockDraft> _detailBlocks = [];
  PartyDetailThemeKey _detailTheme = PartyDetailThemeKey.partychu;
  PartyDetailDecorationIntensity _detailDecorationIntensity = PartyDetailDecorationIntensity.standard;
  int _detailDecorationVariantSeed = 0;

  bool _isSaving = false;
  String _uploadStatus = '';

  // 필수항목 에러 표시 — 각 SectionSummaryRow의 빨간 테두리를 켠다.
  bool _showCapacityError = false;
  bool _showFeeError = false;
  bool _showIntroError = false;
  bool _showMediaCoverError = false;

  // ── 얼리버드 할인 ─────────────────────────────────────────────────
  bool _earlyBirdEnabled = false;
  DateTime? _earlyBirdEndDate;
  TimeOfDay? _earlyBirdEndTime;

  @override
  void initState() {
    super.initState();
    final d = widget.data;

    _titleController = PartyTitleController(text: d['title'] as String? ?? '');
    _descController = TextEditingController(
      text: d['description'] as String? ?? '',
    );
    _capacityController = TextEditingController(
      text: (d['maxParticipants'] as int?)?.toString() ?? '',
    );
    _genderLimit = d['genderLimit'] as String? ?? 'all';
    _maleFeeController = TextEditingController(
      text: (d['maleFee'] as num?)?.toInt().toString() ?? '',
    );
    _femaleFeeController = TextEditingController(
      text: (d['femaleFee'] as num?)?.toInt().toString() ?? '',
    );
    _refundTiers = RefundTier.listFromDynamic(d['refundPolicy']);
    _partyTypes = ((d['partyTypes'] as List?)?.cast<String>() ?? []).toSet();
    _vibes = ((d['vibes'] as List?)?.cast<String>() ?? []).toSet();
    _tags = List<String>.from((d['tags'] as List?)?.cast<String>() ?? []);
    _recruitStatus = d['recruitStatus'] as String? ?? '모집중';
    if (!_statuses.contains(_recruitStatus)) _recruitStatus = '모집중';

    // ── 기존 미디어 URL 추출 ──────────────────────────────────────────
    final imgs = <String>[];
    imgs.addAll((d['images'] as List?)?.cast<String>() ?? []);
    if (imgs.isEmpty) {
      imgs.addAll((d['imageUrls'] as List?)?.cast<String>() ?? []);
    }
    final mainImg = d['mainImageUrl'] as String?;
    if (mainImg != null && mainImg.isNotEmpty && !imgs.contains(mainImg)) {
      imgs.insert(0, mainImg);
    }
    _mediaExistingImageUrls = imgs.where((u) => u.isNotEmpty).toList();
    _mediaExistingVideoUrl = d['videoUrl'] as String?;
    _mediaExistingVideoUid = d['videoUid'] as String?;
    _mediaExistingVideoThumbnailUrl = d['videoThumbnailUrl'] as String?;

    // 기존에 저장된 대표 미디어 선택 상태 복원 — PartyCoverPick 하나로 통일.
    final existingCoverMediaType = d['coverMediaType'] as String?;
    final existingCoverImageUrl = d['coverImageUrl'] as String?;
    if (existingCoverMediaType == 'video') {
      _mediaCoverPick = const PartyCoverPick(isExistingVideo: true);
    } else if (existingCoverMediaType == 'image' &&
        existingCoverImageUrl != null) {
      _mediaCoverPick = PartyCoverPick(existingImageUrl: existingCoverImageUrl);
    }

    // 기존에 저장된 기본카드 동영상 노출 위치(크롭) 복원 — 없으면 기본값 유지.
    _mediaBasicCardFocalX =
        (d['basicCardVideoFocalX'] as num?)?.toDouble() ?? 0.5;
    _mediaBasicCardFocalY =
        (d['basicCardVideoFocalY'] as num?)?.toDouble() ?? 0.5;
    _mediaBasicCardScale =
        (d['basicCardVideoScale'] as num?)?.toDouble() ?? 1.0;
    // Firestore에 이 필드가 실제로 저장돼 있었는지(=이전에 "썸네일
    // 위치조정"을 한 번이라도 완료했는지)로 확정 여부를 판단한다 — 값
    // 자체(0.5/0.5/1.0)만으로는 "확정했는데 우연히 중앙"인지 "아직 한 번도
    // 안 정함"인지 구분할 수 없기 때문.
    _mediaVideoCropConfirmed = d.containsKey('basicCardVideoFocalX');

    // 기존에 저장된 기본카드 사진 노출 위치(크롭) 복원 — 사진 URL별 맵.
    final rawPhotoCrops = d['basicCardPhotoCrops'] as Map?;
    if (rawPhotoCrops != null) {
      _mediaPhotoCrops = rawPhotoCrops.map(
        (key, value) => MapEntry(key as String, {
          'x': ((value as Map)['x'] as num?)?.toDouble() ?? 0.5,
          'y': (value['y'] as num?)?.toDouble() ?? 0.5,
          'scale': (value['scale'] as num?)?.toDouble() ?? 1.0,
        }),
      );
    }

    // 기존에 저장된 Spotify 미리듣기 트랙 복원.
    final spotifyPreviewUrl = d['spotifyPreviewUrl'] as String?;
    if (spotifyPreviewUrl != null && spotifyPreviewUrl.isNotEmpty) {
      _selectedSpotifyTrack = SpotifyTrack(
        id: d['spotifyTrackId'] as String? ?? '',
        name: d['spotifyTrackName'] as String? ?? '',
        artistNames: d['spotifyArtistName'] as String? ?? '',
        albumArtUrl: d['spotifyAlbumArt'] as String?,
        previewUrl: spotifyPreviewUrl,
      );
    }

    // 얼리버드 할인 — 만료 여부와 무관하게 기존 설정을 그대로 불러와 수정 가능하게 한다.
    _earlyBirdEnabled = d['earlyBirdEnabled'] as bool? ?? false;
    final earlyBirdEndTs = d['earlyBirdEndAt'] as Timestamp?;
    if (_earlyBirdEnabled && earlyBirdEndTs != null) {
      _earlyBirdPercentController.text =
          '${(d['earlyBirdDiscountPercent'] as num?)?.toInt() ?? 10}';
      final endDt = earlyBirdEndTs.toDate();
      _earlyBirdEndDate = DateTime(endDt.year, endDt.month, endDt.day);
      _earlyBirdEndTime = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
    } else {
      _earlyBirdEnabled = false;
    }

    // 기존에 저장된 상세페이지 블록 복원 — 필드가 없는 기존 파티는 빈 리스트.
    _detailBlocks = PartyDetailBlock.listFromDynamic(d['detailBlocks'])
        .map((b) => PartyDetailBlockDraft.fromBlock(b))
        .toList();
    // 기존에 저장된 디자인 테마 복원 — 없거나 알 수 없는 값이면 partychu.
    _detailTheme = partyDetailThemeKeyFromString(d['detailTheme'] as String?);
    _detailDecorationIntensity = partyDetailDecorationIntensityFromString(
      d['detailDecorationIntensity'] as String?,
    );
    // 필드가 없으면(이 기능 이전에 등록된 파티) 0 — 지금까지 암묵적으로
    // 써온 시드와 같아 회귀 없이 그대로 렌더링된다.
    _detailDecorationVariantSeed = (d['detailDecorationVariantSeed'] as num?)?.toInt() ?? 0;
    // 상세 설명 방식 복원 — 필드가 없는(이 기능 이전에 등록된) 파티는
    // detailBlocks 유무로 추론한다("블록형 상세페이지를 작성한 데이터가
    // 있으면 수정 화면은 '직접 상세페이지 만들기'로 열림" 요구사항).
    final descriptionModeRaw = d['detailDescriptionMode'] as String?;
    _descriptionMode = descriptionModeRaw != null
        ? partyDescriptionModeFromString(descriptionModeRaw)
        : (_detailBlocks.isNotEmpty ? PartyDescriptionMode.blocks : PartyDescriptionMode.auto);
    _autoDescriptionStyle = PartyAutoDescriptionStyle.fromMap(
      d['autoDescriptionStyle'] as Map<String, dynamic>?,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _capacityController.dispose();
    _maleFeeController.dispose();
    _femaleFeeController.dispose();
    _earlyBirdPercentController.dispose();
    for (final d in _detailBlocks) {
      d.dispose();
    }
    super.dispose();
  }

  bool get _mediaHasVideo =>
      _mediaExistingVideoUrl != null || _mediaNewFiles.any(_isVideoFile);

  static bool _isVideoFile(XFile f) {
    final p = f.path.toLowerCase();
    return p.endsWith('.mp4') || p.endsWith('.mov');
  }

  /// 저장 직전 로컬 파일 경로로 저장돼 있던 사진 크롭 값을, 업로드로 갓
  /// 발급받은 최종 URL 키로 옮겨 담는다. 기존(네트워크) 사진은 URL이 그대로
  /// 유지되므로 옮길 필요 없이 그대로 합친다.
  Map<String, Map<String, double>> _resolvePhotoCrops(
    List<String> newImageUrls,
  ) {
    final result = <String, Map<String, double>>{};
    for (final url in _mediaExistingImageUrls) {
      final c = _mediaPhotoCrops[url];
      if (c != null) result[url] = c;
    }
    var ordinal = 0;
    for (final file in _mediaNewFiles) {
      if (_isVideoFile(file)) continue;
      final c = _mediaPhotoCrops[file.path];
      if (c != null && ordinal < newImageUrls.length) {
        result[newImageUrls[ordinal]] = c;
      }
      ordinal++;
    }
    return result;
  }

  /// 얼리버드 할인 입력값 검증. 문제 없으면 null 반환.
  String? _validateEarlyBird() {
    final pct = int.tryParse(_earlyBirdPercentController.text.trim());
    if (pct == null || pct < 1 || pct > 99) {
      return '얼리버드 할인율은 1~99% 사이로 입력해주세요.';
    }
    if (_earlyBirdEndDate == null || _earlyBirdEndTime == null) {
      return '얼리버드 종료일과 시간을 선택해주세요.';
    }
    final endAt = DateTime(
      _earlyBirdEndDate!.year,
      _earlyBirdEndDate!.month,
      _earlyBirdEndDate!.day,
      _earlyBirdEndTime!.hour,
      _earlyBirdEndTime!.minute,
    );
    if (!endAt.isAfter(DateTime.now())) {
      return '얼리버드 종료 시각은 현재 시간 이후여야 합니다.';
    }
    final maleFee = _genderLimit != 'female'
        ? (int.tryParse(_maleFeeController.text.trim()) ?? 0)
        : 0;
    final femaleFee = _genderLimit != 'male'
        ? (int.tryParse(_femaleFeeController.text.trim()) ?? 0)
        : 0;
    if (maleFee <= 0 && femaleFee <= 0) {
      return '무료 파티는 얼리버드 할인을 사용할 수 없습니다.';
    }
    return null;
  }

  Future<void> _save() async {
    final formValid = _formKey.currentState!.validate();
    final capacityError = _capacityController.text.trim().isEmpty;
    final maleFeeError =
        _genderLimit != 'female' && _maleFeeController.text.trim().isEmpty;
    final femaleFeeError =
        _genderLimit != 'male' && _femaleFeeController.text.trim().isEmpty;
    final introError = _descController.text.trim().isEmpty;
    // 사진/동영상이 2개 이상 등록됐는데 그중 대표를 직접 고르지 않았으면
    // 막는다 — 1개뿐이면 고를 것도 없으니 그대로 자동 대표 처리한다.
    final mediaCoverError = _totalMediaCount() > 1 && _mediaCoverPick == null;

    String? earlyBirdErr;
    if (_earlyBirdEnabled) {
      earlyBirdErr = _validateEarlyBird();
    }

    setState(() {
      _showCapacityError = capacityError;
      _showFeeError = maleFeeError || femaleFeeError || earlyBirdErr != null;
      _showIntroError = introError;
      _showMediaCoverError = mediaCoverError;
    });

    if (!formValid ||
        capacityError ||
        maleFeeError ||
        femaleFeeError ||
        introError ||
        mediaCoverError) {
      return;
    }
    if (earlyBirdErr != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(earlyBirdErr)));
      return;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final partyHostUid =
        widget.data['hostUid'] as String? ??
        widget.data['hostId'] as String? ??
        '';
    if (currentUid.isEmpty || partyHostUid != currentUid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('작성자만 수정할 수 있습니다.')));
      return;
    }

    if (!CloudflareService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('파일 업로드 서비스를 사용할 수 없습니다. 잠시 후 다시 시도해주세요.'),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _uploadStatus = '저장을 준비하는 중...';
    });

    // 이번 저장에서 새로 R2/Stream에 업로드된 상세페이지 블록 사진·동영상 —
    // 이후 Firestore 저장이 실패하면 catch에서 이 목록만 롤백 삭제한다.
    final uploadedBlockImageUrls = <String>[];
    final uploadedBlockVideoUids = <String>[];

    try {
      final newMedia = _mediaNewFiles;

      // ── 새 미디어 업로드 ────────────────────────────────────────────
      final newImageUrls = <String>[];
      String? newVideoUid;
      String? newVideoUrl;
      String? newVideoThumbnailUrl;

      int done = 0;
      for (final file in newMedia) {
        final isVideo =
            file.path.toLowerCase().endsWith('.mp4') ||
            file.path.toLowerCase().endsWith('.mov');
        if (isVideo) {
          setState(() => _uploadStatus = '동영상을 올리는 중...');
          debugPrint(
            '[Edit] 업로드 시작(동영상) — path=${file.path}, '
            'exists=${File(file.path).existsSync()}',
          );
          final result = await CloudflareService.uploadVideo(File(file.path));
          newVideoUid = result['videoUid'];
          newVideoUrl = result['videoUrl'];
          newVideoThumbnailUrl = result['videoThumbnailUrl'];
        } else {
          done++;
          setState(
            () => _uploadStatus = '사진을 올리는 중... ($done/${newMedia.length})',
          );
          final url = await CloudflareService.uploadImage(File(file.path));
          newImageUrls.add(url);
        }
      }

      // ── 병합 ────────────────────────────────────────────────────────
      final allImages = [..._mediaExistingImageUrls, ...newImageUrls];
      final finalVideoUrl = newVideoUrl ?? _mediaExistingVideoUrl;
      final finalVideoUid = newVideoUid ?? _mediaExistingVideoUid;
      final finalThumbUrl =
          newVideoThumbnailUrl ?? _mediaExistingVideoThumbnailUrl;

      // 대표 미디어 — 사용자가 명시적으로 골랐으면 그 값을 그대로 신뢰하고,
      // 고르지 않았다면(coverPick == null) 첫 번째 업로드 미디어를 기본값으로
      // 쓴다(이미지가 있으면 이미지 우선, 없으면 동영상).
      final coverPick = _mediaCoverPick;
      String coverMediaType = 'image';
      String? coverImageUrl;
      String? coverVideoUid;
      String? coverVideoUrl;
      String? coverThumbnailUrl;
      if (coverPick?.isExistingVideo == true || coverPick?.isNewVideo == true) {
        coverMediaType = 'video';
        coverVideoUid = finalVideoUid;
        coverVideoUrl = finalVideoUrl;
        coverThumbnailUrl = finalThumbUrl;
      } else if (coverPick?.existingImageUrl != null) {
        coverImageUrl = coverPick!.existingImageUrl;
        coverThumbnailUrl = coverImageUrl;
      } else if (coverPick?.newImageOrdinal != null) {
        final ordinal = coverPick!.newImageOrdinal!;
        coverImageUrl = ordinal < newImageUrls.length
            ? newImageUrls[ordinal]
            : (allImages.isNotEmpty ? allImages.first : null);
        coverThumbnailUrl = coverImageUrl;
      } else if (allImages.isNotEmpty) {
        coverImageUrl = allImages.first;
        coverThumbnailUrl = coverImageUrl;
      } else if (finalVideoUrl != null) {
        coverMediaType = 'video';
        coverVideoUid = finalVideoUid;
        coverVideoUrl = finalVideoUrl;
        coverThumbnailUrl = finalThumbUrl;
      }

      // 대표로 고른 사진을 실제 저장 배열의 맨 앞(index 0)으로 재정렬한다 —
      // 상세페이지 갤러리가 항상 index 0부터 열리므로, 저장 순서 자체를
      // 바꿔야 대표 미디어가 첫 화면에 온다(카드 썸네일은 coverImageUrl을
      // 직접 참조해 순서와 무관하게 이미 올바르게 표시되고 있었다).
      if (coverMediaType == 'image' && coverImageUrl != null) {
        allImages.remove(coverImageUrl);
        allImages.insert(0, coverImageUrl);
      }

      final finalDetailBlocks = await _resolveDetailBlocksForSave(
        uploadedBlockImageUrls,
        uploadedBlockVideoUids,
      );

      setState(() => _uploadStatus = '저장을 완료하는 중...');

      final maxParticipants =
          int.tryParse(_capacityController.text.trim()) ??
          (widget.data['maxParticipants'] as int? ?? 0);
      final current = (widget.data['currentParticipants'] as int?) ?? 0;
      final maleFee = _genderLimit != 'female'
          ? (int.tryParse(_maleFeeController.text.trim()) ?? 0)
          : null;
      final femaleFee = _genderLimit != 'male'
          ? (int.tryParse(_femaleFeeController.text.trim()) ?? 0)
          : null;

      final earlyBirdEndAt =
          (_earlyBirdEnabled &&
              _earlyBirdEndDate != null &&
              _earlyBirdEndTime != null)
          ? DateTime(
              _earlyBirdEndDate!.year,
              _earlyBirdEndDate!.month,
              _earlyBirdEndDate!.day,
              _earlyBirdEndTime!.hour,
              _earlyBirdEndTime!.minute,
            )
          : null;
      final earlyBirdActuallyEnabled =
          _earlyBirdEnabled && earlyBirdEndAt != null;

      await FirebaseFirestore.instance
          .collection('parties')
          .doc(widget.docId)
          .update({
            'title': _titleController.text.trim(),
            'description': _descController.text.trim(),
            'detailBlocks': PartyDetailBlock.listToMaps(finalDetailBlocks),
            'detailTheme': _detailTheme.name,
            'detailDecorationIntensity': _detailDecorationIntensity.name,
            'detailDecorationVariantSeed': _detailDecorationVariantSeed,
            'detailDescriptionMode': _descriptionMode.name,
            'autoDescriptionStyle': _autoDescriptionStyle.toMap(),
            'partyTypes': _partyTypes.toList(),
            'vibes': _vibes.toList(),
            'tags': _tags,
            'category': _partyTypes.isEmpty ? '기타' : _partyTypes.first,
            'maxParticipants': maxParticipants,
            'maxCapacity': maxParticipants,
            'recruitStatus': _recruitStatus,
            'people': '$current/$maxParticipants명',
            'maleFee': maleFee,
            'femaleFee': femaleFee,
            'refundPolicy': RefundTier.listToMaps(_refundTiers),
            'earlyBirdEnabled': earlyBirdActuallyEnabled,
            'earlyBirdDiscountPercent': earlyBirdActuallyEnabled
                ? (int.tryParse(_earlyBirdPercentController.text.trim()) ?? 0)
                : null,
            'earlyBirdEndAt': earlyBirdActuallyEnabled
                ? Timestamp.fromDate(earlyBirdEndAt)
                : null,
            'images': allImages,
            'imageUrls': allImages,
            // images[0]을 무조건 대표로 쓰던 기존 로직은 완전히 대체하고, 등록자가
            // 직접 고른 대표 미디어(coverMediaType 등)를 별도로 저장한다.
            if (allImages.isNotEmpty) 'mainImageUrl': allImages.first,
            if (finalVideoUrl != null) 'videoProvider': 'cloudflare',
            if (finalVideoUid != null) 'videoUid': finalVideoUid,
            if (finalVideoUrl != null) 'videoUrl': finalVideoUrl,
            if (finalThumbUrl != null) 'videoThumbnailUrl': finalThumbUrl,
            'coverMediaType': coverMediaType,
            'coverImageUrl': coverImageUrl,
            'coverVideoUid': coverVideoUid,
            'coverVideoUrl': coverVideoUrl,
            'coverThumbnailUrl': coverThumbnailUrl,
            'basicCardVideoFocalX': _mediaBasicCardFocalX,
            'basicCardVideoFocalY': _mediaBasicCardFocalY,
            'basicCardVideoScale': _mediaBasicCardScale,
            // 기본 카드에서 "사진"이 노출될 위치(초점)/확대 배율 — 사진 URL별 맵.
            'basicCardPhotoCrops': _resolvePhotoCrops(newImageUrls),
            // Spotify 미리듣기 — 사진만 등록된 파티(동영상이 없을 때)에서만 의미가
            // 있으므로 동영상이 있으면 저장하지 않는다.
            'spotifyTrackId': finalVideoUrl == null
                ? _selectedSpotifyTrack?.id
                : null,
            'spotifyTrackName': finalVideoUrl == null
                ? _selectedSpotifyTrack?.name
                : null,
            'spotifyArtistName': finalVideoUrl == null
                ? _selectedSpotifyTrack?.artistNames
                : null,
            'spotifyAlbumArt': finalVideoUrl == null
                ? _selectedSpotifyTrack?.albumArtUrl
                : null,
            'spotifyPreviewUrl': finalVideoUrl == null
                ? _selectedSpotifyTrack?.previewUrl
                : null,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('수정이 완료되었습니다')));
      Navigator.pop(context);
    } catch (e) {
      // 상세페이지 블록 사진/동영상이 R2·Stream에는 이미 올라갔는데 그
      // 이후(다른 업로드나 Firestore 저장)에서 실패했다면, 저장되지 못한
      // 파일을 정리한다.
      for (final url in uploadedBlockImageUrls) {
        unawaited(CloudflareService.deleteImage(url).catchError((_) {}));
      }
      for (final uid in uploadedBlockVideoUids) {
        unawaited(CloudflareService.deleteVideo(videoUid: uid).catchError((_) {}));
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장에 실패했습니다: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _uploadStatus = '';
        });
      }
    }
  }

  /// 상세페이지 블록을 저장 가능한 형태로 확정한다 — 아직 업로드되지 않은
  /// 사진/동영상 블록만 R2·Stream에 올리고(성공한 URL/UID는 [uploadedUrls]/
  /// [uploadedVideoUids]에 기록해 실패 시 롤백할 수 있게 하고), 빈 블록은
  /// 걸러낸다.
  Future<List<PartyDetailBlock>> _resolveDetailBlocksForSave(
    List<String> uploadedUrls,
    List<String> uploadedVideoUids,
  ) async {
    final result = <PartyDetailBlock>[];
    for (final d in _detailBlocks) {
      if (d.isEmpty) continue;
      if (d.type == PartyDetailBlockType.image && d.newImageFile != null) {
        setState(() => _uploadStatus = '상세페이지 사진을 올리는 중...');
        final url = await CloudflareService.uploadImage(File(d.newImageFile!.path));
        uploadedUrls.add(url);
        d.uploadedImageUrl = url;
        d.newImageFile = null;
      } else if (d.type == PartyDetailBlockType.imageGroup) {
        for (final item in d.imageGroupItems) {
          if (item.newImageFile == null) continue;
          setState(() => _uploadStatus = '상세페이지 사진을 올리는 중...');
          final url = await CloudflareService.uploadImage(File(item.newImageFile!.path));
          uploadedUrls.add(url);
          item.uploadedImageUrl = url;
          item.newImageFile = null;
        }
      } else if (d.type == PartyDetailBlockType.video && d.newVideoFile != null) {
        setState(() => _uploadStatus = '상세페이지 동영상을 올리는 중...');
        final uploaded = await CloudflareService.uploadVideo(File(d.newVideoFile!.path));
        final uid = uploaded['videoUid'];
        if (uid != null) uploadedVideoUids.add(uid);
        d.uploadedVideoUid = uid;
        d.uploadedVideoUrl = uploaded['videoUrl'];
        d.uploadedVideoThumbnailUrl = uploaded['videoThumbnailUrl'];
        d.newVideoFile = null;
      }
      result.add(d.toBlock());
    }
    return result;
  }

  // ── 각 SectionSummaryRow가 여는 선택 화면/시트 ────────────────────────

  Future<void> _openCapacitySheet() async {
    final result = await showGenderCapacitySheet(
      context,
      initial: GenderCapacityDraft(
        genderLimit: _genderLimit,
        genderCapacityMode: 'unlimited',
        genderMode: '',
        capacity: int.tryParse(_capacityController.text.trim()),
      ),
      allowGenderLimitChange: false,
    );
    if (result == null) return;
    setState(() {
      _capacityController.text = result.capacity?.toString() ?? '';
      _showCapacityError = false;
    });
  }

  Future<void> _openFeeSheet() async {
    final result = await showFeeSheet(
      context,
      genderLimit: _genderLimit,
      initial: FeeDraft(
        maleFee: int.tryParse(_maleFeeController.text.trim()),
        femaleFee: int.tryParse(_femaleFeeController.text.trim()),
        earlyBirdEnabled: _earlyBirdEnabled,
        earlyBirdPercent: int.tryParse(_earlyBirdPercentController.text.trim()),
        earlyBirdEndDate: _earlyBirdEndDate,
        earlyBirdEndTime: _earlyBirdEndTime,
      ),
    );
    if (result == null) return;
    setState(() {
      _maleFeeController.text = result.maleFee?.toString() ?? '';
      _femaleFeeController.text = result.femaleFee?.toString() ?? '';
      _earlyBirdEnabled = result.earlyBirdEnabled;
      _earlyBirdPercentController.text =
          result.earlyBirdPercent?.toString() ?? '';
      _earlyBirdEndDate = result.earlyBirdEndDate;
      _earlyBirdEndTime = result.earlyBirdEndTime;
      _showFeeError = false;
    });
  }

  Future<void> _openRefundPolicy() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PartyRefundPolicyScreen(
          initialTiers: _refundTiers,
          onChanged: (tiers) {
            _refundTiers = tiers;
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _openTypeVibeSheet() async {
    final result = await showPartyTypeVibeSheet(
      context,
      initial: PartyTypeVibeDraft(types: _partyTypes, vibes: _vibes, tags: _tags),
    );
    if (result == null) return;
    setState(() {
      _partyTypes
        ..clear()
        ..addAll(result.types);
      _vibes
        ..clear()
        ..addAll(result.vibes);
      _tags = result.tags;
    });
  }

  /// "상세 소개" 행의 진입점 — 먼저 "간편 자동 꾸미기 / 직접 상세페이지
  /// 만들기" 중 하나를 고르게 하고(현재 방식이 강조 표시됨), 고른 방식에
  /// 맞는 편집 화면으로 이동한다. 방식을 바꿔도 서로의 데이터는 지우지
  /// 않는다 — 다시 그 방식을 고르면 이어서 편집할 수 있다.
  Future<void> _openDescriptionEditor() async {
    final chosen = await showPartyDetailDescriptionModeSheet(
      context,
      current: _descriptionMode,
    );
    if (chosen == null || !mounted) return;

    if (chosen != _descriptionMode) {
      final hasContentInCurrentMode = _descriptionMode == PartyDescriptionMode.auto
          ? _descController.text.trim().isNotEmpty
          : _detailBlocks.any((d) => !d.isEmpty);
      if (hasContentInCurrentMode) {
        final confirmed = await confirmPartyDetailDescriptionModeSwitch(context);
        if (!confirmed || !mounted) return;
      }
      setState(() => _descriptionMode = chosen);
    }

    if (!mounted) return;
    if (_descriptionMode == PartyDescriptionMode.auto) {
      await _openIntroScreen();
    } else {
      await _openDetailBlockEditor();
    }
  }

  String? _descriptionSummary() {
    if (_descriptionMode == PartyDescriptionMode.auto) {
      final text = _descController.text.trim();
      if (text.isEmpty) return null;
      final excerpt = text.length > 24 ? '${text.substring(0, 24)}...' : text;
      return '간편 자동 꾸미기 · $excerpt';
    }
    if (_detailBlocks.isEmpty) return null;
    return '직접 상세페이지 만들기 · 블록 ${_detailBlocks.length}개';
  }

  Future<void> _openIntroScreen() async {
    final result = await Navigator.push<PartyIntroSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => PartyIntroScreen(
          initialIntro: _descController.text,
          initialTags: _tags,
          initialTheme: _autoDescriptionStyle.theme,
          initialIntensity: _autoDescriptionStyle.intensity,
          initialVariantSeed: _autoDescriptionStyle.variantSeed,
          initialParagraphStyles: _autoDescriptionStyle.paragraphStyles,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _descController.text = result.intro;
      _tags = result.tags;
      _autoDescriptionStyle = _autoDescriptionStyle.copyWith(
        theme: result.theme,
        intensity: result.intensity,
        variantSeed: result.variantSeed,
        paragraphStyles: result.paragraphStyles,
      );
      _showIntroError = false;
    });
  }

  /// 상세페이지 블록 에디터 — "직접 상세페이지 만들기"를 골랐을 때만
  /// 진입한다. 수정 화면은 기존에 블록 없이 등록된 파티도 많아, 다른
  /// 내용만 고치려는 호스트가 막히지 않도록 최소 1개 필수 검증은 걸지
  /// 않는다(등록 화면과의 차이, party_register_screen.dart 참고).
  Future<void> _openDetailBlockEditor() async {
    var initialBlocks = _detailBlocks;
    final seeded = _detailBlocks.isEmpty;
    if (seeded) {
      initialBlocks = [
        PartyDetailBlockDraft.fromBlock(
          PartyDetailBlock(
            id: generatePartyDetailBlockId(),
            type: PartyDetailBlockType.paragraph,
            text: _descController.text.trim(),
          ),
        ),
      ];
    }
    final result = await Navigator.push<PartyDetailBlockEditorResult>(
      context,
      MaterialPageRoute(
        builder: (_) => PartyDetailBlockEditorScreen(
          initialBlocks: initialBlocks,
          initialTheme: _detailTheme,
          initialIntensity: _detailDecorationIntensity,
          initialVariantSeed: _detailDecorationVariantSeed,
        ),
      ),
    );
    if (result == null) {
      if (seeded) {
        for (final d in initialBlocks) {
          d.dispose();
        }
      }
      return;
    }
    final (newBlocks, newTheme, newIntensity, newVariantSeed) = result;
    setState(() {
      for (final d in _detailBlocks) {
        d.dispose();
      }
      _detailBlocks = newBlocks;
      _detailTheme = newTheme;
      _detailDecorationIntensity = newIntensity;
      _detailDecorationVariantSeed = newVariantSeed;
    });
  }

  Future<void> _openMediaPicker() async {
    final result = await Navigator.push<PartyMediaSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => PartyMediaPickerScreen(
          existingImageUrls: _mediaExistingImageUrls,
          existingVideoUrl: _mediaExistingVideoUrl,
          existingVideoUid: _mediaExistingVideoUid,
          existingVideoThumbnailUrl: _mediaExistingVideoThumbnailUrl,
          newMedia: _mediaNewFiles,
          coverPick: _mediaCoverPick,
          spotifyTrack: _selectedSpotifyTrack,
          basicCardFocalX: _mediaBasicCardFocalX,
          basicCardFocalY: _mediaBasicCardFocalY,
          basicCardScale: _mediaBasicCardScale,
          photoCrops: _mediaPhotoCrops,
          videoCropConfirmed: _mediaVideoCropConfirmed,
          maxImages: 8,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _mediaExistingImageUrls = result.existingImageUrls;
      _mediaExistingVideoUrl = result.existingVideoUrl;
      _mediaExistingVideoUid = result.existingVideoUid;
      _mediaExistingVideoThumbnailUrl = result.existingVideoThumbnailUrl;
      _mediaNewFiles = result.newMedia;
      _mediaCoverPick = result.coverPick;
      _selectedSpotifyTrack = result.spotifyTrack;
      _mediaBasicCardFocalX = result.basicCardFocalX;
      _mediaBasicCardFocalY = result.basicCardFocalY;
      _mediaBasicCardScale = result.basicCardScale;
      _mediaPhotoCrops = result.photoCrops;
      _mediaVideoCropConfirmed = result.videoCropConfirmed;
      _showMediaCoverError = false;
    });
  }

  // ── 요약 텍스트 ─────────────────────────────────────────────────────

  String? _capacitySummary() {
    final cap = _capacityController.text.trim();
    if (cap.isEmpty) return null;
    final option = genderCapacityOptions.firstWhere(
      (o) => o['genderLimit'] == _genderLimit && o['mode'] == 'unlimited',
      orElse: () => const {'label': ''},
    );
    return '${option['label']} · $cap명';
  }

  String? _capacityErrorText() =>
      _capacityController.text.trim().isEmpty ? '최대 인원을 입력해줘' : null;

  String? _feeSummary() {
    final showMale = _genderLimit != 'female';
    final showFemale = _genderLimit != 'male';
    final maleFee = int.tryParse(_maleFeeController.text.trim());
    final femaleFee = int.tryParse(_femaleFeeController.text.trim());
    final parts = <String>[];
    if (showMale && maleFee != null) {
      parts.add('남 ${EarlyBird.formatPrice(maleFee)}');
    }
    if (showFemale && femaleFee != null) {
      parts.add('여 ${EarlyBird.formatPrice(femaleFee)}');
    }
    if (parts.isEmpty) return null;
    var summary = parts.join(' / ');
    if (_earlyBirdEnabled) {
      summary += ' · 얼리버드 ${_earlyBirdPercentController.text}%';
    }
    return summary;
  }

  String? _feeErrorText() {
    if (_genderLimit != 'female' && _maleFeeController.text.trim().isEmpty) {
      return '남자 참가비를 입력해줘';
    }
    if (_genderLimit != 'male' && _femaleFeeController.text.trim().isEmpty) {
      return '여자 참가비를 입력해줘';
    }
    if (_earlyBirdEnabled) {
      final err = _validateEarlyBird();
      if (err != null) return err;
    }
    return null;
  }

  String? _refundSummary() =>
      _refundTiers.isEmpty ? null : '${_refundTiers.length}단계 환불 규정 설정됨';

  String? _typeVibeSummary() {
    final all = [
      ..._partyTypes.map(PartyConstants.labelFor),
      ..._vibes,
      ..._tags.map((t) => '#$t'),
    ];
    return all.isEmpty ? null : all.join(' · ');
  }


  String? _mediaSummary() {
    final photoCount =
        _mediaExistingImageUrls.length +
        _mediaNewFiles.where((f) => !_isVideoFile(f)).length;
    final parts = <String>[];
    if (photoCount > 0) parts.add('사진 $photoCount장');
    if (_mediaHasVideo) parts.add('동영상 1개');
    if (_selectedSpotifyTrack != null) parts.add('배경음악 설정됨');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  int _totalMediaCount() {
    final photoCount =
        _mediaExistingImageUrls.length +
        _mediaNewFiles.where((f) => !_isVideoFile(f)).length;
    return photoCount + (_mediaHasVideo ? 1 : 0);
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF7F7FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 16),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

  Widget _sectionCard({required String title, required Widget child}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'SeoulHangang',
                fontSize: 17,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                  Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            child,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('파티 수정', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
        centerTitle: true,
        foregroundColor: Colors.black,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: const Text(
              '저장',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionCard(
                  title: '기본 정보',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('파티명'),
                      PartyTitleField(
                        controller: _titleController,
                        decoration: _inputDecoration('파티 이름을 입력해줘'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '파티명을 입력해줘'
                            : null,
                      ),
                      _label('모집 상태'),
                      DropdownButtonFormField<String>(
                        initialValue: _recruitStatus,
                        items: _statuses
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _recruitStatus = v);
                        },
                        decoration: _inputDecoration('모집 상태'),
                      ),
                    ],
                  ),
                ),
                SectionSummaryRow(
                  title: '성별 및 모집 인원',
                  summary: _capacitySummary(),
                  hasError: _showCapacityError,
                  errorText: _capacityErrorText(),
                  onTap: _openCapacitySheet,
                ),
                SectionSummaryRow(
                  title: '참가비 설정',
                  summary: _feeSummary(),
                  hasError: _showFeeError,
                  errorText: _showFeeError ? _feeErrorText() : null,
                  onTap: _openFeeSheet,
                ),
                SectionSummaryRow(
                  title: '환불 규정',
                  summary: _refundSummary(),
                  onTap: _openRefundPolicy,
                ),
                SectionSummaryRow(
                  title: '파티 유형 및 분위기',
                  summary: _typeVibeSummary(),
                  onTap: _openTypeVibeSheet,
                ),
                SectionSummaryRow(
                  title: '상세 소개',
                  summary: _descriptionSummary(),
                  hasError: _showIntroError,
                  errorText: '소개를 입력해줘',
                  onTap: _openDescriptionEditor,
                ),
                SectionSummaryRow(
                  title: '미디어 등록',
                  summary: _mediaSummary(),
                  hasError: _showMediaCoverError,
                  errorText: '대표이미지를 체크해주세요',
                  blinkOnError: true,
                  onTap: _openMediaPicker,
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 12, left: 4, top: 2),
                  child: Text(
                    '동영상 최대 1개 · 사진 최대 8장',
                    style: TextStyle(fontSize: 11, color: Colors.black38),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('저장하기'),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
          // 업로드 오버레이 — 압축은 이제 미디어 등록 화면 안에서만 일어나므로
          // 여기서는 업로드 진행 상태만 표시한다.
          if (_isSaving)
            Container(
              color: Colors.black45,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      _uploadStatus,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
