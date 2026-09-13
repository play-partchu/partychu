import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:party_app/models/place_area.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/pet_policy.dart';
import 'package:party_app/models/reservation_modes.dart';
import 'package:party_app/models/place_facility_options.dart';
import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/product_refund_feature.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/models/place_weekly_hours.dart';
import 'package:party_app/screens/address_search_screen.dart';
import 'package:party_app/screens/party_media_picker_screen.dart';
import 'package:party_app/screens/place_event_manage_screen.dart';
import 'package:party_app/screens/place_sales_dashboard_screen.dart';
import 'package:party_app/screens/check_in_scan_screen.dart';
import 'package:party_app/services/place_followup_entry.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/utils/video_crop.dart';
import 'package:party_app/services/content_delete_service.dart'
    show DeletableContent;
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/services/place_promotion_service.dart';
import 'package:party_app/models/draft_type.dart';
import 'package:party_app/models/combo_place_type.dart';
import 'package:party_app/widgets/space_type_selector.dart';
import 'package:party_app/widgets/place_scope_notice.dart';
import 'package:party_app/utils/draftable_register.dart';
import 'package:party_app/utils/partychu_perk_sync.dart';
import 'package:party_app/utils/register_form_mode.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/widgets/delete_content_action.dart';
import 'package:party_app/utils/register_validation.dart';
import 'package:party_app/widgets/party_form/register_field_anchor.dart';
import 'package:party_app/widgets/party_form/register_missing_fields_banner.dart';
import 'package:party_app/widgets/party_form/party_title_field.dart';
import 'package:party_app/widgets/party_media_editor.dart' show PartyCoverPick;
import 'package:party_app/widgets/partychu_perk.dart';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/widgets/guest_inquiry_section.dart';
import 'package:party_app/widgets/place_form/place_area_field.dart';
import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/widgets/place_form/custom_amenity_section.dart';
import 'package:party_app/widgets/place_form/place_facility_options_section.dart';
import 'package:party_app/widgets/place_form/place_product_section.dart';
import 'package:party_app/widgets/place_form/place_promotion_section.dart';
import 'package:party_app/widgets/place_form/room_card.dart';
import 'package:party_app/screens/payout_account_screen.dart';
import 'package:party_app/widgets/place_form/weekly_hours_editor.dart';
import 'package:party_app/widgets/payout_account_prompt.dart';
import 'package:party_app/services/registration_limits.dart';
import 'package:party_app/widgets/web_frame.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 파티 장소(공간대여) 폼의 **정본**
//
// 등록과 수정이 이 화면 하나를 공유한다. 예전에는 place_register_screen.dart와
// place_edit_screen.dart가 섹션 빌더 이름·순서까지 똑같은 복사본이라, 한쪽에만
// 기능이 추가되며 계속 갈라졌다(등록에만 있던 미입력 항목 배너가 대표적이다).
//
// 숨김(isActive:false) 상태에서 수정 모드로 저장하는 것이 곧 **재등록**이다 —
// 저장할 때 항상 isActive:true / hiddenAt 삭제가 함께 나가므로 별도 재등록
// 분기가 필요 없다.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceRegisterScreen extends StatefulWidget {
  /// 등록인지 수정인지 — 자세한 계약은 [RegisterFormMode] 참고.
  final RegisterFormMode mode;

  /// 수정 모드에서 갱신할 places 문서 id.
  final String? docId;

  /// 수정 모드에서 불러올 기존 문서.
  final Map<String, dynamic>? sourceData;

  /// 마이페이지 "임시저장" 목록에서 "이어서 작성"으로 열 때 true.
  final bool autoRestoreDraft;

  /// 공간 유형 선택기에서 다른 유형(매장·즐길거리)을 골랐을 때 셸에 알린다.
  ///
  /// null이면 선택기 자체를 그리지 않는다 — 수정 화면과, 셸을 거치지 않는
  /// 옛 호출부가 예전 그대로 동작한다.
  final ValueChanged<ComboPlaceType>? onSpaceTypeChanged;

  /// 유형 전환으로 다시 마운트된 경우 false — 복구 팝업을 띄우지 않는다.
  final bool offerDraftRestore;

  const PlaceRegisterScreen({
    super.key,
    this.autoRestoreDraft = false,
    this.onSpaceTypeChanged,
    this.offerDraftRestore = true,
  }) : mode = RegisterFormMode.create,
       docId = null,
       sourceData = null;

  /// 장소 수정 진입 — 마이페이지 카드/장소 상세가 쓴다. 숨김 상태에서 저장하면
  /// 그대로 재등록(진행중 복귀)된다.
  const PlaceRegisterScreen.edit({
    super.key,
    required String this.docId,
    required Map<String, dynamic> this.sourceData,
  }) : mode = RegisterFormMode.edit,
       autoRestoreDraft = false,
       onSpaceTypeChanged = null,
       offerDraftRestore = true;

  @override
  State<PlaceRegisterScreen> createState() => _PlaceRegisterScreenState();
}

