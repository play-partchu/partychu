import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/party_auto_description_style.dart';
import 'package:party_app/models/party_description_mode.dart';
import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/party_detail_decoration_intensity.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/models/party_constants.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/models/spotify_track.dart';
import 'package:party_app/screens/party_detail_block_editor_screen.dart';
import 'package:party_app/screens/party_intro_screen.dart';
import 'package:party_app/screens/party_location_picker_screen.dart';
import 'package:party_app/screens/party_media_picker_screen.dart';
import 'package:party_app/screens/party_refund_policy_screen.dart';
import 'package:party_app/utils/age_range_utils.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/party_form/age_restriction_sheet.dart';
import 'package:party_app/widgets/party_form/date_time_sheet.dart';
import 'package:party_app/widgets/party_form/party_date_list_sheet.dart';
import 'package:party_app/widgets/party_form/party_detail_block_draft.dart';
import 'package:party_app/widgets/party_form/party_detail_description_mode_sheet.dart';
import 'package:party_app/widgets/party_form/fee_sheet.dart';
import 'package:party_app/widgets/party_form/gender_capacity_sheet.dart';
import 'package:party_app/widgets/party_form/party_title_field.dart';
import 'package:party_app/widgets/party_form/party_type_vibe_sheet.dart';
import 'package:party_app/widgets/party_form/round_list_editor.dart';
import 'package:party_app/widgets/party_form/section_summary_row.dart';
import 'package:party_app/widgets/party_media_editor.dart' show PartyCoverPick;

class PartyRegisterScreen extends StatefulWidget {
  /// non-null이면 해당 데이터로 필드를 사전 입력 (재등록 용도)
  final Map<String, dynamic>? prefillData;

  /// non-null이면 해당 문서를 update (재등록). null이면 새 문서 add (신규 등록).
  final String? existingDocId;

  const PartyRegisterScreen({super.key, this.prefillData, this.existingDocId});

  @override
  State<PartyRegisterScreen> createState() => _PartyRegisterScreenState();
}

