import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/party_auto_description_style.dart';
import 'package:party_app/models/party_constants.dart';
import 'package:party_app/models/party_description_mode.dart';
import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/draft_type.dart';
import 'package:party_app/models/party_detail_decoration_intensity.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/screens/address_search_screen.dart';
import 'package:party_app/screens/party_detail_block_editor_screen.dart';
import 'package:party_app/screens/party_intro_screen.dart';
import 'package:party_app/screens/party_media_picker_screen.dart';
import 'package:party_app/screens/party_refund_policy_screen.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/age_range_utils.dart';
import 'package:party_app/utils/draftable_register.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/party_form/age_restriction_sheet.dart';
import 'package:party_app/widgets/party_form/custom_time_picker_sheet.dart';
import 'package:party_app/widgets/party_form/date_time_sheet.dart';
import 'package:party_app/widgets/party_form/fee_sheet.dart';
import 'package:party_app/widgets/party_form/gender_capacity_sheet.dart';
import 'package:party_app/widgets/party_form/party_date_list_sheet.dart';
import 'package:party_app/widgets/party_form/party_detail_block_draft.dart';
import 'package:party_app/widgets/combo_intro_card.dart';
import 'package:party_app/widgets/party_form/party_detail_description_mode_sheet.dart';
import 'package:party_app/widgets/party_form/party_title_field.dart';
import 'package:party_app/widgets/party_form/party_type_vibe_sheet.dart';
import 'package:party_app/widgets/party_form/round_list_editor.dart';
import 'package:party_app/widgets/party_form/section_summary_row.dart';
import 'package:party_app/widgets/party_media_editor.dart' show PartyCoverPick;
import 'package:party_app/widgets/place_form/room_card.dart';
import 'package:party_app/widgets/web_frame.dart';

const _kAccent = Color(0xFF7C5CBF);

/// 숙박+파티 콤보 등록 — 게스트하우스·펜션·호텔처럼 숙박과 파티를 함께
/// 운영하는 업체가 한 번의 입력으로 `places` 문서(+`placeRooms`)와
/// `parties` 문서(들)를 함께 만든다. 화면상으로는 하나의 통합 등록이지만,
/// 내부적으로는 기존 "파티 장소 등록"(`place_register_screen.dart`)과
/// "파티 등록"(`party_register_screen.dart`)이 각각 만드는 것과 동일한
/// 셰이프의 문서를 만들고 `bundleId`/`linkedPartyId`/`linkedPlaceId`로
/// 서로 연결한다 — 두 화면의 결제/예약(placeReservationGroups, PortOne,
/// applyToParty)은 전혀 건드리지 않고 그대로 재사용된다(v1은 숙박 예약과
/// 파티 신청이 각자 독립적으로 동작).
///
/// 파티 파트는 "파티 등록" 화면(`party_register_screen.dart`)과 완전히
/// 동일한 기능(다중 날짜/매주 반복/다차수 라운드/성별·인원/참가비+얼리버드/
/// 환불규정/파티 유형·분위기·태그/상세 소개 방식)을 그대로 지원한다 —
/// 다중 날짜를 등록하면 그 등록 화면처럼 날짜 슬롯마다 독립된 `parties`
/// 문서가 만들어지고, 같은 `seriesId`로 묶인다("게시글" 1개). 그 중
/// 대표(1번째) 문서만 장소 문서의 `linkedPartyId`가 가리킨다.
///
/// "숙박"은 체크인/체크아웃 날짜 기반의 새 예약 구조가 아니라, 기존
/// "파티룸 대여" 룸(`RoomCard`) 구조를 그대로 재사용한다 — 객실 유형 =
/// 룸 문서, 숙박가격은 룸의 기존 "패키지" 가격(예: "1박")으로 표현한다.
///
/// 화면이 길어지는 것을 막기 위해 "숙박 등록"/"파티 등록" 두 묶음을
/// 아코디언(한 번에 하나만 펼침)으로 접어둔다 — 공통 정보/사진은 항상
/// 보이고, 나머지는 사용자가 탭한 쪽만 펼쳐진다.
class PartyPlaceComboRegisterScreen extends StatefulWidget {
  /// 마이페이지 "임시저장" 목록에서 "이어서 작성"으로 열 때 true.
  final bool autoRestoreDraft;

  const PartyPlaceComboRegisterScreen({
    super.key,
    this.autoRestoreDraft = false,
  });

  @override
  State<PartyPlaceComboRegisterScreen> createState() =>
      _PartyPlaceComboRegisterScreenState();
}