class _PlaceRegisterScreenState extends State<PlaceRegisterScreen>
    with WidgetsBindingObserver, DraftableRegister<PlaceRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  bool get _isEdit => widget.mode.isEdit;

  /// 수정 모드에서 불러온 원본 문서 — 등록 모드에서는 빈 맵이다.
  Map<String, dynamic> get _source => widget.sourceData ?? const {};

  @override
  void setState(VoidCallback fn) {
    // 수정 모드에서는 임시저장을 쓰지 않아 markDraftDirty가 아무 일도 하지
    // 않는다(autosaver가 없다). 두 모드가 같은 setState를 타도 안전하다.
    markDraftDirty();
    super.setState(fn);
  }

  // 룸별 임시저장 복원 데이터(RoomCard의 initialData로 전달) — _roomKeys와
  // 인덱스가 1:1 대응한다. 신규 룸은 null.
  final List<Map<String, dynamic>?> _roomInitialData = [];

  @override
  DraftType get draftType => DraftType.place;

  @override
  bool get draftAutoRestore => widget.autoRestoreDraft;

  @override
  bool get draftOfferRestore => widget.offerDraftRestore;

  // ── 공간 유형 전환 ───────────────────────────────────────────────────
  // 매장 쪽(event_register_screen.dart)의 _requestSpaceTypeChange와 대칭이다.

  Future<void> _requestSpaceTypeChange(ComboPlaceType next) async {
    final notify = widget.onSpaceTypeChanged;
    if (notify == null || next == ComboPlaceType.stay) return;
    if (draftDirty) {
      final ok = await confirmSpaceTypeChange(
        context,
        from: ComboPlaceType.stay,
        to: next,
      );
      if (!ok || !mounted) return;
      await saveDraftNow();
      if (!mounted) return;
    }
    notify(next);
  }

  @override
  String get draftTitle => _nameCtrl.text;

  @override
  String? get draftCoverImageUrl =>
      _mediaExistingImageUrls.isNotEmpty ? _mediaExistingImageUrls.first : null;

  @override
  Map<String, dynamic> buildDraftPayload() {
    return <String, dynamic>{
      'name': _nameCtrl.text,
      'detailAddress': _detailAddressCtrl.text,
      'description': _descCtrl.text,
      // 평수는 입력한 **문자열 그대로** 담는다 — 아직 검증 전이라 '12.'처럼
      // 숫자로 못 바꾸는 중간 상태도 그대로 되살아나야 한다.
      PlaceArea.field: _areaCtrl.text,
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
      'placeTypes': _placeTypes.toList(),
      'commonFacilities': _commonFacilities.toList(),
      'customCommonFacilities': _customCommonFacilities.toList(),
      CustomAmenities.field: _customAmenities,
      'placeOpenTime': DraftableRegister.timeToMap(_placeOpenTime),
      'placeCloseTime': DraftableRegister.timeToMap(_placeCloseTime),
      'placeWeekendOpenTime': DraftableRegister.timeToMap(
        _placeWeekendOpenTime,
      ),
      'placeWeekendCloseTime': DraftableRegister.timeToMap(
        _placeWeekendCloseTime,
      ),
      'placeIsOpen24Hours': _placeIsOpen24Hours,
      'placeWeeklyHours': _placeWeeklyHours.toMap(),
      'weeklyOperatingHours': _placeWeeklyHours.toMap(),
      'petPolicy': _petPolicy.isUnspecified ? null : _petPolicy.toMap(),
      'facilityOptions': _facilityOptions.toDraftMap(),
      // 계좌는 임시저장에도 담지 않는다 — drafts 문서에 계좌번호가 남는다.
      'autoMsg': _autoMsgCtrl.text,
      // 수정 화면과 맞춘 항목들 — 임시저장에도 그대로 담아 복원한다.
      'partychuPerk': _partychuPerkCtrl.text,
      'contactPhone': _contactCtrl.text,
      'checkInTime': DraftableRegister.timeToMap(_checkInTime),
      'checkOutTime': DraftableRegister.timeToMap(_checkOutTime),
      'packageBookingEnabled': _packageBookingEnabled,
      'packagePriceNote': _packagePriceNoteCtrl.text,
      'products': PlaceProduct.listToDraft(_products),
      'promotions': PlacePromotion.listToDraft(_promotions),
      'existingImageUrls': _mediaExistingImageUrls,
      'existingVideoUrl': _mediaExistingVideoUrl,
      'existingVideoUid': _mediaExistingVideoUid,
      'existingVideoThumbnailUrl': _mediaExistingVideoThumbnailUrl,
      'newFilePaths': [
        for (final f in _mediaNewFiles) LocalMedia.remember(f).path,
      ],
      // 카드 노출 위치도 함께 담는다 — 담지 않으면 "이어서 작성"으로 돌아온
      // 사람이 조정 화면을 처음부터 다시 지나야 한다(그리고 '선택 완료'가
      // 크롭 확정을 요구하므로 실제로 막힌다).
      'basicCardFocalX': _mediaBasicCardFocalX,
      'basicCardFocalY': _mediaBasicCardFocalY,
      'basicCardScale': _mediaBasicCardScale,
      'photoCrops': _mediaPhotoCrops,
      'videoCropConfirmed': _mediaVideoCropConfirmed,
      'coverPick': _mediaCoverPick == null
          ? null
          : {
              'existingImageUrl': _mediaCoverPick!.existingImageUrl,
              'isExistingVideo': _mediaCoverPick!.isExistingVideo,
              'newImageOrdinal': _mediaCoverPick!.newImageOrdinal,
              'isNewVideo': _mediaCoverPick!.isNewVideo,
            },
      ListingInquiry.field: _inquiryEnabled,
      ListingInquiry.guideField: _inquiryGuideCtrl.text,
      // 룸 — 마운트돼 있으면 현재 상태를, 아직 안 그려졌으면 복원 데이터를 쓴다.
      'rooms': [
        for (int i = 0; i < _roomKeys.length; i++)
          _roomKeys[i].currentState?.getDraftData() ??
              _roomInitialData[i] ??
              const <String, dynamic>{},
      ],
    };
  }

  @override
  void applyDraftPayload(Map<String, dynamic> p) {
    _inquiryEnabled = ListingInquiry.isEnabled(p);
    _inquiryGuideCtrl.text = ListingInquiry.guideOf(p);
    _nameCtrl.text = (p['name'] as String?) ?? '';
    _detailAddressCtrl.text = (p['detailAddress'] as String?) ?? '';
    _descCtrl.text = (p['description'] as String?) ?? '';
    // 평수를 받기 전에 만든 임시저장에는 이 키가 없다 — 빈 칸으로 열린다.
    _areaCtrl.text = (p[PlaceArea.field] as String?) ?? '';
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
    // 예전 임시저장은 단일 'placeType' 하나만 갖고 있다 — 그대로 하위호환한다.
    _placeTypes
      ..clear()
      ..addAll(
        (p['placeTypes'] as List?)?.cast<String>() ??
            [
              if (p['placeType'] is String &&
                  (p['placeType'] as String).isNotEmpty)
                p['placeType'] as String,
            ],
      );
    if (_placeTypes.isEmpty) _placeTypes.add(ListingConstants.placeTypes.first);
    _customAmenities = CustomAmenities.of(p);
    _commonFacilities
      ..clear()
      ..addAll((p['commonFacilities'] as List?)?.cast<String>() ?? const []);
    _customCommonFacilities
      ..clear()
      ..addAll(
        (p['customCommonFacilities'] as List?)?.cast<String>() ?? const [],
      );
    _placeOpenTime = DraftableRegister.timeFromMap(p['placeOpenTime']);
    _placeCloseTime = DraftableRegister.timeFromMap(p['placeCloseTime']);
    _placeWeekendOpenTime = DraftableRegister.timeFromMap(
      p['placeWeekendOpenTime'],
    );
    _placeWeekendCloseTime = DraftableRegister.timeFromMap(
      p['placeWeekendCloseTime'],
    );
    _placeIsOpen24Hours = p['placeIsOpen24Hours'] as bool? ?? false;
    final weeklyMap =
        (p['placeWeeklyHours'] as Map?) ?? (p['weeklyOperatingHours'] as Map?);
    _placeWeeklyHours = PlaceWeeklyHours.fromMap(
      weeklyMap == null ? null : Map<String, dynamic>.from(weeklyMap),
    );
    // 애견동반은 저장만 되고 복원이 빠져 있었다(임시저장을 불러와도 초기화됨).
    final petMap = p['petPolicy'];
    _petPolicy = petMap is Map
        ? PetPolicy.fromMap(Map<String, dynamic>.from(petMap))
        : PetPolicy.empty();
    _facilityOptions = PlaceFacilityOptions.fromDraftMap(p['facilityOptions']);
    _autoMsgCtrl.text = (p['autoMsg'] as String?) ?? '';
    // 수정 화면과 맞춘 항목들.
    _partychuPerkCtrl.text = (p['partychuPerk'] as String?) ?? '';
    _contactCtrl.text = (p['contactPhone'] as String?) ?? '';
    _checkInTime = DraftableRegister.timeFromMap(p['checkInTime']);
    _checkOutTime = DraftableRegister.timeFromMap(p['checkOutTime']);
    _packageBookingEnabled = p['packageBookingEnabled'] as bool? ?? false;
    _packagePriceNoteCtrl.text = (p['packagePriceNote'] as String?) ?? '';
    _products
      ..clear()
      ..addAll(PlaceProduct.listFromDraft(p['products']));
    _promotions
      ..clear()
      ..addAll(PlacePromotion.listFromDraft(p['promotions']));

    _mediaExistingImageUrls = [
      ...((p['existingImageUrls'] as List?)?.cast<String>() ?? const []),
    ];
    _mediaExistingVideoUrl = p['existingVideoUrl'] as String?;
    _mediaExistingVideoUid = p['existingVideoUid'] as String?;
    _mediaExistingVideoThumbnailUrl = p['existingVideoThumbnailUrl'] as String?;
    bool anyMissing = false;
    _mediaNewFiles = [];
    for (final path
        in (p['newFilePaths'] as List?)?.cast<String>() ?? const []) {
      if (LocalMedia.exists(path)) {
        _mediaNewFiles.add(LocalMedia.resolve(path));
      } else {
        anyMissing = true;
      }
    }
    _mediaBasicCardFocalX = (p['basicCardFocalX'] as num?)?.toDouble() ?? 0.5;
    _mediaBasicCardFocalY = (p['basicCardFocalY'] as num?)?.toDouble() ?? 0.5;
    _mediaBasicCardScale = (p['basicCardScale'] as num?)?.toDouble() ?? 1.0;
    _mediaPhotoCrops = photoCropsFromRaw(p['photoCrops']);
    _mediaVideoCropConfirmed = p['videoCropConfirmed'] as bool? ?? false;
    final coverPick = p['coverPick'] as Map?;
    _mediaCoverPick = coverPick == null
        ? null
        : PartyCoverPick(
            existingImageUrl: coverPick['existingImageUrl'] as String?,
            isExistingVideo: coverPick['isExistingVideo'] as bool? ?? false,
            newImageOrdinal: (coverPick['newImageOrdinal'] as num?)?.toInt(),
            isNewVideo: coverPick['isNewVideo'] as bool? ?? false,
          );

    // 룸 재구성 — 새 GlobalKey + 복원 데이터(initialData)로 다시 그린다.
    _roomKeys.clear();
    _roomInitialData.clear();
    for (final raw in (p['rooms'] as List?) ?? const []) {
      final m = Map<String, dynamic>.from(raw as Map);
      if (m['_hasUnsavedImages'] == true) anyMissing = true;
      _roomKeys.add(GlobalKey<RoomCardState>());
      _roomInitialData.add(m);
    }
    draftMediaNeedsReselect = anyMissing;
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      _nameCtrl,
      _detailAddressCtrl,
      _descCtrl,
      _autoMsgCtrl,
      _customFacilityCtrl,
      _partychuPerkCtrl,
      _contactCtrl,
      _packagePriceNoteCtrl,
    ]) {
      c.addListener(markDraftDirty);
    }
    if (_isEdit) {
      _loadFromData(_source);
      _loadRooms();
      _loadProductsAndPromotions();
    } else {
      // 임시저장은 "빈 화면에서 새로 등록하는 경우"에만 동작한다 — 수정은 이미
      // 문서 내용을 불러온 상태라 임시저장이 그걸 덮어쓰는 사고만 생긴다.
      initDraft();
      // 등록 모드에는 불러올 룸·상품이 없다 — 곧바로 폼을 보여준다.
      _loadingRooms = false;
      _productsLoaded = true;
    }
  }

  /// 수정 모드 진입 — 기존 문서 값으로 폼을 채운다.
  void _loadFromData(Map<String, dynamic> d) {
    _nameCtrl.text = d['name'] as String? ?? '';
    _detailAddressCtrl.text = d['detailAddress'] as String? ?? '';
    _descCtrl.text = d['description'] as String? ?? '';
    _partychuPerkCtrl.text = partychuPerkFrom(d) ?? '';
    // 평수가 없던 옛 문서는 빈 칸으로 열린다 — 수정 저장에서 필수로 걸리므로
    // 이번 저장부터 값이 채워진다(기존 문서를 미리 손대지는 않는다).
    _areaCtrl.text = PlaceArea.textOf(d);

    final address = d['address'] as String? ?? '';
    if (address.isNotEmpty) {
      _selectedAddress = AddressResult(
        placeName: '',
        address: address,
        roadAddress: address,
        jibunAddress: '',
        latitude: (d['lat'] as num?)?.toDouble() ?? 0.0,
        longitude: (d['lng'] as num?)?.toDouble() ?? 0.0,
      );
    }

    // 새 문서는 types 목록을, 예전 문서는 type 하나를 갖는다.
    _placeTypes
      ..clear()
      ..addAll(
        (d['types'] as List?)?.cast<String>() ??
            [
              if (d['type'] is String && (d['type'] as String).isNotEmpty)
                d['type'] as String,
            ],
      );

    _customAmenities = CustomAmenities.of(d);
    _hadCustomAmenities = d[CustomAmenities.field] is List;

    final facilities = (d['commonFacilities'] as List?)?.cast<String>() ?? [];
    for (final f in facilities) {
      if (_commonFacilityOptions.contains(f)) {
        _commonFacilities.add(f);
      } else {
        _customCommonFacilities.add(f);
      }
    }

    _placeIsOpen24Hours = d['isOpen24Hours'] as bool? ?? false;
    if (!_placeIsOpen24Hours) {
      _placeOpenTime = _parsePlaceTime(d['openTime'] as String?);
      _placeCloseTime = _parsePlaceTime(d['closeTime'] as String?);
    }
    final weeklyMap =
        (d['placeWeeklyHours'] as Map?) ?? (d['weeklyOperatingHours'] as Map?);
    _placeWeeklyHours = PlaceWeeklyHours.fromMap(
      weeklyMap == null ? null : Map<String, dynamic>.from(weeklyMap),
    );
    final facilityMap = d['facilityOptions'];
    _facilityOptions = facilityMap is Map
        ? PlaceFacilityOptions.fromMap(Map<String, dynamic>.from(facilityMap))
        : PlaceFacilityOptions.empty();

    // payoutAccount는 읽지 않는다 — 정산계좌는 계정 단위(settlementInfo)로
    // 옮겼고, 이 문서에 남아 있던 값은 저장 시 삭제된다.
    _autoMsgCtrl.text = d['autoMessage'] as String? ?? '';

    // 통합 등록(숙박+파티)이 저장한 값들 — 없으면 빈 상태로 시작한다.
    _contactCtrl.text = d['contactPhone'] as String? ?? '';
    _checkInTime = _parsePlaceTime(d['accommodationCheckInTime'] as String?);
    _checkOutTime = _parsePlaceTime(d['accommodationCheckOutTime'] as String?);
    _packageBookingEnabled = d['packageBookingEnabled'] as bool? ?? false;
    _packagePriceNoteCtrl.text = d['packagePriceNote'] as String? ?? '';

    _inquiryEnabled = ListingInquiry.isEnabled(d);
    _inquiryGuideCtrl.text = ListingInquiry.guideOf(d);

    // 문서에 원래 있던 필드인지 — 없던 문서에 빈 값이 새로 생기지 않게 하는 기준.
    _hadContact = d.containsKey('contactPhone');
    _hadStayTimes =
        d.containsKey('accommodationCheckInTime') ||
        d.containsKey('accommodationCheckOutTime');
    _hadPackage = d.containsKey('packageBookingEnabled');

    // 미디어 — 파티 수정 화면과 동일하게 coverMediaType/coverImageUrl로
    // 대표 선택 상태를 복원한다.
    _mediaExistingImageUrls = ((d['imageUrls'] as List?)?.cast<String>() ?? [])
        .toList();
    _mediaExistingVideoUrl = d['videoUrl'] as String?;
    _mediaExistingVideoUid = d['videoUid'] as String?;
    _mediaExistingVideoThumbnailUrl = d['videoThumbnailUrl'] as String?;
    final coverMediaType = d['coverMediaType'] as String?;
    final coverImageUrl = d['coverImageUrl'] as String?;
    if (coverMediaType == 'video') {
      _mediaCoverPick = const PartyCoverPick(isExistingVideo: true);
    } else if (coverMediaType == 'image' && coverImageUrl != null) {
      _mediaCoverPick = PartyCoverPick(existingImageUrl: coverImageUrl);
    }

    // 기본 카드 노출 위치 — 저장돼 있던 값을 그대로 되살린다.
    //
    // `basicCardVideoFocalX`가 문서에 **있다는 사실 자체**를 크롭 확정 여부로
    // 쓴다(파티 수정 화면과 같은 판정). 값이 0.5/0.5/1.0이어도 "확정했는데
    // 우연히 중앙"인지 "한 번도 안 정함"인지 값만으로는 가를 수 없어서다.
    // 이 판정이 없으면, 크롭을 이미 정해 둔 장소를 수정하러 들어온 사람이
    // 매번 조정 화면을 다시 지나야 한다.
    _mediaBasicCardFocalX =
        (d['basicCardVideoFocalX'] as num?)?.toDouble() ?? 0.5;
    _mediaBasicCardFocalY =
        (d['basicCardVideoFocalY'] as num?)?.toDouble() ?? 0.5;
    _mediaBasicCardScale =
        (d['basicCardVideoScale'] as num?)?.toDouble() ?? 1.0;
    _mediaVideoCropConfirmed = d.containsKey('basicCardVideoFocalX');
    _mediaPhotoCrops = photoCropsFromRaw(d['basicCardPhotoCrops']);
  }

  TimeOfDay? _parsePlaceTime(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) return null;
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    if (h >= 24) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  /// 기존 룸 문서를 불러와 룸 카드로 펼친다(수정 모드 전용).
  Future<void> _loadRooms() async {
    final snap = await FirebaseFirestore.instance
        .collection('placeRooms')
        .where('placeId', isEqualTo: widget.docId)
        .get();
    if (!mounted) return;
    setState(() {
      for (final doc in snap.docs) {
        _roomKeys.add(GlobalKey<RoomCardState>());
        _roomIds.add(doc.id);
        _roomInitialData.add(doc.data());
        _originalRoomIds.add(doc.id);
        _roomDataById[doc.id] = doc.data();
      }
      _loadingRooms = false;
    });
  }

  /// 이미 등록된 상품·이벤트를 불러온다(수정 모드 전용) — 여기서 채운 목록이
  /// 곧 편집 대상이다.
  Future<void> _loadProductsAndPromotions() async {
    final products = await PlaceProductService.listForPlace(widget.docId!);
    final promos = await PlacePromotionService.listForPlace(widget.docId!);
    if (!mounted) return;
    setState(() {
      _products
        ..clear()
        ..addAll(products);
      _promotions
        ..clear()
        ..addAll(promos);
      _productsLoaded = true;
    });
  }

  // 섹션별 스크롤 앵커
  final _basicInfoKey = GlobalKey();
  final _photosKey = GlobalKey();

  /// 상품·이용권 섹션 앵커 — 취소·환불 규정이 비었을 때 이 자리로 보낸다.
  final _productsKey = GlobalKey();
  final _roomsKey = GlobalKey();
  final _descriptionKey = GlobalKey();

  /// 공간 평수 섹션 앵커 — 비어 있을 때 이 자리로 보낸다.
  final _areaKey = GlobalKey();

  // 상품의 취소·환불 규정은 **상품 카드 안**에 있고, 카드는 한 번에 하나만
  // 펼쳐진다. 그래서 "어느 상품을 펼칠지"(신호)와 "그 안 어느 입력칸으로
  // 갈지"(앵커)를 화면이 들고 있다가 [PlaceProductSection]에 넘긴다 —
  // 섹션이 아직 화면 밖이라 만들어지지 않았어도 미리 세워 둘 수 있어야
  // 하므로, 위젯의 State가 아니라 여기가 주인이다.
  final ProductRefundReveal _revealProductRefund = ProductRefundReveal();
  final GlobalKey _productRefundKey = GlobalKey();

  /// 그 규정 입력칸에 놓을 커서 — 도착한 뒤 바로 적을 수 있게 한다.
  final FocusNode _productRefundFocus = FocusNode();

  /// 필수항목 안내의 모든 줄이 **같은 스크롤 목록**을 움직인다 — 화면마다
  /// 따로 스크롤을 계산하지 않도록 검증 항목에 이 컨트롤러를 그대로 넘긴다
  /// ([RegisterFieldCheck.scrollController]).
  ScrollController get _formScrollCtrl => _scrollCtrl;

  // 누락 항목으로 이동한 뒤 곧바로 입력할 수 있게 커서를 놓는다.
  final _nameFocus = FocusNode();
  final _descFocus = FocusNode();
  final _areaFocus = FocusNode();

  // 기본 장소 정보
  final _nameCtrl = PartyTitleController();
  final _detailAddressCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  AddressResult? _selectedAddress;

  /// 공간 평수 — 플레이스(events)와 **같은 필드·같은 검증**이다([PlaceArea]).
  /// 등록·수정 모두 필수라, 이 필드가 없던 옛 문서도 다음 저장에서 채워진다.
  final _areaCtrl = TextEditingController();

  // ── 사진/동영상 미디어 — 파티 등록과 동일한 공용 위젯(PartyMediaEditor/
  // PartyMediaPickerScreen)을 그대로 재사용한다. 장소 등록은 신규 생성만
  // 지원하므로 existing* 필드는 항상 빈 값으로 시작한다.
  List<String> _mediaExistingImageUrls = [];
  String? _mediaExistingVideoUrl;
  String? _mediaExistingVideoUid;
  String? _mediaExistingVideoThumbnailUrl;
  List<XFile> _mediaNewFiles = [];

  // ── 기본 카드 노출 위치(크롭) ──────────────────────────────────────
  // 파티 등록과 **같은 필드·같은 의미**다. 값은 픽커가 돌려주고, 저장 때
  // `basicCardVideoFocal*` / `basicCardPhotoCrops`로 그대로 나간다 —
  // 카드가 읽는 계약(getPartyCoverMedia)이 파티와 하나다.
  //
  // 예전에는 픽커가 이 값들을 돌려주는데도 받지 않고 버렸고, 애초에
  // showVideoCropButton:false로 조정 UI 자체가 없었다. 그래서 장소대여 카드의
  // 사진·동영상은 언제나 중앙 크롭으로만 보였다.
  double _mediaBasicCardFocalX = 0.5;
  double _mediaBasicCardFocalY = 0.5;
  double _mediaBasicCardScale = 1.0;
  Map<String, Map<String, double>> _mediaPhotoCrops = {};
  bool _mediaVideoCropConfirmed = false;
  PartyCoverPick? _mediaCoverPick;

  // 인라인 에러 플래그
  bool _showAddressError = false;
  bool _showImageError = false;

  /// 등록 버튼을 눌렀을 때 비어 있던 필수 항목 안내 문구들(상단 배너용).
  List<RegisterFieldCheck> _missingFields = const [];

  bool _showRoomError = false;

  // 장소 유형 (상세검색에서 필터링 가능하도록 등록 시점에 선택)
  // 장소 유형 — 수정 화면과 동일하게 **여러 개** 고를 수 있다. 카드 라벨 등
  // 기존 읽는 쪽이 문자열 하나를 기대하므로 저장할 때 `type`에는 대표 1개를
  // 넣고 전체 목록은 `types`로 함께 저장한다.
  final Set<String> _placeTypes = {ListingConstants.placeTypes.first};

  // 공용 편의시설 (프리셋 선택)
  final Set<String> _commonFacilities = {};

  /// 기타 편의 서비스 — 플레이스(events)와 **같은 공용 필드**에 담는다.
  ///
  /// 아래 `_customCommonFacilities`와 헷갈리기 쉬운데 다른 값이다: 그쪽은
  /// 프리셋과 한 배열(`commonFacilities`)에 섞여 저장되는 장소대여 전용
  /// 편의시설이고(OR 필터), 이쪽은 두 컬렉션이 공유하는 검색 키워드 축이다
  /// (AND 필터). 기존 필드를 건드리지 않으려고 나란히 둔다.
  List<String> _customAmenities = const [];
  bool _hadCustomAmenities = false;
  bool _customAmenitiesTouched = false;

  // 공용 편의시설 (직접 입력)
  final Set<String> _customCommonFacilities = {};
  final _customFacilityCtrl = TextEditingController();
  // build마다 새로 만들면 포커스가 끊기므로 State가 하나만 들고 있는다.
  final _customFacilityFocus = FocusNode(debugLabel: 'common-facility-input');
  bool _showCustomFacilityInput = false;

  static const _commonFacilityOptions = ListingConstants.placeFacilities;

  // 장소 전체 운영 시간 — 평일(월~금)에 한 번에 넣을 공통 시간이자,
  // 저장 시 대표 운영시간(openTime/closeTime)으로 쓰인다.
  TimeOfDay? _placeOpenTime;
  TimeOfDay? _placeCloseTime;
  // 주말(토·일)에 한 번에 넣을 공통 시간 — 요일별 칸에 넣기 위한 입력값이라
  // 요일별 시간표(placeWeeklyHours)에만 반영되고 따로 저장되지는 않는다.
  TimeOfDay? _placeWeekendOpenTime;
  TimeOfDay? _placeWeekendCloseTime;
  bool _placeIsOpen24Hours = false;
  PlaceWeeklyHours _placeWeeklyHours = PlaceWeeklyHours.defaultPreset();
  PetPolicy _petPolicy = PetPolicy.empty();

  // 좌석·공간 + 이용 편의 옵션(앞으로 흡연실·주차 등도 여기에 함께 담긴다).
  PlaceFacilityOptions _facilityOptions = PlaceFacilityOptions.empty();

  // 정산 계좌는 이 화면에서 입력받지 않는다 — 계정 단위
  // users/{uid}.settlementInfo 한 곳으로 통일했다(SettlementInfoScreen).

  // 예약자 자동발송 문구
  final _autoMsgCtrl = TextEditingController();

  // ── 수정 화면에만 있던 항목들을 등록 화면에도 맞춘 부분 ──────────────────
  // place_edit_screen과 완전히 같은 값을 저장한다. 두 화면은 서로 독립된
  // 파일이라 한쪽에만 기능이 추가되기 쉬웠던 자리다.
  /// "파티츄 전용 혜택" — 비우면 빈 문자열로 저장돼 배지가 붙지 않는다.
  final _partychuPerkCtrl = TextEditingController();

  /// 상품·이용권 / 매장 이벤트 — 장소 문서가 생긴 뒤 placeId로 함께 저장한다.
  final List<PlaceProduct> _products = [];
  final List<PlacePromotion> _promotions = [];

  /// 연락처 · 숙박 이용 안내 — 통합 등록(숙박+파티)이 쓰던 필드와 같다.
  final _contactCtrl = TextEditingController();
  TimeOfDay? _checkInTime;
  TimeOfDay? _checkOutTime;
  bool _packageBookingEnabled = false;
  final _packagePriceNoteCtrl = TextEditingController();

  // ── 룸 목록 — 세 리스트를 같은 인덱스로 나란히 관리한다.
  // _roomIds[i] == null 이면 이번에 새로 추가한 룸(저장 시 add()),
  // 아니면 기존 룸 문서 ID(저장 시 update()). 등록 모드에서는 항상 null이다.
  final List<GlobalKey<RoomCardState>> _roomKeys = [];
  final List<String?> _roomIds = [];

  // 최초에 불러온 룸 ID 전체(삭제 여부 판단용) + 룸별 원본 데이터(삭제된 룸의
  // 사진을 R2에서 지우기 위해 목록에서 빠진 뒤에도 참조할 수 있게 별도 보관 —
  // _roomInitialData는 _removeRoom 시 같이 사라지기 때문). 수정 모드 전용.
  final Set<String> _originalRoomIds = {};
  final Map<String, Map<String, dynamic>> _roomDataById = {};
  bool _loadingRooms = true;

  /// 상품·이벤트 목록을 다 읽었는지 — 다 읽기 전에 저장하면 빈 목록으로
  /// 덮어써 기존 상품이 지워진다. 등록 모드는 처음부터 true다.
  bool _productsLoaded = false;

  /// 수정 모드에서 "문서에 원래 있던 필드인지" — 없던 문서에 빈 값/기본값을
  /// 새로 만들지 않기 위한 기준. 등록 모드에서는 항상 저장하므로 쓰이지 않는다.
  bool _hadContact = false;

  /// 게스트 문의 받기 — 파티·플레이스와 **같은 필드**(inquiryEnabled) 하나다.
  /// 등록 기본값은 ON([ListingInquiry.defaultEnabled]).
  bool _inquiryEnabled = ListingInquiry.defaultEnabled;

  /// 문의 전 안내문 — 문의 받기가 ON일 때만 입력란이 보인다.
  final _inquiryGuideCtrl = TextEditingController();
  bool _hadStayTimes = false;
  bool _hadPackage = false;
  bool _stayTimesTouched = false;
  bool _packageTouched = false;

  // 업로드 상태 — Stack 오버레이 방식으로 표시 (Form 위젯을 트리에 유지)
  bool _isUploading = false;
  String _uploadStatus = '';

  @override
  void dispose() {
    disposeDraft();
    _scrollCtrl.dispose();
    _revealProductRefund.dispose();
    _productRefundFocus.dispose();
    // 이 화면을 떠나면 강조도 함께 끈다 — 타이머가 화면보다 오래 남지 않게.
    RegisterValidation.clearHighlight();
    _nameCtrl.dispose();
    _detailAddressCtrl.dispose();
    _descCtrl.dispose();
    _inquiryGuideCtrl.dispose();
    _customFacilityCtrl.dispose();
    _customFacilityFocus.dispose();
    _autoMsgCtrl.dispose();
    _partychuPerkCtrl.dispose();
    _contactCtrl.dispose();
    _packagePriceNoteCtrl.dispose();
    _areaCtrl.dispose();
    _nameFocus.dispose();
    _descFocus.dispose();
    _areaFocus.dispose();
    super.dispose();
  }

  void _addRoom() => setState(() {
    _roomKeys.add(GlobalKey<RoomCardState>());
    _roomIds.add(null);
    _roomInitialData.add(null);
    _showRoomError = false;
  });

  void _removeRoom(int index) => setState(() {
    _roomKeys.removeAt(index);
    _roomIds.removeAt(index);
    _roomInitialData.removeAt(index);
  });

  // 판정은 업로더와 **같은 함수 하나**를 쓴다 — 웹에서는 XFile.path가 확장자
  // 없는 blob URL이라, 여기서 경로로 다시 판정하면 동영상을 사진으로 오인한다.
  bool _isVideoFile(XFile f) => MediaUploadService.isVideoFile(f);

  bool get _mediaHasVideo =>
      _mediaExistingVideoUrl != null || _mediaNewFiles.any(_isVideoFile);

  String? _mediaSummary() {
    final photoCount =
        _mediaExistingImageUrls.length +
        _mediaNewFiles.where((f) => !_isVideoFile(f)).length;
    final parts = <String>[];
    if (photoCount > 0) parts.add('사진 $photoCount장');
    if (_mediaHasVideo) parts.add('동영상 1개');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  // 파티 등록과 동일한 공용 미디어 편집 화면(PartyMediaEditor)을 그대로
  // 재사용한다 — 사진 여러 장 + 동영상 1개, 대표 미디어 선택까지 동일하게
  // 지원된다.
  Future<void> _openMediaPicker() async {
    final result = await Navigator.push<PartyMediaSelection>(
      context,
      webFramedRoute(
        (_) => PartyMediaPickerScreen(
          existingImageUrls: _mediaExistingImageUrls,
          existingVideoUrl: _mediaExistingVideoUrl,
          existingVideoUid: _mediaExistingVideoUid,
          existingVideoThumbnailUrl: _mediaExistingVideoThumbnailUrl,
          newMedia: _mediaNewFiles,
          coverPick: _mediaCoverPick,
          basicCardFocalX: _mediaBasicCardFocalX,
          basicCardFocalY: _mediaBasicCardFocalY,
          basicCardScale: _mediaBasicCardScale,
          photoCrops: _mediaPhotoCrops,
          videoCropConfirmed: _mediaVideoCropConfirmed,
          // 장소대여 카드도 파티와 **같은 기본 카드**에 뜬다 — 노출 위치를
          // 못 정하면 사진·동영상이 언제나 중앙으로만 잘린다. 이 값을 켜야
          // 크롭 UI가 나오고, '선택 완료'를 눌러야 넘어가므로 고른 미디어가
          // 뒤로가기로 조용히 사라지는 일도 함께 줄어든다.
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
      // 크롭 값도 함께 받는다 — 예전에는 픽커가 돌려주는데도 버려서, 조정
      // 화면을 지나온 값이 저장까지 한 번도 도달하지 못했다.
      _mediaBasicCardFocalX = result.basicCardFocalX;
      _mediaBasicCardFocalY = result.basicCardFocalY;
      _mediaBasicCardScale = result.basicCardScale;
      _mediaPhotoCrops = result.photoCrops;
      _mediaVideoCropConfirmed = result.videoCropConfirmed;
      _showImageError = false;
    });
  }

  Future<void> _save() async {
    // 중복 클릭 방지 — 업로드가 이미 시작됐으면 아무것도 하지 않는다.
    if (_isUploading) return;

    // 등록 개수 — 장소대여도 10개다([RegistrationLimits]). 진입 관문이 이미
    // 보지만 그 관문은 폼을 **열 때의 유형**으로 판정하므로, 폼 안에서 유형을
    // 바꿔 들어온 길까지 여기서 다시 본다. 수정은 개수를 늘리지 않으므로
    // 새 등록일 때만 본다. 업로드 전에 막아야 지워지지 않는 사진이 남지 않는다.
    if (!_isEdit) {
      if (!await RegistrationLimits.ensure(
        context,
        RegistrationKind.rentalListing,
      )) {
        return;
      }
      if (!mounted) return;
    }

    // ── 1. 전체 필수값 검증 (저장 전에 모두 확인) ─────────────────────
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();

    debugPrint('─── [장소 등록] 필드 검증 시작 ───');
    debugPrint('  name       : "$name"');
    debugPrint('  address    : ${_selectedAddress?.roadAddress ?? "null"}');
    debugPrint(
      '  lat/lng    : ${_selectedAddress?.latitude} / ${_selectedAddress?.longitude}',
    );
    debugPrint('  desc len   : ${desc.length}');
    debugPrint(
      '  mediaCount : photos=${_mediaExistingImageUrls.length + _mediaNewFiles.where((f) => !_isVideoFile(f)).length} '
      'video=${_mediaHasVideo ? 1 : 0}',
    );
    debugPrint('  roomCount  : ${_roomKeys.length}');
    // uid는 **검증을 통과한 뒤**에 찍는다 — 입력값 검사가 Firebase 초기화에
    // 매달리면 안 된다(로그 한 줄 때문에 검증 자체가 끊긴다).

    // 입력칸 아래 빨간 문구를 먼저 그린 뒤, 화면 순서대로 누락 항목을 모아
    // 첫 번째 항목으로 이동한다. 여기서 걸리면 업로드도 로딩 상태도 시작하지
    // 않는다(서버 오류와 구분).
    _formKey.currentState?.validate();

    final nameMissing = name.isEmpty;
    final addressMissing = _selectedAddress == null;
    final descMissing = desc.isEmpty;
    // 공간 평수 — 등록·수정 모두 필수다. null이면 통과.
    final areaError = PlaceArea.validate(_areaCtrl.text);
    final mediaMissing =
        _mediaExistingImageUrls.isEmpty && _mediaNewFiles.isEmpty;
    final roomMissing = _roomKeys.isEmpty;

    setState(() {
      _showAddressError = addressMissing;
      _showImageError = mediaMissing;
      _showRoomError = roomMissing;
    });

    // 규정이 비어 있는 **첫 상품**의 위치 — 그 카드를 펼쳐야 입력칸이 트리에
    // 생긴다(상품 카드는 한 번에 하나만 펼쳐진다).
    final productRefundIndex = PlaceProductRefundPolicyRule.firstMissingIndex(
      _products,
    );

    // 누락 항목과 실제 입력 위치를 잇는 **단 하나의 표**다. 문구·이동 위치·
    // 펼치기·포커스가 한 줄에 함께 적혀 있어, 화면 어디서 눌러도(제출 버튼 ·
    // 상단 배너의 각 줄) 같은 곳으로 간다.
    final checks = [
      RegisterFieldCheck(
        missing: nameMissing,
        message: '장소 이름을 입력해주세요.',
        anchorKey: _basicInfoKey,
        focusNode: _nameFocus,
        scrollController: _formScrollCtrl,
      ),
      RegisterFieldCheck(
        missing: addressMissing,
        message: '주소를 입력해주세요.',
        anchorKey: _basicInfoKey,
        scrollController: _formScrollCtrl,
      ),
      // 공간 평수 — 비어 있으면 [PlaceArea.requiredMessage], 형식이 어긋나면
      // 그 사유가 그대로 배너·스낵바에 뜬다(입력칸 아래 빨간 문구와 같은 문장).
      RegisterFieldCheck(
        missing: areaError != null,
        message: areaError ?? PlaceArea.requiredMessage,
        anchorKey: _areaKey,
        focusNode: _areaFocus,
        scrollController: _formScrollCtrl,
      ),
      RegisterFieldCheck(
        missing: descMissing,
        message: '장소 설명을 입력해주세요.',
        anchorKey: _descriptionKey,
        focusNode: _descFocus,
        scrollController: _formScrollCtrl,
      ),
      RegisterFieldCheck(
        missing: mediaMissing,
        message: '대표 사진 / 동영상을 설정해주세요.',
        anchorKey: _photosKey,
        scrollController: _formScrollCtrl,
      ),
      RegisterFieldCheck(
        missing: roomMissing,
        message: '룸/공간을 최소 1개 추가해주세요.',
        anchorKey: _roomsKey,
        scrollController: _formScrollCtrl,
      ),
      // 상품을 등록했다면 취소·환불 규정은 필수다 — 규칙은 공용
      // [PlaceProductRefundPolicyRule] 하나를 쓴다(티어형 환불 규정과 별개).
      RegisterFieldCheck(
        // 지금은 환불 UX 자체를 내려 둔 상태라 이 게이트도 함께 쉰다 —
        // 입력칸이 없는데 그 칸을 채우라고 막으면 등록이 아예 불가능해진다.
        // 규칙(PlaceProductRefundPolicyRule)과 기존 값은 그대로 두고, 켜는
        // 스위치 하나만 본다(ProductRefundFeature).
        missing: ProductRefundFeature.enabled && productRefundIndex >= 0,
        message: PlaceProductRefundPolicyRule.requiredMessage,
        // 섹션 앞이 아니라 **그 규정 입력칸 자체**로 간다. 상품이 여럿이면
        // 규정이 비어 있는 첫 상품의 칸이다.
        anchorKey: _productRefundKey,
        // 그 카드가 접혀 있으면 입력칸이 아예 없다 — 먼저 펼친다.
        focusNode: _productRefundFocus,
        reveal: () => _revealProductRefund.request(productRefundIndex),
        scrollController: _formScrollCtrl,
      ),
    ];
    setState(() => _missingFields = RegisterValidation.missingFields(checks));
    final passed = RegisterValidation.check(context, checks);
    if (!passed || !mounted) return;

    // 룸별 개별 유효성 검사 — 룸 카드가 각자 자기 입력칸에 오류를 그린다.
    bool roomsValid = true;
    for (int i = 0; i < _roomKeys.length; i++) {
      final state = _roomKeys[i].currentState;
      if (state == null) {
        debugPrint('  ❌ 룸[$i] currentState == null');
        roomsValid = false;
        continue;
      }
      if (!state.validate()) {
        debugPrint('  ❌ 룸[$i] 필수항목 미입력');
        roomsValid = false;
      }
    }
    if (!roomsValid) {
      RegisterValidation.showMessage(context, '룸/공간의 필수 항목을 확인해주세요.');
      // 누락 항목과 **같은 경로**로 보낸다 — 룸 섹션이 아직 화면 밖이면
      // 먼저 만들어질 때까지 목록을 훑어 내려간다.
      RegisterValidation.goToAnchor(
        _roomsKey,
        scrollController: _formScrollCtrl,
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('  ❌ uid == null — 로그인 필요');
      _msg('로그인이 필요합니다');
      return;
    }

    debugPrint('  ✅ 검증 통과 — 업로드 시작 (uid: $uid)');

    // ── 2. 업로드 (Stack 오버레이 — Form·RoomCard 위젯을 트리에 유지) ──
    // _isUploading = true 여도 Scaffold body 가 교체되지 않으므로
    // _roomKeys[i].currentState 는 절대 null 이 되지 않음.
    setState(() {
      _missingFields = const [];
      _isUploading = true;
      _uploadStatus = '장소 사진 업로드 중...';
    });

    try {
      // 장소 사진/동영상 업로드 — 파티 등록과 **같은 공용 업로더**를 쓴다.
      // 예전에는 여기에 for 루프가 따로 복사돼 있어서, 임시저장을 복원한 뒤
      // OS가 캐시를 비워 파일이 사라진 경우(경로만 남음) 정체 불명의 실패로
      // 끝났다. 공용 업로더는 올리기 전에 경로·존재·크기를 먼저 확인하고,
      // 실패하면 어떤 파일이 왜 실패했는지와 그때까지 올라간 것을 함께 던진다.
      final upload = await MediaUploadService.uploadNewMedia(
        media: _mediaNewFiles,
        logTag: 'place-media',
        onVideoStart: () => setState(() => _uploadStatus = '동영상을 올리는 중...'),
        onImageProgress: (done, total) =>
            setState(() => _uploadStatus = '장소 사진 업로드 중... ($done/$total)'),
      );
      final newImageUrls = upload.imageUrls;
      final newVideoUid = upload.videoUid;
      final newVideoUrl = upload.videoUrl;
      final newVideoThumbnailUrl = upload.videoThumbnailUrl;

      final imageUrls = [..._mediaExistingImageUrls, ...newImageUrls];
      final finalVideoUrl = newVideoUrl ?? _mediaExistingVideoUrl;
      final finalVideoUid = newVideoUid ?? _mediaExistingVideoUid;
      final finalVideoThumbnailUrl =
          newVideoThumbnailUrl ?? _mediaExistingVideoThumbnailUrl;

      // 대표 미디어 — 사용자가 명시적으로 골랐으면 그 값을 그대로 신뢰하고,
      // 고르지 않았다면(coverPick == null) 첫 번째 업로드 미디어를 기본값으로
      // 쓴다(이미지가 있으면 이미지 우선, 없으면 동영상) — 파티 등록과 동일.
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

      // 대표로 고른 사진을 실제 저장 배열의 맨 앞(index 0)으로 재정렬한다 —
      // 상세페이지 갤러리가 항상 index 0부터 열리므로, 저장 순서 자체를
      // 바꿔야 대표 미디어가 첫 화면에 온다(파티 등록과 동일한 규칙).
      if (coverMediaType == 'image' && coverImageUrl != null) {
        imageUrls.remove(coverImageUrl);
        imageUrls.insert(0, coverImageUrl);
      }

      // 룸 데이터 먼저 수집(이미지 업로드 포함) — 장소 문서에 최저가/최대인원을
      // 집계해 넣기 위해 장소 문서 쓰기보다 먼저 수행한다.
      //
      // 등록은 새 장소 문서 id를 미리 발급해 룸에 물려주고, 수정은 이미 있는
      // 문서 id를 쓴다. 룸 문서는 등록이면 전부 새로 만들고, 수정이면 기존
      // 룸은 update / 새로 추가한 룸만 add 한다.
      final placeRef = _isEdit
          ? FirebaseFirestore.instance.collection('places').doc(widget.docId)
          : FirebaseFirestore.instance.collection('places').doc();
      final roomDataList = <Map<String, dynamic>>[];
      for (int i = 0; i < _roomKeys.length; i++) {
        setState(
          () => _uploadStatus = '룸 ${i + 1}/${_roomKeys.length} 정보 준비 중...',
        );
        final state = _roomKeys[i].currentState;
        if (state == null) {
          throw Exception('룸[$i] state == null — 예상치 못한 위젯 트리 제거');
        }
        final roomData = await state.uploadAndGetData(uid, placeRef.id);
        roomDataList.add(roomData);
        if (!_isEdit) continue;

        final roomId = _roomIds[i];
        if (roomId == null) {
          // 새 룸 — 문서 id를 먼저 발급해 화면 목록에 되돌려 넣는다. 이걸
          // 하지 않으면 화면을 벗어나지 않고 다시 저장할 때 _roomIds[i]가
          // 여전히 null이라 같은 룸이 새 문서로 또 만들어진다(저장 횟수만큼
          // 중복 생성).
          final ref = FirebaseFirestore.instance.collection('placeRooms').doc();
          await ref.set(roomData);
          _roomIds[i] = ref.id;
          _originalRoomIds.add(ref.id);
          _roomDataById[ref.id] = roomData;
        } else {
          await FirebaseFirestore.instance
              .collection('placeRooms')
              .doc(roomId)
              .update(roomData);
        }
      }

      // ── 목록에서 뺀(삭제된) 기존 룸 — 사진 정리 후 문서 삭제 (수정 전용) ──
      if (_isEdit) {
        final remainingRoomIds = _roomIds.whereType<String>().toSet();
        final deletedRoomIds = _originalRoomIds.difference(remainingRoomIds);
        for (final roomId in deletedRoomIds) {
          setState(() => _uploadStatus = '삭제된 룸 정리 중...');
          final oldImages =
              (_roomDataById[roomId]?['roomImages'] as List?)?.cast<String>() ??
              [];
          for (final url in oldImages) {
            try {
              await CloudflareService.deleteImage(url);
            } catch (_) {}
          }
          await FirebaseFirestore.instance
              .collection('placeRooms')
              .doc(roomId)
              .delete();
        }
      }

      // 상세검색용 집계값 — 룸별 최저가(시간제가 있으면 시간당, 숙박 전용이면
      // 1박 기준) / 최대 수용 인원
      final priceSummary = placePriceSummary(roomDataList);
      final capacities = roomDataList
          .map((r) => (r['capacityMax'] as num?)?.toInt() ?? 0)
          .where((c) => c > 0);
      final minPrice = priceSummary.price;
      final maxCapacity = capacities.isEmpty
          ? 0
          : capacities.reduce((a, b) => a > b ? a : b);

      setState(() => _uploadStatus = '장소 정보 저장 중...');

      // 장소 문서 — 등록은 새로 만들고(set), 수정은 갱신한다(update).
      // 수정에는 isActive:true / hiddenAt 삭제가 항상 함께 나가므로, 숨김
      // 상태였다면 저장과 동시에 재등록(진행중 복귀)된다.
      final placeDoc = <String, dynamic>{
        if (!_isEdit) 'hostId': uid,
        'name': name,
        // 카드 라벨 등 기존 읽는 쪽이 문자열 하나를 기대하므로 `type`에는
        // 대표 1개를 두고, 전체 목록은 `types`로 저장한다(수정 화면과 동일).
        'type': _placeTypes.isEmpty ? '' : _placeTypes.first,
        'types': _placeTypes.toList(),
        'address': _selectedAddress?.roadAddress ?? '',
        'detailAddress': _detailAddressCtrl.text.trim(),
        'lat': _selectedAddress?.latitude ?? 0.0,
        'lng': _selectedAddress?.longitude ?? 0.0,
        'imageUrls': imageUrls,
        'videoProvider': finalVideoUrl == null ? null : 'cloudflare',
        'videoUid': finalVideoUid,
        'videoUrl': finalVideoUrl,
        'videoThumbnailUrl': finalVideoThumbnailUrl,
        // 대표 미디어 — 등록자가 직접 고른 사진/동영상(파티와 동일한 필드
        // 형태). 기존 장소 데이터에는 이 필드들이 없으므로, 읽는 쪽
        // (getPartyCoverMedia)이 imageUrls.first로 폴백해 하위호환된다.
        'coverMediaType': coverMediaType,
        'coverImageUrl': coverImageUrl,
        'coverVideoUid': coverVideoUid,
        'coverVideoUrl': coverVideoUrl,
        'coverThumbnailUrl': coverThumbnailUrl,
        // 기본 카드 노출 위치 — 등록/수정 화면에서 카드 비율 그대로 맞춘 값.
        // 파티와 **같은 키·같은 의미**라 카드가 읽는 함수 하나
        // (getPartyCoverMedia)가 두 도메인을 함께 처리한다. 값이 없는 옛
        // 문서는 0.5/0.5/1.0(중앙)으로 읽혀 예전과 똑같이 보인다.
        'basicCardVideoFocalX': _mediaBasicCardFocalX,
        'basicCardVideoFocalY': _mediaBasicCardFocalY,
        'basicCardVideoScale': _mediaBasicCardScale,
        // 사진 크롭은 **URL별**로 저장한다 — 장소는 사진이 여러 장이라 값
        // 하나를 공유할 수 없다. 픽커가 준 키는 새 파일이면 로컬 경로이므로,
        // 업로드로 받은 URL로 바꿔 담는다.
        'basicCardPhotoCrops': MediaUploadService.resolvePhotoCropKeys(
          crops: _mediaPhotoCrops,
          existingImageUrls: _mediaExistingImageUrls,
          newMedia: _mediaNewFiles,
          uploadedImageUrls: newImageUrls,
        ),
        'description': desc,
        // 공간 평수 — **숫자 그대로** 저장한다('20평' 같은 문자열이 아니다).
        // 등록·수정 둘 다 이 줄을 타므로 필드가 없던 옛 문서도 이번 저장에서
        // 채워진다([PlaceArea]). 위 검증을 통과했으므로 null이 아니다.
        PlaceArea.field: PlaceArea.parse(_areaCtrl.text)!,
        // 파티츄 전용 혜택 — 수정 화면과 같은 필드에 저장한다(비우면 빈 문자열).
        kPartychuPerkField: _partychuPerkCtrl.text.trim(),
        'commonFacilities': {
          ..._commonFacilities,
          ..._customCommonFacilities,
        }.toList(),
        // 기타 편의 서비스 — 등록·수정 모두 항상 쓴다. 항목을 전부 지운
        // 경우에도 빈 배열이 덮어써야 예전 값이 필터에 계속 걸리지 않는다.
        if (!_isEdit || _hadCustomAmenities || _customAmenitiesTouched)
          CustomAmenities.field: CustomAmenities.toStored(_customAmenities),
        // 룸별 최저가/최대인원 집계 — 상세검색(가격범위/수용인원) 필터에 사용
        'pricePerHour': minPrice,
        // 위 대표가가 시간당('hour')인지 1박당('night')인지 — 카드 요금 표기에
        // 쓰인다(숙박 전용 장소가 "₩0 / 시간"으로 보이지 않도록).
        'priceUnit': priceSummary.unit,
        'capacityMax': maxCapacity,
        // ⚠ payoutAccount는 더 이상 여기 저장하지 않는다.
        //   places 문서는 누구나 읽을 수 있어(rules) 계좌번호가 공개로
        //   노출됐다. 정산계좌는 users/{uid}.settlementInfo 한 곳에만 있다.
        //
        //   수정 저장일 때만 delete 센티널을 넣어 **옛 문서에 남아 있던 필드를
        //   치운다**. 신규 등록은 update가 아니라 set이라 delete 센티널을 넣으면
        //   Firestore가 예외를 던진다(set은 merge일 때만 허용).
        if (_isEdit) 'payoutAccount': FieldValue.delete(),
        'autoMessage': _autoMsgCtrl.text.trim(),
        'isActive': true,
        if (_isEdit) 'hiddenAt': FieldValue.delete(),
        'isOpen24Hours': _placeIsOpen24Hours,
        if (_placeIsOpen24Hours) ...{
          'openTime': '00:00',
          'closeTime': '24:00',
        } else if (_placeOpenTime != null && _placeCloseTime != null) ...{
          'openTime': _fmtPlaceTime(_placeOpenTime!),
          'closeTime': _fmtPlaceTime(_placeCloseTime!),
        },
        'placeWeeklyHours': _placeWeeklyHours.toMap(),
        'weeklyOperatingHours': _placeWeeklyHours.toMap(),
        if (!_petPolicy.isUnspecified) 'petPolicy': _petPolicy.toMap(),
        // 좌석·공간/편의 옵션 — 그룹 단위로 확장되는 구조라 새 편의시설이
        // 생겨도 이 한 줄은 그대로다(PlaceFacilityCatalog 참고).
        // 수정은 update()라, 항목을 모두 해제했을 때도 문서에서 지워지도록 빈
        // 맵을 그대로 덮어쓴다(조건부로 빼면 예전 선택이 그대로 남는다).
        if (_isEdit || _facilityOptions.isNotEmpty)
          'facilityOptions': _facilityOptions.toMap(),
        // 게스트 문의 받기는 **언제나 쓴다.** 값이 없는 문서는 어차피 ON으로
        // 읽히므로(ListingInquiry.defaultEnabled) true를 적어도 뜻이 달라지지
        // 않고, 호스트가 OFF로 바꾼 순간에는 반드시 적혀 있어야 한다.
        ...ListingInquiry.toMap(_inquiryEnabled, _inquiryGuideCtrl.text),
        // 연락처 · 숙박 이용 안내 — 등록은 입력한 값이 있을 때만 필드를 만들고,
        // 수정은 "원래 문서에 있었거나 이번에 실제로 건드린" 경우에만 쓴다
        // (이 필드가 없던 문서에 빈 값/기본값이 새로 생기지 않게).
        if (_isEdit
            ? (_hadContact || _contactCtrl.text.trim().isNotEmpty)
            : _contactCtrl.text.trim().isNotEmpty)
          'contactPhone': _contactCtrl.text.trim(),
        if (_isEdit) ...{
          if (_hadStayTimes || _stayTimesTouched) ...{
            'accommodationCheckInTime': _checkInTime == null
                ? FieldValue.delete()
                : _fmtPlaceTime(_checkInTime!),
            'accommodationCheckOutTime': _checkOutTime == null
                ? FieldValue.delete()
                : _fmtPlaceTime(_checkOutTime!),
          },
          if (_hadPackage || _packageTouched) ...{
            'packageBookingEnabled': _packageBookingEnabled,
            'packagePriceNote':
                _packageBookingEnabled &&
                    _packagePriceNoteCtrl.text.trim().isNotEmpty
                ? _packagePriceNoteCtrl.text.trim()
                : FieldValue.delete(),
          },
        } else ...{
          if (_checkInTime != null)
            'accommodationCheckInTime': _fmtPlaceTime(_checkInTime!),
          if (_checkOutTime != null)
            'accommodationCheckOutTime': _fmtPlaceTime(_checkOutTime!),
          'packageBookingEnabled': _packageBookingEnabled,
          if (_packageBookingEnabled &&
              _packagePriceNoteCtrl.text.trim().isNotEmpty)
            'packagePriceNote': _packagePriceNoteCtrl.text.trim(),
        },
        if (!_isEdit) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_isEdit) {
        await placeRef.update(placeDoc);
      } else {
        await placeRef.set(placeDoc);
        // 룸 문서 생성 — 등록에서는 위 루프가 쓰기를 하지 않았으므로 여기서
        // 한 번에 만든다(수정은 루프 안에서 이미 add/update를 끝냈다).
        for (int i = 0; i < roomDataList.length; i++) {
          setState(
            () => _uploadStatus = '룸 ${i + 1}/${roomDataList.length} 등록 중...',
          );
          await FirebaseFirestore.instance
              .collection('placeRooms')
              .add(roomDataList[i]);
        }
      }

      // 상품·이용권 / 매장 이벤트 — 장소 문서가 생긴 뒤에야 placeId를 알 수
      // 있다(플레이스 등록 화면과 같은 순서·같은 저장 함수).
      // 수정에서 아직 목록을 다 읽지 못했다면 건드리지 않는다 — 빈 목록으로
      // 덮어쓰면 기존 상품이 지워진다.
      if (_productsLoaded) {
        setState(() => _uploadStatus = '상품·이벤트 저장 중...');
        await PlaceProductSection.save(
          placeId: placeRef.id,
          placeCollection: 'places',
          hostId: uid,
          products: _products,
        );
        // 이벤트는 **신규 등록에서만** 이 폼이 저장한다. 수정 모드에서는
        // 관리 화면이 단독으로 쓰므로 여기서 건드리면 안 된다 — save는 목록
        // 전체를 치환하는 동작이라, 이 화면이 열려 있는 동안 관리 화면에서
        // 추가된 이벤트를 지워버린다.
        if (!_isEdit) {
          await PlacePromotionSection.save(
            placeId: placeRef.id,
            placeCollection: 'places',
            hostId: uid,
            promotions: _promotions,
          );
        }
      }

      // 콤보(숙박+파티)로 등록된 장소면 연결된 파티 문서(들)에도 같은 혜택을
      // 반영한다 — 파티 상세로 들어와도 같은 혜택이 보이게.
      if (_isEdit) {
        await syncPartychuPerkAcrossBundle(
          bundleId: _source['bundleId'] as String?,
          perk: _partychuPerkCtrl.text.trim(),
          selfDocId: widget.docId!,
        );
      }

      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploadStatus = '';
      });

      // ── 3. 성공 처리 ─────────────────────────────────────────────────
      // 수정은 목록으로 곧장 돌아가는 게 자연스럽다 — 다이얼로그로 한 번 더
      // 확인을 받지 않는다.
      if (_isEdit) {
        _msg('저장되었습니다');
        Navigator.pop(context);
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF7C5CBF)),
              SizedBox(width: 8),
              Text(
                '등록 완료',
                style: TextStyle(
                  fontFamily: 'SeoulHangang',
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                    Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                    Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                    Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                  ],
                ),
              ),
            ],
          ),
          content: const Text(
            '장소가 성공적으로 등록되었습니다.',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C5CBF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      // 최종 등록 완료 — 장소 임시저장은 자동 삭제.
      await deleteCurrentDraft();
      if (!mounted) return;
      // 이용요금을 받는 장소인데 **입금받을 계좌**가 아직 없으면 지금 등록하도록
      // 이어준다(인증돼 있으면 그냥 지나감). 이용요금·예약금은 파티츄를 거치지
      // 않고 호스트 계좌로 바로 들어가므로, 물어야 할 것은 수취계좌다.
      // 새로 등록할 때만 묻는다 — 수정에서까지 재촉할 일은 아니다.
      if (!_isEdit) {
        await promptPayoutAccountAfterRegister(
          context,
          what: '장소',
          // 룸 대표가가 0이면 요금을 받지 않는 장소라 재촉할 이유가 없다.
          usesBankTransfer: minPrice > 0,
        );
        if (!mounted) return;

        // "이 플레이스에서 파티나 이벤트를 여시나요?" — 방금 만든 공간이 이미
        // 정해져 있으므로 어느 공간인지 다시 묻지 않는다([PlaceFollowupEntry]).
        // 플레이스 등록(매장)과 **같은 시트·같은 흐름**이다.
        await PlaceFollowupEntry.show(
          context,
          placeId: placeRef.id,
          placeCollection: 'places',
          placeData: {...placeDoc, 'id': placeRef.id},
          placeName: _nameCtrl.text.trim(),
        );
        if (!mounted) return;
      }
      // 등록 화면이 몇 단계 깊이 열려 있었든(모바일: RegisterTypeScreen 경유,
      // 데스크톱: MainScreen에서 바로) 곧장 메인화면 장소대여 탭으로 복귀한다.
      pendingTopTabAfterRegister.value = 2;
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e, st) {
      debugPrint(_isEdit ? '❌ 장소 수정 실패: $e' : '❌ 장소 등록 실패: $e');
      debugPrint('StackTrace:\n$st');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
        });
        // 예외 원문은 로그에만 — 사용자에게는 공통 안내만 보여준다.
        _msg(RegisterValidation.failureMessage(e));
      }
    }
  }

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );

  /// AppBar 제목 — 등록은 "플레이스 등록", 수정은 "장소 수정".
  ///
  /// 예전에는 "파티 장소 등록"이었다. 등록 유형 화면의 카드 이름을 그대로
  /// 따른 것인데, 그 카드가 "플레이스 등록" 하나로 합쳐지면서 화면 제목만
  /// 옛 이름으로 남으면 "내가 뭘 누른 거지"가 된다.
  ///
  /// 수정 제목은 "장소 수정" 그대로다 — 이미 등록된 장소대여 문서를 여는
  /// 경로(마이페이지·장소 상세)가 부르는 이름이 바뀌지 않았다.
  String get _title => _isEdit ? '장소 수정' : '플레이스 등록';

  static const _titleStyle = TextStyle(
    fontFamily: 'SeoulHangang',
    fontWeight: FontWeight.w500,
    shadows: [
      Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
      Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
      Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
      Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
    ],
  );

  String get _placeNameOrDefault =>
      _nameCtrl.text.trim().isEmpty ? '내 장소' : _nameCtrl.text.trim();

  // 장소 운영 시간 헬퍼
  String _fmtPlaceTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtPlaceTimeDisplay(TimeOfDay t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    if (h == 0) return '오전 12:$m';
    if (h < 12) return '오전 $h:$m';
    if (h == 12) return '오후 12:$m';
    return '오후 ${h - 12}:$m';
  }

  /// 평일/주말 공통 시간 칸 — 여기서 고른 값이 '전체 적용'으로 요일별 칸에 들어간다.
  Future<void> _pickCommonHour({
    required bool weekend,
    required bool isOpen,
  }) async {
    final current = weekend
        ? (isOpen ? _placeWeekendOpenTime : _placeWeekendCloseTime)
        : (isOpen ? _placeOpenTime : _placeCloseTime);
    final picked = await showTimePicker(
      context: context,
      initialTime:
          current ??
          (isOpen
              ? const TimeOfDay(hour: 9, minute: 0)
              : const TimeOfDay(hour: 23, minute: 0)),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF7C5CBF)),
          ),
          child: child!,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (weekend) {
        if (isOpen) {
          _placeWeekendOpenTime = picked;
        } else {
          _placeWeekendCloseTime = picked;
        }
      } else {
        if (isOpen) {
          _placeOpenTime = picked;
        } else {
          _placeCloseTime = picked;
        }
      }
    });
  }

  bool get _showPetPolicyDetails =>
      _petPolicy.status == PetPolicyStatus.possible ||
      _petPolicy.status == PetPolicyStatus.conditional;

  // ── UI 헬퍼 ──────────────────────────────────────────────────────────────

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF7F7FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
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
            child,
          ],
        ),
      );

  // ── 빌드 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 수정 모드는 기존 룸을 다 읽은 뒤에 폼을 그린다 — 먼저 그리면 룸이 하나도
    // 없는 것처럼 보였다가 뒤늦게 나타난다.
    if (_loadingRooms) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          title: Text(_title, style: _titleStyle),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Stack 오버레이 방식 — _isUploading 중에도 Form·RoomCard 를 트리에 유지
    final navigator = Navigator.of(context);
    return PopScope(
      canPop: !draftDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await confirmLeaveWithDraftSave();
        if (!mounted || !navigator.mounted) return;
        if (leave) navigator.pop();
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xFFF3F4F6),
            appBar: AppBar(
              title: Text(_title, style: _titleStyle),
              centerTitle: true,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
              // 운영 도구(판매 통계·이용권 QR)는 이미 만들어진 장소에만 쓸 수
              // 있다 — 등록 중에는 placeId 자체가 없다.
              actions: _isEdit
                  ? [
                      IconButton(
                        icon: const Icon(Icons.insert_chart_outlined),
                        tooltip: '판매 통계',
                        onPressed: () => Navigator.push(
                          context,
                          webFramedRoute(
                            (_) => PlaceSalesDashboardScreen(
                              placeId: widget.docId!,
                              placeName: _placeNameOrDefault,
                              accent: const Color(0xFF7C5CBF),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        tooltip: 'QR 체크인',
                        onPressed: () => Navigator.push(
                          context,
                          webFramedRoute(
                            (_) => const CheckInScanScreen(),
                          ),
                        ),
                      ),
                    ]
                  : [draftSaveAction()],
              bottom: _isEdit ? null : buildAutoSaveIndicator(),
            ),
            body: Form(
              key: _formKey,
              // 값을 채우면 빨간 문구가 즉시 사라지도록 자동 재검증.
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                children: [
                  // 플레이스 등록 두 유형이 함께 쓰는 상단 안내 —
                  // 매장 폼(event_register_screen.dart)과 같은 위젯이다.
                  if (!_isEdit) const PlaceScopeNotice(),
                  // 어떤 공간인가요? — 플레이스+파티 등록과 같은 위젯·같은
                  // 선택지다. 여기서 매장·즐길거리를 고르면 셸이 매장 폼으로
                  // 바꾼다(저장도 events로 간다).
                  if (widget.onSpaceTypeChanged != null)
                    SpaceTypeSelector(
                      value: ComboPlaceType.stay,
                      onChanged: _requestSpaceTypeChange,
                    ),
                  if (draftMediaNeedsReselect) buildMediaReselectBanner(),
                  RegisterMissingFieldsBanner(fields: _missingFields),
                  // 필수항목 안내가 가리키는 영역들 — 0높이 마커가 아니라
                  // **영역 자체**를 감싼다. 그래야 이동한 뒤 어디로 왔는지
                  // 잠깐 강조해 보여줄 수 있다([RegisterFieldAnchor]).
                  RegisterFieldAnchor(
                    key: _basicInfoKey,
                    child: _buildBasicInfo(),
                  ),
                  _buildPlaceType(),
                  RegisterFieldAnchor(key: _photosKey, child: _buildPhotos()),
                  _buildDescription(),
                  // 수정 화면과 같은 순서·같은 공용 섹션.
                  PartychuPerkSection(controller: _partychuPerkCtrl),
                  // 수정 모드에서 목록을 다 읽기 전에는 그리지 않는다 — 빈
                  // 목록으로 보였다가 저장되면 기존 상품이 지워진 것처럼 보인다.
                  if (_productsLoaded) ...[
                    // 이벤트는 등록과 수정에서 창구가 다르다.
                    //   신규: 폼 안에서 첫 이벤트를 함께 넣는다(기존 흐름).
                    //   수정: 별도 관리 화면으로 보낸다 — 이 폼의 저장은
                    //         목록 전체를 치환(syncForPlace)하므로, 관리
                    //         화면에서 그사이 추가한 이벤트가 낡은 목록에
                    //         밀려 사라지는 걸 구조적으로 막는다.
                    if (_isEdit)
                      PlaceEventManageEntryCard(
                        placeId: widget.docId!,
                        placeCollection: 'places',
                        hostId: _source['hostId'] as String? ?? '',
                        placeName: _placeNameOrDefault,
                        accent: const Color(0xFF7C5CBF),
                      )
                    else
                      PlacePromotionSection(
                        promotions: _promotions,
                        onChanged: () => setState(markDraftDirty),
                        accent: const Color(0xFF7C5CBF),
                        linkableProducts: _products,
                      ),
                    RegisterFieldAnchor(
                      key: _productsKey,
                      child: PlaceProductSection(
                        products: _products,
                        onChanged: () => setState(markDraftDirty),
                        accent: const Color(0xFF7C5CBF),
                        // 취소·환불 규정이 비어 있는 상품을 펼치고, 그 입력칸에
                        // 앵커를 붙여 준다 — 안내 문구를 누르면 섹션이 아니라
                        // **그 칸**으로 간다.
                        revealRefundOf: _revealProductRefund,
                        refundAnchorKey: _productRefundKey,
                        refundFocusNode: _productRefundFocus,
                      ),
                    ),
                  ],
                  _buildPlaceHours(),
                  _buildSeatingSection(),
                  _buildOutsideFoodSection(),
                  _buildPetPolicySection(),
                  _buildCommonFacilities(),
                  // 정식 편의시설 선택지 **아래** — 위에서 고를 수 있는 것을
                  // 다 본 뒤에 "여기 없는 것"을 적게 된다.
                  CustomAmenitySection(
                    items: _customAmenities,
                    onChanged: (next) {
                      setState(() {
                        _customAmenities = next;
                        _customAmenitiesTouched = true;
                      });
                      markDraftDirty();
                    },
                  ),
                  RegisterFieldAnchor(
                    key: _roomsKey,
                    child: _buildRoomsSection(),
                  ),
                  _buildStayAndContactSection(),
                  // 문의 받기는 "게스트와 어떻게 연락할지"라 연락처 안내 바로
                  // 아래에 둔다.
                  GuestInquirySection(
                    enabled: _inquiryEnabled,
                    onChanged: (v) => setState(() => _inquiryEnabled = v),
                    guideController: _inquiryGuideCtrl,
                  ),
                  _buildPayoutAccount(),
                  _buildAutoMessageSection(),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isUploading ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C5CBF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: Text(widget.mode.submitLabel('장소')),
                    ),
                  ),
                  // 삭제는 앱 전체가 같은 흐름을 쓴다(공용 DeleteContentButton).
                  // 등록 중에는 지울 대상이 아직 없다.
                  if (_isEdit)
                    DeleteContentButton(
                      type: DeletableContent.place,
                      id: widget.docId!,
                      contentName: _nameCtrl.text.trim(),
                    ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),

          // 업로드 중 반투명 오버레이
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
                    Text(
                      _uploadStatus,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 섹션 빌드 ─────────────────────────────────────────────────────────────

  Widget _buildBasicInfo() => _sectionCard(
    title: '기본 정보',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('장소명 *'),
        PartyTitleField(
          controller: _nameCtrl,
          focusNode: _nameFocus,
          decoration: _inputDeco('예: 한강뷰 루프탑 파티룸'),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? '장소명을 입력해주세요' : null,
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
              color: _showAddressError
                  ? const Color(0xFFFFF0F0)
                  : const Color(0xFFF7F7FA),
              borderRadius: BorderRadius.circular(12),
              border: _showAddressError
                  ? Border.all(color: Colors.redAccent)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  size: 18,
                  color: _showAddressError
                      ? Colors.redAccent
                      : const Color(0xFFFF6FA0),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedAddress?.roadAddress ?? '주소를 검색해주세요',
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedAddress == null
                          ? (_showAddressError
                                ? Colors.redAccent
                                : Colors.black38)
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
            child: Text(
              '주소를 검색해주세요',
              style: TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ),
        _label('상세주소'),
        TextFormField(
          controller: _detailAddressCtrl,
          decoration: _inputDeco('동/호수, 층수 등'),
        ),
        // 공간 평수 — 플레이스 등록·콤보 등록과 **같은 필드·같은 검증·같은
        // 입력칸**을 쓴다([PlaceAreaField]). 단위 '평'은 입력칸이 붙이므로
        // 저장값은 언제나 숫자다.
        RegisterFieldAnchor(
          key: _areaKey,
          child: PlaceAreaField(
            controller: _areaCtrl,
            focusNode: _areaFocus,
            decoration: _inputDeco(PlaceArea.placeholder),
            labelBuilder: _label,
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    ),
  );

  Widget _buildPlaceType() => _sectionCard(
    title: '장소 유형',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('상세검색에서 노출될 장소 유형을 선택해주세요 (여러 개 선택 가능)'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ListingConstants.placeTypes.map((t) {
            final sel = _placeTypes.contains(t);
            return GestureDetector(
              onTap: () => setState(() {
                // 최소 1개는 남긴다 — 카드 라벨에 쓰는 대표 유형이 비면 안 된다.
                if (sel) {
                  if (_placeTypes.length > 1) _placeTypes.remove(t);
                } else {
                  _placeTypes.add(t);
                }
                markDraftDirty();
              }),
              child: _facilityChip(t, selected: sel),
            );
          }).toList(),
        ),
      ],
    ),
  );

  // 파티 등록과 동일한 공용 미디어 편집 화면(PartyMediaEditor)을 재사용한다 —
  // 사진 여러 장 + 동영상 1개(길이/용량 제한·압축 동일), 대표 미디어 선택(핑크
  // 테두리·체크·'대표' 배지)까지 동일하게 지원된다.
  Widget _buildPhotos() => _sectionCard(
    title: '장소 대표 사진 / 동영상',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('사진 최대 10장 · 동영상 1개(최대 30초) *'),
        if (_mediaSummary() != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _mediaSummary()!,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _openMediaPicker,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: Text(_mediaSummary() == null ? '사진 / 동영상 등록' : '사진 / 동영상 수정'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _showImageError
                ? Colors.redAccent
                : const Color(0xFF7C5CBF),
            side: BorderSide(
              color: _showImageError
                  ? Colors.redAccent
                  : const Color(0xFF7C5CBF),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        if (_showImageError)
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 4),
            child: Text(
              '대표 사진 / 동영상을 최소 1개 등록해주세요',
              style: TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ),
      ],
    ),
  );

  Widget _buildDescription() => _sectionCard(
    title: '장소 소개',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('장소 설명 *'),
        RegisterFieldAnchor(
          key: _descriptionKey,
          child: TextFormField(
            controller: _descCtrl,
            focusNode: _descFocus,
            maxLines: 5,
            decoration: _inputDeco('장소의 특징, 분위기, 접근 방법 등을 소개해주세요'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? '장소 설명을 입력해주세요' : null,
          ),
        ),
      ],
    ),
  );

  /// 좌석·공간 — 기본은 접힌 상태로, 선택한 항목 요약만 보여준다.
  /// 앞으로 흡연실·주차·와이파이 같은 섹션도 groups만 바꿔 같은 위젯으로
  /// 추가할 수 있다(PlaceFacilityCatalog 참고).
  Widget _buildSeatingSection() => PlaceFacilityOptionsSection(
    emoji: '🪑',
    title: '좌석·공간',
    emptyHint: '좌석 및 공간 정보를 설정해주세요.',
    groups: PlaceFacilityCatalog.seatingSection,
    value: _facilityOptions,
    capacityNote: '장소 전체의 최대 수용 인원은 아래 "룸/공간"에서 룸별로 설정한 값으로 집계돼요.',
    onChanged: (next) {
      setState(() => _facilityOptions = next);
      markDraftDirty();
    },
  );

  // 외부 음식 반입 — 좌석과 성격이 달라 섹션을 나눈다. 같은 facilityOptions
  // 필드에 그룹 키 하나로 얹히므로 저장·복원·상세 표시가 기존 편의시설과
  // 완전히 같은 경로를 탄다. 장소대여는 상세검색 필터에서도 이 값을 본다.
  Widget _buildOutsideFoodSection() => PlaceFacilityOptionsSection(
    emoji: '🍽',
    title: '외부 음식 반입',
    emptyHint: '외부 음식 반입 가능 여부를 설정해주세요.',
    groups: PlaceFacilityCatalog.foodSection,
    value: _facilityOptions,
    onChanged: (next) {
      setState(() => _facilityOptions = next);
      markDraftDirty();
    },
  );

  Widget _buildPetPolicySection() => _sectionCard(
    title: '애견동반',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '반려동물 동반 가능 여부를 선택해주세요.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _petStatusOption('불가', PetPolicyStatus.notAllowed),
            _petStatusOption('가능', PetPolicyStatus.possible),
            _petStatusOption('조건부 가능', PetPolicyStatus.conditional),
          ],
        ),
        if (_showPetPolicyDetails) ...[
          const SizedBox(height: 16),
          const Text(
            '동반 가능한 반려동물',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['강아지', '고양이', '기타'].map((animal) {
              final selected = _petPolicy.allowedAnimals.contains(animal);
              return GestureDetector(
                onTap: () => setState(() {
                  final next = {..._petPolicy.allowedAnimals};
                  if (selected) {
                    next.remove(animal);
                  } else {
                    next.add(animal);
                  }
                  _petPolicy = _petPolicy.copyWith(allowedAnimals: next);
                }),
                child: _petChoiceChip(animal, selected),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text(
            '크기 제한',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['제한 없음', '소형견만', '중형견까지', '직접 입력'].map((option) {
              final selected =
                  _petPolicy.sizeLimit == option ||
                  (option == '직접 입력' &&
                      _petPolicy.sizeLimit != null &&
                      ![
                        '제한 없음',
                        '소형견만',
                        '중형견까지',
                      ].contains(_petPolicy.sizeLimit));
              return GestureDetector(
                onTap: () {
                  if (option == '직접 입력') {
                    final text = _petPolicy.sizeLimit ?? '소형견만';
                    setState(
                      () => _petPolicy = _petPolicy.copyWith(sizeLimit: text),
                    );
                    return;
                  }
                  setState(
                    () => _petPolicy = _petPolicy.copyWith(sizeLimit: option),
                  );
                },
                child: _petChoiceChip(option, selected),
              );
            }).toList(),
          ),
          if (_petPolicy.sizeLimit != null &&
              !['제한 없음', '소형견만', '중형견까지'].contains(_petPolicy.sizeLimit)) ...[
            const SizedBox(height: 8),
            TextField(
              controller: TextEditingController(text: _petPolicy.sizeLimit)
                ..selection = TextSelection.collapsed(
                  offset: _petPolicy.sizeLimit!.length,
                ),
              decoration: _inputDeco('예: 대형견 제외, 10kg 이하만'),
              onChanged: (value) => setState(
                () => _petPolicy = _petPolicy.copyWith(
                  sizeLimit: value.trim().isEmpty ? null : value.trim(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _label('최대 동반 가능 수'),
          TextField(
            keyboardType: TextInputType.number,
            decoration: _inputDeco('예: 2'),
            controller:
                TextEditingController(
                    text: _petPolicy.maxCount?.toString() ?? '',
                  )
                  ..selection = TextSelection.collapsed(
                    offset: (_petPolicy.maxCount?.toString() ?? '').length,
                  ),
            onChanged: (value) {
              final parsed = int.tryParse(value.trim());
              setState(
                () => _petPolicy = _petPolicy.copyWith(maxCount: parsed),
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _petPolicy.extraFeeEnabled,
                onChanged: (value) => setState(
                  () => _petPolicy = _petPolicy.copyWith(
                    extraFeeEnabled: value ?? false,
                  ),
                ),
              ),
              const Expanded(child: Text('추가 비용 있음')),
            ],
          ),
          if (_petPolicy.extraFeeEnabled) ...[
            const SizedBox(height: 8),
            TextField(
              keyboardType: TextInputType.number,
              decoration: _inputDeco('예: 5000'),
              controller:
                  TextEditingController(
                      text: (_petPolicy.extraFeeAmount ?? 0).toString(),
                    )
                    ..selection = TextSelection.collapsed(
                      offset: (_petPolicy.extraFeeAmount ?? 0)
                          .toString()
                          .length,
                    ),
              onChanged: (value) {
                final parsed = int.tryParse(value.trim());
                setState(
                  () =>
                      _petPolicy = _petPolicy.copyWith(extraFeeAmount: parsed),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            '이용 조건',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['매너벨트 필수', '케이지 필수', '실내 이동 제한', '예방접종 완료', '기타'].map((
              item,
            ) {
              final selected = _petPolicy.requiredConditions.contains(item);
              return GestureDetector(
                onTap: () => setState(() {
                  final next = {..._petPolicy.requiredConditions};
                  if (selected) {
                    next.remove(item);
                  } else {
                    next.add(item);
                  }
                  _petPolicy = _petPolicy.copyWith(requiredConditions: next);
                }),
                child: _petChoiceChip(item, selected),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text(
            '추가 안내 문구',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            maxLines: 3,
            decoration: _inputDeco('예: 실외 산책은 가능하나 실내는 제외됩니다.'),
            controller: TextEditingController(text: _petPolicy.notes ?? '')
              ..selection = TextSelection.collapsed(
                offset: (_petPolicy.notes ?? '').length,
              ),
            onChanged: (value) => setState(
              () => _petPolicy = _petPolicy.copyWith(
                notes: value.trim().isEmpty ? null : value.trim(),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _petStatusOption(String label, PetPolicyStatus status) =>
      GestureDetector(
        onTap: () =>
            setState(() => _petPolicy = _petPolicy.copyWith(status: status)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _petPolicy.status == status
                ? const Color(0xFFFF6FA0)
                : const Color(0xFFFFF4F8),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _petPolicy.status == status
                  ? Colors.white
                  : Colors.black87,
            ),
          ),
        ),
      );

  Widget _petChoiceChip(String label, bool selected) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFFFFE8F2) : const Color(0xFFF7F7FA),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: selected ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: selected ? const Color(0xFFFF6FA0) : Colors.black87,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    ),
  );

  Widget _buildCommonFacilities() => _sectionCard(
    title: '공용 편의시설',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('전체 장소에 해당하는 시설을 선택해주세요'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // ── 프리셋 옵션 칩 ──────────────────────────────────
            ..._commonFacilityOptions.map((f) {
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
            // ── 직접 입력한 항목 칩 (삭제 버튼 포함) ──────────
            ..._customCommonFacilities.map(
              (f) => _customChip(
                f,
                onDelete: () =>
                    setState(() => _customCommonFacilities.remove(f)),
              ),
            ),
            // ── 직접 입력 버튼 ──────────────────────────────────
            GestureDetector(
              onTap: _openCustomFacilityInput,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7FA),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFDDE1EC),
                    style: BorderStyle.solid,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 13, color: Colors.black45),
                    SizedBox(width: 3),
                    Text(
                      '직접 입력',
                      style: TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // ── 인라인 입력 필드 ────────────────────────────────────
        if (_showCustomFacilityInput) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customFacilityCtrl,
                  focusNode: _customFacilityFocus,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: '편의시설 이름 입력 (예: 루프탑, 수영장)',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: Colors.black38,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFDDE1EC)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF7C5CBF)),
                    ),
                  ),
                  onSubmitted: (_) => _addCustomFacility(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _addCustomFacility,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF7C5CBF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('추가', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.black38),
                onPressed: _closeCustomFacilityInput,
                tooltip: '취소',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  void _openCustomFacilityInput() {
    setState(() => _showCustomFacilityInput = true);
    // autofocus 대신 한 번만 요청한다 — autofocus는 rebuild마다 다시 걸려
    // 포커스/키보드가 깜빡이는 원인이 된다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showCustomFacilityInput) {
        _customFacilityFocus.requestFocus();
      }
    });
  }

  /// 입력칸을 닫는다. 순서가 중요하다 — **먼저 포커스를 놓고** 트리에서
  /// 없앤다. 포커스를 가진 채로 사라지면 Flutter가 스코프의 직전 포커스
  /// 대상(보통 화면 위쪽 입력칸)으로 포커스를 되돌리고, 그 입력칸이
  /// showOnScreen()을 부르면서 목록이 위로 튀어 오른다.
  void _closeCustomFacilityInput() {
    _customFacilityFocus.unfocus(); // 기본 scope 처분 — 포커스 이력까지 비운다
    _customFacilityCtrl.clear();
    setState(() => _showCustomFacilityInput = false);
  }

  void _addCustomFacility() {
    final text = _customFacilityCtrl.text.trim();
    if (text.isEmpty) {
      _closeCustomFacilityInput();
      return;
    }
    // 이미 프리셋에 있는 값이면 프리셋 선택으로 처리
    if (_commonFacilityOptions.contains(text)) {
      _commonFacilities.add(text);
    } else {
      _customCommonFacilities.add(text);
    }
    _closeCustomFacilityInput();
  }

  Widget _facilityChip(String label, {required bool selected}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFFF3EFFA) : const Color(0xFFF7F7FA),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: selected ? const Color(0xFF7C5CBF) : const Color(0xFFDDE1EC),
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: selected ? const Color(0xFF7C5CBF) : Colors.black54,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
    ),
  );

  Widget _customChip(String label, {required VoidCallback onDelete}) =>
      Container(
        padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3EFFA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF7C5CBF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF7C5CBF),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onDelete,
              child: const Icon(
                Icons.close,
                size: 14,
                color: Color(0xFF7C5CBF),
              ),
            ),
          ],
        ),
      );

  Widget _buildRoomsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 룸 카드들
        ...List.generate(
          _roomKeys.length,
          (i) => RoomCard(
            key: _roomKeys[i],
            index: i,
            onRemove: () => _removeRoom(i),
            getPreviousData: i > 0
                ? () => _roomKeys[i - 1].currentState?.getRoomData()
                : null,
            // 임시저장에서 복원된 룸이면 그 데이터로 초기화한다(신규 룸은 null).
            initialData: i < _roomInitialData.length
                ? _roomInitialData[i]
                : null,
          ),
        ),

        // 룸 추가 버튼
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: OutlinedButton.icon(
            onPressed: _addRoom,
            icon: const Icon(Icons.add_circle_outline, size: 20),
            label: Text(
              _roomKeys.isEmpty ? '룸 추가하기' : '룸 추가하기 (${_roomKeys.length}개)',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF7C5CBF),
              side: const BorderSide(color: Color(0xFF7C5CBF), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        if (_roomKeys.isEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _showRoomError
                  ? const Color(0xFFFFF0F0)
                  : const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _showRoomError
                    ? Colors.redAccent
                    : const Color(0xFFFFE082),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _showRoomError ? Icons.error_outline : Icons.info_outline,
                  size: 16,
                  color: _showRoomError
                      ? Colors.redAccent
                      : const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _showRoomError
                        ? '룸을 최소 1개 이상 추가해주세요.'
                        : '룸을 1개 이상 추가해야 장소를 등록할 수 있습니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: _showRoomError
                          ? Colors.redAccent
                          : const Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceHours() => _sectionCard(
    title: '운영시간',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 12),
          child: Text(
            '플레이스 이용 가능한 시간을 설정해주세요.',
            style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7FA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _placeIsOpen24Hours
                      ? '✓ 상시 운영 (24시간 또는 제한 없음)'
                      : '✓ 운영시간 직접 설정',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch(
                // 켜면 상시 운영 → 운영시간 입력 UI를 숨긴다.
                value: _placeIsOpen24Hours,
                onChanged: (v) => setState(() => _placeIsOpen24Hours = v),
                activeColor: const Color(0xFF7C5CBF),
              ),
            ],
          ),
        ),
        if (!_placeIsOpen24Hours) ...[
          const SizedBox(height: 10),
          // 휴무·24시간·영업시간·브레이크 타임을 한 편집기에서 다룬다 —
          // 수정 화면·통합 등록 화면도 같은 위젯을 쓰므로 설정이 어긋나지 않는다.
          WeeklyHoursEditor(
            hours: _placeWeeklyHours,
            onChanged: () => setState(() {}),
            weekdayStart: _placeOpenTime,
            weekdayEnd: _placeCloseTime,
            weekendStart: _placeWeekendOpenTime,
            weekendEnd: _placeWeekendCloseTime,
            onPickBaseTime: (weekend, isStart) =>
                _pickCommonHour(weekend: weekend, isOpen: isStart),
            formatTime: _fmtPlaceTimeDisplay,
          ),
        ] else ...[
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3EFFA),
              borderRadius: BorderRadius.circular(12),
            ),
            // 좁은 화면에서 문구가 한 줄에 안 들어가 오버플로가 나던 배너.
            child: const Row(
              children: [
                Icon(Icons.schedule, size: 16, color: Color(0xFF7C5CBF)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '상시 운영 (24시간 또는 제한 없음)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF7C5CBF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _buildAutoMessageSection() => _sectionCard(
    title: '예약자 자동 안내 문구',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.notifications_outlined,
              size: 14,
              color: Color(0xFF7C5CBF),
            ),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                '예약 시간 2시간 전에 예약자에게 자동으로 발송돼요.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7C5CBF)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _autoMsgCtrl,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: '예: 안녕하세요! 예약해주셔서 감사합니다.\n오늘 이용 시 준비물 안내드립니다...',
            hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE8EBF2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE8EBF2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF7C5CBF)),
            ),
          ),
        ),
      ],
    ),
  );

  /// 연락처 + 숙박 체크인/체크아웃 + 패키지 예약 — 수정 화면과 동일한 섹션.
  Widget _buildStayAndContactSection() => _sectionCard(
    title: '연락처 · 숙박 이용 안내',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('연락처'),
        TextField(
          controller: _contactCtrl,
          keyboardType: TextInputType.phone,
          decoration: _inputDeco('예: 010-1234-5678'),
        ),
        const SizedBox(height: 18),
        const Text(
          '체크인 · 체크아웃 시간',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          '숙박형 장소에서만 쓰여요. 파티 상세의 "숙박 정보"에 그대로 표시됩니다.',
          style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.5),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _stayTimePicker(isCheckIn: true)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('~', style: TextStyle(fontSize: 16)),
            ),
            Expanded(child: _stayTimePicker(isCheckIn: false)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Checkbox(
              value: _packageBookingEnabled,
              onChanged: (v) => setState(() {
                _packageBookingEnabled = v ?? false;
                // 수정 모드에서 이 필드가 없던 문서라도, 사용자가 직접 켜고
                // 끄면 그때부터 저장 대상이 된다(_hadPackage 참고).
                _packageTouched = true;
                markDraftDirty();
              }),
              activeColor: const Color(0xFF7C5CBF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Expanded(
              child: Text(
                '숙박+파티 패키지 예약 받기',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        if (_packageBookingEnabled) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _packagePriceNoteCtrl,
            maxLines: 2,
            decoration: _inputDeco('패키지 요금 안내 문구 (선택)'),
          ),
        ],
      ],
    ),
  );

  Widget _stayTimePicker({required bool isCheckIn}) {
    final time = isCheckIn ? _checkInTime : _checkOutTime;
    final hasTime = time != null;
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime:
              time ??
              (isCheckIn
                  ? const TimeOfDay(hour: 15, minute: 0)
                  : const TimeOfDay(hour: 11, minute: 0)),
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
            child: Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFF7C5CBF),
                ),
              ),
              child: child!,
            ),
          ),
        );
        if (picked == null || !mounted) return;
        setState(() {
          if (isCheckIn) {
            _checkInTime = picked;
          } else {
            _checkOutTime = picked;
          }
          // 수정 모드에서 이 필드가 없던 문서라도, 사용자가 직접 시각을 고르면
          // 그때부터 저장 대상이 된다(_hadStayTimes 참고).
          _stayTimesTouched = true;
          markDraftDirty();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hasTime ? const Color(0xFFF3EFFA) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: hasTime
              ? Border.all(
                  color: const Color(0xFF7C5CBF).withValues(alpha: 0.4),
                )
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isCheckIn ? '체크인' : '체크아웃',
                  style: const TextStyle(fontSize: 11, color: Colors.black38),
                ),
                const SizedBox(height: 2),
                Text(
                  hasTime ? _fmtPlaceTimeDisplay(time) : '선택하세요',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: hasTime ? FontWeight.w600 : FontWeight.normal,
                    color: hasTime ? const Color(0xFF7C5CBF) : Colors.black38,
                  ),
                ),
              ],
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: hasTime ? const Color(0xFF7C5CBF) : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }

  /// **입금받을 계좌**(수취계좌) 안내.
  ///
  /// 예전에는 여기서 은행·계좌번호·예금주를 직접 받아 places/{id}.payoutAccount
  /// 로 저장했다. 그런데 places 문서는 규칙상 **누구나 읽을 수 있어**(손님이
  /// 장소 상세를 보려면 열려 있어야 한다) 호스트의 계좌번호가 그대로 공개됐다.
  /// 그래서 입력을 없애고 **계정 단위 계좌 한 곳**으로 통일했다.
  ///
  /// ⚠ 그 "한 곳"이 한동안 정산계좌(users/{uid}.settlementInfo)로 적혀 있었는데,
  /// 이용요금이 실제로 들어오는 계좌는 **수취계좌**(users/{uid}.payoutAccount)다
  /// — 참가비·예약금은 파티츄를 거치지 않고 호스트 계좌로 바로 입금된다.
  /// 정산계좌는 "향후 파티츄가 호스트에게 보낼" 계좌라 이 화면과 관계가 없어,
  /// 진입점은 마이페이지에만 둔다(두 계좌를 같은 말로 부르지 않는다).
  Widget _buildPayoutAccount() => _sectionCard(
    title: '입금받을 계좌',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 10),
          child: Text(
            '이용요금·예약금은 이 계좌로 바로 들어와요.\n'
            '계정에 한 번만 등록·인증하면 등록한 모든 파티·플레이스·장소에 '
            '함께 쓰여요.\n'
            '계좌 정보는 본인만 볼 수 있는 곳에 따로 보관됩니다.',
            style: TextStyle(fontSize: 13, color: Colors.black45, height: 1.5),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              webFramedRoute((_) => const PayoutAccountScreen()),
            ),
            icon: const Icon(Icons.account_balance, size: 18),
            label: const Text('입금받을 계좌 관리로 이동'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF6FA0),
              side: const BorderSide(color: Color(0xFFFF6FA0)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
