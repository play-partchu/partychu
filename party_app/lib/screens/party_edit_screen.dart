import 'dart:async';
import 'package:flutter/services.dart';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/widgets/guest_inquiry_section.dart';
import 'package:party_app/models/payment_policy.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/models/party_application_form.dart';
import 'package:party_app/services/party_application_form_service.dart';
import 'package:party_app/widgets/party_form/application_form_section.dart';
import 'package:party_app/widgets/party_form/payment_policy_sheet.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:party_app/models/participant_gender_visibility.dart';
import 'package:party_app/models/party_gender_recruit.dart';
import 'package:party_app/widgets/gender_recruit_status_field.dart';
import 'package:party_app/models/party_capacity_status.dart';
import 'package:party_app/models/party_auto_description_style.dart';
import 'package:party_app/models/party_description_mode.dart';
import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/party_detail_decoration_intensity.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/models/party_early_bird.dart';
import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/party_round.dart';
import 'package:party_app/models/party_round_offer.dart';
import 'package:party_app/models/party_round_package.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/models/party_constants.dart';
import 'package:party_app/screens/event_detail_screen.dart';
import 'package:party_app/screens/party_applicants_screen.dart';
import 'package:party_app/screens/party_detail_block_editor_screen.dart';
import 'package:party_app/screens/party_intro_screen.dart';
import 'package:party_app/screens/party_media_picker_screen.dart';
import 'package:party_app/screens/party_refund_policy_screen.dart';
import 'package:party_app/screens/place_detail_screen.dart';
import 'package:party_app/screens/place_party_link_screen.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/utils/register_validation.dart';
import 'package:party_app/services/party_bundle_service.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/services/party_slot_sync_service.dart';
import 'package:party_app/models/party_open_state.dart';
import 'package:party_app/services/party_open_alert_service.dart';
import 'package:party_app/services/host_open_policy_service.dart';
import 'package:party_app/services/business_verification_service.dart';
import 'package:party_app/models/business_verification.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:party_app/screens/business_verification_screen.dart';
import 'package:party_app/utils/partychu_perk_sync.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/widgets/party_form/bundled_parties_card.dart';
import 'package:party_app/widgets/party_form/fee_sheet.dart';
import 'package:party_app/widgets/party_form/gender_capacity_sheet.dart';
import 'package:party_app/widgets/party_form/round_list_editor.dart'
    show PartyRoundDraft;
import 'package:party_app/widgets/party_form/round_package_editor.dart';
import 'package:party_app/widgets/party_form/date_time_sheet.dart'
    show formatPartyDate, formatPartyTime;
import 'package:party_app/models/party_detail_image.dart';
import 'package:party_app/widgets/party_form/party_detail_block_draft.dart';
import 'package:party_app/widgets/party_form/party_detail_image_section.dart';
import 'package:party_app/widgets/party_form/party_detail_description_mode_sheet.dart';
import 'package:party_app/widgets/party_form/party_schedule_section.dart';
import 'package:party_app/widgets/party_form/party_title_field.dart';
import 'package:party_app/widgets/party_form/party_type_vibe_sheet.dart';
import 'package:party_app/widgets/party_form/section_summary_row.dart';
import 'package:party_app/widgets/partychu_perk.dart';
import 'package:party_app/services/content_delete_service.dart'
    show DeletableContent;
import 'package:party_app/widgets/delete_content_action.dart';
import 'package:party_app/widgets/party_media_editor.dart' show PartyCoverPick;
import 'package:party_app/widgets/web_frame.dart';

/// 운영 > 파티 수정 **전용** 화면 — 열려 있는 그 문서를 그대로 갱신한다.
///
/// 재등록은 여기 없다. 예전에는 이 화면이 `PartyFormMode.reregister`도 겸했고,
/// 그래서 **등록 화면에만 있는 차수 편집기·연령제한 시트·미입력 항목 배너가
/// 재등록에서 통째로 빠져 있었다.** 지금은 등록 화면(PartyRegisterScreen)이
/// 정본이고 재등록은 그 화면을 [RegisterFormMode.reregister]로 연다 — 등록에
/// 기능을 추가하면 재등록에 자동으로 따라온다.
///
/// 이 화면이 남아 있는 이유는 수정이 재등록과 **본질적으로 다른 동작**이기
/// 때문이다. 수정은 이미 신청자가 붙어 있는 문서를 이어받아 갱신해야 하므로
/// 날짜별 모집 상태·신청 인원을 보존하고, 일정 변경 시 경고를 띄우며, 원본
/// 삭제 버튼을 제공한다. 재등록은 그 반대로 전부 새로 시작한다.
class PartyEditScreen extends StatefulWidget {
  /// 갱신할 파티 문서의 id.
  final String docId;
  final Map<String, dynamic> data;

  const PartyEditScreen({super.key, required this.docId, required this.data});

  @override
  State<PartyEditScreen> createState() => _PartyEditScreenState();
}

class _PartyEditScreenState extends State<PartyEditScreen> {
  final _formKey = GlobalKey<FormState>();

  static const String _screenTitle = '파티 수정';
  static const String _submitLabel = '저장하기';

  // ── 일정(날짜·시간/매주 반복/차수/모집 시작·마감) ──────────────────
  // 등록 화면들과 같은 공용 위젯(PartyScheduleSection)을 쓴다. 수정 모드도
  // 같은 섹션을 그대로 보여준다 — 두 진입 경로의 항목이 어긋나지 않게.
  PartyScheduleDraft _schedule = PartyScheduleDraft.empty();
  bool _showDateError = false;

  /// 일정을 바꿔서 저장하면 이미 신청·결제한 사람이나 차수 데이터와 어긋날 수
  /// 있는 파티인지 — 수정 모드에서 확인창을 띄우는 조건.
  bool get _scheduleChangeIsRisky => PlacePartyLink.hasApplicants(_partyData);

  late final PartyTitleController _titleController;
  late final TextEditingController _descController;

  /// "파티츄 전용 혜택" — 기존 값을 불러와 고치고, 비우면 빈 문자열로 저장된다.
  /// 파티는 **참가자에게 현장에서** 주는 혜택이라 안내 문구가 매장과 다르다
  /// ([PartychuPerkAudience.party]).
  late final TextEditingController _partychuPerkController;
  late final TextEditingController _capacityController;

  // 최소 모집 인원 — 성별/인원 시트에서 함께 고른다(0이면 정하지 않음).
  int _minCapacity = 0;

  /// 게스트에게 현재 참가자의 남/여 인원을 보여줄지 — 기본은 공개.
  bool _revealParticipantGenderRatio = ParticipantGenderVisibility.defaultValue;
  PartyMinCapacityPolicy _minCapacityPolicy = PartyMinCapacityPolicy.proceed;
  late final TextEditingController _maleFeeController;
  late final TextEditingController _femaleFeeController;
  final TextEditingController _earlyBirdPercentController =
      TextEditingController();
  // 환불 규정 — 호스트가 직접 등록하는 기간별 환불률 구간.
  List<RefundTier> _refundTiers = [];

  /// 결제 방식 — null이면 필드를 남기지 않아 기존 파티와 똑같이 동작한다.
  PaymentPolicy? _paymentPolicy;

  /// 신청 방식 — 필드가 없는 기존 파티는 즉시 확정으로 읽힌다.
  /// 파티 문서에 직접 쓰지 않고 setPartyApplicationForm 콜러블로 저장한다.
  PartyApprovalMode _approvalMode = PartyApprovalMode.auto;

  /// 승인 심사용 프로필 사진 요청 — 저장된 값을 그대로 불러온다.
  /// 필드가 없는 기존 파티는 꺼짐으로 읽힌다.
  bool _requireApplicantPhotos = false;
  List<PartyApplicationQuestion> _appQuestions = [];
  late Set<String> _partyTypes;
  late Set<String> _vibes;
  late List<String> _tags;

  /// 게스트 문의 받기 — 등록 화면과 **같은 필드**(inquiryEnabled) 하나다.
  bool _inquiryEnabled = ListingInquiry.defaultEnabled;

  /// 문의 전 안내문 — 수정 진입 시 저장돼 있던 값이 그대로 복원된다.
  final _inquiryGuideCtrl = TextEditingController();

  late String _recruitStatus;
  late String _genderLimit;

  /// 성별별 모집 상태 — 필드가 없던 기존 파티는 남·여 모두 모집중으로 읽힌다
  /// ([PartyGenderRecruit]). 전체 모집마감은 여기가 아니라 [_recruitStatus]다.
  bool _maleRecruitOpen = true;
  bool _femaleRecruitOpen = true;

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

  // ── 상세 이미지(선택) — 대표 미디어와 별개인 상세 본문 전용 1장.
  PartyDetailImageDraft _detailImage = PartyDetailImageDraft.empty;

  /// 화면에 들어올 때 문서에 저장돼 있던 상세 이미지 URL. 저장에 성공한 뒤
  /// 최종 URL과 다르면(교체·삭제) 이 옛 파일을 R2에서 정리한다 — 문서에서
  /// URL만 지우고 원본을 남겨두면 아무도 참조하지 않는 파일이 계속 쌓인다.
  String? _originalDetailImageUrl;

  // 상세 설명 방식 — 간편 자동 꾸미기(auto) / 직접 상세페이지 만들기(blocks)
  // 중 하나만 실제로 렌더링된다. initState에서 기존 파티 데이터로 초기화된다.
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

  bool _isSaving = false;

  // ── 오픈예정 → 모집 오픈 ───────────────────────────────────────────────
  //
  // 오픈은 저장과 **별개의 행동**이다. 날짜를 채워 저장했다고 자동으로 열리지
  // 않고, 호스트가 '모집 오픈'을 직접 눌러야 신청을 받기 시작한다. 그 시점에
  // 서버가 오픈 알림 신청자들에게 알림을 한 번 보낸다.
  //
  // 여기 두 값은 **버튼을 어떻게 보여줄지**만 정한다. 실제 차단은
  // openPartyRecruiting(Cloud Functions)이 같은 정책값과 인증 상태를 다시
  // 읽어서 하므로, 앱을 거치지 않은 요청도 서버에서 막힌다.
  bool _individualOpeningEnabled = false;
  bool _businessVerified = false;
  bool _openingPolicyLoaded = false;
  bool _opening = false;

  /// 지금 이 호스트가 모집을 열 수 있는가.
  bool get _canOpenRecruiting => _businessVerified || _individualOpeningEnabled;

  Future<void> _loadOpeningPolicy() async {
    final results = await Future.wait([
      HostOpenPolicyService.individualHostOpeningEnabled(),
      BusinessVerificationService.fetch(),
    ]);
    if (!mounted) return;
    setState(() {
      _individualOpeningEnabled = results[0] as bool;
      _businessVerified = (results[1] as BusinessVerification).isVerified;
      _openingPolicyLoaded = true;
    });
  }

