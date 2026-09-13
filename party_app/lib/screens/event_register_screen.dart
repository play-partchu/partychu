import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:party_app/screens/full_screen_image_viewer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/place_area.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/screens/address_search_screen.dart';
import 'package:party_app/screens/place_event_manage_screen.dart';
import 'package:party_app/screens/place_party_link_screen.dart';
import 'package:party_app/screens/place_sales_dashboard_screen.dart';
import 'package:party_app/screens/check_in_scan_screen.dart';
import 'package:party_app/services/place_followup_entry.dart';
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/screens/party_media_picker_screen.dart';
import 'package:party_app/utils/video_crop.dart';
import 'package:party_app/widgets/party_media_editor.dart';
import 'package:party_app/services/content_delete_service.dart'
    show DeletableContent;
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/services/place_menu_service.dart';
import 'package:party_app/services/place_promotion_service.dart';
import 'package:party_app/models/draft_type.dart';
import 'package:party_app/utils/draftable_register.dart';
import 'package:party_app/utils/partychu_perk_sync.dart';
import 'package:party_app/utils/register_form_mode.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/services/registration_limits.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/delete_content_action.dart';
import 'package:party_app/models/combo_place_type.dart';
import 'package:party_app/widgets/space_type_selector.dart';
import 'package:party_app/widgets/place_scope_notice.dart';
import 'package:party_app/widgets/partychu_perk.dart';
import 'package:party_app/models/pet_policy.dart';
import 'package:party_app/models/place_facility_options.dart';
import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/product_refund_feature.dart';
import 'package:party_app/models/place_menu.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/models/place_visit_reservation.dart';
import 'package:party_app/utils/register_validation.dart';
import 'package:party_app/models/place_weekly_hours.dart';
import 'package:party_app/widgets/party_form/register_field_anchor.dart';
import 'package:party_app/widgets/party_form/register_missing_fields_banner.dart';
import 'package:party_app/widgets/place_form/place_area_field.dart';
import 'package:party_app/widgets/place_form/pet_policy_section.dart';
import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/models/custom_play_item.dart';
import 'package:party_app/widgets/place_form/custom_amenity_section.dart';
import 'package:party_app/widgets/place_form/place_facility_options_section.dart';
import 'package:party_app/widgets/place_form/place_attributes_section.dart';
import 'package:party_app/widgets/place_form/place_category_section.dart';
import 'package:party_app/widgets/place_form/place_hours_section.dart';
import 'package:party_app/widgets/place_form/place_menu_section.dart';
import 'package:party_app/widgets/place_form/place_promotion_section.dart';
import 'package:party_app/widgets/place_form/place_product_section.dart';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/widgets/guest_inquiry_section.dart';
import 'package:party_app/widgets/place_form/visit_reservation_section.dart';
import 'package:party_app/widgets/payout_account_prompt.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 플레이스(events) 폼의 **정본**.
///
/// 등록과 수정(= 숨김 상태에서는 재등록)이 이 화면 하나를 공유한다. 예전에는
/// event_register_screen.dart와 event_edit_screen.dart가 메서드 이름과 섹션
/// 순서까지 똑같은 복사본이었고, 그 사이 내부 751줄이 이미 어긋나 있었다 —
/// 대표적으로 수정 화면에서는 상품 섹션의 로딩 가드가 중괄호 없는 `if` 탓에
/// 프로모션 섹션에만 걸려 있었다.
///
/// 이제 입력 항목·섹션 순서·검증·사진/동영상·운영시간·상품·이용권·이벤트·주소가
/// 두 모드에서 100% 같다. 모드가 바꾸는 것은 아래뿐이다.
///
///   1. 화면 제목·제출 버튼 문구 ([RegisterFormMode])
///   2. 진입 시 기존 문서를 불러오는지 / 임시저장을 쓰는지
///   3. 저장이 `add`인지 `update`인지
///   4. 수정에만 있는 운영 도구 — 판매 통계·이용권 QR 스캔·삭제 버튼,
///      그리고 등록 직후에만 의미 있는 "기존 파티 연결" 제안
class EventRegisterScreen extends StatefulWidget {
  /// 등록인지 수정인지 — 자세한 계약은 [RegisterFormMode] 참고.
  final RegisterFormMode mode;

  /// 수정 모드에서 갱신할 `events` 문서 id.
  final String? eventId;

  /// 수정 모드에서 불러올 기존 문서.
  final Map<String, dynamic>? sourceData;

  /// 마이페이지 "임시저장" 목록에서 "이어서 작성"으로 열 때 true.
  final bool autoRestoreDraft;

  /// 공간 유형 선택기에서 다른 유형(공간대여·숙박)을 골랐을 때 셸에 알린다.
  ///
  /// null이면 선택기 자체를 그리지 않는다 — 수정 화면과, 셸을 거치지 않는
  /// 옛 호출부가 예전 그대로 동작한다.
  final ValueChanged<ComboPlaceType>? onSpaceTypeChanged;

  /// 유형 전환으로 다시 마운트된 경우 false — 복구 팝업을 띄우지 않는다.
  final bool offerDraftRestore;

  const EventRegisterScreen({
    super.key,
    this.autoRestoreDraft = false,
    this.onSpaceTypeChanged,
    this.offerDraftRestore = true,
  }) : mode = RegisterFormMode.create,
       eventId = null,
       sourceData = null;

  /// 플레이스 수정 진입 — 마이페이지 카드/플레이스 상세가 이 생성자를 쓴다.
  /// 숨김(isActive:false) 상태에서 저장하면 그대로 재등록(다시 노출)이 된다.
  const EventRegisterScreen.edit({
    super.key,
    required String this.eventId,
    required Map<String, dynamic> this.sourceData,
  }) : mode = RegisterFormMode.edit,
       autoRestoreDraft = false,
       onSpaceTypeChanged = null,
       offerDraftRestore = true;

  @override
  State<EventRegisterScreen> createState() => _EventRegisterScreenState();
}

