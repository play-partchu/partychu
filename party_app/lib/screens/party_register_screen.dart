import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/participant_gender_visibility.dart';
import 'package:party_app/models/party_capacity_status.dart';
import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/party_auto_description_style.dart';
import 'package:party_app/models/party_description_mode.dart';
import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/party_detail_decoration_intensity.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/models/party_constants.dart';
import 'package:party_app/models/party_early_bird.dart';
import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/widgets/guest_inquiry_section.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/payment_policy.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/models/party_application_form.dart';
import 'package:party_app/services/party_application_form_service.dart';
import 'package:party_app/widgets/party_form/application_form_section.dart';
import 'package:party_app/widgets/party_form/payment_policy_sheet.dart';
import 'package:party_app/models/party_registration_data.dart';
import 'package:party_app/models/party_round.dart';
import 'package:party_app/models/party_round_package.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/models/draft_type.dart';
import 'package:party_app/services/draft_service.dart';
import 'package:party_app/services/business_verification_service.dart';
import 'package:party_app/models/party_open_state.dart';
import 'package:party_app/screens/party_detail_block_editor_screen.dart';
import 'package:party_app/screens/party_intro_screen.dart';
import 'package:party_app/screens/party_location_picker_screen.dart';
import 'package:party_app/screens/party_media_picker_screen.dart';
import 'package:party_app/screens/party_refund_policy_screen.dart';
import 'package:party_app/models/party_age_restriction.dart';
import 'package:party_app/utils/age_range_utils.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/utils/firestore_payload.dart';
import 'package:party_app/utils/register_form_mode.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/utils/register_validation.dart';
import 'package:party_app/widgets/party_form/register_field_anchor.dart';
import 'package:party_app/widgets/party_form/register_missing_fields_banner.dart';
import 'package:party_app/services/registration_limits.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/party_form/age_restriction_sheet.dart';
import 'package:party_app/widgets/party_form/date_time_sheet.dart';
import 'package:party_app/models/party_detail_image.dart';
import 'package:party_app/widgets/party_form/party_detail_block_draft.dart';
import 'package:party_app/widgets/party_form/party_detail_image_section.dart';
import 'package:party_app/widgets/party_form/party_detail_description_mode_sheet.dart';
import 'package:party_app/widgets/party_form/party_schedule_section.dart';
import 'package:party_app/widgets/party_form/fee_sheet.dart';
import 'package:party_app/widgets/party_form/gender_capacity_sheet.dart';
import 'package:party_app/widgets/party_form/party_title_field.dart';
import 'package:party_app/widgets/party_form/party_type_vibe_sheet.dart';
import 'package:party_app/widgets/party_form/round_list_editor.dart';
import 'package:party_app/widgets/party_form/round_package_editor.dart';
import 'package:party_app/widgets/partychu_perk.dart';
import 'package:party_app/services/party_slot_sync_service.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/widgets/party_form/party_place_link_section.dart';
import 'package:party_app/widgets/party_form/section_summary_row.dart';
import 'package:party_app/widgets/party_media_editor.dart' show PartyCoverPick;
import 'package:party_app/models/payment_method.dart';
import 'package:party_app/widgets/payout_account_prompt.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 등록 로그의 공통 prefix — 기기 로그에서 `party-register`로 한 번에 걸린다.
const String _logTag = 'party-register';

/// 등록이 어디까지 진행됐는지. 실패 로그 prefix와 사용자 안내 문구가 이
/// 단계에 따라 갈린다 — "업로드 실패"와 "저장 실패"를 같은 문구로 묶으면
/// 원인을 좁힐 수 없기 때문이다.
enum _SubmitStage {
  prepare('prepare', '준비'),
  upload('upload', '사진 업로드'),
  build('build', '등록 정보 준비'),
  firestore('firestore', '저장'),
  post('post', '마무리');

  const _SubmitStage(this.key, this.userLabel);

  /// debugPrint prefix에 쓰는 값(`[party-register:upload]`).
  final String key;

  /// 사용자에게 보여줄 단계 이름.
  final String userLabel;
}

/// 파티 등록 폼의 **정본**.
///
/// 등록과 재등록이 이 화면 하나를 공유한다 — 입력 항목·섹션 순서·버튼·토글·
/// 검증·사진/동영상·상세 소개·차수·패키지·얼리버드·환불규정·파티츄 혜택·주소·
/// 지도가 두 모드에서 100% 같다. 예전에는 재등록이 파티 **수정** 화면
/// (PartyEditScreen)을 재사용해서, 등록에만 있는 차수 편집기·연령제한 시트·
/// 미입력 항목 배너가 재등록에서 통째로 빠져 있었다.
///
/// 모드가 바꾸는 것은 [RegisterFormMode] 문서에 적힌 세 가지(제목/버튼 문구,
/// prefill 여부, 임시저장 사용 여부)뿐이다. **저장은 두 모드 모두 항상 새 문서**로
/// 나간다 — 재등록은 "내용은 복사하되 모집은 새로 시작"이라, 원본 파티는 지난
/// 기록으로 그대로 남고 신청자·참가 인원·모집 상태만 초기화된다.
class PartyRegisterScreen extends StatefulWidget {
  /// 등록인지 재등록인지 — 자세한 계약은 [RegisterFormMode] 참고.
  final RegisterFormMode mode;

  /// 재등록에서 불러올 원본 파티 문서. [RegisterFormMode.create]에서는 null.
  final Map<String, dynamic>? sourceData;

  /// 재등록 원본 문서의 id. 저장 후 원본의 `lastUsedAt`을 갱신하는 데만 쓴다 —
  /// 원본을 고치거나 지우는 데는 절대 쓰지 않는다(재등록은 새 문서를 만든다).
  /// 정기 파티 회차를 일회성으로 복사하는 진입처럼 원본 id가 의미 없는
  /// 경우에는 null을 넘겨도 된다.
  final String? sourceDocId;

  /// 마이페이지 "임시저장" 목록에서 "이어서 작성"으로 열 때 true — 복구
  /// 여부를 다시 묻지 않고 곧바로 임시저장을 불러온다.
  final bool autoRestoreDraft;

  /// **연결 대상이 미리 정해진 등록인지.** null이면 지금까지의 일반 등록과
  /// 완전히 같다(등록 탭 → 파티 등록). null이 아니면 "파티 연결 관리 →
  /// 새 파티 만들기"로 들어온 경우로, 저장 직후 그 대상에 자동 연결한 뒤
  /// 연결 관리 화면으로 돌아간다. 계약은 [PartyPrelinkTarget] 참고.
  final PartyPrelinkTarget? prelink;

  /// **등록 진입에서 미리 고른 내 공간.** null이면 지금까지의 일반 등록과
  /// 완전히 같다.
  ///
  /// [prelink]와 헷갈리기 쉬운데 성격이 정반대다:
  ///
  /// |              | [prelink]                  | [initialSpace]          |
  /// |--------------|----------------------------|-------------------------|
  /// | 들어오는 곳  | 그 공간의 "파티 연결 관리" | 등록 탭 → 연결 선택     |
  /// | 바꿀 수 있나 | 아니오(잠김)               | **예** — 다른 공간/해제 |
  /// | 임시저장     | 안 씀                      | 씀(연결 대상까지 저장)  |
  /// | 끝난 뒤      | 부른 화면으로 복귀         | 메인(일반 등록과 동일)  |
  ///
  /// 즉 이 값은 폼의 **초기 선택**일 뿐이라, 사용자가 손대는 순간부터는
  /// 직접 고른 것과 전혀 구분되지 않는다.
  final PartyPrelinkTarget? initialSpace;

  const PartyRegisterScreen({super.key, this.autoRestoreDraft = false})
    : mode = RegisterFormMode.create,
      sourceData = null,
      sourceDocId = null,
      prelink = null,
      initialSpace = null;

  /// **"내 플레이스에서 여는 파티"로 들어온 새 등록.**
  ///
  /// 폼은 일반 등록과 100% 같고, [space]가 연결 항목의 초기 선택으로 들어가
  /// 장소 정보가 그 공간 값으로 채워질 뿐이다. 등록을 마치기 전에 다른 내
  /// 공간으로 바꾸거나 "연결 안 함"으로 되돌릴 수 있다.
  const PartyRegisterScreen.withSpace({
    super.key,
    required PartyPrelinkTarget space,
  }) : mode = RegisterFormMode.create,
       sourceData = null,
       sourceDocId = null,
       autoRestoreDraft = false,
       prelink = null,
       initialSpace = space;

  /// 재등록 진입 — 마이페이지 > 지난 파티, 파티 상세 > 재등록이 모두 이 생성자를
  /// 쓴다. 두 진입점이 서로 다른 화면을 열던 시절의 동작 차이는 여기서 사라진다.
  const PartyRegisterScreen.reregister({
    super.key,
    required Map<String, dynamic> data,
    String? docId,
  }) : mode = RegisterFormMode.reregister,
       sourceData = data,
       sourceDocId = docId,
       autoRestoreDraft = false,
       prelink = null,
       initialSpace = null;

  /// 플레이스·공간대여의 "파티 연결 관리 → 새 파티 만들기" 진입.
  ///
  /// **등록 폼은 조금도 달라지지 않는다** — 달라지는 것은 (1) 장소가 대상
  /// 정보로 미리 채워지고 바꿀 수 없다는 것, (2) 저장 직후 자동 연결, (3) 끝난
  /// 뒤 메인이 아니라 부른 화면으로 돌아간다는 것뿐이다. pop 값은 **실제로
  /// 연결된 파티 문서 수**(취소하면 null, 등록은 됐지만 연결에 실패했으면 0).
  const PartyRegisterScreen.forLink({
    super.key,
    required PartyPrelinkTarget target,
  }) : mode = RegisterFormMode.create,
       sourceData = null,
       sourceDocId = null,
       autoRestoreDraft = false,
       prelink = target,
       initialSpace = null;

  @override
  State<PartyRegisterScreen> createState() => _PartyRegisterScreenState();
}