  /// 모집 오픈 — 확인창을 한 번 거친다. 오픈은 되돌리는 개념이 없고(되돌리려면
  /// '마감'으로 바꿔야 한다), 알림 신청자들에게 알림이 실제로 나가기 때문이다.
  Future<void> _openRecruiting() async {
    if (_opening) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('모집을 열까요?'),
        content: const Text(
          '지금부터 참가 신청을 받기 시작해요.\n'
          '오픈 알림을 신청한 분들께 알림이 한 번 나가고, 다시 보내지지 않아요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('모집 오픈'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _opening = true);
    try {
      final notified = await PartyOpenAlertService.openRecruiting(widget.docId);
      if (!mounted) return;
      // 화면에 열린 상태를 즉시 반영한다 — 다시 누를 수 없게.
      setState(() => _partyData['openState'] = PartyOpenState.open);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notified > 0
                ? '모집을 열었어요. 알림 신청한 $notified명에게 알려드렸어요.'
                : '모집을 열었어요.',
          ),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // 서버가 "무엇이 비었는지"까지 담아 한국어로 던진다 — 그대로 보여준다.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? '모집을 열지 못했어요.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모집을 열지 못했어요. 잠시 후 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// 오픈예정 파티에만 붙는 하단 영역.
  Widget _buildOpenSection() {
    if (!_openingPolicyLoaded) {
      return const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final canOpen = _canOpenRecruiting;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFC7D2FE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 18,
                  color: Color(0xFF4F46E5),
                ),
                SizedBox(width: 6),
                Text(
                  '지금은 오픈예정 상태예요',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              canOpen
                  ? '날짜와 필수 정보를 채운 뒤 모집을 열면 참가 신청을 받기 시작해요. '
                        '저장만으로는 열리지 않아요 — 아래 버튼을 눌러야 열려요.'
                  : '지금은 개인 호스트의 모집 오픈이 열려 있지 않아요. '
                        '사업자 인증을 마치면 바로 모집을 열 수 있어요.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF3730A3),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: canOpen
                  ? ElevatedButton(
                      onPressed: (_opening || _isSaving)
                          ? null
                          : _openRecruiting,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: _opening
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('모집 오픈'),
                    )
                  : OutlinedButton(
                      onPressed: () =>
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const BusinessVerificationScreen(),
                            ),
                          ).then((_) {
                            if (mounted) _loadOpeningPolicy();
                          }),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4F46E5),
                        side: const BorderSide(color: Color(0xFF4F46E5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text('사업자 인증하기'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _uploadStatus = '';

  // 필수항목 에러 표시 — 각 SectionSummaryRow의 빨간 테두리를 켠다.
  bool _showCapacityError = false;
  bool _showFeeError = false;
  bool _showIntroError = false;
  bool _showMediaCoverError = false;
  // 환불 규정 최소 1개 — 구간 없이 저장된 옛 파티도 **다시 저장할 때부터** 요구한다.
  bool _showRefundError = false;

  // ── 얼리버드 할인 ─────────────────────────────────────────────────
  bool _earlyBirdEnabled = false;

  /// 이 파티가 정기 파티인지 — 얼리버드 종료 기준 입력/저장 방식이 갈린다.
  bool _isRecurringParty = false;

  /// 얼리버드 종료 기준 — 날짜 직접 선택 / 파티 시작 전.
  PartyEarlyBirdEndType _earlyBirdEndType = PartyEarlyBirdEndType.fixedDate;

  /// '파티 시작 전' 기준의 상대 규칙(N일 전 / N시간 전).
  PartyEarlyBirdDeadlineRule _earlyBirdRule =
      const PartyEarlyBirdDeadlineRule();

  /// 지금 저장/검증에 쓸 종료 기준이 '파티 시작 전'인지 —
  /// 정기 파티는 고정 종료일을 쓸 수 없어 항상 true다.
  bool get _useBeforeStart =>
      _isRecurringParty ||
      _earlyBirdEndType == PartyEarlyBirdEndType.beforeStart;
  DateTime? _earlyBirdEndDate;
  TimeOfDay? _earlyBirdEndTime;

  // ── 장소 설정 ─────────────────────────────────────────────────────
  // 파티는 "직접 입력한 장소"를 그대로 쓰거나, 호스트가 등록한
  // 플레이스(events)에 연결해 그쪽 장소 정보를 가져다 쓸 수 있다.
  //
  // 연결/해제는 parties + events 두 문서를 batch로 함께 갱신해야 하므로
  // (한쪽만 연결된 상태가 생기면 안 된다) "저장" 버튼과 무관하게 즉시
  // 반영된다 — 이 화면의 _save()는 파티 문서의 장소 필드를 건드리지 않는다.
  /// 화면에서 즉시 갱신되는 파티 문서 사본 — 연결 상태·장소 라벨을 여기서 읽는다.
  late Map<String, dynamic> _partyData;

  /// 차수 패키지 — 이 화면은 차수의 **시간·모집 창구**는 고치지 않고 패키지의
  /// 이름·포함 차수·금액만 고친다. 차수 구성이 바뀌지 않으므로 포함 차수가
  /// 유효한 채로 남는다.
  late List<PartyRoundPackage> _roundPackages;

  // ── 차수별 참가비·정원·얼리버드 (라운드 진행 파티) ──────────────────────
  //
  // 라운드 파티의 실제 신청 금액은 `rounds[]`의 차수별 참가비로 계산된다
  // (functions/partyCapacity.js의 computeAppliedFeeForRounds). 그런데 이
  // 화면은 문서 최상단 참가비만 고치고 `rounds`는 저장된 값을 그대로 다시
  // 썼기 때문에, 수정에서 참가비를 바꿔도 상세·신청 금액은 옛 값 그대로였다.
  // 그래서 라운드 파티는 여기서 **차수별 값을 직접** 고친다.
  //
  // 1차도 예외가 아니다 — 1차 참가비의 정본도 `rounds[0]`이다.
  final List<PartyRoundDraft> _roundDrafts = [];

  /// 'none' | 'uniform' | 'perRound' — 등록 화면과 같은 표식.
  String _roundEarlyBirdMode = 'none';

  /// 차수별 값을 이 화면에서 고칠 수 있는 파티인지 — 서버가 차수별 금액으로
  /// 계산하는 조건과 같다(통합 정원 모드는 문서 최상단 하나가 정본이므로
  /// 예전처럼 '참가비 설정' 줄을 그대로 쓴다).
  bool get _editsRoundFees => _supportsRoundPackages;

  // ── 차수별 정원·참가비·얼리버드 편집 UI ────────────────────────────────
  //
  // 등록 화면의 라운드 설정과 같은 자리·같은 순서로 보여준다(시간 → 정원 →
  // 참가비 → 얼리버드). 시간과 모집 창구는 여기서 고치지 않는다 — 그건 일정
  // 자체라 날짜 슬롯·정기 규칙과 함께 다뤄야 하고, 이 화면의 저장 경로는
  // 그 구성을 그대로 옮기는 것을 전제로 돌아간다.

  Widget _roundFeeSection() {
    final separate =
        (_partyData['genderCapacityMode'] as String?) == 'separate';
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '차수별 정원 · 참가비',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            '실제 신청 금액은 신청자가 고른 차수의 참가비로 계산돼요.',
            style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.4),
          ),
          const SizedBox(height: 12),
          const Text(
            '얼리버드 할인',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _roundEarlyBirdModeChip('사용 안 함', 'none')),
              const SizedBox(width: 6),
              Expanded(child: _roundEarlyBirdModeChip('모든 차수 동일', 'uniform')),
              const SizedBox(width: 6),
              Expanded(child: _roundEarlyBirdModeChip('차수별 설정', 'perRound')),
            ],
          ),
          if (_roundEarlyBirdMode == 'uniform') ...[
            const SizedBox(height: 10),
            _uniformEarlyBirdInputs(),
          ],
          const SizedBox(height: 14),
          for (var i = 0; i < _roundDrafts.length; i++)
            _roundCard(_roundDrafts[i], i + 1, separate: separate),
        ],
      ),
    );
  }

  Widget _roundCard(PartyRoundDraft d, int number, {required bool separate}) {
    final label = d.round.labelFor(number);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _roundTimeLabel(d.round),
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: d.minCapacityCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) => _updateRound(
              d,
              d.round.copyWith(minCapacity: int.tryParse(v.trim()) ?? 0),
            ),
            // 이 차수 하나의 최소 인원 — 파티 전체 최소 모집 인원과 다른
            // 값이고, 여기 값들을 더해서 파티 값을 만들지 않는다.
            decoration: _roundDeco('이 차수 최소 인원 (선택)'),
          ),
          const SizedBox(height: 8),
          if (!separate)
            TextField(
              controller: d.capacityCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) => _updateRound(
                d,
                d.round.copyWith(maxCapacity: int.tryParse(v.trim()) ?? 0),
              ),
              decoration: _roundDeco('최대 인원'),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: d.maleCapacityCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => _updateRound(
                      d,
                      d.round.copyWith(
                        maleCapacity: int.tryParse(v.trim()) ?? 0,
                      ),
                    ),
                    decoration: _roundDeco('남자 인원'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: d.femaleCapacityCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => _updateRound(
                      d,
                      d.round.copyWith(
                        femaleCapacity: int.tryParse(v.trim()) ?? 0,
                      ),
                    ),
                    decoration: _roundDeco('여자 인원'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_genderLimit != 'female')
                Expanded(
                  child: TextField(
                    controller: d.maleFeeCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => _updateRound(
                      d,
                      d.round.copyWith(maleFee: int.tryParse(v.trim()) ?? 0),
                    ),
                    decoration: _roundDeco(
                      _genderLimit == 'all' ? '남자 참가비 (원)' : '참가비 (원)',
                    ),
                  ),
                ),
              if (_genderLimit == 'all') const SizedBox(width: 8),
              if (_genderLimit != 'male')
                Expanded(
                  child: TextField(
                    controller: d.femaleFeeCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => _updateRound(
                      d,
                      d.round.copyWith(femaleFee: int.tryParse(v.trim()) ?? 0),
                    ),
                    decoration: _roundDeco(
                      _genderLimit == 'all' ? '여자 참가비 (원)' : '참가비 (원)',
                    ),
                  ),
                ),
            ],
          ),
          if (_roundEarlyBirdMode == 'perRound') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$label 얼리버드',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                ),
                Switch(
                  value: d.round.earlyBird.enabled,
                  activeThumbColor: const Color(0xFFFF6FA0),
                  onChanged: (v) => _updateRound(
                    d,
                    d.round.copyWith(
                      earlyBird: d.round.earlyBird.copyWith(
                        enabled: v,
                        percent: d.round.earlyBird.percent ?? 10,
                        endType: PartyEarlyBirdEndType.beforeStart,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (d.round.earlyBird.enabled)
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: d.earlyBirdPercentCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) => _updateRound(
                        d,
                        d.round.copyWith(
                          earlyBird: d.round.earlyBird.copyWith(
                            percent: int.tryParse(v.trim()),
                          ),
                        ),
                      ),
                      decoration: _roundDeco('할인율 %'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final picked = await _pickEarlyBirdRule(
                          d.round.earlyBird.beforeStartRule,
                        );
                        if (picked == null) return;
                        _updateRound(
                          d,
                          d.round.copyWith(
                            earlyBird: d.round.earlyBird.copyWith(
                              beforeStartRule: picked,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE8EBF2)),
                        ),
                        child: Text(
                          _ruleLabel(d.round.earlyBird.beforeStartRule),
                          style: const TextStyle(fontSize: 13),
                        ),
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

  /// '모든 차수 동일' 얼리버드 — 규칙 한 벌을 받아 저장할 때 모든 차수에
  /// 복사한다. 할인 금액은 각 차수 참가비 기준으로 따로 계산된다.
  Widget _uniformEarlyBirdInputs() {
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
                onChanged: (_) => setState(() => _showFeeError = false),
                decoration: _roundDeco('할인율 %'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final picked = await _pickEarlyBirdRule(_earlyBirdRule);
                  if (picked == null) return;
                  setState(() => _earlyBirdRule = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE8EBF2)),
                  ),
                  child: Text(
                    _ruleLabel(_earlyBirdRule),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '각 차수의 시작 시각 기준이며, 할인 금액은 그 차수 참가비로 계산돼요.',
          style: TextStyle(fontSize: 11, color: Colors.black38),
        ),
      ],
    );
  }

  Widget _roundEarlyBirdModeChip(String title, String mode) {
    final selected = _roundEarlyBirdMode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _roundEarlyBirdMode = mode;
        _earlyBirdEnabled = mode != 'none';
        if (mode != 'none') {
          _earlyBirdEndType = PartyEarlyBirdEndType.beforeStart;
          if (_earlyBirdPercentController.text.trim().isEmpty) {
            _earlyBirdPercentController.text = '10';
          }
        }
        _showFeeError = false;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF3F7) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFFFF6FA0) : const Color(0xFFE8EBF2),
          ),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: selected ? const Color(0xFFFF6FA0) : Colors.black87,
          ),
        ),
      ),
    );
  }

  Future<PartyEarlyBirdDeadlineRule?> _pickEarlyBirdRule(
    PartyEarlyBirdDeadlineRule current,
  ) {
    return showModalBottomSheet<PartyEarlyBirdDeadlineRule>(
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
                  trailing: option == current
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
  }

  String _ruleLabel(PartyEarlyBirdDeadlineRule rule) =>
      '${rule.label}${rule.usesTime ? ' ${formatScheduleTime(rule.time)}' : ''}까지';

  /// 저장된 절대 시각으로 만든 시간 요약 — 이 화면은 차수 시간을 고치지 않으니
  /// 지금 값을 그대로 보여주기만 한다.
  String _roundTimeLabel(PartyRound round) {
    final start = round.startTime;
    final end = round.endTime;
    final s = formatScheduleTime(start);
    return end == null ? s : '$s ~ ${formatScheduleTime(end)}';
  }

  void _updateRound(PartyRoundDraft d, PartyRound next) {
    setState(() {
      d.round = next;
      _showFeeError = false;
    });
  }

  InputDecoration _roundDeco(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 12, color: Colors.black45),
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE8EBF2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFFF6FA0)),
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );

  /// 문서의 `rounds[]`를 편집용 초안으로 되살린다. 1차도 그대로 한 장이다.
  void _initRoundDrafts(Map<String, dynamic> d) {
    if (d['hasMultipleRounds'] != true ||
        (d['roundCapacityMode'] as String?) != 'perRound') {
      return;
    }
    for (final raw in PartyRoundOffers.roundsOf(d)) {
      final round = PartyRound.fromMap(raw);
      if (round != null) _roundDrafts.add(PartyRoundDraft(round));
    }
    if (_roundDrafts.isEmpty) return;
    // 얼리버드 방식 — 저장된 표식이 있으면 그대로, 없으면 지금 값에서 읽는다.
    final stored = d['roundEarlyBirdMode'];
    if (stored == 'none' || stored == 'uniform' || stored == 'perRound') {
      _roundEarlyBirdMode = stored as String;
      return;
    }
    final on = _roundDrafts.where((r) => r.round.earlyBird.enabled).toList();
    if (on.isEmpty) {
      _roundEarlyBirdMode = 'none';
    } else if (on.length == _roundDrafts.length &&
        on.every(
          (r) =>
              r.round.earlyBird.percent == on.first.round.earlyBird.percent &&
              r.round.earlyBird.beforeStartRule ==
                  on.first.round.earlyBird.beforeStartRule,
        )) {
      _roundEarlyBirdMode = 'uniform';
    } else {
      _roundEarlyBirdMode = 'perRound';
    }
  }

  /// 패키지 id → 검증 문구.
  Map<String, String> _packageErrors = const {};

  /// 같은 시리즈의 날짜 슬롯을 다 불러왔는지 — 다 불러온 뒤에만 저장할 수 있다.
  bool _seriesSlotsLoaded = false;

  /// 형제 날짜 조회가 실패했는지 — 이 상태로 저장하면 못 읽은 날짜가 삭제
  /// 대상으로 오해될 수 있어 저장을 막는다([_loadSeriesSlots] 참고).
  bool _seriesSlotsLoadFailed = false;

  /// 이 파티가 차수 패키지를 가질 수 있는지 — 차수별 정원·참가비 모드에서만
  /// 가능하다(서버 partyCapacity.js와 같은 조건).
  bool get _supportsRoundPackages =>
      _partyData['hasMultipleRounds'] == true &&
      (_partyData['roundCapacityMode'] as String?) == 'perRound';

  /// 패키지 편집기가 쓰는 차수 목록.
  ///
  /// 차수 참가비를 이 화면에서 고칠 수 있으므로 **지금 입력 중인 값**을 쓴다 —
  /// 저장된 값을 그대로 읽으면 "1차를 3만원으로 올렸는데 패키지 화면의 개별
  /// 합계는 옛 금액"인 상태가 된다.
  List<RoundPackageRoundInfo> get _packageRoundInfos {
    if (!_supportsRoundPackages) return const [];
    if (_roundDrafts.isNotEmpty) {
      return [
        for (var i = 0; i < _roundDrafts.length; i++)
          RoundPackageRoundInfo(
            roundNumber: i + 1,
            roundId: _roundDrafts[i].round.id,
            label: _roundDrafts[i].round.labelFor(i + 1),
            maleFee: _roundDrafts[i].round.maleFee,
            femaleFee: _roundDrafts[i].round.femaleFee,
          ),
      ];
    }
    return [
      for (final r in PartyRoundOffers.roundsOf(_partyData))
        RoundPackageRoundInfo(
          roundNumber: (r['roundNumber'] as num?)?.toInt() ?? 0,
          roundId: r['id'] as String? ?? '',
          label: (r['label'] as String?)?.trim().isNotEmpty == true
              ? r['label'] as String
              : '${(r['roundNumber'] as num?)?.toInt() ?? 0}차',
          maleFee: (r['maleFee'] as num?)?.toInt() ?? 0,
          femaleFee: (r['femaleFee'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  /// 남녀 참가비를 따로 받는 파티인지 — 패키지 금액 입력칸을 1개/2개로 가른다
  /// (요청: 남녀무관 가격 모드에서는 패키지 가격 하나만 입력).
  bool get _packageSeparateGenderFee {
    if (_roundDrafts.isNotEmpty) {
      return _roundDrafts.any((d) => d.round.maleFee != d.round.femaleFee);
    }
    final maleFee = int.tryParse(_maleFeeController.text.trim()) ?? 0;
    final femaleFee = int.tryParse(_femaleFeeController.text.trim()) ?? 0;
    if (maleFee != femaleFee) return true;
    return PartyRoundOffers.roundsOf(_partyData).any(
      (r) =>
          ((r['maleFee'] as num?)?.toInt() ?? 0) !=
          ((r['femaleFee'] as num?)?.toInt() ?? 0),
    );
  }

  /// 패키지 입력 검증(패키지 id → 문구) — 등록 화면과 같은 모델 규칙을 쓴다.
  Map<String, String> _validatePackageInputs() {
    if (!_supportsRoundPackages || _roundPackages.isEmpty) return const {};
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

  /// 포함된 첫 차수의 시작 시각 — 패키지 얼리버드 종료 시각 캐시의 기준.
  DateTime? _firstRoundStartOf(PartyRoundPackage pkg) {
    final first = pkg.normalizedRoundNumbers.first;
    for (final r in PartyRoundOffers.roundsOf(_partyData)) {
      if ((r['roundNumber'] as num?)?.toInt() == first) {
        final ts = r['time'];
        if (ts is Timestamp) return ts.toDate();
      }
    }
    return null;
  }

  /// 연결된 플레이스 문서 데이터(표시·변경사항 반영용). 필요할 때만 읽는다.
  Map<String, dynamic>? _linkedPlaceData;
  bool _isLinkBusy = false;

  /// 이 파티가 붙어 있는 공간 — 종류와 문서 id를 함께 읽는다. 안 붙어 있으면
  /// null. 판정은 서비스 정본([PlacePartyLink.linkOf]) 하나만 쓴다.
  ///
  /// 예전에는 `linkedEventId`만 봤다. 그 시절엔 일반 파티가 `places`에 붙을
  /// 길이 없었지만, 지금은 등록에서 장소대여를 골라 만든 파티가 그렇게 붙는다 —
  /// events만 보면 그런 파티의 수정 화면이 "연결 안 됨"으로 보인다.
  ({PartyLinkTarget target, String id})? get _link =>
      PlacePartyLink.linkOf(_partyData);

  /// 연결된 문서 id — 없으면 null.
  String? get _linkedTargetId => _link?.id;


  /// 이 파티가 장소와 **한 번에 묶여 등록된** 콤보인지.
  ///
  /// 숙박+파티는 방·패키지 예약까지 얽혀 있고, 플레이스+파티는 장소 문서가
  /// `linkedPartyId`/`bundleId`로 이 파티를 대표로 가리키고 있다. 어느 쪽이든
  /// 여기서 링크만 떼면 번들이 반쪽만 남으므로 장소 변경을 아예 막는다.
  ///
  /// 판정은 묶음 조회와 **같은 기준**을 쓴다([PartyBundleService]). 예전에는
  /// `linkedPlaceId`가 있으면 무조건 콤보로 봤는데, 이제는 일반 등록에서
  /// 장소대여를 골라도 그 필드가 채워진다 — 그대로 두면 그렇게 만든 파티가
  /// "함께 등록된 파티"로 오인돼 장소 연결을 영영 못 바꾸게 된다.
  bool get _isBundledCombo =>
      PartyBundleService.isBundledRegistration(_partyData);

  // ── 함께 등록된 파티(콤보 묶음) ───────────────────────────────────
  // 플레이스+파티 통합 등록은 파티 문서를 날짜 슬롯마다 하나씩 만들면서 모두
  // 같은 `bundleId`로 묶는다. 이 화면에서 형제 파티를 확인하고 각각의 수정
  // 화면으로 바로 갈 수 있게, 열릴 때 한 번 조회해 들고 있는다.
  PartyBundle _bundle = PartyBundle.empty;
  bool _bundleLoading = false;

  /// 이 파티의 묶음이 걸린 플레이스 문서 — 콤보 종류에 따라 컬렉션이 다르다.
  /// (`linkedEventId` → events / `linkedPlaceId` → places)
  ({String collection, String id})? get _bundledPlaceRef {
    final link = _link;
    if (link == null) return null;
    return (collection: link.target.collection, id: link.id);
  }

  /// 장소 설정 카드에 보여줄 플레이스 이름.
  String get _bundledPlaceName {
    final snapshot = _partyData[PlacePartyLink.snapshotField];
    if (snapshot is Map) {
      final name = (snapshot['name'] as String?)?.trim() ?? '';
      if (name.isNotEmpty) return name;
    }
    final cached = (_linkedPlaceData?['name'] as String?)?.trim() ?? '';
    if (cached.isNotEmpty) return cached;
    final placeName = (_partyData['placeName'] as String?)?.trim() ?? '';
    if (placeName.isNotEmpty) return placeName;
    final location = (_partyData['location'] as String?)?.trim() ?? '';
    return location.isNotEmpty ? location : '함께 등록된 플레이스';
  }

  /// "플레이스 변경사항 반영" 버튼을 줄 수 있는 파티인지 —
  /// 신청자가 없고 아직 시작하지 않은 파티만.
  bool get _canRefreshPlaceSnapshot {
    if (_linkedTargetId == null) return false;
    if (PlacePartyLink.hasApplicants(_partyData)) return false;
    final dt = PartyCard.parsePartyDateTime(_partyData);
    return dt == null || dt.isAfter(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    // 오픈예정이 아니어도 인증 상태는 항상 읽는다 — 날짜를 새로 추가하면
    // 새 파티 문서가 만들어지고, 그 문서에 지금의 인증 상태를 실어야 한다.
    _loadOpeningPolicy();
    final d = widget.data;
    _partyData = Map<String, dynamic>.from(d);
    _roundPackages = PartyRoundPackage.listFrom(d['roundPackages']);
    _initRoundDrafts(d);

    // 파티 제목. 플레이스+파티(숙박+파티) 콤보로 등록된 예전 데이터는 제목을
    // 하나만 갖고 있어 파티 쪽 title이 비어 있을 수 있다 — 그럴 때는 함께
    // 저장된 플레이스 이름을 기본값으로 채워 빈 칸으로 열리지 않게 한다.
    _titleController = PartyTitleController(
      text: (d['title'] as String?)?.trim().isNotEmpty == true
          ? d['title'] as String
          : (d['name'] as String? ?? d['placeName'] as String? ?? ''),
    );
    _partychuPerkController = TextEditingController(
      text: partychuPerkFrom(d) ?? '',
    );
    _descController = TextEditingController(
      text: d['description'] as String? ?? '',
    );
    _capacityController = TextEditingController(
      text: (d['maxParticipants'] as int?)?.toString() ?? '',
    );
    // 파티 전체 최소 모집 인원 — 새 필드가 없는 옛 문서(차수 합계로 오염된
    // minCapacity)는 안전한 폴백을 탄다([PartyMinCapacity]).
    _minCapacity = PartyMinCapacity.of(d);
    _minCapacityPolicy = PartyMinCapacityPolicy.fromKey(
      d['minCapacityPolicy'] as String?,
    );
    _genderLimit = d['genderLimit'] as String? ?? 'all';
    // 참가자 현황 공개 — 필드가 없던 파티는 공개로 읽는다(기존 동작 유지).
    _revealParticipantGenderRatio = ParticipantGenderVisibility.of(d);
    _maleFeeController = TextEditingController(
      text: (d['maleFee'] as num?)?.toInt().toString() ?? '',
    );
    _femaleFeeController = TextEditingController(
      text: (d['femaleFee'] as num?)?.toInt().toString() ?? '',
    );
    _refundTiers = RefundTier.listFromDynamic(d['refundPolicy']);
    // 결제 방식 — 기존 설정값을 그대로 불러와 수정할 수 있게 한다.
    _paymentPolicy = PaymentPolicy.fromMap(d);
    // 신청 방식 — 필드가 없는 기존 파티는 즉시 확정으로 읽힌다.
    final form = PartyApplicationForm.fromParty(d);
    _approvalMode = form.mode;
    _appQuestions = [...form.questions];
    _requireApplicantPhotos = form.requirePhotos;
    _partyTypes = ((d['partyTypes'] as List?)?.cast<String>() ?? []).toSet();
    _vibes = ((d['vibes'] as List?)?.cast<String>() ?? []).toSet();
    _tags = List<String>.from((d['tags'] as List?)?.cast<String>() ?? []);
    _recruitStatus = d['recruitStatus'] as String? ?? '모집중';
    if (!_statuses.contains(_recruitStatus)) _recruitStatus = '모집중';
    _maleRecruitOpen = !PartyGenderRecruit.isMaleClosed(d);
    _femaleRecruitOpen = !PartyGenderRecruit.isFemaleClosed(d);
    // 게스트 문의 받기 — 필드가 없던 옛 파티는 켜진 것으로 읽는다
    // (ListingInquiry 상단 주석).
    _inquiryEnabled = ListingInquiry.isEnabled(d);
    _inquiryGuideCtrl.text = ListingInquiry.guideOf(d);

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

    // 상세 이미지(선택) — 저장돼 있던 것을 그대로 복원한다. 손대지 않고
    // 저장하면 같은 URL이 다시 저장되므로 값이 유지된다.
    _detailImage = PartyDetailImageDraft.fromPartyData(d);
    _originalDetailImageUrl = _detailImage.uploadedUrl;

    // 얼리버드 할인 — 만료 여부와 무관하게 기존 설정을 그대로 불러와 수정 가능하게 한다.
    // 정기 파티는 고정 종료 시각 대신 회차 기준 규칙(earlyBirdDeadlineRule)이
    // 저장돼 있다.
    _isRecurringParty = PartySchedule.isRecurring(d);
    _earlyBirdEnabled = d['earlyBirdEnabled'] as bool? ?? false;
    final earlyBirdEndTs = d['earlyBirdEndAt'] as Timestamp?;
    final ruleRaw = d[kEarlyBirdRuleField];
    final savedRule = ruleRaw is Map
        ? PartyEarlyBirdDeadlineRule.fromMap(Map<String, dynamic>.from(ruleRaw))
        : null;
    if (_earlyBirdEnabled && savedRule != null) {
      _earlyBirdPercentController.text =
          '${(d['earlyBirdDiscountPercent'] as num?)?.toInt() ?? 10}';
      _earlyBirdEndType = PartyEarlyBirdEndType.beforeStart;
      _earlyBirdRule = savedRule;
    } else if (_earlyBirdEnabled && earlyBirdEndTs != null) {
      _earlyBirdPercentController.text =
          '${(d['earlyBirdDiscountPercent'] as num?)?.toInt() ?? 10}';
      final endDt = earlyBirdEndTs.toDate();
      _earlyBirdEndDate = DateTime(endDt.year, endDt.month, endDt.day);
      _earlyBirdEndTime = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
    } else {
      _earlyBirdEnabled = false;
    }

    // 기존에 저장된 상세페이지 블록 복원 — 필드가 없는 기존 파티는 빈 리스트.
    _detailBlocks = PartyDetailBlock.listFromDynamic(
      d['detailBlocks'],
    ).map((b) => PartyDetailBlockDraft.fromBlock(b)).toList();
    // 기존에 저장된 디자인 테마 복원 — 없거나 알 수 없는 값이면 partychu.
    _detailTheme = partyDetailThemeKeyFromString(d['detailTheme'] as String?);
    _detailDecorationIntensity = partyDetailDecorationIntensityFromString(
      d['detailDecorationIntensity'] as String?,
    );
    // 필드가 없으면(이 기능 이전에 등록된 파티) 0 — 지금까지 암묵적으로
    // 써온 시드와 같아 회귀 없이 그대로 렌더링된다.
    _detailDecorationVariantSeed =
        (d['detailDecorationVariantSeed'] as num?)?.toInt() ?? 0;
    // 상세 설명 방식 복원 — 필드가 없는(이 기능 이전에 등록된) 파티는
    // detailBlocks 유무로 추론한다("블록형 상세페이지를 작성한 데이터가
    // 있으면 수정 화면은 '직접 상세페이지 만들기'로 열림" 요구사항).
    final descriptionModeRaw = d['detailDescriptionMode'] as String?;
    _descriptionMode = descriptionModeRaw != null
        ? partyDescriptionModeFromString(descriptionModeRaw)
        : (_detailBlocks.isNotEmpty
              ? PartyDescriptionMode.blocks
              : PartyDescriptionMode.auto);
    _autoDescriptionStyle = PartyAutoDescriptionStyle.fromMap(
      d['autoDescriptionStyle'] as Map<String, dynamic>?,
    );

    // 일정 복원 — 정기 파티면 반복 규칙 그대로, 일회성이면 이 문서의 날짜
    // 한 건을 슬롯 하나로 되살린다. 모집 시작·마감 규칙과 차수도 함께 복원
    // 된다. 등록/재등록/수정이 전부 같은 헬퍼를 쓴다.
    _schedule = PartyScheduleDraft.fromPartyData(d);

    // 여기까지가 "불러온 그대로"의 상태 — 이후 사용자가 뭔가 바꿨는지는 이
    // 지문과 비교해서 판단한다(형제 파티 수정 화면으로 넘어가기 전 경고용).
    _initialSnapshot = _editSnapshot();

    _loadBundle();
    // 여러 날짜로 등록된 게시글은 날짜마다 문서가 따로 있다 — 위 복원은 이
    // 문서의 날짜 하나만 되살리므로, 같은 seriesId의 나머지 날짜를 이어서
    // 붙인다(등록 화면과 같은 방식). 그래야 "8/10, 8/13"이 그대로 보이고
    // 추가·삭제까지 된다.
    _loadSeriesSlots();
  }

  /// 같은 게시글(`seriesId`)의 다른 날짜 문서를 읽어 일정 슬롯으로 이어 붙인다.
  ///
  /// 정기 파티는 규칙 하나가 곧 일정이라 대상이 아니다.
  ///
  /// **조회에 실패하면 저장을 막는다**([_seriesSlotsLoadFailed]). 슬롯 목록이
  /// 반쪽인 상태로 저장하면, 못 불러온 날짜가 "사용자가 지운 날짜"로 오해돼
  /// 삭제될 수 있기 때문이다.
  Future<void> _loadSeriesSlots() async {
    if (_schedule.isRecurring) {
      setState(() => _seriesSlotsLoaded = true);
      return;
    }
    final seriesId = (widget.data['seriesId'] as String?)?.trim();
    if (seriesId == null || seriesId.isEmpty) {
      // 레거시 문서 — 시리즈가 자기 하나뿐이라 더 읽을 것이 없다.
      setState(() => _seriesSlotsLoaded = true);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('parties')
          .where('seriesId', isEqualTo: seriesId)
          .get();
      if (!mounted) return;
      final slots = [..._schedule.slots];
      final seen = slots.map((s) => s.dedupeKey).toSet();
      for (final doc in snap.docs) {
        if (doc.id == widget.docId) continue;
        final sibling = doc.data();
        if (sibling['isDeleted'] == true || sibling['status'] == 'deleted') {
          continue;
        }
        for (final slot in PartyScheduleDraft.fromPartyData(sibling).slots) {
          if (seen.add(slot.dedupeKey)) slots.add(slot);
        }
      }
      slots.sort((a, b) => a.start.compareTo(b.start));
      setState(() {
        _schedule = _schedule.copyWith(slots: slots);
        _seriesSlotsLoaded = true;
        // 불러온 날짜까지 포함해 지문을 다시 잡는다 — 안 그러면 화면에 손도
        // 대지 않았는데 "일정이 바뀌었다"로 잡혀 경고가 뜬다.
        _initialSnapshot = _editSnapshot();
      });
    } catch (e) {
      // 못 읽었으면 저장을 막는다 — 슬롯 목록이 반쪽인 상태로 저장하면
      // 못 불러온 날짜가 "사용자가 지운 날짜"로 오해돼 삭제될 수 있다.
      debugPrint('[PartyEdit] 시리즈 일정 조회 실패: $e');
      if (mounted) setState(() => _seriesSlotsLoadFailed = true);
    }
  }

  // ── 미저장 변경 감지 ──────────────────────────────────────────────
  // 저장 버튼을 누르지 않은 편집 내용이 있는지 — 형제 파티의 수정 화면으로
  // 이동하기 전에 확인창을 띄우기 위해 필요하다. 필드가 많아 개별 리스너를
  // 다는 대신, 저장에 실제로 쓰이는 값들을 문자열 하나로 직렬화해 초깃값과
  // 비교한다(=순수 비교라 언제 호출해도 안전하다).
  late String _initialSnapshot;

  String _editSnapshot() {
    final cover = _mediaCoverPick;
    final blocks = _detailBlocks.map((d) => d.toBlock()).toList();
    return [
      // 일정도 저장 대상이므로 지문에 넣는다 — 안 넣으면 날짜만 고쳐둔 채
      // 형제 파티로 넘어갈 때 "변경 없음"으로 보여 편집이 조용히 사라진다.
      _scheduleSnapshot(_schedule),
      _titleController.text.trim(),
      _descController.text.trim(),
      _partychuPerkController.text.trim(),
      _capacityController.text.trim(),
      _maleFeeController.text.trim(),
      _femaleFeeController.text.trim(),
      _recruitStatus,
      '$_maleRecruitOpen/$_femaleRecruitOpen',
      _genderLimit,
      RefundTier.listToMaps(_refundTiers).toString(),
      _paymentPolicy?.toMap().toString() ?? '',
      (_partyTypes.toList()..sort()).join(','),
      (_vibes.toList()..sort()).join(','),
      _tags.join(','),
      _mediaExistingImageUrls.join(','),
      _mediaExistingVideoUrl ?? '',
      _mediaNewFiles.map((f) => f.path).join(','),
      '${cover?.existingImageUrl}/${cover?.isExistingVideo}'
          '/${cover?.newImageOrdinal}/${cover?.isNewVideo}',
      '$_mediaBasicCardFocalX/$_mediaBasicCardFocalY/$_mediaBasicCardScale',
      _mediaPhotoCrops.toString(),
      _detailImage.signature,
      '$_earlyBirdEnabled',
      _earlyBirdPercentController.text.trim(),
      _earlyBirdEndType.name,
      _earlyBirdRule.toMap().toString(),
      '${_earlyBirdEndDate?.toIso8601String()}',
      '${_earlyBirdEndTime?.hour}:${_earlyBirdEndTime?.minute}',
      _descriptionMode.name,
      _autoDescriptionStyle.toMap().toString(),
      _detailTheme.name,
      _detailDecorationIntensity.name,
      '$_detailDecorationVariantSeed',
      PartyDetailBlock.listToMaps(blocks).toString(),
      // 아직 업로드 전인 상세페이지 사진/동영상은 toBlock()에 URL이 없어
      // 드러나지 않는다 — 고른 파일 경로를 따로 얹어 교체도 감지되게 한다.
      _detailBlocks
          .map(
            (d) => [
              d.newImageFile?.path ?? '',
              d.newVideoFile?.path ?? '',
              d.imageGroupItems
                  .map((i) => i.newImageFile?.path ?? '')
                  .join(','),
            ].join('/'),
          )
          .join(';'),
    ].join('|');
  }

  bool get _hasUnsavedChanges => _editSnapshot() != _initialSnapshot;

  // ── 함께 등록된 파티 조회 ─────────────────────────────────────────

  Future<void> _loadBundle() async {
    setState(() => _bundleLoading = true);
    try {
      // 인증 조회도 try 안에 둔다 — 이 메서드는 initState에서 await 없이
      // 불리므로, 여기서 새는 예외는 아무도 받지 않는 비동기 오류가 되어
      // 화면 전체를 무너뜨린다. 아래 catch가 이미 "묶음은 못 읽어도 수정은
      // 계속한다"로 처리하고 있으니 같은 규칙을 첫 줄에도 적용한다.
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isEmpty) return;
      final bundle = await PartyBundleService.load(
        partyId: widget.docId,
        partyData: _partyData,
        hostId: uid,
      );
      if (!mounted) return;
      setState(() => _bundle = bundle);
    } catch (e) {
      debugPrint('[PartyEdit] 함께 등록된 파티 조회 실패: $e');
    } finally {
      if (mounted) setState(() => _bundleLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _partychuPerkController.dispose();
    _inquiryGuideCtrl.dispose();
    _capacityController.dispose();
    _maleFeeController.dispose();
    _femaleFeeController.dispose();
    _earlyBirdPercentController.dispose();
    for (final d in _detailBlocks) {
      d.dispose();
    }
    for (final d in _roundDrafts) {
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

  /// 일정 입력값 검증. 문제 없으면 null 반환.
  String? _validateSchedule() {
    if (_schedule.isRecurring) {
      return _schedule.recurring.nextOccurrence(DateTime.now()) == null
          ? '반복 요일과 시간을 정해줘'
          : null;
    }
    final ready = _schedule.slots.where((s) => s.startTime != null).toList();
    if (ready.isEmpty) return '파티 날짜와 시간을 정해줘';
    // 수정도 재등록과 똑같이 날짜를 여러 개 다룬다 — 슬롯↔문서 동기화를
    // 공용 서비스(PartySlotSyncService)가 맡으므로, 날짜를 추가하면 문서가
    // 새로 생기고 지우면 그 문서가 삭제된다.
    return null;
  }

  /// 이미 신청자가 있는 파티의 일정을 바꾸려 할 때 한 번 물어본다 —
  /// 신청·결제와 차수 데이터가 옛 날짜 기준으로 잡혀 있기 때문이다.
  Future<bool> _confirmRiskyScheduleChange() async {
    if (!_scheduleChangeIsRisky) return true;
    if (!_scheduleChanged) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('일정을 바꿀까요?'),
        content: const Text(
          '이미 신청한 사람이 있는 파티예요. 날짜·시간을 바꾸면 신청자가 알던 일정과 '
          '달라지고, 차수·모집 마감도 새 날짜 기준으로 다시 계산됩니다.\n\n'
          '그대로 진행할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('바꾸기'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// 불러온 일정에서 실제로 달라진 게 있는지.
  bool get _scheduleChanged =>
      _scheduleSnapshot(_schedule) !=
      _scheduleSnapshot(PartyScheduleDraft.fromPartyData(widget.data));

  String _scheduleSnapshot(PartyScheduleDraft s) => [
    s.type.name,
    s.slots
        .map((e) => '${e.date.toIso8601String()}/${e.startTime}/${e.endTime}')
        .join('|'),
    s.openRule.toMap().toString(),
    s.deadlineRule.toMap().toString(),
    s.recurring.toMap().toString(),
  ].join('#');

  /// 얼리버드 할인 입력값 검증. 문제 없으면 null 반환.
  String? _validateEarlyBird() {
    final pct = int.tryParse(_earlyBirdPercentController.text.trim());
    if (pct == null || pct < 1 || pct > 99) {
      return '얼리버드 할인율은 1~99% 사이로 입력해주세요.';
    }
    // '파티 시작 전' 기준은 고정 종료 시각이 없다 — 상대 규칙만 확인한다.
    // (정기 파티는 회차마다 날짜가 달라 항상 이쪽이다.)
    if (_useBeforeStart) {
      if (_earlyBirdRule.mode == EarlyBirdDeadlineMode.daysBefore &&
          _earlyBirdRule.days < 0) {
        return '얼리버드 종료 기준일은 0일 이상이어야 합니다.';
      }
      if (_earlyBirdRule.mode == EarlyBirdDeadlineMode.hoursBefore &&
          _earlyBirdRule.hours < 1) {
        return '얼리버드 종료 기준 시간은 1시간 이상이어야 합니다.';
      }
    } else {
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
    // 날짜 슬롯을 다 불러오기 전에 저장하면, 아직 화면에 없는 날짜가 "지운
    // 날짜"로 오해돼 문서가 삭제될 수 있다 — 불러오기가 끝날 때까지 막는다.
    if (!_seriesSlotsLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _seriesSlotsLoadFailed
                ? '일정 정보를 불러오지 못했어요. 화면을 다시 열어주세요.'
                : '일정 정보를 불러오는 중이에요. 잠시만 기다려주세요.',
          ),
        ),
      );
      return;
    }
    final formValid = _formKey.currentState!.validate();
    // 라운드 파티는 인원·참가비가 차수마다 있다 — 문서 최상단 칸(합계·대표값)
    // 이 아니라 차수 입력을 검사한다.
    final roundError = _editsRoundFees ? _validateRoundDrafts() : null;
    final capacityError = _editsRoundFees
        ? false
        : _capacityController.text.trim().isEmpty;
    final maleFeeError = _editsRoundFees
        ? false
        : (_genderLimit != 'female' && _maleFeeController.text.trim().isEmpty);
    final femaleFeeError = _editsRoundFees
        ? false
        : (_genderLimit != 'male' && _femaleFeeController.text.trim().isEmpty);
    final introError = _descController.text.trim().isEmpty;
    // 사진/동영상이 2개 이상 등록됐는데 그중 대표를 직접 고르지 않았으면
    // 막는다 — 1개뿐이면 고를 것도 없으니 그대로 자동 대표 처리한다.
    final mediaCoverError = _totalMediaCount() > 1 && _mediaCoverPick == null;

    String? earlyBirdErr;
    if (_earlyBirdEnabled) {
      earlyBirdErr = _validateEarlyBird();
    }
    final scheduleErr = _validateSchedule();

    // 환불 규정 최소 1개 — 등록 화면과 **같은 규칙**([RefundPolicyRule]).
    // 구간 없이 저장돼 있던 옛 파티도 화면 진입은 그대로 되고, 여기서부터 막힌다.
    final refundError = RefundPolicyRule.isMissing(_refundTiers);

    setState(() {
      _showCapacityError = capacityError;
      _showFeeError =
          maleFeeError ||
          femaleFeeError ||
          earlyBirdErr != null ||
          roundError != null;
      _showIntroError = introError;
      _showMediaCoverError = mediaCoverError;
      _showDateError = scheduleErr != null;
      _showRefundError = refundError;
    });

    if (!formValid ||
        capacityError ||
        maleFeeError ||
        femaleFeeError ||
        introError ||
        mediaCoverError) {
      return;
    }
    if (refundError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(RefundPolicyRule.requiredMessage)),
      );
      return;
    }
    if (scheduleErr != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(scheduleErr)));
      return;
    }
    if (earlyBirdErr != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(earlyBirdErr)));
      return;
    }
    if (roundError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(roundError)));
      return;
    }
    // 차수 패키지 검증 — 등록 화면과 같은 규칙(모델이 갖고 있다).
    final packageErrors = _validatePackageInputs();
    if (packageErrors.isNotEmpty) {
      setState(() => _packageErrors = packageErrors);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(packageErrors.values.first)));
      return;
    }
    // 이미 신청자가 있는 파티의 날짜를 바꾸는 경우에만 한 번 확인한다.
    if (!await _confirmRiskyScheduleChange()) return;
    if (!mounted) return;

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
      CloudflareService.logMissingConfig('party-edit');
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
      //
      // 등록 화면과 **같은 공용 업로더**를 쓴다. 예전에는 여기만 옛 복사 루프가
      // 남아 있어서, 등록 화면에는 있는 업로드 전 검사(경로가 로컬 파일인지 ·
      // 파일이 실제로 있는지 · 0바이트는 아닌지)와 단계별 로그가 수정 화면에는
      // 없었다. 그래서 같은 동영상이 등록에서는 원인이 찍히고 수정에서는
      // "저장에 실패했습니다"만 떴다.
      //
      // 사진 진행률도 이 참에 바로잡힌다 — 옛 루프는 분모에 동영상까지 넣어
      // 사진 1장 + 동영상 1개일 때 "사진을 올리는 중... (1/2)"로 보였다.
      final upload = await MediaUploadService.uploadNewMedia(
        media: newMedia,
        logTag: 'party-edit-media',
        onVideoStart: () => setState(() => _uploadStatus = '동영상을 올리는 중...'),
        onImageProgress: (done, total) =>
            setState(() => _uploadStatus = '사진을 올리는 중... ($done/$total)'),
      );
      final newImageUrls = upload.imageUrls;
      final newVideoUid = upload.videoUid;
      final newVideoUrl = upload.videoUrl;
      final newVideoThumbnailUrl = upload.videoThumbnailUrl;

      // 상세 이미지(선택) — 대표 미디어와 따로 올린다(결과가 images 배열에
      // 섞이면 안 된다). 새로 고른 파일이 없으면 아무것도 올리지 않고 기존
      // URL이 그대로 유지된다 = "수정 없이 저장하면 그대로".
      // 업로더는 등록 화면과 동일한 공용 경로다(저장 위치만 하위 폴더).
      String? newDetailImageUrl;
      if (_detailImage.hasNewFile) {
        setState(() => _uploadStatus = '상세 이미지를 올리는 중...');
        final detailUpload = await MediaUploadService.uploadNewMedia(
          media: [_detailImage.newFile!],
          logTag: 'party-edit-detail-image',
          uploadImage: (file) => CloudflareService.uploadImage(
            file,
            folder: PartyDetailImage.storageFolder,
          ),
        );
        newDetailImageUrl = detailUpload.imageUrls.isNotEmpty
            ? detailUpload.imageUrls.first
            : null;
        if (newDetailImageUrl != null) {
          uploadedBlockImageUrls.add(newDetailImageUrl);
        }
      }
      final detailImage = _detailImage.resolve(
        newUploadedUrl: newDetailImageUrl,
      );

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

      // 라운드 파티의 문서 최상단 값은 **차수에서 파생된 대표값**이다 —
      // 정원은 차수 합계(등록 화면과 같은 규칙), 참가비는 1차 값이다.
      // 목록 카드·검색·결제 정책 판정처럼 차수를 모르는 코드가 이 값을 읽는다.
      final primaryRound = _editsRoundFees && _roundDrafts.isNotEmpty
          ? _roundDrafts.first.round
          : null;
      final maxParticipants = _editsRoundFees && _roundDrafts.isNotEmpty
          ? _roundDrafts.fold<int>(
              0,
              (total, d) => total + d.round.separateTotal,
            )
          : (int.tryParse(_capacityController.text.trim()) ??
                (widget.data['maxParticipants'] as int? ?? 0));
      // ⚠️ 최소 모집 인원은 **합산하지 않는다.** 정원은 자리 수라 차수 합계가
      // 곧 총 정원이지만, 최소 모집 인원은 "이 파티(회차)가 열리려면 몇 명이
      // 와야 하는가"라 더할 수 있는 값이 아니다 — 1차·2차를 모두 신청한 한
      // 사람이 두 번 세진다. 차수 최소 인원은 rounds[]에만 남는다
      // ([PartyMinCapacity]).
      final minCapacity = _minCapacity;
      final current = (widget.data['currentParticipants'] as int?) ?? 0;
      final maleFee = _genderLimit != 'female'
          ? (primaryRound?.maleFee ??
                int.tryParse(_maleFeeController.text.trim()) ??
                0)
          : null;
      final femaleFee = _genderLimit != 'male'
          ? (primaryRound?.femaleFee ??
                int.tryParse(_femaleFeeController.text.trim()) ??
                0)
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
      // 정기 파티는 고정 종료 시각이 없어도(회차 규칙만으로) 유효하다.
      final earlyBirdActuallyEnabled =
          _earlyBirdEnabled && (_isRecurringParty || earlyBirdEndAt != null);

      final partychuPerk = _partychuPerkController.text.trim();
      // 두 모드가 **똑같이** 저장하는 필드 묶음. 수정은 이걸 그대로 기존
      // 문서에 update하고, 재등록은 여기에 새 일정·초기화된 카운터를 얹어
      // 새 문서로 set한다.
      final fields = <String, dynamic>{
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
        // 새 필드(정본) + 옛 필드를 같은 값으로 함께 쓴다 — 이 문서를 아직
        // 업데이트 안 된 코드가 읽어도 어긋나지 않게.
        PartyMinCapacity.field: minCapacity,
        'minCapacity': minCapacity,
        // 정기 파티도 자동 취소를 쓸 수 있다 — 취소 단위가 미달된 회차 하나다.
        'minCapacityPolicy': minCapacity > 0
            ? _minCapacityPolicy.key
            : PartyMinCapacityPolicy.proceed.key,
        // 참가자 현황 공개 — 호스트가 언제든 바꿀 수 있어야 하므로 수정
        // 저장에서도 항상 쓴다(게스트 문의 받기와 같은 규칙). 값이 없던
        // 파티에 true를 적어도 뜻이 달라지지 않고(없음=공개), 숨김으로
        // 바꾼 순간에는 반드시 적혀야 한다.
        ParticipantGenderVisibility.field: _revealParticipantGenderRatio,
        'recruitStatus': _recruitStatus,
        // 성별별 모집 상태 — 남·여 모두 모집중이면 null이 들어가 필드가 지워진다
        // (기본값과 같은 상태를 문서에 남기지 않는다: PartyGenderRecruit.toField).
        // 호스트가 언제든 바꿀 수 있어야 하므로 수정 저장에서도 항상 쓴다.
        PartyGenderRecruit.field: PartyGenderRecruit.toField(
          maleClosed: !_maleRecruitOpen,
          femaleClosed: !_femaleRecruitOpen,
        ),
        // 게스트 문의 받기 — 등록 화면과 같은 필드 하나다. 호스트가 언제든
        // 켜고 끌 수 있어야 하므로 수정 저장에서도 항상 쓴다.
        ...ListingInquiry.toMap(_inquiryEnabled, _inquiryGuideCtrl.text),
        'people': '$current/$maxParticipants명',
        'maleFee': maleFee,
        'femaleFee': femaleFee,
        'refundPolicy': RefundTier.listToMaps(_refundTiers),
        // 결제 방식 — 무료 파티이거나 설정 안 함이면 필드를 만들지 않는다.
        if (!_isFree && _paymentPolicy != null) ..._paymentPolicy!.toMap(),
        'earlyBirdEnabled': earlyBirdActuallyEnabled,
        'earlyBirdDiscountPercent': earlyBirdActuallyEnabled
            ? (int.tryParse(_earlyBirdPercentController.text.trim()) ?? 0)
            : null,
        // 일회성은 고정 종료 시각, 정기는 회차 규칙 — 한 문서에 둘이
        // 섞이지 않도록 반대쪽은 명시적으로 null로 지운다.
        kEarlyBirdEndTypeField: earlyBirdActuallyEnabled
            ? (_useBeforeStart
                  ? PartyEarlyBirdEndType.beforeStart.key
                  : PartyEarlyBirdEndType.fixedDate.key)
            : null,
        'earlyBirdEndAt':
            earlyBirdActuallyEnabled &&
                !_useBeforeStart &&
                earlyBirdEndAt != null
            ? Timestamp.fromDate(earlyBirdEndAt)
            : null,
        kEarlyBirdRuleField: earlyBirdActuallyEnabled && _useBeforeStart
            ? _earlyBirdRule.toMap()
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
        // 상세 본문 전용 세로형 이미지 1장(선택). 지웠으면 빈 값으로 덮어써야
        // 한다 — 키를 빼면 update가 예전 URL을 그대로 남긴다
        // (PartyDetailImage.toFirestore 주석 참고).
        ...PartyDetailImage.toFirestore(detailImage),
        // 배경음악(Spotify) 기능은 제거됐다 — 예전 문서에 남아 있는
        // spotify* 필드는 아무 데서도 읽지 않으므로 그대로 두고, 저장할 때
        // 새로 쓰지 않는다. 이 fields 맵은 기존 날짜 문서에는 update로,
        // 새로 생기는 날짜 문서에는 set으로 쓰이므로(PartySlotSyncService)
        // FieldValue.delete()를 섞으면 set 쪽에서 실패한다.
        // 파티츄 전용 혜택 — 다 지우면 빈 문자열로 저장돼 명패/카드가
        // 사라진다(필드를 남겨둬야 예전 값이 되살아나지 않는다).
        kPartychuPerkField: partychuPerk,
        // 차수 패키지 — 이 화면에서 이름·포함 차수·금액을 고칠 수 있다. 얼리버드
        // 종료 시각 캐시는 지금 문서의 차수 시작 시각으로 다시 계산한다.
        if (_supportsRoundPackages)
          'roundPackages': [
            for (final p in _roundPackages)
              p.toMap(firstRoundStart: _firstRoundStartOf(p)),
          ],
        // 라운드 파티의 문서 최상단 얼리버드는 **대표값**이다 — 실제 할인은
        // 차수별 규칙으로 계산되고, 이 값은 목록 카드 뱃지와 '얼리버드
        // 진행중' 필터가 읽는다. 위에서 쓴 값을 여기서 덮어쓴다.
        if (_editsRoundFees) ...{
          ..._representativeEarlyBird.toMapFor(isRecurring: _isRecurringParty),
          'roundEarlyBirdMode': _roundEarlyBirdMode,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 날짜 슬롯 ↔ 문서 동기화는 등록 화면과 **같은 서비스**가 한다 —
      // 날짜를 추가하면 문서가 새로 생기고, 지우면 그 날짜 문서가 삭제되고
      // (신청자가 있으면 서버 정책이 막는다), 남은 날짜는 update된다.
      final slotOutcome = await _commitScheduleSlots(fields);

      // 콤보로 등록된 파티면 연결된 플레이스/형제 파티 문서에도 같은 혜택을
      // 반영한다 — 어느 상세로 들어와도 같은 혜택이 보이게.
      await syncPartychuPerkAcrossBundle(
        bundleId: widget.data['bundleId'] as String?,
        perk: partychuPerk,
        selfDocId: widget.docId,
      );

      // 신청 방식 + 사전질문 — 파티 문서에 직접 못 쓰는 두 필드라 저장이 끝난
      // 뒤 콜러블로 보낸다(firestore.rules에서 클라이언트 쓰기가 막혀 있다).
      // 날짜를 여러 개 쓰는 파티는 이번에 저장된 문서 전부에 같은 설정이 간다.
      final formError = await PartyApplicationFormService.save(
        partyIds: slotOutcome.savedDocIds.isEmpty
            ? [widget.docId]
            : slotOutcome.savedDocIds,
        mode: _approvalMode,
        questions: _appQuestions,
        requirePhotos: _requireApplicantPhotos,
      );

      // 저장이 끝났으니 이제 안 쓰는 옛 상세 이미지를 정리한다 — 교체했거나
      // 삭제했을 때다. 저장 **전에** 지우면 저장이 실패했을 때 화면에는
      // 남아 있는데 원본은 사라진 상태가 된다. 실패해도 저장 결과에는 영향을
      // 주지 않도록 기다리지 않고 흘려보낸다(프로필 사진 교체와 같은 방식 —
      // my_page_screen.dart 참고).
      final oldDetailUrl = _originalDetailImageUrl;
      if (oldDetailUrl != null &&
          oldDetailUrl.isNotEmpty &&
          oldDetailUrl != detailImage?.url) {
        unawaited(
          CloudflareService.deleteImage(oldDetailUrl).catchError((_) {}),
        );
      }
      // 이번 저장이 반영된 상태를 새 기준으로 삼는다(연속 저장 시 이미 지운
      // URL을 또 지우려 하지 않게).
      _originalDetailImageUrl = detailImage?.url;
      // 새 파일은 업로드가 끝났으므로 URL만 남긴다 — 다시 저장할 때 같은
      // 파일을 한 번 더 올리지 않는다.
      _detailImage = _detailImage.settled(newUploadedUrl: detailImage?.url);

      if (!mounted) return;
      // 승인제로 바꿨는데 저장에 실패하면 반드시 알린다 — 호스트는 승인제라고
      // 믿는데 실제로는 즉시확정으로 신청을 받게 된다.
      if (formError != null && _approvalMode == PartyApprovalMode.manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('신청 방식을 저장하지 못했어요 — $formError')),
        );
      }
      // 지운 날짜가 서버 정책에 걸렸다면(저장 사이에 신청자가 생긴 경우 등)
      // 편집 내용은 이미 저장됐으므로, 되돌리지 않고 사실만 알린다.
      if (slotOutcome.hasDeleteFailures) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '일부 날짜를 삭제하지 못했어요: '
              '${slotOutcome.deleteFailures.values.first}',
            ),
          ),
        );
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: const Text('수정이 완료되었습니다')));
      Navigator.pop(context);
    } catch (e, st) {
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
      // 원인은 로그에, 사용자에게는 **갈래에 맞는 안내**를 준다.
      //
      // 예전에는 예외 원문을 그대로 스낵바에 붙였다("저장에 실패했습니다:
      // [cloud_firestore/permission-denied] ..."). 사용자는 그걸 읽고 할 수
      // 있는 일이 없고, 내부 사정(권한·경로)이 그대로 노출된다. 반대로 로그는
      // 하나도 남지 않아 개발자도 원인을 못 찾았다. 다른 등록 화면들과 같은
      // 함수를 써서 둘 다 해결한다 — 사진이 문제면 그 사진을 빼라고, 인증·
      // 네트워크가 문제면 다시 시도하라고 안내한다.
      MediaUploadService.logUploadError(
        e,
        st,
        logTag: 'party-media',
        label: '❌ 파티 수정 저장 실패',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(RegisterValidation.failureMessage(e, stage: '저장')),
          ),
        );
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

  // ── 일정 저장 ─────────────────────────────────────────────────────

  /// 슬롯 하나에 적용할 **날짜 종속 필드**. 등록 화면의 `buildSlotDateFields`와
  /// 같은 값을 만든다(문서를 읽는 쪽이 두 화면을 구분할 필요가 없어야 한다).
  ///
  /// [existing]은 저장 대상 문서의 현재 값(새 문서면 null) — 차수별 신청 인원
  /// 카운터를 그대로 이어붙이는 데 쓴다.
  Map<String, dynamic> _slotDateFields(
    PartyDateSlot slot, {
    Map<String, dynamic>? existing,
  }) {
    if (_schedule.isRecurring) {
      return PartySchedule.buildRecurringFields(_schedule.recurring);
    }
    final single = slot.toSingleSchedule();
    final deadlineAt = _schedule.deadlineRule.resolve(
      single.start,
      occurrenceEnd: single.end,
    );
    final openAt = _schedule.openRule.resolve(
      single.start,
      occurrenceEnd: single.end,
    );
    return {
      ...PartySchedule.buildSingleFields(
        slot.toSingleSchedule(
          registrationDeadline: deadlineAt,
          registrationOpen: openAt,
        ),
        deadlineRule: _schedule.deadlineRule,
        openRule: _schedule.openRule,
      ),
      'date':
          '${formatPartyDate(slot.date)} ${formatPartyTime(slot.startTime)}',
      'partyDateTime': Timestamp.fromDate(
        DateTime(
          slot.date.year,
          slot.date.month,
          slot.date.day,
          slot.startTime!.hour,
          slot.startTime!.minute,
        ),
      ),
      'recruitDeadlineAt': deadlineAt != null
          ? Timestamp.fromDate(deadlineAt)
          : null,
      // 다음 저장이 "이 슬롯 = 이 문서"를 되찾는 열쇠 — 등록 화면과 같은 키다.
      'dateSlotId': slot.id,
      // 차수·패키지도 그 날짜 기준으로 다시 계산해 저장한다 — 새로 추가한
      // 날짜의 문서가 옛 날짜의 Timestamp를 물려받으면 모집 창구가 이미 지난
      // 상태로 만들어진다.
      ..._roundFieldsForSlot(slot, existing: existing),
    };
  }

  /// 이 슬롯 날짜에 맞춰 다시 계산한 차수·패키지 필드.
  ///
  /// 차수 구성 자체(시간·정원·참가비)는 이 화면에서 고치지 않으므로 문서에 있는
  /// 값을 그대로 쓰고, **날짜만** 갈아 끼운다.
  ///
  /// 다시 계산하면 차수별 신청 인원이 0으로 초기화되므로([PartyRound.toMap]),
  /// 기존 문서([existing])의 카운터를 그대로 옮겨 붙인다 — 그러지 않으면 수정
  /// 저장만으로 그 날짜의 신청 인원이 사라진다.
  /// 이 날짜 기준으로 다시 계산한 차수 배열(카운터는 0으로 초기화된 상태).
  ///
  /// 차수의 **정원·참가비·얼리버드**는 이 화면에서 고친 값([_roundDrafts])을
  /// 쓰고, 시간·모집 창구는 문서에 있던 규칙을 그대로 옮긴다. 라운드 파티가
  /// 아니거나 통합 정원 모드면 예전처럼 문서 값을 그대로 다시 쓴다.
  List<Map<String, dynamic>> _recomputedRounds(DateTime partyDate) {
    final sourceRounds = (widget.data['rounds'] as List?) ?? const [];
    if (sourceRounds.isEmpty) return const [];
    final perRound =
        (widget.data['roundCapacityMode'] as String?) == 'perRound';
    return [
      for (var i = 0; i < sourceRounds.length; i++)
        ?_roundForSave(i, sourceRounds[i])?.toMap(
          roundNumber:
              (sourceRounds[i] is Map
                  ? (sourceRounds[i]['roundNumber'] as num?)?.toInt()
                  : null) ??
              (i + 1),
          partyDate: partyDate,
          perRound: perRound,
        ),
    ];
  }

  /// 저장에 쓸 차수 하나 — 화면에서 고친 값이 있으면 그것, 없으면 문서 값.
  PartyRound? _roundForSave(int index, dynamic raw) {
    if (!_editsRoundFees || index >= _roundDrafts.length) {
      return PartyRound.fromMap(raw);
    }
    final edited = _roundDrafts[index].round;
    return edited.copyWith(earlyBird: _roundEarlyBirdOf(edited.earlyBird));
  }

  /// 차수 입력 검증 — 문제가 없으면 null. 규칙은 등록 화면과 같은 모델
  /// ([PartyRound.validate])이 갖고 있고, 여기서는 이 화면이 고칠 수 있는
  /// 값(정원·참가비·얼리버드)만 본다(시간·모집 창구는 고치지 않는다).
  String? _validateRoundDrafts() {
    if (_roundDrafts.isEmpty) return null;
    final separate =
        (_partyData['genderCapacityMode'] as String?) == 'separate';
    for (var i = 0; i < _roundDrafts.length; i++) {
      final r = _roundDrafts[i].round;
      final label = r.labelFor(i + 1);
      final capacityOk = separate
          ? (r.maleCapacity > 0 || r.femaleCapacity > 0)
          : r.maxCapacity > 0;
      if (!capacityOk) return '$label 모집 인원을 입력해주세요.';
      final minError = PartyCapacityStatus.validate(
        min: r.minCapacity,
        max: r.separateTotal,
      );
      if (minError != null) return '$label — $minError';
      if (r.maleFee % 1000 != 0 || r.femaleFee % 1000 != 0) {
        return '$label 참가비를 1,000원 단위로 입력해주세요. (무료면 0)';
      }
      final eb = _roundEarlyBirdOf(r.earlyBird);
      final ebError = eb.validate(
        isFree: r.maleFee == 0 && r.femaleFee == 0,
        isRecurring: true, // 차수는 날짜가 바뀌므로 늘 '시작 전' 규칙이다.
      );
      if (ebError != null) return '$label 얼리버드 — $ebError';
    }
    return null;
  }

  /// 문서 최상단에 남길 대표 얼리버드 — 등록 화면과 같은 규칙이다.
  /// 차수별로 켠 경우에도 "이 파티에 얼리버드가 있다"는 사실이 목록에서
  /// 사라지지 않도록 켜져 있는 첫 차수의 규칙을 대표로 남긴다.
  PartyEarlyBird get _representativeEarlyBird {
    switch (_roundEarlyBirdMode) {
      case 'none':
        return const PartyEarlyBird.off();
      case 'uniform':
        return _roundEarlyBirdOf(const PartyEarlyBird.off());
      default:
        for (final d in _roundDrafts) {
          if (d.round.earlyBird.enabled) return d.round.earlyBird;
        }
        return const PartyEarlyBird.off();
    }
  }

  /// 차수 하나에 실제로 저장할 얼리버드 — 등록 화면과 같은 규칙이다.
  /// '모든 차수 동일'은 **규칙을 복사**할 뿐 할인된 금액을 저장하지 않는다.
  PartyEarlyBird _roundEarlyBirdOf(PartyEarlyBird own) {
    switch (_roundEarlyBirdMode) {
      case 'none':
        return const PartyEarlyBird.off();
      case 'uniform':
        return PartyEarlyBird(
          enabled: true,
          percent: int.tryParse(_earlyBirdPercentController.text.trim()),
          endType: PartyEarlyBirdEndType.beforeStart,
          beforeStartRule: _earlyBirdRule,
        );
      default:
        return own;
    }
  }

  /// 정기 파티의 차수 필드 — 날짜 슬롯이 없으므로 **다음 회차 날짜**를 기준으로
  /// 다시 계산한다. 시:분과 서로의 간격만 의미가 있고(회차마다 날짜가 바뀌므로
  /// 판정 직전에 다시 계산된다 — functions/partyCapacity.js의 rebaseRounds),
  /// 차수별 신청 인원은 회차 칸(occurrenceStats)에 따로 쌓이므로 여기서 옮길
  /// 카운터는 문서에 있던 최상단 값 그대로다.
  Map<String, dynamic> _roundFieldsForRecurring() {
    if (!_editsRoundFees) return const {};
    final next = _schedule.recurring.nextOccurrence(DateTime.now());
    final base = next?.start ?? _firstRoundStoredStart() ?? DateTime.now();
    final recomputed = _recomputedRounds(
      DateTime(base.year, base.month, base.day),
    );
    if (recomputed.isEmpty) return const {};
    final rebuilt = PartySlotSyncService.carryOverRoundCounters(
      recomputed,
      widget.data['rounds'],
    );
    return {'rounds': rebuilt};
  }

  /// 문서에 저장돼 있던 1차 시작 시각 — 앞으로 열릴 회차가 없을 때의 기준.
  DateTime? _firstRoundStoredStart() {
    for (final r in PartyRoundOffers.roundsOf(widget.data)) {
      final ts = r['time'];
      if (ts is Timestamp) return ts.toDate();
    }
    return null;
  }

  Map<String, dynamic> _roundFieldsForSlot(
    PartyDateSlot slot, {
    Map<String, dynamic>? existing,
  }) {
    final recomputed = _recomputedRounds(slot.date);
    if (recomputed.isEmpty) return const {};
    // 그 문서가 이미 갖고 있던 차수별 신청 인원을 되돌려 놓는다(새 문서는
    // existing이 null이라 0으로 남는다 — 그게 맞다).
    final rebuilt = PartySlotSyncService.carryOverRoundCounters(
      recomputed,
      existing?['rounds'],
    );

    DateTime? startOf(int roundNumber) {
      for (final r in rebuilt) {
        if ((r['roundNumber'] as int?) == roundNumber) {
          final ts = r['time'];
          if (ts is Timestamp) return ts.toDate();
        }
      }
      return null;
    }

    final available = rebuilt
        .map((r) => r['roundNumber'] as int?)
        .whereType<int>()
        .toSet();
    return {
      'rounds': rebuilt,
      if (_supportsRoundPackages)
        'roundPackages': [
          for (final p in _roundPackages)
            if (p.normalizedRoundNumbers.every(available.contains))
              p.toMap(firstRoundStart: startOf(p.normalizedRoundNumbers.first)),
        ],
    };
  }

  /// 수정 저장 — 날짜 슬롯을 문서에 동기화한다(등록 화면과 같은 공용 서비스).
  ///
  /// 기존 날짜 문서는 update되고(신청자·정원 카운터는 건드리지 않는다), 새로
  /// 추가한 날짜는 문서가 새로 만들어지고, 빠진 날짜는 기존 삭제 흐름으로
  /// 삭제된다. 신청자가 남아 있는 날짜는 여기서 먼저 막는다.
  Future<PartySlotSyncOutcome> _commitScheduleSlots(
    Map<String, dynamic> fields,
  ) async {
    // 정기 파티는 **반복 규칙 하나 = 문서 하나**다(날짜 슬롯이 없다) —
    // 슬롯 동기화 대상이 아니라서 예전처럼 이 문서만 갱신한다.
    if (_schedule.isRecurring) {
      await FirebaseFirestore.instance
          .collection('parties')
          .doc(widget.docId)
          .update({
            ...fields,
            // 정기 파티는 날짜 슬롯이 없어 차수도 여기서 함께 저장한다 —
            // 예전에는 이 경로에 rounds가 아예 없어서 차수 참가비를 고쳐도
            // 저장되지 않았다.
            ..._roundFieldsForRecurring(),
            ...PartySchedule.buildRecurringFields(_schedule.recurring),
          });
      return const PartySlotSyncOutcome(createdCount: 0, updatedCount: 1);
    }

    final seriesId =
        (widget.data['seriesId'] as String?)?.trim().isNotEmpty == true
        ? widget.data['seriesId'] as String
        // 레거시 문서는 자기 자신이 시리즈의 시작점이 된다(등록 화면과 동일).
        : widget.docId;

    final slots = _schedule.slots.where((s) => s.startTime != null).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final plan = await PartySlotSyncService.plan(
      seriesId: seriesId,
      primaryDocId: widget.docId,
      slots: slots,
    );
    if (plan.blockedOrphans.isNotEmpty) {
      final names = plan.blockedOrphans.map((o) => o.label).join(', ');
      throw StateError(
        '$names 일정에는 신청자가 있어 삭제할 수 없어요. '
        '그 날짜를 다시 추가하거나, 파티 상태를 \'취소\'로 바꿔 신청을 정리한 뒤 '
        '삭제해주세요.',
      );
    }

    return plan.commit(
      fieldsFor:
          (
            slot, {
            required isUpdate,
            required index,
            required docId,
            required existing,
          }) => {
            // ── 공통 정보 vs 날짜별 운영 상태 ───────────────────────────────
            // 제목·소개·카테고리·대표 이미지처럼 게시글 자체의 정보는 모든 날짜에
            // 동기화한다. 반면 모집 상태·신청 인원·취소 상태처럼 **그 날짜만의
            // 상태**는 다른 날짜 문서에 덮어쓰면 안 된다 — 8/10을 마감했다고 8/13이
            // 함께 마감되는 일이 생긴다.
            //
            // 그래서 지금 편집 중인 문서에는 입력한 값을 그대로 쓰고(사용자가 이
            // 화면에서 바꾼 모집 상태 등이 반영돼야 한다), **다른 날짜 문서에는
            // 공통 정보만** 쓴다(PartySlotSyncService.perDateStateKeys).
            ...(docId == widget.docId
                ? fields
                : PartySlotSyncService.sharedOnly(fields)),
            // 'people'은 "현재 인원/최대 인원" 표시 문자열이라 두 성격이 섞여 있다 —
            // 최대 인원은 공통 정보이고 현재 인원은 그 날짜의 상태다. 다른 날짜
            // 문서에는 **그 문서의 현재 인원**에 새 최대 인원을 붙여 다시 계산한다
            // (위에서 통째로 걷어냈으므로 여기서 채운다).
            if (isUpdate && docId != widget.docId && existing != null)
              'people':
                  '${(existing['currentParticipants'] as num?)?.toInt() ?? 0}'
                  '/${(fields['maxParticipants'] as num?)?.toInt() ?? 0}명',
            ..._slotDateFields(slot, existing: existing),
            // `seriesId`가 없던 예전 문서에도 채워 넣는다 — 이 문서가 시리즈의
            // 시작점이 되어, 지금 추가한 날짜들과 같은 게시글로 묶인다.
            'seriesId': seriesId,
            // 새로 추가한 날짜는 **새 문서**다 — 호스트/신청 상태를 초기화해야
            // 한다. 기존 날짜 문서는 신청자·카운터를 그대로 둔다(수정은 신청을
            // 건드리지 않는다는 이 화면의 기존 정책).
            if (!isUpdate) ...{
              'hostId': widget.data['hostId'] ?? UserSession.userId,
              'hostUid':
                  widget.data['hostUid'] ??
                  FirebaseAuth.instance.currentUser?.uid ??
                  UserSession.userId,
              'applicants': <String>[],
              'approvedApplicants': <String>[],
              'rejectedApplicants': <String>[],
              'approved': true,
              'currentParticipants': 0,
              'currentMaleCount': 0,
              'currentFemaleCount': 0,
              'recruitStatus': '모집중',
              // 새로 추가한 날짜 문서도 **원본 게시글과 같은 오픈 상태**여야 한다 —
              // 오픈예정 파티에 날짜를 더했는데 그 날짜만 신청을 받으면 안 된다.
              //
              // hostBusinessVerified는 원본의 값이 아니라 **지금의 인증 상태**를
              // 쓴다. firestore.rules의 parties create 규칙이 이 값을 실제 인증
              // 상태와 정확히 대조하기 때문에, 오래된 값을 그대로 복사하면 날짜
              // 추가가 통째로 거부된다.
              'openState': PartyOpenState.of(widget.data),
              'hostBusinessVerified': _businessVerified,
              'dateTbd': false,
              'isDeleted': false,
              'status': 'active',
              'isActive': true,
              'createdAt': Timestamp.fromDate(DateTime.now()),
            },
          },
    );
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

  Future<void> _openCapacitySheet() async {
    final result = await showGenderCapacitySheet(
      context,
      initial: GenderCapacityDraft(
        genderLimit: _genderLimit,
        genderCapacityMode: 'unlimited',
        genderMode: '',
        capacity: int.tryParse(_capacityController.text.trim()),
        minCapacity: _minCapacity,
        minCapacityPolicy: _minCapacityPolicy,
        revealParticipantGenderRatio: _revealParticipantGenderRatio,
      ),
      allowGenderLimitChange: false,
      isRecurring: _isRecurringParty,
      // 차수별 참가비/정원을 이 화면에서 고치는 파티는 최대 인원 칸이 차수
      // 쪽에 있다 — "최소 ≤ 최대"를 검사하려면 총 정원을 넘겨줘야 한다.
      totalCapacity: _editsRoundFees && _roundDrafts.isNotEmpty
          ? _roundDrafts.fold<int>(
              0,
              (total, d) => total + d.round.separateTotal,
            )
          : null,
    );
    if (result == null) return;
    setState(() {
      _capacityController.text = result.capacity?.toString() ?? '';
      _minCapacity = result.minCapacity ?? 0;
      _minCapacityPolicy = result.minCapacityPolicy;
      _revealParticipantGenderRatio = result.revealParticipantGenderRatio;
      _showCapacityError = false;
    });
  }

  Future<void> _openFeeSheet() async {
    final result = await showFeeSheet(
      context,
      genderLimit: _genderLimit,
      isRecurring: _isRecurringParty,
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
            if (mounted) setState(() {});
          },
        ),
      ),
    );
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
  /// 맞는 편집 화면으로 이동한다. 방식을 바꿔도 서로의 데이터는 지우지
  /// 않는다 — 다시 그 방식을 고르면 이어서 편집할 수 있다.
  Future<void> _openDescriptionEditor() async {
    final chosen = await showPartyDetailDescriptionModeSheet(
      context,
      current: _descriptionMode,
    );
    if (chosen == null || !mounted) return;

    if (chosen != _descriptionMode) {
      final hasContentInCurrentMode =
          _descriptionMode == PartyDescriptionMode.auto
          ? _descController.text.trim().isNotEmpty
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
      webFramedRoute(
        (_) => PartyIntroScreen(
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

  /// 참가비가 0원인지 — 무료 파티에는 결제 방식을 노출하지 않는다.
  bool get _isFree {
    final male = int.tryParse(_maleFeeController.text.trim()) ?? 0;
    final female = int.tryParse(_femaleFeeController.text.trim()) ?? 0;
    return male <= 0 && female <= 0;
  }

  /// 계산 예시 기준 금액 — 남녀 참가비가 다르면 더 큰 쪽.
  int? _sampleFeeForPreview() {
    final male = int.tryParse(_maleFeeController.text.trim()) ?? 0;
    final female = int.tryParse(_femaleFeeController.text.trim()) ?? 0;
    final fee = male > female ? male : female;
    return fee > 0 ? fee : null;
  }

  Future<void> _openPaymentPolicySheet() async {
    final result = await showPaymentPolicySheet(
      context,
      initial: _paymentPolicy ?? PaymentPolicy.initial,
      sampleTotal: _sampleFeeForPreview(),
    );
    if (result == null) return;
    setState(() => _paymentPolicy = result);
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

  String? _refundSummary() => RefundPolicyRule.summaryLabel(_refundTiers);

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

  // ── 장소 설정 ─────────────────────────────────────────────────────
  // "직접 입력한 장소 유지" / "내 플레이스에서 선택" 두 갈래. 연결 상태에
  // 따라 시트 안의 선택지가 달라진다.

  String _locationSummary() {
    final link = _link;
    if (link != null) {
      final snapshot = _partyData[PlacePartyLink.snapshotField];
      final name = snapshot is Map
          ? (snapshot['name'] as String? ?? '')
          : (_linkedPlaceData?['name'] as String? ?? '');
      final placeName = name.isNotEmpty
          ? name
          : (_partyData['placeName'] as String? ?? link.target.noun);
      return '${link.target.noun} · $placeName';
    }
    final location = (_partyData['location'] as String?)?.trim() ?? '';
    if (location.isNotEmpty) return '직접 입력 · $location';
    return '직접 입력한 장소';
  }

  void _linkMsg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  /// 연결된 공간 문서를 읽어 캐시한다(없으면 null).
  /// 컬렉션은 연결 종류가 정한다 — 'events'로 굳히면 장소대여에 연결된 파티가
  /// 늘 "찾을 수 없어요"가 된다.
  Future<Map<String, dynamic>?> _loadLinkedPlace() async {
    final link = _link;
    if (link == null) return null;
    if (_linkedPlaceData != null) return _linkedPlaceData;
    final snap = await FirebaseFirestore.instance
        .collection(link.target.collection)
        .doc(link.id)
        .get();
    _linkedPlaceData = snap.data();
    return _linkedPlaceData;
  }

  /// 콤보로 묶인 플레이스 문서를 읽어 캐시한다 — `events`/`places` 어느
  /// 컬렉션인지는 파티 문서의 연결 필드로 정해진다.
  Future<Map<String, dynamic>?> _loadBundledPlace() async {
    final ref = _bundledPlaceRef;
    if (ref == null) return null;
    if (_linkedPlaceData != null) return _linkedPlaceData;
    final snap = await FirebaseFirestore.instance
        .collection(ref.collection)
        .doc(ref.id)
        .get();
    _linkedPlaceData = snap.data();
    return _linkedPlaceData;
  }

  /// 콤보로 묶인 플레이스의 상세 화면을 연다(연결을 바꾸지 않는 읽기 전용 이동).
  Future<void> _openBundledPlace() async {
    final ref = _bundledPlaceRef;
    if (ref == null) {
      _linkMsg('연결된 플레이스 정보를 찾을 수 없어요.');
      return;
    }
    final place = await _loadBundledPlace();
    if (!mounted) return;
    if (place == null) {
      _linkMsg('연결된 플레이스를 찾을 수 없어요.');
      return;
    }
    await Navigator.push(
      context,
      webFramedRoute(
        (_) => ref.collection == 'events'
            ? EventDetailScreen(eventId: ref.id, eventData: place)
            : PlaceDetailScreen(placeId: ref.id, data: place),
      ),
    );
  }

  /// 묶음 목록에서 "수정"을 눌렀을 때 — 현재 파티면 그대로 머무르고, 다른
  /// 파티면 미저장 변경사항을 확인한 뒤 그 파티의 수정 화면을 연다.
  Future<void> _openBundledPartyEdit(BundledParty party) async {
    if (party.isCurrent) {
      _linkMsg('지금 수정 중인 파티예요.');
      return;
    }
    if (_hasUnsavedChanges) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('저장하지 않은 변경사항이 있습니다.'),
          content: const Text('이동하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('이동'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    await Navigator.push(
      context,
      webFramedRoute((_) => PartyEditScreen(docId: party.id, data: party.data)),
    );
    if (!mounted) return;
    // 형제 파티가 수정됐을 수 있으니 목록을 다시 읽는다.
    await _loadBundle();
  }

  Future<void> _openLocationSheet() async {
    if (_isBundledCombo) {
      _linkMsg('이 파티는 플레이스와 함께 등록되어 장소 연결은 변경할 수 없습니다.');
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final link = _link;
        final linked = link != null;
        // 문구는 연결 종류를 따라간다 — 장소대여에 붙은 파티에 "플레이스"라고
        // 적으면 사용자가 다른 것을 보고 있다고 오해한다.
        final noun = link?.target.noun ?? PartyLinkTarget.place.noun;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '장소 설정',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              if (!linked) ...[
                ListTile(
                  leading: const Icon(
                    Icons.edit_location_alt_outlined,
                    color: Colors.black54,
                  ),
                  title: const Text('직접 입력한 장소 유지'),
                  subtitle: Text(
                    (_partyData['location'] as String?)?.trim().isNotEmpty ==
                            true
                        ? _partyData['location'] as String
                        : '등록할 때 입력한 주소를 그대로 써요',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(ctx, 'keep'),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.storefront_outlined,
                    color: Color(0xFFFF6FA0),
                  ),
                  title: const Text('내 공간에서 선택'),
                  subtitle: const Text('등록한 플레이스·장소대여와 연결하고 장소 정보를 가져와요'),
                  onTap: () => Navigator.pop(ctx, 'pick'),
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.open_in_new, color: Colors.black54),
                  title: Text('연결된 $noun 보기'),
                  onTap: () => Navigator.pop(ctx, 'view'),
                ),
                ListTile(
                  leading: const Icon(Icons.swap_horiz, color: Colors.black54),
                  title: const Text('다른 공간으로 변경'),
                  onTap: () => Navigator.pop(ctx, 'change'),
                ),
                if (_canRefreshPlaceSnapshot)
                  ListTile(
                    leading: const Icon(
                      Icons.refresh,
                      color: Color(0xFFFF6FA0),
                    ),
                    title: Text('$noun 변경사항 반영'),
                    subtitle: Text('$noun에서 바뀐 주소·좌표를 이 파티에 다시 가져와요'),
                    onTap: () => Navigator.pop(ctx, 'refresh'),
                  ),
                ListTile(
                  leading: const Icon(Icons.link_off, color: Color(0xFFB00020)),
                  title: const Text('연결 해제'),
                  subtitle: const Text('파티는 삭제되지 않아요'),
                  onTap: () => Navigator.pop(ctx, 'unlink'),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'keep':
        break;
      case 'pick':
        await _linkToMyPlace();
      case 'change':
        await _linkToMyPlace();
      case 'view':
        await _openLinkedPlace();
      case 'refresh':
        await _refreshPlaceSnapshot();
      case 'unlink':
        await _unlinkPlace();
    }
  }

  Future<void> _openLinkedPlace() async {
    final link = _link;
    if (link == null) return;
    final place = await _loadLinkedPlace();
    if (!mounted) return;
    if (place == null) {
      _linkMsg('연결된 ${link.target.noun}을 찾을 수 없어요.');
      return;
    }
    await Navigator.push(
      context,
      webFramedRoute(
        (_) => switch (link.target) {
          PartyLinkTarget.place => EventDetailScreen(
            eventId: link.id,
            eventData: place,
          ),
          PartyLinkTarget.rental => PlaceDetailScreen(
            placeId: link.id,
            data: place,
          ),
        },
      ),
    );
  }

  /// 내 공간 목록에서 하나를 골라 연결(또는 재연결)한다.
  ///
  /// 목록은 등록 화면과 **같은 시트**([pickMyPlace])이고 플레이스·장소대여를
  /// 모두 보여준다 — 등록에서 장소대여에 붙일 수 있게 된 이상, 수정에서만
  /// events로 좁혀두면 그렇게 만든 파티를 여기서 손댈 수 없다.
  Future<void> _linkToMyPlace() async {
    final current = _link;
    // 이미 다른 공간과 연결돼 있으면 확인 없이 덮어쓰지 않는다.
    if (current != null) {
      final ok = await _confirmRelink();
      if (ok != true || !mounted) return;
    }
    final picked = await pickMyPlace(
      context,
      excludeEventId: current?.id,
      targets: PartyLinkTarget.values.toSet(),
    );
    if (picked == null || !mounted) return;

    if (PlacePartyLink.hasApplicants(_partyData)) {
      final ok = await _confirmApplicantsWarning();
      if (ok != true || !mounted) return;
    }

    setState(() => _isLinkBusy = true);
    try {
      final hostId = UserSession.userId;
      if (current != null) {
        // 종류가 바뀌면(플레이스 → 장소대여) 이전 연결 필드는 서비스가 같은
        // 배치에서 지운다 — 두 필드가 동시에 남는 상태가 생기지 않는다.
        await PlacePartyLink.relinkParty(
          partyId: widget.docId,
          fromTarget: current.target,
          fromTargetId: current.id,
          toTarget: picked.target,
          toTargetId: picked.targetId,
          toPlace: picked.data,
          hostId: hostId,
        );
      } else {
        await PlacePartyLink.linkParties(
          targetId: picked.targetId,
          place: picked.data,
          partyIds: [widget.docId],
          hostId: hostId,
          target: picked.target,
        );
      }
      if (!mounted) return;
      // 화면이 들고 있는 사본에서도 이전 종류의 필드를 지운다 — 서버만
      // 정리하고 여기 남겨두면 다시 저장할 때 지운 필드가 되살아난다.
      final stale = _otherLinkFields(picked.target);
      setState(() {
        _linkedPlaceData = picked.data;
        _partyData
          ..addAll(PlacePartyLink.placeLocationFields(picked.data))
          ..removeWhere((key, _) => stale.contains(key))
          ..[picked.target.linkField] = picked.targetId
          ..[PlacePartyLink.usesRegisteredPlaceField] = true
          ..[PlacePartyLink.snapshotField] = PlacePartyLink.buildPlaceSnapshot(
            targetId: picked.targetId,
            place: picked.data,
            target: picked.target,
          );
      });
      _linkMsg('${picked.target.noun}와 연결했어요. 제목·일정·참가비는 그대로예요.');
    } on StateError catch (e) {
      _linkMsg(e.message);
    } catch (_) {
      _linkMsg('연결에 실패했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isLinkBusy = false);
    }
  }

  /// [keep] 말고 다른 종류의 연결 필드 이름들 — 화면 사본을 서버와 같은
  /// 규칙으로 정리하는 데 쓴다([PlacePartyLink.clearOtherLinkFields]와 짝).
  static Set<String> _otherLinkFields(PartyLinkTarget? keep) => {
    for (final t in PartyLinkTarget.values)
      if (t != keep) t.linkField,
  };

  Future<void> _unlinkPlace() async {
    final link = _link;
    if (link == null) return;
    final choice = await showUnlinkDialog(context, _partyData);
    if (choice == null || !mounted) return;

    final allLinkFields = _otherLinkFields(null);
    setState(() => _isLinkBusy = true);
    try {
      final previous = _partyData[PlacePartyLink.previousSnapshotField];
      await PlacePartyLink.unlinkParty(
        targetId: link.id,
        partyId: widget.docId,
        restorePreviousLocation: choice == UnlinkLocationChoice.restorePrevious,
        target: link.target,
      );
      if (!mounted) return;
      setState(() {
        _linkedPlaceData = null;
        if (choice == UnlinkLocationChoice.restorePrevious && previous is Map) {
          for (final key in kPartyLocationFields) {
            if (previous.containsKey(key)) _partyData[key] = previous[key];
          }
        }
        _partyData
          // 종류와 무관하게 두 연결 필드를 모두 지운다 — 서버가 하는 것과
          // 같은 규칙이라야 화면과 문서가 어긋나지 않는다.
          ..removeWhere((key, _) => allLinkFields.contains(key))
          ..remove(PlacePartyLink.snapshotField)
          ..remove(PlacePartyLink.previousSnapshotField)
          ..[PlacePartyLink.usesRegisteredPlaceField] = false;
      });
      _linkMsg('연결을 해제했어요. 파티는 그대로 남아 있어요.');
    } catch (_) {
      _linkMsg('연결 해제에 실패했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isLinkBusy = false);
    }
  }

  Future<void> _refreshPlaceSnapshot() async {
    final link = _link;
    if (link == null) return;
    setState(() => _isLinkBusy = true);
    try {
      // 캐시가 아니라 지금 시점의 공간 문서를 다시 읽어 반영한다.
      _linkedPlaceData = null;
      final place = await _loadLinkedPlace();
      if (place == null) {
        _linkMsg('연결된 ${link.target.noun}을 찾을 수 없어요.');
        return;
      }
      await PlacePartyLink.refreshPlaceSnapshot(
        targetId: link.id,
        partyId: widget.docId,
        place: place,
        target: link.target,
      );
      if (!mounted) return;
      setState(() {
        _partyData
          ..addAll(PlacePartyLink.placeLocationFields(place))
          ..[PlacePartyLink.snapshotField] = PlacePartyLink.buildPlaceSnapshot(
            targetId: link.id,
            place: place,
            target: link.target,
          );
      });
      _linkMsg('${link.target.noun}의 최신 장소 정보를 반영했어요.');
    } catch (_) {
      _linkMsg('반영에 실패했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isLinkBusy = false);
    }
  }

  Future<bool?> _confirmRelink() => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('이미 연결된 파티예요', style: TextStyle(fontSize: 17)),
      content: const Text(
        '이 파티는 이미 다른 공간과 연결돼 있어요.\n'
        '새로 고른 공간으로 바꾸면 장소 정보도 그 공간 값으로 바뀝니다.',
        style: TextStyle(fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF6FA0)),
          child: const Text('계속하기'),
        ),
      ],
    ),
  );

  Future<bool?> _confirmApplicantsWarning() => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('신청자가 있는 파티예요', style: TextStyle(fontSize: 17)),
      content: const Text(
        '이미 신청한 사람이 있어요. 장소를 연결하면 파티의 주소·좌표가 '
        '플레이스 값으로 바뀌므로 신청자에게 안내가 필요할 수 있어요.',
        style: TextStyle(fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF6FA0)),
          child: const Text('그래도 연결하기'),
        ),
      ],
    ),
  );

  /// 플레이스와 함께 등록된 파티의 "장소 설정" 카드 — 연결 필드는 잠그고
  /// 플레이스 이름과 상세로 나가는 버튼만 둔다.
  Widget _bundledPlaceCard() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '장소 설정',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.storefront_outlined,
                size: 18,
                color: Color(0xFFFF6FA0),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _bundledPlaceName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.lock_outline, size: 16, color: Colors.black26),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '이 파티는 플레이스와 함께 등록되어 장소 연결은 변경할 수 없습니다.',
            style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.4),
          ),
          if (_bundledPlaceRef != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLinkBusy ? null : _openBundledPlace,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('플레이스 보기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black87,
                  side: const BorderSide(color: Colors.black26),
                  minimumSize: const Size(0, 40),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
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
        title: Text(
          _screenTitle,
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
                          if (v != null) {
                            setState(() => _recruitStatus = v);
                          }
                        },
                        decoration: _inputDecoration('모집 상태'),
                      ),
                      const SizedBox(height: 12),
                      // 성별별 모집 — 위 '모집 상태'가 전체 기준이고, 여기는
                      // 그 위에 얹히는 성별 예외다(전체가 모집중일 때만 뜻이
                      // 있어 나머지 상태에서는 잠긴다).
                      GenderRecruitStatusField(
                        maleOpen: _maleRecruitOpen,
                        femaleOpen: _femaleRecruitOpen,
                        genderLimit: _genderLimit,
                        enabled: _recruitStatus == '모집중',
                        disabledNote: '전체 $_recruitStatus 상태라 성별 설정은 적용되지 않아요.',
                        onChanged: (v) => setState(() {
                          _maleRecruitOpen = v.maleOpen;
                          _femaleRecruitOpen = v.femaleOpen;
                        }),
                      ),
                    ],
                  ),
                ),
                // 일정 — 날짜·시간 / 매주 반복 / 차수 / 모집 시작·마감.
                // 등록 화면들과 같은 공용 위젯이고, 수정·재등록 모두 같은
                // 자리에 같은 모양으로 들어간다.
                PartyScheduleSection(
                  value: _schedule,
                  onChanged: (v) => setState(() {
                    _schedule = v;
                    _showDateError = false;
                  }),
                  showError: _showDateError,
                ),
                // 장소 설정 — 직접 입력한 주소를 유지하거나, 내가 등록한
                // 플레이스에 연결해 그쪽 장소 정보를 가져다 쓴다. 연결/해제는
                // 두 문서를 batch로 함께 갱신해야 해서 여기서 즉시 반영된다.
                //
                // 플레이스와 **함께 등록된** 콤보 파티는 placeId/bundleId/
                // seriesId 같은 연결 필드를 이 화면에서 바꾸면 번들이 반쪽만
                // 남으므로, 아예 잠긴 전용 카드로 보여주고 플레이스 상세로
                // 나가는 길만 열어둔다.
                if (_isBundledCombo)
                  _bundledPlaceCard()
                else
                  SectionSummaryRow(
                    title: '장소 설정',
                    summary: _locationSummary(),
                    onTap: () {
                      if (!_isLinkBusy) _openLocationSheet();
                    },
                  ),
                // 같은 등록에서 함께 만들어진 파티 목록 — 여기서 형제 파티의
                // 수정 화면으로 바로 갈 수 있다.
                if (_isBundledCombo &&
                    (_bundleLoading || _bundle.parties.isNotEmpty))
                  BundledPartiesCard(
                    bundle: _bundle,
                    loading: _bundleLoading,
                    onEdit: _openBundledPartyEdit,
                  ),
                SectionSummaryRow(
                  title: '성별 및 모집 인원',
                  summary: _capacitySummary(),
                  hasError: _showCapacityError,
                  errorText: _capacityErrorText(),
                  onTap: _openCapacitySheet,
                ),
                SectionSummaryRow(
                  title: '신청 방식',
                  summary: _approvalSummary(),
                  onTap: _openApplicationFormSheet,
                ),
                // 라운드 파티는 차수마다 참가비가 따로 있고 그게 실제 결제
                // 금액의 정본이다 — 문서 최상단 하나를 고치는 이 줄을 함께
                // 두면 "여기서 바꿨는데 금액이 그대로"인 상태가 된다.
                if (!_editsRoundFees)
                  SectionSummaryRow(
                    title: '참가비 설정',
                    summary: _feeSummary(),
                    hasError: _showFeeError,
                    errorText: _showFeeError ? _feeErrorText() : null,
                    onTap: _openFeeSheet,
                  ),
                SectionSummaryRow(
                  title: RefundPolicyRule.sectionTitle,
                  summary: _refundSummary(),
                  isRequired: true,
                  hasError: _showRefundError,
                  errorText: _showRefundError
                      ? RefundPolicyRule.requiredMessage
                      : null,
                  onTap: _openRefundPolicy,
                ),
                // 무료 파티에는 결제 방식이라는 개념이 없다.
                if (!_isFree)
                  SectionSummaryRow(
                    title: '결제 방식',
                    summary: _paymentSummary(),
                    onTap: _openPaymentPolicySheet,
                  ),
                SectionSummaryRow(
                  title: '파티 유형 · 분위기',
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
                  title: '사진 / 동영상 수정',
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
                // 상세 이미지(선택) — 등록 화면과 같은 위젯·같은 규칙.
                PartyDetailImageSection(
                  draft: _detailImage,
                  onChanged: (next) => setState(() => _detailImage = next),
                ),
                // 차수별 정원·참가비·얼리버드 — 라운드 파티의 금액 정본이다.
                if (_editsRoundFees) ...[
                  _roundFeeSection(),
                  const SizedBox(height: 16),
                ],
                // 차수 패키지 — 차수의 시간·모집 창구는 이 화면에서 고치지
                // 않으므로, 패키지의 이름·포함 차수·금액만 손본다.
                if (_supportsRoundPackages) ...[
                  RoundPackageEditor(
                    rounds: _packageRoundInfos,
                    packages: _roundPackages,
                    separateGenderFee: _packageSeparateGenderFee,
                    errors: _packageErrors,
                    onChanged: (next) => setState(() {
                      _roundPackages = next;
                      _packageErrors = const {};
                    }),
                  ),
                  const SizedBox(height: 16),
                ],
                GuestInquirySection(
                  enabled: _inquiryEnabled,
                  onChanged: (v) => setState(() => _inquiryEnabled = v),
                  guideController: _inquiryGuideCtrl,
                ),
                // 파티 참가자에게 현장에서 주는 혜택 — 매장(플레이스·장소대여)
                // 안내와 문구가 다르다.
                PartychuPerkSection(
                  controller: _partychuPerkController,
                  audience: PartychuPerkAudience.party,
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
                        : Text(_submitLabel),
                  ),
                ),
                // 오픈예정 파티에만 붙는 "모집 오픈" 영역 — 저장과 오픈은
                // 별개의 행동이다. 날짜를 채워 저장했다고 자동으로 열리지
                // 않고, 호스트가 여기서 직접 눌러야 모집이 시작된다.
                if (PartyOpenState.isPreopen(_partyData)) _buildOpenSection(),
                // 삭제는 앱 전체가 같은 흐름을 쓴다(공용 DeleteContentButton)
                // — 마이페이지 목록과 문구·확인창·권한 검사·연결 데이터
                // 정리가 완전히 동일하다.
                DeleteContentButton(
                  type: DeletableContent.party,
                  id: widget.docId,
                  seriesId: widget.data['seriesId'] as String? ?? widget.docId,
                  contentName: widget.data['title'] as String?,
                  // 신청자가 남아 삭제가 막히면 그 신청자 목록으로 바로 보낸다.
                  // 목적지가 제목·문서까지 요구해서 기본 경로로는 못 만든다.
                  blockerScreen: (_) => PartyApplicantsScreen(
                    partyId: widget.docId,
                    partyTitle: widget.data['title'] as String? ?? '파티',
                    partyData: widget.data,
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
          // 플레이스 연결/해제는 저장과 별개로 즉시 커밋되므로 그동안에도
          // 화면을 잠근다(연타로 batch가 두 번 나가지 않게).
          if (_isLinkBusy)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
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