class _EventRegisterScreenState extends State<EventRegisterScreen>
    with WidgetsBindingObserver, DraftableRegister<EventRegisterScreen> {
  bool get _isEdit => widget.mode.isEdit;

  /// 수정 모드에서 불러온 원본 문서 — 등록 모드에서는 빈 맵이다.
  Map<String, dynamic> get _source => widget.sourceData ?? const {};

  @override
  void setState(VoidCallback fn) {
    // 수정 모드에서는 임시저장을 쓰지 않으므로 markDraftDirty가 아무 일도 하지
    // 않는다(autosaver가 없고 _draftReady도 false다). 두 모드가 같은 setState를
    // 타도 안전하다.
    markDraftDirty();
    super.setState(fn);
  }

  @override
  DraftType get draftType => DraftType.event;

  @override
  bool get draftAutoRestore => widget.autoRestoreDraft;

  @override
  bool get draftOfferRestore => widget.offerDraftRestore;

  @override
  String get draftTitle => _nameCtrl.text;

  @override
  String? get draftCoverImageUrl => null;

  // ── 공간 유형 전환 ───────────────────────────────────────────────────
  // 플레이스+파티 등록(콤보)의 _requestTypeChange와 **같은 절차**다 — 확인 →
  // 지금 유형의 임시저장에 남기기 → 셸에 알리기. 다만 단독 등록은 두 폼이
  // 상태를 공유하지 않으므로 확인 문구가 그 사실을 말한다.

  Future<void> _requestSpaceTypeChange(ComboPlaceType next) async {
    final notify = widget.onSpaceTypeChanged;
    if (notify == null || next == ComboPlaceType.venue) return;
    // 아무것도 안 쓴 상태면 묻지도, 빈 임시저장을 남기지도 않는다 — 빈
    // 임시저장이 생기면 다음에 이 화면을 열 때 "작성 중인 내용이 있습니다"가
    // 뜬 뒤 이어서 작성해도 아무것도 복원되지 않는다.
    if (draftDirty) {
      final ok = await confirmSpaceTypeChange(
        context,
        from: ComboPlaceType.venue,
        to: next,
      );
      if (!ok || !mounted) return;
      await saveDraftNow();
      if (!mounted) return;
    }
    notify(next);
  }

  @override
  Map<String, dynamic> buildDraftPayload() {
    return <String, dynamic>{
      'name': _nameCtrl.text,
      'description': _descCtrl.text,
      kPartychuPerkField: _partychuPerkCtrl.text,
      'isActive': _isActive,
      // 'themeTags'·'eventSubtype'은 더 담지 않는다 — 입력이 사라졌으므로
      // 되살릴 값도 없다. 예전 형식의 임시저장에 그 키가 남아 있어도 복원
      // 쪽이 읽지 않으니 그냥 무시된다.
      'businessTypes': _businessTypes.toList(),
      'placeCategory': _placeCategory,
      'placeSubcategories': _subcategories.toList(),
      'placeAttributes': _placeAttributes.toDraftMap(),
      'priceRange': _priceRange,
      'placeProducts': PlaceProduct.listToDraft(_products),
      'placePromotions': PlacePromotion.listToDraft(_promotions),
      'placeMenus': PlaceMenu.listToDraft(_menus),
      // 순서를 살려 한 줄에 담는다('u:'는 올라간 사진, 'f:'는 로컬 파일).
      // 예전 키 두 개는 더 쓰지 않지만, 그 형식으로 저장된 임시저장도
      // 계속 열려야 하므로 복원 쪽에 폴백을 남겨 두었다.
      'menuBoardImageEntries': _menuBoardImages.map((m) => m.draftTag).toList(),
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
      'detailAddress': _detailAddressCtrl.text,
      'contactPhone': _contactCtrl.text,
      // 평수는 입력한 **문자열 그대로** 담는다 — 아직 검증 전이라 '12.'처럼
      // 숫자로 못 바꾸는 중간 상태도 그대로 되살아나야 한다.
      PlaceArea.field: _areaCtrl.text,
      'placeIsOpen24Hours': _placeIsOpen24Hours,
      'placeOpenTime': DraftableRegister.timeToMap(_placeOpenTime),
      'placeCloseTime': DraftableRegister.timeToMap(_placeCloseTime),
      'placeWeeklyHours': _placeWeeklyHours.toMap(),
      'visitReservation': _visitReservation.toMap(),
      ListingInquiry.field: _inquiryEnabled,
      ListingInquiry.guideField: _inquiryGuideCtrl.text,
      'petPolicy': _petPolicy.isUnspecified ? null : _petPolicy.toMap(),
      'facilityOptions': _facilityOptions.toDraftMap(),
      CustomAmenities.field: _customAmenities,
      // '기타'를 껐다 켜는 사이에도 적어 둔 값이 살아남도록, 임시저장에는
      // 프리셋 선택과 무관하게 담는다(문서에 쓸 때만 활성 여부를 본다).
      CustomPlayItems.field: _customPlayItems,
      // 로컬 미디어 경로(최선; 파일이 사라지면 복원 시 재선택 안내).
      'introImagePaths': [
        for (final f in _newIntroImages) LocalMedia.remember(f).path,
      ],
      // 대표 미디어 — 공용 픽커의 스냅샷을 그대로 담는다(장소대여와 같은 모양).
      'coverExistingImageUrls': _coverExistingImageUrls,
      'coverExistingVideoUrl': _coverExistingVideoUrl,
      'coverExistingVideoUid': _coverExistingVideoUid,
      'coverExistingVideoThumbnailUrl': _coverExistingVideoThumbnailUrl,
      'coverNewFilePaths': [
        for (final f in _coverNewFiles) LocalMedia.remember(f).path,
      ],
      'coverBasicCardFocalX': _coverBasicCardFocalX,
      'coverBasicCardFocalY': _coverBasicCardFocalY,
      'coverBasicCardScale': _coverBasicCardScale,
      'coverPhotoCrops': _coverPhotoCrops,
      'coverVideoCropConfirmed': _coverVideoCropConfirmed,
      'coverPick': _coverPick == null
          ? null
          : {
              'existingImageUrl': _coverPick!.existingImageUrl,
              'isExistingVideo': _coverPick!.isExistingVideo,
              'newImageOrdinal': _coverPick!.newImageOrdinal,
              'isNewVideo': _coverPick!.isNewVideo,
            },
    };
  }

  @override
  void applyDraftPayload(Map<String, dynamic> p) {
    _nameCtrl.text = (p['name'] as String?) ?? '';
    _descCtrl.text = (p['description'] as String?) ?? '';
    _partychuPerkCtrl.text = (p[kPartychuPerkField] as String?) ?? '';
    _detailAddressCtrl.text = (p['detailAddress'] as String?) ?? '';
    _isActive = p['isActive'] as bool? ?? true;
    _businessTypes
      ..clear()
      ..addAll(
        ((p['businessTypes'] as List?)?.cast<String>() ?? const []).take(
          _maxBusinessTypes,
        ),
      );
    _placeCategory = PlaceTaxonomy.byLabel(
      p['placeCategory'] as String?,
    )?.label;
    _subcategories
      ..clear()
      ..addAll(
        ((p['placeSubcategories'] as List?)?.cast<String>() ?? const []).take(
          _maxSubcategories,
        ),
      );
    _placeAttributes = PlaceAttributes.fromDraftMap(p['placeAttributes']);
    _priceRange = (p['priceRange'] as String?)?.isNotEmpty == true
        ? p['priceRange'] as String
        : null;
    _products
      ..clear()
      ..addAll(PlaceProduct.listFromDraft(p['placeProducts']));
    _promotions
      ..clear()
      ..addAll(PlacePromotion.listFromDraft(p['placePromotions']));
    _menus
      ..clear()
      ..addAll(PlaceMenu.listFromDraft(p['placeMenus']));
    _menuBoardImages.clear();
    final entries = p['menuBoardImageEntries'] as List?;
    if (entries != null) {
      for (final e in entries) {
        final parsed = _MenuBoardImage.fromDraftTag(e);
        if (parsed != null) _menuBoardImages.add(parsed);
      }
    } else {
      // 예전 형식(올라간 사진 목록 + 로컬 경로 목록)으로 저장된 임시저장.
      for (final u in (p['menuBoardImageUrls'] as List?) ?? const []) {
        if (u is String && u.isNotEmpty) {
          _menuBoardImages.add(_MenuBoardImage.url(u));
        }
      }
      for (final path in (p['menuBoardImagePaths'] as List?) ?? const []) {
        if (path is String && path.isNotEmpty) {
          _menuBoardImages.add(_MenuBoardImage.file(LocalMedia.resolve(path)));
        }
      }
    }
    _syncMenuModeFromData();
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
    _existingAddress = _selectedAddress?.address ?? '';
    // 진행 기간·이용 시간은 폼에서 없앴다 — 그 키가 들어 있는 옛 임시저장도
    // 나머지 값은 그대로 복원된다(없는 키를 읽지 않을 뿐이다).
    _contactCtrl.text = (p['contactPhone'] as String?) ?? '';
    // 평수를 받기 전에 만든 임시저장에는 이 키가 없다 — 빈 칸으로 열린다.
    _areaCtrl.text = (p[PlaceArea.field] as String?) ?? '';
    _placeIsOpen24Hours = p['placeIsOpen24Hours'] as bool? ?? false;
    _placeOpenTime = DraftableRegister.timeFromMap(p['placeOpenTime']);
    _placeCloseTime = DraftableRegister.timeFromMap(p['placeCloseTime']);
    final weeklyMap = p['placeWeeklyHours'];
    _placeWeeklyHours = PlaceWeeklyHours.fromMap(
      weeklyMap is Map ? Map<String, dynamic>.from(weeklyMap) : null,
    );
    final visitMap = p['visitReservation'];
    _visitReservation = PlaceVisitReservationConfig.fromMap(
      visitMap is Map ? Map<String, dynamic>.from(visitMap) : null,
    );
    _inquiryEnabled = ListingInquiry.isEnabled(p);
    _inquiryGuideCtrl.text = ListingInquiry.guideOf(p);
    final petMap = p['petPolicy'];
    _petPolicy = petMap is Map
        ? PetPolicy.fromMap(Map<String, dynamic>.from(petMap))
        : PetPolicy.empty();
    _facilityOptions = PlaceFacilityOptions.fromDraftMap(p['facilityOptions']);
    _customAmenities = CustomAmenities.of(p);
    _customPlayItems = CustomPlayItems.of(p);

    // 로컬 미디어 복원 — **파일이 남아 있을 때만** 되살린다. OS가 캐시를
    // 비웠으면 경로만 남고 파일은 없는데, 그대로 업로드에 들어가면 정체 불명의
    // 실패가 된다. 하나라도 사라졌으면 화면 위에 재선택 안내를 띄운다.
    bool anyMissing = false;

    _coverExistingImageUrls = [
      ...((p['coverExistingImageUrls'] as List?)?.cast<String>() ?? const []),
    ];
    _coverExistingVideoUrl = p['coverExistingVideoUrl'] as String?;
    _coverExistingVideoUid = p['coverExistingVideoUid'] as String?;
    _coverExistingVideoThumbnailUrl =
        p['coverExistingVideoThumbnailUrl'] as String?;
    _coverNewFiles = [];
    for (final path
        in (p['coverNewFilePaths'] as List?)?.cast<String>() ?? const []) {
      if (LocalMedia.exists(path)) {
        _coverNewFiles.add(LocalMedia.resolve(path));
      } else {
        anyMissing = true;
      }
    }
    _coverBasicCardFocalX =
        (p['coverBasicCardFocalX'] as num?)?.toDouble() ?? 0.5;
    _coverBasicCardFocalY =
        (p['coverBasicCardFocalY'] as num?)?.toDouble() ?? 0.5;
    _coverBasicCardScale =
        (p['coverBasicCardScale'] as num?)?.toDouble() ?? 1.0;
    _coverPhotoCrops = photoCropsFromRaw(p['coverPhotoCrops']);
    _coverVideoCropConfirmed = p['coverVideoCropConfirmed'] as bool? ?? false;
    final coverPick = p['coverPick'] as Map?;
    _coverPick = coverPick == null
        ? null
        : PartyCoverPick(
            existingImageUrl: coverPick['existingImageUrl'] as String?,
            isExistingVideo: coverPick['isExistingVideo'] as bool? ?? false,
            newImageOrdinal: (coverPick['newImageOrdinal'] as num?)?.toInt(),
            isNewVideo: coverPick['isNewVideo'] as bool? ?? false,
          );

    _newIntroImages.clear();
    for (final path
        in (p['introImagePaths'] as List?)?.cast<String>() ?? const []) {
      if (LocalMedia.exists(path)) {
        _newIntroImages.add(LocalMedia.resolve(path));
      } else {
        anyMissing = true;
      }
    }
    draftMediaNeedsReselect = anyMissing;
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      _nameCtrl,
      _descCtrl,
      _detailAddressCtrl,
      _partychuPerkCtrl,
      _contactCtrl,
      _areaCtrl,
    ]) {
      c.addListener(markDraftDirty);
    }
    if (_isEdit) {
      _prefillFromSource();
      _loadProducts();
    } else {
      // 임시저장은 "빈 화면에서 새로 등록하는 경우"에만 동작한다 — 수정은 이미
      // 문서 내용을 불러온 상태라 임시저장이 그걸 덮어쓰는 사고만 생긴다.
      initDraft();
      // 등록 모드에는 불러올 상품이 없다 — 섹션을 곧바로 보여준다.
      _productsLoaded = true;
    }
  }

  /// 수정 모드 진입 — 기존 문서 값으로 폼을 채운다.
  void _prefillFromSource() {
    final d = _source;
    _nameCtrl.text = d['name'] as String? ?? '';
    _descCtrl.text = d['description'] as String? ?? '';
    _partychuPerkCtrl.text = partychuPerkFrom(d) ?? '';
    _detailAddressCtrl.text = d['detailAddress'] as String? ?? '';
    _contactCtrl.text = d['contactPhone'] as String? ?? '';
    // 평수가 없던 옛 문서는 빈 칸으로 열린다 — 수정 저장에서 필수로 걸리므로
    // 이번 저장부터 값이 채워진다(기존 문서를 미리 손대지는 않는다).
    _areaCtrl.text = PlaceArea.textOf(d);
    _isActive = d['isActive'] as bool? ?? true;

    // `themeTags`·`eventSubtype`·옛 `category`는 읽지 않는다 — 이 폼에
    // 그 입력이 없어졌기 때문이다. 문서의 값은 손대지 않고 그대로 둔다
    // (저장 payload에도 없으므로 수정 저장이 덮어쓰지 않는다).

    // 업종 — 다중('businessTypes')이 정본이고, 단일('businessType')로 저장된
    // 문서는 값 하나짜리 집합으로 읽는다. 필터가 두 형식을 모두 보는 것과
    // 같은 규칙이다. 필드가 아예 없던 기존 문서는 빈 채로 시작한다.
    final types = (d['businessTypes'] as List?)?.cast<String>();
    if (types != null && types.isNotEmpty) {
      _businessTypes.addAll(types.take(_maxBusinessTypes));
    } else {
      final single = d['businessType'] as String?;
      if (single != null && single.isNotEmpty) _businessTypes.add(single);
    }
    _hadBusinessTypes =
        d.containsKey('businessTypes') || d.containsKey('businessType');

    final price = d['priceRange'] as String?;
    if (price != null && price.isNotEmpty) _priceRange = price;
    _hadPriceRange = d.containsKey('priceRange');

    // 대분류 — 필드가 없던 옛 문서는 업종에서 **유추한 값으로 시작**한다.
    // 빈 채로 열면 호스트가 아무것도 안 건드리고 저장했을 때 이미 잘
    // 분류돼 보이던 가게가 미분류로 떨어진다.
    _placeCategory = PlaceTaxonomy.categoryOf(d);
    _subcategories.addAll(
      PlaceTaxonomy.subcategoriesOf(d).take(_maxSubcategories),
    );
    _hadCategory = d.containsKey(PlaceTaxonomy.categoryField);

    _placeAttributes = PlaceAttributes.fromDoc(d);
    _hadAttributes = d.containsKey(PlaceAttributeCatalog.field);

    _existingAddress = d['address'] as String? ?? '';
    // 대표 미디어 — 저장 필드는 예전 그대로(`mainImageUrl` + `videoUrl` 계열)
    // 이고, 공용 픽커가 쓰는 "사진 목록 + 동영상 1개" 모양으로 옮겨 담는다.
    final mainUrl = d['mainImageUrl'] as String?;
    _coverExistingImageUrls = (mainUrl == null || mainUrl.isEmpty)
        ? []
        : [mainUrl];
    _coverExistingVideoUrl = d['videoUrl'] as String?;
    _coverExistingVideoUid = d['videoUid'] as String?;
    _coverExistingVideoThumbnailUrl = d['videoThumbnailUrl'] as String?;
    // 대표 지정 — `coverMediaType`이 없는 옛 문서는 사진이 있으면 사진,
    // 없으면 동영상이 대표였다(getPartyCoverMedia의 레거시 순서와 같다).
    // 그 상태를 그대로 골라 둔 채로 열어야, 수정 저장 한 번에 대표가 바뀌는
    // 일이 없다.
    final coverMediaType = d['coverMediaType'] as String?;
    final coverImageUrl = d['coverImageUrl'] as String?;
    if (coverMediaType == 'video') {
      _coverPick = const PartyCoverPick(isExistingVideo: true);
    } else if (coverMediaType == 'image' && coverImageUrl != null) {
      _coverPick = PartyCoverPick(existingImageUrl: coverImageUrl);
    } else if (_coverExistingImageUrls.isNotEmpty) {
      _coverPick = PartyCoverPick(
        existingImageUrl: _coverExistingImageUrls.first,
      );
    } else if (_coverExistingVideoUrl != null) {
      _coverPick = const PartyCoverPick(isExistingVideo: true);
    }
    _coverBasicCardFocalX =
        (d['basicCardVideoFocalX'] as num?)?.toDouble() ?? 0.5;
    _coverBasicCardFocalY =
        (d['basicCardVideoFocalY'] as num?)?.toDouble() ?? 0.5;
    _coverBasicCardScale =
        (d['basicCardVideoScale'] as num?)?.toDouble() ?? 1.0;
    // 필드가 **있다는 사실 자체**가 "한 번 정했다"는 뜻이다(장소대여·파티와
    // 같은 판정). 값만 보면 0.5/0.5/1.0이 "확정한 중앙"인지 "미정"인지
    // 구분되지 않는다.
    _coverVideoCropConfirmed = d.containsKey('basicCardVideoFocalX');
    _coverPhotoCrops = photoCropsFromRaw(d['basicCardPhotoCrops']);

    _existingIntroImageUrls.addAll(
      (d['introImageUrls'] as List?)?.cast<String>() ?? const [],
    );
    // 메뉴판 사진 — 없던 문서면 빈 목록이라 섹션이 비어 있는 채로 시작한다.
    for (final u in (d['menuBoardImageUrls'] as List?) ?? const []) {
      if (u is String && u.trim().isNotEmpty) {
        _menuBoardImages.add(_MenuBoardImage.url(u));
      }
    }
    _hadMenuBoard = d.containsKey('menuBoardImageUrls');

    // 진행 기간(`isOngoing`/`startDate`/`endDate`)과 이용 시간
    // (`hasTimeRange`/`startTime`/`endTime`)은 이 폼에서 없앴다. 옛 문서에
    // 남아 있는 값은 **읽지도 쓰지도 않는다** — 손대지 않고 그대로 둔다
    // (상세 화면의 호환 읽기는 살아 있어 예전처럼 보인다).

    // 운영시간 — 통합 등록이 저장한 'openTime'/'closeTime'(HH:mm)을 그대로 복원.
    // 24시간 운영으로 저장된 문서는 '00:00'~'24:00'이라 파싱값을 쓰지 않는다.
    _placeIsOpen24Hours = d['isOpen24Hours'] as bool? ?? false;
    if (!_placeIsOpen24Hours) {
      _placeOpenTime = _parseTime24(d['openTime'] as String?);
      _placeCloseTime = _parseTime24(d['closeTime'] as String?);
    }
    final weekly = d['placeWeeklyHours'] ?? d['weeklyOperatingHours'];
    if (weekly is Map) {
      _placeWeeklyHours = PlaceWeeklyHours.fromMap(
        Map<String, dynamic>.from(weekly),
      );
    }
    if (d['visitReservation'] is Map) {
      _visitReservation = PlaceVisitReservationConfig.fromMap(
        Map<String, dynamic>.from(d['visitReservation'] as Map),
      );
    }
    _inquiryEnabled = ListingInquiry.isEnabled(d);
    _inquiryGuideCtrl.text = ListingInquiry.guideOf(d);
    if (d['petPolicy'] is Map) {
      _petPolicy = PetPolicy.fromMap(
        Map<String, dynamic>.from(d['petPolicy'] as Map),
      );
    }
    if (d['facilityOptions'] is Map) {
      _facilityOptions = PlaceFacilityOptions.fromMap(
        Map<String, dynamic>.from(d['facilityOptions'] as Map),
      );
    }

    // 문서에 원래 있던 필드인지 — 없던 문서에 값을 새로 만들지 않기 위한 기준.
    _hadHours =
        d.containsKey('isOpen24Hours') ||
        d.containsKey('openTime') ||
        d.containsKey('placeWeeklyHours') ||
        d.containsKey('weeklyOperatingHours');
    _hadVisitReservation = d['visitReservation'] is Map;
    _hadPetPolicy = d['petPolicy'] is Map;
    _hadFacilityOptions = d['facilityOptions'] is Map;
    _customAmenities = CustomAmenities.of(d);
    _hadCustomAmenities = d[CustomAmenities.field] is List;
    _customPlayItems = CustomPlayItems.of(d);
    _hadCustomPlayItems = d[CustomPlayItems.field] is List;
    _hadContact = d.containsKey('contactPhone');
  }

  /// 이미 등록된 상품·프로모션을 불러온다 — 수정은 임시저장이 아니라 실제
  /// 문서에서 시작하므로, 여기서 채운 목록이 곧 편집 대상이다.
  Future<void> _loadProducts() async {
    final placeId = widget.eventId!;
    final loaded = await PlaceProductService.listForPlace(placeId);
    final promos = await PlacePromotionService.listForPlace(placeId);
    final menus = await PlaceMenuService.listForPlace(placeId);
    if (!mounted) return;
    setState(() {
      _products
        ..clear()
        ..addAll(loaded);
      _promotions
        ..clear()
        ..addAll(promos);
      // 수정 화면에서 기존 메뉴가 그대로 채워지는 지점 — 여기서 담은 목록이
      // 곧 편집 대상이고, 저장할 때 이 목록에 맞춰 문서가 동기화된다.
      _menus
        ..clear()
        ..addAll(menus);
      // 개별 메뉴를 다 읽은 지금에야 "이 매장이 어느 방식으로 등록했는지"를
      // 알 수 있다(문서만 읽은 시점에는 메뉴 목록이 비어 있어 늘 메뉴판
      // 방식으로 보였다).
      _syncMenuModeFromData();
      _productsLoaded = true;
    });
  }

  TimeOfDay? _parseTime24(String? s) {
    if (s == null || !s.contains(':')) return null;
    final p = s.split(':');
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  // ── 기본 정보 ─────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  /// "파티츄 전용 혜택" — '파티츄 보고 왔어요!' 손님에게 줄 혜택(선택 입력).
  final _partychuPerkCtrl = TextEditingController();
  bool _isActive = true;

  // ── 업종 / 가격대 ────────────────────────────────────────────────
  // 값 문자열은 [ListingConstants]에만 있고 이 화면도 상세검색 시트도 그것을
  // 그대로 읽는다 — 어느 한쪽에서 문구를 고쳐 매칭이 깨지는 일이 없다.

  /// 업종(다중, 최대 [_maxBusinessTypes]개) — Firestore `businessTypes`.
  ///
  /// 대분류([_placeCategory])가 생긴 뒤에도 **남겨 둔다** — 이미 등록된
  /// 문서가 이 값으로 대분류를 유추받고(PlaceTaxonomy.categoryOf), 예전
  /// 상세검색의 업종 조건도 그대로 걸리기 때문이다.
  final Set<String> _businessTypes = {};
  static const int _maxBusinessTypes = 3;

  // ── 대분류 / 소분류 / 세부 속성 ──────────────────────────────────
  //
  // 대분류가 폼의 첫 갈림길이다 — 고른 대분류에 필요한 항목만 아래에
  // 펼쳐진다(PlaceAttributesSection). 하위호환 규칙은 업종·가격대와
  // 완전히 같다: 원래 없던 필드는 **실제로 고른 경우에만** 새로 생긴다.

  /// 대분류(하나) — Firestore `placeCategory`.
  String? _placeCategory;

  /// 소분류(다중, 최대 [_maxSubcategories]개) — Firestore `placeSubcategories`.
  final Set<String> _subcategories = {};
  static const int _maxSubcategories = 3;

  /// 세부 속성 — Firestore `placeAttributes` + `placeAttributeDetails`.
  PlaceAttributes _placeAttributes = PlaceAttributes.empty();

  bool _hadCategory = false;
  bool _hadAttributes = false;
  bool _categoryTouched = false;
  bool _attributesTouched = false;

  /// 가격대(단일) — Firestore `priceRange`. 안 고르면 null이라 저장하지 않는다.
  String? _priceRange;

  /// 원래 문서에 이 필드들이 있었는지 — 없던 문서에 빈 값을 새로 만들지 않기
  /// 위한 기준(운영시간·반려동물과 같은 방침).
  bool _hadBusinessTypes = false;
  bool _hadPriceRange = false;

  // 상품·이용권 판매 — 네 등록 화면이 공유하는 공통 섹션이 이 목록을 고친다.
  final List<PlaceProduct> _products = [];

  // 매장 이벤트·프로모션 — 결제가 없는 홍보만 담는 별도 목록.
  final List<PlacePromotion> _promotions = [];

  // 메뉴 — 앱에서 파는 상품이 아니라 매장에서 시켜 먹는 것. 상품·프로모션과
  // 같은 방식(별도 컬렉션 + 저장 시 sync)으로 다룬다.
  final List<PlaceMenu> _menus = [];

  // 전체 메뉴판 사진 — 개별 메뉴와 달리 몇 장뿐이고 매장 자체에 딸린 값이라
  // 소개 이미지와 똑같이 events 문서에 URL 배열로 둔다.
  //
  // 이미 올라간 사진과 방금 고른 사진을 **한 목록**에 섞어 둔다. 예전처럼
  // 둘로 나눠 두면 만들 수 있는 순서가 "기존 사진 전부 → 새 사진 전부"
  // 하나뿐이라, 방금 고른 메뉴판을 맨 앞으로 옮길 방법이 없다. 손님이 보는
  // 순서가 곧 이 목록의 순서다.
  final List<_MenuBoardImage> _menuBoardImages = [];
  static const int _maxMenuBoardImages = 6;

  /// 메뉴 등록 방식 — 개별 메뉴를 한 줄씩 넣을지, 메뉴판 사진만 올릴지.
  ///
  /// **저장하지 않는다.** 화면에서 무엇을 입력할지 고르는 스위치일 뿐이고,
  /// 데이터는 두 갈래(placeMenus 컬렉션 / menuBoardImageUrls 필드)로 이미
  /// 나뉘어 있다. 방식을 저장하면 "필드에는 사진이 있는데 방식은 개별"처럼
  /// 서로 어긋나는 상태가 생기고, 그때 무엇을 보여줄지 또 정해야 한다.
  /// 그래서 들어올 때 **데이터를 보고 판정한다**([_syncMenuModeFromData]).
  bool _menuBoardMode = false;

  /// 지금 등록된 메뉴판 사진 장수(이미 올라간 것 + 방금 고른 것).
  int get _menuBoardCount => _menuBoardImages.length;

  /// 데이터를 보고 등록 방식을 정한다 — 메뉴판 사진만 있고 개별 메뉴가
  /// 하나도 없으면 사장님이 고른 방식은 '전체 메뉴판'이었다는 뜻이다.
  /// 둘 다 있거나 둘 다 없으면 기본값(개별 메뉴)으로 연다.
  void _syncMenuModeFromData() {
    _menuBoardMode = _menuBoardImages.isNotEmpty && _menus.isEmpty;
  }

  /// 원래 문서에 메뉴판 필드가 있었는지 — 다른 선택 필드(운영시간·반려동물)와
  /// 같은 방침으로, 없던 문서에 빈 배열을 새로 만들지 않기 위한 기준이다.
  bool _hadMenuBoard = false;

  /// 상품 목록을 다 읽었는지 — 다 읽기 전에 섹션을 그리면 빈 목록으로 보였다가
  /// 저장 시 기존 상품이 지워진 것처럼 보인다. 등록 모드는 처음부터 true다.
  bool _productsLoaded = false;

  // ── 매장 주소 (검색 기반) ─────────────────────────────────────────
  AddressResult? _selectedAddress;

  /// 수정 모드에서 아직 주소를 다시 고르지 않았을 때 보여줄 기존 주소 문자열.
  String _existingAddress = '';
  final _detailAddressCtrl = TextEditingController();

  // ── 대표 미디어(사진 1장 + 동영상 1개) ───────────────────────────
  //
  // 파티·장소대여와 **같은 공용 픽커**([PartyMediaPickerScreen])를 쓴다.
  // 예전에는 대표 이미지 피커와 [SingleVideoPicker]가 따로 있어서
  //  · 사진과 동영상 중 **무엇을 대표로 쓸지 고를 수 없었고**,
  //  · 기본 카드 노출 위치를 정하는 단계가 아예 없었다.
  // 그 결과 동영상을 올려도 카드에서는 사진이 무조건 이겼다(대표 계약을
  // 쓰지 않아 getPartyCoverMedia가 레거시 분기로 내려갔기 때문).
  //
  // 사진은 **1장**이다 — 저장 필드가 예전 그대로 `mainImageUrl` 하나이기
  // 때문이다. 소개 이미지·메뉴판 사진은 이 픽커와 무관하게 예전 구조를
  // 그대로 쓴다(통합하지 않는다).
  static const int _coverMaxImages = 1;

  /// 이미 올라가 있는 대표 사진(0개 또는 1개) — `mainImageUrl`.
  List<String> _coverExistingImageUrls = [];
  String? _coverExistingVideoUrl;
  String? _coverExistingVideoUid;
  String? _coverExistingVideoThumbnailUrl;
  List<XFile> _coverNewFiles = [];
  PartyCoverPick? _coverPick;
  double _coverBasicCardFocalX = 0.5;
  double _coverBasicCardFocalY = 0.5;
  double _coverBasicCardScale = 1.0;
  Map<String, Map<String, double>> _coverPhotoCrops = {};
  bool _coverVideoCropConfirmed = false;

  bool get _coverHasVideo =>
      _coverExistingVideoUrl != null ||
      _coverNewFiles.any(MediaUploadService.isVideoFile);

  int get _coverPhotoCount =>
      _coverExistingImageUrls.length +
      _coverNewFiles.where((f) => !MediaUploadService.isVideoFile(f)).length;

  // ── 소개 이미지 ──────────────────────────────────────────────────
  // 등록 모드에서는 existing 쪽이 항상 비어 있다 — 수정 모델이 등록 모델을
  // 그대로 포함하므로 한 벌만 두고 두 모드가 함께 쓴다.
  final List<String> _existingIntroImageUrls = [];
  final List<XFile> _newIntroImages = [];
  final _picker = ImagePicker();

  // 플레이스의 시간 정본은 아래 **운영시간 하나**다. 예전에는 여기에
  // '진행 기간(상시 진행)'과 '이용 시간(시간 지정)'이 더 있었지만, 둘 다
  // 이벤트(`placePromotions`) 모양을 물려받은 잔재였다 — 검색·지도·방문
  // 예약 어디에도 쓰이지 않고 상세 화면 표시에만 남아 있었다. 기간·시간이
  // 걸린 내용은 이벤트에서 관리한다.

  // ── 운영시간 / 반려동물 / 좌석·공간 / 연락처 ─────────────────────
  bool _placeIsOpen24Hours = false;
  TimeOfDay? _placeOpenTime;
  TimeOfDay? _placeCloseTime;
  // 가변 객체라 PlaceHoursSection이 그 자리에서 고쳐 쓴다. 불러오기(프리필·
  // 임시저장 복원) 때만 통째로 갈아끼운다.
  PlaceWeeklyHours _placeWeeklyHours = PlaceWeeklyHours.defaultPreset();
  PetPolicy _petPolicy = PetPolicy.empty();
  PlaceFacilityOptions _facilityOptions = PlaceFacilityOptions.empty();

  /// 기타 편의 서비스(호스트 자유 입력). 정식 편의 서비스와 **다른 축**이라
  /// facilityOptions에 섞지 않고 공용 필드에 따로 담는다([CustomAmenities]).
  List<String> _customAmenities = const [];

  /// 수정 진입 시 문서에 이 필드가 있었는지 — 항목을 전부 지웠을 때도 문서에
  /// 남지 않도록 덮어쓸지 판단한다(facilityOptions와 같은 방침).
  bool _hadCustomAmenities = false;
  bool _customAmenitiesTouched = false;

  /// 기타 놀거리(호스트 자유 입력) — 놀거리 프리셋의 '기타'에 딸린 값이다.
  /// 프리셋 배열(`placeAttributes.playItems`)에 섞지 않고 별도 필드에 담는다
  /// ([CustomPlayItems]).
  ///
  /// '기타'를 껐다고 이 목록을 비우지 않는다 — 화면에서 접힐 뿐이고, 문서에
  /// 살아 있는 값인지는 저장 시점에 정해진다. 임시저장에는 '기타'와 무관하게
  /// 담기므로 실수로 한 번 끈 것이 열 개를 날리지 않는다.
  List<String> _customPlayItems = const [];

  bool _hadCustomPlayItems = false;
  bool _customPlayItemsTouched = false;
  final _contactCtrl = TextEditingController();

  /// 공간 평수 — 등록·수정 모두 필수다([PlaceArea]). 이 필드가 없던 옛 문서는
  /// 빈 칸으로 열리므로, 수정하러 들어온 호스트가 이번에 채우게 된다.
  final _areaCtrl = TextEditingController();
  final _areaFocus = FocusNode();

  /// 평수 입력칸으로 스크롤할 때 쓰는 앵커.
  final GlobalKey _areaKey = GlobalKey();

  // ── 필수항목 안내가 가리키는 나머지 자리들 ───────────────────────
  //
  // 문구·이동 위치·펼치기·포커스를 한 표에 모아 두는 공용 구조를 다른 등록
  // 화면과 똑같이 쓴다([RegisterFieldCheck]) — 화면마다 따로 스크롤 로직을
  // 만들지 않기 위해서다.
  final GlobalKey _nameKey = GlobalKey();
  final FocusNode _nameFocus = FocusNode();

  /// 본문 스크롤 — 검증 항목에 그대로 넘겨, 어느 줄을 눌러도 같은 목록이
  /// 움직이게 한다([RegisterFieldCheck.scrollController]).
  final ScrollController _scrollCtrl = ScrollController();

  // 상품의 취소·환불 규정은 **상품 카드 안**에 있고, 카드는 한 번에 하나만
  // 펼쳐진다. 그래서 "어느 상품을 펼칠지"(신호)와 "그 안 어느 입력칸으로
  // 갈지"(앵커)를 화면이 들고 있다가 [PlaceProductSection]에 넘긴다.
  final ProductRefundReveal _revealProductRefund = ProductRefundReveal();
  final GlobalKey _productRefundKey = GlobalKey();

  /// 그 규정 입력칸에 놓을 커서 — 도착한 뒤 바로 적을 수 있게 한다.
  final FocusNode _productRefundFocus = FocusNode();

  /// 등록 버튼을 눌렀을 때 비어 있던 필수 항목 — 화면 맨 위 배너에 목록으로
  /// 남는다. 스낵바는 사라지고, 각 칸의 빨간 문구는 화면 밖이면 안 보인다.
  List<RegisterFieldCheck> _missingFields = const [];

  /// 이 화면에는 [Form]이 없어서, 손대지 않은 입력칸의 빨간 문구를 저장
  /// 버튼에서 직접 띄워야 한다.
  final GlobalKey<FormFieldState<String>> _areaFieldKey = GlobalKey();

  /// 무료 방문 예약 설정 — 문서의 visitReservation 맵 하나로 저장된다.
  /// (아래 "상품·이용권"의 유료 좌석권과는 별개 기능이다.)
  PlaceVisitReservationConfig _visitReservation =
      PlaceVisitReservationConfig.disabled;
  bool _visitReservationTouched = false;

  /// 게스트 문의 받기 — 파티·장소대여와 **같은 필드**(inquiryEnabled) 하나다.
  /// 등록 기본값은 ON([ListingInquiry.defaultEnabled]).
  bool _inquiryEnabled = ListingInquiry.defaultEnabled;

  /// 문의 전 안내문 — 문의 받기가 ON일 때만 입력란이 보인다.
  final _inquiryGuideCtrl = TextEditingController();

  /// 수정 모드에서 "문서에 원래 있던 필드인지" — 없던 문서에 빈 값/기본값을
  /// 새로 만들지 않기 위한 기준. 등록 모드에서는 항상 저장하므로 쓰이지 않는다.
  bool _hadHours = false;
  bool _hadVisitReservation = false;
  bool _hadPetPolicy = false;
  bool _hadFacilityOptions = false;
  bool _hadContact = false;

  /// 사용자가 해당 섹션을 실제로 건드렸는지 — 건드린 순간부터 저장 대상이 된다.
  bool _hoursTouched = false;
  bool _petPolicyTouched = false;
  bool _facilityTouched = false;

  bool _showNameError = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    disposeDraft();
    _scrollCtrl.dispose();
    _revealProductRefund.dispose();
    _productRefundFocus.dispose();
    _nameFocus.dispose();
    // 이 화면을 떠나면 강조도 함께 끈다 — 타이머가 화면보다 오래 남지 않게.
    RegisterValidation.clearHighlight();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _partychuPerkCtrl.dispose();
    _inquiryGuideCtrl.dispose();
    _detailAddressCtrl.dispose();
    _contactCtrl.dispose();
    _areaCtrl.dispose();
    _areaFocus.dispose();
    super.dispose();
  }

  // ── 이미지 선택 ──────────────────────────────────────────────────
  // 대표 사진은 여기가 아니라 공용 픽커([_openCoverMediaPicker])가 맡는다 —
  // 대표 지정·카드 프레임 조정이 함께 필요하기 때문이다. 아래 소개 이미지와
  // 메뉴판 사진은 카드에 뜨지 않아 그 단계가 없고, 예전 방식 그대로다.

  Future<void> _pickIntro() async {
    final remain =
        6 - (_existingIntroImageUrls.length + _newIntroImages.length);
    if (remain <= 0) return;
    final picked = await _picker.pickMultiImage(limit: remain);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (_existingIntroImageUrls.length + _newIntroImages.length < 6) {
          _newIntroImages.add(f);
        }
      }
    });
  }

  /// 메뉴판 사진 고르기 — 소개 이미지(_pickIntro)와 완전히 같은 규칙
  /// (남은 장수만큼만 받고, 그 이상은 무시한다).
  Future<void> _pickMenuBoard() async {
    final remain = _maxMenuBoardImages - _menuBoardCount;
    if (remain <= 0) return;
    final picked = await _picker.pickMultiImage(limit: remain);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (_menuBoardCount >= _maxMenuBoardImages) break;
        _menuBoardImages.add(_MenuBoardImage.file(f));
      }
    });
  }

  // ── 제출 ─────────────────────────────────────────────────────────
  //
  // 검증은 두 모드가 완전히 같다. 갈리는 것은 "새 문서를 만드는가(add) 기존
  // 문서를 갱신하는가(update)"와, 그에 딸린 후속 처리뿐이다.
  Future<void> _submit() async {
    if (UserSession.userId.isEmpty) {
      _msg('로그인이 필요합니다.');
      return;
    }
    // 등록 개수 — 플레이스도 10개다([RegistrationLimits]). 진입 관문이 이미
    // 보지만 그 관문은 폼을 **열 때의 유형**으로 판정하므로, 폼 안에서 유형을
    // 바꿔 들어온 길까지 여기서 다시 본다. 수정은 개수를 늘리지 않으므로
    // 새 등록일 때만 본다. 업로드 전에 막아야 지워지지 않는 사진이 남지 않는다.
    if (!_isEdit) {
      if (!await RegistrationLimits.ensure(
        context,
        RegistrationKind.placeListing,
      )) {
        return;
      }
      if (!mounted) return;
    }
    // ── 필수값 검증 ────────────────────────────────────────────────
    //
    // 조건·문구는 예전과 한 글자도 다르지 않다. 달라진 것은 "어떻게 알리는가"
    // 뿐이다 — 첫 번째 문제에서 멈춰 스낵바만 띄우던 것을, 다른 등록 화면과
    // **같은 공용 표**([RegisterFieldCheck])로 모아 상단 배너에 전부 남기고
    // 그 줄을 누르면 해당 입력칸으로 데려간다.
    final nameMissing = _nameCtrl.text.trim().isEmpty;
    // 공간 평수 — 등록·수정 모두 필수다. 이 필드가 없던 옛 문서를 수정하러
    // 들어온 경우에도 여기서 걸리므로, 다음 저장부터 값이 채워진다.
    final areaError = PlaceArea.validate(_areaCtrl.text);
    // 상품을 등록했다면 취소·환불 규정은 필수다 — 규칙은 공용
    // [PlaceProductRefundPolicyRule] 하나를 쓴다(티어형 환불 규정과 별개).
    // 규정 없이 저장돼 있던 옛 상품도 화면 진입은 그대로 되고 여기서만 막힌다.
    final productRefundIndex = PlaceProductRefundPolicyRule.firstMissingIndex(
      _products,
    );

    setState(() => _showNameError = nameMissing);
    if (areaError != null) {
      // 아직 손대지 않은 입력칸에도 빨간 문구를 띄운다 — 스낵바만으로는
      // 어느 칸이 문제인지 화면에서 찾기 어렵다.
      _areaFieldKey.currentState?.validate();
    }

    // 순서는 **화면에 보이는 순서**여야 한다 — 제출 시 자동 이동은 이 목록의
    // 첫 누락 항목을 대상으로 한다.
    final checks = [
      RegisterFieldCheck(
        missing: nameMissing,
        message: '플레이스 제목을 입력해주세요.',
        anchorKey: _nameKey,
        focusNode: _nameFocus,
        scrollController: _scrollCtrl,
      ),
      RegisterFieldCheck(
        missing: areaError != null,
        message: areaError ?? PlaceArea.requiredMessage,
        anchorKey: _areaKey,
        focusNode: _areaFocus,
        scrollController: _scrollCtrl,
      ),
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
        scrollController: _scrollCtrl,
      ),
    ];
    setState(() => _missingFields = RegisterValidation.missingFields(checks));
    if (!RegisterValidation.check(context, checks) || !mounted) return;

    final areaPyeong = PlaceArea.parse(_areaCtrl.text)!;
    setState(() {
      _missingFields = const [];
      _isSubmitting = true;
    });
    try {
      // 대표 미디어 — 파티·장소대여와 **같은 공용 업로더**를 쓴다. 올리기
      // 전에 경로·존재·크기를 확인하고, 실패하면 어떤 파일이 왜 실패했는지를
      // 담아 던진다(예전에는 여기서 나는 실패의 원인이 통째로 사라졌다).
      final coverUpload = await MediaUploadService.uploadNewMedia(
        media: _coverNewFiles,
        logTag: 'place-cover',
      );
      final coverImageUrls = [
        ..._coverExistingImageUrls,
        ...coverUpload.imageUrls,
      ];
      // 저장 필드는 예전 그대로 — 사진은 `mainImageUrl` 한 장이다.
      final String mainUrl = coverImageUrls.isEmpty ? '' : coverImageUrls.first;
      final videoUidFinal = coverUpload.videoUid ?? _coverExistingVideoUid;
      final videoUrlFinal = coverUpload.videoUrl ?? _coverExistingVideoUrl;
      final videoThumbFinal =
          coverUpload.videoThumbnailUrl ?? _coverExistingVideoThumbnailUrl;

      // 아래 세 묶음(소개 이미지 · 메뉴판 사진 · 개별 메뉴 사진)도 **같은 공용
      // 업로더**로 올린다. 카드에 뜨지 않아 대표·크롭 개념은 없지만, 올리기
      // 전 검사(경로/존재/0바이트)와 실패 원인 분류는 똑같이 필요하다 —
      // 임시저장을 복원한 뒤 파일이 사라지는 상황은 여기서도 똑같이 생긴다.
      //
      // 순서는 전부 **화면에 보이던 그대로** 유지한다: 새 파일만 순서대로
      // 올린 뒤, 목록을 다시 훑으며 올라온 URL을 차례로 끼워 넣는다.

      // 소개 이미지 — 남겨둔 기존 URL 뒤에 새로 고른 것을 붙인다.
      final introUpload = await MediaUploadService.uploadNewMedia(
        media: _newIntroImages,
        logTag: 'place-intro',
      );
      final introUrls = [..._existingIntroImageUrls, ...introUpload.imageUrls];

      // 전체 메뉴판 사진 — 이미 올라간 사진 사이에 새 사진이 끼어 있을 수
      // 있으므로, 목록을 순서대로 훑으며 새 파일 자리에만 URL을 채운다.
      final menuBoardNewFiles = [
        for (final m in _menuBoardImages)
          if ((m.url == null || m.url!.isEmpty) && m.file != null) m.file!,
      ];
      final menuBoardUpload = await MediaUploadService.uploadNewMedia(
        media: menuBoardNewFiles,
        logTag: 'place-menuboard',
      );
      final menuBoardUrls = <String>[];
      var menuBoardOrdinal = 0;
      for (final m in _menuBoardImages) {
        final uploaded = m.url;
        if (uploaded != null && uploaded.isNotEmpty) {
          menuBoardUrls.add(uploaded);
          continue;
        }
        if (m.file == null) continue;
        if (menuBoardOrdinal < menuBoardUpload.imageUrls.length) {
          menuBoardUrls.add(menuBoardUpload.imageUrls[menuBoardOrdinal]);
        }
        menuBoardOrdinal++;
      }

      // 개별 메뉴 사진 — 아직 안 올린 로컬 경로만 올리고 URL로 바꾼다.
      // (이미 올라간 메뉴는 건드리지 않으므로 재업로드가 없다.)
      final menuLocalIndexes = [
        for (var i = 0; i < _menus.length; i++)
          if ((_menus[i].localImagePath ?? '').isNotEmpty) i,
      ];
      final menuUpload = await MediaUploadService.uploadNewMedia(
        media: [
          for (final i in menuLocalIndexes)
            LocalMedia.resolve(_menus[i].localImagePath!),
        ],
        logTag: 'place-menu',
      );
      for (var n = 0; n < menuLocalIndexes.length; n++) {
        if (n >= menuUpload.imageUrls.length) break;
        final i = menuLocalIndexes[n];
        _menus[i] = _menus[i].copyWith(
          imageUrl: menuUpload.imageUrls[n],
          clearLocalImage: true,
        );
      }

      // 동영상 — 위 공용 업로더가 이미 함께 올렸다. 사용자가 지웠으면 값이
      // null로 남아 수정 모드에서 필드를 삭제한다(예전과 같은 규칙).
      final String? videoUid = videoUidFinal;
      final String? videoUrl = videoUrlFinal;
      final String? videoThumbnailUrl = videoThumbFinal;

      // ── 대표 미디어 계약 ─────────────────────────────────────────
      // 목록 카드·상세가 읽는 함수(getPartyCoverMedia)와 **정확히 같은 키**로
      // 저장한다. 예전에는 이 필드를 하나도 쓰지 않아서 그 함수가 레거시
      // 분기로 내려갔고, 거기서는 "사진이 하나도 없을 때만" 동영상이 대표가
      // 될 수 있었다 — 대표 이미지가 있으면 동영상은 카드에 절대 못 나왔다.
      //
      // 고르지 않았으면 파티·장소대여와 같은 기본값(사진 우선 → 없으면
      // 동영상)을 쓴다.
      String coverMediaType = 'image';
      String? coverImageUrl;
      String? coverVideoUid;
      String? coverVideoUrl;
      String? coverThumbnailUrl;
      if (_coverPick?.isExistingVideo == true ||
          _coverPick?.isNewVideo == true) {
        coverMediaType = 'video';
        coverVideoUid = videoUid;
        coverVideoUrl = videoUrl;
        coverThumbnailUrl = videoThumbnailUrl;
      } else if (_coverPick?.existingImageUrl != null) {
        coverImageUrl = _coverPick!.existingImageUrl;
        coverThumbnailUrl = coverImageUrl;
      } else if (_coverPick?.newImageOrdinal != null) {
        final ordinal = _coverPick!.newImageOrdinal!;
        coverImageUrl = ordinal < coverUpload.imageUrls.length
            ? coverUpload.imageUrls[ordinal]
            : (coverImageUrls.isNotEmpty ? coverImageUrls.first : null);
        coverThumbnailUrl = coverImageUrl;
      } else if (coverImageUrls.isNotEmpty) {
        coverImageUrl = coverImageUrls.first;
        coverThumbnailUrl = coverImageUrl;
      } else if (videoUrl != null) {
        coverMediaType = 'video';
        coverVideoUid = videoUid;
        coverVideoUrl = videoUrl;
        coverThumbnailUrl = videoThumbnailUrl;
      }
      final coverPhotoCrops = MediaUploadService.resolvePhotoCropKeys(
        crops: _coverPhotoCrops,
        existingImageUrls: _coverExistingImageUrls,
        newMedia: _coverNewFiles,
        uploadedImageUrls: coverUpload.imageUrls,
      );

      // ── 두 모드가 공유하는 필드 ────────────────────────────────────
      final doc = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        kPartychuPerkField: _partychuPerkCtrl.text.trim(),
        // `themeTags`·`eventSubtype`은 이 폼이 쓰지 않는다.
        //
        // 신규 등록: 이벤트를 함께 넣었으면 저장 직후
        //   [PlacePromotionService.syncForPlace]가 '이벤트'를 켜 준다.
        // 수정: **필드를 아예 넘기지 않는다.** 빈 배열을 쓰면 이벤트 등록이
        //   자동으로 켜 둔 '이벤트'와 옛 문서의 '핫플'이 저장 한 번에
        //   사라진다 — 기존 데이터는 손대지 않는다는 원칙 그대로다.
        // 공간 평수 — **숫자 그대로** 저장한다('20평' 같은 문자열이 아니다).
        // 등록·수정 둘 다 이 줄을 타므로 필드가 없던 옛 문서도 이번 저장에서
        // 채워진다([PlaceArea]).
        PlaceArea.field: areaPyeong,
        'mainImageUrl': mainUrl,
        'introImageUrls': introUrls,
        // ── 대표 미디어 계약 — 카드·상세가 읽는 키 그대로 ──────────
        // 등록·수정 둘 다 이 줄을 타므로, 필드가 없던 옛 문서도 이번
        // 저장에서 채워진다. 값이 없던 문서는 예전처럼 레거시 분기로
        // 읽히므로 저장하기 전까지 보이는 모습은 달라지지 않는다.
        'coverMediaType': coverMediaType,
        'coverImageUrl': coverImageUrl,
        'coverVideoUid': coverVideoUid,
        'coverVideoUrl': coverVideoUrl,
        'coverThumbnailUrl': coverThumbnailUrl,
        'basicCardVideoFocalX': _coverBasicCardFocalX,
        'basicCardVideoFocalY': _coverBasicCardFocalY,
        'basicCardVideoScale': _coverBasicCardScale,
        'basicCardPhotoCrops': coverPhotoCrops,
        'detailAddress': _detailAddressCtrl.text.trim(),
        // `isOngoing`/`startDate`/`endDate`/`hasTimeRange`/`startTime`/
        // `endTime`은 **더 이상 쓰지 않는다**(입력 자체가 없어졌다). 이미
        // 그 필드를 가진 문서에서도 지우지 않는다 — 수정 저장이 남은 값을
        // 건드리지 않고 지나가므로, 상세 화면의 호환 읽기가 예전 그대로
        // 동작한다.
        'isActive': _isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // ── 숨긴 시각(hiddenAt) ──────────────────────────────────────────
      // **자동 삭제(14일)의 기준점**이다(functions/index.js의
      // deleteExpiredEvents). 장소대여가 쓰던 규칙을 그대로 가져왔다
      // (place_register_screen.dart):
      //   · 숨김으로 저장 → 시각을 적는다
      //   · 노출로 저장   → 지운다(그 순간 자동 삭제 대상에서 빠진다)
      //
      // ⚠️ updatedAt으로 대신 셀 수 없다 — 마지막 수정이 숨김과 아무 상관
      //    없는 시각일 수 있어서, 방금 숨긴 플레이스가 곧바로 삭제되거나
      //    반대로 영영 남는다.
      //
      // 숨김을 유지한 채 내용만 고친 저장은 시각을 **다시 적는다**(기한이
      // 그만큼 밀린다). 이 화면은 저장 전 상태를 들고 있지 않아 "이미
      // 감춰져 있었는지"를 알 수 없는데, 기한이 밀리는 쪽이 남의 등록물을
      // 일찍 지우는 것보다 안전하다.
      //
      // FieldValue.delete()는 **수정에서만** 쓴다 — 새 문서를 만드는
      // add()에 넣으면 그 자리에서 예외가 난다.
      if (!_isActive) {
        doc['hiddenAt'] = FieldValue.serverTimestamp();
      } else if (_isEdit) {
        doc['hiddenAt'] = FieldValue.delete();
      }

      // 동영상 — 등록은 "있을 때만 넣고", 수정은 "지웠으면 필드를 지운다".
      if (_isEdit) {
        doc['videoProvider'] = videoUrl != null
            ? 'cloudflare'
            : FieldValue.delete();
        doc['videoUid'] = videoUid ?? FieldValue.delete();
        doc['videoUrl'] = videoUrl ?? FieldValue.delete();
        doc['videoThumbnailUrl'] = videoThumbnailUrl ?? FieldValue.delete();
        // 옛 단일 `category` 필드도 지우지 않는다. 예전에는 이 폼이 그 값을
        // `themeTags`로 옮겨 적은 뒤 지웠지만, 이제 태그를 쓰지 않으므로
        // 여기서 지우면 옮겨 갈 곳 없이 사라진다 — 읽는 쪽
        // ([ListingConstants.themeTagsOf])이 `themeTags`가 비면 `category`를
        // 태그 하나로 읽어 주므로, 그대로 두는 것이 맞다.
      } else {
        if (videoUrl != null) doc['videoProvider'] = 'cloudflare';
        if (videoUid != null) doc['videoUid'] = videoUid;
        if (videoUrl != null) doc['videoUrl'] = videoUrl;
        if (videoThumbnailUrl != null) {
          doc['videoThumbnailUrl'] = videoThumbnailUrl;
        }
      }

      // 주소 — 등록은 항상 쓰고, 수정은 사용자가 다시 고른 경우에만 덮어쓴다
      // (안 골랐으면 기존 주소를 그대로 둔다).
      if (!_isEdit || _selectedAddress != null) {
        final detail = _detailAddressCtrl.text.trim();
        doc['address'] = _selectedAddress?.address ?? '';
        doc['roadAddress'] = _selectedAddress?.roadAddress ?? '';
        doc['jibunAddress'] = _selectedAddress?.jibunAddress ?? '';
        doc['latitude'] = _selectedAddress?.latitude ?? 0.0;
        doc['longitude'] = _selectedAddress?.longitude ?? 0.0;
        doc['location'] = _selectedAddress == null
            ? ''
            : '${_selectedAddress!.address}'
                  '${detail.isNotEmpty ? ' $detail' : ''}';
      }

      // ── 운영시간 / 연락처 / 반려동물 / 좌석·공간 ────────────────────
      // 등록은 항상 저장한다. 수정은 "원래 문서에 있었거나 이번에 직접 건드린"
      // 경우에만 쓴다 — 이 필드가 아예 없던 문서에 빈 값/기본값이 새로 생기지
      // 않게 하기 위한 장치다.
      if (!_isEdit || _hadContact || _contactCtrl.text.trim().isNotEmpty) {
        doc['contactPhone'] = _contactCtrl.text.trim();
      }
      if (!_isEdit || _hadHours || _hoursTouched) {
        doc['isOpen24Hours'] = _placeIsOpen24Hours;
        if (_placeIsOpen24Hours) {
          doc['openTime'] = '00:00';
          doc['closeTime'] = '24:00';
        } else if (_placeOpenTime != null && _placeCloseTime != null) {
          doc['openTime'] = _fmtTime24(_placeOpenTime!);
          doc['closeTime'] = _fmtTime24(_placeCloseTime!);
        }
        doc['placeWeeklyHours'] = _placeWeeklyHours.toMap();
        doc['weeklyOperatingHours'] = _placeWeeklyHours.toMap();
      }
      // 방문 예약 설정 — 예약을 켠 적이 없는 옛 문서에 빈 설정을 새로 만들지
      // 않도록, 등록이거나 실제로 손댄 경우에만 쓴다(운영시간과 같은 규칙).
      if (!_isEdit || _visitReservationTouched || _hadVisitReservation) {
        doc['visitReservation'] = _visitReservation.toMap();
      }
      // 게스트 문의 받기는 **언제나 쓴다.** 다른 설정과 달리 "옛 문서에 없던
      // 필드를 새로 만들지 않는다"는 규칙을 따르지 않는 이유: 값이 없는 문서는
      // 어차피 ON으로 읽히므로(ListingInquiry.defaultEnabled) true를 적어도
      // 뜻이 달라지지 않고, 호스트가 OFF로 바꾼 순간에는 반드시 적혀야 한다.
      doc.addAll(ListingInquiry.toMap(_inquiryEnabled, _inquiryGuideCtrl.text));
      if (!_isEdit) {
        if (!_petPolicy.isUnspecified) doc['petPolicy'] = _petPolicy.toMap();
        if (_facilityOptions.isNotEmpty) {
          doc['facilityOptions'] = _facilityOptions.toMap();
        }
        if (_customAmenities.isNotEmpty) {
          doc[CustomAmenities.field] = CustomAmenities.toStored(
            _customAmenities,
          );
        }
      } else {
        if (_hadPetPolicy || _petPolicyTouched) {
          // "미지정"으로 되돌리면 필드 자체를 지운다.
          doc['petPolicy'] = _petPolicy.isUnspecified
              ? FieldValue.delete()
              : _petPolicy.toMap();
        }
        if (_hadFacilityOptions || _facilityTouched) {
          // update()라서, 항목을 모두 해제했을 때도 문서에 남지 않도록 빈 맵을
          // 그대로 덮어쓴다(조건부로 빼면 예전 선택이 그대로 남는다).
          doc['facilityOptions'] = _facilityOptions.toMap();
        }
        if (_hadCustomAmenities || _customAmenitiesTouched) {
          // 전부 지웠을 때도 빈 배열로 덮어쓴다 — 조건부로 빼면 예전 항목이
          // 문서에 그대로 남아 필터에 계속 걸린다.
          doc[CustomAmenities.field] = CustomAmenities.toStored(
            _customAmenities,
          );
        }
      }

      // 메뉴판 사진 — 없던 문서에 빈 배열을 새로 만들지 않는다(운영시간·
      // 반려동물과 같은 방침). 한 번이라도 올렸으면 그 뒤로는 항상 쓴다.
      if (!_isEdit || _hadMenuBoard || menuBoardUrls.isNotEmpty) {
        doc['menuBoardImageUrls'] = menuBoardUrls;
      }

      // ── 업종 / 가격대 ───────────────────────────────────────────────
      // 하위호환: 이 필드가 없던 기존 문서는 사용자가 **실제로 고른 경우에만**
      // 필드가 새로 생긴다. 안 고르고 저장하면 문서는 예전 그대로다.
      // 한 번 값이 있던 문서에서 선택을 모두 해제하면 그때는 필드를 지운다
      // (빈 값을 남겨 두면 필터가 "업종 미상"과 "업종 없음"을 구분 못 한다).
      if (!_isEdit) {
        if (_businessTypes.isNotEmpty) {
          doc['businessTypes'] = _businessTypes.toList();
        }
        if (_priceRange != null) doc['priceRange'] = _priceRange;
      } else {
        if (_hadBusinessTypes || _businessTypes.isNotEmpty) {
          doc['businessTypes'] = _businessTypes.isEmpty
              ? FieldValue.delete()
              : _businessTypes.toList();
          // 단일 'businessType'으로 저장돼 있던 예전 문서는 다중 필드로
          // 옮겨 적었으므로 옛 필드를 정리한다(둘이 어긋난 채 남지 않게).
          if (_source.containsKey('businessType')) {
            doc['businessType'] = FieldValue.delete();
          }
        }
        if (_hadPriceRange || _priceRange != null) {
          doc['priceRange'] = _priceRange ?? FieldValue.delete();
        }
      }

      // ── 대분류 / 소분류 / 세부 속성 ─────────────────────────────────
      // 업종·가격대와 **똑같은 하위호환 규칙**을 쓴다.
      //   · 등록: 실제로 고른 것만 쓴다(안 고르면 문서에 필드가 안 생긴다).
      //   · 수정: 원래 있었거나 이번에 건드린 경우에만 쓰고, 비우면 필드를
      //          지운다(빈 값이 남으면 '미분류'와 '분류 없음'을 구분 못 한다).
      //
      // 고른 대분류에서 묻지 않는 속성은 저장 직전에 털어낸다 — 클럽으로
      // 등록했다가 카페로 바꾸면 음악 장르가 화면에서 사라지는데, 값만
      // 문서에 남아 필터에 계속 걸리기 때문이다.
      final attrs = pruneAttributesFor(_placeAttributes, _placeCategory);
      final attrMap = attrs.toMap();
      final attrDetails = attrs.detailsToMap();
      if (!_isEdit) {
        if (_placeCategory != null) {
          doc[PlaceTaxonomy.categoryField] = _placeCategory;
          if (_subcategories.isNotEmpty) {
            doc[PlaceTaxonomy.subcategoryField] = _subcategories.toList();
          }
        }
        if (attrMap.isNotEmpty) {
          doc[PlaceAttributeCatalog.field] = attrMap;
          if (attrDetails.isNotEmpty) {
            doc[PlaceAttributeCatalog.detailField] = attrDetails;
          }
        }
      } else {
        if (_hadCategory || _categoryTouched) {
          doc[PlaceTaxonomy.categoryField] =
              _placeCategory ?? FieldValue.delete();
          doc[PlaceTaxonomy.subcategoryField] = _subcategories.isEmpty
              ? FieldValue.delete()
              : _subcategories.toList();
        }
        if (_hadAttributes || _attributesTouched) {
          doc[PlaceAttributeCatalog.field] = attrMap.isEmpty
              ? FieldValue.delete()
              : attrMap;
          doc[PlaceAttributeCatalog.detailField] = attrDetails.isEmpty
              ? FieldValue.delete()
              : attrDetails;
        }
      }

      // ── 기타 놀거리(자유기재) ───────────────────────────────────────
      // 프리셋에서 '기타'를 고른 경우에만 **활성 데이터**다 — 껐다면 입력해
      // 둔 값이 남아 있어도 빈 배열이 들어간다([CustomPlayItems.activeFor]).
      // 기준이 되는 attrs는 위에서 대분류로 한 번 털어낸 것이라, 업종을
      // 바꿔 놀거리 자체가 화면에서 사라진 경우도 함께 꺼진다.
      final activePlayItems = CustomPlayItems.activeFor(
        attrs,
        _customPlayItems,
      );
      if (!_isEdit) {
        if (activePlayItems.isNotEmpty) {
          doc[CustomPlayItems.field] = activePlayItems;
        }
      } else if (_hadCustomPlayItems ||
          _customPlayItemsTouched ||
          _attributesTouched) {
        // 전부 지웠거나 '기타'를 끈 경우에도 빈 배열로 덮어쓴다 — 조건부로
        // 빼면 예전 항목이 문서에 남아 게스트 목록·필터에 계속 걸린다.
        doc[CustomPlayItems.field] = activePlayItems;
      }

      if (_isEdit) {
        await _saveEdit(doc);
      } else {
        await _saveCreate(doc);
      }
    } catch (e, st) {
      // 예외를 통째로 삼키지 않는다 — 예전에는 `catch (_)`가 원인을 버리고
      // "등록 중 오류" 한 줄만 남겨서, 사진이 안 올라간 것인지 문서 저장이
      // 실패한 것인지조차 알 수 없었다. 로그에는 원문과 stack trace를,
      // 사용자에게는 갈래에 맞는 안내를 준다(파일 문제면 그 사진을 빼라고,
      // 인증·네트워크 문제면 다시 시도하라고 — 파티·장소대여와 같은 함수).
      MediaUploadService.logUploadError(
        e,
        st,
        logTag: 'place-cover',
        label: _isEdit ? '❌ 플레이스 수정 실패' : '❌ 플레이스 등록 실패',
      );
      if (mounted) {
        _msg(
          RegisterValidation.failureMessage(e, stage: _isEdit ? '수정' : '등록'),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// 신규 등록 — 새 `events` 문서를 만들고 상품·프로모션을 저장한 뒤,
  /// 기존 파티를 이 플레이스에 연결할 기회를 한 번 준다.
  Future<void> _saveCreate(Map<String, dynamic> doc) async {
    doc['hostId'] = UserSession.userId;
    doc['hostName'] = UserSession.displayName;
    doc['createdAt'] = FieldValue.serverTimestamp();

    final eventRef = await FirebaseFirestore.instance
        .collection('events')
        .add(doc);

    // 상품·이용권 — 플레이스 문서가 생긴 뒤에야 placeId를 알 수 있다.
    await _saveProducts(eventRef.id);

    if (!mounted) return;
    // 최종 등록 완료 — 이 유형의 임시저장은 자동 삭제.
    await deleteCurrentDraft();
    if (!mounted) return;

    // 매장이 있어도 일반 파티부터 먼저 등록한 호스트가 많다 — 등록 직후에
    // "이 장소에서 진행하는 기존 파티"를 골라 한 번에 연결할 기회를 준다.
    // 자동 연결은 하지 않고 호스트가 직접 고른 것만 연결된다.
    // 메인화면으로 돌아가기 전에 물어봐야 한다(popUntil 이후에는 이 화면의
    // Navigator로 더 이상 push할 수 없다).
    // 여기서 뭐가 잘못돼도 플레이스 등록 자체는 이미 끝났다 — 바깥 catch로
    // 흘려보내면 "등록 중 오류" 문구가 잘못 뜨므로 따로 삼킨다.
    try {
      final linkedCount = await promptLinkExistingParties(
        context: context,
        eventId: eventRef.id,
        // createdAt/updatedAt은 서버 센티널이지만, 연결 로직은 장소
        // 필드(이름/주소/좌표 등)만 읽으므로 그대로 넘겨도 안전하다.
        place: {...doc, 'id': eventRef.id},
      );
      if (!mounted) return;
      if (linkedCount > 0) {
        _msg('파티 $linkedCount개를 이 플레이스에 연결했어요.');
      }
    } catch (_) {
      if (!mounted) return;
      _msg('플레이스는 등록됐어요. 파티 연결은 마이페이지에서 이어서 할 수 있어요.');
    }

    // 예약금을 받는 플레이스인데 **입금받을 계좌**가 아직 없으면 지금 등록하도록
    // 이어준다(인증돼 있으면 그냥 지나감). 예약금은 파티츄를 거치지 않고 업주
    // 계좌로 바로 들어가므로, 여기서 물어야 할 것은 정산계좌가 아니라 수취계좌다.
    await promptPayoutAccountAfterRegister(
      context,
      what: '플레이스',
      // 예약금이 0이면 지금까지처럼 무료 방문예약이라 받을 돈이 없다.
      usesBankTransfer: _visitReservation.hasDeposit,
    );
    if (!mounted) return;

    // "이 플레이스에서 파티나 이벤트를 여시나요?" — 방금 만든 플레이스가
    // 이미 정해져 있으므로 어느 플레이스인지 다시 묻지 않는다
    // ([PlaceFollowupEntry]). 고르지 않으면 아래로 그대로 흘러 메인으로 간다.
    // 메인으로 돌아가기 전이어야 한다(popUntil 이후에는 이 화면의 Navigator로
    // 더 이상 push할 수 없다 — 위 파티 연결 안내와 같은 이유).
    await PlaceFollowupEntry.show(
      context,
      placeId: eventRef.id,
      placeCollection: 'events',
      placeData: {...doc, 'id': eventRef.id},
      placeName: _nameCtrl.text.trim(),
    );
    if (!mounted) return;

    // 등록 화면이 몇 단계 깊이 열려 있었든(모바일: RegisterTypeScreen 경유,
    // 데스크톱: MainScreen에서 바로) 곧장 메인화면 플레이스 탭으로 복귀한다.
    pendingTopTabAfterRegister.value = 1;
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  /// 수정 저장 — 기존 문서를 갱신한다. 숨김 상태에서 저장하면 사용자가 켜 둔
  /// 노출 토글 그대로 다시 노출되므로, 이 경로가 곧 "재등록"이기도 하다.
  Future<void> _saveEdit(Map<String, dynamic> doc) async {
    final placeId = widget.eventId!;
    await FirebaseFirestore.instance
        .collection('events')
        .doc(placeId)
        .update(doc);

    // 상품·이용권 — 화면 목록을 문서에 그대로 맞춘다. 아직 다 읽지 못했다면
    // 손대지 않는다(빈 목록으로 덮어써 기존 상품을 지우면 안 된다).
    if (_productsLoaded) await _saveProducts(placeId);

    // 콤보(플레이스+파티)로 등록된 플레이스면 연결된 파티 문서에도 같은
    // 혜택을 반영한다 — 파티 상세로 들어와도 같은 혜택이 보이게.
    await syncPartychuPerkAcrossBundle(
      bundleId: _source['bundleId'] as String?,
      perk: _partychuPerkCtrl.text.trim(),
      selfDocId: placeId,
    );

    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _saveProducts(String placeId) async {
    await PlaceProductSection.save(
      placeId: placeId,
      placeCollection: 'events',
      hostId: UserSession.userId,
      products: _products,
    );
    // 이벤트는 **신규 등록에서만** 이 폼이 저장한다. 수정 모드에서는 관리
    // 화면이 단독으로 쓴다 — save는 목록 전체를 치환하는 동작이라, 이 화면이
    // 열려 있는 동안 관리 화면에서 추가된 이벤트를 지워버린다.
    if (!_isEdit) {
      await PlacePromotionSection.save(
        placeId: placeId,
        placeCollection: 'events',
        hostId: UserSession.userId,
        promotions: _promotions,
      );
    }
    await PlaceMenuSection.save(
      placeId: placeId,
      placeCollection: 'events',
      hostId: UserSession.userId,
      menus: _menus,
    );
  }

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(t), behavior: SnackBarBehavior.floating),
  );

  // 저장용 24시간제("HH:mm") — 운영시간(openTime/closeTime)이 쓴다.
  String _fmtTime24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ── 빌드 ─────────────────────────────────────────────────────────
  //
  // 섹션 구성과 순서는 **등록 화면 기준(정본)** 이다. 수정도 이 순서를 그대로
  // 쓰므로 두 화면이 다시 어긋날 수 없다.
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !draftDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await confirmLeaveWithDraftSave();
        // context.mounted로 확인한다 — State의 mounted만 보면 이 build의
        // BuildContext가 이미 트리에서 빠진 경우를 놓친다.
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF4F8),
        appBar: AppBar(
          title: Text(
            widget.mode.screenTitle('플레이스'),
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
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          // 운영 도구(판매 통계·이용권 QR)는 이미 만들어진 플레이스에만 쓸 수
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
                          placeId: widget.eventId!,
                          placeName: _placeNameOrDefault,
                          accent: const Color(0xFFFF6FA0),
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
        body: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 0. 플레이스가 무엇인지 ───────────────────────────
              // "플레이스 = 술집·카페 같은 매장"으로만 읽혀서, 파티 공간이나
              // 숙박을 가진 호스트가 이 화면을 자기 것이 아니라고 지나쳤다.
              // 무엇을 올릴 수 있는지와, 파티가 아직 없어도 먼저 올려두면
              // 된다는 것을 **입력을 시작하기 전에** 알려준다.
              // 수정할 때는 이미 아는 이야기라 띄우지 않는다.
              if (!_isEdit) const PlaceScopeNotice(),
              // ── 0-1. 어떤 공간인가요? ────────────────────────────
              // 플레이스+파티 등록과 **같은 위젯·같은 선택지**다. 여기서
              // 공간대여·숙박을 고르면 셸이 룸·요금·예약 입력을 가진
              // 장소대여 폼으로 바꾼다(저장도 places+placeRooms로 간다).
              if (widget.onSpaceTypeChanged != null)
                SpaceTypeSelector(
                  value: ComboPlaceType.venue,
                  onChanged: _requestSpaceTypeChange,
                ),
              // ── 0-2. 오픈 기념 홍보 이벤트 ──────────────────────
              // 입력 항목 중에서는 가장 먼저 보이도록 맨 위에 둔다.
              PartychuPerkSection(controller: _partychuPerkCtrl),
              if (draftMediaNeedsReselect) buildMediaReselectBanner(),
              // 등록을 눌렀을 때 비어 있던 필수 항목이 목록으로 남는다 —
              // 각 줄을 누르면 그 입력칸으로 간다(다른 등록 화면과 동일).
              RegisterMissingFieldsBanner(fields: _missingFields),

              // ── 1. 플레이스 제목 ─────────────────────────────────────
              _label('플레이스 제목 (매장 이름)', required: true),
              RegisterFieldAnchor(
                key: _nameKey,
                child: TextField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _showNameError = false),
                  decoration: _deco(
                    '예: 파티츄 2호 혼술바',
                    error: _showNameError,
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // ── 2. 업종 대분류 ───────────────────────────────────────
              // 폼의 첫 갈림길 — 여기서 고른 대분류에 따라 아래 '세부 정보'
              // 섹션이 물어보는 항목이 달라진다(클럽이면 음악 장르·입장
              // 정보, 카페면 그런 항목이 아예 안 나온다).
              PlaceCategorySection(
                category: _placeCategory,
                subcategories: _subcategories,
                maxSubcategories: _maxSubcategories,
                onCategoryChanged: (next) => setState(() {
                  _placeCategory = next;
                  _categoryTouched = true;
                  // 대분류를 바꾸면 이전 대분류의 소분류는 뜻이 없다.
                  _subcategories.clear();
                  // 새 대분류에서 묻지 않는 속성도 함께 버린다 — 화면에서
                  // 사라진 값이 문서에만 남지 않게.
                  _placeAttributes = pruneAttributesFor(_placeAttributes, next);
                  _attributesTouched = true;
                }),
                onSubcategoryToggled: (sub) => setState(() {
                  _categoryTouched = true;
                  if (!_subcategories.remove(sub)) _subcategories.add(sub);
                }),
              ),
              const SizedBox(height: 22),

              // ── 2-1. 업종(기존) ──────────────────────────────────────
              // "무슨 가게인가" — 한 매장이 술집이면서 바이고 라운지일 수 있어
              // 다중 선택이되, 세 개를 넘으면 정체성이 흐려져 손님이 무슨
              // 가게인지 판단할 수 없으므로 최대 3개로 끊는다.
              _label('업종 (최대 $_maxBusinessTypes개)'),
              _buildBusinessTypeChips(),
              const SizedBox(height: 22),

              // ── 3. 대표 가격대 ───────────────────────────────────────
              // 1인 기준 예상 지출 — 한 매장에 하나만 붙는 값이라 단일 선택.
              _label('대표 가격대'),
              _buildPriceRangeChips(),
              const SizedBox(height: 6),
              const Text(
                '1인 기준으로 가장 대표적인 가격대를 선택해주세요.',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
              const SizedBox(height: 22),

              // 예전에는 여기에 '특징 태그 (다중 선택 가능)' 칩
              // (📸 사진맛집 / 🎉 이벤트 진행중)과, 그 아래 '어떤
              // 이벤트인가요?' 소분류가 있었다. 둘 다 없앴다.
              //
              //  · 🎉 이벤트 진행중 — 호스트가 손으로 켜고 끄는 값이 아니라
              //    **이벤트 정본에서 자동으로 결정**된다. 이 플레이스의
              //    이벤트(`placePromotions`)를 저장·숨김·삭제할 때마다
              //    [PartyEventSource.eventMirrorUpdate]가 `themeTags`의
              //    '이벤트'와 갈래·종료일 미러를 함께 다시 적는다. 손으로
              //    켜 두면 이벤트가 하나도 없는데 이벤트 탐색에 걸리고,
              //    손으로 안 켜면 이벤트를 올려도 목록에 안 뜬다 — 같은
              //    사실을 두 곳에서 정하니 늘 한쪽이 틀렸다.
              //  · 📸 사진맛집 — 호스트가 스스로 붙이는 홍보 문구였다.
              //    검색 조건으로 쓰기에는 근거가 없어 입력을 닫는다.
              //
              // **읽는 쪽은 그대로다.** 이미 달린 `themeTags`는 상세·카드·
              // 필터에서 예전과 똑같이 보이고, 수정 저장은 이 필드를 아예
              // 건드리지 않으므로 기존 값이 지워지지 않는다.

              // ── 3. 대표 미디어 ───────────────────────────────────────
              // 사진 1장과 동영상 1개를 한 화면에서 고르고, 그중 **무엇을
              // 목록 카드의 대표로 쓸지**까지 여기서 정한다. 예전에는
              // 대표 이미지와 동영상이 서로 다른 피커로 나뉘어 있어 고를
              // 방법이 없었고, 동영상은 카드에 나오지 못했다.
              _label('대표 사진 / 동영상'),
              _buildCoverMediaPicker(),
              const SizedBox(height: 4),
              const Text(
                '대표 사진 1장 · 동영상 1개(최대 30초) · 목록 카드에 보일 위치까지 정할 수 있어요',
                style: TextStyle(fontSize: 11, color: Colors.black38),
              ),
              const SizedBox(height: 22),

              // ── 4. 소개 이미지 ───────────────────────────────────────
              _label('소개 이미지 (최대 6장)'),
              _buildIntroImagePicker(),
              const SizedBox(height: 22),

              // ── 5. 플레이스 안내 ─────────────────────────────────────
              // 여기는 '매장 자체'를 적는 칸이다. 기간·시간대가 걸린 혜택은
              // 이벤트 정본(placePromotions)에서 관리하므로, 그 내용이 이
              // 칸에 들어오지 않도록 입력창 위에서 먼저 갈라 준다.
              _label('플레이스 안내'),
              const Text(
                '※ 특정 기간·시간대에 진행하는 무료입장, 할인, 무료 제공 등의 '
                '혜택은 이벤트에서 등록해주세요.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE03131),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '매장의 분위기, 특징, 이용 방법 등 플레이스 자체에 대한 내용을 '
                '적어주세요.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descCtrl,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: _deco(
                  '예: 혼자 방문하기 좋은 바예요. 바 좌석과 테이블석이 있고, '
                  '가볍게 칵테일이나 맥주를 즐길 수 있어요.',
                ),
              ),
              const SizedBox(height: 22),

              // ── 6. 매장 위치 ─────────────────────────────────────────
              _label('매장 위치'),
              _buildLocationSection(),
              const SizedBox(height: 22),

              // ── 6-1. 공간 평수 ───────────────────────────────────────
              //
              // 장소대여·콤보 등록과 **같은 필드(areaPyeong)·같은 검증**을
              // 쓴다([PlaceAreaField]). 단위 '평'은 입력칸이 붙이므로 저장값은
              // 언제나 숫자다.
              RegisterFieldAnchor(
                key: _areaKey,
                child: PlaceAreaField(
                  fieldKey: _areaFieldKey,
                  controller: _areaCtrl,
                  focusNode: _areaFocus,
                  decoration: _deco(PlaceArea.placeholder),
                  labelBuilder: (text) => _label(text),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 22),

              // 예전에는 여기에 '진행 기간(상시 진행)'과 '이용 시간(시간
              // 지정)'이 있었다. 둘 다 이벤트(`placePromotions`) 모양을 그대로
              // 물려받은 잔재였고, 검색·지도·방문예약 어디에도 쓰이지 않은 채
              // 상세 화면 표시에만 남아 있었다. 플레이스의 시간 정본은 아래
              // **운영시간 하나**이고, 기간·시간이 걸린 내용은 이벤트에서
              // 관리한다.

              // ── 7-2. 연락처 ──────────────────────────────────────────
              _label('연락처'),
              TextField(
                controller: _contactCtrl,
                keyboardType: TextInputType.phone,
                decoration: _deco('예: 010-1234-5678'),
              ),
              const SizedBox(height: 22),

              // ── 7-3. 운영시간 / 애견동반 / 좌석·공간 ──────────────────
              PlaceHoursSection(
                title: '운영시간',
                description: '플레이스 상세에 표시되는 기본 운영 시간이에요.',
                isOpen24Hours: _placeIsOpen24Hours,
                onOpen24HoursChanged: (v) => setState(() {
                  _placeIsOpen24Hours = v;
                  _hoursTouched = true;
                }),
                openTime: _placeOpenTime,
                closeTime: _placeCloseTime,
                onTimeChanged: (isOpen, picked) => setState(() {
                  if (isOpen) {
                    _placeOpenTime = picked;
                  } else {
                    _placeCloseTime = picked;
                  }
                  _hoursTouched = true;
                }),
                weeklyHours: _placeWeeklyHours,
                onWeeklyChanged: () => setState(() => _hoursTouched = true),
              ),
              // 방문 예약은 영업시간 안에서만 받으므로 운영시간 바로 아래에 둔다.
              VisitReservationSection(
                config: _visitReservation,
                onChanged: (next) => setState(() {
                  _visitReservation = next;
                  _visitReservationTouched = true;
                }),
              ),
              // 문의 받기는 "손님과 어떻게 연락할지"라 방문 예약 바로 아래에 둔다.
              GuestInquirySection(
                enabled: _inquiryEnabled,
                onChanged: (v) => setState(() => _inquiryEnabled = v),
                guideController: _inquiryGuideCtrl,
              ),
              PetPolicySection(
                value: _petPolicy,
                onChanged: (next) => setState(() {
                  _petPolicy = next;
                  _petPolicyTouched = true;
                }),
              ),
              // 세부 속성 — 고른 대분류에 필요한 것만 펼쳐진다.
              // 놀거리의 '기타'를 고르면 그 아래에 자유기재 칸이 함께 뜬다 —
              // 값은 `placeAttributes`가 아니라 별도 배열로 간다.
              PlaceAttributesSection(
                category: _placeCategory,
                value: _placeAttributes,
                onChanged: (next) => setState(() {
                  _placeAttributes = next;
                  _attributesTouched = true;
                }),
                customPlayItems: _customPlayItems,
                onCustomPlayItemsChanged: (next) => setState(() {
                  _customPlayItems = next;
                  _customPlayItemsTouched = true;
                }),
              ),
              const SizedBox(height: 14),
              PlaceFacilityOptionsSection(
                emoji: '🪑',
                title: '좌석·공간',
                emptyHint: '좌석 및 공간 정보를 설정해주세요.',
                groups: PlaceFacilityCatalog.seatingSection,
                value: _facilityOptions,
                onChanged: (next) => setState(() {
                  _facilityOptions = next;
                  _facilityTouched = true;
                }),
              ),
              // 외부 음식 반입 — 좌석과 성격이 달라 섹션을 나눈다. 같은
              // facilityOptions 필드에 그룹 키 하나로 얹히므로 저장·복원·
              // 상세 표시가 기존 편의시설과 완전히 같은 경로를 탄다.
              PlaceFacilityOptionsSection(
                emoji: '🍽',
                title: '외부 음식 반입',
                emptyHint: '외부 음식 반입 가능 여부를 설정해주세요.',
                groups: PlaceFacilityCatalog.foodSection,
                value: _facilityOptions,
                onChanged: (next) => setState(() {
                  _facilityOptions = next;
                  _facilityTouched = true;
                }),
              ),
              // 기타 편의 서비스 — 정식 선택지 **아래**에 둔다. 위에서 고를 수
              // 있는 것을 다 본 뒤에야 "여기 없는 것"을 적게 된다.
              CustomAmenitySection(
                items: _customAmenities,
                onChanged: (next) => setState(() {
                  _customAmenities = next;
                  _customAmenitiesTouched = true;
                }),
              ),
              const SizedBox(height: 14),

              // ── 8. 노출 여부 ─────────────────────────────────────────
              _buildToggleRow(
                icon: Icons.visibility_outlined,
                title: '노출 중',
                desc: '플레이스를 목록에 지금 노출할지 설정해요.',
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: 16),

              // 상품·이용권과 매장 이벤트는 **선택 사항**이라 폼 맨 뒤에 둔다 —
              // 위쪽에 두면 제목·주소·사진 같은 필수 입력이 아래로 밀려서,
              // 이 기능을 안 쓰는 사장님이 매번 길게 스크롤해야 한다.
              //
              // 수정 모드에서 목록을 다 읽기 전에는 두 섹션 모두 그리지 않는다 —
              // 빈 목록으로 보였다가 저장되면 기존 상품이 지워진 것처럼 보인다.
              // (예전 수정 화면은 중괄호 없는 `if` 탓에 이 가드가 프로모션
              //  섹션에만 걸려 있었다.)
              if (_productsLoaded) ...[
                // 메뉴 — 술집·바·카페에서 가장 먼저 보게 되는 정보라 상품·
                // 이벤트보다 위에 둔다.
                _buildMenuModeSelector(),
                // 고른 방식의 입력만 그린다. **다른 방식으로 이미 넣어 둔
                // 데이터는 지우지 않는다** — 방식 선택은 무엇을 입력할지
                // 고르는 스위치이지 데이터를 버리는 스위치가 아니다.
                // 둘 다 남아 있으면 손님 화면에는 둘 다 나온다.
                if (_menuBoardMode)
                  _buildMenuBoardSection()
                else
                  PlaceMenuSection(
                    menus: _menus,
                    onChanged: () => setState(() {}),
                    accent: const Color(0xFFFF6FA0),
                  ),
                // 이벤트는 등록과 수정에서 창구가 다르다.
                //   신규: 폼 안에서 첫 이벤트를 함께 넣는다(기존 흐름).
                //   수정: 별도 관리 화면으로 보낸다 — 이 폼의 저장은 목록
                //         전체를 치환(syncForPlace)하므로, 관리 화면에서
                //         그사이 추가한 이벤트가 밀려 사라지는 걸 막는다.
                if (_isEdit)
                  PlaceEventManageEntryCard(
                    placeId: widget.eventId!,
                    placeCollection: 'events',
                    hostId: _source['hostId'] as String? ?? '',
                    placeName: _placeNameOrDefault,
                    accent: const Color(0xFFFF6FA0),
                  )
                else
                  PlacePromotionSection(
                    promotions: _promotions,
                    onChanged: () => setState(() {}),
                    accent: const Color(0xFFFF6FA0),
                    linkableProducts: _products,
                  ),
                PlaceProductSection(
                  products: _products,
                  onChanged: () => setState(() {}),
                  accent: const Color(0xFFFF6FA0),
                  showAddonChannel: false,
                  // 취소·환불 규정이 비어 있는 상품을 펼치고, 그 입력칸에
                  // 앵커를 붙여 준다 — 안내 문구를 누르면 섹션이 아니라
                  // **그 칸**으로 간다.
                  revealRefundOf: _revealProductRefund,
                  refundAnchorKey: _productRefundKey,
                  refundFocusNode: _productRefundFocus,
                ),
              ],
              const SizedBox(height: 16),

              // ── 제출 버튼 ────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  // 동영상 압축 중 저장을 막던 조건은 뺐다 — 압축은 이제
                  // 공용 픽커 화면 안에서만 일어나고, 그 화면이 닫힌 뒤에야
                  // 여기로 돌아오므로 이 화면에서 압축이 진행 중일 수 없다.
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6FA0),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          widget.mode.submitLabel('플레이스'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              // 삭제는 앱 전체가 같은 흐름을 쓴다(공용 DeleteContentButton).
              // 등록 중에는 지울 대상이 아직 없다.
              if (_isEdit)
                DeleteContentButton(
                  type: DeletableContent.event,
                  id: widget.eventId!,
                  contentName: _nameCtrl.text.trim(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _placeNameOrDefault =>
      _nameCtrl.text.trim().isEmpty ? '내 플레이스' : _nameCtrl.text.trim();

  // ── 업종 칩 (다중 선택, 최대 3개) ───────────────────────────────────
  // 상세검색 시트의 업종 항목과 **같은 상수**([ListingConstants.
  // eventBusinessTypes])를 읽으므로, 고른 값이 그대로 필터에 걸린다.
  Widget _buildBusinessTypeChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ListingConstants.eventBusinessTypes.map((c) {
        final sel = _businessTypes.contains(c);
        // 이미 3개를 골랐으면 나머지는 눌러도 안 켜진다는 걸 색으로 알린다.
        final full = !sel && _businessTypes.length >= _maxBusinessTypes;
        return GestureDetector(
          onTap: () {
            if (full) {
              _msg('업종은 최대 $_maxBusinessTypes개까지 고를 수 있어요.');
              return;
            }
            setState(() {
              if (sel) {
                _businessTypes.remove(c);
              } else {
                _businessTypes.add(c);
              }
            });
            markDraftDirty();
          },
          child: _selectChip(c, selected: sel, dimmed: full),
        );
      }).toList(),
    );
  }

  // ── 가격대 칩 (단일 선택) ───────────────────────────────────────────
  // 한 매장에 하나만 붙는 값이라 고른 것을 다시 누르면 해제된다(= 미지정).
  Widget _buildPriceRangeChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ListingConstants.eventPriceRanges.map((c) {
        final sel = _priceRange == c;
        return GestureDetector(
          onTap: () {
            setState(() => _priceRange = sel ? null : c);
            markDraftDirty();
          },
          child: _selectChip(c, selected: sel),
        );
      }).toList(),
    );
  }

  /// 업종·가격대가 함께 쓰는 칩 — 특징 태그 칩과 같은 모양이다(이모지만 없음).
  Widget _selectChip(
    String label, {
    required bool selected,
    bool dimmed = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFFFF6FA0) : const Color(0xFFF7F7FA),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: selected ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: selected
            ? Colors.white
            : (dimmed ? Colors.black26 : Colors.black54),
      ),
    ),
  );


  // ── 매장 위치 검색 섹션 ──────────────────────────────────────────
  Widget _buildLocationSection() {
    // 수정 모드에서 아직 주소를 다시 고르지 않았으면 문서에 저장된 주소를
    // 그대로 보여준다(등록 모드에서는 _existingAddress가 늘 비어 있다).
    final displayAddress = _selectedAddress?.address ?? _existingAddress;
    final hasAddress = displayAddress.isNotEmpty;
    return Column(
      children: [
        GestureDetector(
          onTap: () async {
            final result = await Navigator.push<AddressResult>(
              context,
              webFramedRoute((_) => const AddressSearchScreen()),
            );
            if (result != null) {
              setState(() {
                _selectedAddress = result;
                _existingAddress = result.address;
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: hasAddress ? const Color(0xFFFFF0F5) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasAddress
                    ? const Color(0xFFFF6FA0)
                    : const Color(0xFFE8EBF2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: hasAddress ? const Color(0xFFFF6FA0) : Colors.black38,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasAddress ? displayAddress : '주소 검색',
                    style: TextStyle(
                      fontSize: 14,
                      color: hasAddress ? Colors.black87 : Colors.black38,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_selectedAddress != null)
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedAddress = null;
                      _existingAddress = _source['address'] as String? ?? '';
                    }),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.black38,
                    ),
                  )
                else
                  const Icon(Icons.search, size: 18, color: Colors.black38),
              ],
            ),
          ),
        ),
        // 주소 검색으로는 잡히지 않는 층/호수/건물 내부 위치를 손으로 적는 칸.
        // 저장은 `detailAddress` 한 필드로만 가고, 지도·좌표는 검색으로 고른
        // 기본 주소만 쓴다 — 이 값은 좌표에 영향을 주지 않는다.
        if (hasAddress) ...[
          const SizedBox(height: 14),
          _label('상세 주소'),
          TextField(
            controller: _detailAddressCtrl,
            textInputAction: TextInputAction.next,
            decoration: _deco('예: 3층 301호'),
          ),
        ],
      ],
    );
  }

  // ── 대표 미디어(사진 1장 + 동영상 1개) ───────────────────────────
  //
  // 파티·장소대여와 같은 공용 픽커 하나를 연다. 그 안에서
  //   사진/동영상 선택 → (동영상이면) 30초 트림 → 압축 → 대표 지정 →
  //   기본 카드 프레임 조정 → 선택 완료
  // 까지 끝난다. 이 화면은 결과 스냅샷만 보관한다.

  String? _coverSummary() {
    final photos = _coverPhotoCount;
    final parts = <String>[
      if (photos > 0) '사진 $photos장',
      if (_coverHasVideo) '동영상 1개',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _openCoverMediaPicker() async {
    final result = await Navigator.push<PartyMediaSelection>(
      context,
      webFramedRoute(
        (_) => PartyMediaPickerScreen(
          existingImageUrls: _coverExistingImageUrls,
          existingVideoUrl: _coverExistingVideoUrl,
          existingVideoUid: _coverExistingVideoUid,
          existingVideoThumbnailUrl: _coverExistingVideoThumbnailUrl,
          newMedia: _coverNewFiles,
          coverPick: _coverPick,
          basicCardFocalX: _coverBasicCardFocalX,
          basicCardFocalY: _coverBasicCardFocalY,
          basicCardScale: _coverBasicCardScale,
          photoCrops: _coverPhotoCrops,
          videoCropConfirmed: _coverVideoCropConfirmed,
          // 플레이스도 파티·장소대여와 같은 기본 카드에 뜬다 — 대표로 고른
          // 미디어의 노출 위치를 정해야 '선택 완료'가 열린다.
          maxImages: _coverMaxImages,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _coverExistingImageUrls = result.existingImageUrls;
      _coverExistingVideoUrl = result.existingVideoUrl;
      _coverExistingVideoUid = result.existingVideoUid;
      _coverExistingVideoThumbnailUrl = result.existingVideoThumbnailUrl;
      _coverNewFiles = result.newMedia;
      _coverPick = result.coverPick;
      _coverBasicCardFocalX = result.basicCardFocalX;
      _coverBasicCardFocalY = result.basicCardFocalY;
      _coverBasicCardScale = result.basicCardScale;
      _coverPhotoCrops = result.photoCrops;
      _coverVideoCropConfirmed = result.videoCropConfirmed;
    });
  }

  Widget _buildCoverMediaPicker() {
    final summary = _coverSummary();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              summary,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _openCoverMediaPicker,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: Text(summary == null ? '대표 사진 / 동영상 등록' : '대표 사진 / 동영상 수정'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFF6FA0),
            side: const BorderSide(color: Color(0xFFFF6FA0)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  // ── 소개 이미지 피커 ─────────────────────────────────────────────
  /// 전체 메뉴판 사진 — 매장에 걸린 메뉴판을 찍어 올리는 자리.
  ///
  /// 개별 메뉴([PlaceMenuSection])와 나란히 두되 섹션을 나눈 이유는, 둘이
  /// 서로를 대신하는 관계이기 때문이다. 대표 메뉴 몇 개만 사진과 함께 보여주고
  /// 나머지는 메뉴판 사진 한 장으로 갈음하는 게 사장님에게 가장 편하다.
  ///
  /// 사진 고르기·지우기·개수 제한은 소개 이미지와 완전히 같은 방식을 쓴다.
  /// 메뉴 등록 방식 고르기 — 개별 메뉴 / 전체 메뉴판 사진.
  ///
  /// 두 방식은 저장되는 곳이 아예 다르다(placeMenus 컬렉션 / 문서의
  /// menuBoardImageUrls). 그래서 여기서 고르는 것은 **이 화면에서 무엇을
  /// 입력할지**일 뿐이고, 반대쪽에 이미 넣어 둔 것은 그대로 남는다. 남아
  /// 있다는 사실을 모르면 "지웠는데 손님 화면에 계속 보인다"가 되므로
  /// 아래 안내 줄에서 그 사실을 그대로 말해 준다.
  Widget _buildMenuModeSelector() {
    final otherCount = _menuBoardMode ? _menus.length : _menuBoardCount;
    final otherLabel = _menuBoardMode ? '개별 메뉴' : '메뉴판 사진';

    Widget chip(String label, String hint, bool selected, VoidCallback onTap) =>
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFFF0F5) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFF6FA0)
                      : const Color(0xFFE8EBF2),
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: selected
                            ? const Color(0xFFFF6FA0)
                            : Colors.black26,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? const Color(0xFFE2568A)
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '메뉴 등록 방식',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            '편한 쪽으로 고르세요. 나중에 언제든 바꿀 수 있어요.',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
          const SizedBox(height: 12),
          // 두 카드의 높이를 맞춘다. Row에 stretch만 주면 세로가 무한인
          // 자리(SingleChildScrollView 안의 Column)에서는 h=Infinity가 되어
          // 레이아웃이 통째로 터진다 — 높이를 먼저 재 주는 IntrinsicHeight가
          // 있어야 stretch가 성립한다.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                chip(
                  '개별 메뉴 등록',
                  '메뉴명·가격을 한 줄씩',
                  !_menuBoardMode,
                  () => setState(() => _menuBoardMode = false),
                ),
                const SizedBox(width: 8),
                chip(
                  '전체 메뉴판 사진',
                  '메뉴판을 찍어 올리기',
                  _menuBoardMode,
                  () => setState(() => _menuBoardMode = true),
                ),
              ],
            ),
          ),
          // 반대쪽에 남아 있는 데이터를 숨기지 않고 알린다.
          if (otherCount > 0) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.black38),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '이미 등록한 $otherLabel $otherCount개도 그대로 남아 있어요. '
                    '손님 화면에는 둘 다 표시됩니다.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: Colors.black45,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuBoardSection() {
    final total = _menuBoardCount;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF6FA0).withValues(alpha: 0.28),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text('📋', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text(
                '전체 메뉴판 사진',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '매장에 걸린 메뉴판을 찍어 올리면 손님이 확대해서 볼 수 있어요. '
            '메뉴를 하나하나 등록하지 않아도 됩니다. '
            '최대 $_maxMenuBoardImages장, 사진을 누르면 미리보기 · '
            '좌우 화살표로 순서를 바꿉니다.',
            style: TextStyle(fontSize: 12, height: 1.4, color: Colors.black45),
          ),
          const SizedBox(height: 12),
          if (total > 0) ...[
            SizedBox(
              height: 104,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _menuBoardImages.length; i++)
                    _menuBoardThumb(i),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (total < _maxMenuBoardImages)
            GestureDetector(
              onTap: _pickMenuBoard,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE8EBF2)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.add_a_photo_outlined,
                      size: 28,
                      color: Colors.black38,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '메뉴판 사진 추가 ($total/$_maxMenuBoardImages)',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIntroImagePicker() {
    final total = _existingIntroImageUrls.length + _newIntroImages.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0) ...[
          SizedBox(
            height: 104,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ..._existingIntroImageUrls.asMap().entries.map(
                  (e) => _introThumb(
                    image: NetworkImage(e.value),
                    onRemove: () =>
                        setState(() => _existingIntroImageUrls.removeAt(e.key)),
                  ),
                ),
                ..._newIntroImages.asMap().entries.map(
                  (e) => _introThumb(
                    image: LocalMedia.imageProvider(e.value),
                    onRemove: () =>
                        setState(() => _newIntroImages.removeAt(e.key)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (total < 6)
          GestureDetector(
            onTap: _pickIntro,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE8EBF2)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.add_a_photo_outlined,
                    size: 28,
                    color: Colors.black38,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '소개 이미지 추가 ($total/6)',
                    style: const TextStyle(fontSize: 13, color: Colors.black38),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 기존 URL 썸네일과 새로 고른 파일 썸네일이 완전히 같은 모양이라 하나로 묶었다.
  /// 메뉴판 사진 한 장 — 눌러서 크게 보고, 좌우로 순서를 바꾸고, 지운다.
  ///
  /// 소개 이미지 썸네일([_introThumb])과 달리 순서 버튼이 붙는다. 메뉴판은
  /// 여러 장을 순서대로 넘겨 보는 물건이라(1페이지·2페이지) 순서가 곧 정보다.
  Widget _menuBoardThumb(int index) {
    final item = _menuBoardImages[index];
    final image = item.imageProvider;
    final isFirst = index == 0;
    final isLast = index == _menuBoardImages.length - 1;

    Widget arrow(IconData icon, bool enabled, VoidCallback onTap) =>
        GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: 26,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled ? Colors.black54 : Colors.black12,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: Colors.white),
          ),
        );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _previewMenuBoard(index),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              image: DecorationImage(image: image, fit: BoxFit.cover),
            ),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: -4,
          right: 4,
          child: GestureDetector(
            onTap: () => setState(() => _menuBoardImages.removeAt(index)),
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black54,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          right: 12,
          child: Row(
            children: [
              arrow(
                Icons.chevron_left,
                !isFirst,
                () => _moveMenuBoard(index, index - 1),
              ),
              const SizedBox(width: 4),
              arrow(
                Icons.chevron_right,
                !isLast,
                () => _moveMenuBoard(index, index + 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _moveMenuBoard(int from, int to) {
    if (to < 0 || to >= _menuBoardImages.length) return;
    setState(() {
      final item = _menuBoardImages.removeAt(from);
      _menuBoardImages.insert(to, item);
    });
  }

  /// 등록 화면에서의 미리보기 — 올라간 사진은 손님이 보는 것과 같은 뷰어로,
  /// 아직 안 올린 로컬 파일은 같은 크기의 다이얼로그로 보여준다(뷰어는 URL만
  /// 받는다).
  void _previewMenuBoard(int index) {
    final item = _menuBoardImages[index];
    final url = item.url;
    if (url != null && url.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FullScreenImageViewer(imageUrl: url)),
      );
      return;
    }
    final file = item.file;
    if (file == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(
            child: LocalMedia.image(file, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Widget _introThumb({
    required ImageProvider image,
    required VoidCallback onRemove,
  }) => Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        margin: const EdgeInsets.only(right: 8),
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          image: DecorationImage(image: image, fit: BoxFit.cover),
        ),
      ),
      Positioned(
        top: -4,
        right: 4,
        child: GestureDetector(
          onTap: onRemove,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black54,
            ),
            child: const Icon(Icons.close, size: 12, color: Colors.white),
          ),
        ),
      ),
    ],
  );

  // ── 공통 위젯 ────────────────────────────────────────────────────
  Widget _buildToggleRow({
    required IconData icon,
    required String title,
    required String desc,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE8EBF2)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFFFF6FA0)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFFFF6FA0),
          activeTrackColor: const Color(0xFFFFB8D0),
        ),
      ],
    ),
  );

  Widget _label(String text, {bool required = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFFFF6FA0),
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    ),
  );

  InputDecoration _deco(String hint, {String? suffix, bool error = false}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
        suffixText: suffix,
        suffixStyle: const TextStyle(color: Colors.black45, fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: error ? Colors.redAccent : const Color(0xFFE8EBF2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: error ? Colors.redAccent : const Color(0xFFE8EBF2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF6FA0)),
        ),
      );
}