class _PartyRegisterScreenState extends State<PartyRegisterScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();

  // ── 임시저장(Draft) ──────────────────────────────────────────────────
  // 임시저장은 "빈 화면에서 새로 등록하는 경우"에만 동작한다 — 재등록은 이미
  // 원본 내용을 불러온 상태라, 임시저장을 덮어쓰거나 반대로 임시저장이 불러온
  // 내용을 밀어내는 사고만 생긴다(요구사항 9번).
  //
  // 연결용 등록(prelink)도 임시저장을 쓰지 않는다 — 임시저장에는 연결 대상이
  // 함께 담기지 않아서, 복구하면 "어느 플레이스에 붙일 파티였는지"가 사라진
  // 채 일반 파티 임시저장을 덮어쓰게 된다.
  bool get _isDraftEnabled => widget.mode.isCreate && widget.prelink == null;

  /// 재등록 모드인지 — 화면 문구와 "원본에서 불러오기" 동작에만 쓴다.
  /// 입력 항목·검증·저장 경로는 등록과 완전히 같다.
  bool get _isReregister => widget.mode.isReregister;
  DraftAutosaver? _autosaver;
  // initState/복구 중에는 자동저장을 예약하지 않도록 막는 게이트. 복구 결정이
  // 끝난 뒤에야 true가 된다.
  bool _draftReady = false;
  // 임시저장 복구 시 로컬 파일이 사라져 다시 선택해야 하는 사진/동영상이
  // 있으면 true — 화면 상단에 안내 배너를 띄운다.
  bool _draftMediaNeedsReselect = false;

  // ── 뒤로가기 이탈 방지 ───────────────────────────────────────────────
  // 사용자가 사진·동영상·환불 규정처럼 setState를 거치지 않는 값까지 포함해
  // 뭔가 하나라도 바꾸면 true가 된다. setState를 오버라이드해서 이 화면의
  // 거의 모든 상호작용을 개별 호출부를 일일이 손대지 않고 한 곳에서 잡아낸다.
  bool _dirty = false;

  void _markDirty() {
    _dirty = true;
    _scheduleAutosave();
  }

  @override
  void setState(VoidCallback fn) {
    _dirty = true;
    _scheduleAutosave();
    super.setState(fn);
  }

  /// "사용자가 고친 게 아니라 화면이 스스로 불러온 값"을 반영할 때 쓴다 —
  /// 위 setState 오버라이드를 타면 화면을 열자마자 _dirty가 서서 뒤로가기에
  /// 이탈 확인창이 뜬다. 프리필/비동기 로딩 결과 반영에만 쓴다.
  void _setStateQuiet(VoidCallback fn) {
    if (!mounted) return;
    super.setState(fn);
  }

  /// 마지막 변경 후 1초 debounce 뒤 한 번 자동저장을 예약한다. 복구가 끝나기
  /// 전(_draftReady==false)이나 임시저장 비활성 화면에서는 아무 일도 안 한다.
  void _scheduleAutosave() {
    if (!_isDraftEnabled || !_draftReady) return;
    _autosaver?.schedule(_buildDraftSnapshot);
  }

  DraftSnapshot _buildDraftSnapshot() {
    final cover = _mediaExistingImageUrls.isNotEmpty
        ? _mediaExistingImageUrls.first
        : null;
    return DraftSnapshot(
      title: _partyNameController.text.trim(),
      coverImageUrl: cover,
      payload: _toDraftPayload(),
    );
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

  // ── 임시저장 직렬화 헬퍼 ─────────────────────────────────────────────
  static Map<String, int>? _timeToMap(TimeOfDay? t) =>
      t == null ? null : {'h': t.hour, 'm': t.minute};

  static TimeOfDay? _timeFromMap(Object? raw) {
    if (raw is Map) {
      final h = (raw['h'] as num?)?.toInt();
      final m = (raw['m'] as num?)?.toInt();
      if (h != null && m != null) return TimeOfDay(hour: h, minute: m);
    }
    return null;
  }

  /// 현재 화면의 "전체" 작성 상태를 순수 JSON 맵으로 직렬화한다. 날짜는
  /// epoch millis, 시간은 {h,m}로 저장해 Firestore·SharedPreferences 양쪽에
  /// 그대로 담을 수 있게 한다(Timestamp를 쓰지 않는다).
  Map<String, dynamic> _toDraftPayload() {
    return <String, dynamic>{
      // 텍스트 입력(사용자가 친 그대로 보존)
      'titleText': _partyNameController.text,
      'introText': _introController.text,
      kPartychuPerkField: _partychuPerkController.text,
      'detailAddressText': _detailAddressController.text,
      'maleFeeText': _maleFeeController.text,
      'femaleFeeText': _femaleFeeController.text,
      'earlyBirdPercentText': _earlyBirdPercentController.text,
      'capacityText': _capacityController.text,
      'minCapacity': _minCapacity,
      'round1MinCapacity': _round1MinCapacity,
      'minCapacityPolicy': _minCapacityPolicy.key,
      'maleCapacityText': _maleCapacityController.text,
      'femaleCapacityText': _femaleCapacityController.text,
      // 장소
      'place': _selectedPlace == null
          ? null
          : {
              'placeName': _selectedPlace!.placeName,
              'address': _selectedPlace!.address,
              'roadAddress': _selectedPlace!.roadAddress,
              'jibunAddress': _selectedPlace!.jibunAddress,
              'latitude': _selectedPlace!.latitude,
              'longitude': _selectedPlace!.longitude,
            },
      // 내 공간 연결 — id와 **종류**만 담는다. 문서 본문은 복구할 때 다시
      // 읽는다(임시저장해 둔 사이에 그 공간이 수정·삭제됐을 수 있다).
      // 종류를 빼면 어느 컬렉션에서 읽어야 할지 알 수 없어, 공간대여에
      // 연결해 둔 임시저장이 복구할 때마다 조용히 사라진다.
      'linkedEventId': _linkedEventId,
      'linkTarget': _linkTarget.name,
      ListingInquiry.field: _inquiryEnabled,
      ListingInquiry.guideField: _inquiryGuideController.text,
      // 성별·인원
      'genderLimit': _genderLimit,
      'genderCapacityMode': _genderCapacityMode,
      'genderMode': _genderMode,
      ParticipantGenderVisibility.field: _revealParticipantGenderRatio,
      // 환불 규정
      'refundPolicy': RefundTier.listToMaps(_refundTiers),
      // 결제 방식 — 임시저장에서도 그대로 살린다.
      'paymentPolicy': _paymentPolicy?.toMap(),
      // 신청 방식 + 사전질문 — 임시저장에는 담아 두고, 실제 파티 문서에는
      // 저장이 끝난 뒤 콜러블로 보낸다(문서 직접 쓰기가 막혀 있다).
      'applicationApprovalMode': _approvalMode.key,
      'applicationQuestions': [
        for (var i = 0; i < _appQuestions.length; i++)
          _appQuestions[i].toMap(i),
      ],
      kRequireApplicantPhotosField: _requireApplicantPhotos,
      // 얼리버드
      'earlyBirdEnabled': _earlyBirdEnabled,
      'earlyBirdEndType': _earlyBirdEndType.key,
      'earlyBirdEndDateMs': _earlyBirdEndDate?.millisecondsSinceEpoch,
      'earlyBirdEndTime': _timeToMap(_earlyBirdEndTime),
      'earlyBirdRecurringRule': _earlyBirdRule.toMap(),
      // 유형·분위기·태그·지역·나이
      'partyTypes': _partyTypes.toList(),
      'vibes': _vibes.toList(),
      'tags': _tags,
      'region': _region,
      'district': _district,
      // 연령 제한 — 파티 문서와 **같은 키**로 담는다(성별별 필드 + 구버전용
      // 공통 필드). 그래야 복원이 PartyAgeRestriction.fromMap 하나로 끝난다.
      ..._ageRestriction.toFields(genderLimit: _genderLimit),
      'seriesId': _existingSeriesId,
      // 일정(방식 + 날짜 슬롯 + 정기 규칙) — 등록 화면 세 곳이 같은 키를 쓴다.
      ..._schedule.toDraftMap(),
      // 다차수 라운드
      'hasMultipleRounds': _hasMultipleRounds,
      'roundCapacityMode': _roundCapacityMode,
      'roundEarlyBirdMode': _roundEarlyBirdMode,
      // 차수마다 모집 창구·일정·정원·참가비·얼리버드를 통째로 담는다
      // (PartyRound.toDraftMap) — 문서 저장과 같은 모델이라 어긋나지 않는다.
      'extraRounds': [for (final r in _extraRounds) r.round.toDraftMap()],
      'roundPackages': [for (final p in _roundPackages) p.toDraftMap()],
      // 미디어 — 업로드된 URL은 그대로, 아직 업로드 안 된 로컬 파일은 경로만.
      'existingImageUrls': _mediaExistingImageUrls,
      'existingVideoUrl': _mediaExistingVideoUrl,
      'existingVideoUid': _mediaExistingVideoUid,
      'existingVideoThumbnailUrl': _mediaExistingVideoThumbnailUrl,
      'newFilePaths': [
        for (final f in _mediaNewFiles) LocalMedia.remember(f).path,
      ],
      'coverPick': _mediaCoverPick == null
          ? null
          : {
              'existingImageUrl': _mediaCoverPick!.existingImageUrl,
              'isExistingVideo': _mediaCoverPick!.isExistingVideo,
              'newImageOrdinal': _mediaCoverPick!.newImageOrdinal,
              'isNewVideo': _mediaCoverPick!.isNewVideo,
            },
      'basicCardVideoFocalX': _mediaBasicCardFocalX,
      'basicCardVideoFocalY': _mediaBasicCardFocalY,
      'basicCardVideoScale': _mediaBasicCardScale,
      'mediaVideoCropConfirmed': _mediaVideoCropConfirmed,
      'basicCardPhotoCrops': _mediaPhotoCrops,
      // 상세 이미지(선택) — 업로드된 URL과 아직 안 올린 로컬 파일 경로를 모두
      // 담는다(대표 미디어와 같은 규칙).
      'detailImage': _detailImage.toDraftMap(),
      // 상세 설명 방식·블록
      'descriptionMode': _descriptionMode.name,
      'autoDescriptionStyle': _autoDescriptionStyle.toMap(),
      'detailBlocks': PartyDetailBlock.listToMaps(
        _detailBlocks.map((d) => d.toBlock()).toList(),
      ),
      // 상세 블록의 "아직 업로드 안 된 로컬 파일" 경로 — 블록 id별.
      'detailBlockLocalFiles': {
        for (final d in _detailBlocks)
          if (d.newImageFile != null || d.newVideoFile != null)
            d.id: {
              'image': d.newImageFile == null
                  ? null
                  : LocalMedia.remember(d.newImageFile!).path,
              'video': d.newVideoFile == null
                  ? null
                  : LocalMedia.remember(d.newVideoFile!).path,
            },
      },
      'detailTheme': _detailTheme.name,
      'detailDecorationIntensity': _detailDecorationIntensity.name,
      'detailDecorationVariantSeed': _detailDecorationVariantSeed,
    };
  }

  /// 임시저장 payload로 화면 상태 전체를 복원한다. 복원 도중에는
  /// _draftReady=false라 자동저장이 예약되지 않는다(복원값을 그대로 다시
  /// 저장하는 낭비/무한루프 방지).
  void _applyDraftPayload(Map<String, dynamic> p) {
    _inquiryEnabled = ListingInquiry.isEnabled(p);
    _inquiryGuideController.text = ListingInquiry.guideOf(p);
    String s(String key) => (p[key] as String?) ?? '';
    _partyNameController.text = s('titleText');
    _introController.text = s('introText');
    _partychuPerkController.text = s(kPartychuPerkField);
    _detailAddressController.text = s('detailAddressText');
    _maleFeeController.text = s('maleFeeText');
    _femaleFeeController.text = s('femaleFeeText');
    _earlyBirdPercentController.text = s('earlyBirdPercentText');
    _capacityController.text = s('capacityText');
    _minCapacity = (p['minCapacity'] as num?)?.toInt() ?? 0;
    _setRound1MinCapacity((p['round1MinCapacity'] as num?)?.toInt() ?? 0);
    _minCapacityPolicy = PartyMinCapacityPolicy.fromKey(
      p['minCapacityPolicy'] as String?,
    );
    _maleCapacityController.text = s('maleCapacityText');
    _femaleCapacityController.text = s('femaleCapacityText');

    final place = p['place'] as Map?;
    _selectedPlace = place == null
        ? null
        : AddressResult(
            placeName: place['placeName'] as String? ?? '',
            address: place['address'] as String? ?? '',
            roadAddress: place['roadAddress'] as String? ?? '',
            jibunAddress: place['jibunAddress'] as String? ?? '',
            latitude: (place['latitude'] as num?)?.toDouble() ?? 0,
            longitude: (place['longitude'] as num?)?.toDouble() ?? 0,
          );

    // 내 공간 연결도 임시저장에서 되살린다 — 안 하면 "이어서 작성"으로 열었을
    // 때만 연결이 조용히 사라져 등록/재등록과 또 어긋난다.
    //
    // 진입에서 공간을 미리 골라 들어왔더라도(initialSpace) **임시저장 쪽이
    // 이긴다** — 복구는 "그때 쓰던 화면을 그대로 되돌리는" 동작이라, 진입
    // 선택만 남으면 주소는 임시저장 값인데 연결은 다른 공간을 가리키게 된다.
    _linkTarget = _linkTargetFromName(p['linkTarget'] as String?);
    _linkedEventId = p['linkedEventId'] as String?;
    _linkedPlaceData = null;
    if (_linkedEventId != null) _loadLinkedPlaceForPrefill();

    _genderLimit = p['genderLimit'] as String? ?? 'all';
    _genderCapacityMode = p['genderCapacityMode'] as String? ?? 'unlimited';
    _genderMode = p['genderMode'] as String? ?? '';
    // 이 설정이 없던 예전 임시저장은 공개로 복원된다(기존 파티와 같은 규칙).
    _revealParticipantGenderRatio =
        p[ParticipantGenderVisibility.field] as bool? ??
        ParticipantGenderVisibility.defaultValue;

    _refundTiers = RefundTier.listFromDynamic(p['refundPolicy']);
    _paymentPolicy = PaymentPolicy.fromMap(
      (p['paymentPolicy'] as Map?)?.cast<String, dynamic>(),
    );
    // 신청 방식 — 필드가 없던 예전 임시저장은 즉시 확정으로 복원된다.
    final draftForm = PartyApplicationForm.fromParty(p.cast<String, dynamic>());
    _approvalMode = draftForm.mode;
    _appQuestions = [...draftForm.questions];
    // 필드가 없던 예전 임시저장은 사진 요청 꺼짐으로 복원된다.
    _requireApplicantPhotos = draftForm.requirePhotos;

    _earlyBirdEnabled = p['earlyBirdEnabled'] as bool? ?? false;
    // 종료 기준이 없던 예전 임시저장은 날짜 직접 선택으로 복원된다.
    _earlyBirdEndType = PartyEarlyBirdEndType.fromKey(
      p['earlyBirdEndType'] as String?,
    );
    final ebMs = (p['earlyBirdEndDateMs'] as num?)?.toInt();
    _earlyBirdEndDate = ebMs != null
        ? DateTime.fromMillisecondsSinceEpoch(ebMs)
        : null;
    _earlyBirdEndTime = _timeFromMap(p['earlyBirdEndTime']);
    _earlyBirdRule =
        PartyEarlyBirdDeadlineRule.fromMap(
          p['earlyBirdRecurringRule'] is Map
              ? Map<String, dynamic>.from(p['earlyBirdRecurringRule'] as Map)
              : null,
        ) ??
        const PartyEarlyBirdDeadlineRule();

    _partyTypes
      ..clear()
      ..addAll((p['partyTypes'] as List?)?.cast<String>() ?? const []);
    _vibes
      ..clear()
      ..addAll((p['vibes'] as List?)?.cast<String>() ?? const []);
    _tags = [...((p['tags'] as List?)?.cast<String>() ?? const [])];
    _region = p['region'] as String? ?? '서울';
    _district = p['district'] as String?;
    // 성별별 필드가 없는 예전 임시저장은 옛 공통 범위가 남녀 모두에게
    // 적용된 것으로 복원된다(PartyAgeRestriction.fromMap).
    _ageRestriction = PartyAgeRestriction.fromMap(p.cast<String, dynamic>());
    _existingSeriesId = p['seriesId'] as String?;

    // 일정 — 방식·날짜 슬롯·정기 규칙을 한 번에 복원한다. 예전 임시저장에
    // 있던 매주 반복 자동생성 관련 키(weeklyRepeat*)는 무시된다(읽기 오류 없음).
    _schedule = PartyScheduleDraft.fromDraftMap(p);

    // 다차수 라운드 — 기존 것을 정리하고 새로 만든다.
    for (final r in _extraRounds) {
      r.dispose();
    }
    _extraRounds.clear();
    _hasMultipleRounds = p['hasMultipleRounds'] as bool? ?? false;
    _roundCapacityMode = p['roundCapacityMode'] as String? ?? 'unified';
    _roundEarlyBirdMode = _normalizedRoundEarlyBirdMode(
      p['roundEarlyBirdMode'] as String?,
    );
    for (final raw in (p['extraRounds'] as List?) ?? const []) {
      final round = PartyRound.fromMap(raw);
      if (round != null) _extraRounds.add(PartyRoundDraft(round));
    }
    // 차수 패키지 — 없는 차수를 가리키는 패키지는 저장 시점 검증에서 걸러진다.
    _roundPackages = PartyRoundPackage.listFrom(p['roundPackages']);

    // 미디어(업로드된 URL)
    _mediaExistingImageUrls = [
      ...((p['existingImageUrls'] as List?)?.cast<String>() ?? const []),
    ];
    _mediaExistingVideoUrl = p['existingVideoUrl'] as String?;
    _mediaExistingVideoUid = p['existingVideoUid'] as String?;
    _mediaExistingVideoThumbnailUrl = p['existingVideoThumbnailUrl'] as String?;

    // 아직 업로드 안 된 로컬 파일 — 파일이 아직 있으면 되살리고, 없으면
    // 배너로 재선택을 안내한다(요구 8번).
    _mediaNewFiles = [];
    bool anyMissing = false;
    for (final path
        in (p['newFilePaths'] as List?)?.cast<String>() ?? const []) {
      if (LocalMedia.exists(path)) {
        _mediaNewFiles.add(LocalMedia.resolve(path));
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
    _mediaBasicCardFocalX =
        (p['basicCardVideoFocalX'] as num?)?.toDouble() ?? 0.5;
    _mediaBasicCardFocalY =
        (p['basicCardVideoFocalY'] as num?)?.toDouble() ?? 0.5;
    _mediaBasicCardScale =
        (p['basicCardVideoScale'] as num?)?.toDouble() ?? 1.0;
    _mediaVideoCropConfirmed = p['mediaVideoCropConfirmed'] as bool? ?? false;
    final rawCrops = p['basicCardPhotoCrops'] as Map?;
    _mediaPhotoCrops = rawCrops == null
        ? {}
        : rawCrops.map(
            (key, value) => MapEntry(key as String, {
              'x': ((value as Map)['x'] as num?)?.toDouble() ?? 0.5,
              'y': (value['y'] as num?)?.toDouble() ?? 0.5,
              'scale': (value['scale'] as num?)?.toDouble() ?? 1.0,
            }),
          );

    // 상세 이미지 — 대표 미디어와 같은 규칙으로, 로컬 파일이 사라졌으면
    // 경로만 버리고 안내 대상에 포함시킨다.
    _detailImage = PartyDetailImageDraft.fromDraftMap(
      p['detailImage'],
      missingFile: () => anyMissing = true,
    );

    // 상세 블록 — 기존 것을 정리하고 새로 만든다.
    for (final d in _detailBlocks) {
      d.dispose();
    }
    _detailBlocks = PartyDetailBlock.listFromDynamic(
      p['detailBlocks'],
    ).map((b) => PartyDetailBlockDraft.fromBlock(b)).toList();
    // 상세 블록의 로컬 파일 되살리기(있으면) — 블록 id로 매칭.
    final blockFiles = p['detailBlockLocalFiles'] as Map?;
    if (blockFiles != null) {
      for (final block in _detailBlocks) {
        final entry = blockFiles[block.id] as Map?;
        if (entry == null) continue;
        final imgPath = entry['image'] as String?;
        final vidPath = entry['video'] as String?;
        if (imgPath != null) {
          if (LocalMedia.exists(imgPath)) {
            block.newImageFile = LocalMedia.resolve(imgPath);
          } else {
            anyMissing = true;
          }
        }
        if (vidPath != null) {
          if (LocalMedia.exists(vidPath)) {
            block.newVideoFile = LocalMedia.resolve(vidPath);
          } else {
            anyMissing = true;
          }
        }
      }
    }

    _descriptionMode = partyDescriptionModeFromString(
      p['descriptionMode'] as String?,
    );
    _autoDescriptionStyle = PartyAutoDescriptionStyle.fromMap(
      p['autoDescriptionStyle'] as Map<String, dynamic>?,
    );
    _detailTheme = partyDetailThemeKeyFromString(p['detailTheme'] as String?);
    _detailDecorationIntensity = partyDetailDecorationIntensityFromString(
      p['detailDecorationIntensity'] as String?,
    );
    _detailDecorationVariantSeed =
        (p['detailDecorationVariantSeed'] as num?)?.toInt() ?? 0;

    _draftMediaNeedsReselect = anyMissing;
  }

  /// 등록 화면에 새로 들어왔을 때, 임시저장이 있으면 이어서/새로/취소를 묻는다.
  Future<void> _maybeOfferDraftRestore() async {
    if (!_isDraftEnabled) {
      _draftReady = true;
      return;
    }
    _autosaver ??= DraftAutosaver(type: DraftType.party);
    final has = await DraftService.hasDraft(DraftType.party);
    if (!mounted) {
      _draftReady = true;
      return;
    }
    if (!has) {
      _draftReady = true;
      return;
    }

    // 마이페이지 목록에서 "이어서 작성"으로 들어온 경우 — 다시 묻지 않고
    // 곧바로 복구한다.
    if (widget.autoRestoreDraft) {
      final record = await DraftService.loadDraft(DraftType.party);
      if (mounted && record != null) {
        setState(() => _applyDraftPayload(record.payload));
        if (_draftMediaNeedsReselect) {
          _showMessage('임시저장된 사진 / 동영상 일부는 다시 선택해주세요.');
        }
      }
      _draftReady = true;
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text(
          '작성 중인 내용이 있습니다',
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
        content: const Text('이어서 작성하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'new'),
            child: const Text('새로 작성'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'continue'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6FA0),
              foregroundColor: Colors.white,
            ),
            child: const Text('이어서 작성'),
          ),
        ],
      ),
    );
    if (!mounted) {
      _draftReady = true;
      return;
    }

    if (choice == 'continue') {
      final record = await DraftService.loadDraft(DraftType.party);
      if (!mounted) {
        _draftReady = true;
        return;
      }
      if (record != null) {
        setState(() => _applyDraftPayload(record.payload));
        if (_draftMediaNeedsReselect) {
          _showMessage('임시저장된 사진 / 동영상 일부는 다시 선택해주세요.');
        }
      }
    } else if (choice == 'new') {
      final confirmNew = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          content: const Text('저장된 임시저장 내용을 지우고 새로 작성할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('삭제하고 새로 작성'),
            ),
          ],
        ),
      );
      if (confirmNew == true) {
        await DraftService.deleteDraft(DraftType.party);
      }
    } else {
      // 취소 — 등록 화면을 닫고 이전(등록 유형) 화면으로 돌아간다.
      if (mounted) Navigator.of(context).maybePop();
    }
    _draftReady = true;
  }

  /// 상단 '임시저장' 버튼 — 즉시 저장 후 안내.
  Future<void> _manualSaveDraft() async {
    if (!_isDraftEnabled) return;
    _autosaver ??= DraftAutosaver(type: DraftType.party);
    await _autosaver!.flushNow(_buildDraftSnapshot);
    if (mounted) _showMessage('임시저장되었습니다');
  }

  /// 뒤로가기 시(임시저장 가능 화면) — 내용을 버리지 않고 먼저 저장한 뒤
  /// "임시저장되었습니다" 안내와 함께 나가기/계속 작성을 묻는다.
  Future<bool> _confirmLeaveWithDraftSave() async {
    // 아무것도 입력하지 않았으면 저장할 것도, 안내할 것도 없이 바로 나간다.
    if (!_dirty) return true;
    _autosaver ??= DraftAutosaver(type: DraftType.party);
    await _autosaver!.flushNow(_buildDraftSnapshot);
    if (!mounted) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          '작성 중인 내용이 임시저장되었습니다',
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
        content: const Text('나중에 이어서 작성할 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 작성'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  /// AppBar 하단의 "자동 저장됨 · HH:mm" 표시(임시저장 활성일 때만).
  PreferredSizeWidget? _buildAutoSaveIndicator() {
    final saver = _autosaver;
    if (saver == null) return null;
    return PreferredSize(
      preferredSize: const Size.fromHeight(22),
      child: ValueListenableBuilder<DateTime?>(
        valueListenable: saver.lastSavedAt,
        builder: (context, savedAt, _) {
          if (savedAt == null) return const SizedBox(height: 22);
          final synced = saver.lastSaveSynced.value;
          final hh = savedAt.hour.toString().padLeft(2, '0');
          final mm = savedAt.minute.toString().padLeft(2, '0');
          return SizedBox(
            height: 22,
            child: Center(
              child: Text(
                synced ? '자동 저장됨 · $hh:$mm' : '기기에 보관됨 · $hh:$mm',
                style: TextStyle(
                  fontSize: 11,
                  color: synced ? Colors.black45 : const Color(0xFFC26A00),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 임시저장 복구 시 로컬 파일이 사라진 사진/동영상이 있을 때의 안내 배너.
  Widget _buildMediaReselectBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD8A8)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFFC26A00)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '임시저장된 사진 / 동영상 일부는 다시 선택해주세요.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF8A5A00)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 백그라운드로 가거나 종료될 때 마지막 내용을 즉시 저장한다.
    if (!_isDraftEnabled || !_draftReady) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _autosaver?.flushNow(_buildDraftSnapshot);
    }
  }

  final _partyNameController = PartyTitleController();
  final _introController = TextEditingController();

  /// "파티츄 전용 혜택" — **파티 참가자에게 현장에서** 주는 혜택(선택 입력).
  /// 안내 문구는 매장용과 다르다([PartychuPerkAudience.party]).
  final _partychuPerkController = TextEditingController();
  final _maleFeeController = TextEditingController();
  final _femaleFeeController = TextEditingController();
  final _earlyBirdPercentController = TextEditingController();
  // 환불 규정 — 호스트가 직접 등록하는 기간별 환불률 구간. 기본값 없음.
  List<RefundTier> _refundTiers = [];

  /// 결제 방식 — null이면 설정을 남기지 않는다(기존 파티와 동일하게 참가자가
  /// 결제수단을 자유롭게 고른다). 무료 파티에서는 아예 노출하지 않는다.
  PaymentPolicy? _paymentPolicy;

  /// 신청 방식 — 기본은 즉시 확정이라 기존 등록 흐름과 똑같다.
  /// 이 두 값은 파티 문서에 직접 쓰지 않고, 저장이 끝난 뒤
  /// setPartyApplicationForm 콜러블로 보낸다(firestore.rules에서 클라이언트
  /// 쓰기가 막혀 있다 — PartyApplicationFormService 주석 참고).
  PartyApprovalMode _approvalMode = PartyApprovalMode.auto;

  /// 승인 심사용 프로필 사진을 요청할지 — **기본은 꺼짐**이다.
  /// 승인제가 아니면 의미가 없어 저장 시에도 false로 내려간다.
  bool _requireApplicantPhotos = false;
  List<PartyApplicationQuestion> _appQuestions = [];
  final _capacityController = TextEditingController();
  final _maleCapacityController = TextEditingController();
  final _femaleCapacityController = TextEditingController();
  final _detailAddressController = TextEditingController();

  /// **파티 전체**(정기 파티는 회차 하나) 최소 모집 인원. 0이면 정하지 않음.
  ///
  /// 입구는 성별·인원 시트 하나뿐이다([_openGenderCapacitySheet]). 라운드를
  /// 켜도 여기는 그대로다 — 차수마다 정하는 '차수 최소 인원'과는 뜻이 다른
  /// 값이라, 차수 값을 더해서 만들면 안 된다([PartyMinCapacity]).
  int _minCapacity = 0;
  PartyMinCapacityPolicy _minCapacityPolicy = PartyMinCapacityPolicy.proceed;

  /// **1차 차수**의 최소 인원(차수별 정원 모드에서만 뜻이 있다).
  ///
  /// 2차 이후는 각 차수 카드가 자기 값을 갖는다([PartyRoundDraft]). 1차는
  /// 카드가 따로 없고 라운드 설정 영역 위쪽 칸이 곧 1차라 여기 담는다.
  int _round1MinCapacity = 0;
  final TextEditingController _round1MinCapacityController =
      TextEditingController();

  void _setRound1MinCapacity(int value) {
    _round1MinCapacity = value;
    final text = value == 0 ? '' : '$value';
    if (_round1MinCapacityController.text != text) {
      _round1MinCapacityController.text = text;
    }
  }

  AddressResult? _selectedPlace;

  // ── 플레이스 연결 ────────────────────────────────────────────────────
  // 등록·재등록 모두 여기서 "내 플레이스"와 연결할 수 있다. 고른 시점에는
  // 파티 문서가 아직 없으므로 **화면 상태에만** 담아두고, 저장이 끝나 새 파티
  // 문서 id가 생긴 뒤에 한 번에 커밋한다(_commitPlaceLink).
  //
  // 재등록은 원본 파티의 연결(linkedEventId)을 그대로 물려받아 기본 선택된
  // 상태로 시작하고, 사용자가 이 화면에서 바꾸거나 뺄 수 있다. 어느 경우에도
  // **원본 파티의 연결은 건드리지 않는다** — 연결이 옮겨가는 게 아니라 새 파티가
  // 같은 플레이스에 추가로 붙는 것이다.
  //
  // 연결용 등록(prelink)에서는 대상이 진입 시점에 이미 정해져 있고 바꿀 수
  // 없다 — 아래 세 값이 initState에서 채워진 뒤 그대로 유지된다.
  String? _linkedEventId;
  Map<String, dynamic>? _linkedPlaceData;

  /// 임시저장에 담긴 종류 이름을 되읽는다. 이 값이 없던 예전 임시저장은
  /// 플레이스로 본다 — 그때는 화면에서 고를 수 있는 대상이 플레이스뿐이었다.
  static PartyLinkTarget _linkTargetFromName(String? name) {
    for (final t in PartyLinkTarget.values) {
      if (t.name == name) return t;
    }
    return PartyLinkTarget.place;
  }

  /// 연결 대상이 플레이스(events)인지 공간대여(places)인지.
  ///
  /// 화면에서 직접 고르는 경로([_onPlaceLinkChanged])는 예나 지금이나 플레이스
  /// 뿐이라 기본값이 place다. 공간대여는 "파티 연결 관리 → 새 파티 만들기"로만
  /// 들어오고, 그때 [PartyPrelinkTarget]이 이 값을 바꾼다.
  PartyLinkTarget _linkTarget = PartyLinkTarget.place;

  /// 재등록 진입 직후 원본의 연결 플레이스 문서를 읽어오는 중인지.
  bool _linkedPlaceLoading = false;

  /// 상단 배너에 보여줄 연결 공간 이름. 문서를 아직 못 읽었으면(재등록·임시저장
  /// 복구 직후) 종류 이름으로 버틴다 — 빈 줄이 잠깐 보이는 것보다 낫다.
  String get _linkedSpaceName {
    final name = (_linkedPlaceData?['name'] as String?)?.trim() ?? '';
    return name.isEmpty ? _linkTarget.noun : name;
  }

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

  // ── 상세 이미지(선택) — 대표 미디어와 **완전히 별개**다.
  // 대표 사진/동영상은 카드 썸네일·상단 갤러리용이고, 이 한 장은 상세 본문
  // 전용이다. 그래서 _mediaExistingImageUrls/_mediaNewFiles에 절대 섞지
  // 않는다(섞으면 대표 판정과 갤러리 순서가 흔들린다 — PartyDetailImage 주석).
  PartyDetailImageDraft _detailImage = PartyDetailImageDraft.empty;

  // 상세 설명 방식 — 간편 자동 꾸미기(auto) / 직접 상세페이지 만들기(blocks)
  // 중 하나만 실제로 렌더링된다. 기본값은 auto(일반 사용자 기본 추천).
  PartyDescriptionMode _descriptionMode = PartyDescriptionMode.auto;
  PartyAutoDescriptionStyle _autoDescriptionStyle =
      const PartyAutoDescriptionStyle();

  // 파티 상세페이지 블록("직접 상세페이지 만들기"를 골랐을 때만 쓰인다) —
  // 모드를 auto로 바꿔도 지우지 않고 그대로 들고 있다가, 다시 blocks로
  // 돌아오면 이어서 편집할 수 있게 한다.
  List<PartyDetailBlockDraft> _detailBlocks = [];
  PartyDetailThemeKey _detailTheme = PartyDetailThemeKey.partychu;
  PartyDetailDecorationIntensity _detailDecorationIntensity =
      PartyDetailDecorationIntensity.standard;
  int _detailDecorationVariantSeed = 0;

  /// 게스트 문의 받기 — 플레이스·장소대여와 **같은 필드**(inquiryEnabled) 하나다.
  /// 등록 기본값은 ON([ListingInquiry.defaultEnabled]).
  bool _inquiryEnabled = ListingInquiry.defaultEnabled;

  /// 문의 전 안내문 — 문의 받기가 ON일 때만 입력란이 보인다.
  final _inquiryGuideController = TextEditingController();

  bool _isUploading = false;
  String _uploadStatus = '';

  // 필수항목 에러 표시 — 각 SectionSummaryRow의 빨간 테두리를 켠다.
  bool _showAddressError = false;

  /// 등록 버튼을 눌렀을 때 비어 있던 필수 항목들(상단 배너용) — 각 줄을 누르면
  /// 해당 입력칸으로 이동한다.
  List<RegisterFieldCheck> _missingFields = const [];

  bool _showDateError = false;
  bool _showCapacityError = false;
  bool _showFeeError = false;
  bool _showIntroError = false;
  bool _showMediaCoverError = false;
  // 환불 규정 최소 1개 — 판정은 공용 규칙([RefundPolicyRule])이 한다.
  bool _showRefundError = false;
  bool _showDetailBlocksError = false;

  // ── 라운드 섹션 오류 ────────────────────────────────────────────────
  // 예전에는 "라운드(차수) 정보를 확인해주세요" 한 줄만 띄우고 정작 라운드
  // 섹션에는 아무 표시도 하지 않아서(스크롤도 엉뚱하게 모집 인원 행으로
  // 갔다) 무엇을 고쳐야 하는지 알 수 없었다. 이제 어느 라운드의 어느
  // 칸이 비었는지까지 들고 있다가 그 칸을 빨갛게 칠한다.
  bool _showRoundsError = false;

  /// 라운드 카드 안(2차 이상)의 문제만 담는 섹션 헤더 문구.
  String? _roundsErrorText;

  /// 상단 배너·스낵바에 쓸 문구 — 라운드별 정원 모드에서 1차(위쪽 모집 인원/
  /// 참가비 섹션)가 비어 있는 경우까지 포함한다.
  String? _roundsMessage;
  Map<String, List<PartyRoundIssue>> _roundErrors = const {};

  /// 검증에 걸린 첫 라운드 카드의 앵커 — 없으면 라운드 섹션 전체로 이동한다.
  GlobalKey? _roundsErrorAnchor;

  // 스크롤 + 에러 위치 이동용 키
  final ScrollController _scrollController = ScrollController();

  /// 필수항목 안내의 모든 줄이 **같은 스크롤 목록**을 움직인다 — 본문이
  /// [ListView]라 화면 밖 섹션은 아직 만들어지지도 않았기 때문이다. 컨트롤러를
  /// 넘겨야 [RegisterValidation.goTo]가 그 위젯이 만들어질 때까지 목록을 훑어
  /// 내려간다([RegisterFieldCheck.scrollController]).
  ScrollController get _formScrollCtrl => _scrollController;

  /// 파티명 칸 — 이동한 뒤 곧바로 입력할 수 있게 커서를 놓는다.
  final FocusNode _partyNameFocus = FocusNode();
  final GlobalKey _keyPartyName = GlobalKey();
  final GlobalKey _keyAddress = GlobalKey();
  final GlobalKey _keyDateTime = GlobalKey();
  final GlobalKey _keyRounds = GlobalKey();
  final GlobalKey _keyCapacity = GlobalKey();
  final GlobalKey _keyFee = GlobalKey();
  final GlobalKey _keyIntro = GlobalKey();
  final GlobalKey _keyMedia = GlobalKey();
  final GlobalKey _keyRefund = GlobalKey();

  // ── 일정 ─────────────────────────────────────────────────────────────
  // 일정 방식(날짜 직접 선택 / 매주 반복)과 그에 딸린 입력을 한 값으로 들고
  // 있다. 플레이스+파티·숙박+파티 등록 화면도 같은 [PartyScheduleDraft]와
  // [PartyScheduleSection]을 쓴다 — 일정 관련 기능은 그쪽에만 추가하면 세
  // 화면에 함께 반영된다.
  //
  // "날짜 직접 선택"의 슬롯은 각각 독립된 Firestore 문서가 된다(_submit 참고).
  // index 0 슬롯이 항상 "기준"이며, 수정 모드에서는 그 슬롯이 기존 문서를
  // 그대로 업데이트한다.
  PartyScheduleDraft _schedule = PartyScheduleDraft.empty();

  // 아래 게터들은 화면 곳곳의 읽기 코드가 예전 이름을 그대로 쓰게 해준다 —
  // 값의 단일 출처는 항상 _schedule이다.
  PartyScheduleType get _scheduleType => _schedule.type;
  PartyRecurringSchedule get _recurringSchedule => _schedule.recurring;
  List<PartyDateSlot> get _dateSlots => _schedule.slots;
  PartyRecruitDeadlineRule get _deadlineRule => _schedule.deadlineRule;
  bool get _isRecurring => _schedule.isRecurring;
  // 이 화면(수정 모드)이 속한 "시리즈"(한 번의 등록에서 나온 날짜 문서
  // 묶음) id. prefill에서 복원하고, 없으면(레거시 문서) 제출 시
  // existingDocId로 대체한다 — 10개 제한을 "게시글" 단위로 세는 데 쓰인다.
  String? _existingSeriesId;

  // ── 다차수(1차/2차/3차) 라운드 ────────────────────────────────────────
  // 1차는 위 _dateSlots(각 날짜의 시작 시간)와 정원/참가비 컨트롤러가 그대로
  // 담당하고, 여기 _extraRounds는 2차부터만 관리한다(RoundListEditor 참고).
  bool _hasMultipleRounds = false;
  String _roundCapacityMode = 'unified'; // 'unified' | 'perRound'

  /// 라운드 진행 파티의 얼리버드 적용 방식 — 'none' | 'uniform' | 'perRound'.
  ///
  /// **계산에는 쓰이지 않는다.** 어느 쪽을 고르든 저장되는 것은 각 차수의
  /// 얼리버드 규칙이고(`uniform`이면 같은 규칙을 모든 차수에 복사한다), 할인
  /// 금액은 서버·앱 모두 **그 차수 자신의 참가비**로 계산한다. 이 값은 수정·
  /// 재등록에서 화면을 원래 모양으로 되살리기 위한 표식이다.
  String _roundEarlyBirdMode = 'none';

  /// 차수 패키지("1+2차 통합권") — 차수별 정원·참가비 모드에서만 쓴다.
  /// 비어 있으면 패키지를 팔지 않는 것이다.
  List<PartyRoundPackage> _roundPackages = [];

  /// 패키지 id → 검증 문구.
  Map<String, String> _packageErrors = const {};
  final List<PartyRoundDraft> _extraRounds = [];

  /// 차수 카드가 "실제 일시"와 상태를 계산할 때 쓰는 기준 날짜 — 날짜 직접
  /// 선택은 가장 이른 일정, 매주 반복은 다음 회차의 날짜다.
  DateTime? get _roundReferenceDate {
    if (_isRecurring) {
      final occ = _recurringSchedule.nextOccurrence(DateTime.now());
      return occ == null
          ? null
          : DateTime(occ.start.year, occ.start.month, occ.start.day);
    }
    final ready = _dateSlots.where((s) => s.startTime != null).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return ready.isEmpty ? null : ready.first.date;
  }

  /// 1차 — 위 일정·모집 마감·정원·참가비·얼리버드 섹션이 곧 1차 설정이다.
  /// '1차 설정 복사'와 1차 상태 뱃지가 이 값을 읽는다.
  PartyRound? get _primaryRound {
    final slot = _isRecurring
        ? _recurringSchedule.nextOccurrence(DateTime.now())
        : null;
    final TimeOfDay? start;
    final TimeOfDay? end;
    if (_isRecurring) {
      if (slot == null) return null;
      start = TimeOfDay.fromDateTime(slot.start);
      end = TimeOfDay.fromDateTime(slot.end);
    } else {
      final ready = _dateSlots.where((s) => s.startTime != null).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      if (ready.isEmpty) return null;
      start = ready.first.startTime;
      end = ready.first.endTime;
    }
    final int male = int.tryParse(_maleCapacityController.text.trim()) ?? 0;
    final int female = int.tryParse(_femaleCapacityController.text.trim()) ?? 0;
    return PartyRound(
      id: 'primary',
      label: '1차',
      startTime: start!,
      endTime: end,
      openRule: _isRecurring ? _recurringSchedule.openRule : _schedule.openRule,
      closeRule: _isRecurring
          ? _recurringSchedule.deadlineRule
          : _schedule.deadlineRule,
      minCapacity: _minCapacity,
      maxCapacity: int.tryParse(_capacityController.text.trim()) ?? 0,
      maleCapacity: male,
      femaleCapacity: female,
      maleFee: int.tryParse(_maleFeeController.text.trim()) ?? 0,
      femaleFee: int.tryParse(_femaleFeeController.text.trim()) ?? 0,
      earlyBird: _earlyBird,
    );
  }

  // ── 얼리버드 할인 ─────────────────────────────────────────────────
  bool _earlyBirdEnabled = false;
  DateTime? _earlyBirdEndDate;
  TimeOfDay? _earlyBirdEndTime;

  /// 얼리버드 종료 기준 — 날짜 직접 선택 / 파티 시작 전.
  /// (정기 파티는 고정 날짜를 쓸 수 없어 모델이 항상 '파티 시작 전'으로 본다.)
  PartyEarlyBirdEndType _earlyBirdEndType = PartyEarlyBirdEndType.fixedDate;

  /// '파티 시작 전' 기준의 상대 규칙(N일 전 / N시간 전).
  PartyEarlyBirdDeadlineRule _earlyBirdRule =
      const PartyEarlyBirdDeadlineRule();

  /// 정기 파티를 일회성으로 복사해 와서, 얼리버드 종료일을 새로 골라야 하는
  /// 상태인지 — 첫 프레임에 한 번 안내한다.
  bool _earlyBirdNeedsNewEndDate = false;

  final Set<String> _partyTypes = {};
  final Set<String> _vibes = {};
  String _region = '서울';
  String? _district;

  /// 연령 제한 — **성별마다 따로** 정한다([PartyAgeRestriction]). 화면에는
  /// 항상 나이로만 노출되고(_ageSummary()), 저장은 출생연도로 한다.
  PartyAgeRestriction _ageRestriction = PartyAgeRestriction.off;

  /// all/male/female
  String _genderLimit = 'all';

  /// separate(남녀별 정원 따로) / unlimited(전체 인원만)
  String _genderCapacityMode = 'unlimited';

  /// 게스트에게 현재 참가자의 남/여 인원을 보여줄지 — 기본은 공개.
  bool _revealParticipantGenderRatio = ParticipantGenderVisibility.defaultValue;

  /// 성비 맞춤일 때 'balanced', 그 외 빈 문자열
  String _genderMode = '';

  List<String> _tags = [];

  @override
  void initState() {
    super.initState();
    _loadBusinessVerification();
    final source = widget.sourceData;
    if (source != null) {
      _prefill(source);
      // 원본에 플레이스 연결이 있으면 그 플레이스 문서를 읽어와 기본 선택
      // 상태로 만든다(_prefill에서 id만 먼저 세워둔다).
      if (_linkedEventId != null) _loadLinkedPlaceForPrefill();
    }
    // "파티 연결 관리 → 새 파티 만들기" 진입 — 대상이 이미 정해져 있으므로
    // 문서를 읽으러 갈 것도, 사용자에게 고르라고 할 것도 없다. 장소 정보를
    // 대상 값으로 채워두면 등록 폼의 나머지는 일반 등록과 완전히 같다.
    final prelink = widget.prelink;
    if (prelink != null) {
      _linkTarget = prelink.target;
      _linkedEventId = prelink.targetId;
      _linkedPlaceData = prelink.data;
      // setState 없이 값만 세운다 — 아직 첫 빌드 전이다.
      _applyLinkedPlaceLocation(prelink.data);
    }
    // "내 플레이스에서 여는 파티"로 들어온 새 등록 — 고른 공간을 연결 항목의
    // **초기 선택**으로 세운다. prelink와 달리 잠기지 않으므로, 이 뒤로는
    // 사용자가 화면에서 직접 고른 것과 똑같이 다뤄진다.
    final initialSpace = widget.initialSpace;
    if (initialSpace != null) {
      _linkTarget = initialSpace.target;
      _linkedEventId = initialSpace.targetId;
      _linkedPlaceData = initialSpace.data;
      // setState 없이 값만 세운다 — 아직 첫 빌드 전이다.
      _applyLinkedPlaceLocation(initialSpace.data);
    }
    // 정기 파티를 일회성으로 복사해 왔다면 얼리버드 종료일이 비어 있다 —
    // 저장 단계에서 막히기 전에 먼저 알려준다.
    if (_earlyBirdNeedsNewEndDate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '정기 파티의 얼리버드 기준은 일회성 파티에 그대로 쓸 수 없어요. 종료 날짜·시간을 새로 정해주세요.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 5),
          ),
        );
      });
    }
    // 프리필 이후에 붙여야 초기값을 채우는 동작 자체가 "변경"으로 잡히지
    // 않는다. TextField는 onChanged 없이도 타이핑 자체는 화면에 반영되므로
    // (컨트롤러가 스스로 다시 그림) 오버라이드한 setState만으로는 일반
    // 텍스트 입력을 놓친다 — 컨트롤러 리스너로 직접 잡는다.
    for (final c in [
      _partyNameController,
      _introController,
      _partychuPerkController,
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
    // 앱 백그라운드/종료 시 마지막 내용 저장을 위해 라이프사이클 관찰.
    WidgetsBinding.instance.addObserver(this);
    if (_isDraftEnabled) {
      _autosaver = DraftAutosaver(type: DraftType.party);
    }
    // 첫 프레임 뒤에 임시저장 복구 여부를 묻는다(빈 새 등록일 때만).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeOfferDraftRestore();
    });
  }

  // ── 사업자 인증 여부 ───────────────────────────────────────────────────
  //
  // 사업자 인증을 마치지 않은 호스트는 **오픈예정(사전등록)으로만** 등록할 수
  // 있다 — 신청·예약·결제를 받지 않는 상태다. 그래서 이 화면은 인증 여부에
  // 따라 (1) 날짜를 필수로 받을지, (2) 어떤 openState로 저장할지가 달라진다.
  //
  // 확인 전(로딩 중)에는 미인증으로 본다 — 아직 모르는 상태를 "인증됨"으로
  // 가정하면 규칙에 걸려 저장이 통째로 실패한다.
  bool _businessVerified = false;

  /// 사업자 인증을 안 마쳤으면 오픈예정으로만 등록된다.
  bool get _preopenRequired => !_businessVerified;

  Future<void> _loadBusinessVerification() async {
    final v = await BusinessVerificationService.fetch();
    if (!mounted) return;
    setState(() => _businessVerified = v.isVerified);
  }

  /// 오픈예정으로 등록된다는 사실을 등록 **시작 전에** 알리는 배너.
  Widget _buildPreopenNotice() => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEEF2FF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFC7D2FE)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.schedule_outlined, size: 18, color: Color(0xFF4F46E5)),
            SizedBox(width: 6),
            Text(
              '오픈예정으로 등록돼요',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4F46E5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '지금은 신청·예약·결제를 받지 않고 파티를 미리 알리는 단계예요. '
          '사람들은 "오픈 알림 받기"를 눌러둘 수 있고, 나중에 모집을 열면 그분들께 한 번에 알려드려요.\n'
          '제목·사진·소개·장소·참가비는 지금 다 채워둘 수 있고, 나중에 같은 게시물을 '
          '수정해서 그대로 오픈하면 돼요(새로 만들 필요 없어요).',
          style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF3730A3)),
        ),
      ],
    ),
  );

  // 예전에는 여기에 _loadSeriesSlots()가 있었다 — 같은 seriesId의 형제 날짜
  // 문서를 읽어와 슬롯에 이어 붙이는 함수로, "기존 문서를 그대로 다시 열어
  // 덮어쓰던" 옛 재등록 방식에서만 의미가 있었다. 재등록이 항상 새 문서를
  // 만드는 지금은 원본의 날짜를 물려받을 이유가 없으므로(날짜·시간은 새로
  // 고른다) 통째로 삭제했다.

  /// 재등록 진입 시 원본이 연결해 둔 플레이스 문서를 읽어와 기본 선택 상태로
  /// 만든다.
  ///
  /// 문서 전체가 필요하다 — 저장 마무리의 [PlacePartyLink.linkParties]가
  /// 소유자(hostId)를 검사하고 장소 필드를 파티에 복사하기 때문이다. 파티
  /// 문서에 남아 있는 placeSnapshot만으로는 부족하다.
  Future<void> _loadLinkedPlaceForPrefill() async {
    final eventId = _linkedEventId;
    if (eventId == null) return;
    // initState에서 동기적으로 불리는 경로가 있으므로 여기서는 setState를 쓰지
    // 않는다(첫 빌드 도중 markNeedsBuild를 부르게 된다). 값만 세워두면 첫
    // 빌드가 "불러오는 중" 상태를 그대로 그리고, 아래 await가 끝난 뒤의
    // _setStateQuiet이 결과를 다시 그린다.
    _linkedPlaceLoading = true;
    try {
      // 컬렉션은 종류가 정한다 — 'events'로 굳혀 두면 공간대여에 연결해 둔
      // 재등록·임시저장이 "문서를 찾을 수 없다"로 조용히 풀린다.
      final snap = await FirebaseFirestore.instance
          .collection(_linkTarget.collection)
          .doc(eventId)
          .get();
      if (!mounted) return;
      final data = snap.data();
      if (data == null || data['isDeleted'] == true) {
        // 연결했던 공간이 사라졌다 — 연결 없이 진행한다. 주소는 이미 프리필된
        // 값이 남아 있으므로 등록 자체는 그대로 할 수 있다.
        _setStateQuiet(() {
          _linkedEventId = null;
          _linkedPlaceData = null;
          _linkedPlaceLoading = false;
        });
        _showMessage('연결했던 ${_linkTarget.noun}을 찾을 수 없어 연결 없이 시작합니다.');
        return;
      }
      _setStateQuiet(() {
        _linkedPlaceData = data;
        _linkedPlaceLoading = false;
      });
    } catch (e) {
      debugPrint('[$_logTag] 연결 플레이스 조회 실패: $e');
      if (!mounted) return;
      _setStateQuiet(() {
        _linkedEventId = null;
        _linkedPlaceData = null;
        _linkedPlaceLoading = false;
      });
    }
  }

  /// 플레이스 연결 섹션에서 고르거나 해제했을 때.
  ///
  /// 플레이스를 고르면 장소 정보(주소·좌표·상세주소)를 그 플레이스 값으로
  /// 맞춘다 — 연결해 놓고 주소만 다른 곳을 가리키면 지도와 목록이 어긋난다.
  /// 해제할 때는 주소를 그대로 둔다(직접 입력한 장소로 계속 쓰겠다는 뜻).
  void _onPlaceLinkChanged(PartyPrelinkTarget? picked) {
    if (picked == null) {
      setState(() {
        _linkedEventId = null;
        _linkedPlaceData = null;
        // 종류는 기본값으로 되돌린다 — 남겨두면 다음에 연결 없이 저장할 때
        // 실패 안내(_linkRetryGuide)만 엉뚱한 화면을 가리킨다.
        _linkTarget = PartyLinkTarget.place;
      });
      _showMessage('공간 연결을 해제했어요. 장소는 직접 입력한 값으로 등록됩니다.');
      return;
    }

    setState(() {
      // 종류를 함께 세워야 저장 마무리가 올바른 연결 필드
      // (linkedEventId / linkedPlaceId)에 쓴다.
      _linkTarget = picked.target;
      _linkedEventId = picked.targetId;
      _linkedPlaceData = picked.data;
      _applyLinkedPlaceLocation(picked.data);
    });
    _showMessage('${picked.target.noun}와 연결했어요. 장소 정보를 가져왔습니다.');
  }

  /// 연결 대상(플레이스·공간대여) 문서의 장소 정보를 폼의 장소 항목에 옮긴다.
  ///
  /// **setState를 부르지 않는다** — 부르는 쪽이 setState 안에서 쓰거나(선택),
  /// 첫 빌드 전 initState에서 쓴다(연결용 등록). 복사하는 값은 연결이 실제로
  /// 커밋될 때 [PlacePartyLink.placeLocationFields]가 파티 문서에 쓰는 것과
  /// 같은 묶음이라, 화면에 보이는 주소와 저장되는 주소가 어긋나지 않는다.
  void _applyLinkedPlaceLocation(Map<String, dynamic> place) {
    final fields = PlacePartyLink.placeLocationFields(place);
    final address = fields['address'] as String? ?? '';
    _selectedPlace = AddressResult(
      placeName: fields['placeName'] as String? ?? '',
      address: address,
      roadAddress: fields['roadAddress'] as String? ?? '',
      jibunAddress: fields['jibunAddress'] as String? ?? '',
      latitude: (fields['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (fields['longitude'] as num?)?.toDouble() ?? 0.0,
    );
    final detail = (fields['detailAddress'] as String? ?? '').trim();
    if (detail.isNotEmpty) _detailAddressController.text = detail;
    _showAddressError = false;
    if (address.isNotEmpty) {
      _region = RegionData.extractRegion(address);
      _district = RegionData.extractDistrict(address, region: _region);
    }
  }

  /// 파티 문서가 만들어진 **뒤에** 플레이스 연결을 한 번 시도한다.
  ///
  /// 실패해도 예외를 던지지 않는다 — 파티 문서는 이미 저장됐고, 여기서 예외를
  /// 올리면 바깥 catch가 "등록 실패"로 안내해 사용자가 같은 파티를 또 등록하게
  /// 된다. 실패 사유만 돌려주고 후속 안내는 [_handlePlaceLinkFailure]가 맡는다.
  ///
  /// 반환값이 null이면 성공(또는 연결할 게 없음), null이 아니면 실패 사유다.
  Future<String?> _tryLinkPlace(List<String> partyIds) async {
    final eventId = _linkedEventId;
    final place = _linkedPlaceData;
    if (eventId == null || place == null || partyIds.isEmpty) return null;
    try {
      await PlacePartyLink.linkParties(
        targetId: eventId,
        place: place,
        partyIds: partyIds,
        hostId: UserSession.userId,
        target: _linkTarget,
      );
      debugPrint('[$_logTag] ${_linkTarget.noun} 연결 성공 (${partyIds.length}건)');
      return null;
    } on StateError catch (e) {
      debugPrint('[$_logTag] 플레이스 연결 실패: ${e.message}');
      return e.message;
    } catch (e) {
      debugPrint('[$_logTag] 플레이스 연결 실패: $e');
      return '잠시 후 다시 시도해주세요.';
    }
  }

  /// 파티 등록은 성공했지만 플레이스 연결만 실패했을 때의 안내와 **1회 재시도**.
  ///
  /// 화면을 닫기 전에 모달로 띄운다 — 스낵바로 알리면 곧바로 이어지는
  /// `Navigator.popUntil`에 묻혀 사라지고, 사용자는 연결이 안 된 사실조차
  /// 모른 채 나가게 된다.
  ///
  /// 재시도는 **이미 만들어진 [partyIds]를 그대로** 다시 연결할 뿐이다. 파티
  /// 문서를 다시 만들지 않으므로 몇 번을 눌러도 중복 등록이 생기지 않는다.
  ///
  /// 반환값은 **결국 연결됐는지** — 연결용 등록(prelink)은 이 값으로 부른
  /// 화면에 "연결된 파티가 늘었는지"를 알린다.
  Future<bool> _handlePlaceLinkFailure(
    List<String> partyIds,
    String reason,
  ) async {
    if (!mounted) return false;
    // 저장은 이미 끝났으므로 "등록을 완료하고 있습니다..." 오버레이를 먼저
    // 내린다 — 안내창 뒤에 그대로 떠 있으면 아직 등록 중인 것처럼 보인다.
    // _setStateQuiet을 쓰는 이유: 여기서 일반 setState를 타면 방금 내려둔
    // _dirty가 다시 서서 이탈 방지 확인창이 뜬다.
    _setStateQuiet(() {
      _isUploading = false;
      _uploadStatus = '';
    });

    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${_linkTarget.noun} 연결 실패',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '파티 등록은 완료되었지만 ${_linkTarget.noun} 연결에 실패했습니다.\n\n'
          '$reason\n\n'
          '파티는 이미 등록되어 있으니 다시 등록하지 마세요. '
          '연결만 다시 시도할 수 있어요.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('나중에 하기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF6FA0),
            ),
            child: const Text('연결 다시 시도'),
          ),
        ],
      ),
    );
    if (!mounted) return false;

    if (retry != true) {
      _showMessage('파티 등록은 완료되었어요. $_linkRetryGuide');
      return false;
    }

    // 재시도 — 새 문서를 만들지 않고 방금 만들어진 문서만 다시 연결한다.
    final failed = await _tryLinkPlace(partyIds);
    if (!mounted) return failed == null;
    if (failed == null) {
      _showMessage('${_linkTarget.noun}와 연결했어요.');
      return true;
    }
    // 두 번째도 실패 — 더 반복하지 않고 확실한 다음 행동만 알린다.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '연결에 다시 실패했어요',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '파티 등록은 완료된 상태입니다.\n\n'
          '$failed\n\n'
          '$_linkRetryGuide',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return false;
  }

  /// 연결만 실패했을 때 "그럼 어디서 다시 하면 되는지" 한 줄 안내.
  ///
  /// 대상마다 다시 붙일 수 있는 화면이 다르다 — 플레이스는 파티 수정 화면에서
  /// 고를 수 있지만, 공간대여 연결은 그 공간대여의 "파티 연결 관리"에서만
  /// 다룬다. 없는 길을 안내하지 않도록 여기서 갈라 준다.
  String get _linkRetryGuide => switch (_linkTarget) {
    PartyLinkTarget.place => '운영 > 파티 수정 화면에서 플레이스 연결을 다시 시도해주세요.',
    PartyLinkTarget.rental => '내 등록 > 공간대여의 \'연결 파티\'에서 방금 등록한 파티를 연결할 수 있어요.',
  };

  void _prefill(Map<String, dynamic> d) {
    // 게스트 문의 받기 — 재등록은 원본의 설정을 그대로 이어받는다(필드가
    // 없던 옛 파티는 ON으로 읽힌다).
    _inquiryEnabled = ListingInquiry.isEnabled(d);
    _inquiryGuideController.text = ListingInquiry.guideOf(d);
    _partyNameController.text = d['title'] as String? ?? '';
    _introController.text = d['description'] as String? ?? '';
    _partychuPerkController.text = partychuPerkFrom(d) ?? '';
    _detailAddressController.text = d['detailAddress'] as String? ?? '';

    // 플레이스 연결 복원 — id만 먼저 세우고, 플레이스 문서 본문은 initState가
    // [_loadLinkedPlaceForPrefill]로 이어서 읽는다. 원본의 연결은 그대로 두고
    // **새 파티도 같은 플레이스에 붙도록** 기본 선택 상태로만 시작한다.
    // 재등록 — 원본의 연결을 **종류까지** 물려받는다. events만 읽으면 장소대여에
    // 연결돼 있던 파티가 재등록에서 조용히 연결을 잃는다(수정 화면과 같은 판정).
    final sourceLink = PlacePartyLink.linkOf(d);
    _linkTarget = sourceLink?.target ?? PartyLinkTarget.place;
    _linkedEventId = sourceLink?.id;

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

    // 일정 복원 — 정기 파티면 정기 규칙을 그대로 물려받는다(규칙은 "설정"이라
    // 재등록해도 그대로 쓰는 게 맞고, 실제 회차는 nextOccurrence가 앞으로의
    // 날짜로 계산한다).
    // 모집 마감 규칙도 여기서 함께 복원된다 — 저장된 규칙(recruitDeadlineRule)이
    // 있으면 그대로, 규칙이 생기기 전 문서면 저장된 마감 Timestamp를 보고 가장
    // 가까운 규칙으로 되돌린다(PartySchedule.singleDeadlineRuleOf).
    _schedule = PartyScheduleDraft.fromPartyData(d);

    // 일회성 파티의 **지나간 날짜는 물려받지 않는다.** 재등록은 "내용은 복사,
    // 모집은 새로 시작"이라 날짜·시간은 새로 고르는 값이다. 이걸 지우지 않으면
    // 과거 날짜 그대로 새 파티가 만들어져 목록에 이미 끝난 파티가 올라온다.
    // 슬롯이 비면 기존 필수값 검증이 "파티 날짜를 선택해주세요"로 잡아준다.
    if (!_schedule.isRecurring) {
      final now = DateTime.now();
      final upcoming = _schedule.slots
          .where((s) => !s.start.isBefore(now))
          .toList();
      if (upcoming.length != _schedule.slots.length) {
        _schedule = _schedule.copyWith(slots: upcoming);
      }
    }

    // 성별·인원 제한
    _genderLimit = d['genderLimit'] as String? ?? 'all';
    _genderCapacityMode = d['genderCapacityMode'] as String? ?? 'unlimited';
    _genderMode = d['genderMode'] as String? ?? '';
    // 참가자 현황 공개 — 필드가 없던 파티는 공개로 읽는다(기존 동작 유지).
    _revealParticipantGenderRatio = ParticipantGenderVisibility.of(d);

    // 인원
    // 파티 전체 최소 모집 인원 — 새 필드가 없는 옛 문서는 안전한 폴백을 탄다
    // (차수 합계로 오염된 값은 0으로 본다, [PartyMinCapacity]).
    _minCapacity = PartyMinCapacity.of(d);
    _minCapacityPolicy = PartyMinCapacityPolicy.fromKey(
      d['minCapacityPolicy'] as String?,
    );
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

    // 신청 방식 + 사전질문 — 재등록도 이전 설정을 그대로 불러온다. 필드가 없던
    // 기존 파티는 즉시 확정으로 읽히므로 지금 동작이 그대로 유지된다.
    final sourceForm = PartyApplicationForm.fromParty(
      d.cast<String, dynamic>(),
    );
    _approvalMode = sourceForm.mode;
    _appQuestions = [...sourceForm.questions];
    _requireApplicantPhotos = sourceForm.requirePhotos;

    // 결제 방식 — 파티 문서에는 최상단에 평평하게 저장돼 있다. 설정이 없던
    // 파티면 null 그대로 두어 기존 동작을 유지한다.
    _paymentPolicy = PaymentPolicy.fromMap(d.cast<String, dynamic>());

    // 얼리버드 할인 — 재등록 시 이전 설정을 그대로 불러오되, 종료일이 이미
    // 지난 값이면 꺼진 상태로 초기화한다(PartyEarlyBird.fromMap이 그 규칙을
    // 담고 있어 플레이스+파티 등록과 동일하게 동작한다).
    //
    // 정기 → 일회성으로 복사할 때(= '이 파티를 기반으로 이벤트 등록')는 회차
    // 기준 상대 규칙이 의미가 없다 — 할인율만 가져오고 종료 시각은 비워서
    // 사용자가 새로 고르게 한다(안 고르면 저장 단계에서 안내된다).
    // 정기 → 정기 복제는 규칙을 그대로 유지한다.
    final sourceWasRecurring = PartySchedule.isRecurring(d);
    var restoredEarlyBird = PartyEarlyBird.fromMap(d);
    if (sourceWasRecurring && !_isRecurring) {
      restoredEarlyBird = restoredEarlyBird.toOneOffTemplate();
      if (restoredEarlyBird.enabled) {
        _earlyBirdNeedsNewEndDate = true;
      }
    }
    if (restoredEarlyBird.enabled) {
      _earlyBirdEnabled = true;
      _earlyBirdPercentController.text = '${restoredEarlyBird.percent ?? 10}';
      _earlyBirdEndType = restoredEarlyBird.endType;
      _earlyBirdEndDate = restoredEarlyBird.endDate;
      _earlyBirdEndTime = restoredEarlyBird.endTime;
      _earlyBirdRule = restoredEarlyBird.beforeStartRule;
    }

    // 파티 유형·분위기·태그
    _partyTypes.addAll((d['partyTypes'] as List?)?.cast<String>() ?? []);
    _vibes.addAll((d['vibes'] as List?)?.cast<String>() ?? []);
    _tags = [...((d['tags'] as List?)?.cast<String>() ?? [])];

    // 나이 제한
    // 기존 파티(성별별 필드가 없는 문서)는 옛 공통 범위를 남녀 모두에게
    // 적용한 상태로 되살아난다 — 수정 화면에서 연령 제한이 사라지면 안 된다.
    _ageRestriction = PartyAgeRestriction.fromMap(d);

    // 다차수 라운드 — 재등록 시 2차 이상 라운드 구성을 그대로 불러온다.
    _hasMultipleRounds = d['hasMultipleRounds'] as bool? ?? false;
    if (_hasMultipleRounds) {
      _roundCapacityMode = d['roundCapacityMode'] as String? ?? 'unified';
      _roundEarlyBirdMode = _inferRoundEarlyBirdMode(d);
      final rawRounds = (d['rounds'] as List?) ?? [];
      for (final raw in rawRounds) {
        final m = Map<String, dynamic>.from(raw as Map);
        if ((m['roundNumber'] as num?)?.toInt() == 1) {
          // 1차는 카드가 따로 없다 — 정원·참가비는 위에서 문서 최상단 값으로
          // 이미 복원됐고, **차수 최소 인원만** 1차 칸에 따로 담는다
          // (파티 전체 최소 모집 인원과 다른 값이다).
          _setRound1MinCapacity((m['minCapacity'] as num?)?.toInt() ?? 0);
          continue;
        }
        final round = PartyRound.fromMap(m);
        if (round != null) _extraRounds.add(PartyRoundDraft(round));
      }
      // 차수 패키지도 그대로 가져온다. 재등록에서 차수 구성을 줄이면 없어진
      // 차수를 가리키게 되는데, 그때는 저장 검증(_validatePackages)이 막고
      // 사용자가 포함 차수를 다시 고르게 한다 — 조용히 버리지 않는다.
      _roundPackages = PartyRoundPackage.listFrom(d['roundPackages']);
    }

    // 지역 (저장된 region/district 우선, 없으면 주소에서 자동 추출)
    // isRecurring은 더는 화면에서 읽지 않는다 — 이 화면을 거치는 모든
    // 문서는 이제 항상 true로 저장된다(_submit() 참고).
    //
    // seriesId는 **일부러 물려받지 않는다.** 재등록으로 만들어지는 파티는 원본과
    // 별개의 새 게시글이므로 새 seriesId를 발급받아야 한다. 물려받으면 원본
    // 날짜 문서들과 한 묶음이 되어, 나중에 "전체 일정 삭제"가 원본까지 지운다.
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

    // 재등록 시 상세 이미지도 그대로 이어받는다 — 원본과 같은 R2 URL을
    // 가리킬 뿐이라 파일을 새로 올리지 않는다(원본을 나중에 지워도 이 URL은
    // 서버 정리 대상에 함께 들어 있으므로, 원본 삭제 시 함께 사라진다는 점은
    // 대표 사진과 동일하다).
    _detailImage = PartyDetailImageDraft.fromPartyData(d);

    // 재등록 시 이전 상세페이지 블록 구성을 그대로 불러온다.
    _detailBlocks = PartyDetailBlock.listFromDynamic(
      d['detailBlocks'],
    ).map((b) => PartyDetailBlockDraft.fromBlock(b)).toList();
    // 재등록 시 이전 디자인 테마 선택을 그대로 불러온다. 없거나 알 수 없는
    // 값이면 partyDetailThemeKeyFromString이 partychu로 안전하게 대체한다.
    _detailTheme = partyDetailThemeKeyFromString(d['detailTheme'] as String?);
    _detailDecorationIntensity = partyDetailDecorationIntensityFromString(
      d['detailDecorationIntensity'] as String?,
    );
    // 필드가 없으면(이 기능 이전에 등록된 파티) 0 — 지금까지 암묵적으로
    // 써온 시드와 같아 회귀 없이 그대로 렌더링된다.
    _detailDecorationVariantSeed =
        (d['detailDecorationVariantSeed'] as num?)?.toInt() ?? 0;
    // 재등록 시 이전 상세 설명 방식을 그대로 불러온다. 필드가 없는(이 기능
    // 이전에 등록된) 파티는 detailBlocks 유무로 추론한다.
    final descriptionModeRaw = d['detailDescriptionMode'] as String?;
    _descriptionMode = descriptionModeRaw != null
        ? partyDescriptionModeFromString(descriptionModeRaw)
        : (_detailBlocks.isNotEmpty
              ? PartyDescriptionMode.blocks
              : PartyDescriptionMode.auto);
    _autoDescriptionStyle = PartyAutoDescriptionStyle.fromMap(
      d['autoDescriptionStyle'] as Map<String, dynamic>?,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaver?.dispose();
    _scrollController.dispose();
    _partyNameFocus.dispose();
    // 이 화면을 떠나면 강조도 함께 끈다 — 타이머가 화면보다 오래 남지 않게.
    RegisterValidation.clearHighlight();
    _partyNameController.dispose();
    _introController.dispose();
    _partychuPerkController.dispose();
    _inquiryGuideController.dispose();
    _maleFeeController.dispose();
    _femaleFeeController.dispose();
    _earlyBirdPercentController.dispose();
    _capacityController.dispose();
    _round1MinCapacityController.dispose();
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

  // 판정은 업로더와 **같은 함수 하나**를 쓴다 — 웹에서는 XFile.path가 확장자
  // 없는 blob URL이라, 여기서 경로로 다시 판정하면 동영상을 사진으로 오인해
  // 이미지 업로더로 보낸다.
  static bool _isVideoFile(XFile f) => MediaUploadService.isVideoFile(f);

  /// 등록 직전 로컬 파일 경로로 저장돼 있던 사진 크롭 값을, 업로드로 갓
  /// 발급받은 최종 URL 키로 옮겨 담는다. 기존(네트워크) 사진은 URL이 그대로
  /// 유지되므로 옮길 필요 없이 그대로 합친다.
  Map<String, Map<String, double>> _resolvePhotoCrops(_UploadResult uploaded) {
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

  /// 이미지 → Cloudflare R2, 동영상 → Cloudflare Stream.
  /// 콤보 등록 화면들과 **같은 공통 업로더**를 쓴다 — 화면마다 복사된 루프가
  /// 조금씩 달라 실패 원인을 못 찾던 문제 때문에 하나로 합쳤다.
  Future<_UploadResult> _uploadAll(List<XFile> newMedia) async {
    final upload = await MediaUploadService.uploadNewMedia(
      media: newMedia,
      logTag: 'party-media',
      onVideoStart: () => setState(() => _uploadStatus = '동영상을 올리는 중...'),
      onImageProgress: (done, total) =>
          setState(() => _uploadStatus = '사진을 올리는 중... ($done/$total)'),
    );
    return _UploadResult(
      imageUrls: upload.imageUrls,
      videoUid: upload.videoUid,
      videoUrl: upload.videoUrl,
      videoThumbnailUrl: upload.videoThumbnailUrl,
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

  /// "여러 라운드" 스위치. 켤 때 2차 카드를 하나 만들어 둔다 — 켜자마자
  /// 빈 화면이 나오면 "1차가 사라졌다"고 오해하기 쉽고, 그대로 등록하면
  /// 라운드가 1개뿐인 파티가 되기 때문이다(1차는 위 일정/정원/참가비
  /// 섹션이 담당하고 저장 시 자동으로 만들어진다).
  void _onMultipleRoundsToggled(bool enabled) {
    setState(() {
      _hasMultipleRounds = enabled;
      if (enabled) {
        // 라운드를 켜기 전에 참가비 시트에서 이미 얼리버드를 켜뒀다면 그 설정을
        // 잃지 않는다 — '모든 차수 동일'이 그 규칙을 그대로 이어받는다.
        _roundEarlyBirdMode = _earlyBirdEnabled ? 'uniform' : 'none';
        if (_earlyBirdEnabled) {
          _earlyBirdEndType = PartyEarlyBirdEndType.beforeStart;
        }
      }
      if (enabled && _extraRounds.isEmpty) {
        // 새 차수는 1차 설정을 물려받아 시작한다 — 시간만 고치면 되도록.
        final draft = PartyRoundDraft.empty();
        final primary = _primaryRound;
        if (primary != null) draft.applySettingsFrom(primary);
        _extraRounds.add(draft);
      }
      if (!enabled) {
        _showRoundsError = false;
        _roundsErrorText = null;
        _roundsMessage = null;
        _roundErrors = const {};
        _roundsErrorAnchor = null;
      }
    });
    _markDirty();
  }

  /// 라운드 카드의 값이 바뀔 때마다 — 이미 빨간 표시가 떠 있으면 다시 검사해
  /// 채운 칸의 표시를 즉시 지운다(아직 오류가 없으면 굳이 검사하지 않는다).
  void _onRoundsChanged() {
    _markDirty();
    if (_showRoundsError || _roundsMessage != null) _validateRoundsInputs();
  }

  /// 다차수 라운드 입력값 검증. 문제 없으면 true.
  ///
  /// 예전에는 첫 문제를 만나면 스낵바 한 줄만 띄우고 바로 false를 돌려줬는데,
  /// 그 스낵바는 곧바로 요약 안내에 덮여 사라지고 라운드 카드에는 아무 표시도
  /// 남지 않아 "무엇을 입력해야 하는지" 알 수 없었다. 이제는 **비어 있는 칸을
  /// 모두** 모아 [_roundErrors]에 담고(카드가 빨갛게 강조된다), 배너·스낵바에
  /// 쓸 구체적인 문구와 이동할 앵커까지 함께 세팅한다.
  bool _validateRoundsInputs() {
    if (!_hasMultipleRounds) {
      setState(() {
        _showRoundsError = false;
        _roundsErrorText = null;
        _roundsMessage = null;
        _roundErrors = const {};
        _roundsErrorAnchor = null;
      });
      return true;
    }

    final errors = <String, List<PartyRoundIssue>>{};
    String? firstMessage;
    GlobalKey? firstAnchor;

    void mark(PartyRoundDraft r, List<PartyRoundIssue> issues) {
      if (issues.isEmpty) return;
      errors.putIfAbsent(r.id, () => []).addAll(issues);
      firstMessage ??= issues.first.message;
      firstAnchor ??= r.anchorKey;
    }

    // 라운드를 켜놓고 2차를 하나도 추가하지 않으면 "여러 라운드"가 아니다 —
    // 예전에는 그대로 통과해서 라운드가 1개뿐인 파티가 저장됐다.
    if (_extraRounds.isEmpty) {
      setState(() {
        _showRoundsError = true;
        _roundsErrorText =
            '2차 라운드를 1개 이상 추가해주세요. '
            '(1차는 위에서 정한 일정·모집 인원·참가비를 그대로 사용해요)';
        _roundsMessage = '2차 라운드를 1개 이상 추가해주세요.';
        _roundErrors = const {};
        _roundsErrorAnchor = null;
      });
      return false;
    }

    final perRound = _roundCapacityMode == 'perRound';
    bool filled(TextEditingController c) => c.text.trim().isNotEmpty;

    // 차수별 검증(모집 시작<마감, 종료 시각, 정원·참가비·얼리버드)은 모델이
    // 한 곳에서 한다 — 등록 화면 두 곳이 같은 규칙을 쓴다.
    final referenceDate = _roundReferenceDate ?? DateTime.now();
    for (var i = 0; i < _extraRounds.length; i++) {
      final r = _extraRounds[i];
      mark(
        r,
        r.round.validate(
          roundNumber: i + 2,
          perRound: perRound,
          separateGender: _genderCapacityMode == 'separate',
          partyDate: referenceDate,
          isFree:
              _validateFee(_maleFeeController.text) == null &&
              (int.tryParse(_maleFeeController.text.trim()) ?? 0) == 0,
        ),
      );
    }

    // 라운드 설정 영역 안의 정원·참가비 칸 — '차수별 설정'이면 1차 카드,
    // '모든 차수 동일'이면 목록 위 공통 칸이다. 어느 쪽이든 비어 있으면 그
    // 자리를 빨갛게 켜고 라운드 섹션으로 보낸다(예전에는 바깥 줄로 보냈다).
    var firstRoundError = false;
    final where = perRound ? '1차' : '공통';
    final capacityMissing = _genderCapacityMode == 'unlimited'
        ? !filled(_capacityController)
        : (!filled(_maleCapacityController) ||
              !filled(_femaleCapacityController));
    if (capacityMissing) {
      firstRoundError = true;
      firstMessage ??= '$where 모집 인원을 입력해주세요. (라운드 설정)';
      firstAnchor ??= _keyRounds;
      setState(() => _showCapacityError = true);
    }
    final feeMissing =
        (_genderLimit != 'female' &&
            _validateFee(_maleFeeController.text) != null) ||
        (_genderLimit != 'male' &&
            _validateFee(_femaleFeeController.text) != null);
    if (feeMissing) {
      firstRoundError = true;
      firstMessage ??= '$where 참가비를 입력해주세요. (라운드 설정)';
      firstAnchor ??= _keyRounds;
      setState(() => _showFeeError = true);
    }
    // 공통 얼리버드(모든 차수 동일)와 1차 얼리버드(차수별 설정)는 둘 다 문서
    // 최상단 상태를 쓰므로 여기서 검사한다 — 2차 이후는 PartyRound.validate가
    // 카드마다 따로 검사한다.
    if (_roundEarlyBirdMode != 'none' && _earlyBirdEnabled) {
      final ebError = _validateEarlyBird();
      if (ebError != null) {
        firstRoundError = true;
        firstMessage ??= '얼리버드 — $ebError';
        firstAnchor ??= _keyRounds;
        setState(() => _showFeeError = true);
      }
    }

    // 차수 패키지 검증 — 문제가 있으면 그 패키지 카드 아래에 문구가 뜬다.
    final packageErrors = _validatePackageInputs();
    if (packageErrors.isNotEmpty) {
      firstMessage ??= packageErrors.values.first;
    }

    final hasError =
        errors.isNotEmpty || firstRoundError || packageErrors.isNotEmpty;
    setState(() {
      _roundErrors = errors;
      _packageErrors = packageErrors;
      _showRoundsError = errors.isNotEmpty || packageErrors.isNotEmpty;
      _roundsErrorText = errors.isNotEmpty ? firstMessage : null;
      // 1차만 비어 있는 경우에도 배너에는 구체적인 문구가 남아야 한다.
      _roundsMessage = hasError ? firstMessage : null;
      _roundsErrorAnchor = firstAnchor;
    });
    return !hasError;
  }

  /// 지금 화면의 차수 목록 — 패키지 편집기가 쓰는 형태. 1차는 위쪽 섹션들이
  /// 담당하므로 그 값들을 모아 넣고, 2차 이상은 각 카드의 입력값을 쓴다.
  List<RoundPackageRoundInfo> get _packageRoundInfos {
    final perRound = _roundCapacityMode == 'perRound';
    if (!_hasMultipleRounds || !perRound) return const [];
    final firstMale = int.tryParse(_maleFeeController.text.trim()) ?? 0;
    final firstFemale = int.tryParse(_femaleFeeController.text.trim()) ?? 0;
    return [
      RoundPackageRoundInfo(
        roundNumber: 1,
        roundId: 'round_1',
        label: '1차',
        maleFee: firstMale,
        femaleFee: firstFemale,
      ),
      for (var i = 0; i < _extraRounds.length; i++)
        RoundPackageRoundInfo(
          roundNumber: i + 2,
          roundId: _extraRounds[i].round.id,
          label: _extraRounds[i].round.labelFor(i + 2),
          maleFee: _extraRounds[i].round.maleFee,
          femaleFee: _extraRounds[i].round.femaleFee,
        ),
    ];
  }

  /// 남녀 참가비를 따로 받는지 — 패키지 금액 입력칸을 1개/2개로 가른다
  /// (요청: 남녀무관 가격 모드에서는 패키지 가격 하나만 입력).
  bool get _packageSeparateGenderFee =>
      _pricing.hasGenderedPrice ||
      _extraRounds.any((r) => r.round.maleFee != r.round.femaleFee);

  /// 패키지 입력 검증(패키지 id → 문구). 모델이 규칙을 갖고 있어 등록 화면
  /// 두 곳과 수정 화면이 같은 판정을 쓴다.
  Map<String, String> _validatePackageInputs() {
    if (_roundPackages.isEmpty) return const {};
    final available = _packageRoundInfos.map((r) => r.roundNumber).toList();
    final result = <String, String>{};
    for (final p in _roundPackages) {
      final error = p.validate(
        availableRoundNumbers: available,
        separateGenderFee: _packageSeparateGenderFee,
      );
      if (error != null) result[p.id] = '${p.displayName} — $error';
    }
    return result;
  }

  /// 화면의 얼리버드 입력 상태를 공통 모델로 모은다 — 검증·직렬화를 플레이스+
  /// 파티 등록과 완전히 같은 규칙으로 맞추기 위함이다.
  /// 저장된 값이 아는 값일 때만 그대로 쓴다 — 모르는 문자열이 들어오면 화면이
  /// 어느 입력도 보여주지 않는 상태가 된다.
  static String _normalizedRoundEarlyBirdMode(String? raw) =>
      (raw == 'uniform' || raw == 'perRound' || raw == 'none') ? raw! : 'none';

  /// 얼리버드 방식 표식이 없던 문서(이 기능 이전에 만든 라운드 파티)에서 화면
  /// 모양을 되살린다 — 차수에 얼리버드가 하나라도 켜져 있으면 '차수별',
  /// 문서 최상단만 켜져 있으면 '모든 차수 동일'로 본다.
  static String _inferRoundEarlyBirdMode(Map<String, dynamic> data) {
    final stored = _normalizedRoundEarlyBirdMode(
      data['roundEarlyBirdMode'] as String?,
    );
    if (data['roundEarlyBirdMode'] is String) return stored;
    final rounds = (data['rounds'] as List?) ?? const [];
    final perRoundOn = rounds.whereType<Map>().any(
      (r) => r['earlyBirdEnabled'] == true,
    );
    if (perRoundOn) return 'perRound';
    return data['earlyBirdEnabled'] == true ? 'uniform' : 'none';
  }

  PartyEarlyBird get _earlyBird => PartyEarlyBird(
    enabled: _earlyBirdEnabled,
    percent: int.tryParse(_earlyBirdPercentController.text.trim()),
    endType: _earlyBirdEndType,
    endDate: _earlyBirdEndDate,
    endTime: _earlyBirdEndTime,
    beforeStartRule: _earlyBirdRule,
  );

  /// 차수 하나에 **실제로 저장할** 얼리버드.
  ///
  /// '모든 차수 동일'이라도 저장하는 것은 규칙이지 할인된 금액이 아니다 —
  /// 같은 규칙을 모든 차수에 복사해 두면 서버·앱이 각자 그 차수의 참가비에
  /// 규칙을 적용하므로, 1차 2만원·2차 3만원에 20%면 16,000원·24,000원이 된다.
  PartyEarlyBird _roundEarlyBirdOf(PartyEarlyBird own) {
    if (!_hasMultipleRounds) return own;
    switch (_roundEarlyBirdMode) {
      case 'none':
        return const PartyEarlyBird.off();
      case 'uniform':
        // 차수는 날짜가 저마다 달라 고정 종료 시각을 쓸 수 없다.
        return _earlyBird.copyWith(endType: PartyEarlyBirdEndType.beforeStart);
      default:
        return own;
    }
  }

  /// 문서 최상단에 남길 대표 얼리버드.
  ///
  /// 목록 카드의 얼리버드 뱃지와 '얼리버드 진행중' 필터는 차수를 모르고 문서
  /// 최상단만 읽는다 — 차수별로 켠 경우에도 "이 파티에 얼리버드가 있다"는
  /// 사실이 사라지지 않도록 켜져 있는 첫 차수의 규칙을 대표로 남긴다.
  /// (실제 결제 금액은 차수별 규칙으로 계산되므로 이 값은 표시용이다.)
  PartyEarlyBird get _representativeEarlyBird {
    if (!_hasMultipleRounds) return _earlyBird;
    switch (_roundEarlyBirdMode) {
      case 'none':
        return const PartyEarlyBird.off();
      case 'uniform':
        return _earlyBird.copyWith(endType: PartyEarlyBirdEndType.beforeStart);
      default:
        if (_earlyBirdEnabled) {
          return _earlyBird.copyWith(
            endType: PartyEarlyBirdEndType.beforeStart,
          );
        }
        for (final r in _extraRounds) {
          if (r.round.earlyBird.enabled) return r.round.earlyBird;
        }
        return const PartyEarlyBird.off();
    }
  }

  /// 참가비 — 성별 제한에 따라 한쪽만 받는 경우까지 반영한 공통 모델.
  PartyPricing get _pricing => PartyPricing.gendered(
    male: _genderLimit != 'female'
        ? int.tryParse(_maleFeeController.text.trim())
        : 0,
    female: _genderLimit != 'male'
        ? int.tryParse(_femaleFeeController.text.trim())
        : 0,
  );

  /// 얼리버드 할인 입력값 검증. 문제 없으면 null 반환.
  /// 정기 파티는 고정 종료 시각이 아니라 회차 기준 규칙을 검증하고, 다음
  /// 회차의 모집 마감보다 늦게 끝나는 설정도 여기서 걸러진다.
  String? _validateEarlyBird() {
    final occurrence = _isRecurring
        ? _recurringSchedule.nextOccurrence(DateTime.now())
        : null;
    return _earlyBird.validate(
      isFree: _pricing.isFree,
      isRecurring: _isRecurring,
      occurrenceStart: occurrence?.start,
      recruitDeadline: occurrence?.deadline,
    );
  }

  Future<void> _submit() async {
    // 중복 클릭 방지 — 업로드가 이미 시작됐으면 아무것도 하지 않는다.
    if (_isUploading) return;

    // 모든 필수항목 한 번에 검증
    final formValid = _formKey.currentState!.validate();
    final addressError = _selectedPlace == null;
    final detailAddressEmpty = _detailAddressController.text.trim().isEmpty;
    // 일회성: 날짜 슬롯이 최소 1개 + 각 슬롯의 시작 시간 필요.
    // 정기: 운영 요일이 최소 1개 + 앞으로 열릴 회차가 남아 있어야 한다
    // (운영 종료일이 이미 지난 설정은 막는다).
    //
    // 오픈예정(사업자 미인증) 사전등록은 날짜를 필수로 받지 않는다 — 나중에
    // 수정 화면에서 날짜를 확정하고 모집을 오픈한다. 날짜를 **골랐다면**
    // 시작 시간은 그대로 필수다(반쯤 채운 날짜를 저장하지 않기 위함).
    final dateError = _isRecurring
        ? (!_recurringSchedule.hasEnabledDay ||
              _recurringSchedule.nextOccurrence(DateTime.now()) == null)
        : (_dateSlots.isEmpty && !_preopenRequired);
    final timeError =
        !_isRecurring &&
        !dateError &&
        _dateSlots.any((s) => s.startTime == null);
    final introError = _introController.text.trim().isEmpty;
    // 상세페이지 블록 최소 1개 필수 — "직접 상세페이지 만들기"를 고른
    // 경우에만 적용된다("간편 자동 꾸미기"에서는 블록을 아예 안 씀).
    // 내용 없는(isEmpty) 블록만 있어도 실제로는 빈 것과 같으므로 함께 걸러낸다.
    final detailBlocksError =
        _descriptionMode == PartyDescriptionMode.blocks &&
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
      _showRefundError = RefundPolicyRule.isMissing(_refundTiers);
    });

    // 인원/참가비는 자체 검증 함수가 _showCapacityError/_showFeeError를 세팅한다
    // (호출 자체가 상태를 바꾸므로 조건식 안에서 단락 평가되지 않게 먼저 부른다).
    final capacityValid = _validateCapacityInputs();
    final roundsValid = _validateRoundsInputs();

    // 화면에 나열된 순서대로 검사 — 첫 누락 항목이 곧 자동 이동 대상이다.
    // 통과하지 못하면 여기서 끝내고 업로드/로딩 상태로 들어가지 않는다.
    final checks = [
      RegisterFieldCheck(
        missing: _partyNameController.text.trim().isEmpty,
        message: '파티명을 입력해주세요.',
        anchorKey: _keyPartyName,
        focusNode: _partyNameFocus,
        scrollController: _formScrollCtrl,
      ),
      RegisterFieldCheck(
        missing: dateError || timeError,
        message: dateError
            ? (_isRecurring ? '정기 일정을 설정해주세요.' : '파티 날짜를 선택해주세요.')
            : '시작 시간을 선택해주세요.',
        anchorKey: _keyDateTime,
        scrollController: _formScrollCtrl,
      ),
      RegisterFieldCheck(
        missing: addressError || detailAddressEmpty,
        message: addressError ? '장소를 선택해주세요.' : '상세 주소를 입력해주세요.',
        anchorKey: _keyAddress,
        scrollController: _formScrollCtrl,
      ),
      // 라운드를 켜면 인원·참가비 입력이 라운드 설정 영역에 있다 — 숨어 있는
      // 줄로 보내면 "고칠 곳으로 데려간다"는 안내가 거짓말이 된다.
      RegisterFieldCheck(
        missing: !capacityValid,
        message: '모집 인원을 확인해주세요.',
        anchorKey: _hasMultipleRounds ? _keyRounds : _keyCapacity,
        scrollController: _formScrollCtrl,
      ),
      // 라운드는 "무엇이 비었는지"를 검증에서 받아 그대로 쓴다 — 예전처럼
      // 뭉뚱그린 문구로 모집 인원 행(_keyCapacity)에 보내면 정작 고칠 곳을
      // 찾을 수 없다.
      RegisterFieldCheck(
        missing: !roundsValid,
        message: _roundsMessage ?? '라운드(차수) 정보를 확인해주세요.',
        // 라운드를 끄면 이 검사 자체가 통과하므로(_validateRoundsInputs)
        // 여기 걸린다는 것은 라운드 영역이 이미 펼쳐져 있다는 뜻이다 —
        // 따로 펼칠 것이 없다.
        anchorKey: _roundsErrorAnchor ?? _keyRounds,
        scrollController: _formScrollCtrl,
      ),
      RegisterFieldCheck(
        missing: _showFeeError,
        message: '참가비를 확인해주세요.',
        anchorKey: _hasMultipleRounds ? _keyRounds : _keyFee,
        scrollController: _formScrollCtrl,
      ),
      // 환불 규정은 무료 파티도 예외가 아니다 — 규칙은 [RefundPolicyRule] 하나다.
      RegisterFieldCheck(
        missing: RefundPolicyRule.isMissing(_refundTiers),
        message: RefundPolicyRule.requiredMessage,
        anchorKey: _keyRefund,
        scrollController: _formScrollCtrl,
      ),
      RegisterFieldCheck(
        missing: introError || detailBlocksError,
        message: introError ? '파티 소개를 입력해주세요.' : '상세페이지 내용을 1개 이상 추가해주세요.',
        anchorKey: _keyIntro,
        scrollController: _formScrollCtrl,
      ),
      RegisterFieldCheck(
        missing: mediaCoverError,
        message: '대표 사진 / 동영상을 설정해주세요.',
        anchorKey: _keyMedia,
        scrollController: _formScrollCtrl,
      ),
      // 위 항목에 걸리지 않는 나머지 Form 필드(validator) 오류.
      RegisterFieldCheck(
        missing: !formValid,
        message: '입력하지 않은 항목이 있어요.',
        anchorKey: _keyPartyName,
        focusNode: _partyNameFocus,
        scrollController: _formScrollCtrl,
      ),
    ];
    setState(() => _missingFields = RegisterValidation.missingFields(checks));
    final passed = RegisterValidation.check(context, checks);
    if (!passed || !mounted) return;

    if (!CloudflareService.isConfigured) {
      // 사용자에게는 그대로 두되(설정 키 이름은 알 바가 아니다), 로그에는
      // 어떤 키가 빠졌는지 남긴다 — 이 문구만 보고는 네트워크 문제인지
      // 설정 문제인지 가릴 수 없어 원인 찾기가 매번 처음부터였다.
      CloudflareService.logMissingConfig('party-register');
      _showMessage('현재 파일 업로드 서비스를 사용할 수 없습니다. 잠시 후 다시 시도해주세요.');
      return;
    }

    setState(() {
      _missingFields = const [];
      _isUploading = true;
      _uploadStatus = '파티 등록을 준비하는 중...';
    });

    // 이번 저장에서 새로 R2/Stream에 업로드된 상세페이지 블록 사진·동영상 —
    // 이후 Firestore 저장이 실패하면 catch에서 이 목록만 롤백 삭제한다.
    final uploadedBlockImageUrls = <String>[];
    final uploadedBlockVideoUids = <String>[];

    // 실패했을 때 "어디까지 갔는지"를 로그와 사용자 문구에 함께 남기기 위한
    // 진행 단계. 사진 업로드 실패와 Firestore 저장 실패가 같은 문구로 뭉뚱그려
    // 지면 원인을 좁힐 수 없어서 단계를 나눴다.
    var stage = _SubmitStage.prepare;
    // 저장 직전까지 조립된 payload — 실패 로그에 그대로 찍는다.
    Map<String, dynamic>? lastPayload;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? UserSession.userId;

      // ── 파티 개수 제한 체크 ────────────────────────────────────────────
      // 규칙도 숫자도 안내 문구도 [RegistrationLimits] 하나에 있다 — 예전에는
      // 이 자리와 등록 진입 화면이 **서로 다른 기준으로** 셌다(여기는 게시글
      // 단위, 저쪽은 날짜 문서 단위). 날짜를 여러 개 고른 파티를 가진 계정이
      // 진입에서는 막히고 저장에서는 통과하는 구간이 실제로 있었다.
      //
      // 지금도 세는 단위는 **게시글**(seriesId)이고, 여기에 더해 이미 끝난
      // 파티는 자리를 차지하지 않는다 — 14일 뒤 자동 삭제 대기열이라
      // 그것 때문에 새 등록이 막히면 호스트가 풀 방법이 없다.
      //
      // 재등록도 그대로 적용된다. 재등록은 원본을 덮어쓰지 않고 **새 게시글을
      // 만들기 때문에** 개수가 실제로 하나 늘어난다.
      if (!await RegistrationLimits.ensure(context, RegistrationKind.party)) {
        return;
      }
      if (!mounted) return;

      // ── 1단계: 미디어 업로드(Cloudflare) ──────────────────────────────
      // Firestore 저장은 이 await가 끝난 뒤에만 시작된다 — 업로드가 실패하면
      // 예외로 빠져나가므로 URL이 null인 채로 payload에 들어갈 일이 없다.
      stage = _SubmitStage.upload;
      final newMedia = _mediaNewFiles;
      debugPrint(
        '[$_logTag:upload] new=${newMedia.length} '
        'existingImages=${_mediaExistingImageUrls.length}',
      );
      final uploaded = newMedia.isNotEmpty
          ? await _uploadAll(newMedia)
          : _UploadResult(
              imageUrls: [],
              videoUid: null,
              videoUrl: null,
              videoThumbnailUrl: null,
            );
      debugPrint(
        '[$_logTag:upload] done images=${uploaded.imageUrls.length} '
        'video=${uploaded.videoUrl != null}',
      );

      // 상세 이미지(선택) — 대표 미디어와 **따로** 올린다(결과가 images
      // 배열에 섞이면 대표 판정과 갤러리 순서가 흔들린다). 업로더는 같은
      // 공용 경로를 쓴다 — 업로드 전 검사(경로·존재·0바이트)와 실패 갈래
      // 분류를 여기서 다시 만들지 않기 위해서다. 저장 위치만 하위 폴더로
      // 바꾸므로 주입점(uploadImage)으로 폴더를 넘긴다.
      String? detailImageUrl;
      if (_detailImage.hasNewFile) {
        setState(() => _uploadStatus = '상세 이미지를 올리는 중...');
        final detailUpload = await MediaUploadService.uploadNewMedia(
          media: [_detailImage.newFile!],
          logTag: 'party-detail-image',
          uploadImage: (file) => CloudflareService.uploadImage(
            file,
            folder: PartyDetailImage.storageFolder,
          ),
        );
        detailImageUrl = detailUpload.imageUrls.isNotEmpty
            ? detailUpload.imageUrls.first
            : null;
        // 이후 단계에서 실패하면 고아가 되므로 롤백 목록에 넣는다(블록
        // 사진과 같은 목록을 쓴다 — catch에서 한 번에 정리된다).
        if (detailImageUrl != null) uploadedBlockImageUrls.add(detailImageUrl);
      }
      final detailImage = _detailImage.resolve(newUploadedUrl: detailImageUrl);

      stage = _SubmitStage.build;
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
      // 정기 파티는 날짜 슬롯 대신 "첫 회차"를 기준 슬롯 하나로 만들어 쓴다 —
      // 정원/라운드/얼리버드 등 날짜에 얽힌 기존 계산을 그대로 재사용하기
      // 위해서다. 실제 문서에는 회차별로 계산되는 recurringSchedule이 저장되고
      // (buildSlotDateFields 참고), 문서는 1개만 만들어진다.
      final firstOccurrence = _isRecurring
          ? _recurringSchedule.nextOccurrence(DateTime.now())
          : null;
      final effectiveSlots = _isRecurring
          ? [
              PartyDateSlot(
                id: newPartyDateSlotId(),
                date: DateTime(
                  firstOccurrence!.start.year,
                  firstOccurrence.start.month,
                  firstOccurrence.start.day,
                ),
                startTime: TimeOfDay.fromDateTime(firstOccurrence.start),
                endTime: TimeOfDay.fromDateTime(firstOccurrence.end),
              ),
            ]
          : _dateSlots;
      // 날짜 없이 사전등록하는 오픈예정 파티는 슬롯이 하나도 없다 — 이때는
      // 날짜에 얽힌 계산(차수 시각·마감 규칙)을 아예 건너뛴다.
      final primarySlot = effectiveSlots.isEmpty ? null : effectiveSlots.first;
      final datelessPreopen = effectiveSlots.isEmpty;

      // 인증 상태는 저장 직전에 다시 읽는다 — 화면을 열어둔 사이 인증을 마쳤을
      // 수 있고, firestore.rules가 hostBusinessVerified를 **실제 인증 상태와
      // 정확히 같은 값**일 때만 통과시키기 때문이다(오래된 값으로 쓰면 저장이
      // 통째로 거부된다).
      final verifiedNow =
          (await BusinessVerificationService.fetch()).isVerified;
      if (!mounted) return;

      // ── 다차수 라운드 — 1차(슬롯의 시작 시간 그대로) + 2차 이상
      // (_extraRounds, PartyRoundDraft.toMap이 partyDate를 받으므로 슬롯마다
      // 다시 계산할 수 있다). 정원/참가비 템플릿은 모든 날짜 슬롯이 동일하게
      // 공유하고, 오직 각 라운드의 시간(Timestamp)만 슬롯 날짜에 따라
      // 달라진다.
      // 1차는 위 섹션들이 곧 설정이므로 여기서 PartyRound 하나로 모아 2차
      // 이상과 **같은 모양**으로 저장한다 — 읽는 쪽(상세/서버)이 차수를
      // 구분해 다룰 필요가 없다.
      final perRound = _roundCapacityMode == 'perRound';
      List<Map<String, dynamic>>? buildRoundsField(
        DateTime slotDate,
        TimeOfDay slotStartTime,
        TimeOfDay? slotEndTime,
      ) {
        if (!_hasMultipleRounds) return null;
        final firstRound = PartyRound(
          id: 'round_1',
          label: '1차',
          startTime: slotStartTime,
          endTime: slotEndTime,
          openRule: _isRecurring
              ? _recurringSchedule.openRule
              : _schedule.openRule,
          closeRule: _isRecurring
              ? _recurringSchedule.deadlineRule
              : _schedule.deadlineRule,
          // 1차 **차수**의 최소 인원 — 파티 전체 최소 모집 인원(_minCapacity)과
          // 다른 값이다. 여기에 파티 값을 넣으면 예전처럼 두 값이 뒤엉킨다.
          minCapacity: _round1MinCapacity,
          maxCapacity: maxCapacity,
          maleCapacity: maleCapacity,
          femaleCapacity: femaleCapacity,
          maleFee: maleFee ?? 0,
          femaleFee: femaleFee ?? 0,
          earlyBird: _roundEarlyBirdOf(_earlyBird),
        );
        return [
          firstRound.toMap(
            roundNumber: 1,
            partyDate: slotDate,
            perRound: perRound,
          ),
          for (var i = 0; i < _extraRounds.length; i++)
            _extraRounds[i].round
                .copyWith(
                  // '모든 차수 동일'이면 공통 규칙을, '사용 안 함'이면 꺼진
                  // 상태를 모든 차수가 그대로 갖는다 — 차수마다 규칙이 갈리면
                  // 화면에서 고른 방식과 실제 금액이 어긋난다.
                  earlyBird: _roundEarlyBirdOf(_extraRounds[i].round.earlyBird),
                )
                .toMap(
                  roundNumber: i + 2,
                  partyDate: slotDate,
                  perRound: perRound,
                ),
        ];
      }

      // 차수 패키지 — 포함 차수·금액은 슬롯과 무관하고, 얼리버드 종료 시각만
      // 그 슬롯의 "첫 포함 차수 시작 시각"으로 계산된다.
      List<Map<String, dynamic>> buildRoundPackagesField(
        DateTime slotDate,
        TimeOfDay slotStartTime,
      ) {
        final rounds =
            buildRoundsField(slotDate, slotStartTime, null) ?? const [];
        DateTime? startOf(int roundNumber) {
          for (final r in rounds) {
            if ((r['roundNumber'] as int?) == roundNumber) {
              final ts = r['time'];
              if (ts is Timestamp) return ts.toDate();
            }
          }
          return null;
        }

        return [
          for (final p in _roundPackages)
            p.toMap(firstRoundStart: startOf(p.normalizedRoundNumbers.first)),
        ];
      }

      // 정원 합계(aggMaxCapacity 등) 계산 기준 — 대표 슬롯 결과만 있으면
      // 충분하다(모든 슬롯이 동일한 정원 템플릿을 공유하므로).
      final roundsField = primarySlot == null
          ? null
          : buildRoundsField(
              primarySlot.date,
              primarySlot.startTime!,
              primarySlot.endTime,
            );

      // perRound 모드에서는 라운드를 모르는 기존 코드(피드 카드 등)를 위해
      // 상단 정원 필드를 라운드 전체 합계로 채운다 — 참가비는 합산 의미가
      // 없으므로(1인당 금액) 그대로 1차 값을 대표로 유지한다.
      var aggMaxCapacity = maxCapacity;
      var aggMaleCapacity = maleCapacity;
      var aggFemaleCapacity = femaleCapacity;
      // ⚠️ 최소 인원은 **합산하지 않는다.**
      //
      // 예전에는 최대 정원과 같은 방식으로 차수 최소 인원을 더해 문서 최상단
      // minCapacity에 넣었다. 1차 2명·2차 2명으로 등록한 파티가 상세에서
      // "최소 모집: 4명"으로 보인 원인이 이것이다. 정원은 자리 수라 더할 수
      // 있지만, 최소 모집 인원은 "이 파티가 열리려면 몇 명이 와야 하는가"라
      // 더할 수 있는 값이 아니다(1차·2차를 다 신청한 한 사람이 두 번 세진다).
      //
      // 파티 전체 최소 모집 인원은 호스트가 성별·인원 시트에서 직접 정한
      // [_minCapacity] 하나뿐이고, 차수별 최소 인원은 rounds[]에만 남는다.
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
      // 문서가 공유하는 값. 등록/재등록 모두 **매번 새로 발급한다** — 이 화면은
      // 항상 새 게시글을 만들기 때문이다. 재등록이 원본의 seriesId를 물려받으면
      // 원본 날짜 문서들과 한 묶음이 되어 "전체 일정 삭제"가 원본까지 지운다.
      final seriesId = FirebaseFirestore.instance
          .collection('parties')
          .doc()
          .id;

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
        // ── 두 등록 화면이 공유하는 파티 필드 묶음 ─────────────────────
        // 성별/정원·참가비·얼리버드·환불규정·연령·유형/분위기·소개가 여기서
        // 한 번에 직렬화된다(PartyRegistrationData 참고). 일정 유형 필드는
        // 이 화면이 날짜 슬롯마다 따로 계산하므로 buildSlotDateFields가 맡는다.
        ...PartyRegistrationData(
          scheduleType: _scheduleType,
          // 정기 파티는 반드시 규칙 객체까지 넘겨야 한다 — 안 넘기면
          // 회차 계산 필드(recurringSchedule/partyDateTime)가 통째로 빠진다.
          // 일회성은 날짜 슬롯마다 문서가 갈리므로 buildSlotDateFields가
          // 슬롯별 singleSchedule을 따로 채운다(여기서는 넘기지 않는다).
          recurringSchedule: _isRecurring ? _recurringSchedule : null,
          genderLimit: _genderLimit,
          genderCapacityMode: _genderCapacityMode,
          genderMode: _genderMode,
          maleCapacity: aggMaleCapacity,
          femaleCapacity: aggFemaleCapacity,
          // 파티 전체 최소 모집 인원 — 차수 합계가 아니라 호스트가 정한 값.
          minCapacity: _minCapacity,
          maxCapacity: aggMaxCapacity,
          minCapacityPolicy: _minCapacityPolicy,
          revealParticipantGenderRatio: _revealParticipantGenderRatio,
          pricing: PartyPricing.gendered(male: maleFee, female: femaleFee),
          earlyBird: _representativeEarlyBird,
          refundTiers: _refundTiers,
          paymentPolicy: _paymentPolicy,
          ageRestriction: _ageRestriction,
          partyTypes: _partyTypes,
          vibes: _vibes,
          tags: _tags,
          description: _introController.text.trim(),
        ).toFirestore(),
        // 게스트 문의 받기 — 파티·플레이스·장소대여가 같은 필드를 쓴다.
        ...ListingInquiry.toMap(_inquiryEnabled, _inquiryGuideController.text),
        'hasMultipleRounds': _hasMultipleRounds,
        if (_hasMultipleRounds) 'roundCapacityMode': _roundCapacityMode,
        // 얼리버드 적용 방식은 **화면 복원용 표식**이다 — 금액 계산은 각
        // 차수(또는 문서 최상단)의 규칙만 읽는다.
        if (_hasMultipleRounds) 'roundEarlyBirdMode': _roundEarlyBirdMode,
        // 파티츄 전용 혜택(선택) — 비워두면 빈 문자열로 남고, 상세페이지는
        // 값이 있을 때만 카드를 그린다.
        kPartychuPerkField: _partychuPerkController.text.trim(),
        'region': _region,
        'district': _district,
        'images': allImages,
        if (finalVideoUrl != null) 'videoProvider': 'cloudflare',
        if (finalVideoUid != null) 'videoUid': finalVideoUid,
        if (finalVideoUrl != null) 'videoUrl': finalVideoUrl,
        if (finalVideoThumbnailUrl != null)
          'videoThumbnailUrl': finalVideoThumbnailUrl,
        'detailAddress': _detailAddressController.text.trim(),
        // 상세 본문 전용 세로형 이미지 1장(선택) — images/videoUrl과 별개다.
        ...PartyDetailImage.toFirestore(detailImage),
        'detailBlocks': PartyDetailBlock.listToMaps(finalDetailBlocks),
        'detailTheme': _detailTheme.name,
        'detailDecorationIntensity': _detailDecorationIntensity.name,
        'detailDecorationVariantSeed': _detailDecorationVariantSeed,
        'detailDescriptionMode': _descriptionMode.name,
        'autoDescriptionStyle': _autoDescriptionStyle.toMap(),
        'recruitStatus': '모집중',
        // 오픈 상태 — recruitStatus와 별개의 독립 필드다(그 문자열에는 값을
        // 추가하지 않는다. models/party_open_state.dart 상단 주석 참고).
        //
        // 사업자 인증을 마치지 않은 호스트는 'preopen'으로만 저장할 수 있다 —
        // firestore.rules의 parties create 규칙이 같은 판정을 하므로, 여기서
        // 다른 값을 넣으면 저장 자체가 거부된다.
        // 날짜가 없는 문서는 인증 호스트라도 열 수 없다 — 인증을 갓 마친
        // 호스트가 날짜 없이 저장하는 경우까지 오픈예정으로 붙잡아 둔다.
        'openState': (verifiedNow && !datelessPreopen)
            ? PartyOpenState.open
            : PartyOpenState.preopen,
        'hostBusinessVerified': verifiedNow,
        // 날짜 미정 사전등록 표시 — 날짜 기반 검색·달력에서 빠지는 근거다.
        'dateTbd': datelessPreopen,
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
      };

      // 슬롯(날짜) 하나마다 달라지는 필드만 계산한다. 그 외(정원/참가비/
      // 사진/설명 등)는 sharedFields로 모든 날짜 문서가 동일하게 공유한다.
      // 모집 마감은 화면 전체에서 규칙 하나만 고르고(_deadlineRule), 각 슬롯
      // 자신의 시작 시각에 그 규칙을 적용해 슬롯마다 독립된 마감 시각을
      // 만든다 — 규칙 자체도 문서에 함께 남겨 수정/재등록에서 되살린다.
      Map<String, dynamic> buildSlotDateFields(PartyDateSlot slot) {
        final slotPartyDateTime = DateTime(
          slot.date.year,
          slot.date.month,
          slot.date.day,
          slot.startTime!.hour,
          slot.startTime!.minute,
        );
        final slotSchedule = slot.toSingleSchedule();
        final deadlineDateTime = _deadlineRule.resolve(
          slotSchedule.start,
          occurrenceEnd: slotSchedule.end,
        );
        final openDateTime = _schedule.openRule.resolve(
          slotSchedule.start,
          occurrenceEnd: slotSchedule.end,
        );
        return {
          'date':
              '${formatPartyDate(slot.date)} ${formatPartyTime(slot.startTime)}',
          'partyDateTime': Timestamp.fromDate(slotPartyDateTime),
          if (deadlineDateTime != null)
            'recruitDeadlineAt': Timestamp.fromDate(deadlineDateTime),
          if (_hasMultipleRounds)
            'rounds': buildRoundsField(
              slot.date,
              slot.startTime!,
              slot.endTime,
            ),
          // 차수 패키지 — 얼리버드 종료 시각 캐시가 슬롯 날짜에 따라 달라지므로
          // 슬롯마다 다시 만든다(포함 차수·금액은 모든 슬롯이 공유한다).
          if (_hasMultipleRounds && perRound && _roundPackages.isNotEmpty)
            'roundPackages': buildRoundPackagesField(
              slot.date,
              slot.startTime!,
            ),
          // 일정 유형 필드 — 정기 파티는 요일별 일정과 회차별 마감 규칙을
          // 저장하고, 위에서 채운 고정 recruitDeadlineAt은 null로 덮어쓴다
          // (회차마다 새로 계산해야 하므로 고정 마감을 남기면 안 된다).
          if (_isRecurring)
            ...PartySchedule.buildRecurringFields(_recurringSchedule)
          else
            ...PartySchedule.buildSingleFields(
              PartySingleSchedule(
                date: slot.date,
                startTime: slot.startTime!,
                endTime: slot.endTime,
                registrationDeadline: deadlineDateTime,
                registrationOpen: openDateTime,
              ),
              deadlineRule: _deadlineRule,
              openRule: _schedule.openRule,
            ),
        };
      }

      stage = _SubmitStage.firestore;

      // 새 파티 문서에 공통으로 붙는 값 — 날짜가 있든 없든 동일하다.
      Map<String, dynamic> newDocBaseFields() => {
        'hostId': UserSession.userId,
        'hostUid': uid,
        'applicants': <String>[],
        'approvedApplicants': <String>[],
        'rejectedApplicants': <String>[],
        'approved': true,
        'createdAt': Timestamp.fromDate(DateTime.now()),
      };

      // ── 날짜 없이 사전등록하는 오픈예정 파티 ─────────────────────────
      //
      // 날짜 슬롯 동기화(PartySlotSyncService)는 "슬롯 하나 = 문서 하나"가
      // 전제라 슬롯이 0개면 문서가 하나도 만들어지지 않는다. 그래서 이
      // 경우만 문서 하나를 직접 만든다 — date/partyDateTime/rounds 같은
      // 날짜 필드는 아예 쓰지 않는다(빈 값으로 채우면 "날짜를 못 읽는 옛
      // 문서"와 구별할 수 없다). 날짜·차수는 나중에 수정 화면에서 채운다.
      final PartySlotSyncOutcome outcome;
      if (datelessPreopen) {
        final docFields = FirestorePayload.assertSafe({
          ...sharedFields,
          ...newDocBaseFields(),
          'dateSlotId': newPartyDateSlotId(),
        }, tag: _logTag);
        lastPayload ??= docFields;
        final ref = await FirebaseFirestore.instance
            .collection('parties')
            .add(docFields);
        outcome = PartySlotSyncOutcome(
          createdCount: 1,
          updatedCount: 0,
          savedDocIds: [ref.id],
        );
      } else {
        // ── 날짜 슬롯 ↔ 문서 동기화 ────────────────────────────────────
        // 슬롯이 어느 문서였는지 찾고(dateSlotId → 시작 시각), 없으면 새 문서를
        // 만들고, 빠진 날짜의 문서를 지우는 일은 전부 공용 서비스가 한다 —
        // 파티 수정 화면(PartyEditScreen)도 같은 서비스를 쓰므로 두 화면의 날짜
        // 관리 동작이 갈라질 수 없다(PartySlotSyncService 참고).
        //
        // primaryDocId는 **항상 null**이다 — 이 화면(등록·재등록)은 기존 문서를
        // 덮어쓰지 않고 언제나 새 문서를 만든다. 원본 파티는 지난 기록으로 그대로
        // 남는다. (기존 문서를 이어받아 갱신하는 건 파티 수정 화면의 역할이다.)
        final plan = await PartySlotSyncService.plan(
          seriesId: seriesId,
          primaryDocId: null,
          slots: effectiveSlots,
        );

        // 신청자가 남아 있는 날짜는 지울 수 없다 — 저장을 시작하기 전에 알린다
        // (최종 판정은 서버가 하지만, 절반 저장된 뒤 실패를 알리지 않기 위함).
        if (plan.blockedOrphans.isNotEmpty) {
          final names = plan.blockedOrphans.map((o) => o.label).join(', ');
          throw StateError(
            '$names 일정에는 신청자가 있어 삭제할 수 없어요. '
            '그 날짜를 다시 추가하거나, 파티 상태를 \'취소\'로 바꿔 신청을 정리한 뒤 '
            '삭제해주세요.',
          );
        }

        outcome = await plan.commit(
          fieldsFor:
              (
                slot, {
                required isUpdate,
                required index,
                required docId,
                required existing,
              }) {
                final rawFields = <String, dynamic>{
                  ...sharedFields,
                  ...buildSlotDateFields(slot),
                  // 다음 수정 저장이 이 문서를 되찾는 열쇠.
                  'dateSlotId': slot.id,
                  // 이 화면이 만드는 문서는 **항상 새 파티**다(등록·재등록 모두).
                  // 그래서 모집 관련 실시간 값은 언제나 빈 상태에서 시작한다 —
                  // 재등록이 원본의 신청자·참가 인원을 물려받는 일은 없다.
                  ...newDocBaseFields(),
                };

                // 저장 직전 타입 점검 — Set/enum/DateTime/Map<dynamic,dynamic>은
                // 저장 가능한 형태로 바꾸고, 컨트롤러·위젯처럼 손쓸 수 없는 값이
                // 섞여 있으면 **어느 필드인지 이름을 달고** 여기서 멈춘다.
                // (예전에는 그대로 commit 했다가 정체불명의 TypeError만 올라왔다.)
                final docFields = FirestorePayload.assertSafe(
                  rawFields,
                  tag: _logTag,
                );
                // 첫 문서의 payload만 실패 로그용으로 들고 있는다 — 슬롯마다 다른
                // 값은 날짜 관련 필드뿐이라 원인 파악에는 하나면 충분하다.
                lastPayload ??= docFields;
                return docFields;
              },
        );
      }
      debugPrint(
        '[$_logTag:firestore] saved ${outcome.savedDocIds.length} doc(s) '
        '(mode=${widget.mode.name}, '
        'new=${outcome.createdCount}, reused=${outcome.updatedCount}, '
        'deleted=${outcome.deletedDocIds.length})',
      );

      // 플레이스 연결 — 이제 새 파티 문서 id가 생겼으니 커밋한다. 날짜를 여러
      // 개 골랐으면 이번에 만들어진 날짜 문서 전부가 함께 연결된다.
      // 재등록이어도 **원본 파티의 연결은 건드리지 않는다** — 연결이 옮겨가는
      // 게 아니라 새 파티가 같은 플레이스에 추가로 붙는 것이다.
      //
      // 실패하더라도 여기서 예외로 빠지지 않는다 — 파티 문서는 이미 저장됐고,
      // "등록 실패"로 안내하면 사용자가 같은 파티를 또 등록한다. 안내와 재시도는
      // 아래 _SubmitStage.post 구간에서 화면을 닫기 직전에 처리한다.
      final placeLinkError = await _tryLinkPlace(outcome.savedDocIds);
      if (!mounted) return;

      // 신청 방식 + 사전질문 — 파티 문서에 직접 못 쓰는 두 필드라 저장이 끝난
      // 뒤 콜러블로 보낸다. 즉시확정(기본값)이어도 한 번 보내서 서버가 옛
      // 정의를 비우게 한다(재등록으로 옛 설정이 딸려오는 일을 막는다).
      //
      // 실패해도 등록 자체를 되돌리지 않는다 — 파티 문서는 이미 저장됐고,
      // "등록 실패"로 안내하면 사용자가 같은 파티를 또 등록한다.
      // 그 대신 승인제로 설정했는데 저장에 실패한 경우는 **반드시 알린다** —
      // 호스트는 승인제라고 믿는데 실제로는 즉시확정으로 신청을 받게 된다.
      final formError = await PartyApplicationFormService.save(
        partyIds: outcome.savedDocIds,
        mode: _approvalMode,
        questions: _appQuestions,
        requirePhotos: _requireApplicantPhotos,
      );
      if (!mounted) return;
      if (formError != null && _approvalMode == PartyApprovalMode.manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '신청 방식을 저장하지 못했어요 — $formError\n'
              '파티 수정에서 다시 설정해주세요.',
            ),
          ),
        );
      }

      // 재등록의 원본에는 "언제 마지막으로 다시 쓰였는지"만 남긴다 — 원본
      // 파티는 지난 기록으로 그대로 보존되고, 이 필드 외에는 조금도 건드리지
      // 않는다(사진·동영상 파일도 새 파티가 같은 URL을 참조할 뿐이다).
      final sourceDocId = widget.sourceDocId;
      if (_isReregister && sourceDocId != null) {
        try {
          await FirebaseFirestore.instance
              .collection('parties')
              .doc(sourceDocId)
              .update({'lastUsedAt': FieldValue.serverTimestamp()});
        } catch (e) {
          // 재등록 자체는 이미 성공했다 — 기록용 필드 하나 때문에 실패로
          // 되돌리지 않는다.
          debugPrint('[$_logTag] 원본 lastUsedAt 갱신 실패(무시): $e');
        }
      }
      // 지운 날짜가 서버 정책에 걸렸다면(저장 사이에 신청자가 생긴 경우 등)
      // 편집 내용은 이미 저장됐으므로 실패로 되돌리지 않고 사실만 알린다.
      if (outcome.hasDeleteFailures && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '일부 날짜를 삭제하지 못했어요: '
              '${outcome.deleteFailures.values.first}',
            ),
          ),
        );
      }

      stage = _SubmitStage.post;
      if (!mounted) return;
      _dirty = false; // 정상 등록 완료 — 나갈 때 이탈 방지 확인창을 띄우지 않는다.
      // 최종 등록이 끝났으니 이 유형의 임시저장은 자동 삭제한다(요구 6·7번).
      if (_isDraftEnabled) {
        await DraftService.deleteDraft(DraftType.party);
        if (!mounted) return;
      }

      // 파티 문서는 저장됐지만 플레이스 연결만 실패한 경우 — 평소의 성공 흐름과
      // 똑같이 조용히 닫아버리면 사용자는 연결이 안 된 사실을 모른 채 나간다.
      // 화면을 닫기 **전에** 별도 안내를 띄우고 1회 재시도를 제공한다.
      // (재시도는 방금 만들어진 문서만 다시 연결하며, 파티를 새로 만들지 않는다.)
      bool linked = placeLinkError == null;
      if (placeLinkError != null) {
        linked = await _handlePlaceLinkFailure(
          outcome.savedDocIds,
          placeLinkError,
        );
        if (!mounted) return;
      }

      // 참가비를 받는 파티인데 **입금받을 계좌**가 아직 없으면 지금 등록하도록
      // 이어준다(인증돼 있으면 그냥 지나감). 정산계좌가 아니라 수취계좌다 —
      // 참가비는 파티츄를 거치지 않고 호스트 계좌로 바로 들어간다.
      await promptPayoutAccountAfterRegister(
        context,
        what: '파티',
        // 무료 파티는 받을 돈이 없고, '현장 전액결제'로 정했으면 무통장입금
        // 자체가 열리지 않는다 — 둘 다 재촉할 이유가 없다.
        usesBankTransfer:
            (_sampleFeeForPreview() ?? 0) > 0 &&
            (_paymentPolicy?.allowedMethods.contains(
                  PaymentMethod.bankTransfer,
                ) ??
                true),
      );
      if (!mounted) return;

      // 연결용 등록(파티 연결 관리 → 새 파티 만들기)은 메인으로 나가지 않는다 —
      // 사용자는 "이 플레이스/공간대여의 연결 목록"을 보던 중이었고, 방금 만든
      // 파티가 거기에 한 줄 늘어나는 것을 바로 확인해야 한다. pop 값은 실제로
      // 연결된 문서 수(연결까지 실패했으면 0)라 부른 화면이 그대로 안내한다.
      if (widget.prelink != null) {
        Navigator.pop(context, linked ? outcome.savedDocIds.length : 0);
        return;
      }

      // 등록 화면이 몇 단계 깊이 열려 있었든(모바일: RegisterTypeScreen 경유,
      // 데스크톱: MainScreen에서 바로) 곧장 메인화면 파티 탭으로 복귀한다.
      pendingTopTabAfterRegister.value = 0;
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e, stackTrace) {
      // 대표 미디어 업로드가 도중에 끊겼다면 그때까지 올라간 것도 고아 파일이
      // 된다 — 예외가 들고 온 부분 성공분을 정리 목록에 합친다.
      if (e is MediaUploadException) {
        uploadedBlockImageUrls.addAll(e.uploadedImageUrls);
        final partialVideoUid = e.uploadedVideoUid;
        if (partialVideoUid != null)
          uploadedBlockVideoUids.add(partialVideoUid);
      }
      // 상세페이지 블록 사진/동영상이 R2·Stream에는 이미 올라갔는데 그
      // 이후(다른 업로드나 Firestore 저장)에서 실패했다면, 저장되지 못한
      // 파일을 정리한다.
      for (final url in uploadedBlockImageUrls) {
        unawaited(CloudflareService.deleteImage(url).catchError((_) {}));
      }
      for (final uid in uploadedBlockVideoUids) {
        unawaited(
          CloudflareService.deleteVideo(videoUid: uid).catchError((_) {}),
        );
      }
      // 단계별 prefix + 예외 타입/메시지/stackTrace + 저장 직전 payload를
      // 한 번에 남긴다. "등록 중 문제가 발생했습니다"만 보고 원인을 못 찾던
      // 상황을 없애기 위한 것이라, 실패 시엔 반드시 이 세 줄이 함께 찍힌다.
      FirestorePayload.logFailure(
        tag: _logTag,
        stage: stage.key,
        error: e,
        stackTrace: stackTrace,
        payload: lastPayload,
      );
      // 업로드 단계에서 죽었다면 Cloudflare 쪽 분류 로그도 함께 남긴다.
      if (stage == _SubmitStage.upload) {
        MediaUploadService.logUploadError(
          e,
          stackTrace,
          logTag: 'party-media',
          label: '파티 사진 업로드 실패',
        );
      }
      // 예외 원문은 로그에만 — 사용자에게는 단계가 구분된 안내를 보여준다.
      if (mounted) {
        _showMessage(
          RegisterValidation.failureMessage(e, stage: stage.userLabel),
        );
      }
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
        final url = await CloudflareService.uploadImage(d.newImageFile!);
        uploadedUrls.add(url);
        d.uploadedImageUrl = url;
        d.newImageFile = null;
      } else if (d.type == PartyDetailBlockType.imageGroup) {
        for (final item in d.imageGroupItems) {
          if (item.newImageFile == null) continue;
          setState(() => _uploadStatus = '상세페이지 사진을 올리는 중...');
          final url = await CloudflareService.uploadImage(item.newImageFile!);
          uploadedUrls.add(url);
          item.uploadedImageUrl = url;
          item.newImageFile = null;
        }
      } else if (d.type == PartyDetailBlockType.video &&
          d.newVideoFile != null) {
        setState(() => _uploadStatus = '상세페이지 동영상을 올리는 중...');
        final uploaded = await CloudflareService.uploadVideo(d.newVideoFile!);
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

  /// 일정 입력이 바뀔 때 — 방식 선택도, 날짜 시트도, 정기 시트도 전부
  /// [PartyScheduleSection]을 통해 이 한 곳으로 들어온다.
  void _onScheduleChanged(PartyScheduleDraft next) {
    setState(() {
      _schedule = next;
      _showDateError = false;
    });
    _markDirty();
  }

  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<PartyLocationSelection>(
      context,
      webFramedRoute(
        (_) => PartyLocationPickerScreen(
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

  /// 라운드 파티의 총 정원 — 저장 시 문서 최상단 maxCapacity가 되는 값과 같은
  /// 규칙이다('차수별 설정'이면 차수 합계, '모든 차수 동일'이면 공통 칸 하나).
  /// **정원은 자리 수라 합산이 옳다** — 최소 모집 인원과는 다르다.
  int _totalRoundCapacity() {
    int ofControllers() => _genderCapacityMode == 'separate'
        ? (int.tryParse(_maleCapacityController.text.trim()) ?? 0) +
              (int.tryParse(_femaleCapacityController.text.trim()) ?? 0)
        : (int.tryParse(_capacityController.text.trim()) ?? 0);
    if (_roundCapacityMode != 'perRound') return ofControllers();
    var total = ofControllers(); // 1차
    for (final d in _extraRounds) {
      total += d.round.separateTotal;
    }
    return total;
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
        minCapacity: _minCapacity,
        minCapacityPolicy: _minCapacityPolicy,
        revealParticipantGenderRatio: _revealParticipantGenderRatio,
      ),
      isRecurring: _isRecurring,
      // 라운드 진행 파티의 **최대** 인원은 라운드 설정 영역이 정본이다 —
      // 여기서는 성별/인원 제한 방식과 파티 전체 최소 모집 인원만 고른다.
      showCapacityFields: !_hasMultipleRounds,
      // 최대 인원 칸이 없어도 "최소 ≤ 최대"는 검사할 수 있어야 한다.
      totalCapacity: _hasMultipleRounds ? _totalRoundCapacity() : null,
    );
    if (result == null) return;
    setState(() {
      _minCapacity = result.minCapacity ?? 0;
      _minCapacityPolicy = result.minCapacityPolicy;
      _revealParticipantGenderRatio = result.revealParticipantGenderRatio;
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
      isRecurring: _isRecurring,
      initial: FeeDraft(
        maleFee: int.tryParse(_maleFeeController.text.trim()),
        femaleFee: int.tryParse(_femaleFeeController.text.trim()),
        earlyBirdEnabled: _earlyBirdEnabled,
        earlyBirdPercent: int.tryParse(_earlyBirdPercentController.text.trim()),
        earlyBirdEndType: _earlyBirdEndType,
        earlyBirdEndDate: _earlyBirdEndDate,
        earlyBirdEndTime: _earlyBirdEndTime,
        earlyBirdRule: _earlyBirdRule,
      ),
    );
    if (result == null) return;
    setState(() {
      _maleFeeController.text = result.maleFee?.toString() ?? '';
      _femaleFeeController.text = result.femaleFee?.toString() ?? '';
      _earlyBirdEnabled = result.earlyBirdEnabled;
      _earlyBirdPercentController.text =
          result.earlyBirdPercent?.toString() ?? '';
      _earlyBirdEndType = result.earlyBirdEndType;
      _earlyBirdEndDate = result.earlyBirdEndDate;
      _earlyBirdEndTime = result.earlyBirdEndTime;
      _earlyBirdRule = result.earlyBirdRule;
      _showFeeError = false;
    });
  }

  Future<void> _openRefundPolicy() async {
    await Navigator.push(
      context,
      webFramedRoute(
        (_) => PartyRefundPolicyScreen(
          initialTiers: _refundTiers,
          onChanged: (tiers) {
            _refundTiers = tiers;
            _markDirty();
            // 채우자마자 빨간 표시를 거둔다 — 저장을 눌러야 풀리면 고쳤는데도
            // 여전히 잘못된 것처럼 보인다.
            if (RefundPolicyRule.isSatisfied(tiers)) _showRefundError = false;
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  /// 신청 방식(즉시 확정 / 호스트 승인제) + 사전질문.
  Future<void> _openApplicationFormSheet() async {
    final result = await showApplicationFormSheet(
      context,
      mode: _approvalMode,
      questions: _appQuestions,
      requirePhotos: _requireApplicantPhotos,
    );
    if (result == null) return;
    setState(() {
      _approvalMode = result.mode;
      _appQuestions = result.questions;
      _requireApplicantPhotos = result.requirePhotos;
    });
    _markDirty();
  }

  String _approvalSummary() {
    if (_approvalMode != PartyApprovalMode.manual) {
      return PartyApprovalMode.auto.label;
    }
    // 사전질문과 사진 요청은 독립이라 둘 다 따로 적는다.
    final parts = <String>[
      _appQuestions.isEmpty ? '사전질문 없음' : '사전질문 ${_appQuestions.length}개',
      if (_requireApplicantPhotos) '사진 요청',
    ];
    return '${PartyApprovalMode.manual.label} · ${parts.join(' · ')}';
  }

  /// 결제 방식 — 참가비가 있을 때만 연다. 계산 예시에는 지금 입력된 참가비를
  /// 그대로 넘겨, 금액을 고치면 예시도 함께 바뀌게 한다.
  Future<void> _openPaymentPolicySheet() async {
    final result = await showPaymentPolicySheet(
      context,
      initial: _paymentPolicy ?? PaymentPolicy.initial,
      sampleTotal: _sampleFeeForPreview(),
    );
    if (result == null) return;
    setState(() => _paymentPolicy = result);
    _markDirty();
  }

  /// 계산 예시 기준 금액 — 남녀 참가비가 다르면 더 큰 쪽을 쓴다(호스트가
  /// '최대 이만큼 받는다'를 기준으로 보게).
  int? _sampleFeeForPreview() {
    final male = int.tryParse(_maleFeeController.text.trim()) ?? 0;
    final female = int.tryParse(_femaleFeeController.text.trim()) ?? 0;
    final fee = male > female ? male : female;
    return fee > 0 ? fee : null;
  }

  String _paymentSummary() {
    final p = _paymentPolicy;
    if (p == null) return '설정 안 함 (참가자가 결제수단 선택)';
    if (p.mode != PaymentMode.partial) return p.mode.label;
    if (p.upfrontType == UpfrontType.percentage) {
      return '현장 결제 · 예약금 참가비의 ${p.upfrontPercent ?? 0}%';
    }
    return '현장 결제 · 예약금 ${formatWon(p.upfrontFixedAmount ?? 0)}';
  }

  Future<void> _openAgeRestrictionSheet() async {
    // 이 화면에는 아직 파티 대상 유형(성인/청소년/혼합)을 고르는 UI가 없어
    // 항상 성인 전용 범위로 연다 — 청소년 전용 파티 기능이 생기면 그때 고른
    // audienceType 값을 여기 그대로 넘기면 된다(`age_range_utils.dart`의
    // `partyAgeRangeFor` 참고).
    final result = await showAgeRestrictionSheet(
      context,
      initial: _ageRestriction,
      // 성별 모집 설정에 맞는 성별 칸만 보여준다(여성만 모집이면 여성 칸만).
      genderLimit: _genderLimit,
      audienceType: PartyAudienceType.adult,
    );
    if (result == null) return;
    setState(() => _ageRestriction = result);
  }

  Future<void> _openTypeVibeSheet() async {
    final result = await showPartyTypeVibeSheet(
      context,
      initial: PartyTypeVibeDraft(
        types: _partyTypes,
        vibes: _vibes,
        tags: _tags,
      ),
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
      final hasContentInCurrentMode =
          _descriptionMode == PartyDescriptionMode.auto
          ? _introController.text.trim().isNotEmpty
          : _detailBlocks.any((d) => !d.isEmpty);
      if (hasContentInCurrentMode) {
        final confirmed = await confirmPartyDetailDescriptionModeSwitch(
          context,
        );
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
      webFramedRoute(
        (_) => PartyIntroScreen(
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
      webFramedRoute(
        (_) => PartyDetailBlockEditorScreen(
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
      _mediaBasicCardFocalX = result.basicCardFocalX;
      _mediaBasicCardFocalY = result.basicCardFocalY;
      _mediaBasicCardScale = result.basicCardScale;
      _mediaPhotoCrops = result.photoCrops;
      _mediaVideoCropConfirmed = result.videoCropConfirmed;
      _showMediaCoverError = false;
    });
  }

  // ── 요약 텍스트 ─────────────────────────────────────────────────────

  // 일정 요약/오류 문구는 PartyScheduleDraft(summaryLabel/errorText)가 갖고
  // 있다 — 세 등록 화면이 같은 문구를 쓰도록 모델 한 곳에만 둔다.

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
    // 라운드 진행 파티는 인원을 라운드 설정에서 받으므로 여기 요약에 숫자를
    // 넣지 않는다 — 차수마다 다른 값을 하나로 줄여 보여주면 오해를 만든다.
    if (_hasMultipleRounds) {
      return label.isEmpty ? null : '$label · 인원은 라운드 설정에서';
    }
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

  String? _refundSummary() => RefundPolicyRule.summaryLabel(_refundTiers);

  // 남녀 제한이 같아도 '남성 …세 · 여성 …세'로 나눠 보여준다 — 합쳐 놓으면
  // 그게 내 성별에도 적용되는 값인지 알 수 없다([PartyAgeRestriction]).
  String? _ageSummary() {
    final label = _ageRestriction.summaryLabel(genderLimit: _genderLimit);
    return label.isEmpty ? null : label;
  }

  String? _typeVibeSummary() {
    final all = [
      ..._partyTypes.map(PartyConstants.labelFor),
      ..._vibes.map(PartyConstants.vibeLabelFor),
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

  /// [sectionKey]/[hasError]/[errorText]는 필수값이 빠졌을 때 그 섹션으로
  /// 스크롤하고 카드 전체를 빨갛게 강조하기 위한 것이다 — 문구만 위쪽 배너에
  /// 띄우면 정작 어느 카드를 고쳐야 하는지 알 수 없다.
  Widget _sectionCard({
    required String title,
    required Widget child,
    GlobalKey? sectionKey,
    bool hasError = false,
    String? errorText,
  }) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: hasError
            ? Border.all(color: const Color(0xFFE53935), width: 1.5)
            : null,
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
          if (hasError && errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: Color(0xFFE53935),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      errorText,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Color(0xFFE53935),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
    // 필수항목 안내가 가리키는 카드면 **카드 자체**를 감싼다 — 0높이 마커로는
    // 도착한 자리를 강조할 수 없다([RegisterFieldAnchor]).
    if (sectionKey == null) return card;
    return RegisterFieldAnchor(key: sectionKey, child: card);
  }

  // ── 라운드 진행 파티의 정원·참가비·얼리버드 입력 ────────────────────────
  //
  // 라운드를 켜면 이 값들을 **라운드 설정 영역 안에서만** 받는다. 예전에는
  // 1차만 바깥 '성별 및 모집 인원'·'참가비 설정' 줄에서 받고 2차부터 카드에서
  // 받아, 같은 성격의 값이 두 곳에 나뉘어 있었다("가격을 두 번 입력한다"는
  // 오해의 원인).
  //
  // **저장 상태는 그대로 둔다.** 아래 입력들은 예전과 똑같은 컨트롤러·필드를
  // 고친다 — 저장·검증·집계 경로를 건드리지 않아야 라운드 OFF 파티와 기존
  // 문서 동작이 그대로 유지된다. 바뀐 것은 이 칸들이 그려지는 위치뿐이다.

  /// 정원 + 참가비 한 묶음. '모든 차수 동일'이면 목록 위 공통 블록으로,
  /// '차수별 설정'이면 1차 카드 안으로 들어간다(2차 이후 카드와 같은 자리).
  Widget _roundInlineCapacityFee() {
    final separate = _genderCapacityMode == 'separate';
    final showMale = _genderLimit != 'female';
    final showFemale = _genderLimit != 'male';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _roundInlineLabel('모집 인원 · 참가비'),
        // 차수 최소 인원 — '차수별 설정'일 때만 저장된다(PartyRound.toMap이
        // perRound에서만 정원을 남긴다). '모든 차수 동일'에서는 저장되지도
        // 않는 칸을 보여줄 이유가 없어 감춘다.
        //
        // ⚠️ 파티 전체 최소 모집 인원과 **다른 값**이다. 파티 값은 성별·인원
        // 시트에 있고, 이 칸들을 더해서 만들지 않는다([PartyMinCapacity]).
        if (_roundCapacityMode == 'perRound') ...[
          TextField(
            controller: _round1MinCapacityController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) => setState(() {
              _round1MinCapacity = int.tryParse(v.trim()) ?? 0;
              _markDirty();
            }),
            decoration: _roundInlineDeco('1차 최소 인원 (선택)'),
          ),
          const SizedBox(height: 8),
        ],
        if (!separate)
          TextField(
            controller: _capacityController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {
              _showCapacityError = false;
              _markDirty();
            }),
            decoration: _roundInlineDeco('최대 인원', error: _showCapacityError),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _maleCapacityController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {
                    _showCapacityError = false;
                    _markDirty();
                  }),
                  decoration: _roundInlineDeco(
                    '남자 인원',
                    error: _showCapacityError,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _femaleCapacityController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {
                    _showCapacityError = false;
                    _markDirty();
                  }),
                  decoration: _roundInlineDeco(
                    '여자 인원',
                    error: _showCapacityError,
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (showMale)
              Expanded(
                child: TextField(
                  controller: _maleFeeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {
                    _showFeeError = false;
                    _markDirty();
                  }),
                  decoration: _roundInlineDeco(
                    showFemale ? '남자 참가비 (원)' : '참가비 (원)',
                    error: _showFeeError,
                  ),
                ),
              ),
            if (showMale && showFemale) const SizedBox(width: 8),
            if (showFemale)
              Expanded(
                child: TextField(
                  controller: _femaleFeeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {
                    _showFeeError = false;
                    _markDirty();
                  }),
                  decoration: _roundInlineDeco(
                    showMale ? '여자 참가비 (원)' : '참가비 (원)',
                    error: _showFeeError,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '무료면 0을 입력해주세요. 1,000원 단위로 받습니다.',
          style: TextStyle(fontSize: 11, color: Colors.black38),
        ),
      ],
    );
  }

  /// '모든 차수 동일' 얼리버드 — 규칙 한 벌을 받아 **모든 차수에 그대로**
  /// 복사해 저장한다. 할인 금액은 각 차수 참가비에 이 규칙을 적용해 따로
  /// 계산되므로(서버 applyRoundEarlyBird), 1차 20,000원·2차 30,000원에 20%면
  /// 16,000원·24,000원이 된다 — 할인된 금액 하나를 저장하지 않는다.
  Widget _roundInlineEarlyBird() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 100,
              child: TextField(
                controller: _earlyBirdPercentController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {
                  _showFeeError = false;
                  _markDirty();
                }),
                decoration: _roundInlineDeco('할인율 %'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: _pickRoundEarlyBirdRule,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7FA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_earlyBirdRule.label}'
                    '${_earlyBirdRule.usesTime ? ' ${formatScheduleTime(_earlyBirdRule.time)}' : ''}까지',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '각 차수의 시작 시각을 기준으로 계산돼요. 할인 금액은 그 차수 참가비 기준입니다.',
          style: TextStyle(fontSize: 11, color: Colors.black38),
        ),
      ],
    );
  }

  /// 1차 카드 안의 얼리버드 — '차수별 설정'에서만 쓴다. 2차 이후 카드의
  /// 얼리버드 줄과 같은 모양이고, 값만 문서 최상단 상태(1차 = 대표값)를 쓴다.
  Widget _roundInlinePrimaryEarlyBird() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '1차 얼리버드 할인',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
            Switch(
              value: _earlyBirdEnabled,
              activeThumbColor: const Color(0xFFFF6FA0),
              onChanged: (v) => setState(() {
                _earlyBirdEnabled = v;
                if (v) {
                  _earlyBirdEndType = PartyEarlyBirdEndType.beforeStart;
                  if (_earlyBirdPercentController.text.trim().isEmpty) {
                    _earlyBirdPercentController.text = '10';
                  }
                }
                _showFeeError = false;
                _markDirty();
              }),
            ),
          ],
        ),
        if (_earlyBirdEnabled) _roundInlineEarlyBird(),
      ],
    );
  }

  /// 얼리버드 종료 기준(며칠/몇 시간 전) — 차수 카드의 선택지와 같은 목록이다.
  Future<void> _pickRoundEarlyBirdRule() async {
    final picked = await showModalBottomSheet<PartyEarlyBirdDeadlineRule>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '얼리버드 종료 기준',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final option in kRoundEarlyBirdRuleOptions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    option.label,
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: option == _earlyBirdRule
                      ? const Icon(
                          Icons.check,
                          size: 18,
                          color: Color(0xFFFF6FA0),
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, option),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _earlyBirdRule = picked;
      _markDirty();
    });
  }

  Widget _roundInlineLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.black54,
      ),
    ),
  );

  InputDecoration _roundInlineDeco(String label, {bool error = false}) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: Colors.black45),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: error ? const Color(0xFFE53935) : const Color(0xFFE8EBF2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: error ? const Color(0xFFE53935) : const Color(0xFFFF6FA0),
          ),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  /// 얼리버드 적용 방식 칩 — 사용 안 함 / 모든 차수 동일 / 차수별 설정.
  Widget _roundEarlyBirdModeChip(String title, String subtitle, String mode) {
    // '차수별 설정'은 차수마다 참가비가 따로 있을 때만 뜻이 있다 — 통합 정원
    // 모드는 차수에 참가비·얼리버드를 저장하지 않으므로(PartyRound.toMap)
    // 골라도 적용되지 않는다. 고를 수 없게 막고 이유를 보여준다.
    final disabled = mode == 'perRound' && _roundCapacityMode != 'perRound';
    final selected = _roundEarlyBirdMode == mode;
    return GestureDetector(
      onTap: disabled
          ? null
          : () => setState(() {
              _roundEarlyBirdMode = mode;
              _earlyBirdEnabled = mode != 'none';
              if (mode != 'none') {
                // 차수마다 날짜가 다르므로 고정 종료 시각은 쓸 수 없다.
                _earlyBirdEndType = PartyEarlyBirdEndType.beforeStart;
                _earlyBirdPercentController.text =
                    _earlyBirdPercentController.text.trim().isEmpty
                    ? '10'
                    : _earlyBirdPercentController.text;
              }
              _showFeeError = false;
              _markDirty();
            }),
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
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
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: selected ? const Color(0xFFFF6FA0) : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 10, color: Colors.black45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundModeChip(String title, String subtitle, String mode) {
    final selected = _roundCapacityMode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _roundCapacityMode = mode;
        // 통합 정원으로 되돌리면 차수별 얼리버드는 저장되지 않는다 —
        // 고른 상태로 남겨두면 "설정했는데 적용되지 않는" 화면이 된다.
        if (mode != 'perRound' && _roundEarlyBirdMode == 'perRound') {
          _roundEarlyBirdMode = 'uniform';
        }
        _markDirty();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF3F7) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
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
                color: selected ? const Color(0xFFFF6FA0) : Colors.black87,
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
        // 임시저장 가능한(빈 새 등록) 화면에서는 내용을 버리지 않고 먼저
        // 자동 임시저장한 뒤 "임시저장되었습니다" 안내를 보여준다. 수정·재등록
        // 화면은 기존 "종료하시겠습니까?" 확인창을 그대로 쓴다.
        final shouldLeave = _isDraftEnabled
            ? await _confirmLeaveWithDraftSave()
            : await _confirmLeave();
        if (shouldLeave && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FC),
        appBar: AppBar(
          title: Text(
            widget.mode.screenTitle('파티'),
            style: const TextStyle(
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
          centerTitle: true,
          actions: _isDraftEnabled
              ? [
                  TextButton(
                    onPressed: _manualSaveDraft,
                    child: const Text(
                      '임시저장',
                      style: TextStyle(
                        color: Color(0xFFFF6FA0),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ]
              : null,
          bottom: _isDraftEnabled ? _buildAutoSaveIndicator() : null,
        ),
        body: Stack(
          children: [
            Form(
              key: _formKey,
              // 값을 채우면 빨간 문구가 즉시 사라지도록 자동 재검증.
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  // 지금 이 파티가 어느 공간에 붙는지 — 맨 위에 남겨 둔다.
                  // 연결이 있을 때만 그린다(공간이 없는 호스트에게는 이 줄이
                  // 아예 없어 등록 화면이 지금까지와 완전히 같다).
                  if (widget.prelink == null && _linkedEventId != null)
                    LinkedSpaceBanner(
                      target: _linkTarget,
                      name: _linkedSpaceName,
                      onChange: () => showPartySpaceLinkSheet(
                        context,
                        linkedEventId: _linkedEventId,
                        onChanged: _onPlaceLinkChanged,
                      ),
                    ),
                  // 사업자 인증 전에는 이 파티가 어떤 상태로 올라가는지를 등록을
                  // 시작하기 전에 알려준다 — 다 채워 저장한 뒤에야 "신청을 못
                  // 받는다"는 걸 알게 되면 안 된다.
                  if (_preopenRequired) _buildPreopenNotice(),
                  // 오픈 이벤트 안내 + 혜택 입력 — 등록을 시작하기 전에 가장
                  // 먼저 보이도록 맨 위에 둔다. 파티는 "참가자에게 현장에서
                  // 주는 혜택"이라 매장(플레이스·장소대여)과 안내 문구가 다르다.
                  PartychuPerkSection(
                    controller: _partychuPerkController,
                    audience: PartychuPerkAudience.party,
                  ),
                  if (_isDraftEnabled && _draftMediaNeedsReselect)
                    _buildMediaReselectBanner(),
                  RegisterMissingFieldsBanner(fields: _missingFields),
                  _sectionCard(
                    title: '기본 정보',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('파티명'),
                        // 필수항목 안내가 가리키는 영역 — 0높이 마커가 아니라
                        // **입력칸 자체**를 감싼다. 그래야 이동한 뒤 어디로
                        // 왔는지 잠깐 강조해 보여줄 수 있다.
                        RegisterFieldAnchor(
                          key: _keyPartyName,
                          child: PartyTitleField(
                            controller: _partyNameController,
                            focusNode: _partyNameFocus,
                            decoration: _inputDecoration('예: 한강 야경 드라이브 번개'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? '파티명을 입력해줘'
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 일정 — 플레이스+파티·숙박+파티 등록 화면과 같은 위젯.
                  _sectionCard(
                    title: _preopenRequired ? '일정 (선택)' : '일정',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 사업자 인증 전에는 날짜를 비워두고 먼저 올릴 수 있다 —
                        // 그 사실을 여기서 분명히 말해줘야 "필수 항목을 안 채운
                        // 채 저장하는 것"처럼 느끼지 않는다.
                        if (_preopenRequired)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              '날짜는 나중에 정해도 돼요. 비워두면 "날짜 미정"으로 올라가고, '
                              '나중에 수정 화면에서 날짜를 정한 뒤 모집을 열 수 있어요.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: Color(0xFF4F46E5),
                              ),
                            ),
                          ),
                        PartyScheduleSection(
                          value: _schedule,
                          onChanged: _onScheduleChanged,
                          showError: _showDateError,
                          rowKey: _keyDateTime,
                        ),
                      ],
                    ),
                  ),
                  _sectionCard(
                    title: '여러 라운드로 진행하나요?',
                    sectionKey: _keyRounds,
                    hasError: _showRoundsError,
                    errorText: _roundsErrorText,
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
                              onChanged: _onMultipleRoundsToggled,
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
                                  '모든 차수 동일',
                                  '전체 라운드가 같은 정원/참가비',
                                  'unified',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _roundModeChip(
                                  '차수별 설정',
                                  '1차부터 차수마다 따로',
                                  'perRound',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            '얼리버드 할인',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _roundEarlyBirdModeChip(
                                  '사용 안 함',
                                  '할인 없음',
                                  'none',
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _roundEarlyBirdModeChip(
                                  '모든 차수 동일',
                                  '같은 할인율 적용',
                                  'uniform',
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _roundEarlyBirdModeChip(
                                  '차수별 설정',
                                  '차수마다 따로',
                                  'perRound',
                                ),
                              ),
                            ],
                          ),
                          if (_roundEarlyBirdMode == 'uniform') ...[
                            const SizedBox(height: 10),
                            _roundInlineEarlyBird(),
                          ],
                          if (_roundEarlyBirdMode == 'perRound' &&
                              _roundCapacityMode != 'perRound')
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                '차수별 얼리버드는 "차수별 설정" 참가비에서만 쓸 수 있어요.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFFE53935),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          RoundListEditor(
                            rounds: _extraRounds,
                            roundCapacityMode: _roundCapacityMode,
                            genderCapacityMode: _genderCapacityMode,
                            primaryRound: _primaryRound,
                            referenceDate: _roundReferenceDate,
                            errors: _roundErrors,
                            onChanged: _onRoundsChanged,
                            earlyBirdMode: _roundEarlyBirdMode,
                            // 정원·참가비는 라운드 영역 안에서만 받는다 —
                            // '모든 차수 동일'이면 목록 위 공통 칸 하나,
                            // '차수별 설정'이면 1차 카드부터 차수마다.
                            commonSettings: _roundCapacityMode == 'perRound'
                                ? null
                                : _roundInlineCapacityFee(),
                            primarySettings: _roundCapacityMode == 'perRound'
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _roundInlineCapacityFee(),
                                      // 1차 얼리버드도 다른 차수와 같은
                                      // 자리에서 켜고 끈다 — '차수별 설정'의
                                      // 1차만 예외로 바깥에 두면 예전과 같은
                                      // 혼란이 그대로 남는다.
                                      if (_roundEarlyBirdMode ==
                                          'perRound') ...[
                                        const SizedBox(height: 10),
                                        _roundInlinePrimaryEarlyBird(),
                                      ],
                                    ],
                                  )
                                : null,
                          ),
                          // 차수 패키지 판매 — 차수별 정원·참가비 모드에서만
                          // 만들 수 있다(통합 정원은 차수별 카운터가 없어
                          // "포함 차수마다 1명씩"을 지킬 수 없고, 서버도 같은
                          // 이유로 패키지 신청을 거부한다).
                          if (_roundCapacityMode == 'perRound') ...[
                            const SizedBox(height: 16),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            RoundPackageEditor(
                              rounds: _packageRoundInfos,
                              packages: _roundPackages,
                              separateGenderFee: _packageSeparateGenderFee,
                              errors: _packageErrors,
                              onChanged: (next) => setState(() {
                                _roundPackages = next;
                                _packageErrors = const {};
                                _markDirty();
                              }),
                            ),
                          ],
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
                  // 플레이스 연결 — 장소 바로 아래에 둔다(고르면 위 장소 정보가
                  // 그 플레이스 값으로 채워지므로 두 줄이 붙어 있어야 이해된다).
                  // 등록·재등록이 같은 위젯·같은 저장 경로를 쓴다.
                  // 연결 대상이 미리 정해진 등록에서는 고르는 UI 대신 "여기에
                  // 붙는다"는 사실만 보여준다 — 바꿀 수 있는 것처럼 보이면
                  // 돌아갈 화면과 어긋난다.
                  if (widget.prelink case final prelink?)
                    PartyPlaceLinkSection.locked(
                      targetNoun: prelink.target.noun,
                      targetName: prelink.displayName,
                    )
                  else
                    PartyPlaceLinkSection(
                      linkedEventId: _linkedEventId,
                      linkedTarget: _linkTarget,
                      linkedPlaceData: _linkedPlaceData,
                      loading: _linkedPlaceLoading,
                      onChanged: _onPlaceLinkChanged,
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
                    title: '신청 방식',
                    summary: _approvalSummary(),
                    onTap: _openApplicationFormSheet,
                  ),
                  // 문의 받기는 "게스트와 어떻게 연락할지"라 신청 방식 바로
                  // 아래에 둔다.
                  GuestInquirySection(
                    enabled: _inquiryEnabled,
                    onChanged: (v) => setState(() => _inquiryEnabled = v),
                    guideController: _inquiryGuideController,
                  ),
                  // 라운드 진행 파티는 참가비·얼리버드를 라운드 설정 영역에서
                  // 받는다 — 이 줄을 함께 두면 같은 금액을 두 번 입력하는
                  // 것처럼 보인다(1차 값이 어느 쪽인지도 알 수 없다).
                  if (!_hasMultipleRounds)
                    SectionSummaryRow(
                      rowKey: _keyFee,
                      title: '참가비 설정',
                      summary: _feeSummary(),
                      hasError: _showFeeError,
                      errorText: _showFeeError ? _feeErrorText() : null,
                      onTap: _openFeeSheet,
                    ),
                  SectionSummaryRow(
                    rowKey: _keyRefund,
                    title: RefundPolicyRule.sectionTitle,
                    summary: _refundSummary(),
                    isRequired: true,
                    hasError: _showRefundError,
                    errorText: _showRefundError
                        ? RefundPolicyRule.requiredMessage
                        : null,
                    onTap: _openRefundPolicy,
                  ),
                  // 무료 파티에는 결제 방식이라는 개념이 없다 — 줄 자체를 숨긴다.
                  if (!_pricing.isFree)
                    SectionSummaryRow(
                      title: '결제 방식',
                      summary: _paymentSummary(),
                      onTap: _openPaymentPolicySheet,
                    ),
                  SectionSummaryRow(
                    title: '연령대 설정',
                    summary: _ageSummary(),
                    onTap: _openAgeRestrictionSheet,
                  ),
                  SectionSummaryRow(
                    title: '파티 유형 · 분위기',
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
                    title: '사진 / 동영상 등록',
                    summary: _mediaSummary(),
                    hasError: _showMediaCoverError,
                    errorText: '대표 사진 / 동영상을 선택해주세요',
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
                  // 상세 이미지(선택) — 위 "사진 / 동영상 등록"과 다른 쓰임이라
                  // 별도 카드로 둔다. 대표 사진 개수·순서·동영상 규칙에는
                  // 아무 영향을 주지 않는다.
                  PartyDetailImageSection(
                    draft: _detailImage,
                    onChanged: (next) => setState(() {
                      _detailImage = next;
                      _markDirty();
                    }),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isUploading ? null : _submit,
                      child: Text(
                        widget.mode.submitLabel('파티'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // 삭제 버튼은 여기 없다 — 이 화면은 등록·재등록 전용이고 둘 다
                  // "새 파티를 만드는" 화면이라 지울 대상이 없다. 원본 파티를
                  // 지우는 건 파티 수정 화면(PartyEditScreen)의 공용
                  // DeleteContentButton이 맡는다.
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