class _PartyPlaceComboRegisterScreenState
    extends State<PartyPlaceComboRegisterScreen>
    with
        WidgetsBindingObserver,
        DraftableRegister<PartyPlaceComboRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  // ── 임시저장 ─────────────────────────────────────────────────────────
  // 파티 등록 화면과 동일한 방식(1초 debounce 자동저장 + 임시저장 버튼 +
  // 재진입 복구 팝업)을 공용 믹스인으로 붙인다. 파티 파트의 직렬화는 파티
  // 등록 화면(_toDraftPayload)과 같은 키·형식을 쓴다.

  /// 룸별 복원 데이터(RoomCard의 initialData로 전달) — _roomKeys와 인덱스가
  /// 1:1 대응한다. 신규 룸은 null.
  final List<Map<String, dynamic>?> _roomInitialData = [];

  @override
  void setState(VoidCallback fn) {
    markDraftDirty();
    super.setState(fn);
  }

  @override
  DraftType get draftType => DraftType.stayPartyCombo;

  @override
  bool get draftAutoRestore => widget.autoRestoreDraft;

  @override
  String get draftTitle => _nameCtrl.text;

  @override
  String? get draftCoverImageUrl =>
      _mediaExistingImageUrls.isNotEmpty ? _mediaExistingImageUrls.first : null;

  @override
  Map<String, dynamic> buildDraftPayload() {
    return <String, dynamic>{
      // 공통 정보
      'name': _nameCtrl.text,
      'detailAddress': _detailAddressCtrl.text,
      'contact': _contactCtrl.text,
      'description': _descCtrl.text,
      'address': _selectedAddress == null
          ? null
          : {
              'placeName': _selectedAddress!.placeName,
              'address': _selectedAddress!.address,
              'roadAddress': _selectedAddress!.roadAddress,
              'jibunAddress': _selectedAddress!.jibunAddress,
              'latitude': _selectedAddress!.latitude,
              'longitude': _selectedAddress!.longitude,
            },
      'expandedSection': _expandedSection,
      // 미디어 — 업로드된 URL은 그대로, 아직 업로드 안 된 로컬 파일은 경로만.
      'existingImageUrls': _mediaExistingImageUrls,
      'existingVideoUrl': _mediaExistingVideoUrl,
      'existingVideoUid': _mediaExistingVideoUid,
      'existingVideoThumbnailUrl': _mediaExistingVideoThumbnailUrl,
      'newFilePaths': _mediaNewFiles.map((f) => f.path).toList(),
      'coverPick': _mediaCoverPick == null
          ? null
          : {
              'existingImageUrl': _mediaCoverPick!.existingImageUrl,
              'isExistingVideo': _mediaCoverPick!.isExistingVideo,
              'newImageOrdinal': _mediaCoverPick!.newImageOrdinal,
              'isNewVideo': _mediaCoverPick!.isNewVideo,
            },
      // 숙박 정보
      'placeType': _placeType,
      'checkInTime': DraftableRegister.timeToMap(_checkInTime),
      'checkOutTime': DraftableRegister.timeToMap(_checkOutTime),
      'commonFacilities': _commonFacilities.toList(),
      'customCommonFacilities': _customCommonFacilities.toList(),
      'bookingLink': _bookingLinkCtrl.text,
      'rooms': _roomDraftList(),
      // 파티 날짜/시간
      'dateSlots': _dateSlots
          .map((s) => {
                'dateMs': DateTime(s.date.year, s.date.month, s.date.day)
                    .millisecondsSinceEpoch,
                'start': DraftableRegister.timeToMap(s.startTime),
                'end': DraftableRegister.timeToMap(s.endTime),
                'auto': s.isAutoGenerated,
              })
          .toList(),
      'recruitDeadlineTime':
          DraftableRegister.timeToMap(_recruitDeadlineTime),
      'weeklyRepeatEnabled': _weeklyRepeatEnabled,
      'weeklyRepeatEndDateMs': _weeklyRepeatEndDate?.millisecondsSinceEpoch,
      'weeklyRepeatCount': _weeklyRepeatCount,
      'weeklyRepeatExcludedDates': _weeklyRepeatExcludedDates.toList(),
      // 다차수 라운드
      'hasMultipleRounds': _hasMultipleRounds,
      'roundCapacityMode': _roundCapacityMode,
      'extraRounds': _extraRounds
          .map((r) => {
                'id': r.id,
                'label': r.labelCtrl.text,
                'time': DraftableRegister.timeToMap(r.time),
                'capacity': r.capacityCtrl.text,
                'maleCapacity': r.maleCapacityCtrl.text,
                'femaleCapacity': r.femaleCapacityCtrl.text,
                'maleFee': r.maleFeeCtrl.text,
                'femaleFee': r.femaleFeeCtrl.text,
              })
          .toList(),
      // 성별·인원
      'genderLimit': _genderLimit,
      'genderCapacityMode': _genderCapacityMode,
      'genderMode': _genderMode,
      'capacityText': _capacityCtrl.text,
      'maleCapacityText': _maleCapacityCtrl.text,
      'femaleCapacityText': _femaleCapacityCtrl.text,
      // 참가비 + 얼리버드
      'maleFeeText': _maleFeeCtrl.text,
      'femaleFeeText': _femaleFeeCtrl.text,
      'earlyBirdEnabled': _earlyBirdEnabled,
      'earlyBirdPercentText': _earlyBirdPercentCtrl.text,
      'earlyBirdEndDateMs': _earlyBirdEndDate?.millisecondsSinceEpoch,
      'earlyBirdEndTime': DraftableRegister.timeToMap(_earlyBirdEndTime),
      // 환불 규정 · 연령 · 유형
      'refundPolicy': RefundTier.listToMaps(_refundTiers),
      'ageRestrictionEnabled': _ageRestrictionEnabled,
      'minBirthYear': _minBirthYear,
      'maxBirthYear': _maxBirthYear,
      'partyTypes': _partyTypes.toList(),
      'vibes': _vibes.toList(),
      'tags': _tags,
      // 상세 소개
      'introText': _introCtrl.text,
      'descriptionMode': _descriptionMode.name,
      'autoDescriptionStyle': _autoDescriptionStyle.toMap(),
      'detailBlocks': PartyDetailBlock.listToMaps(
          _detailBlocks.map((d) => d.toBlock()).toList()),
      'detailBlockLocalFiles': {
        for (final d in _detailBlocks)
          if (d.newImageFile != null || d.newVideoFile != null)
            d.id: {
              'image': d.newImageFile?.path,
              'video': d.newVideoFile?.path,
            },
      },
      'detailTheme': _detailTheme.name,
      'detailDecorationIntensity': _detailDecorationIntensity.name,
      'detailDecorationVariantSeed': _detailDecorationVariantSeed,
      // 패키지 옵션
      'packageBookingEnabled': _packageBookingEnabled,
      'packagePriceNote': _packagePriceNoteCtrl.text,
    };
  }

  /// 객실 목록의 임시저장 스냅샷.
  ///
  /// 지금은 "숙박 등록" 아코디언을 접어도 AnimatedCrossFade가 RoomCard를
  /// 높이 0으로 트리에 남겨두므로 `currentState`가 살아 있다. 다만 복원 직후
  /// 첫 프레임처럼 아직 안 그려진 순간에는 null이라, 그때는 복원 데이터를
  /// 쓴다. 마운트돼 있는 동안 읽은 값은 [_roomInitialData]에 계속 덮어써
  /// 폴백이 항상 최신이게 한다(접기 방식이 바뀌어 실제로 언마운트되더라도
  /// 편집 내용이 옛 값으로 되돌아가지 않는다).
  List<Map<String, dynamic>> _roomDraftList() {
    final rooms = <Map<String, dynamic>>[];
    for (int i = 0; i < _roomKeys.length; i++) {
      while (_roomInitialData.length <= i) {
        _roomInitialData.add(null);
      }
      final live = _roomKeys[i].currentState?.getDraftData();
      if (live != null) _roomInitialData[i] = live;
      rooms.add(live ?? _roomInitialData[i] ?? const <String, dynamic>{});
    }
    return rooms;
  }

  @override
  void applyDraftPayload(Map<String, dynamic> p) {
    String s(String key) => (p[key] as String?) ?? '';
    _nameCtrl.text = s('name');
    _detailAddressCtrl.text = s('detailAddress');
    _contactCtrl.text = s('contact');
    _descCtrl.text = s('description');
    final addr = p['address'] as Map?;
    _selectedAddress = addr == null
        ? null
        : AddressResult(
            placeName: addr['placeName'] as String? ?? '',
            address: addr['address'] as String? ?? '',
            roadAddress: addr['roadAddress'] as String? ?? '',
            jibunAddress: addr['jibunAddress'] as String? ?? '',
            latitude: (addr['latitude'] as num?)?.toDouble() ?? 0,
            longitude: (addr['longitude'] as num?)?.toDouble() ?? 0,
          );
    _expandedSection = p['expandedSection'] as String?;

    // 미디어
    _mediaExistingImageUrls =
        [...((p['existingImageUrls'] as List?)?.cast<String>() ?? const [])];
    _mediaExistingVideoUrl = p['existingVideoUrl'] as String?;
    _mediaExistingVideoUid = p['existingVideoUid'] as String?;
    _mediaExistingVideoThumbnailUrl = p['existingVideoThumbnailUrl'] as String?;
    bool anyMissing = false;
    _mediaNewFiles = [];
    for (final path
        in (p['newFilePaths'] as List?)?.cast<String>() ?? const []) {
      if (File(path).existsSync()) {
        _mediaNewFiles.add(XFile(path));
      } else {
        anyMissing = true;
      }
    }
    final coverPick = p['coverPick'] as Map?;
    _mediaCoverPick = coverPick == null
        ? null
        : PartyCoverPick(
            existingImageUrl: coverPick['existingImageUrl'] as String?,
            isExistingVideo: coverPick['isExistingVideo'] as bool? ?? false,
            newImageOrdinal: (coverPick['newImageOrdinal'] as num?)?.toInt(),
            isNewVideo: coverPick['isNewVideo'] as bool? ?? false,
          );

    // 숙박 정보
    _placeType = p['placeType'] as String? ?? ListingConstants.placeTypes.first;
    _checkInTime = DraftableRegister.timeFromMap(p['checkInTime']);
    _checkOutTime = DraftableRegister.timeFromMap(p['checkOutTime']);
    _commonFacilities
      ..clear()
      ..addAll((p['commonFacilities'] as List?)?.cast<String>() ?? const []);
    _customCommonFacilities
      ..clear()
      ..addAll(
          (p['customCommonFacilities'] as List?)?.cast<String>() ?? const []);
    _bookingLinkCtrl.text = s('bookingLink');

    // 객실 재구성 — 새 GlobalKey + 복원 데이터(initialData)로 다시 그린다.
    _roomKeys.clear();
    _roomInitialData.clear();
    for (final raw in (p['rooms'] as List?) ?? const []) {
      final m = Map<String, dynamic>.from(raw as Map);
      if (m['_hasUnsavedImages'] == true) anyMissing = true;
      _roomKeys.add(GlobalKey<RoomCardState>());
      _roomInitialData.add(m);
    }

    // 파티 날짜 슬롯
    _dateSlots = ((p['dateSlots'] as List?) ?? const [])
        .map((raw) {
          final m = raw as Map;
          final ms = (m['dateMs'] as num?)?.toInt();
          if (ms == null) return null;
          final d = DateTime.fromMillisecondsSinceEpoch(ms);
          return PartyDateSlot(
            id: newPartyDateSlotId(),
            date: DateTime(d.year, d.month, d.day),
            startTime: DraftableRegister.timeFromMap(m['start']),
            endTime: DraftableRegister.timeFromMap(m['end']),
            isAutoGenerated: m['auto'] as bool? ?? false,
          );
        })
        .whereType<PartyDateSlot>()
        .toList();
    _recruitDeadlineTime =
        DraftableRegister.timeFromMap(p['recruitDeadlineTime']);
    _weeklyRepeatEnabled = p['weeklyRepeatEnabled'] as bool? ?? false;
    final wrMs = (p['weeklyRepeatEndDateMs'] as num?)?.toInt();
    _weeklyRepeatEndDate =
        wrMs != null ? DateTime.fromMillisecondsSinceEpoch(wrMs) : null;
    _weeklyRepeatCount = (p['weeklyRepeatCount'] as num?)?.toInt();
    _weeklyRepeatExcludedDates = {
      ...((p['weeklyRepeatExcludedDates'] as List?)?.cast<String>() ?? const [])
    };

    // 다차수 라운드 — 기존 것을 정리하고 새로 만든다.
    for (final r in _extraRounds) {
      r.dispose();
    }
    _extraRounds.clear();
    _hasMultipleRounds = p['hasMultipleRounds'] as bool? ?? false;
    _roundCapacityMode = p['roundCapacityMode'] as String? ?? 'unified';
    for (final raw in (p['extraRounds'] as List?) ?? const []) {
      final m = raw as Map;
      _extraRounds.add(PartyRoundDraft(
        id: m['id'] as String?,
        label: m['label'] as String? ?? '',
        time: DraftableRegister.timeFromMap(m['time']),
        capacity: m['capacity'] as String?,
        maleCapacity: m['maleCapacity'] as String?,
        femaleCapacity: m['femaleCapacity'] as String?,
        maleFee: m['maleFee'] as String?,
        femaleFee: m['femaleFee'] as String?,
      ));
    }

    // 성별·인원·참가비
    _genderLimit = p['genderLimit'] as String? ?? 'all';
    _genderCapacityMode = p['genderCapacityMode'] as String? ?? 'unlimited';
    _genderMode = p['genderMode'] as String? ?? '';
    _capacityCtrl.text = s('capacityText');
    _maleCapacityCtrl.text = s('maleCapacityText');
    _femaleCapacityCtrl.text = s('femaleCapacityText');
    _maleFeeCtrl.text = s('maleFeeText');
    _femaleFeeCtrl.text = s('femaleFeeText');
    _earlyBirdEnabled = p['earlyBirdEnabled'] as bool? ?? false;
    _earlyBirdPercentCtrl.text = s('earlyBirdPercentText');
    final ebMs = (p['earlyBirdEndDateMs'] as num?)?.toInt();
    _earlyBirdEndDate =
        ebMs != null ? DateTime.fromMillisecondsSinceEpoch(ebMs) : null;
    _earlyBirdEndTime = DraftableRegister.timeFromMap(p['earlyBirdEndTime']);

    _refundTiers = RefundTier.listFromDynamic(p['refundPolicy']);
    _ageRestrictionEnabled = p['ageRestrictionEnabled'] as bool? ?? false;
    _minBirthYear =
        (p['minBirthYear'] as num?)?.toInt() ?? birthYearFromAge(31);
    _maxBirthYear =
        (p['maxBirthYear'] as num?)?.toInt() ?? birthYearFromAge(23);
    _partyTypes
      ..clear()
      ..addAll((p['partyTypes'] as List?)?.cast<String>() ?? const []);
    _vibes
      ..clear()
      ..addAll((p['vibes'] as List?)?.cast<String>() ?? const []);
    _tags = [...((p['tags'] as List?)?.cast<String>() ?? const [])];

    // 상세 소개 — 기존 블록을 정리하고 새로 만든다.
    _introCtrl.text = s('introText');
    for (final d in _detailBlocks) {
      d.dispose();
    }
    _detailBlocks = PartyDetailBlock.listFromDynamic(p['detailBlocks'])
        .map((b) => PartyDetailBlockDraft.fromBlock(b))
        .toList();
    final blockFiles = p['detailBlockLocalFiles'] as Map?;
    if (blockFiles != null) {
      for (final block in _detailBlocks) {
        final entry = blockFiles[block.id] as Map?;
        if (entry == null) continue;
        final imgPath = entry['image'] as String?;
        final vidPath = entry['video'] as String?;
        if (imgPath != null) {
          if (File(imgPath).existsSync()) {
            block.newImageFile = XFile(imgPath);
          } else {
            anyMissing = true;
          }
        }
        if (vidPath != null) {
          if (File(vidPath).existsSync()) {
            block.newVideoFile = XFile(vidPath);
          } else {
            anyMissing = true;
          }
        }
      }
    }
    _descriptionMode =
        partyDescriptionModeFromString(p['descriptionMode'] as String?);
    _autoDescriptionStyle = PartyAutoDescriptionStyle.fromMap(
        p['autoDescriptionStyle'] as Map<String, dynamic>?);
    _detailTheme = partyDetailThemeKeyFromString(p['detailTheme'] as String?);
    _detailDecorationIntensity = partyDetailDecorationIntensityFromString(
        p['detailDecorationIntensity'] as String?);
    _detailDecorationVariantSeed =
        (p['detailDecorationVariantSeed'] as num?)?.toInt() ?? 0;

    _packageBookingEnabled = p['packageBookingEnabled'] as bool? ?? false;
    _packagePriceNoteCtrl.text = s('packagePriceNote');

    draftMediaNeedsReselect = anyMissing;
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      _nameCtrl,
      _detailAddressCtrl,
      _contactCtrl,
      _descCtrl,
      _customFacilityCtrl,
      _bookingLinkCtrl,
      _capacityCtrl,
      _maleCapacityCtrl,
      _femaleCapacityCtrl,
      _maleFeeCtrl,
      _femaleFeeCtrl,
      _earlyBirdPercentCtrl,
      _introCtrl,
      _packagePriceNoteCtrl,
    ]) {
      c.addListener(markDraftDirty);
    }
    initDraft();
  }

  // 섹션별 스크롤 앵커
  final _basicInfoKey = GlobalKey();
  final _photosKey = GlobalKey();
  final _roomsKey = GlobalKey();
  final _partyDateKey = GlobalKey();
  final _partyCapacityKey = GlobalKey();
  final _partyFeeKey = GlobalKey();
  final _partyIntroKey = GlobalKey();

  // ── 아코디언 펼침 상태 — 'accommodation' | 'party' | null(둘 다 접힘).
  String? _expandedSection;

  // ── 공통 정보 ────────────────────────────────────────────────────────
  final _nameCtrl = PartyTitleController();
  final _detailAddressCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  AddressResult? _selectedAddress;
  bool _showAddressError = false;

  // ── 사진/동영상 — 파티·장소 등록과 동일한 공용 위젯 재사용. 신규 등록만
  // 지원하므로 existing* 필드는 항상 빈 값으로 시작한다.
  List<String> _mediaExistingImageUrls = [];
  String? _mediaExistingVideoUrl;
  String? _mediaExistingVideoUid;
  String? _mediaExistingVideoThumbnailUrl;
  List<XFile> _mediaNewFiles = [];
  PartyCoverPick? _mediaCoverPick;
  bool _showImageError = false;

  // ── 숙박 정보 ────────────────────────────────────────────────────────
  String _placeType = ListingConstants.placeTypes.first;
  TimeOfDay? _checkInTime;
  TimeOfDay? _checkOutTime;
  final List<GlobalKey<RoomCardState>> _roomKeys = [];
  bool _showRoomError = false;
  final Set<String> _commonFacilities = {};
  final Set<String> _customCommonFacilities = {};
  final _customFacilityCtrl = TextEditingController();
  bool _showCustomFacilityInput = false;
  final _bookingLinkCtrl = TextEditingController();

  // ── 파티 날짜/시간(다중 날짜 + 매주 반복) — party_register_screen.dart와
  // 동일하게, 슬롯마다 독립된 문서가 된다(_submit() 참고).
  List<PartyDateSlot> _dateSlots = [];
  TimeOfDay? _recruitDeadlineTime;
  bool _weeklyRepeatEnabled = false;
  DateTime? _weeklyRepeatEndDate;
  int? _weeklyRepeatCount;
  Set<String> _weeklyRepeatExcludedDates = {};
  bool _showDateError = false;

  // ── 다차수(1차/2차) 라운드 ────────────────────────────────────────────
  bool _hasMultipleRounds = false;
  String _roundCapacityMode = 'unified'; // 'unified' | 'perRound'
  final List<PartyRoundDraft> _extraRounds = [];

  // ── 성별 및 모집 인원 ─────────────────────────────────────────────────
  String _genderLimit = 'all';
  String _genderCapacityMode = 'unlimited'; // 'unlimited' | 'separate'
  String _genderMode = '';
  final _capacityCtrl = TextEditingController();
  final _maleCapacityCtrl = TextEditingController();
  final _femaleCapacityCtrl = TextEditingController();
  bool _showCapacityError = false;

  // ── 참가비 + 얼리버드 ─────────────────────────────────────────────────
  final _maleFeeCtrl = TextEditingController();
  final _femaleFeeCtrl = TextEditingController();
  bool _earlyBirdEnabled = false;
  final _earlyBirdPercentCtrl = TextEditingController();
  DateTime? _earlyBirdEndDate;
  TimeOfDay? _earlyBirdEndTime;
  bool _showFeeError = false;

  // ── 환불 규정 ─────────────────────────────────────────────────────────
  List<RefundTier> _refundTiers = [];

  // ── 연령대 설정 ──────────────────────────────────────────────────────
  bool _ageRestrictionEnabled = false;
  int _minBirthYear = birthYearFromAge(31);
  int _maxBirthYear = birthYearFromAge(23);

  // ── 파티 유형 · 분위기 · 태그 ─────────────────────────────────────────
  final Set<String> _partyTypes = {};
  final Set<String> _vibes = {};
  List<String> _tags = [];

  // ── 상세 소개 — 간편 자동 꾸미기(auto) / 직접 상세페이지 만들기(blocks).
  final _introCtrl = TextEditingController();
  PartyDescriptionMode _descriptionMode = PartyDescriptionMode.auto;
  PartyAutoDescriptionStyle _autoDescriptionStyle =
      const PartyAutoDescriptionStyle();
  List<PartyDetailBlockDraft> _detailBlocks = [];
  PartyDetailThemeKey _detailTheme = PartyDetailThemeKey.partychu;
  PartyDetailDecorationIntensity _detailDecorationIntensity =
      PartyDetailDecorationIntensity.standard;
  int _detailDecorationVariantSeed = 0;
  bool _showIntroError = false;
  bool _showDetailBlocksError = false;

  // ── 패키지 옵션 — v1은 플래그만 저장(실제 결제 연동은 후속 작업).
  bool _packageBookingEnabled = false;
  final _packagePriceNoteCtrl = TextEditingController();

  bool _isUploading = false;
  String _uploadStatus = '';

  @override
  void dispose() {
    disposeDraft();
    _scrollCtrl.dispose();
    _nameCtrl.dispose();
    _detailAddressCtrl.dispose();
    _contactCtrl.dispose();
    _descCtrl.dispose();
    _customFacilityCtrl.dispose();
    _bookingLinkCtrl.dispose();
    _capacityCtrl.dispose();
    _maleCapacityCtrl.dispose();
    _femaleCapacityCtrl.dispose();
    _maleFeeCtrl.dispose();
    _femaleFeeCtrl.dispose();
    _earlyBirdPercentCtrl.dispose();
    _introCtrl.dispose();
    _packagePriceNoteCtrl.dispose();
    for (final r in _extraRounds) {
      r.dispose();
    }
    for (final d in _detailBlocks) {
      d.dispose();
    }
    super.dispose();
  }

  // ── 미디어 ───────────────────────────────────────────────────────────

  bool _isVideoFile(XFile f) {
    final p = f.path.toLowerCase();
    return p.endsWith('.mp4') || p.endsWith('.mov');
  }

  bool get _mediaHasVideo =>
      _mediaExistingVideoUrl != null || _mediaNewFiles.any(_isVideoFile);

  String? _mediaSummary() {
    final photoCount = _mediaExistingImageUrls.length +
        _mediaNewFiles.where((f) => !_isVideoFile(f)).length;
    final parts = <String>[];
    if (photoCount > 0) parts.add('사진 $photoCount장');
    if (_mediaHasVideo) parts.add('동영상 1개');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _openMediaPicker() async {
    final result = await Navigator.push<PartyMediaSelection>(
      context,
      webFramedRoute((_) => PartyMediaPickerScreen(
          existingImageUrls: _mediaExistingImageUrls,
          existingVideoUrl: _mediaExistingVideoUrl,
          existingVideoUid: _mediaExistingVideoUid,
          existingVideoThumbnailUrl: _mediaExistingVideoThumbnailUrl,
          newMedia: _mediaNewFiles,
          coverPick: _mediaCoverPick,
          showSpotifySection: false,
          showVideoCropButton: false,
          maxImages: 10,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _mediaExistingImageUrls = result.existingImageUrls;
      _mediaExistingVideoUrl = result.existingVideoUrl;
      _mediaExistingVideoUid = result.existingVideoUid;
      _mediaExistingVideoThumbnailUrl = result.existingVideoThumbnailUrl;
      _mediaNewFiles = result.newMedia;
      _mediaCoverPick = result.coverPick;
      _showImageError = false;
    });
  }

  // ── 룸(객실 유형) ────────────────────────────────────────────────────

  void _addRoom() => setState(() {
    _roomKeys.add(GlobalKey<RoomCardState>());
    _roomInitialData.add(null);
    _showRoomError = false;
  });

  void _removeRoom(int index) => setState(() {
    _roomKeys.removeAt(index);
    if (index < _roomInitialData.length) _roomInitialData.removeAt(index);
  });

  // ── 편의시설 ─────────────────────────────────────────────────────────

  static const _facilityOptions = ListingConstants.placeFacilities;

  void _addCustomFacility() {
    final text = _customFacilityCtrl.text.trim();
    if (text.isEmpty) return;
    if (_facilityOptions.contains(text)) {
      setState(() {
        _commonFacilities.add(text);
        _customFacilityCtrl.clear();
        _showCustomFacilityInput = false;
      });
      return;
    }
    setState(() {
      _customCommonFacilities.add(text);
      _customFacilityCtrl.clear();
      _showCustomFacilityInput = false;
    });
  }

  // ── 체크인/체크아웃 시간 ─────────────────────────────────────────────

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickCheckTime(bool isCheckIn) async {
    final picked = await showCustomTimePicker(
      context,
      initial: (isCheckIn ? _checkInTime : _checkOutTime) ??
          TimeOfDay(hour: isCheckIn ? 15 : 11, minute: 0),
      title: isCheckIn ? '체크인 시간' : '체크아웃 시간',
    );
    if (picked == null) return;
    setState(() {
      if (isCheckIn) {
        _checkInTime = picked;
      } else {
        _checkOutTime = picked;
      }
    });
  }

  // ── 파티: 날짜 목록(다중 날짜 + 매주 반복) ───────────────────────────

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

  // ── 파티: 성별 및 모집 인원 ───────────────────────────────────────────

  Future<void> _openGenderCapacitySheet() async {
    final result = await showGenderCapacitySheet(
      context,
      initial: GenderCapacityDraft(
        genderLimit: _genderLimit,
        genderCapacityMode: _genderCapacityMode,
        genderMode: _genderMode,
        capacity: int.tryParse(_capacityCtrl.text.trim()),
        maleCapacity: int.tryParse(_maleCapacityCtrl.text.trim()),
        femaleCapacity: int.tryParse(_femaleCapacityCtrl.text.trim()),
      ),
    );
    if (result == null) return;
    setState(() {
      final prevGenderLimit = _genderLimit;
      _genderLimit = result.genderLimit;
      _genderCapacityMode = result.genderCapacityMode;
      _genderMode = result.genderMode;
      _capacityCtrl.text = result.capacity?.toString() ?? '';
      _maleCapacityCtrl.text = result.maleCapacity?.toString() ?? '';
      _femaleCapacityCtrl.text = result.femaleCapacity?.toString() ?? '';
      if (prevGenderLimit != _genderLimit) {
        if (_genderLimit == 'male') _femaleFeeCtrl.clear();
        if (_genderLimit == 'female') _maleFeeCtrl.clear();
      }
      _showCapacityError = false;
    });
  }

  (int, int, int) _resolveCapacities() {
    if (_genderCapacityMode == 'unlimited') {
      final max = int.tryParse(_capacityCtrl.text.trim()) ?? 0;
      return (0, 0, max);
    }
    final male = (_genderLimit == 'all' || _genderLimit == 'male')
        ? int.tryParse(_maleCapacityCtrl.text.trim()) ?? 0
        : 0;
    final female = (_genderLimit == 'all' || _genderLimit == 'female')
        ? int.tryParse(_femaleCapacityCtrl.text.trim()) ?? 0
        : 0;
    return (male, female, male + female);
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
      final cap = _capacityCtrl.text.trim();
      if (cap.isEmpty) return null;
      return '$label · $cap명';
    }
    final m = _maleCapacityCtrl.text.trim();
    final f = _femaleCapacityCtrl.text.trim();
    if (m.isEmpty && f.isEmpty) return null;
    return '$label · 남 ${m.isEmpty ? '-' : m}명 / 여 ${f.isEmpty ? '-' : f}명';
  }

  String? _capacityErrorText() {
    if (_genderCapacityMode == 'unlimited') {
      return _capacityCtrl.text.trim().isEmpty ? '전체 최대 인원을 입력해줘' : null;
    }
    if (_maleCapacityCtrl.text.trim().isEmpty) return '남자 모집 인원을 입력해줘';
    if (_femaleCapacityCtrl.text.trim().isEmpty) return '여자 모집 인원을 입력해줘';
    return null;
  }

  bool _validateCapacityInputs() {
    if (_genderCapacityMode == 'unlimited') {
      if (_capacityCtrl.text.trim().isEmpty) {
        _msg('전체 최대 인원을 입력해줘');
        setState(() => _showCapacityError = true);
        return false;
      }
    } else {
      if (_maleCapacityCtrl.text.trim().isEmpty) {
        _msg('남자 모집 인원을 입력해줘');
        setState(() => _showCapacityError = true);
        return false;
      }
      if (_femaleCapacityCtrl.text.trim().isEmpty) {
        _msg('여자 모집 인원을 입력해줘');
        setState(() => _showCapacityError = true);
        return false;
      }
    }
    setState(() => _showCapacityError = false);

    if (_genderLimit != 'female') {
      final err = _validateFee(_maleFeeCtrl.text);
      if (err != null) {
        _msg(err);
        setState(() => _showFeeError = true);
        return false;
      }
    }
    if (_genderLimit != 'male') {
      final err = _validateFee(_femaleFeeCtrl.text);
      if (err != null) {
        _msg(err);
        setState(() => _showFeeError = true);
        return false;
      }
    }
    if (_earlyBirdEnabled) {
      final err = _validateEarlyBird();
      if (err != null) {
        setState(() => _showFeeError = true);
        _msg(err);
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
        _msg('${i + 2}차 시간을 선택해줘');
        return false;
      }
    }
    if (_roundCapacityMode != 'perRound') return true;

    bool filled(TextEditingController c) => c.text.trim().isNotEmpty;

    if (_genderCapacityMode == 'unlimited') {
      if (!filled(_capacityCtrl)) {
        _msg('1차 최대 인원을 입력해줘');
        return false;
      }
    } else {
      if (!filled(_maleCapacityCtrl) || !filled(_femaleCapacityCtrl)) {
        _msg('1차 남녀 모집 인원을 입력해줘');
        return false;
      }
    }
    if (_genderLimit != 'female' && _validateFee(_maleFeeCtrl.text) != null) {
      _msg('1차 참가비를 입력해줘');
      return false;
    }
    if (_genderLimit != 'male' && _validateFee(_femaleFeeCtrl.text) != null) {
      _msg('1차 참가비를 입력해줘');
      return false;
    }

    for (var i = 0; i < _extraRounds.length; i++) {
      final r = _extraRounds[i];
      final n = i + 2;
      if (_genderCapacityMode == 'unlimited') {
        if (!filled(r.capacityCtrl)) {
          _msg('$n차 최대 인원을 입력해줘');
          return false;
        }
      } else {
        if (!filled(r.maleCapacityCtrl) || !filled(r.femaleCapacityCtrl)) {
          _msg('$n차 남녀 모집 인원을 입력해줘');
          return false;
        }
      }
      if (_genderLimit != 'female' && _validateFee(r.maleFeeCtrl.text) != null) {
        _msg('$n차 참가비를 입력해줘 (무료면 0)');
        return false;
      }
      if (_genderLimit != 'male' && _validateFee(r.femaleFeeCtrl.text) != null) {
        _msg('$n차 참가비를 입력해줘 (무료면 0)');
        return false;
      }
    }
    return true;
  }

  Widget _roundModeChip(String title, String subtitle, String mode) {
    final selected = _roundCapacityMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _roundCapacityMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF3EFFA) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _kAccent : const Color(0xFFE8EBF2),
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
                color: selected ? _kAccent : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
          ],
        ),
      ),
    );
  }

  // ── 파티: 참가비 + 얼리버드 ───────────────────────────────────────────

  Future<void> _openFeeSheet() async {
    final result = await showFeeSheet(
      context,
      genderLimit: _genderLimit,
      initial: FeeDraft(
        maleFee: int.tryParse(_maleFeeCtrl.text.trim()),
        femaleFee: int.tryParse(_femaleFeeCtrl.text.trim()),
        earlyBirdEnabled: _earlyBirdEnabled,
        earlyBirdPercent: int.tryParse(_earlyBirdPercentCtrl.text.trim()),
        earlyBirdEndDate: _earlyBirdEndDate,
        earlyBirdEndTime: _earlyBirdEndTime,
      ),
    );
    if (result == null) return;
    setState(() {
      _maleFeeCtrl.text = result.maleFee?.toString() ?? '';
      _femaleFeeCtrl.text = result.femaleFee?.toString() ?? '';
      _earlyBirdEnabled = result.earlyBirdEnabled;
      _earlyBirdPercentCtrl.text = result.earlyBirdPercent?.toString() ?? '';
      _earlyBirdEndDate = result.earlyBirdEndDate;
      _earlyBirdEndTime = result.earlyBirdEndTime;
      _showFeeError = false;
    });
  }

  String? _validateFee(String? v) {
    if (v == null || v.trim().isEmpty) return '참가비를 입력해주세요. (무료인 경우 0 입력)';
    final fee = int.tryParse(v.trim());
    if (fee == null || fee < 0) return '숫자만 입력해주세요.';
    if (fee % 1000 != 0) return '참가비는 1,000원 단위로 입력해주세요.';
    return null;
  }

  String? _validateEarlyBird() {
    final pct = int.tryParse(_earlyBirdPercentCtrl.text.trim());
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
        ? (int.tryParse(_maleFeeCtrl.text.trim()) ?? 0)
        : 0;
    final femaleFee = _genderLimit != 'male'
        ? (int.tryParse(_femaleFeeCtrl.text.trim()) ?? 0)
        : 0;
    if (maleFee <= 0 && femaleFee <= 0) {
      return '무료 파티는 얼리버드 할인을 사용할 수 없습니다.';
    }
    return null;
  }

  String? _feeSummary() {
    final showMale = _genderLimit != 'female';
    final showFemale = _genderLimit != 'male';
    final maleFee = int.tryParse(_maleFeeCtrl.text.trim());
    final femaleFee = int.tryParse(_femaleFeeCtrl.text.trim());
    final parts = <String>[];
    if (showMale && maleFee != null) parts.add('남 ${EarlyBird.formatPrice(maleFee)}');
    if (showFemale && femaleFee != null) parts.add('여 ${EarlyBird.formatPrice(femaleFee)}');
    if (parts.isEmpty) return null;
    var summary = parts.join(' / ');
    if (_earlyBirdEnabled) summary += ' · 얼리버드 ${_earlyBirdPercentCtrl.text}%';
    return summary;
  }

  String? _feeErrorText() {
    if (_genderLimit != 'female') {
      final err = _validateFee(_maleFeeCtrl.text);
      if (err != null) return err;
    }
    if (_genderLimit != 'male') {
      final err = _validateFee(_femaleFeeCtrl.text);
      if (err != null) return err;
    }
    if (_earlyBirdEnabled) {
      final err = _validateEarlyBird();
      if (err != null) return err;
    }
    return null;
  }

  // ── 파티: 환불 규정 ───────────────────────────────────────────────────

  Future<void> _openRefundPolicy() async {
    await Navigator.push(
      context,
      webFramedRoute((_) => PartyRefundPolicyScreen(
          initialTiers: _refundTiers,
          onChanged: (tiers) {
            _refundTiers = tiers;
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  String? _refundSummary() =>
      _refundTiers.isEmpty ? null : '${_refundTiers.length}단계 환불 규정 설정됨';

  // ── 파티: 연령대 설정 ─────────────────────────────────────────────────

  Future<void> _openAgeRestrictionSheet() async {
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

  String? _ageSummary() => _ageRestrictionEnabled
      ? '${ageFromBirthYear(_maxBirthYear)}세 ~ ${ageFromBirthYear(_minBirthYear)}세'
      : null;

  // ── 파티: 유형 · 분위기 · 태그 ────────────────────────────────────────

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

  String? _typeVibeSummary() {
    final all = [
      ..._partyTypes.map(PartyConstants.labelFor),
      ..._vibes,
      ..._tags.map((t) => '#$t'),
    ];
    return all.isEmpty ? null : all.join(' · ');
  }

  // ── 파티: 상세 소개(간편 자동 꾸미기 / 직접 상세페이지 만들기) ───────

  Future<void> _openDescriptionEditor() async {
    final chosen = await showPartyDetailDescriptionModeSheet(
      context,
      current: _descriptionMode,
    );
    if (chosen == null || !mounted) return;

    if (chosen != _descriptionMode) {
      final hasContentInCurrentMode = _descriptionMode == PartyDescriptionMode.auto
          ? _introCtrl.text.trim().isNotEmpty
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
      final text = _introCtrl.text.trim();
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
      webFramedRoute((_) => PartyIntroScreen(
          initialIntro: _introCtrl.text,
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
      _introCtrl.text = result.intro;
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

  Future<void> _openDetailBlockEditor() async {
    var initialBlocks = _detailBlocks;
    final seeded = _detailBlocks.isEmpty;
    if (seeded) {
      initialBlocks = [
        PartyDetailBlockDraft.fromBlock(
          PartyDetailBlock(
            id: generatePartyDetailBlockId(),
            type: PartyDetailBlockType.paragraph,
            text: _introCtrl.text.trim(),
          ),
        ),
      ];
    }
    final result = await Navigator.push<PartyDetailBlockEditorResult>(
      context,
      webFramedRoute((_) => PartyDetailBlockEditorScreen(
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

  void _scrollToKey(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.05,
        );
      }
    });
  }

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );

  // ── 제출 ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    bool hasError = false;
    GlobalKey? firstErrorKey;

    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) {
      hasError = true;
      firstErrorKey ??= _basicInfoKey;
    }
    if (_selectedAddress == null) {
      setState(() => _showAddressError = true);
      hasError = true;
      firstErrorKey ??= _basicInfoKey;
    }
    if (_mediaExistingImageUrls.isEmpty && _mediaNewFiles.isEmpty) {
      setState(() => _showImageError = true);
      hasError = true;
      firstErrorKey ??= _photosKey;
    }
    if (_roomKeys.isEmpty) {
      setState(() => _showRoomError = true);
      hasError = true;
      firstErrorKey ??= _roomsKey;
    }
    final dateError = _dateSlots.isEmpty;
    final timeError = !dateError && _dateSlots.any((s) => s.startTime == null);
    if (dateError || timeError) {
      setState(() => _showDateError = true);
      hasError = true;
      firstErrorKey ??= _partyDateKey;
      setState(() => _expandedSection = 'party');
    }
    final introError = _descriptionMode == PartyDescriptionMode.auto &&
        _introCtrl.text.trim().isEmpty;
    final detailBlocksError = _descriptionMode == PartyDescriptionMode.blocks &&
        _detailBlocks.every((d) => d.isEmpty);
    if (introError || detailBlocksError) {
      setState(() {
        _showIntroError = introError;
        _showDetailBlocksError = detailBlocksError;
      });
      hasError = true;
      firstErrorKey ??= _partyIntroKey;
      setState(() => _expandedSection = 'party');
    }

    if (hasError) {
      // 오류 항목이 접힌 아코디언(숙박/파티) 안에 있으면 먼저 그 섹션을 펼쳐
      // 빨간 오류 표시가 실제로 보이게 한 뒤 스크롤한다. 그리고 조용히 끝내지
      // 않고 항상 안내 스낵바를 띄운다(버튼을 눌러도 아무 반응 없어 보이는
      // 문제 방지 — 요구사항 3·6).
      if (firstErrorKey == _roomsKey) {
        setState(() => _expandedSection = 'accommodation');
      } else if (firstErrorKey == _partyDateKey ||
          firstErrorKey == _partyCapacityKey ||
          firstErrorKey == _partyFeeKey ||
          firstErrorKey == _partyIntroKey) {
        setState(() => _expandedSection = 'party');
      }
      _scrollToKey(firstErrorKey!);
      _msg('입력하지 않은 필수 항목이 있어요. 표시된 부분을 확인해주세요.');
      return;
    }

    bool roomsValid = true;
    for (final key in _roomKeys) {
      final state = key.currentState;
      if (state == null || !state.validate()) roomsValid = false;
    }
    if (!roomsValid) {
      setState(() => _expandedSection = 'accommodation');
      _scrollToKey(_roomsKey);
      _msg('객실 정보를 확인해주세요.');
      return;
    }

    if (!_validateCapacityInputs()) {
      setState(() => _expandedSection = 'party');
      _scrollToKey(_showFeeError ? _partyFeeKey : _partyCapacityKey);
      _msg('파티 인원/참가비를 확인해주세요.');
      return;
    }
    if (!_validateRoundsInputs()) {
      setState(() => _expandedSection = 'party');
      _scrollToKey(_partyCapacityKey);
      _msg('라운드(차수) 정보를 확인해주세요.');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _msg('로그인이 필요합니다');
      return;
    }

    if (!CloudflareService.isConfigured) {
      _msg('현재 파일 업로드 서비스를 사용할 수 없습니다. 잠시 후 다시 시도해주세요.');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = '사진 업로드 중...';
    });

    final uploadedBlockImageUrls = <String>[];
    final uploadedBlockVideoUids = <String>[];

    try {
      // ── 공유 미디어 업로드(장소·파티 등록과 동일한 방식) ────────────
      final newMedia = _mediaNewFiles;
      final newImageUrls = <String>[];
      String? newVideoUid;
      String? newVideoUrl;
      String? newVideoThumbnailUrl;

      int done = 0;
      for (final file in newMedia) {
        if (_isVideoFile(file)) {
          setState(() => _uploadStatus = '동영상을 올리는 중...');
          final result = await CloudflareService.uploadVideo(File(file.path));
          newVideoUid = result['videoUid'];
          newVideoUrl = result['videoUrl'];
          newVideoThumbnailUrl = result['videoThumbnailUrl'];
        } else {
          done++;
          setState(
            () => _uploadStatus = '사진 업로드 중... ($done/${newMedia.length})',
          );
          newImageUrls.add(await CloudflareService.uploadImage(File(file.path)));
        }
      }

      final imageUrls = [..._mediaExistingImageUrls, ...newImageUrls];
      final finalVideoUrl = newVideoUrl ?? _mediaExistingVideoUrl;
      final finalVideoUid = newVideoUid ?? _mediaExistingVideoUid;
      final finalVideoThumbnailUrl =
          newVideoThumbnailUrl ?? _mediaExistingVideoThumbnailUrl;

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
        coverImageUrl = ordinal < newImageUrls.length
            ? newImageUrls[ordinal]
            : (imageUrls.isNotEmpty ? imageUrls.first : null);
        coverThumbnailUrl = coverImageUrl;
      } else if (imageUrls.isNotEmpty) {
        coverImageUrl = imageUrls.first;
        coverThumbnailUrl = coverImageUrl;
      } else if (finalVideoUrl != null) {
        coverMediaType = 'video';
        coverVideoUid = finalVideoUid;
        coverVideoUrl = finalVideoUrl;
        coverThumbnailUrl = finalVideoThumbnailUrl;
      }
      if (coverMediaType == 'image' && coverImageUrl != null) {
        imageUrls.remove(coverImageUrl);
        imageUrls.insert(0, coverImageUrl);
      }

      final finalDetailBlocks = await _resolveDetailBlocksForSubmit(
        uploadedBlockImageUrls,
        uploadedBlockVideoUids,
      );

      // ── 문서 참조 미리 발급 — 서로의 id로 연결해야 하므로 set() 전에
      // 확정해둔다. bundleId는 place 문서 자신의 id를 그대로 쓴다. 파티는
      // 날짜 슬롯 수만큼 문서가 생기므로, 대표(0번째) 슬롯의 문서 id만
      // 장소 문서의 linkedPartyId가 가리킨다.
      final placeRef = FirebaseFirestore.instance.collection('places').doc();
      final partiesCol = FirebaseFirestore.instance.collection('parties');
      final partyRefs = List.generate(_dateSlots.length, (_) => partiesCol.doc());
      final primaryPartyRef = partyRefs.first;
      final bundleId = placeRef.id;
      final seriesId = primaryPartyRef.id;

      // ── 룸(객실 유형) 데이터 수집 — 장소 등록과 동일한 순서로, 장소
      // 문서에 넣을 최저가/최대인원 집계도 여기서 먼저 계산한다.
      final roomDataList = <Map<String, dynamic>>[];
      for (var i = 0; i < _roomKeys.length; i++) {
        setState(
          () => _uploadStatus = '객실 ${i + 1}/${_roomKeys.length} 정보 준비 중...',
        );
        final state = _roomKeys[i].currentState;
        if (state == null) {
          throw Exception('룸[$i] state == null — 예상치 못한 위젯 트리 제거');
        }
        roomDataList.add(await state.uploadAndGetData(uid, placeRef.id));
      }
      final prices = roomDataList
          .map((r) => (r['pricePerHour'] as num?)?.toInt() ?? 0)
          .where((p) => p > 0);
      final capacities = roomDataList
          .map((r) => (r['capacityMax'] as num?)?.toInt() ?? 0)
          .where((c) => c > 0);
      final minPrice =
          prices.isEmpty ? 0 : prices.reduce((a, b) => a < b ? a : b);
      final maxRoomCapacity =
          capacities.isEmpty ? 0 : capacities.reduce((a, b) => a > b ? a : b);

      setState(() => _uploadStatus = '등록 정보 저장 중...');

      final commonDesc = _descCtrl.text.trim();
      final contactPhone = _contactCtrl.text.trim();

      final commonFacilities = {
        ..._commonFacilities,
        ..._customCommonFacilities,
      }.toList();

      // ── places 문서 — 기존 "파티 장소 등록" 셰이프 + 콤보 연결 필드.
      final placeFields = <String, dynamic>{
        'hostId': uid,
        'name': name,
        'type': _placeType,
        'address': _selectedAddress?.roadAddress ?? '',
        'detailAddress': _detailAddressCtrl.text.trim(),
        'lat': _selectedAddress?.latitude ?? 0.0,
        'lng': _selectedAddress?.longitude ?? 0.0,
        'imageUrls': imageUrls,
        if (finalVideoUrl != null) 'videoProvider': 'cloudflare',
        if (finalVideoUid != null) 'videoUid': finalVideoUid,
        if (finalVideoUrl != null) 'videoUrl': finalVideoUrl,
        if (finalVideoThumbnailUrl != null)
          'videoThumbnailUrl': finalVideoThumbnailUrl,
        'coverMediaType': coverMediaType,
        'coverImageUrl': coverImageUrl,
        'coverVideoUid': coverVideoUid,
        'coverVideoUrl': coverVideoUrl,
        'coverThumbnailUrl': coverThumbnailUrl,
        'description': commonDesc,
        'commonFacilities': commonFacilities,
        'pricePerHour': minPrice,
        'capacityMax': maxRoomCapacity,
        'isActive': true,
        'contactPhone': contactPhone,
        // ── 콤보(숙박+파티) 전용 필드 ──────────────────────────────────
        'bundleId': bundleId,
        'linkedPartyId': primaryPartyRef.id,
        'isCombo': true,
        if (_checkInTime != null)
          'accommodationCheckInTime': _fmtTime(_checkInTime!),
        if (_checkOutTime != null)
          'accommodationCheckOutTime': _fmtTime(_checkOutTime!),
        if (_bookingLinkCtrl.text.trim().isNotEmpty)
          'bookingLink': _bookingLinkCtrl.text.trim(),
        'packageBookingEnabled': _packageBookingEnabled,
        if (_packageBookingEnabled &&
            _packagePriceNoteCtrl.text.trim().isNotEmpty)
          'packagePriceNote': _packagePriceNoteCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final (maleCapacity, femaleCapacity, maxCapacity) = _resolveCapacities();
      final maleFee = _genderLimit != 'female'
          ? (int.tryParse(_maleFeeCtrl.text.trim()) ?? 0)
          : null;
      final femaleFee = _genderLimit != 'male'
          ? (int.tryParse(_femaleFeeCtrl.text.trim()) ?? 0)
          : null;
      final primarySlot = _dateSlots.first;
      final earlyBirdEndAt = (_earlyBirdEnabled &&
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
      final earlyBirdActuallyEnabled = _earlyBirdEnabled && earlyBirdEndAt != null;

      // ── 다차수 라운드 — 1차(슬롯의 시작 시간 그대로) + 2차 이상.
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

      final roundsField = buildRoundsField(primarySlot.date, primarySlot.startTime!);
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

      // ── parties 문서가 모두 공유하는 필드 — 날짜 종속 필드(date/
      // partyDateTime/recruitDeadlineAt/rounds)는 buildSlotDateFields()로
      // 슬롯마다 따로 계산해 여기 합쳐진다(party_register_screen.dart와
      // 동일한 방식).
      final sharedPartyFields = <String, dynamic>{
        'title': name,
        'location': _selectedAddress?.displayAddress ?? '',
        'address': _selectedAddress?.address ?? '',
        'roadAddress': _selectedAddress?.roadAddress ?? '',
        'jibunAddress': _selectedAddress?.jibunAddress ?? '',
        'placeName': _selectedAddress?.placeName ?? '',
        if (_selectedAddress != null) 'latitude': _selectedAddress!.latitude,
        if (_selectedAddress != null) 'longitude': _selectedAddress!.longitude,
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
        'category': _partyTypes.isEmpty ? '숙박+파티' : _partyTypes.first,
        'partyTypes': _partyTypes.toList(),
        'vibes': _vibes.toList(),
        'tags': _tags,
        'region': RegionData.extractRegion(_selectedAddress?.address ?? ''),
        'district': RegionData.extractDistrict(_selectedAddress?.address ?? ''),
        'ageRestrictionEnabled': _ageRestrictionEnabled,
        if (_ageRestrictionEnabled) 'minBirthYear': _minBirthYear,
        if (_ageRestrictionEnabled) 'maxBirthYear': _maxBirthYear,
        'maleFee': maleFee,
        'femaleFee': femaleFee,
        'refundPolicy': RefundTier.listToMaps(_refundTiers),
        'earlyBirdEnabled': earlyBirdActuallyEnabled,
        'earlyBirdDiscountPercent': earlyBirdActuallyEnabled
            ? (int.tryParse(_earlyBirdPercentCtrl.text.trim()) ?? 0)
            : null,
        'earlyBirdEndAt':
            earlyBirdActuallyEnabled ? Timestamp.fromDate(earlyBirdEndAt) : null,
        'images': imageUrls,
        if (finalVideoUrl != null) 'videoProvider': 'cloudflare',
        if (finalVideoUid != null) 'videoUid': finalVideoUid,
        if (finalVideoUrl != null) 'videoUrl': finalVideoUrl,
        if (finalVideoThumbnailUrl != null)
          'videoThumbnailUrl': finalVideoThumbnailUrl,
        'detailAddress': _detailAddressCtrl.text.trim(),
        'description': _introCtrl.text.trim(),
        'detailBlocks': PartyDetailBlock.listToMaps(finalDetailBlocks),
        'detailTheme': _detailTheme.name,
        'detailDecorationIntensity': _detailDecorationIntensity.name,
        'detailDecorationVariantSeed': _detailDecorationVariantSeed,
        'detailDescriptionMode': _descriptionMode.name,
        'autoDescriptionStyle': _autoDescriptionStyle.toMap(),
        'recruitStatus': '모집중',
        'isRecurring': true,
        'lastUsedAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'isDeleted': false,
        'status': 'active',
        'mainImageUrl': imageUrls.isNotEmpty ? imageUrls.first : null,
        'coverMediaType': coverMediaType,
        'coverImageUrl': coverImageUrl,
        'coverVideoUid': coverVideoUid,
        'coverVideoUrl': coverVideoUrl,
        'coverThumbnailUrl': coverThumbnailUrl,
        'basicCardVideoFocalX': 0.5,
        'basicCardVideoFocalY': 0.5,
        'basicCardVideoScale': 1.0,
        'basicCardPhotoCrops': <String, dynamic>{},
        'hostId': UserSession.userId,
        'hostUid': uid,
        'contactPhone': contactPhone,
        'applicants': <String>[],
        'approvedApplicants': <String>[],
        'approved': true,
        // ── 콤보(숙박+파티) 전용 필드 ──────────────────────────────────
        'bundleId': bundleId,
        'linkedPlaceId': placeRef.id,
        'isCombo': true,
        'packageBookingEnabled': _packageBookingEnabled,
      };

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
          'date': '${formatPartyDate(slot.date)} ${formatPartyTime(slot.startTime)}',
          'partyDateTime': Timestamp.fromDate(slotPartyDateTime),
          if (deadlineDateTime != null)
            'recruitDeadlineAt': Timestamp.fromDate(deadlineDateTime),
          if (_hasMultipleRounds) 'rounds': buildRoundsField(slot.date, slot.startTime!),
        };
      }

      // ── place + party(들) 문서를 배치로 한 번에 커밋한다 — 서로의 id를
      // 이미 참조하므로, 일부만 생기는 상황(원자성 깨짐)을 막는다. 룸
      // 문서는 장소 등록 화면과 동일하게 커밋 이후 순차로 추가한다(룸
      // 하나가 실패해도 장소·파티 연결 자체는 이미 유효하기 때문).
      final batch = FirebaseFirestore.instance.batch();
      batch.set(placeRef, placeFields);
      for (var i = 0; i < _dateSlots.length; i++) {
        final slot = _dateSlots[i];
        batch.set(partyRefs[i], {
          ...sharedPartyFields,
          ...buildSlotDateFields(slot),
          'createdAt': Timestamp.fromDate(DateTime.now()),
        });
      }
      await batch.commit();

      for (var i = 0; i < roomDataList.length; i++) {
        setState(
          () => _uploadStatus = '객실 ${i + 1}/${roomDataList.length} 등록 중...',
        );
        await FirebaseFirestore.instance
            .collection('placeRooms')
            .add(roomDataList[i]);
      }

      // 최종 등록 완료 — 숙박+파티 임시저장은 자동 삭제.
      await deleteCurrentDraft();

      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploadStatus = '';
      });

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: _kAccent),
              SizedBox(width: 8),
              Text('등록 완료', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
            ],
          ),
          content: const Text(
            '숙박+파티가 등록되었어요.\n"파티" 탭과 "장소대여" 탭 양쪽에서 확인할 수 있어요.',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('확인'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      pendingTopTabAfterRegister.value = 0;
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e, st) {
      debugPrint('❌ 숙박+파티 콤보 등록 실패: $e');
      debugPrint('StackTrace:\n$st');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
        });
        _msg('등록 중 오류가 발생했습니다: $e');
      }
    }
  }

  // ── UI 헬퍼 ──────────────────────────────────────────────────────────

  InputDecoration _inputDeco(String hint) => InputDecoration(
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
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );

  Widget _sectionCard({required String title, String? subtitle, required Widget child}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontFamily: 'SeoulHangang',
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                      Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                      Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                      Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                    ])),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black45)),
            ],
            child,
          ],
        ),
      );

  /// "숙박 등록"/"파티 등록"을 하나씩 펼쳐볼 수 있는 아코디언 카드 — 두
  /// 묶음을 동시에 펼치지 않아서 화면이 한 번에 다 길어지지 않는다.
  Widget _collapsibleSection({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    final expanded = _expandedSection == id;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expandedSection = expanded ? null : id),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(icon, color: _kAccent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontFamily: 'SeoulHangang',
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                                shadows: [
                                  Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                                  Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                                  Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                                  Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                                ])),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: const TextStyle(fontSize: 12, color: Colors.black45)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
            crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _facilityChip(String label, {required bool selected}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF3EFFA) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _kAccent : const Color(0xFFDDE1EC)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? _kAccent : Colors.black54,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      );

  Widget _timeBox(String label, TimeOfDay? value, VoidCallback onTap) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  value != null ? formatPartyTime(value) : '시간 선택',
                  style: TextStyle(color: value != null ? Colors.black87 : Colors.black38),
                ),
              ),
            ),
          ],
        ),
      );

  // ── 빌드 ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !draftDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await confirmLeaveWithDraftSave();
        if (leave && mounted) Navigator.of(context).pop();
      },
      child: Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          appBar: AppBar(
            title: const Text('숙박+파티 등록', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])),
            centerTitle: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
            actions: [draftSaveAction()],
            bottom: buildAutoSaveIndicator(),
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                _buildIntroCard(),
                if (draftMediaNeedsReselect) buildMediaReselectBanner(),
                SizedBox(key: _basicInfoKey, height: 0),
                _buildCommonInfo(),
                SizedBox(key: _photosKey, height: 0),
                _buildPhotos(),
                _collapsibleSection(
                  id: 'accommodation',
                  title: '숙박 등록',
                  subtitle: '숙박 유형·체크인/체크아웃·객실·편의시설',
                  icon: Icons.hotel_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAccommodationInfo(),
                      SizedBox(key: _roomsKey, height: 0),
                      _buildRoomsSection(),
                      _buildFacilities(),
                    ],
                  ),
                ),
                _collapsibleSection(
                  id: 'party',
                  title: '파티 등록',
                  subtitle: '날짜·인원·참가비·환불규정·유형/분위기·상세소개',
                  icon: Icons.celebration_outlined,
                  child: _buildPartyInfo(),
                ),
                _buildPackageOption(),
                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isUploading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    child: const Text('숙박+파티 등록하기'),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
        if (_isUploading)
          IgnorePointer(
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 20),
                  Text(_uploadStatus, style: const TextStyle(fontSize: 14, color: Colors.white)),
                ],
              ),
            ),
          ),
      ],
      ),
    );
  }

  // ── 섹션: 안내 카드 ──────────────────────────────────────────────────

  /// 이 등록이 어떤 기능인지 알려주는 접이식 안내 — 폼을 가리지 않도록
  /// 기본은 요약 한 줄만 보여준다(플레이스+파티 등록과 같은 컴포넌트).
  Widget _buildIntroCard() => const ComboIntroCard(
        summary: '게스트하우스·펜션 등에서 숙박과 파티를 함께 운영하시나요?',
        sections: [
          ComboIntroSection(
            lines: [
              '🛏️ 객실과 파티 정보를 한 번에 등록할 수 있어요.',
              '🎉 숙박 이용객에게 진행되는 파티를 함께 소개할 수 있어요.',
              '🔗 숙박 상세페이지와 파티 상세페이지가 서로 연결돼요.',
            ],
          ),
        ],
      );

  // ── 섹션: 공통 정보 ──────────────────────────────────────────────────

  Widget _buildCommonInfo() => _sectionCard(
        title: '공통 정보',
        subtitle: '업체명·주소·사진 등은 숙박과 파티에 함께 쓰여요',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('업체명 *'),
            PartyTitleField(
              controller: _nameCtrl,
              decoration: _inputDeco('예: 강릉 오션뷰 게스트하우스'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '업체명을 입력해주세요' : null,
            ),
            _label('주소 *'),
            GestureDetector(
              onTap: () async {
                final result = await Navigator.push<AddressResult>(
                  context,
                  webFramedRoute((_) => const AddressSearchScreen()),
                );
                if (result != null) {
                  setState(() {
                    _selectedAddress = result;
                    _showAddressError = false;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: _showAddressError ? const Color(0xFFFFF0F0) : const Color(0xFFF7F7FA),
                  borderRadius: BorderRadius.circular(12),
                  border: _showAddressError ? Border.all(color: Colors.redAccent) : null,
                ),
                child: Row(
                  children: [
                    Icon(Icons.search,
                        size: 18, color: _showAddressError ? Colors.redAccent : _kAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedAddress?.roadAddress ?? '주소를 검색해주세요',
                        style: TextStyle(
                          fontSize: 14,
                          color: _selectedAddress == null
                              ? (_showAddressError ? Colors.redAccent : Colors.black38)
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showAddressError)
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 4),
                child: Text('주소를 검색해주세요', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
              ),
            _label('상세주소'),
            TextFormField(
              controller: _detailAddressCtrl,
              decoration: _inputDeco('동/호수, 층수 등'),
            ),
            _label('연락처'),
            TextFormField(
              controller: _contactCtrl,
              keyboardType: TextInputType.phone,
              decoration: _inputDeco('예: 010-1234-5678'),
            ),
            _label('소개'),
            TextFormField(
              controller: _descCtrl,
              maxLines: 4,
              decoration: _inputDeco('업체 특징, 분위기, 오시는 길 등을 소개해주세요'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '소개를 입력해주세요' : null,
            ),
          ],
        ),
      );

  Widget _buildPhotos() => _sectionCard(
        title: '대표 사진·동영상',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('사진 최대 10장 · 동영상 1개(최대 30초) *'),
            if (_mediaSummary() != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_mediaSummary()!, style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ),
            OutlinedButton.icon(
              onPressed: _openMediaPicker,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(_mediaSummary() == null ? '사진/동영상 등록' : '사진/동영상 수정'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _showImageError ? Colors.redAccent : _kAccent,
                side: BorderSide(color: _showImageError ? Colors.redAccent : _kAccent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (_showImageError)
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 4),
                child: Text('대표 사진 또는 동영상을 최소 1개 등록해주세요',
                    style: TextStyle(fontSize: 12, color: Colors.redAccent)),
              ),
          ],
        ),
      );

  // ── 섹션: 숙박 정보 ──────────────────────────────────────────────────

  Widget _buildAccommodationInfo() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('숙박 유형'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ListingConstants.placeTypes.map((t) {
                final sel = _placeType == t;
                return GestureDetector(
                  onTap: () => setState(() => _placeType = t),
                  child: _facilityChip(t, selected: sel),
                );
              }).toList(),
            ),
            _label('체크인 / 체크아웃'),
            Row(
              children: [
                _timeBox('체크인', _checkInTime, () => _pickCheckTime(true)),
                const SizedBox(width: 10),
                _timeBox('체크아웃', _checkOutTime, () => _pickCheckTime(false)),
              ],
            ),
            _label('숙박 예약 링크 (선택)'),
            TextFormField(
              controller: _bookingLinkCtrl,
              keyboardType: TextInputType.url,
              decoration: _inputDeco('네이버·야놀자 등 외부 예약 페이지 URL'),
            ),
          ],
        ),
      );

  Widget _buildRoomsSection() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('객실 유형 *', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kAccent)),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '객실(룸) 단위로 정원·가격을 등록해요. 숙박 가격은 "패키지" 예약 방식으로 1박 단가를 매길 수 있어요.',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ),
            ...List.generate(
              _roomKeys.length,
              (i) => RoomCard(
                key: _roomKeys[i],
                index: i,
                onRemove: () => _removeRoom(i),
                getPreviousData: i > 0 ? () => _roomKeys[i - 1].currentState?.getRoomData() : null,
                // 임시저장에서 복원된 객실이면 그 데이터로 초기화한다(신규는 null).
                initialData:
                    i < _roomInitialData.length ? _roomInitialData[i] : null,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _addRoom,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              label: Text(_roomKeys.isEmpty ? '객실 추가하기' : '객실 추가하기 (${_roomKeys.length}개)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kAccent,
                side: const BorderSide(color: _kAccent, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                minimumSize: const Size.fromHeight(52),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            if (_roomKeys.isEmpty)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _showRoomError ? const Color(0xFFFFF0F0) : const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '객실 유형을 최소 1개 등록해주세요',
                  style: TextStyle(fontSize: 12, color: _showRoomError ? Colors.redAccent : Colors.black54),
                ),
              ),
          ],
        ),
      );

  Widget _buildFacilities() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('제공하는 편의시설을 선택해주세요'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._facilityOptions.map((f) {
                  final selected = _commonFacilities.contains(f);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _commonFacilities.remove(f);
                      } else {
                        _commonFacilities.add(f);
                      }
                    }),
                    child: _facilityChip(f, selected: selected),
                  );
                }),
                ..._customCommonFacilities.map(
                  (f) => _customChip(f, onDelete: () => setState(() => _customCommonFacilities.remove(f))),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showCustomFacilityInput = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7FA),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFDDE1EC)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14, color: Colors.black54),
                        SizedBox(width: 2),
                        Text('직접 입력', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_showCustomFacilityInput) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customFacilityCtrl,
                      decoration: _inputDeco('편의시설 이름'),
                      onSubmitted: (_) => _addCustomFacility(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addCustomFacility,
                    style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
                    child: const Text('추가'),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _showCustomFacilityInput = false;
                      _customFacilityCtrl.clear();
                    }),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ],
          ],
        ),
      );

  Widget _customChip(String label, {required VoidCallback onDelete}) => Container(
        padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3EFFA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kAccent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: _kAccent, fontWeight: FontWeight.w600)),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onDelete,
              child: const Icon(Icons.close, size: 14, color: _kAccent),
            ),
          ],
        ),
      );

  // ── 섹션: 파티 정보 (party_register_screen.dart와 동일한 구성) ──────

  Widget _buildPartyInfo() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: _partyDateKey,
            margin: const EdgeInsets.only(bottom: 10),
            child: SectionSummaryRow(
              title: '파티 날짜와 시간 *',
              summary: _dateTimeSummary(),
              hasError: _showDateError,
              errorText: _dateTimeErrorText(),
              onTap: _openDateListSheet,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '여러 라운드로 진행하나요? (1차/2차/3차)',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ),
                    Switch(
                      value: _hasMultipleRounds,
                      onChanged: (v) => setState(() => _hasMultipleRounds = v),
                      activeThumbColor: _kAccent,
                    ),
                  ],
                ),
                if (_hasMultipleRounds) ...[
                  const SizedBox(height: 12),
                  const Text('정원/참가비 방식',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _roundModeChip('통합 정원', '모든 라운드가 같은 정원/참가비', 'unified'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _roundModeChip('라운드별 정원', '라운드마다 정원/참가비가 다름', 'perRound'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  RoundListEditor(
                    rounds: _extraRounds,
                    roundCapacityMode: _roundCapacityMode,
                    genderCapacityMode: _genderCapacityMode,
                    onChanged: () {},
                  ),
                ],
              ],
            ),
          ),
          Container(
            key: _partyCapacityKey,
            margin: const EdgeInsets.only(bottom: 10),
            child: SectionSummaryRow(
              title: '성별 및 모집 인원 *',
              summary: _genderCapacitySummary(),
              hasError: _showCapacityError,
              errorText: _capacityErrorText(),
              onTap: _openGenderCapacitySheet,
            ),
          ),
          Container(
            key: _partyFeeKey,
            margin: const EdgeInsets.only(bottom: 10),
            child: SectionSummaryRow(
              title: '참가비 설정 (+얼리버드)',
              summary: _feeSummary(),
              hasError: _showFeeError,
              errorText: _showFeeError ? _feeErrorText() : null,
              onTap: _openFeeSheet,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SectionSummaryRow(
              title: '환불 규정',
              summary: _refundSummary(),
              onTap: _openRefundPolicy,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SectionSummaryRow(
              title: '연령대 설정',
              summary: _ageSummary(),
              onTap: _openAgeRestrictionSheet,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SectionSummaryRow(
              title: '파티 유형 및 분위기',
              summary: _typeVibeSummary(),
              onTap: _openTypeVibeSheet,
            ),
          ),
          Container(
            key: _partyIntroKey,
            child: SectionSummaryRow(
              title: '상세 소개 *',
              summary: _descriptionSummary(),
              hasError: _showIntroError || _showDetailBlocksError,
              errorText: _showDetailBlocksError
                  ? '상세페이지 블록을 최소 1개 추가해주세요.'
                  : '파티 소개를 입력해줘',
              onTap: _openDescriptionEditor,
            ),
          ),
        ],
      );

  // ── 섹션: 패키지 옵션 ────────────────────────────────────────────────

  Widget _buildPackageOption() => _sectionCard(
        title: '패키지 옵션',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('숙박+파티 패키지 예약 가능', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      SizedBox(height: 2),
                      Text('숙박과 파티를 묶어 예약할 수 있어요', style: TextStyle(fontSize: 12, color: Colors.black45)),
                    ],
                  ),
                ),
                Switch(
                  value: _packageBookingEnabled,
                  onChanged: (v) => setState(() => _packageBookingEnabled = v),
                  activeThumbColor: _kAccent,
                ),
              ],
            ),
            if (_packageBookingEnabled) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF3EFFA), borderRadius: BorderRadius.circular(10)),
                child: const Text(
                  '실제 예약/결제는 아직 앱에서 자동으로 연결되지 않아요. 상세페이지에 안내가 노출되고, '
                  '이용자는 채팅으로 호스트에게 직접 문의할 수 있어요.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF4A5568)),
                ),
              ),
              _label('패키지 안내 문구 (선택)'),
              TextFormField(
                controller: _packagePriceNoteCtrl,
                maxLines: 2,
                decoration: _inputDeco('예: 1박 2일 + 파티 참가 패키지 15만원, 채팅으로 문의해주세요'),
              ),
            ],
          ],
        ),
      );
}