class _PartyRegisterScreenState extends State<PartyRegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── 뒤로가기 이탈 방지 ───────────────────────────────────────────────
  // 사용자가 사진·동영상·환불 규정처럼 setState를 거치지 않는 값까지 포함해
  // 뭔가 하나라도 바꾸면 true가 된다. setState를 오버라이드해서 이 화면의
  // 거의 모든 상호작용을 개별 호출부를 일일이 손대지 않고 한 곳에서 잡아낸다.
  bool _dirty = false;

  void _markDirty() => _dirty = true;

  @override
  void setState(VoidCallback fn) {
    _dirty = true;
    super.setState(fn);
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          '등록을 종료하시겠습니까?',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontSize: 16,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        content: const Text('작성 중인 정보가 모두 초기화됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 작성'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  final _partyNameController = PartyTitleController();
  final _introController = TextEditingController();
  final _maleFeeController = TextEditingController();
  final _femaleFeeController = TextEditingController();
  final _earlyBirdPercentController = TextEditingController();
  // 환불 규정 — 호스트가 직접 등록하는 기간별 환불률 구간. 기본값 없음.
  List<RefundTier> _refundTiers = [];
  final _capacityController = TextEditingController();
  final _maleCapacityController = TextEditingController();
  final _femaleCapacityController = TextEditingController();
  final _detailAddressController = TextEditingController();

  AddressResult? _selectedPlace;

  // ── 미디어 — PartyMediaPickerScreen을 pop할 때만 갱신되는 스냅샷.
  // PartyMediaEditor는 AutomaticKeepAliveClientMixin으로 상시 마운트를
  // 전제하므로, push된 화면이 사라지기 전에 반드시 여기로 값을 받아와야 한다.
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
  // 중 하나만 실제로 렌더링된다. 기본값은 auto(일반 사용자 기본 추천).
  PartyDescriptionMode _descriptionMode = PartyDescriptionMode.auto;
  PartyAutoDescriptionStyle _autoDescriptionStyle = const PartyAutoDescriptionStyle();

  // 파티 상세페이지 블록("직접 상세페이지 만들기"를 골랐을 때만 쓰인다) —
  // 모드를 auto로 바꿔도 지우지 않고 그대로 들고 있다가, 다시 blocks로
  // 돌아오면 이어서 편집할 수 있게 한다.
  List<PartyDetailBlockDraft> _detailBlocks = [];
  PartyDetailThemeKey _detailTheme = PartyDetailThemeKey.partychu;
  PartyDetailDecorationIntensity _detailDecorationIntensity = PartyDetailDecorationIntensity.standard;
  int _detailDecorationVariantSeed = 0;

  bool _isUploading = false;
  String _uploadStatus = '';

  // 필수항목 에러 표시 — 각 SectionSummaryRow의 빨간 테두리를 켠다.
  bool _showAddressError = false;
  bool _showDateError = false;
  bool _showCapacityError = false;
  bool _showFeeError = false;
  bool _showIntroError = false;
  bool _showMediaCoverError = false;
  bool _showDetailBlocksError = false;

  // 스크롤 + 에러 위치 이동용 키
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _keyPartyName = GlobalKey();
  final GlobalKey _keyAddress = GlobalKey();
  final GlobalKey _keyDateTime = GlobalKey();
  final GlobalKey _keyCapacity = GlobalKey();
  final GlobalKey _keyFee = GlobalKey();
  final GlobalKey _keyIntro = GlobalKey();
  final GlobalKey _keyMedia = GlobalKey();

  // ── 날짜 및 시간 ─────────────────────────────────────────────────────
  // 파티는 서로 다른 날짜를 여러 개 가질 수 있다(각 슬롯이 독립된 Firestore
  // 문서가 된다 — _submit() 참고). index 0 슬롯이 항상 "기준"이며, 수정
  // 모드에서는 그 슬롯이 기존 문서를 그대로 업데이트한다.
  List<PartyDateSlot> _dateSlots = [];
  TimeOfDay? _recruitDeadlineTime;
  bool _weeklyRepeatEnabled = false;
  DateTime? _weeklyRepeatEndDate;
  int? _weeklyRepeatCount;
  Set<String> _weeklyRepeatExcludedDates = {};
  // 이 화면(수정 모드)이 속한 "시리즈"(한 번의 등록에서 나온 날짜 문서
  // 묶음) id. prefill에서 복원하고, 없으면(레거시 문서) 제출 시
  // existingDocId로 대체한다 — 10개 제한을 "게시글" 단위로 세는 데 쓰인다.
  String? _existingSeriesId;

  // ── 다차수(1차/2차/3차) 라운드 ────────────────────────────────────────
  // 1차는 위 _dateSlots(각 날짜의 시작 시간)와 정원/참가비 컨트롤러가 그대로
  // 담당하고, 여기 _extraRounds는 2차부터만 관리한다(RoundListEditor 참고).
  bool _hasMultipleRounds = false;
  String _roundCapacityMode = 'unified'; // 'unified' | 'perRound'
  final List<PartyRoundDraft> _extraRounds = [];

  // ── 얼리버드 할인 ─────────────────────────────────────────────────
  bool _earlyBirdEnabled = false;
  DateTime? _earlyBirdEndDate;
  TimeOfDay? _earlyBirdEndTime;
  final Set<String> _partyTypes = {};
  final Set<String> _vibes = {};
  String _region = '서울';
  String? _district;

  bool _ageRestrictionEnabled = false;
  // 예시 기본값(23세 ~ 31세)을 출생연도로 환산해 저장 — 화면에는 항상 나이로만
  // 노출된다(_ageSummary() 참고).
  int _minBirthYear = birthYearFromAge(31);
  int _maxBirthYear = birthYearFromAge(23);

  /// all/male/female
  String _genderLimit = 'all';

  /// separate(남녀별 정원 따로) / unlimited(전체 인원만)
  String _genderCapacityMode = 'unlimited';

  /// 성비 맞춤일 때 'balanced', 그 외 빈 문자열
  String _genderMode = '';

  List<String> _tags = [];

  @override
  void initState() {
    super.initState();
    if (widget.prefillData != null) {
      _prefill(widget.prefillData!);
    }
    // 프리필 이후에 붙여야 초기값을 채우는 동작 자체가 "변경"으로 잡히지
    // 않는다. TextField는 onChanged 없이도 타이핑 자체는 화면에 반영되므로
    // (컨트롤러가 스스로 다시 그림) 오버라이드한 setState만으로는 일반
    // 텍스트 입력을 놓친다 — 컨트롤러 리스너로 직접 잡는다.
    for (final c in [
      _partyNameController,
      _introController,
      _maleFeeController,
      _femaleFeeController,
      _earlyBirdPercentController,
      _capacityController,
      _maleCapacityController,
      _femaleCapacityController,
      _detailAddressController,
    ]) {
      c.addListener(_markDirty);
    }
  }

  void _prefill(Map<String, dynamic> d) {
    _partyNameController.text = d['title'] as String? ?? '';
    _introController.text = d['description'] as String? ?? '';
    _detailAddressController.text = d['detailAddress'] as String? ?? '';

    // 장소 복원
    final lat = (d['latitude'] as num?)?.toDouble();
    final lng = (d['longitude'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      _selectedPlace = AddressResult(
        placeName: d['placeName'] as String? ?? '',
        address: d['address'] as String? ?? '',
        roadAddress: d['roadAddress'] as String? ?? '',
        jibunAddress: d['jibunAddress'] as String? ?? '',
        latitude: lat,
        longitude: lng,
      );
    }

    // 날짜·시간 복원 (partyDateTime Timestamp) — 수정 모드는 항상 슬롯
    // 1개로 시작한다(이 문서 자신의 날짜만). 형제 시리즈 문서를 여기서
    // 재구성하지 않는다 — 그건 각자 독립된 문서이기 때문이다.
    final partyTs = d['partyDateTime'] as Timestamp?;
    if (partyTs != null) {
      final dt = partyTs.toDate();
      _dateSlots = [
        PartyDateSlot(
          id: newPartyDateSlotId(),
          date: DateTime(dt.year, dt.month, dt.day),
          startTime: TimeOfDay(hour: dt.hour, minute: dt.minute),
        ),
      ];
    }

    // 모집 마감 시간
    final deadlineTs = d['recruitDeadlineAt'] as Timestamp?;
    if (deadlineTs != null) {
      final dt = deadlineTs.toDate();
      _recruitDeadlineTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
    }

    // 성별·인원 제한
    _genderLimit = d['genderLimit'] as String? ?? 'all';
    _genderCapacityMode = d['genderCapacityMode'] as String? ?? 'unlimited';
    _genderMode = d['genderMode'] as String? ?? '';

    // 인원
    final maxCap = (d['maxCapacity'] as num?)?.toInt() ?? 0;
    final maleCap = (d['maleCapacity'] as num?)?.toInt() ?? 0;
    final femaleCap = (d['femaleCapacity'] as num?)?.toInt() ?? 0;
    if (_genderCapacityMode == 'unlimited') {
      if (maxCap > 0) {
        _capacityController.text = '$maxCap';
      }
    } else {
      if (maleCap > 0) {
        _maleCapacityController.text = '$maleCap';
      }
      if (femaleCap > 0) {
        _femaleCapacityController.text = '$femaleCap';
      }
    }

    // 참가비
    final maleFee = (d['maleFee'] as num?)?.toInt();
    final femaleFee = (d['femaleFee'] as num?)?.toInt();
    if (maleFee != null) {
      _maleFeeController.text = '$maleFee';
    }
    if (femaleFee != null) {
      _femaleFeeController.text = '$femaleFee';
    }

    // 환불 규정 — 재등록 시 이전 설정을 그대로 불러온다.
    _refundTiers = RefundTier.listFromDynamic(d['refundPolicy']);

    // 얼리버드 할인 — 재등록 시 이전 설정을 그대로 불러오되, 종료일이 이미
    // 지난 값이면 그대로 켜두지 않고 꺼진 상태로 초기화한다 (사용자가 새로 설정).
    final earlyBirdEndTs = d['earlyBirdEndAt'] as Timestamp?;
    if (d['earlyBirdEnabled'] == true &&
        earlyBirdEndTs != null &&
        earlyBirdEndTs.toDate().isAfter(DateTime.now())) {
      _earlyBirdEnabled = true;
      _earlyBirdPercentController.text =
          '${(d['earlyBirdDiscountPercent'] as num?)?.toInt() ?? 10}';
      final endDt = earlyBirdEndTs.toDate();
      _earlyBirdEndDate = DateTime(endDt.year, endDt.month, endDt.day);
      _earlyBirdEndTime = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
    }

    // 파티 유형·분위기·태그
    _partyTypes.addAll((d['partyTypes'] as List?)?.cast<String>() ?? []);
    _vibes.addAll((d['vibes'] as List?)?.cast<String>() ?? []);
    _tags = [...((d['tags'] as List?)?.cast<String>() ?? [])];

    // 나이 제한
    _ageRestrictionEnabled = d['ageRestrictionEnabled'] as bool? ?? false;
    if (_ageRestrictionEnabled) {
      _minBirthYear = (d['minBirthYear'] as num?)?.toInt() ?? birthYearFromAge(31);
      _maxBirthYear = (d['maxBirthYear'] as num?)?.toInt() ?? birthYearFromAge(23);
    }

    // 다차수 라운드 — 재등록 시 2차 이상 라운드 구성을 그대로 불러온다.
    _hasMultipleRounds = d['hasMultipleRounds'] as bool? ?? false;
    if (_hasMultipleRounds) {
      _roundCapacityMode = d['roundCapacityMode'] as String? ?? 'unified';
      final rawRounds = (d['rounds'] as List?) ?? [];
      for (final raw in rawRounds) {
        final m = Map<String, dynamic>.from(raw as Map);
        if ((m['roundNumber'] as num?)?.toInt() == 1) continue; // 1차는 위에서 이미 복원됨
        _extraRounds.add(PartyRoundDraft.fromMap(m));
      }
    }

    // 시리즈 id·지역 (저장된 region/district 우선, 없으면 주소에서 자동 추출)
    // isRecurring은 더는 화면에서 읽지 않는다 — 이 화면을 거치는 모든
    // 문서는 이제 항상 true로 저장된다(_submit() 참고).
    _existingSeriesId = d['seriesId'] as String?;
    final addrForRegion = d['address'] as String? ?? '';
    _region = d['region'] as String? ?? RegionData.extractRegion(addrForRegion);
    _district =
        d['district'] as String? ??
        RegionData.extractDistrict(addrForRegion, region: _region);

    // ── 기존 미디어 URL 복원 ──────────────────────────────────────
    // images → imageUrls 순으로 시도 (필드명 하위 호환)
    final imgs = <String>[];
    imgs.addAll((d['images'] as List?)?.cast<String>() ?? []);
    if (imgs.isEmpty) {
      imgs.addAll((d['imageUrls'] as List?)?.cast<String>() ?? []);
    }
    // mainImageUrl이 images 목록에 없으면 맨 앞에 추가
    final mainImg = d['mainImageUrl'] as String?;
    if (mainImg != null && mainImg.isNotEmpty && !imgs.contains(mainImg)) {
      imgs.insert(0, mainImg);
    }
    _mediaExistingImageUrls = imgs.where((u) => u.isNotEmpty).toList();

    _mediaExistingVideoUrl = d['videoUrl'] as String?;
    _mediaExistingVideoUid = d['videoUid'] as String?;
    _mediaExistingVideoThumbnailUrl = d['videoThumbnailUrl'] as String?;

    // 기존에 저장된 대표 미디어 선택 상태 복원 — PartyCoverPick 하나로 통일.
    final prefillCoverMediaType = d['coverMediaType'] as String?;
    final prefillCoverImageUrl = d['coverImageUrl'] as String?;
    if (prefillCoverMediaType == 'video') {
      _mediaCoverPick = const PartyCoverPick(isExistingVideo: true);
    } else if (prefillCoverMediaType == 'image' &&
        prefillCoverImageUrl != null) {
      _mediaCoverPick = PartyCoverPick(existingImageUrl: prefillCoverImageUrl);
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

    // 재등록 시 이전 상세페이지 블록 구성을 그대로 불러온다.
    _detailBlocks = PartyDetailBlock.listFromDynamic(d['detailBlocks'])
        .map((b) => PartyDetailBlockDraft.fromBlock(b))
        .toList();
    // 재등록 시 이전 디자인 테마 선택을 그대로 불러온다. 없거나 알 수 없는
    // 값이면 partyDetailThemeKeyFromString이 partychu로 안전하게 대체한다.
    _detailTheme = partyDetailThemeKeyFromString(d['detailTheme'] as String?);
    _detailDecorationIntensity = partyDetailDecorationIntensityFromString(
      d['detailDecorationIntensity'] as String?,
    );
    // 필드가 없으면(이 기능 이전에 등록된 파티) 0 — 지금까지 암묵적으로
    // 써온 시드와 같아 회귀 없이 그대로 렌더링된다.
    _detailDecorationVariantSeed = (d['detailDecorationVariantSeed'] as num?)?.toInt() ?? 0;
    // 재등록 시 이전 상세 설명 방식을 그대로 불러온다. 필드가 없는(이 기능
    // 이전에 등록된) 파티는 detailBlocks 유무로 추론한다.
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
    _scrollController.dispose();
    _partyNameController.dispose();
    _introController.dispose();
    _maleFeeController.dispose();
    _femaleFeeController.dispose();
    _earlyBirdPercentController.dispose();
    _capacityController.dispose();
    _maleCapacityController.dispose();
    _femaleCapacityController.dispose();
    _detailAddressController.dispose();
    for (final r in _extraRounds) {
      r.dispose();
    }
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

  /// 등록 직전 로컬 파일 경로로 저장돼 있던 사진 크롭 값을, 업로드로 갓
  /// 발급받은 최종 URL 키로 옮겨 담는다. 기존(네트워크) 사진은 URL이 그대로
  /// 유지되므로 옮길 필요 없이 그대로 합친다.
  Map<String, Map<String, double>> _resolvePhotoCrops(
    _UploadResult uploaded,
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
      if (c != null && ordinal < uploaded.imageUrls.length) {
        result[uploaded.imageUrls[ordinal]] = c;
      }
      ordinal++;
    }
    return result;
  }

  /// 이미지 → Cloudflare Images, 동영상 → Cloudflare Stream
  Future<_UploadResult> _uploadAll(List<XFile> newMedia) async {
    final imageUrls = <String>[];
    String? videoUid;
    String? videoUrl;
    String? videoThumbnailUrl;

    int total = newMedia.length;
    int done = 0;

    for (final file in newMedia) {
      final isVideo =
          file.path.toLowerCase().endsWith('.mp4') ||
          file.path.toLowerCase().endsWith('.mov');

      if (isVideo) {
        setState(() => _uploadStatus = '동영상을 올리는 중...');
        debugPrint(
          '[Register] 업로드 시작(동영상) — path=${file.path}, '
          'exists=${File(file.path).existsSync()}',
        );
        final result = await CloudflareService.uploadVideo(File(file.path));
        videoUid = result['videoUid'];
        videoUrl = result['videoUrl'];
        videoThumbnailUrl = result['videoThumbnailUrl'];
      } else {
        done++;
        setState(() => _uploadStatus = '사진을 올리는 중... ($done/$total)');
        final url = await CloudflareService.uploadImage(File(file.path));
        imageUrls.add(url);
      }
      done++;
    }
    return _UploadResult(
      imageUrls: imageUrls,
      videoUid: videoUid,
      videoUrl: videoUrl,
      videoThumbnailUrl: videoThumbnailUrl,
    );
  }

  /// 성별/인원 제한 설정에 따라 남자/여자/전체 정원을 계산합니다.
  /// 반환: (maleCapacity, femaleCapacity, maxCapacity)
  (int, int, int) _resolveCapacities() {
    if (_genderCapacityMode == 'unlimited') {
      final max = int.tryParse(_capacityController.text.trim()) ?? 0;
      return (0, 0, max);
    }
    final male = (_genderLimit == 'all' || _genderLimit == 'male')
        ? int.tryParse(_maleCapacityController.text.trim()) ?? 0
        : 0;
    final female = (_genderLimit == 'all' || _genderLimit == 'female')
        ? int.tryParse(_femaleCapacityController.text.trim()) ?? 0
        : 0;
    return (male, female, male + female);
  }

  String? _validateFee(String? v) {
    if (v == null || v.trim().isEmpty) return '참가비를 입력해주세요. (무료인 경우 0 입력)';
    final fee = int.tryParse(v.trim());
    if (fee == null || fee < 0) return '숫자만 입력해주세요.';
    if (fee % 1000 != 0) return '참가비는 1,000원 단위로 입력해주세요.';
    return null;
  }

  bool _validateCapacityInputs() {
    if (_genderCapacityMode == 'unlimited') {
      if (_capacityController.text.trim().isEmpty) {
        _showMessage('전체 최대 인원을 입력해줘');
        setState(() => _showCapacityError = true);
        return false;
      }
    } else {
      if (_maleCapacityController.text.trim().isEmpty) {
        _showMessage('남자 모집 인원을 입력해줘');
        setState(() => _showCapacityError = true);
        return false;
      }
      if (_femaleCapacityController.text.trim().isEmpty) {
        _showMessage('여자 모집 인원을 입력해줘');
        setState(() => _showCapacityError = true);
        return false;
      }
    }
    setState(() => _showCapacityError = false);

    if (_genderLimit != 'female') {
      final err = _validateFee(_maleFeeController.text);
      if (err != null) {
        _showMessage(err);
        setState(() => _showFeeError = true);
        return false;
      }
    }
    if (_genderLimit != 'male') {
      final err = _validateFee(_femaleFeeController.text);
      if (err != null) {
        _showMessage(err);
        setState(() => _showFeeError = true);
        return false;
      }
    }
    if (_earlyBirdEnabled) {
      final err = _validateEarlyBird();
      if (err != null) {
        setState(() => _showFeeError = true);
        _showMessage(err);
        return false;
      }
    }
    setState(() => _showFeeError = false);
    return true;
  }

  /// 다차수 라운드 입력값 검증. 문제 없으면 true.
  bool _validateRoundsInputs() {
    if (!_hasMultipleRounds) return true;
    for (var i = 0; i < _extraRounds.length; i++) {
      if (_extraRounds[i].time == null) {
        _showMessage('${i + 2}차 시간을 선택해줘');
        return false;
      }
    }
    if (_roundCapacityMode != 'perRound') return true;

    bool filled(TextEditingController c) => c.text.trim().isNotEmpty;

    // 1차는 기존 정원/참가비 섹션의 값을 그대로 쓴다.
    if (_genderCapacityMode == 'unlimited') {
      if (!filled(_capacityController)) {
        _showMessage('1차 최대 인원을 입력해줘');
        return false;
      }
    } else {
      if (!filled(_maleCapacityController) || !filled(_femaleCapacityController)) {
        _showMessage('1차 남녀 모집 인원을 입력해줘');
        return false;
      }
    }
    if (_genderLimit != 'female' &&
        _validateFee(_maleFeeController.text) != null) {
      _showMessage('1차 참가비를 입력해줘');
      return false;
    }
    if (_genderLimit != 'male' &&
        _validateFee(_femaleFeeController.text) != null) {
      _showMessage('1차 참가비를 입력해줘');
      return false;
    }

    for (var i = 0; i < _extraRounds.length; i++) {
      final r = _extraRounds[i];
      final n = i + 2;
      if (_genderCapacityMode == 'unlimited') {
        if (!filled(r.capacityCtrl)) {
          _showMessage('$n차 최대 인원을 입력해줘');
          return false;
        }
      } else {
        if (!filled(r.maleCapacityCtrl) || !filled(r.femaleCapacityCtrl)) {
          _showMessage('$n차 남녀 모집 인원을 입력해줘');
          return false;
        }
      }
      if (_genderLimit != 'female' && _validateFee(r.maleFeeCtrl.text) != null) {
        _showMessage('$n차 참가비를 입력해줘 (무료면 0)');
        return false;
      }
      if (_genderLimit != 'male' && _validateFee(r.femaleFeeCtrl.text) != null) {
        _showMessage('$n차 참가비를 입력해줘 (무료면 0)');
        return false;
      }
    }
    return true;
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

  Future<void> _submit() async {
    // 모든 필수항목 한 번에 검증
    final formValid = _formKey.currentState!.validate();
    final addressError = _selectedPlace == null;
    final detailAddressEmpty = _detailAddressController.text.trim().isEmpty;
    final dateError = _dateSlots.isEmpty;
    final timeError = !dateError && _dateSlots.any((s) => s.startTime == null);
    final introError = _introController.text.trim().isEmpty;
    // 상세페이지 블록 최소 1개 필수 — "직접 상세페이지 만들기"를 고른
    // 경우에만 적용된다("간편 자동 꾸미기"에서는 블록을 아예 안 씀).
    // 내용 없는(isEmpty) 블록만 있어도 실제로는 빈 것과 같으므로 함께 걸러낸다.
    final detailBlocksError = _descriptionMode == PartyDescriptionMode.blocks &&
        _detailBlocks.every((d) => d.isEmpty);
    // 사진/동영상이 2개 이상 등록됐는데 그중 대표를 직접 고르지 않았으면
    // 막는다 — 1개뿐이면 고를 것도 없으니 그대로 자동 대표 처리한다.
    final mediaCoverError = _totalMediaCount() > 1 && _mediaCoverPick == null;

    setState(() {
      _showAddressError = addressError || detailAddressEmpty;
      _showDateError = dateError || timeError;
      _showIntroError = introError;
      _showDetailBlocksError = detailBlocksError;
      _showMediaCoverError = mediaCoverError;
    });

    if (!formValid ||
        addressError ||
        detailAddressEmpty ||
        dateError ||
        timeError ||
        introError ||
        detailBlocksError ||
        mediaCoverError ||
        !_validateCapacityInputs() ||
        !_validateRoundsInputs()) {
      // 가장 위에 있는 누락 항목으로 스크롤
      GlobalKey? target;
      if (_partyNameController.text.trim().isEmpty) {
        target = _keyPartyName;
      } else if (addressError || detailAddressEmpty) {
        target = _keyAddress;
      } else if (dateError || timeError) {
        target = _keyDateTime;
      } else if (_showCapacityError) {
        target = _keyCapacity;
      } else if (_showFeeError) {
        target = _keyFee;
      } else if (introError || detailBlocksError) {
        target = _keyIntro;
      } else if (mediaCoverError) {
        target = _keyMedia;
      }
      if (target?.currentContext != null) {
        await Scrollable.ensureVisible(
          target!.currentContext!,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.1,
        );
      }
      return;
    }

    if (!CloudflareService.isConfigured) {
      _showMessage('현재 파일 업로드 서비스를 사용할 수 없습니다. 잠시 후 다시 시도해주세요.');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = '파티 등록을 준비하는 중...';
    });

    // 이번 저장에서 새로 R2/Stream에 업로드된 상세페이지 블록 사진·동영상 —
    // 이후 Firestore 저장이 실패하면 catch에서 이 목록만 롤백 삭제한다.
    final uploadedBlockImageUrls = <String>[];
    final uploadedBlockVideoUids = <String>[];

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? UserSession.userId;

      // ── 신규 등록 시 파티 개수 제한 체크 ────────────────────────────────
      // "게시글" 단위로 센다 — 한 번의 등록에서 나온 여러 날짜 문서는
      // seriesId가 같으므로 하나로 묶는다. seriesId가 없는 레거시 문서는
      // 문서 자신을 각각 1개의 게시글로 취급한다(폴백).
      if (widget.existingDocId == null) {
        final countSnap = await FirebaseFirestore.instance
            .collection('parties')
            .where('hostId', isEqualTo: UserSession.userId)
            .get();
        final activePostKeys = <String>{};
        for (final d in countSnap.docs) {
          final data = d.data();
          if (data['isDeleted'] == true || data['status'] == 'deleted') {
            continue;
          }
          final seriesId = data['seriesId'] as String?;
          activePostKeys.add(seriesId ?? d.id);
        }
        if (activePostKeys.length >= 10) {
          if (mounted) {
            _showMessage(
              '현재 등록 가능한 파티는 최대 10개입니다.\n'
              '마이페이지 > 지난 파티에서 재등록 또는 삭제 후 다시 시도해주세요.',
            );
          }
          return;
        }
      }

      final newMedia = _mediaNewFiles;
      final uploaded = newMedia.isNotEmpty
          ? await _uploadAll(newMedia)
          : _UploadResult(
              imageUrls: [],
              videoUid: null,
              videoUrl: null,
              videoThumbnailUrl: null,
            );

      setState(() => _uploadStatus = '등록을 완료하고 있습니다...');

      final (maleCapacity, femaleCapacity, maxCapacity) = _resolveCapacities();
      final maleFee = _genderLimit != 'female'
          ? (int.tryParse(_maleFeeController.text.trim()) ?? 0)
          : null;
      final femaleFee = _genderLimit != 'male'
          ? (int.tryParse(_femaleFeeController.text.trim()) ?? 0)
          : null;
      // 대표(1차) 날짜 슬롯 — rounds 합계 등 "모든 슬롯이 동일하게 공유하는"
      // 값 계산의 기준으로 쓰인다. 실제로 각 문서에 저장되는 날짜 종속
      // 필드(date/partyDateTime/recruitDeadlineAt/rounds)는 슬롯마다
      // buildSlotDateFields()로 따로 계산한다.
      final primarySlot = _dateSlots.first;
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

      // ── 다차수 라운드 — 1차(슬롯의 시작 시간 그대로) + 2차 이상
      // (_extraRounds, PartyRoundDraft.toMap이 partyDate를 받으므로 슬롯마다
      // 다시 계산할 수 있다). 정원/참가비 템플릿은 모든 날짜 슬롯이 동일하게
      // 공유하고, 오직 각 라운드의 시간(Timestamp)만 슬롯 날짜에 따라
      // 달라진다.
      List<Map<String, dynamic>>? buildRoundsField(
        DateTime slotDate,
        TimeOfDay slotStartTime,
      ) {
        if (!_hasMultipleRounds) return null;
        final slotPartyDateTime = DateTime(
          slotDate.year,
          slotDate.month,
          slotDate.day,
          slotStartTime.hour,
          slotStartTime.minute,
        );
        return [
          <String, dynamic>{
            'roundNumber': 1,
            'label': '1차',
            'time': Timestamp.fromDate(slotPartyDateTime),
            if (_roundCapacityMode == 'perRound') ...{
              'maxCapacity': maxCapacity,
              'maleCapacity': maleCapacity,
              'femaleCapacity': femaleCapacity,
              'currentParticipants': 0,
              'currentMaleCount': 0,
              'currentFemaleCount': 0,
              'maleFee': maleFee ?? 0,
              'femaleFee': femaleFee ?? 0,
            },
          },
          for (var i = 0; i < _extraRounds.length; i++)
            _extraRounds[i].toMap(
              roundNumber: i + 2,
              partyDate: slotDate,
              roundCapacityMode: _roundCapacityMode,
              genderCapacityMode: _genderCapacityMode,
            ),
        ];
      }

      // 정원 합계(aggMaxCapacity 등) 계산 기준 — 대표 슬롯 결과만 있으면
      // 충분하다(모든 슬롯이 동일한 정원 템플릿을 공유하므로).
      final roundsField = buildRoundsField(
        primarySlot.date,
        primarySlot.startTime!,
      );

      // perRound 모드에서는 라운드를 모르는 기존 코드(피드 카드 등)를 위해
      // 상단 정원 필드를 라운드 전체 합계로 채운다 — 참가비는 합산 의미가
      // 없으므로(1인당 금액) 그대로 1차 값을 대표로 유지한다.
      var aggMaxCapacity = maxCapacity;
      var aggMaleCapacity = maleCapacity;
      var aggFemaleCapacity = femaleCapacity;
      if (_hasMultipleRounds &&
          _roundCapacityMode == 'perRound' &&
          roundsField != null) {
        aggMaxCapacity = 0;
        aggMaleCapacity = 0;
        aggFemaleCapacity = 0;
        for (final r in roundsField) {
          aggMaxCapacity += (r['maxCapacity'] as int?) ?? 0;
          aggMaleCapacity += (r['maleCapacity'] as int?) ?? 0;
          aggFemaleCapacity += (r['femaleCapacity'] as int?) ?? 0;
        }
      }

      // 공통 필드 맵
      final allImages = [..._mediaExistingImageUrls, ...uploaded.imageUrls];
      final finalVideoUrl = uploaded.videoUrl ?? _mediaExistingVideoUrl;
      final finalVideoUid = uploaded.videoUid ?? _mediaExistingVideoUid;
      final finalVideoThumbnailUrl =
          uploaded.videoThumbnailUrl ?? _mediaExistingVideoThumbnailUrl;

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
        coverThumbnailUrl = finalVideoThumbnailUrl;
      } else if (coverPick?.existingImageUrl != null) {
        coverImageUrl = coverPick!.existingImageUrl;
        coverThumbnailUrl = coverImageUrl;
      } else if (coverPick?.newImageOrdinal != null) {
        final ordinal = coverPick!.newImageOrdinal!;
        coverImageUrl = ordinal < uploaded.imageUrls.length
            ? uploaded.imageUrls[ordinal]
            : (allImages.isNotEmpty ? allImages.first : null);
        coverThumbnailUrl = coverImageUrl;
      } else if (allImages.isNotEmpty) {
        coverImageUrl = allImages.first;
        coverThumbnailUrl = coverImageUrl;
      } else if (finalVideoUrl != null) {
        coverMediaType = 'video';
        coverVideoUid = finalVideoUid;
        coverVideoUrl = finalVideoUrl;
        coverThumbnailUrl = finalVideoThumbnailUrl;
      }

      // 대표로 고른 사진을 실제 저장 배열의 맨 앞(index 0)으로 재정렬한다 —
      // 상세페이지 갤러리가 항상 index 0부터 열리므로, 저장 순서 자체를
      // 바꿔야 대표 미디어가 첫 화면에 온다(카드 썸네일은 coverImageUrl을
      // 직접 참조해 순서와 무관하게 이미 올바르게 표시되고 있었다).
      if (coverMediaType == 'image' && coverImageUrl != null) {
        allImages.remove(coverImageUrl);
        allImages.insert(0, coverImageUrl);
      }

      final finalDetailBlocks = await _resolveDetailBlocksForSubmit(
        uploadedBlockImageUrls,
        uploadedBlockVideoUids,
      );

      // 시리즈 id — 이번 제출(=1개의 "게시글")에서 만들어지는 모든 날짜
      // 문서가 공유하는 값. 편집 모드에서 기존 seriesId가 없던(레거시)
      // 문서를 처음 이 코드로 편집하면, 그 문서 자신의 id를 채택한다(그
      // 문서가 시리즈의 시작점이 된다) — 신규 등록은 매번 새로 발급한다.
      final seriesId =
          _existingSeriesId ??
          widget.existingDocId ??
          FirebaseFirestore.instance.collection('parties').doc().id;

      // 모든 날짜 문서가 동일하게 공유하는 필드. 날짜 종속 필드(date/
      // partyDateTime/recruitDeadlineAt/rounds)는 buildSlotDateFields()로
      // 슬롯마다 따로 계산해 여기 합쳐진다.
      final sharedFields = <String, dynamic>{
        'title': _partyNameController.text.trim(),
        'location': _selectedPlace?.displayAddress ?? '',
        'address': _selectedPlace?.address ?? '',
        'roadAddress': _selectedPlace?.roadAddress ?? '',
        'jibunAddress': _selectedPlace?.jibunAddress ?? '',
        'placeName': _selectedPlace?.placeName ?? '',
        if (_selectedPlace != null) 'latitude': _selectedPlace!.latitude,
        if (_selectedPlace != null) 'longitude': _selectedPlace!.longitude,
        'seriesId': seriesId,
        'people': '0/$aggMaxCapacity명',
        'genderLimit': _genderLimit,
        'genderCapacityMode': _genderCapacityMode,
        'genderMode': _genderMode,
        'maleCapacity': aggMaleCapacity,
        'femaleCapacity': aggFemaleCapacity,
        'currentMaleCount': 0,
        'currentFemaleCount': 0,
        'maxCapacity': aggMaxCapacity,
        'maxParticipants': aggMaxCapacity,
        'currentParticipants': 0,
        'hasMultipleRounds': _hasMultipleRounds,
        if (_hasMultipleRounds) 'roundCapacityMode': _roundCapacityMode,
        'category': _partyTypes.isEmpty ? '기타' : _partyTypes.first,
        'partyTypes': _partyTypes.toList(),
        'vibes': _vibes.toList(),
        'tags': _tags,
        'region': _region,
        'district': _district,
        'ageRestrictionEnabled': _ageRestrictionEnabled,
        if (_ageRestrictionEnabled) 'minBirthYear': _minBirthYear,
        if (_ageRestrictionEnabled) 'maxBirthYear': _maxBirthYear,
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
        if (finalVideoUrl != null) 'videoProvider': 'cloudflare',
        if (finalVideoUid != null) 'videoUid': finalVideoUid,
        if (finalVideoUrl != null) 'videoUrl': finalVideoUrl,
        if (finalVideoThumbnailUrl != null)
          'videoThumbnailUrl': finalVideoThumbnailUrl,
        'detailAddress': _detailAddressController.text.trim(),
        'description': _introController.text.trim(),
        'detailBlocks': PartyDetailBlock.listToMaps(finalDetailBlocks),
        'detailTheme': _detailTheme.name,
        'detailDecorationIntensity': _detailDecorationIntensity.name,
        'detailDecorationVariantSeed': _detailDecorationVariantSeed,
        'detailDescriptionMode': _descriptionMode.name,
        'autoDescriptionStyle': _autoDescriptionStyle.toMap(),
        'recruitStatus': '모집중',
        // 이 화면을 거쳐 저장되는 모든 문서는 이제 항상 재등록 가능하다
        // (예전엔 화면의 별도 토글로 껐다 켰지만, 다중 날짜/매주 반복이
        // 그 자리를 대체하면서 더는 사용자가 따로 켤 필요가 없어졌다).
        'isRecurring': true,
        'lastUsedAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'isDeleted': false,
        'status': 'active',
        // 대표 미디어 — 등록자가 직접 고른 사진/동영상. images[0]을 무조건
        // 대표로 쓰던 기존 mainImageUrl 로직은 완전히 대체한다.
        'mainImageUrl': allImages.isNotEmpty ? allImages.first : null,
        'coverMediaType': coverMediaType,
        'coverImageUrl': coverImageUrl,
        'coverVideoUid': coverVideoUid,
        'coverVideoUrl': coverVideoUrl,
        'coverThumbnailUrl': coverThumbnailUrl,
        // 기본 카드에서 동영상이 노출될 위치(초점)/확대 배율 — 대표 미디어가
        // 사진이어도 그대로 보관해두면 나중에 동영상으로 바뀔 때 재사용된다.
        'basicCardVideoFocalX': _mediaBasicCardFocalX,
        'basicCardVideoFocalY': _mediaBasicCardFocalY,
        'basicCardVideoScale': _mediaBasicCardScale,
        // 기본 카드에서 "사진"이 노출될 위치(초점)/확대 배율 — 사진 URL별 맵.
        'basicCardPhotoCrops': _resolvePhotoCrops(uploaded),
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
      };

      // 슬롯(날짜) 하나마다 달라지는 필드만 계산한다. 그 외(정원/참가비/
      // 사진/설명 등)는 sharedFields로 모든 날짜 문서가 동일하게 공유한다.
      // 모집마감시간은 화면 전체에서 시간 하나만 고르고(_recruitDeadlineTime),
      // 각 슬롯 자신의 날짜에 적용해 슬롯마다 독립된 마감 시각을 만든다 —
      // 기존 등록화면의 "날짜는 공유, 시간만 선택" 방식을 그대로 여러
      // 날짜로 확장한 것이다.
      Map<String, dynamic> buildSlotDateFields(PartyDateSlot slot) {
        final slotPartyDateTime = DateTime(
          slot.date.year,
          slot.date.month,
          slot.date.day,
          slot.startTime!.hour,
          slot.startTime!.minute,
        );
        final deadlineDateTime = _recruitDeadlineTime != null
            ? DateTime(
                slot.date.year,
                slot.date.month,
                slot.date.day,
                _recruitDeadlineTime!.hour,
                _recruitDeadlineTime!.minute,
              )
            : null;
        return {
          'date':
              '${formatPartyDate(slot.date)} ${formatPartyTime(slot.startTime)}',
          'partyDateTime': Timestamp.fromDate(slotPartyDateTime),
          if (deadlineDateTime != null)
            'recruitDeadlineAt': Timestamp.fromDate(deadlineDateTime),
          if (_hasMultipleRounds)
            'rounds': buildRoundsField(slot.date, slot.startTime!),
        };
      }

      final docId = widget.existingDocId;
      final partiesCol = FirebaseFirestore.instance.collection('parties');
      // 대표(index 0) 문서 참조 — 수정 모드면 기존 문서, 신규 등록이면 새
      // 문서. 나머지 날짜 슬롯은 항상 새 문서로 추가된다.
      final primaryRef = docId != null ? partiesCol.doc(docId) : partiesCol.doc();
      final batch = FirebaseFirestore.instance.batch();

      for (var i = 0; i < _dateSlots.length; i++) {
        final slot = _dateSlots[i];
        final isPrimary = i == 0;
        final ref = isPrimary ? primaryRef : partiesCol.doc();
        final docFields = {...sharedFields, ...buildSlotDateFields(slot)};

        if (isPrimary && docId != null) {
          // ── 수정: 기존 문서 업데이트 (신청자 초기화, 기존 동작 그대로) ──
          batch.update(ref, {
            ...docFields,
            'applicants': [],
            'approvedApplicants': [],
            'rejectedApplicants': [],
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          // ── 신규 문서 (신규 등록의 대표 슬롯이거나, 그 외 모든 추가 날짜) ──
          batch.set(ref, {
            ...docFields,
            'hostId': UserSession.userId,
            'hostUid': uid,
            'applicants': [],
            'approvedApplicants': [],
            'approved': true,
            'createdAt': Timestamp.fromDate(DateTime.now()),
          });
        }
      }
      await batch.commit();

      if (!mounted) return;
      _dirty = false; // 정상 등록 완료 — 나갈 때 이탈 방지 확인창을 띄우지 않는다.
      // 등록 화면이 몇 단계 깊이 열려 있었든(모바일: RegisterTypeScreen 경유,
      // 데스크톱: MainScreen에서 바로) 곧장 메인화면 파티 탭으로 복귀한다.
      pendingTopTabAfterRegister.value = 0;
      Navigator.popUntil(context, (route) => route.isFirst);
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
      debugPrint('[PartyRegister] 등록 실패: $e');
      if (mounted) _showMessage('파티 등록에 실패했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
        });
      }
    }
  }

  /// 상세페이지 블록을 저장 가능한 형태로 확정한다 — 아직 업로드되지 않은
  /// 사진/동영상 블록만 R2·Stream에 올리고(성공한 URL/UID는 [uploadedUrls]/
  /// [uploadedVideoUids]에 기록해 실패 시 롤백할 수 있게 하고), 빈 블록은
  /// 걸러낸다.
  Future<List<PartyDetailBlock>> _resolveDetailBlocksForSubmit(
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

  Future<void> _openDateListSheet() async {
    final result = await showPartyDateListSheet(
      context,
      initial: PartyDateListDraft(
        slots: _dateSlots,
        recruitDeadlineTime: _recruitDeadlineTime,
        weeklyRepeatEnabled: _weeklyRepeatEnabled,
        weeklyRepeatEndDate: _weeklyRepeatEndDate,
        weeklyRepeatCount: _weeklyRepeatCount,
        weeklyRepeatExcludedDates: _weeklyRepeatExcludedDates,
      ),
    );
    if (result == null) return;
    setState(() {
      _dateSlots = result.slots;
      _recruitDeadlineTime = result.recruitDeadlineTime;
      _weeklyRepeatEnabled = result.weeklyRepeatEnabled;
      _weeklyRepeatEndDate = result.weeklyRepeatEndDate;
      _weeklyRepeatCount = result.weeklyRepeatCount;
      _weeklyRepeatExcludedDates = result.weeklyRepeatExcludedDates;
      _showDateError = false;
    });
  }

  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<PartyLocationSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => PartyLocationPickerScreen(
          initialPlace: _selectedPlace,
          initialDetailAddress: _detailAddressController.text,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _selectedPlace = result.place;
      _detailAddressController.text = result.detailAddress;
      _showAddressError = false;
      final addr = result.place.roadAddress.isNotEmpty
          ? result.place.roadAddress
          : result.place.jibunAddress;
      if (addr.isNotEmpty) {
        _region = RegionData.extractRegion(addr);
        _district = RegionData.extractDistrict(addr, region: _region);
      }
    });
  }

  Future<void> _openGenderCapacitySheet() async {
    final result = await showGenderCapacitySheet(
      context,
      initial: GenderCapacityDraft(
        genderLimit: _genderLimit,
        genderCapacityMode: _genderCapacityMode,
        genderMode: _genderMode,
        capacity: int.tryParse(_capacityController.text.trim()),
        maleCapacity: int.tryParse(_maleCapacityController.text.trim()),
        femaleCapacity: int.tryParse(_femaleCapacityController.text.trim()),
      ),
    );
    if (result == null) return;
    setState(() {
      final prevGenderLimit = _genderLimit;
      _genderLimit = result.genderLimit;
      _genderCapacityMode = result.genderCapacityMode;
      _genderMode = result.genderMode;
      _capacityController.text = result.capacity?.toString() ?? '';
      _maleCapacityController.text = result.maleCapacity?.toString() ?? '';
      _femaleCapacityController.text = result.femaleCapacity?.toString() ?? '';
      // 성별 제한이 바뀌어 숨겨지는 참가비 필드는 기존과 동일하게 비운다.
      if (prevGenderLimit != _genderLimit) {
        if (_genderLimit == 'male') _femaleFeeController.clear();
        if (_genderLimit == 'female') _maleFeeController.clear();
      }
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
            _markDirty();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _openAgeRestrictionSheet() async {
    // 이 화면에는 아직 파티 대상 유형(성인/청소년/혼합)을 고르는 UI가 없어
    // 항상 성인 전용 범위로 연다 — 청소년 전용 파티 기능이 생기면 그때 고른
    // audienceType 값을 여기 그대로 넘기면 된다(`age_range_utils.dart`의
    // `partyAgeRangeFor` 참고).
    final result = await showAgeRestrictionSheet(
      context,
      initial: AgeRestrictionDraft(
        enabled: _ageRestrictionEnabled,
        minYear: _minBirthYear,
        maxYear: _maxBirthYear,
      ),
      audienceType: PartyAudienceType.adult,
    );
    if (result == null) return;
    setState(() {
      _ageRestrictionEnabled = result.enabled;
      _minBirthYear = result.minYear;
      _maxBirthYear = result.maxYear;
    });
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
  /// 맞는 편집 화면으로 이동한다. 두 방식은 동시에 쓸 수 없지만 데이터는
  /// 서로 지우지 않는다 — 방식을 왔다갔다 바꿔도 각자 마지막으로 작성한
  /// 내용이 그대로 남아있어 다시 그 방식을 고르면 이어서 편집된다.
  Future<void> _openDescriptionEditor() async {
    final chosen = await showPartyDetailDescriptionModeSheet(
      context,
      current: _descriptionMode,
    );
    if (chosen == null || !mounted) return;

    if (chosen != _descriptionMode) {
      final hasContentInCurrentMode = _descriptionMode == PartyDescriptionMode.auto
          ? _introController.text.trim().isNotEmpty
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
      final text = _introController.text.trim();
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
          initialIntro: _introController.text,
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
      _introController.text = result.intro;
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
  /// 진입한다. 그 방식을 고른 경우에는 최소 1개 블록을 필수로 요구한다
  /// (검증은 _submit() 참고, `_descriptionMode == blocks`일 때만 걸림).
  ///
  /// 블록이 하나도 없는 상태로 처음 열면 완전히 빈 화면에서 시작하지
  /// 않도록, 지금까지 입력한 "모임 소개" 텍스트를 본문(paragraph) 블록
  /// 1개로 미리 채워 넘긴다 — 사용자가 취소하면 이 임시 시드 블록은
  /// _detailBlocks에 반영되지 않은 채로 버려지므로 직접 dispose한다.
  Future<void> _openDetailBlockEditor() async {
    var initialBlocks = _detailBlocks;
    final seeded = _detailBlocks.isEmpty;
    if (seeded) {
      initialBlocks = [
        PartyDetailBlockDraft.fromBlock(
          PartyDetailBlock(
            id: generatePartyDetailBlockId(),
            type: PartyDetailBlockType.paragraph,
            text: _introController.text.trim(),
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
      _showDetailBlocksError = false;
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

  String? _dateTimeSummary() {
    if (_dateSlots.isEmpty) return null;
    final first = _dateSlots.first;
    if (first.startTime == null) return null;
    var s = '${formatPartyDate(first.date)} ${formatPartyTime(first.startTime)}';
    if (first.endTime != null) s += ' ~ ${formatPartyTime(first.endTime)}';
    if (_dateSlots.length > 1) s += ' 외 ${_dateSlots.length - 1}건';
    return s;
  }

  String? _dateTimeErrorText() {
    if (_dateSlots.isEmpty) return '파티 날짜와 시작 시간을 선택해줘';
    final missingIndex = _dateSlots.indexWhere((s) => s.startTime == null);
    if (missingIndex == 0) return '시작 시간을 선택해줘';
    if (missingIndex > 0) return '${missingIndex + 1}번째 날짜의 시작 시간을 선택해줘';
    return null;
  }

  String? _locationSummary() {
    if (_selectedPlace == null) return null;
    final regionDistrict = [
      _region,
      _district,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return regionDistrict.isNotEmpty
        ? regionDistrict
        : _selectedPlace!.displayAddress;
  }

  String? _addressErrorText() {
    if (_selectedPlace == null) return '파티 장소를 선택해주세요.';
    if (_detailAddressController.text.trim().isEmpty) return '상세주소를 입력해주세요.';
    return null;
  }

  String? _genderCapacitySummary() {
    final option = genderCapacityOptions.firstWhere(
      (o) =>
          o['genderLimit'] == _genderLimit &&
          o['mode'] == _genderCapacityMode &&
          o['genderMode'] == _genderMode,
      orElse: () => const {'label': ''},
    );
    final label = option['label'] ?? '';
    if (_genderCapacityMode == 'unlimited') {
      final cap = _capacityController.text.trim();
      if (cap.isEmpty) return null;
      return '$label · $cap명';
    }
    final m = _maleCapacityController.text.trim();
    final f = _femaleCapacityController.text.trim();
    if (m.isEmpty && f.isEmpty) return null;
    return '$label · 남 ${m.isEmpty ? '-' : m}명 / 여 ${f.isEmpty ? '-' : f}명';
  }

  String? _capacityErrorText() {
    if (_genderCapacityMode == 'unlimited') {
      return _capacityController.text.trim().isEmpty ? '전체 최대 인원을 입력해줘' : null;
    }
    if (_maleCapacityController.text.trim().isEmpty) return '남자 모집 인원을 입력해줘';
    if (_femaleCapacityController.text.trim().isEmpty) return '여자 모집 인원을 입력해줘';
    return null;
  }

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
    if (_genderLimit != 'female') {
      final err = _validateFee(_maleFeeController.text);
      if (err != null) return err;
    }
    if (_genderLimit != 'male') {
      final err = _validateFee(_femaleFeeController.text);
      if (err != null) return err;
    }
    if (_earlyBirdEnabled) {
      final err = _validateEarlyBird();
      if (err != null) return err;
    }
    return null;
  }

  String? _refundSummary() =>
      _refundTiers.isEmpty ? null : '${_refundTiers.length}단계 환불 규정 설정됨';

  String? _ageSummary() => _ageRestrictionEnabled
      ? '${ageFromBirthYear(_maxBirthYear)}세 ~ ${ageFromBirthYear(_minBirthYear)}세'
      : null;

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

  void _showMessage(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ─── UI helpers ──────────────────────────────────────────────────────────

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
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
              fontSize: 18,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _roundModeChip(String title, String subtitle, String mode) {
    final selected = _roundCapacityMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _roundCapacityMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF3F7) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? const Color(0xFFFF6FA0)
                : const Color(0xFFE8EBF2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: selected
                    ? const Color(0xFFFF6FA0)
                    : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10.5, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 안드로이드 시스템 뒤로가기·제스처, 앱바 뒤로가기 버튼 모두 이 한
      // 지점을 거친다. 아무것도 바꾸지 않았으면(_dirty==false) 그냥 나가고,
      // 뭔가 바꿨으면 막고 확인 다이얼로그를 띄운다.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await _confirmLeave();
        if (shouldLeave && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FC),
        appBar: AppBar(title: const Text('파티 등록', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])), centerTitle: true),
        body: Stack(
          children: [
            Form(
              key: _formKey,
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionCard(
                    title: '기본 정보',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('파티명'),
                        PartyTitleField(
                          fieldKey: _keyPartyName,
                          controller: _partyNameController,
                          decoration: _inputDecoration('예: 한강 야경 드라이브 번개'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? '파티명을 입력해줘'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  SectionSummaryRow(
                    rowKey: _keyDateTime,
                    title: '날짜 및 시간 선택',
                    summary: _dateTimeSummary(),
                    hasError: _showDateError,
                    errorText: _dateTimeErrorText(),
                    onTap: _openDateListSheet,
                  ),
                  _sectionCard(
                    title: '여러 라운드로 진행하나요?',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '1차/2차/3차처럼 라운드를 나눠 진행하면 켜주세요.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                            Switch(
                              value: _hasMultipleRounds,
                              onChanged: (v) =>
                                  setState(() => _hasMultipleRounds = v),
                              activeThumbColor: const Color(0xFFFF6FA0),
                            ),
                          ],
                        ),
                        if (_hasMultipleRounds) ...[
                          const SizedBox(height: 12),
                          const Text(
                            '정원/참가비 방식',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _roundModeChip(
                                  '통합 정원',
                                  '모든 라운드가 같은 정원/참가비',
                                  'unified',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _roundModeChip(
                                  '라운드별 정원',
                                  '라운드마다 정원/참가비가 다름',
                                  'perRound',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          RoundListEditor(
                            rounds: _extraRounds,
                            roundCapacityMode: _roundCapacityMode,
                            genderCapacityMode: _genderCapacityMode,
                            onChanged: _markDirty,
                          ),
                        ],
                      ],
                    ),
                  ),
                  SectionSummaryRow(
                    rowKey: _keyAddress,
                    title: '장소 선택',
                    summary: _locationSummary(),
                    hasError: _showAddressError,
                    errorText: _addressErrorText(),
                    onTap: _openLocationPicker,
                  ),
                  SectionSummaryRow(
                    rowKey: _keyCapacity,
                    title: '성별 및 모집 인원',
                    summary: _genderCapacitySummary(),
                    hasError: _showCapacityError,
                    errorText: _capacityErrorText(),
                    onTap: _openGenderCapacitySheet,
                  ),
                  SectionSummaryRow(
                    rowKey: _keyFee,
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
                    title: '연령대 설정',
                    summary: _ageSummary(),
                    onTap: _openAgeRestrictionSheet,
                  ),
                  SectionSummaryRow(
                    title: '파티 유형 및 분위기',
                    summary: _typeVibeSummary(),
                    onTap: _openTypeVibeSheet,
                  ),
                  SectionSummaryRow(
                    rowKey: _keyIntro,
                    title: '상세 소개',
                    summary: _descriptionSummary(),
                    hasError: _showIntroError || _showDetailBlocksError,
                    errorText: _showDetailBlocksError
                        ? '상세페이지 블록을 최소 1개 추가해주세요.'
                        : '파티 소개를 입력해줘',
                    blinkOnError: _showDetailBlocksError,
                    onTap: _openDescriptionEditor,
                  ),
                  SectionSummaryRow(
                    rowKey: _keyMedia,
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
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isUploading ? null : _submit,
                      child: const Text(
                        '파티 등록하기',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
            if (_isUploading)
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UploadResult {
  final List<String> imageUrls;
  final String? videoUid;
  final String? videoUrl;
  final String? videoThumbnailUrl;

  const _UploadResult({
    required this.imageUrls,
    required this.videoUid,
    required this.videoUrl,
    required this.videoThumbnailUrl,
  });
}