/// 메뉴판 사진 한 장 — 이미 올라간 URL이거나, 아직 안 올린 로컬 파일이다.
///
/// 두 종류를 한 목록에 담기 위한 최소한의 상자다. 순서 변경 때문에 생겼다 —
/// 목록을 "올라간 것"과 "새로 고른 것"으로 나눠 두면 만들 수 있는 순서가
/// "기존 전부 → 새것 전부" 하나뿐이라, 방금 고른 사진을 맨 앞으로 옮길 수 없다.
class _MenuBoardImage {
  _MenuBoardImage.url(String this.url) : file = null;
  _MenuBoardImage.file(XFile this.file) : url = null;

  /// 업로드가 끝난 주소. 로컬 파일이면 null.
  final String? url;

  /// 아직 안 올린 파일. 이미 올라간 사진이면 null.
  final XFile? file;

  ImageProvider get imageProvider {
    final uploaded = url;
    if (uploaded != null) return NetworkImage(uploaded);
    return LocalMedia.imageProvider(file!);
  }

  /// 임시저장에 **순서까지** 담기 위한 한 줄 표현.
  String get draftTag {
    final uploaded = url;
    return uploaded != null
        ? 'u:$uploaded'
        : 'f:${LocalMedia.remember(file!).path}';
  }

  static _MenuBoardImage? fromDraftTag(Object? raw) {
    if (raw is! String || raw.length < 3) return null;
    final value = raw.substring(2);
    if (value.isEmpty) return null;
    if (raw.startsWith('u:')) return _MenuBoardImage.url(value);
    if (raw.startsWith('f:')) {
      return _MenuBoardImage.file(LocalMedia.resolve(value));
    }
    return null;
  }
}
