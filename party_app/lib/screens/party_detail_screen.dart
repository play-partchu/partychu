import 'dart:async';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/widgets/guest_inquiry_button.dart';
import 'package:party_app/widgets/refund_account_prompt.dart';
import 'package:party_app/models/payment_policy.dart';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:party_app/utils/auto_description_classifier.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/utils/party_detail_view_mode.dart';
import 'package:party_app/utils/party_eligibility.dart';
import 'package:party_app/models/party_age_restriction.dart';
import 'package:party_app/models/participant_gender_visibility.dart';
import 'package:party_app/models/party_capacity_status.dart';
import 'package:party_app/models/party_gender_recruit.dart';
import 'package:party_app/models/party_occurrence_recruit.dart';
import 'package:party_app/models/party_open_state.dart';
import 'package:party_app/services/party_create_eligibility.dart';
import 'package:party_app/services/party_open_alert_service.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/models/reservation_modes.dart';
import 'package:party_app/models/party_constants.dart';
import 'package:party_app/models/party_application_form.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/screens/party_application_answer_screen.dart';
import 'package:party_app/models/party_round.dart';
import 'package:party_app/models/party_round_offer.dart';
import 'package:party_app/models/party_series.dart';
import 'package:party_app/widgets/party_round_offers_view.dart';
import 'package:party_app/models/apply_occurrence_state.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/models/payment_method.dart';
import 'package:party_app/models/payment_order_summary.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/screens/payment_method_screen.dart';
import 'package:party_app/models/party_timeline.dart';
import 'package:party_app/models/party_early_bird_schedule.dart'
    show earlyBirdInfoRowText;
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/widgets/early_bird_price_line.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/models/report_reason.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/widgets/user_safety_actions.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/services/map_directions_service.dart';
import 'package:party_app/widgets/party_capacity_meter.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/widgets/media_gallery.dart';
import 'package:party_app/widgets/nickname_edit_dialog.dart';
import 'package:party_app/widgets/partychu_perk.dart';
import 'package:party_app/widgets/party_auto_keyword_badges.dart';
import 'package:party_app/widgets/occurrence_picker.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/party_type_vibe_icon.dart';
import 'package:party_app/widgets/party_detail_block_preview.dart';
import 'package:party_app/widgets/party_detail_block_text_view.dart';
import 'package:party_app/widgets/party_detail_theme.dart';
import 'package:party_app/widgets/party_identity_notice.dart';
import 'package:party_app/widgets/partychu_icon_button.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/place_access_info.dart';
import 'package:party_app/widgets/place_address_row.dart';
import 'package:party_app/widgets/refund_policy_editor.dart';
import 'package:party_app/login.dart';
import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/party_detail_image.dart';
import 'package:party_app/widgets/party_detail_image_view.dart';
import 'package:party_app/models/party_auto_description_style.dart';
import 'package:party_app/models/party_detail_decoration_intensity.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/screens/full_screen_image_viewer.dart';
import 'package:party_app/screens/package_booking_screen.dart';
import 'package:party_app/screens/party_applicants_screen.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/screens/place_detail_screen.dart';
import 'package:party_app/screens/event_detail_screen.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/services/analytics_service.dart';
import 'package:party_app/services/push_permission_gate.dart';
import 'package:party_app/widgets/party_review_section.dart';
import 'package:party_app/widgets/refund_account_sheet.dart';
import 'package:party_app/widgets/share_bottom_sheet.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 신청 플로우의 한 단계가 어떻게 끝났는지.
///
/// 신청은 날짜 → 회차 → 차수 → 사전질문 → 결제수단 순서로 묻는데, 예전에는
/// 각 단계가 "골랐다 / 안 골랐다" 두 가지만 돌려줬다. 그래서 날짜를 잘못 고른
/// 사람이 차수 화면에서 할 수 있는 일은 신청을 끝까지 진행하거나 화면을 닫는
/// 것뿐이었다. 세 번째 결말([back])을 만들어 호출부가 **한 칸 앞 단계부터
/// 다시 묻게** 한다.
enum _ApplyStep {
  /// 다음 단계로 간다(마지막 단계면 신청이 끝난 것이다).
  proceed,

  /// 한 칸 앞 단계로 돌아간다 — 그 단계에서 고른 값은 호출부가 지운다.
  back,

  /// 신청을 그만둔다.
  quit,
}

class PartyDetailScreen extends StatefulWidget {
  final String docId;

  const PartyDetailScreen({super.key, required this.docId});

  @override
  State<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

/// 연결된 `places` 문서와 그 룸 — 유형 판정([placeSupportsStay])에 둘 다
/// 필요해서 한 번에 들고 다닌다.
class _LinkedPlaceInfo {
  final Map<String, dynamic> place;
  final List<Map<String, dynamic>> rooms;

  const _LinkedPlaceInfo({required this.place, required this.rooms});
}

class _PartyDetailScreenState extends State<PartyDetailScreen> {
  // ── 여러 날짜(같은 seriesId) 게시글 ──────────────────────────────────
  //
  // 저장 구조는 "날짜 슬롯 1개 = parties 문서 1개"다. 목록은 시리즈를 카드 한
  // 장으로 접어 보여주므로(PartySeries), 상세에서 다른 날짜를 고를 수 있어야
  // 한다.
  //
  // 고르면 **그 날짜의 문서로 화면 전체를 바꾼다**([_activeDocId]) — 정원·모집
  // 마감·차수·패키지·신청 여부가 모두 문서 단위라, 대상 문서만 바꾸면 신청
  // 흐름과 서버 로직은 예전 그대로 동작한다(새 신청 경로를 만들지 않는다).

  /// 지금 보고 있는(= 신청 대상) 날짜 문서. 처음에는 목록에서 눌린 대표 문서다.
  late String _activeDocId = widget.docId;

  /// 상단 바의 신고·차단 버튼이 쓸 값 — 파티 문서가 도착할 때 채워진다.
  /// 상단 바가 StreamBuilder 바깥에 있어서 문서를 직접 볼 수 없기 때문이다.
  String _reportHostId = '';
  String _reportTitle = '';

  /// 같은 시리즈의 **아직 남아 있는** 일정 목록(시작 시각 오름차순).
  ///
  /// 이미 끝난 일정은 담기지 않는다([PartyTimeline]) — 1개 이하면 선택 UI를
  /// 그리지 않으므로, 남은 일정이 하나뿐이면 그 일정이 곧바로 상세가 되고
  /// 하나도 없으면(전부 지난 파티) 날짜 영역 자체가 사라진다.
  List<PartyScheduleOption> _scheduleOptions = const [];

  /// 정기 파티의 **실제 참가 회차** — 신청 플로우 안에서만 정해진다.
  ///
  /// 상세 화면이 보여주는 것은 반복 **규칙**뿐이다(상단 '일정' 칸과 '정기 일정'
  /// 줄) — 개별 날짜를 나열하지도, 고르게 하지도 않으므로 **상세는 이 값을
  /// 건드리지 않는다.** 신청은 언제나 특정 회차 한 건을 대상으로 하므로,
  /// '신청하기'를 눌러 연 달력에서만 여기에 담긴다([_pickOccurrence]).
  /// 일회성 파티는 회차가 하나뿐이라 쓰지 않는다.
  ///
  /// 규칙(플로우 진입마다 다시 묻기 / 직전 선택은 표시 초기값으로만 기억하기)은
  /// [ApplyOccurrenceState]에 모여 있다.
  final ApplyOccurrenceState _applyOccurrence = ApplyOccurrenceState();

  // ── 신청 진행 상태 ────────────────────────────────────────────────────
  //
  // 신청은 경로가 여러 갈래다(무료/유료·즉시승인/승인제·단일/정기·차수 선택).
  // 그 갈래가 전부 [_startApplyFlow] 하나로 모이므로, 진행 상태도 **이 플래그
  // 하나**만 쓴다 — 경로별로 따로 두면 어느 하나가 해제를 빠뜨렸을 때 버튼이
  // 영영 죽는다.
  //
  // 인위적인 딜레이가 아니라 **실제 비동기 작업의 수명**에 그대로 붙어 있다:
  // 플로우가 시작될 때 true, 어떤 경로로 끝나든(성공·실패·중간 취소) finally
  // 에서 false. 선택 시트가 떠 있는 동안에는 버튼이 모달 배리어에 가려 보이지
  // 않으므로, 이 값이 곧 "신청 요청이 살아 있다"는 뜻이 된다.
  bool _applying = false;

  /// 취소 요청이 살아 있는 동안 true.
  ///
  /// 취소도 신청과 같은 이유로 **플래그 하나**만 둔다 — 버튼 한 번 탭에
  /// callable이 한 번만 나가게 하는 관문이다. 확인 다이얼로그가 떠 있는 동안에도
  /// true라, 연타로 겹쳐 뜬 두 번째 다이얼로그를 눌러도 요청이 두 번 나가지 않는다.
  bool _cancelling = false;

  /// "이 회차 신청은 이미 끝났다"고 확인된 회차들.
  ///
  /// 파티 문서의 applicants 배열은 신청의 **상태**를 표현하지 못한다 —
  /// 취소가 서버에서 끝난 뒤에도 배열이 내려오기 전까지는 화면이 '신청 취소'를
  /// 계속 띄운다. 그 틈에 한 번 더 누르면 서버가 '이미취소'로 거절한다.
  /// 취소 성공·이미 취소됨을 확인한 순간 여기에 담아 버튼을 곧바로 감춘다.
  final Set<String> _knownCancelledKeys = <String>{};

  /// [_knownCancelledKeys]의 키 — "어느 문서의 어느 회차"까지 구분한다.
  String _applicationKey(Map<String, dynamic> data) =>
      '$_activeDocId/${_roundOccurrenceId(data) ?? ''}';

  /// 신청 각 구간 소요 시간 측정용 — 체감 지연이 UX 문제인지 실제 서버가
  /// 느린 것인지 가르려면 구간을 나눠 봐야 한다([_applyLog]).
  Stopwatch? _applyWatch;

  /// 서버 응답은 왔고 파티 문서(applicants)에 반영되기를 기다리는 중.
  /// 반영이 화면에 도달한 순간을 build에서 잡아 마지막 구간을 찍는다.
  bool _awaitingApplyReflection = false;

  /// 반영이 끝내 오지 않는 경우를 대비한 상한. 서버는 성공했는데 파티 문서에
  /// 내 uid가 올라오지 않는 경로(승인 대기로만 쌓이는 파티 등)에서 버튼이
  /// 영영 '신청 처리 중...'으로 남는 것을 막는다.
  Timer? _applyReleaseTimer;

  /// 신청 구간 로그 — `[apply] <구간> +<경과>ms` 한 줄.
  ///
  /// 버튼 탭을 0으로 잡고 누적 경과를 찍으므로, 어느 구간에서 시간이 튀는지
  /// 바로 보인다(함수 호출 전 = 클라이언트 준비, 호출~응답 = 서버,
  /// 응답~반영 = Firestore 전파).
  void _applyLog(String stage) {
    final watch = _applyWatch;
    if (watch == null) return;
    debugPrint('[apply] ${stage.padRight(24)} +${watch.elapsedMilliseconds}ms');
  }

  /// 달력에서 고른 날 아래에 붙는 요약 — '8월 25일(화)' / '오후 8:00 ·
  /// 모집 마감 오후 6:00' / (얼리버드가 붙는 날이면) 정상가 → 할인가.
  ///
  /// 세 값 모두 이미 정본이 있다: 시각·마감은 [PartyOccurrence](= PartySchedule이
  /// 만든 회차), 금액은 [PartyPricing] + 회차 기준 [EarlyBird.effectivePrice]다.
  /// 달력용으로 다시 계산하지 않으므로 여기 적힌 금액과 실제 신청 금액이
  /// 어긋날 수 없다.
  ///
  /// **이 요약은 날짜를 고른 뒤에만 그려진다.** 달력 칸은 얼리버드 여부를
  /// 드러내지 않으므로(occurrence_picker.dart 참고), 할인을 말하는 자리는
  /// 신청 흐름에서 여기가 처음이다.
  OccurrenceDaySummary _occurrenceSummary(
    Map<String, dynamic> data,
    PartyOccurrence occ,
  ) {
    final wd = _weekdayKo[occ.start.weekday - 1];
    final baseFee = PartyPricing.fromMap(data).displayPrice;
    final earlyBirdOn = EarlyBird.isActive(data, occurrenceStart: occ.start);
    final discounted = EarlyBird.effectivePrice(
      baseFee,
      data,
      occurrenceStart: occ.start,
    );
    final deadline = occ.deadline;
    return OccurrenceDaySummary(
      title: '${occ.start.month}월 ${occ.start.day}일($wd)',
      timeText: formatKoreanTimeOfDay(TimeOfDay.fromDateTime(occ.start)),
      deadlineText: deadline == null
          ? null
          : '모집 마감 ${formatKoreanTimeOfDay(TimeOfDay.fromDateTime(deadline))}',
      earlyBird:
          earlyBirdOn && EarlyBirdPriceLine.worthShowing(baseFee, discounted)
          ? (regular: baseFee, discounted: discounted)
          : null,
    );
  }

  /// 차수 시각을 계산할 기준 날짜 — "이 화면이 지금 말하고 있는 파티 날짜"다.
  ///
  /// 정기 파티는 사용자가 고른 회차(아직 안 골랐으면 다음 회차), 일회성 파티는
  /// 그 파티의 날짜다. `rounds[].time`은 등록 시점 날짜로 굳어 있는 캐시라
  /// 그대로 쓰면 두 번째 회차부터 모든 차수가 '종료'로 보인다
  /// ([PartyRoundOffers.of]의 occurrenceStart 참고).
  ///
  /// 표시(차수 및 참가비)·요약 줄·신청 시트가 **모두 이 하나**를 쓰므로 세
  /// 곳의 판정이 어긋날 수 없다.
  DateTime? _roundBaseDate(Map<String, dynamic> data) =>
      _applyOccurrence.selected?.start ?? PartySchedule.startAt(data);

  /// 차수 인원을 읽어올 회차 id — 정기 파티는 고른 회차, 아직 안 골랐으면
  /// 화면이 가리키는 다음 회차다. 일회성 파티는 회차가 없어 null이다.
  ///
  /// 정기 파티는 **차수 정원도 회차별**이라(서버 occurrenceStats.{회차}.rounds)
  /// 이 값이 없으면 8/22 차수에 8/15 인원이 그려진다.
  String? _roundOccurrenceId(Map<String, dynamic> data) {
    if (!PartySchedule.isRecurring(data)) return null;
    return _applyOccurrence.selected?.id ??
        PartySchedule.nextOccurrence(data)?.id;
  }

  /// 오늘 이후 신청 가능한 실제 회차 목록을 바텀시트로 띄운다.
  /// 고르면 [_applyOccurrence]에 담고 [_ApplyStep.proceed]를 돌려준다.
  ///
  /// **신청 플로우에서만 부른다** — 상세 화면에는 날짜를 고르는 자리가 없다
  /// (반복 규칙만 보여준다).
  ///
  /// [autoSelectSingle]이면 고를 회차가 하나뿐일 때 달력을 띄우지 않고 그
  /// 회차로 정한다 — 선택지가 하나뿐인 단계를 거치게 만들 이유가 없다
  /// (단일 날짜 파티가 날짜 선택 없이 곧바로 다음 단계로 가는 것과 같은 이유다).
  ///
  /// [canGoBack]이면 앞 단계(날짜 문서 선택)가 있다는 뜻이라, 시트를 닫는
  /// 모든 경로가 [_ApplyStep.back]이 된다 — 고를 회차가 하나도 없는 날짜를
  /// 골랐을 때도 마찬가지다(그 날짜에 갇히지 않고 다시 고를 수 있어야 한다).
  /// 본인확인으로 확정된 내 성별('male'/'female'). 아직 모르면 null —
  /// 성별별 모집 상태([PartyGenderRecruit])는 그때 판정하지 않고, 신청
  /// 시점에 서버가 users 문서의 정본 성별로 다시 본다.
  String? get _myGender =>
      UserSession.gender.isEmpty ? null : UserSession.gender;

  Future<_ApplyStep> _pickOccurrence(
    BuildContext context,
    Map<String, dynamic> data, {
    bool autoSelectSingle = false,
    bool canGoBack = false,
  }) async {
    // 시트를 닫는 모든 경로(← 버튼·시스템 뒤로가기·바깥 탭)가 여기로 모인다.
    final dismissed = canGoBack ? _ApplyStep.back : _ApplyStep.quit;
    // 회차 계산은 새로 만들지 않고 기존 recurringSchedule/nextOccurrence
    // 로직(PartySchedule)을 그대로 쓴다 — 선택한 날짜에 **실제로 존재하고
    // 아직 모집이 열려 있는** 회차만 담긴다.
    //
    // 거기서 **호스트가 닫은 회차**를 한 번 더 걷어낸다
    // ([PartyOccurrenceRecruit]) — 마감·취소한 날짜, 그리고 내 성별의 모집을
    // 닫은 날짜는 달력에 살아 있으면 안 된다(골라도 서버가 거절한다).
    final occurrences = PartyOccurrenceRecruit.openOccurrences(
      data,
      PartySchedule.selectableOccurrences(data),
      gender: _myGender,
    );
    if (occurrences.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('지금 신청할 수 있는 회차가 없어요.')));
      return dismissed;
    }
    if (autoSelectSingle && occurrences.length == 1) {
      setState(() => _applyOccurrence.select(occurrences.first));
      return _ApplyStep.proceed;
    }
    // 세로 목록 → 월간 달력. 매일 열리는 파티는 회차가 수십 개라 목록으로는
    // 원하는 날짜를 찾기 어려웠고, 화·목처럼 **요일 주기**도 보이지 않았다.
    // 달력이 스스로 일정을 계산하지는 않는다 — 위에서 만든 occurrences(실제로
    // 존재하고, 아직 오지 않았고, 모집이 열려 있는 회차)에 든 날만 살아 있다.
    final picked = await showApplyOccurrenceCalendar(
      context: context,
      occurrences: occurrences,
      selectedId: _applyOccurrence.calendarInitialId,
      canGoBack: canGoBack,
      // 얼리버드는 달력에 미리 드러내지 않는다 — 고른 날의 요약에서만 말한다
      // ([_occurrenceSummary]). 할인 판정·계산은 정본(EarlyBird) 그대로다.
      summaryOf: (occ) => _occurrenceSummary(data, occ),
    );
    if (picked == null) return dismissed;
    setState(() => _applyOccurrence.select(picked));
    return _ApplyStep.proceed;
  }

  @override
  void initState() {
    super.initState();
    // 화면이 다시 빌드될 때(StreamBuilder 갱신 등)마다 중복 기록되지 않도록
    // initState에서 한 번만 로깅한다 — build()는 파티 문서가 갱신될 때마다
    // 다시 호출되므로 거기서 로깅하면 조회수가 과도하게 잡힌다.
    AnalyticsService.logEvent(
      AnalyticsEventType.partyView,
      partyId: widget.docId,
    );
    // 로그인 화면에서 로그인을 마치고 이 화면으로 돌아왔을 때(또는 이
    // 화면을 띄운 채로 다른 경로에서 로그인/로그아웃이 일어났을 때) 뒤로
    // 갔다 다시 들어오지 않아도 신청 버튼 등이 즉시 로그인 상태를
    // 반영하도록 UserSession 변경을 구독한다.
    UserSession.revision.addListener(_onAuthChanged);
    _loadScheduleOptions();
  }

  /// 같은 게시글(`seriesId`)의 날짜 문서들을 읽어 "날짜 및 시간 선택" 목록을
  /// 만든다.
  ///
  /// 단일 필드 등등 조건이라 자동 색인만으로 동작한다(등록 화면과 삭제 흐름이
  /// 이미 같은 쿼리를 쓴다 — 새 인덱스가 필요하지 않다).
  /// `seriesId`가 없던 예전 문서는 시리즈 id가 자기 문서 id라, 이 쿼리가 0건이면
  /// 자기 자신 하나만 있는 것으로 보고 선택 UI를 그리지 않는다.
  ///
  /// **지난 일정은 목록에 담지 않는다** — 앞으로 신청할 수 있는 일정만 남는다.
  Future<void> _loadScheduleOptions() async {
    try {
      final self = await FirebaseFirestore.instance
          .collection('parties')
          .doc(widget.docId)
          .get();
      final selfData = self.data();
      if (selfData == null) return;
      final seriesId = PartySeries.idOf(selfData, widget.docId);

      final snap = await FirebaseFirestore.instance
          .collection('parties')
          .where('seriesId', isEqualTo: seriesId)
          .get();

      // 자기 문서는 쿼리 결과에 없을 수 있다(seriesId가 없는 레거시 문서).
      final docs = <String, Map<String, dynamic>>{widget.docId: selfData};
      for (final d in snap.docs) {
        docs[d.id] = d.data();
      }

      final now = DateTime.now();
      final options = <PartyScheduleOption>[];
      for (final entry in docs.entries) {
        final data = entry.value;
        if (!PartySeries.isVisible(data)) continue;
        // 정기 파티는 "날짜 문서 여러 개"가 아니라 반복 규칙 하나다 — 참가
        // 회차는 기존 회차 선택 시트(_pickOccurrence)가 담당하므로 여기서
        // 다루지 않는다.
        if (PartySchedule.isRecurring(data)) continue;
        final occ = PartySchedule.nextOccurrence(data, now: now);
        if (occ == null) continue;
        // 이미 끝난 일정은 목록에서 **아예 뺀다**. 고를 수도 신청할 수도 없는
        // 카드가 '지난 일정'으로 남아 자리만 차지했다. 판정은 시작이 아니라
        // 실제 종료 시각(차수 종료 포함) 기준이고, 목록의 대표 일정 계산과
        // 같은 함수를 쓴다([PartyTimeline]) — 두 화면의 "다음 일정"이 어긋날
        // 수 없다.
        if (PartyTimeline.hasEnded(data, now: now, occurrence: occ)) continue;
        final start = occ.start;
        final deadline = PartyCard.recruitDeadlineAt(data, now: now);
        final openAt = PartyCard.recruitOpenAt(data, now: now);
        // 모집 상태는 **보는 사람 성별 기준**이다 — 호스트가 남/여 모집을
        // 따로 닫아 둘 수 있어서, 같은 날짜가 남성에게는 마감이고 여성에게는
        // 열려 있을 수 있다([PartyGenderRecruit]). 날짜 문서마다 설정이 따로라
        // 이 목록에서 날짜별로 답이 갈리는 것이 정상이다.
        final status = PartyCard.effectiveStatusFor(data, _myGender, now: now);
        final genderClosedLabel =
            PartyGenderRecruit.isClosedFor(data, _myGender)
            ? (PartyGenderRecruit.labelFor(data, _myGender) ?? '모집 마감')
            : null;
        // 못 고르는 이유는 카드·버튼과 같은 판정을 쓴다(새 규칙을 만들지 않는다).
        // '지난 일정'은 더 이상 나오지 않는다 — 위에서 목록에서 빠졌다.
        //
        // 정원도 여기서 함께 본다. 마감·모집시작·모집상태만 보던 때에는 **정원이
        // 찬 날짜가 '신청 가능'으로 보였고**, 신청 버튼도 그 날짜 하나 때문에
        // 열렸다(고를 수 있는 날짜가 남아 있다고 판단해서). 고르고 나서야 정원
        // 초과로 막히니, 날짜 목록이 사실과 달랐다.
        // 정기 파티는 이 목록에 담기지 않으므로(위 continue) 여기 정원은 언제나
        // 그 날짜 문서 하나의 값이다 — 회차 누적값을 잘못 보는 문제가 없다.
        final blocked = (openAt != null && now.isBefore(openAt))
            ? '모집 시작 전'
            : (deadline != null && now.isAfter(deadline))
            ? '모집 마감'
            : genderClosedLabel ??
                  (status != '모집중'
                      ? status
                      : _isFull(data)
                      ? '정원 마감'
                      : null);
        options.add(
          PartyScheduleOption(
            docId: entry.key,
            start: start,
            end: occ.end,
            recruiting: blocked == null,
            blockedReason: blocked,
          ),
        );
      }
      options.sort((a, b) => a.start.compareTo(b.start));

      // 목록·링크로 들어온 문서 자체가 지난 일정이면 남아 있는 가장 이른
      // 일정으로 화면을 옮긴다 — 남은 일정이 하나뿐이면 선택 UI 없이 그 일정의
      // 상세가 바로 보이고, 여러 개면 사용자가 다시 고르게 둔다
      // (_scheduleConfirmed는 그대로 false라 신청 전에 한 번은 확정해야 한다).
      // 남은 일정이 하나도 없으면(전부 지난 파티) 지금 문서에 그대로 머물러
      // 기존 종료 정책(모집마감 상태 → 신청 버튼 비활성)이 그대로 적용된다.
      final selfEnded =
          !PartySchedule.isRecurring(selfData) &&
          PartyTimeline.hasEnded(selfData, now: now);

      if (!mounted) return;
      setState(() {
        _scheduleOptions = options;
        if (selfEnded &&
            options.isNotEmpty &&
            !options.any((o) => o.docId == _activeDocId)) {
          _activeDocId = options.first.docId;
        }
      });
    } catch (e) {
      // 형제 일정 조회가 실패해도 상세 화면 자체는 그대로 동작해야 한다 —
      // 선택 UI만 안 나오고 지금 문서로 신청하는 예전 흐름이 유지된다.
      debugPrint('[PartyDetail] 일정 목록 조회 실패: $e');
    }
  }

  /// 사용자가 날짜를 **직접** 골랐는지. 처음 들어왔을 때 [_activeDocId]는 목록
  /// 대표(가장 가까운) 일정이라 "선택된 것처럼" 보이는데, 여러 날짜 게시글에서는
  /// 그 상태로 신청이 나가면 안 된다 — 신청 전에 한 번은 반드시 고르게 한다.
  bool _scheduleConfirmed = false;

  /// 다른 날짜를 골랐다 — 화면 전체를 그 문서로 옮긴다(신청 대상도 함께 바뀐다).
  void _selectScheduleDoc(String docId) {
    setState(() {
      _activeDocId = docId;
      _scheduleConfirmed = true;
    });
  }

  /// 신청 전에 날짜가 확정됐는지 확인한다. 아직 안 골랐으면 선택 시트를 띄우고,
  /// 고르면 true를 돌려준다(신청 흐름이 곧바로 이어진다).
  ///
  /// 일정이 하나뿐인 파티(예전 데이터 포함)는 고를 것이 없으므로 그대로 통과한다.
  Future<bool> _ensureScheduleSelected(BuildContext context) async {
    if (_scheduleOptions.length < 2 || _scheduleConfirmed) return true;

    final selectable = _scheduleOptions.where((o) => o.recruiting).toList();
    if (selectable.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('지금 신청할 수 있는 일정이 없어요.')));
      return false;
    }
    final picked = await showModalBottomSheet<PartyScheduleOption>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '참가할 날짜를 선택해주세요',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              const Text(
                '고른 날짜의 일정으로 신청이 진행돼요.',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
              for (final option in _scheduleOptions)
                _ScheduleOptionTile(
                  option: option,
                  selected: option.docId == _activeDocId && _scheduleConfirmed,
                  onTap: option.recruiting
                      ? () => Navigator.pop(ctx, option)
                      : null,
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return false;
    _selectScheduleDoc(picked.docId);
    return true;
  }

  /// "📅 일정" — 이 게시글이 열리는 날짜를 **읽기만 하는** 안내다.
  ///
  /// 예전에는 여기가 '날짜 선택' 카드였다. 상세를 둘러보다 날짜를 누르면 그
  /// 날짜가 핑크 체크로 켜지고 신청 대상까지 그 자리에서 바뀌었다 — 상세를
  /// **읽는** 행위가 곧 신청 날짜를 **정하는** 행위가 되어, 신청 플로우가 다시
  /// 묻는 날짜와 두 벌이 됐다.
  ///
  /// 지금 신청 대상 회차의 정본은 신청 플로우에서 고른 값 하나뿐이다
  /// ([_ensureScheduleSelected]의 날짜 시트 → [_pickOccurrence]의 달력).
  /// 그래서 이 영역에는 선택 상태도, 누를 수 있는 자리도 없다.
  ///
  /// 그리는 조건은 예전과 같다 — 앞으로 열리는 날짜가 2개 이상일 때만이다.
  /// 하나뿐이면 위 요약 칸('날짜')이 이미 그 날짜와 시각을 말하고, 정기 파티는
  /// 애초에 [_scheduleOptions]에 담기지 않아(반복 규칙은 '정기 일정' 줄이
  /// 맡는다) 이 카드가 뜨지 않는다.
  ///
  /// 못 고르는 이유('모집 마감' 등)는 로그인한 사용자에게만 붙인다 — 예전
  /// 카드와 같은 판정이고, 로그인 전에는 그 자체가 상태 정보라 감춘다.
  Widget _scheduleInfo() {
    if (_scheduleOptions.length < 2) return const SizedBox.shrink();
    final revealStatus = UserSession.userId.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F0F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('📅', style: TextStyle(fontSize: 16)),
              SizedBox(width: 6),
              Text(
                '일정',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            "이 파티는 아래 날짜에 열려요. 참가할 날짜는 '신청하기'에서 고를 수 있어요.",
            style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.4),
          ),
          const SizedBox(height: 8),
          for (final option in _scheduleOptions)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _scheduleInfoLine(option, revealStatus: revealStatus),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2D3748),
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 안내 한 줄 — '9월 12일(토) 오후 7:00' (+ 로그인 상태면 ' · 모집 마감').
  String _scheduleInfoLine(
    PartyScheduleOption option, {
    required bool revealStatus,
  }) {
    final time = formatKoreanTimeOfDay(TimeOfDay.fromDateTime(option.start));
    final blocked = revealStatus ? option.blockedReason : null;
    return '${option.shortLabel} $time${blocked == null ? '' : ' · $blocked'}';
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    UserSession.revision.removeListener(_onAuthChanged);
    _applyReleaseTimer?.cancel();
    super.dispose();
  }

  /// 차수·패키지 선택 시트. 참가비까지 함께 보여주고 결제 예정 금액을 계산하는
  /// 일은 공용 위젯([PartyRoundOfferPicker])이 하고, 이 화면은 결과만 받는다 —
  /// 상세의 "차수 및 참가비" 영역과 같은 [PartyRoundOffers] 목록을 쓰므로 두
  /// 화면의 금액이 어긋날 수 없다.
  ///
  /// [canGoBack]이면 뒤로가기(←)를 띄우고, **시트를 닫는 모든 경로**(← 버튼,
  /// 시스템 뒤로가기/제스처, 바깥 탭)를 [_ApplyStep.back]으로 돌려준다 —
  /// 앞 단계인 날짜 선택으로 되돌아간다는 뜻이다. 앞 단계가 없는 파티
  /// (정기 파티가 아닌데 차수만 있는 경우)는 예전 그대로 신청을 그만둔다.
  Future<({_ApplyStep step, PartyRoundSelection? selection})> _pickRounds(
    BuildContext context,
    Map<String, dynamic> data, {
    required bool canGoBack,
  }) async {
    // 시트를 닫는 모든 경로가 여기로 모인다 — ← 버튼과 시스템 뒤로가기가
    // 같은 결말을 갖도록 한 곳에서만 정한다.
    final dismissed = canGoBack ? _ApplyStep.back : _ApplyStep.quit;
    final offers = PartyRoundOffers.of(
      data,
      gender: UserSession.gender,
      occurrenceStart: _roundBaseDate(data),
      // 정기 파티는 차수 정원도 회차별이다 — 잔여·'정원 마감' 판정이 고른
      // 회차의 인원을 보게 한다(서버 occurrenceStats.{회차}.rounds와 같은 값).
      occurrenceId: _roundOccurrenceId(data),
    );
    if (offers.isEmpty) {
      // 통합 정원 모드(차수별 참가비가 없는 파티) — 예전처럼 차수만 고른다.
      final rounds = PartyRoundOffers.roundsOf(data);
      if (rounds.isEmpty) return (step: _ApplyStep.quit, selection: null);
      final picked = await showDialog<List<int>>(
        context: context,
        builder: (_) =>
            _RoundSelectionDialog(rounds: rounds, canGoBack: canGoBack),
      );
      if (picked == null || picked.isEmpty) {
        return (step: dismissed, selection: null);
      }
      return (
        step: _ApplyStep.proceed,
        selection: PartyRoundSelection(roundNumbers: picked, expectedFee: 0),
      );
    }
    final selection = await showModalBottomSheet<PartyRoundSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (canGoBack)
                      // 날짜를 잘못 고른 사람의 유일한 출구다 — 이게 없으면
                      // 신청을 끝까지 진행하거나 화면을 닫는 수밖에 없다.
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.arrow_back, size: 20),
                          color: Colors.black54,
                          tooltip: '참가할 날짜 다시 고르기',
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                      ),
                    const Expanded(
                      child: Text(
                        '참여할 차수를 선택해주세요',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                PartyRoundOfferPicker(offers: offers),
              ],
            ),
          ),
        ),
      ),
    );
    if (selection == null || selection.roundNumbers.isEmpty) {
      return (step: dismissed, selection: null);
    }
    return (step: _ApplyStep.proceed, selection: selection);
  }

  /// 결제수단 고르기 — 참가비가 있는 파티만 거친다(무료 파티는 결제가 없으므로
  /// 화면 자체를 띄우지 않는다).
  ///
  /// 지금 고를 수 있는 것은 무통장입금·현장결제뿐이고, 어느 쪽도 **그 자리에서
  /// 결제되지 않는다** — 신청은 '입금대기'/'현장결제 예정'으로 만들어지고 확정은
  /// 입금 확인·현장 결제 뒤에 일어난다([PaymentStatus]).
  ///
  /// 취소하면 null을 돌려주고 신청 자체를 하지 않는다.
  Future<PaymentInfo?> _choosePayment(
    BuildContext context,
    Map<String, dynamic> data, {
    required int fee,
    required PaymentPolicy? policy,
    required PaymentBreakdown breakdown,
    PartyOccurrence? occurrence,
    int? originalFee,
  }) {
    final start = occurrence?.start ?? PartySchedule.startAt(data);
    // 얼리버드 표시 조건 — **고른 회차 기준 정본**이 유효하다고 할 때만,
    // 그리고 실제로 정상가가 더 비쌀 때만 취소선을 보여준다. 표시용으로
    // 여부를 새로 계산하지 않는다(회차를 안 넘기면 예전 버그로 되돌아간다).
    final earlyBirdOn = EarlyBird.isActive(data, occurrenceStart: start);
    final showsDiscount =
        earlyBirdOn && EarlyBirdPriceLine.worthShowing(originalFee, fee);
    return Navigator.push<PaymentInfo>(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentMethodScreen(
          summary: PaymentOrderSummary.party(
            partyName: data['title'] as String? ?? '파티',
            dateText: start == null ? '일정 미정' : _applyDateText(start),
            peopleText: '1명',
            fee: fee,
            originalFee: showsDiscount ? originalFee : null,
            discountLabel: showsDiscount ? '얼리버드' : null,
          ),
          // 호스트가 결제 방식을 정한 파티만 "지금 얼마 / 현장에서 얼마"를
          // 보여주고 수단을 좁힌다. 설정이 없는 기존 파티는 둘 다 null이라
          // 지금까지의 화면 그대로다.
          breakdown: policy == null ? null : breakdown,
          allowedMethods: policy?.allowedMethods,
          // 돈을 받는 사람 = 이 파티의 호스트.
          hostId: (data['hostId'] ?? data['hostUid']) as String? ?? '',
        ),
      ),
    );
  }

  /// '8월 20일(수) 오후 7:00' — 결제 화면 주문정보에 쓰는 짧은 표기.
  static String _applyDateText(DateTime d) {
    const week = ['월', '화', '수', '목', '금', '토', '일'];
    final ampm = d.hour < 12 ? '오전' : '오후';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${d.month}월 ${d.day}일(${week[d.weekday - 1]}) '
        '$ampm $h:${d.minute.toString().padLeft(2, '0')}';
  }

  void _snack(BuildContext context, String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  /// 신청 플로우 안에서 **날짜를 새로 고른 뒤** 그 문서 기준으로 다시 보는
  /// 차단 사유. 막을 이유가 없으면 null.
  ///
  /// 판정 규칙은 신청 버튼의 것과 같은 함수를 쓴다(새 규칙을 만들지 않는다) —
  /// 다만 대상이 "화면이 보여주던 날짜"가 아니라 "방금 고른 날짜"다. 정기 파티의
  /// **회차별** 정원은 파티 문서의 `occurrenceStats`에만 있고 클라이언트는 그
  /// 값을 읽지 않으므로 여기서 판정하지 않는다 — 서버(reserveApplicantSlot)가
  /// 회차 칸을 보고 최종 판정한다.
  String? _applyBlockReason(Map<String, dynamic> data) {
    // 오픈예정은 마감·정원보다 먼저 본다 — 아직 모집 자체가 시작되지 않았다.
    if (PartyOpenState.isPreopen(data)) {
      return '아직 오픈 전인 파티예요. 오픈 알림을 신청하면 열릴 때 알려드려요.';
    }
    final now = DateTime.now();
    final openAt = PartyCard.recruitOpenAt(data, now: now);
    if (openAt != null && now.isBefore(openAt)) {
      return '선택한 날짜는 아직 모집 시작 전이에요.';
    }
    final deadline = PartyCard.recruitDeadlineAt(data, now: now);
    if (deadline != null && deadline.isBefore(now)) {
      return '선택한 날짜는 모집이 마감됐어요.';
    }
    final status = data['recruitStatus'] as String? ?? '모집중';
    if (status != '모집중') return '선택한 날짜는 지금 신청받지 않아요($status).';
    // 성별별 모집 상태는 아래 checkPartyEligibility가 자기 성별 기준으로
    // 판정한다(성별을 아직 모르는 사용자는 양쪽이 다 닫혔을 때만 걸린다).
    if (PartyGenderRecruit.isClosedFor(data, _myGender)) {
      final label = PartyGenderRecruit.labelFor(data, _myGender) ?? '모집마감';
      return '선택한 날짜는 지금 $label 상태예요.';
    }
    if (_isFull(data)) return '선택한 날짜는 정원이 다 찼어요. 다른 날짜를 골라주세요.';
    final eligibility = checkPartyEligibility(
      data,
      UserSession.gender,
      UserSession.birthYear,
    );
    if (eligibility != PartyEligibility.eligible) {
      return eligibilityLabel(eligibility);
    }
    return null;
  }

  /// '신청하기' 진입점 — 버튼은 언제나 이 하나이고, **아직 정해지지 않은 값만**
  /// 여기서 순서대로 이어 받는다:
  ///
  ///   로그인 → 닉네임 → ① 날짜 → ② 회차(시간) → ③ 차수 → ④ 결제수단 → ⑤ 신청
  ///
  /// 상세에서 이미 고른 단계는 각 헬퍼가 스스로 건너뛰고, 선택지가 하나뿐인
  /// 단계도 시트를 띄우지 않고 통과한다 — 고를 것이 없는 파티는 버튼 한 번으로
  /// 바로 신청된다. 날짜를 **미리 고르지 않았다는 이유로 버튼을 막지 않는 것**이
  /// 이 흐름의 핵심이다(버튼이 곧 선택의 진입점이다).
  ///
  /// 마감·정원·자격·결제 검증은 예전 그대로다 — 최종 판정은 언제나 서버
  /// (applyToParty)가 하고, 여기서는 사용자가 헛걸음하지 않도록 미리 걸러줄 뿐이다.
  Future<void> _startApplyFlow(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    // 빠르게 여러 번 눌러도 신청은 한 번만 나간다 — 버튼 비활성화(onPressed
    // null)만으로는 같은 프레임에 들어온 연타를 놓칠 수 있어, 진입점에서도
    // 한 번 더 막는다.
    if (_applying) return;
    setState(() {
      _applying = true;
      _applyWatch = Stopwatch()..start();
      _awaitingApplyReflection = false;
    });
    _applyLog('버튼 탭');
    try {
      await _runApplyFlow(context, data);
    } finally {
      // 성공·실패·중간 취소 어느 쪽으로 끝나든 반드시 로딩을 푼다.
      //
      // 단, 서버가 성공을 돌려준 직후에는 아직 파티 문서에 내 신청이
      // 반영되기 전이다. 여기서 바로 풀면 버튼이 '신청하기'로 되돌아갔다가
      // 곧 '신청 완료'로 바뀌는 깜빡임이 생기고, 그 찰나에 한 번 더 눌릴 수도
      // 있다. 그래서 반영이 도착할 때까지(또는 상한까지) 로딩을 유지한다.
      if (mounted) {
        if (_awaitingApplyReflection) {
          _applyReleaseTimer?.cancel();
          _applyReleaseTimer = Timer(const Duration(seconds: 8), () {
            if (!mounted || !_applying) return;
            _applyLog('반영 대기 상한 도달 — 로딩 해제');
            _applyWatch = null;
            setState(() {
              _applying = false;
              _awaitingApplyReflection = false;
            });
          });
        } else {
          setState(() => _applying = false);
        }
      }
    }
  }

  Future<void> _runApplyFlow(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    if (UserSession.userId.isEmpty) {
      // await 없이 push만 하면 로그인 완료 후 돌아왔을 때 이 핸들러는 이미
      // 끝나버려서 로그인 여부를 다시 확인할 기회가 없었다 —
      // UserSession.revision을 구독 중이라 화면 자체는 곧바로 갱신되지만,
      // 여기서도 await해 화면이 돌아온 시점을 명확히 한다.
      await Navigator.push(context, webFramedRoute((_) => LoginPage()));
      return;
    }
    if (!await _requireNickname(context)) return;
    if (!context.mounted) return;

    // ①~⑥은 **앞뒤로 오갈 수 있어야 한다.** 예전에는 한 방향으로만 흘러서,
    // 날짜를 잘못 고른 사람이 뒤 단계에서 할 수 있는 일이 "끝까지 진행" 또는
    // "화면 닫기"뿐이었다. 그래서 순서를 그대로 두되 통째로 루프로 돌린다 —
    // 어느 단계든 [_ApplyStep.back]을 돌려주면 그 단계에서 고른 값을 지우고
    // 한 칸 앞부터 다시 묻는다.
    //
    // 서버에 무언가를 만드는 것은 **마지막 신청 호출 하나뿐**이라, 몇 번을
    // 오가도 신청 문서가 중복으로 생기지 않는다(사전질문 사진만 예외라
    // 아래에서 따로 들고 다닌다).
    //
    // 단계 상태는 전부 이 아래 지역 변수다. 뒤로 갈 때 "무엇을 지워야 하는지"가
    // 한 곳에 모여 있어야, 지난 날짜의 차수·금액으로 신청이 나가는 일이 없다.
    var target = data;
    // [target]을 읽어온 문서. [_activeDocId]와 어긋나면 날짜가 바뀐 것이다.
    var loadedDocId = _activeDocId;
    // 날짜 문서를 고를 수 있는 게시글인가 — ①이 존재하는지를 가른다.
    final canPickScheduleDoc = _scheduleOptions.length >= 2;
    // 회차가 하나뿐일 때 시트를 건너뛰는 것은 **그 문서에서 처음 한 번뿐**이다.
    // 뒤로 돌아온 사용자에게까지 건너뛰면 고치러 온 화면이 나타나지 않는다.
    var autoSelectSingleOccurrence = true;
    PartyRoundSelection? roundSelection;
    // 사전질문은 제출하는 순간 사진이 Storage에 올라간다 — 뒤로 갔다 와도 다시
    // 올리지 않도록 답변을 들고 다닌다. 다만 **날짜 문서나 회차가 바뀌면**
    // 사진이 매달린 신청 문서 자체가 달라지므로(applicationDocId) 버린다.
    PartyApplicationSubmission? submission;
    String? submissionDocId;
    String? submissionOccurrenceId;

    // 참가 회차는 **이 흐름 안에서만** 정해진다.
    //
    // 상세 화면에는 날짜를 고르는 자리가 없어 이 값을 만들지 않고, 지난번 신청에서
    // 남아 있던 값도 여기서 비운다 — 그래야 '신청하기'를 누를 때마다 ②의 달력이
    // 정확히 한 번 뜬다(예전에는 상세에서 미리 골라두면 그 단계를 건너뛰었다).
    //
    // 직전에 고른 날은 [ApplyOccurrenceState.calendarInitialId]가 기억해 달력의
    // **초기값**으로만 되살아난다 — 신청 대상은 달력에서 다시 확정된다.
    setState(_applyOccurrence.beginFlow);

    while (true) {
      // ① 날짜 — 같은 게시글에 날짜 문서가 여럿이면 먼저 확정한다.
      // (일정이 하나뿐인 파티는 [_ensureScheduleSelected]가 그대로 통과시킨다.)
      if (!await _ensureScheduleSelected(context)) return;
      if (!context.mounted) return;

      // 날짜를 새로 골랐으면 **신청 대상 문서가 바뀐다**. 정원·차수·참가비·마감이
      // 전부 문서 단위라, 화면이 다시 그려지기를 기다리지 않고 바뀐 문서를 여기서
      // 직접 읽어 이어간다 — 이전 날짜의 차수·금액으로 신청이 나가면 안 된다.
      if (_activeDocId != loadedDocId) {
        final snap = await FirebaseFirestore.instance
            .collection('parties')
            .doc(_activeDocId)
            .get();
        final fresh = snap.data();
        if (!context.mounted) return;
        if (fresh == null) {
          _snack(context, '선택한 날짜의 파티를 찾을 수 없어요.');
          return;
        }
        // 바뀐 문서 기준으로 **모집상태·마감·모집시작·정원·자격을 다시 판정한다.**
        //
        // 날짜 목록(_scheduleOptions)의 recruiting 플래그는 화면에 처음 들어올 때
        // 읽은 스냅샷이라, 상세를 오래 열어둔 사이 마감 시각이 지나면 실제와
        // 어긋난다. 여기서 방금 읽은 문서로 다시 보면 결제수단까지 고른 뒤에
        // 서버가 거절하는 헛걸음이 없어진다(서버 판정은 그대로 최종 관문이다).
        final blocked = _applyBlockReason(fresh);
        if (blocked != null) {
          // 막힌 날짜를 고른 것뿐이니 신청을 끝내지 않고 ①부터 다시 묻는다.
          //
          // [target]과 [loadedDocId]는 **그대로 둔다** — 여기서 커밋해 버리면
          // 사용자가 같은 날짜를 한 번 더 골랐을 때 "바뀐 게 없다"가 되어
          // 마감 판정을 건너뛴 채 흘러간다.
          _snack(context, blocked);
          setState(() => _scheduleConfirmed = false);
          continue;
        }

        target = fresh;
        loadedDocId = _activeDocId;
        // 문서가 바뀌면 앞서 고른 값은 **전부 다른 파티의 것**이다 — 회차·차수는
        // 물론 사전질문 답변까지 버린다(사진이 옛 문서 경로에 매달려 있다).
        roundSelection = null;
        submission = null;
        submissionDocId = null;
        submissionOccurrenceId = null;
        autoSelectSingleOccurrence = true;
        if (_applyOccurrence.selected != null) {
          setState(_applyOccurrence.clear);
        }
      }

      // 문서가 바뀌면 이 두 값도 바뀔 수 있다(A는 차수가 있고 B는 없는 식) —
      // 루프 밖에서 한 번만 계산하면 지난 문서의 성격으로 흐름이 흘러간다.
      final isRecurring = PartySchedule.isRecurring(target);
      final hasRounds = target['hasMultipleRounds'] == true;

      // ② 정기 파티의 참가 회차도 결국 '날짜'다 — 차수보다 먼저 물어 "날짜를 다
      // 고른 뒤 시간을 고르는" 순서를 지킨다. 상세에서 미리 골랐으면 건너뛴다.
      if (isRecurring && _applyOccurrence.selected == null) {
        final picked = await _pickOccurrence(
          context,
          target,
          autoSelectSingle: autoSelectSingleOccurrence,
          canGoBack: canPickScheduleDoc,
        );
        if (!context.mounted) return;
        if (picked == _ApplyStep.quit) return;
        if (picked == _ApplyStep.back) {
          setState(() => _scheduleConfirmed = false); // ①로
          continue;
        }
      }
      autoSelectSingleOccurrence = false;

      // 들고 온 답변이 **지금 신청과 같은 문서·같은 회차의 것**일 때만 쓴다.
      // (문서가 바뀌는 경로에서 이미 버리지만, 여기서 한 번 더 못 박는다.)
      if (submission != null &&
          (submissionDocId != loadedDocId ||
              submissionOccurrenceId != _applyOccurrence.selected?.id)) {
        submission = null;
        submissionDocId = null;
        submissionOccurrenceId = null;
      }

      // ③ 차수·패키지 — 1차/2차가 있는 파티만.
      if (hasRounds && roundSelection == null) {
        final picked = await _pickRounds(
          context,
          target,
          canGoBack: isRecurring || canPickScheduleDoc,
        );
        if (!context.mounted) return;
        if (picked.step == _ApplyStep.quit) return;
        if (picked.step == _ApplyStep.back) {
          // 한 칸 앞으로 — 회차가 있으면 ②, 없으면 ①이다.
          if (isRecurring) {
            setState(_applyOccurrence.clear);
          } else {
            setState(() => _scheduleConfirmed = false);
          }
          continue;
        }
        roundSelection = picked.selection;
        // proceed면 선택이 반드시 실려 오지만, 만에 하나 비어 오면 같은
        // 단계를 무한히 다시 묻게 된다 — 그럴 바에는 조용히 그만둔다.
        if (roundSelection == null) return;
      }

      // ④ 사전질문 → ⑤ 결제수단 → ⑥ 최종 신청. 참가비는 서버가 다시 계산하므로
      // 여기 값은 결제 화면에 보여줄 예상 금액이다(차수를 골랐으면 그 금액,
      // 아니면 대표 금액).
      final result = await _apply(
        context,
        data: target,
        // 차수를 고른 경우는 PartyRoundOffers가 이미 그 회차 기준으로 얼리버드를
        // 반영해 돌려준다. 차수가 없는 파티는 여기서 같은 회차 기준으로 적용해야
        // 서버 computeAppliedFee와 값이 맞는다 — 안 맞으면 결제 화면에 정상가가
        // 뜨고, 예약금 정책이 있는 파티는 서버 assertClientAmountMatches에 걸려
        // 신청 자체가 '금액이 변경되었어요'로 막힌다.
        expectedFee:
            roundSelection?.expectedFee ??
            EarlyBird.effectivePrice(
              PartyPricing.fromMap(target).displayPrice,
              target,
              occurrenceStart:
                  _applyOccurrence.selected?.start ??
                  PartySchedule.startAt(target),
            ),
        // 할인 전 정상가 — 결제 화면에서 "20,000원(취소선) → 얼리버드 16,000원"
        // 으로 보여주기 위한 **표시용 값**이다. 신청 payload에는 실리지 않고,
        // 금액의 정본은 그대로 서버 계산이다.
        //
        // 여기서 얼리버드를 다시 판정하지 않는다 — 차수를 골랐으면
        // PartyRoundOffers가 회차 기준으로 계산해둔 정상가 합계를, 아니면
        // 위 expectedFee와 짝이 되는 같은 파티 참가비를 그대로 쓴다.
        originalFee:
            roundSelection?.originalFee ??
            PartyPricing.fromMap(target).displayPrice,
        selectedRounds: roundSelection?.roundNumbers,
        packageId: roundSelection?.packageId,
        occurrence: _applyOccurrence.selected,
        cachedSubmission: submission,
      );
      if (result.step != _ApplyStep.back) return;

      // 뒤로 — 바로 앞의 '고르는 단계'부터 다시 묻는다.
      submission = result.submission;
      submissionDocId = submission == null ? null : loadedDocId;
      submissionOccurrenceId = submission == null
          ? null
          : _applyOccurrence.selected?.id;
      if (hasRounds) {
        roundSelection = null; // ③으로
      } else if (isRecurring) {
        setState(_applyOccurrence.clear); // ②로
      } else if (canPickScheduleDoc) {
        setState(() => _scheduleConfirmed = false); // ①로
      } else {
        return; // 돌아갈 앞 단계가 없다.
      }
      if (!context.mounted) return;
    }
  }

  /// 사전질문 → 결제수단 → 신청 호출.
  ///
  /// 앞의 두 단계에서 사용자가 되돌아가면 [_ApplyStep.back]을 돌려준다.
  /// 이때 **이미 받아둔 사전질문 답변은 함께 돌려준다** — 사진이 그 시점에
  /// 이미 Storage에 올라갔기 때문에, 다시 물으면 같은 사진이 한 벌 더 쌓인다.
  /// 호출부가 그 값을 [cachedSubmission]으로 되돌려주면 질문 화면을 건너뛴다.
  Future<({_ApplyStep step, PartyApplicationSubmission? submission})> _apply(
    BuildContext context, {
    required Map<String, dynamic> data,
    required int expectedFee,
    int? originalFee,
    List<int>? selectedRounds,
    String? packageId,
    PartyOccurrence? occurrence,
    PartyApplicationSubmission? cachedSubmission,
  }) async {
    // 호스트 결제 방식 — 파티 문서 최상단에 평평하게 저장돼 있다. 설정이
    // 없으면 null이고, 그때는 지금까지처럼 참가자가 수단을 자유롭게 고른다.
    // 무료 파티는 정책을 보지 않는다(받을 돈이 없으면 예약금이 성립하지 않음).
    final policy = expectedFee > 0 ? PaymentPolicy.fromMap(data) : null;
    final breakdown = PaymentBreakdown.of(policy, expectedFee);

    // ④-b 사전질문·사진 — **호스트가 받기로 한 것이 있을 때만** 연다.
    //
    // 예전에는 "승인제면 연다"였다(form.requiresApproval). 그러면 질문도 사진도
    // 요청하지 않은 승인제 파티에서 신청자가 빈 화면을 한 번 거쳐야 했고,
    // 무엇보다 호스트가 요청한 적 없는 프로필 사진 칸이 떴다.
    //
    // 결제 **전에** 두는 이유는 그대로다: 결제하고 나서야 질문이 나오면 답을
    // 못 채운 사람이 이미 돈을 낸 상태가 된다.
    final form = PartyApplicationForm.fromParty(data);
    // 뒤로 갔다 온 신청이면 답변을 이미 받아 뒀다 — 다시 묻지 않는다.
    var submission = cachedSubmission;
    if (form.needsSubmissionStep && submission == null) {
      submission = await Navigator.push<PartyApplicationSubmission>(
        context,
        webFramedRoute(
          (_) => PartyApplicationAnswerScreen(
            partyId: _activeDocId,
            hostId: data['hostId'] as String? ?? '',
            applicationId: partyApplicationDocId(occurrence?.id),
            form: form,
          ),
        ),
      );
      if (!context.mounted) {
        return (step: _ApplyStep.quit, submission: submission);
      }
      // 질문 화면에서 뒤로가기 — 앞 단계(차수/날짜)로 돌려보낸다.
      if (submission == null) {
        return (step: _ApplyStep.back, submission: null);
      }
    }

    // ⑤ 결제수단 — 참가비가 있는 파티만. 고르지 않고 나가면 신청하지 않는다.
    PaymentInfo? payment;
    if (expectedFee > 0) {
      payment = await _choosePayment(
        context,
        data,
        fee: expectedFee,
        originalFee: originalFee,
        policy: policy,
        breakdown: breakdown,
        occurrence: occurrence,
      );
      if (!context.mounted) {
        return (step: _ApplyStep.quit, submission: submission);
      }
      // 결제수단 화면에서 뒤로가기 — 받아둔 답변은 그대로 들고 돌아간다.
      if (payment == null) {
        return (step: _ApplyStep.back, submission: submission);
      }
      // ⑤-1 환불계좌 — **무통장입금을 고른 경우에만** 확인한다.
      //
      // 무통장입금은 PG가 없어 원결제 취소가 불가능하다. 취소·환불이 생기면
      // 계좌이체가 유일한 길이므로, 돈을 내기 **전에** 본인 명의로 인증된
      // 환불계좌를 받아 둔다. 현장결제는 현장에서 현금으로 돌려주므로 이
      // 단계를 지나간다.
      //
      // 인증을 마치지 않으면 받아둔 답변을 들고 앞 단계로 돌려보낸다 —
      // 서버(applyToParty)가 어차피 같은 조건으로 거절하므로, 여기서 멈추는
      // 편이 "신청은 눌렀는데 실패"보다 낫다.
      if (payment.method == PaymentMethod.bankTransfer) {
        final ready = await ensureRefundAccountVerified(context);
        if (!context.mounted) {
          return (step: _ApplyStep.quit, submission: submission);
        }
        if (!ready) {
          return (step: _ApplyStep.back, submission: submission);
        }
      }
    }
    // 여기까지가 클라이언트 준비 구간(로그인·닉네임·날짜·회차·차수·결제수단).
    // 사용자가 시트에서 고민한 시간도 포함되므로, 아래 호출~응답 구간과 나눠
    // 봐야 "느린 게 서버인지 선택 단계인지"가 갈린다.
    _applyLog('선택 완료 → 호출 준비');
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('applyToParty');
      _applyLog('함수 호출 시작');
      final result = await callable.call({
        // 여러 날짜 게시글은 상세에서 고른 날짜의 **문서**가 신청 대상이다 —
        // 정원·마감이 문서 단위라 서버 로직은 예전 그대로 동작한다.
        'partyId': _activeDocId,
        'selectedRounds': ?selectedRounds,
        // 패키지 신청 — 서버가 파티 문서의 패키지 정의로 포함 차수와 금액을
        // 다시 확인하므로, 여기서 보낸 차수 목록만으로는 패키지 가격이
        // 적용되지 않는다(조작 방지).
        'packageId': ?packageId,
        // 정기 파티는 "어느 회차에 가는지"까지 함께 보낸다 — 서버가 같은
        // 규칙으로 회차를 다시 계산해 검증하고, 신청 문서와 회차별 카운터에
        // 이 값을 기준으로 기록한다.
        if (occurrence != null) ...{
          'occurrenceId': occurrence.id,
          'occurrenceStartAt': occurrence.start.toUtc().toIso8601String(),
        },
        // 결제수단·결제상태 — 서버가 수단을 다시 검증하고 **상태는 서버가
        // 정한다**(클라이언트가 보낸 status는 쓰지 않는다). 무료 파티는 이
        // 필드 자체가 없다.
        if (payment != null) 'payment': payment.toMap(),
        // 화면에 띄운 금액 — 서버가 자기 계산과 대조해 다르면 신청을 막는다.
        // 금액의 정본은 어디까지나 서버 계산이고 이 값은 대조용이다.
        if (policy != null) 'amounts': breakdown.toClaim(),
        // 사전질문 답변·제출 사진 — 승인제 파티에만 있다. 질문 정의와 필수
        // 여부는 서버가 파티 문서에서 **다시 읽어** 검증하므로, 여기서 보낸
        // 값만으로는 필수 답변을 건너뛸 수 없다.
        if (submission != null) ...{
          'answers': submission.answers,
          'photos': submission.photos,
        },
      });

      _applyLog('서버 응답');
      // 이제부터는 파티 문서(applicants)가 스트림으로 내려오기를 기다리는
      // 구간이다 — 도달하는 순간을 build에서 잡는다.
      _awaitingApplyReflection = true;
      // 취소했다가 다시 신청한 회차 — '이미 끝난 신청'이라는 기억을 지운다.
      _knownCancelledKeys.remove(_applicationKey(data));

      if (context.mounted) {
        // 서버가 신청 확정 시점에 계산한 실제 적용 금액(얼리버드 반영)을 그대로 안내.
        final resultData = Map<String, dynamic>.from(result.data as Map);
        final appliedFee = (resultData['appliedFee'] as num?)?.toInt() ?? 0;
        // 결제가 붙은 신청은 **아직 결제가 끝나지 않았다** — '완료'라고 말하면
        // 입금 전인데 확정된 것으로 읽힌다. 그래서 결제 상태를 그대로 알린다.
        // 무통장입금이면 **어디서 계좌를 보는지**까지 알려준다. 계좌는 신청이
        // 만들어진 뒤 그 신청 문서의 스냅샷으로만 보이는데(호스트의 인증된
        // 수취계좌 — functions/paymentInfo.js), 이 자리에서 아무 말도 하지
        // 않으면 "입금대기"라는 말만 듣고 어디로 가야 할지 모른 채 화면을
        // 떠나게 된다. 계좌 자체는 여기 띄우지 않는다 — 스낵바는 사라지고,
        // 정본은 신청 내역의 입금 안내([DepositPanel]) 하나뿐이다.
        final msg = payment == null
            ? (appliedFee > 0
                  ? '신청이 완료되었습니다! (참가비 ${_formatFee(appliedFee)})'
                  : '신청이 완료되었습니다!')
            : '신청이 접수됐어요 · ${payment.status.label} — '
                  '${payment.status.description}'
                  '${payment.method == PaymentMethod.bankTransfer ? '\n입금 계좌는 마이 > 파티츄 게스트 > 파티츄 탭에서 확인할 수 있어요.' : ''}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        _applyLog('안내 표시(스낵바)');

        // 신청을 막 마친 지금이 알림을 권하기 좋은 자리다 — 승인·입금 확인·
        // 시작 1시간 전 안내가 전부 이 신청에 딸려 오기 때문. 스낵바가 먼저
        // 보이도록 한 프레임 뒤로 미룬다.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          PushPermissionGate.ensure(context, PushPromptReason.booking);
        });
      }
    } catch (e) {
      _applyLog('실패(${e.runtimeType})');
      _awaitingApplyReflection = false;
      _applyWatch = null;
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_applyErrorMessage(e))));
      }
    }
    // 성공이든 실패든 이 신청 시도는 여기서 끝난다 — 실패는 이미 스낵바로
    // 알렸으므로 앞 단계로 되돌리지 않는다(예전과 같은 동작이다).
    return (step: _ApplyStep.proceed, submission: submission);
  }

  // 참가자 자체 취소 — 실제 결제 금액(appliedFee)은 파티 문서가 아니라
  // parties/{id}/applications/{uid} 서브컬렉션에 신청 시점 스냅샷으로
  // 저장돼 있다(얼리버드 할인 등으로 파티의 현재 참가비와 다를 수 있음).
  // 미리보기는 클라이언트에서 계산하지만, 실제 환불 금액/상태는 서버
  // (cancelApplication)가 다시 계산해 저장한 값을 최종으로 신뢰한다.
  Future<void> _confirmAndCancelApplication(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final userId = UserSession.userId;
    if (userId.isEmpty) return;
    // 취소 요청이 이미 살아 있으면 아무 것도 하지 않는다 — 버튼을 연타해
    // 확인 다이얼로그가 겹쳐 떠도 callable은 탭 한 번당 한 번만 나간다
    // (신청의 [_applying]과 같은 방식이다).
    if (_cancelling) return;
    setState(() => _cancelling = true);
    try {
      await _cancelApplicationFlow(context, data, userId);
    } finally {
      if (mounted) {
        setState(() => _cancelling = false);
      } else {
        _cancelling = false;
      }
    }
  }

  Future<void> _cancelApplicationFlow(
    BuildContext context,
    Map<String, dynamic> data,
    String userId,
  ) async {
    // 취소 대상은 **지금 화면이 가리키는 회차 한 건**이다. 정기 파티는 회차마다
    // 신청 문서가 따로 있으므로(서버 applicationDocId), 문서 ID도 회차까지
    // 합쳐 만든다.
    //
    // 회차 id는 [_applicantsOf]와 **같은 값**을 쓴다. 예전에는 여기만
    // 고른 회차 id 하나였는데, 상세를 새로 열면 그 값이 null이라
    // 화면은 '다음 회차' 기준으로 취소 버튼을 띄우면서 요청은 회차 없이 나갔다.
    // 그러면 서버는 회차가 붙기 전의 옛 신청 문서(id가 uid)를 보게 되고,
    // 그 문서가 예전에 취소된 건이면 '이미취소'로 거절한다.
    final occurrenceId = _roundOccurrenceId(data);
    int appliedFee = 0;
    // 무통장입금으로 **실제 입금까지 끝난** 건인지 — 이때만 환불계좌를 묻는다.
    // (무료·현장결제·입금 전 취소는 계좌이체로 돌려줄 돈이 없다.)
    bool paidByBankTransfer = false;
    // 취소할 게 남아 있지 않은 신청이면 그 이유 — 서버까지 갈 필요 없이
    // 화면만 그 상태로 맞춘다.
    String? closedReason;
    try {
      final apps = FirebaseFirestore.instance
          .collection('parties')
          .doc(_activeDocId)
          .collection('applications');
      var appSnap = await apps
          .doc(occurrenceId == null ? userId : '${userId}_$occurrenceId')
          .get();
      if (!appSnap.exists && occurrenceId != null) {
        // 옛 문서(id가 uid) 폴백 — 서버(cancelApplication)와 **같은 조건**으로만
        // 쓴다. 이미 취소된 옛 문서를 이 회차의 신청으로 오인하면, 화면은
        // 취소할 게 있다고 믿고 서버는 '이미취소'로 거절하는 어긋남이 생긴다.
        final legacy = await apps.doc(userId).get();
        final legacyOcc = legacy.data()?['occurrenceId'] as String?;
        if (legacy.exists &&
            legacy.data()?['status'] != 'cancelled' &&
            (legacyOcc ?? occurrenceId) == occurrenceId) {
          appSnap = legacy;
        }
      }
      if (!appSnap.exists) {
        closedReason = '취소할 신청 내역이 없어요.';
      } else {
        closedReason = _closedApplicationMessage(
          appSnap.data()?['status'] as String?,
        );
      }
      appliedFee = (appSnap.data()?['appliedFee'] as num?)?.toInt() ?? 0;
      final pay = appSnap.data()?['payment'] as Map<String, dynamic>?;
      paidByBankTransfer =
          pay?['method'] == 'bank_transfer' && pay?['status'] == 'paid';
    } catch (_) {
      // 조회 실패 시에도 취소 자체는 진행할 수 있게 0원으로 폴백(서버가 재계산).
    }

    // 이미 끝난 신청이면 확인 다이얼로그도 띄우지 않는다 — 화면을 취소됨으로
    // 맞춰 버튼을 감추고, 사용자에게는 상태만 한 줄로 알린다.
    if (closedReason != null) {
      _markApplicationClosed(data);
      if (context.mounted) _snack(context, closedReason);
      return;
    }

    final refundPolicy = RefundTier.listFromDynamic(data['refundPolicy']);
    final partyDateTime = PartyCard.parsePartyDateTime(data);
    final preview = computeRefundPreview(
      refundPolicy: refundPolicy,
      appliedFee: appliedFee,
      partyDateTime: partyDateTime,
    );

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _CancelApplicationDialog(appliedFee: appliedFee, preview: preview),
    );
    if (confirmed != true || !context.mounted) return;

    // ── 환불계좌 ──────────────────────────────────────────────────────────
    // 돌려줄 돈이 실제로 있고, 그 돈이 계좌이체로만 돌아갈 수 있는 건일 때만
    // 계좌를 확인한다. 시트는 **인증된 계좌를 마스킹해 보여주고 확인만** 받는다
    // — 계좌 값은 앱이 서버로 보내지 않고, 서버가 인증된 계좌에서 직접 스냅샷을
    // 뜬다. 인증이 안 돼 있으면 시트가 인증 흐름을 먼저 띄운다.
    //
    // 여기서 사용자가 닫으면 취소 자체를 진행하지 않는다 — 돈을 돌려줄 곳을
    // 모른 채 신청만 사라지는 상황을 만들지 않는다.
    if (paidByBankTransfer && preview.refundAmount > 0) {
      final ready = await confirmRefundAccount(
        context,
        refundAmount: preview.refundAmount,
        formatAmount: _formatFee,
      );
      if (!ready || !context.mounted) return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
      ),
    );

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('cancelApplication');
      final result = await callable.call({
        'partyId': _activeDocId,
        // 이 회차만 취소한다 — 다른 회차 신청·승인·입금 상태는 그대로다.
        'occurrenceId': ?occurrenceId,
        // 계좌는 **보내지 않는다.** 환불 요청에 박힐 계좌는 서버가 인증된
        // 환불계좌에서 직접 뜬다(refundAccountVerify.verifiedSnapshotOf).
        // 필요한데 인증돼 있지 않으면 REFUND_ACCOUNT_REQUIRED로 거절한다.
      });
      // 파티 문서(applicants)가 스트림으로 내려오기까지는 시간이 걸린다 —
      // 그 사이 버튼이 '신청 취소'로 남아 있으면 한 번 더 누르게 되고, 두 번째
      // 요청은 서버에서 '이미취소'로 거절당한다. 성공을 안 순간 화면부터 맞춘다.
      _markApplicationClosed(data);
      if (context.mounted) {
        Navigator.pop(context); // 로딩 닫기
        final resultData = Map<String, dynamic>.from(result.data as Map);
        final refundAmount = (resultData['refundAmount'] as num?)?.toInt() ?? 0;
        final msg = refundAmount > 0
            ? '신청이 취소되었어요. 환불 예정 금액 ${_formatFee(refundAmount)}'
            : '신청이 취소되었어요.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } on FirebaseFunctionsException catch (e) {
      // 이미 끝난 신청을 다시 취소하려던 경우 — 에러 원문을 그대로 보여주는
      // 대신, 화면을 그 상태로 동기화해 버튼을 감춘다(다시 누를 수 없게).
      final failure = _cancelFailure(e);
      if (failure != null && failure.syncClosed) _markApplicationClosed(data);
      if (context.mounted) {
        Navigator.pop(context); // 로딩 닫기
        // 매핑된 경우만 서버 문구를 쓴다 — 그 외에는 일반 안내만 띄우고
        // 원문(코드·메시지)은 로그로만 남긴다.
        _snack(context, failure?.message ?? '취소 처리에 실패했어요. 잠시 후 다시 시도해 주세요.');
      }
    } catch (e) {
      // 분류되지 않은 예외 — 원문에는 예외 타입·플러그인 코드가 그대로
      // 들어 있어 사용자에게 보여줄 것이 못 된다. 화면에는 안내만 띄우고
      // 내용은 로그로 남긴다.
      debugPrint('[cancelApplication] 실패: $e');
      if (context.mounted) {
        Navigator.pop(context); // 로딩 닫기
        _snack(context, '취소 처리에 실패했어요. 잠시 후 다시 시도해 주세요.');
      }
    }
  }

  /// 더 이상 취소할 수 없는 신청 상태면 그 이유, 아니면 null.
  ///
  /// 서버(cancelApplication)가 거절하는 상태와 같은 목록이다 — 승인제가 붙으며
  /// 상태가 늘었지만 **취소를 막는 상태**는 여기 적힌 것뿐이고, applied·
  /// approved처럼 살아 있는 상태(그리고 아직 모르는 새 상태)는 그대로 통과한다.
  static String? _closedApplicationMessage(String? status) {
    switch (status) {
      case 'cancelled':
        return '이미 취소된 신청이에요.';
      case 'attended':
        return '참석 처리가 끝난 신청이라 취소할 수 없어요.';
      case 'no_show':
        return '노쇼 처리된 신청이라 취소할 수 없어요.';
      case 'rejected':
        // 거절된 신청은 그 시점에 자리도 이미 반납됐다(decidePartyApplication) —
        // 여기서 다시 취소하면 같은 자리를 두 번 되돌리게 된다.
        return '거절된 신청이라 취소할 것이 없어요.';
    }
    return null;
  }

  /// 서버가 "이 신청은 이미 끝났다"고 거절한 응답을 사람이 읽는 문구로.
  ///
  /// [syncClosed]가 true면 그 신청은 더 이상 살아 있지 않다는 뜻이라, 화면도
  /// 취소됨으로 맞춰 버튼을 감춘다. '종료된파티'처럼 신청 자체는 살아 있는
  /// 거절은 문구만 바꾸고 버튼 상태는 건드리지 않는다.
  static ({String message, bool syncClosed})? _cancelFailure(
    FirebaseFunctionsException e,
  ) {
    final m = e.message ?? '';
    if (e.code == 'not-found' && m.contains('신청 내역')) {
      return (message: '취소할 신청 내역이 없어요.', syncClosed: true);
    }
    if (e.code != 'failed-precondition') return null;
    if (m.contains('이미취소')) {
      return (message: '이미 취소된 신청이에요.', syncClosed: true);
    }
    if (m.contains('이미참석')) {
      return (message: '참석 처리가 끝난 신청이라 취소할 수 없어요.', syncClosed: true);
    }
    // 거절된 신청 — 자리는 거절 시점에 이미 반납됐으므로 취소할 것이 없다
    // (functions/index.js cancelApplication). 서버 문구를 그대로 띄우지 않고
    // 화면 상태까지 맞춘다.
    if (m.contains('이미 거절된 신청')) {
      return (message: '거절된 신청이라 취소할 것이 없어요.', syncClosed: true);
    }
    if (m.contains('종료된파티')) {
      return (message: '이미 시작된 파티라 취소할 수 없어요.', syncClosed: false);
    }
    // 서버가 취소 대상을 유일하게 특정하지 못한 경우(살아 있는 회차 신청이
    // 여럿) — 신청은 **그대로 살아 있으므로** 버튼을 감추면 안 된다.
    // 이 앱은 늘 회차를 함께 보내므로 여기까지 오지 않지만, 회차를 못 보내던
    // 시절 화면에서 넘어온 요청까지 안전하게 받아준다
    // (functions/partyApplicationTargets.js의 AMBIGUOUS).
    if (m.contains('회차를 지정')) {
      return (message: '취소할 참가 날짜를 먼저 골라 주세요.', syncClosed: false);
    }
    return null;
  }

  /// 이 회차 신청은 더 이상 살아 있지 않다 — 화면을 그 상태로 맞춘다.
  void _markApplicationClosed(Map<String, dynamic> data) {
    final key = _applicationKey(data);
    if (_knownCancelledKeys.contains(key)) return;
    if (!mounted) {
      _knownCancelledKeys.add(key);
      return;
    }
    setState(() => _knownCancelledKeys.add(key));
  }

  // 닉네임을 아직 설정하지 않았으면(null/빈 값/"기본닉네임") 참여를 진행하지
  // 않고 먼저 닉네임 설정 다이얼로그를 띄운다. 저장에 성공하면 true를 돌려줘
  // 호출부가 원래 하려던 신청을 곧바로 이어서 실행할 수 있게 한다(재클릭 불필요).
  Future<bool> _requireNickname(BuildContext context) async {
    if (UserSession.hasNickname) return true;
    final saved = await showNicknameEditDialog(
      context,
      title: '닉네임을 먼저 설정해주세요',
      description: '파티에 참여하려면 닉네임이 필요해요.',
    );
    return saved && UserSession.hasNickname;
  }

  String _applyErrorMessage(Object e) {
    final msg = e.toString();
    if (msg.contains('미인증')) return '본인인증 후 신청할 수 있습니다.';
    if (msg.contains('성별제한')) return '해당 성별만 신청할 수 있습니다.';
    if (msg.contains('연령미인증')) return '출생연도 인증 후 신청할 수 있습니다.';
    if (msg.contains('연령제한')) return '이 파티는 설정된 연령 제한에 해당하지 않아 신청할 수 없습니다.';
    if (msg.contains('마감')) return '마감되었습니다';
    if (msg.contains('이미신청')) return '이미 신청하셨습니다';
    return '신청에 실패했습니다';
  }

  /// 지금 이 화면이 가리키는 **회차**의 신청자 명단.
  ///
  /// 정기 파티는 회차마다 신청이 따로다 — 문서 최상단 `applicants`는 "이 파티에
  /// 살아 있는 신청이 하나라도 있는 사람" 집합이라 '이미 신청함' 판정에 쓰면
  /// 8/15 신청 때문에 8/22까지 막힌다. 회차 칸(`occurrenceStats`)이 정본이다.
  /// 일회성·날짜별 문서 파티는 최상단 배열이 곧 그 날짜의 명단이다.
  List<String> _applicantsOf(Map<String, dynamic> data) {
    // 판정 대상은 **화면이 지금 가리키는 회차**다. 여기서만 고른 회차를
    // 쓰면, 날짜를 아직 고르지 않은 채 열어본 정기 파티에서 "보여주는 회차"와
    // "판정하는 회차"가 어긋난다(표시는 다음 회차, 판정은 회차 없음).
    final occurrenceId = _roundOccurrenceId(data);
    final stat = PartyCard.occurrenceStat(data, occurrenceId: occurrenceId);
    if (stat != null) {
      return List<String>.from(stat['applicants'] as List? ?? const []);
    }
    // 회차 칸을 이미 쓰고 있는 파티인데 이 회차 칸만 없다면, 그 회차에는 아직
    // 아무도 신청하지 않은 것이다 — 최상단 applicants로 폴백하면 안 된다.
    // 그 배열은 "이 파티에 살아 있는 신청이 하나라도 있는 사람"이라, 지난주
    // 회차 신청 때문에 이번 주 회차가 '신청 완료 · 취소 가능'으로 보이고,
    // 그대로 취소를 누르면 서버는 있지도 않은 신청(또는 회차가 붙기 전의 옛
    // uid 문서)을 보고 '이미취소'를 던진다.
    if (occurrenceId != null && data['occurrenceStats'] is Map) {
      return const [];
    }
    // 일회성 파티, 그리고 회차 칸이 생기기 전의 옛 정기 파티(신청이 uid 문서
    // 하나로만 남아 있는 파티)는 최상단 배열이 곧 그 명단이다.
    return List<String>.from(data['applicants'] as List? ?? const []);
  }

  /// 남자/여자 정원이 모두 찼는지(또는 전체 정원이 찼는지) 계산.
  /// 정기 파티는 회차 칸을 본다([_applicantsOf]와 같은 이유).
  bool _isFull(Map<String, dynamic> data) {
    final stat = PartyCard.occurrenceStat(
      data,
      occurrenceId: _roundOccurrenceId(data),
    );
    final counts = stat ?? data;
    int intOf(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;
    final mode = data['genderCapacityMode'] as String? ?? 'unlimited';
    if (mode == 'separate') {
      final maleCapacity = intOf(data, 'maleCapacity');
      final femaleCapacity = intOf(data, 'femaleCapacity');
      final currentMale = intOf(counts, 'currentMaleCount');
      final currentFemale = intOf(counts, 'currentFemaleCount');
      final maleFull = maleCapacity <= 0 || currentMale >= maleCapacity;
      final femaleFull = femaleCapacity <= 0 || currentFemale >= femaleCapacity;
      return maleFull && femaleFull;
    }
    final current = intOf(counts, 'currentParticipants');
    final max = intOf(data, 'maxParticipants') != 0
        ? intOf(data, 'maxParticipants')
        : intOf(data, 'maxCapacity');
    return max > 0 && current >= max;
  }

  // 남녀 참가비가 다르면 본인인증된 본인 성별 참가비만, 미인증이면 안내
  // 문구만 보여준다(남녀 가격이 같아도 '참가비' 한 줄로 통일해 표시).
  // 아이콘은 호출부(요약 카드의 _StatTile)가 그리므로 여기서는 값(메인)과
  // 얼리버드 할인율 같은 보조 정보를 한 쌍(record)으로 돌려준다.
  ({Widget main, Widget? sub}) _feeTileContent(Map<String, dynamic> data) {
    // 참가비는 공통 모델로 읽는다 — pricingType이 있는 새 문서와 maleFee/
    // femaleFee/fee만 있는 기존 문서를 같은 방식으로 다룬다.
    final pricing = PartyPricing.fromMap(data);
    // 얼리버드 판정 기준은 **화면이 지금 가리키는 회차**다([_roundBaseDate]).
    // 회차를 안 넘기면 "다음 회차" 기준이 되어, 8/25를 골라놨는데 8/21 회차의
    // 끝난 얼리버드로 판정해 정상가가 뜬다(서버는 8/25로 계산해 할인가).
    final occurrenceStart = _roundBaseDate(data);
    final earlyBirdOn = EarlyBird.isActive(
      data,
      occurrenceStart: occurrenceStart,
    );
    // 얼리버드 문구는 핑크 알약 배지 안에 넣고, 폭이 좁은 칸에서도 항상
    // 한 줄로 보이도록 FittedBox로 필요하면 살짝 축소한다.
    final earlyBirdSub = earlyBirdOn
        ? FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: PartyChuColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '얼리버드 ${EarlyBird.discountPercent(data)}%',
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          )
        : null;

    // 참가비는 로그인 사용자에게만 공개되는 정보다 — 무료 파티(표시할 참가비
    // 자체가 없는 경우)는 기존처럼 아무것도 보여주지 않되, 참가비가 있는
    // 파티는 본인인증 여부와 무관하게 로그인 전이면 잠금 안내만 보여준다.
    final hasFeeData = !pricing.isFree;
    if (hasFeeData && !UserSession.isLoggedIn) {
      return (
        main: const Text(
          '로그인 후 확인',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: PartyChuColors.muted,
          ),
        ),
        sub: null,
      );
    }

    if (pricing.isFree) {
      return (
        main: const Text(
          '무료',
          textAlign: TextAlign.center,
          style: _tileValueStyle,
        ),
        sub: null,
      );
    }

    // 남녀 금액이 다른 파티는 본인 성별이 확인돼야 낼 금액이 정해진다.
    if (pricing.hasGenderedPrice &&
        (!UserSession.identityVerified || UserSession.gender.isEmpty)) {
      return (
        main: const Text(
          '본인인증 후 확인',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: PartyChuColors.muted,
          ),
        ),
        // 인증 전에도 범위는 알려준다(예: 25,000~35,000원).
        sub: Text(
          '${_formatFee(pricing.displayPrice)}~${_formatFee(pricing.maxPrice)}',
          textAlign: TextAlign.center,
          style: _tileSubStyle,
        ),
      );
    }

    final ownFee = pricing.priceFor(
      UserSession.identityVerified ? UserSession.gender : null,
    );
    return (
      main: _priceRich(
        data,
        ownFee,
        earlyBirdOn,
        occurrenceStart: occurrenceStart,
      ),
      sub: earlyBirdSub,
    );
  }

  // 참가비가 있는 파티만 환불 규정을 보여준다 — 무료 파티는 취소해도 환불
  // 자체가 없으므로(참가 취소만 처리) 규정을 안내할 필요가 없다.
  Widget _refundPolicyInfo(Map<String, dynamic> data) {
    if (PartyPricing.fromMap(data).isFree) return const SizedBox.shrink();

    final tiers = RefundTier.listFromDynamic(data['refundPolicy']);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: PartyChuCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.assignment_return_outlined,
                  size: 20,
                  color: Color(0xFFFF8A80),
                ),
                const SizedBox(width: 8),
                _sectionTitle('환불 규정'),
              ],
            ),
            const SizedBox(height: 12),
            RefundPolicyView(tiers: tiers),
          ],
        ),
      ),
    );
  }

  /// 요약 카드의 참가비 한 줄 값 — 얼리버드 중이면 할인 적용가를, 아니면
  /// 정가를 굵게 표시한다. 할인율/원가 대비 정보는 옆의 보조 줄
  /// ("얼리버드 10%")이 맡으므로 여기서는 한 줄에 들어가는 최종 금액만
  /// 보여준다(취소선 표기는 카드 폭이 좁아지며 줄바꿈을 유발해 제외).
  Widget _priceRich(
    Map<String, dynamic> data,
    int fee,
    bool earlyBirdOn, {
    DateTime? occurrenceStart,
  }) {
    final displayFee = earlyBirdOn && fee > 0
        ? EarlyBird.effectivePrice(fee, data, occurrenceStart: occurrenceStart)
        : fee;
    return Text(
      _formatFee(displayFee),
      textAlign: TextAlign.center,
      style: _tileValueStyle,
    );
  }

  /// `places` 문서에 연결된 파티(`linkedPlaceId` 있음)에서만 렌더링되는
  /// "장소 정보 함께보기" 카드 — 연결된 `places/{id}` 문서와 그 룸을 조회해
  /// 유형/체크인·체크아웃/대표가격을 보여주고, 장소 상세로 이동하는 버튼을
  /// 제공한다. 필드가 없는(일반) 파티는 아무것도 그리지 않는다.
  ///
  /// **문구는 공간 유형에 따라 갈린다** — `places`는 숙박(호텔·펜션)과
  /// 대관(파티룸·스튜디오)을 같은 컬렉션에 담아서, 무조건 '숙박'이라고 쓰면
  /// 대관 공간에도 숙박이라는 말이 붙는다. 판정은 [placeSupportsStay] 한 곳에
  /// 있다(룸의 예약 방식이 정본).
  /// 연결된 장소 조회 결과를 장소 id별로 들고 있는다 — [FutureBuilder]에
  /// 조회를 그대로 넘기면 리빌드마다 다시 읽는다(문서 1건 + 룸 목록).
  final Map<String, Future<_LinkedPlaceInfo?>> _linkedPlaceCache = {};

  /// 장소 문서와 그 룸을 함께 읽는다. 룸이 필요한 이유는 **예약 방식이 룸에
  /// 저장**되기 때문이다 — 숙박인지 대관인지는 룸을 봐야 알 수 있다.
  Future<_LinkedPlaceInfo?> _loadLinkedPlace(String placeId) {
    return _linkedPlaceCache.putIfAbsent(placeId, () async {
      final db = FirebaseFirestore.instance;
      final placeSnap = await db.collection('places').doc(placeId).get();
      final place = placeSnap.data();
      if (place == null) return null;
      // 룸을 못 읽어도 카드 자체는 보여준다 — 그때는 장소 문서만으로 유형을
      // 판단한다(placeSupportsStay가 그 경로를 갖고 있다).
      var rooms = const <Map<String, dynamic>>[];
      try {
        final roomsSnap = await db
            .collection('placeRooms')
            .where('placeId', isEqualTo: placeId)
            .get();
        rooms = roomsSnap.docs
            .map((d) => d.data())
            .where((r) => r['isActive'] != false)
            .toList();
      } catch (_) {
        // 무시 — 아래 판정이 장소 문서만으로도 돌아간다.
      }
      return _LinkedPlaceInfo(place: place, rooms: rooms);
    });
  }

  Widget _linkedPlaceInfo(Map<String, dynamic> data) {
    final linkedPlaceId = data['linkedPlaceId'] as String?;
    if (linkedPlaceId == null || linkedPlaceId.isEmpty) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<_LinkedPlaceInfo?>(
      future: _loadLinkedPlace(linkedPlaceId),
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        if (loaded == null) return const SizedBox.shrink();
        final placeData = loaded.place;
        // 숙박을 받는 곳이면 '숙박', 대관·시간제 공간이면 '공간대여'.
        final isStay = placeSupportsStay(placeData, rooms: loaded.rooms);
        final noun = isStay ? '숙박' : '공간대여';
        final checkIn = placeData['accommodationCheckInTime'] as String?;
        final checkOut = placeData['accommodationCheckOutTime'] as String?;
        final price = (placeData['pricePerHour'] as num?)?.toInt() ?? 0;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: PartyChuCard(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        // 침대 아이콘은 숙박에만 — 대관 공간에는 방을 빌린다는
                        // 뜻이 되어버린다.
                        isStay
                            ? Icons.hotel_outlined
                            : Icons.meeting_room_outlined,
                        size: 16,
                        color: const Color(0xFF7C5CBF),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$noun 정보 함께보기',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7C5CBF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (placeData['type'] != null)
                    Text(
                      '$noun 유형 : ${placeData['type']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  // 체크인·체크아웃은 숙박에만 입력받는 값이라 유형 문구가
                  // 따로 필요 없다(대관 공간에는 애초에 값이 없다).
                  if (checkIn != null && checkOut != null)
                    Text(
                      '체크인 $checkIn · 체크아웃 $checkOut',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  if (price > 0)
                    Text(
                      // 값의 출처는 `pricePerHour`라 대관에서는 시간당 요금이다.
                      isStay
                          ? '숙박 가격 ${formatPrice(price)}~'
                          : '대관 가격 시간당 ${formatPrice(price)}~',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      webFramedRoute(
                        (_) => PlaceDetailScreen(
                          placeId: linkedPlaceId,
                          data: placeData,
                        ),
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: const Color(0xFF7C5CBF),
                    ),
                    child: Text(
                      '$noun 상세 보기 →',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (placeData['packageBookingEnabled'] == true) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          webFramedRoute(
                            (_) => PackageBookingScreen(
                              placeId: linkedPlaceId,
                              // 패키지 예약도 고른 날짜의 문서를 대상으로 한다.
                              partyId: _activeDocId,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.card_giftcard, size: 18),
                        label: const Text('📦 패키지로 예약하기'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C5CBF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 플레이스(`events`)와 연결된 파티에서만 렌더링되는 "이 파티가 열리는
  /// 플레이스" 카드 — "플레이스+파티" 콤보로 한 번에 등록된 파티와, 나중에
  /// 호스트가 기존 파티를 연결한 경우가 모두 같은 `linkedEventId`를 쓴다.
  ///
  /// 특징 태그/위치는 **연결 시점 스냅샷**(`placeSnapshot`)이 있으면 그 값을
  /// 먼저 쓴다 — 플레이스가 나중에 수정돼도 이미 신청자가 있는 파티의 장소
  /// 정보가 갑자기 바뀌지 않게 하기 위해서다(스냅샷이 없는 예전 콤보 문서는
  /// 지금처럼 연결된 문서를 그대로 읽는다). 이동 버튼은 항상 최신 플레이스
  /// 상세로 간다.
  ///
  /// `linkedPlaceId`(숙박+파티 콤보, `places` 컬렉션 하드코딩)와는 다른
  /// 필드/컬렉션이라 별도 위젯으로 분리한다 — 필드가 없는(일반) 파티는
  /// 아무것도 그리지 않는다.
  Widget _linkedEventInfo(Map<String, dynamic> data) {
    final linkedEventId = data['linkedEventId'] as String?;
    if (linkedEventId == null || linkedEventId.isEmpty) {
      return const SizedBox.shrink();
    }
    final snapshotRaw = data['placeSnapshot'];
    final placeSnapshot = snapshotRaw is Map
        ? Map<String, dynamic>.from(snapshotRaw)
        : const <String, dynamic>{};
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('events')
          .doc(linkedEventId)
          .get(),
      builder: (context, snapshot) {
        final eventData = snapshot.data?.data();
        // 스냅샷이 있으면 플레이스 문서를 아직 못 읽었어도 카드를 그린다.
        if (eventData == null && placeSnapshot.isEmpty) {
          return const SizedBox.shrink();
        }
        final source = placeSnapshot.isNotEmpty ? placeSnapshot : eventData!;
        final placeName = source['name'] as String? ?? '';
        final themeTags =
            (source['themeTags'] as List?)?.cast<String>() ?? const [];
        final location = source['location'] as String? ?? '';
        return Container(
          // 상세의 다른 섹션 카드(환불 규정 · '숙박/공간대여 정보 함께보기')와
          // **같은 폭 규칙**을 쓴다. 이 카드들이 놓이는 바깥 Column은
          // crossAxisAlignment.start라 자식에게 느슨한 폭 제약을 준다 — 폭을
          // 스스로 잡지 않으면 내용 크기(제목 Row가 mainAxisSize.min)에 맞춰
          // 짧게 끝나 옆 카드들과 좌우 끝이 어긋난다. 좌우 여백은 페이지의
          // Padding(all 20)이 이미 갖고 있으므로 여기서 따로 두지 않는다.
          width: double.infinity,
          // 위아래 섹션과의 간격은 이 카드가 스스로 갖는다 — 호출부에 두면
          // 연결된 플레이스가 없을 때도 빈 간격이 남아, 태그 → 위치가 예전처럼
          // 붙지 않는다.
          margin: const EdgeInsets.only(top: 24, bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0F5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFD6E4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wine_bar_outlined,
                    size: 16,
                    color: Color(0xFFFF6FA0),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '이 파티가 열리는 플레이스',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6FA0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (placeName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    placeName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
              if (themeTags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in themeTags)
                      Text(
                        '${ListingConstants.placeThemeTagEmojis[tag] ?? ''} '
                        '${ListingConstants.placeThemeTagLabel(tag)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                  ],
                ),
              if (location.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '위치 : $location',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              const SizedBox(height: 8),
              // 이동은 항상 최신 플레이스 문서로 — 아직 못 읽었거나 삭제된
              // 플레이스면 버튼을 비활성화한다(스냅샷만으로 상세를 열어
              // 사라진 플레이스를 살아 있는 것처럼 보여주지 않는다).
              TextButton(
                onPressed: eventData == null
                    ? null
                    : () => Navigator.push(
                        context,
                        webFramedRoute(
                          (_) => EventDetailScreen(
                            eventId: linkedEventId,
                            eventData: eventData,
                          ),
                        ),
                      ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: const Color(0xFFFF6FA0),
                ),
                child: const Text(
                  '플레이스 상세 보기 →',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatFee(int fee) => formatPrice(fee);

  // 요약 카드 4칸 공통 타이포 — 값(Value)이 가장 먼저 눈에 들어오도록
  // 라벨보다 훨씬 크고 굵게, 보조 설명은 라벨보다 살짝 크되 값보다는
  // 작게 둔다(모두 가운데 정렬).
  static const _tileValueStyle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: Colors.black,
  );
  static const _tileSubStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Color(0xFF8A8A8A),
  );

  static const _weekdayKo = ['월', '화', '수', '목', '금', '토', '일'];

  /// 날짜 값(main)은 "MM.DD (요일)"로 직접 포맷한다(예: "09.28 (일)") —
  /// partyDateTime을 실제로 파싱해 요일을 계산하므로 항상 정확하다.
  /// 보조(시간) 줄은 기존 그대로 data['date'] 문자열의 공백 이후 부분을
  /// 그대로 사용한다(시간 포맷 로직은 건드리지 않음).
  ({String main, String? sub}) _splitDate(Map<String, dynamic> data) {
    final raw = (data['date'] as String?)?.trim() ?? '';
    final spaceIdx = raw.indexOf(' ');
    // 정기 파티의 date 문자열은 첫 회차 시각이라 시간이 지나면 어긋난다 —
    // 보조 줄(시간)은 계산된 다음 회차에서 직접 뽑는다.
    final sub = PartySchedule.isRecurring(data)
        ? PartyCard.formatTimeOnly(data)
        : (spaceIdx > 0 ? raw.substring(spaceIdx + 1).trim() : null);

    final dt = PartyCard.parsePartyDateTime(data);
    if (dt == null) {
      // 파싱 실패 시에만 기존 문자열 첫 토큰으로 안전하게 대체.
      if (raw.isEmpty) return (main: '-', sub: null);
      return (main: spaceIdx > 0 ? raw.substring(0, spaceIdx) : raw, sub: sub);
    }
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final wd = _weekdayKo[dt.weekday - 1];
    return (main: '$mm.$dd($wd)', sub: sub);
  }

  /// 참여 인원 요약 카드 값: unlimited면 메인에 "X/Y명"을, 보조 줄에는
  /// 성별 제한(genderLimit) 여부에 따라 "남녀무관"/"남자만"/"여자만"을
  /// 보여준다. separate면 메인에 남녀 합산 "X/Y명"을, 보조 줄에
  /// "남 A / 여 B"(현재 신청자 수)를 보여준다. 아이콘은 호출부의
  /// _StatTile이 그린다.
  ///
  /// **현재 모집된 인원은 로그인한 사용자에게만 보여준다** — 참가비·모집
  /// 상태와 같은 규칙이다(아래 [PartyCapacityMeter]도 같은 기준). 대신 정원
  /// 자체는 파티를 고르는 데 필요한 일반 정보라 그대로 남기고, 칸 라벨만
  /// '참여 인원' → '모집 정원'으로 바꿔 무엇을 보고 있는지 분명히 한다.
  /// 잔여 인원을 역산할 수 있는 값(현재 인원, 남/여 현재 수, 캐시 문자열
  /// `people`("2/40명"))은 전부 빠진다.
  ({Widget main, Widget? sub, String label}) _peopleTileContent(
    Map<String, dynamic> data, {
    required bool isHost,
  }) {
    const mainStyle = _tileValueStyle;
    const subStyle = _tileSubStyle;
    final loggedOut = !UserSession.isLoggedIn;
    // 순서가 중요하다: 비로그인 정책이 **먼저**(현재 인원 자체가 안 보인다),
    // 그 관문을 통과한 로그인 게스트에게만 이 설정이 걸린다. 호스트는 자기
    // 파티라 언제나 본다([ParticipantGenderVisibility]).
    final revealRatio = ParticipantGenderVisibility.revealsTo(
      data,
      isHost: isHost,
    );
    final mode = data['genderCapacityMode'] as String? ?? 'unlimited';
    if (mode == 'separate') {
      final maleCapacity = (data['maleCapacity'] as int?) ?? 0;
      final femaleCapacity = (data['femaleCapacity'] as int?) ?? 0;
      final currentMale = (data['currentMaleCount'] as int?) ?? 0;
      final currentFemale = (data['currentFemaleCount'] as int?) ?? 0;
      final totalMax = maleCapacity + femaleCapacity;
      final totalCurrent = currentMale + currentFemale;
      if (loggedOut) {
        // 보조 줄에는 '정원'이라고 못 박은 남녀 정원을 쓴다 — 같은 자리에
        // 같은 모양으로 현재 인원이 뜨던 자리라, 라벨 없이 숫자만 두면
        // 로그인 전후로 뜻이 뒤바뀐 것처럼 읽힌다.
        return (
          label: '모집 정원',
          main: Text(
            totalMax > 0 ? '$totalMax명' : '-',
            textAlign: TextAlign.center,
            style: mainStyle,
          ),
          sub: totalMax > 0
              ? Text(
                  '정원 남 $maleCapacity/여 $femaleCapacity',
                  textAlign: TextAlign.center,
                  style: subStyle,
                )
              : null,
        );
      }
      return (
        label: '참여 인원',
        // 총 참가 인원과 정원은 **어느 설정에서도 그대로 보인다** — 이 설정이
        // 감추는 것은 남/여 내역뿐이다.
        main: Text(
          totalMax > 0 ? '$totalCurrent/$totalMax명' : '$totalCurrent명',
          textAlign: TextAlign.center,
          style: mainStyle,
        ),
        // 숨김이면 보조 줄을 비우는 대신 호스트가 정한 **모집 조건**(남녀
        // 정원)을 적는다 — 정원은 "누가 왔는가"가 아니라 "어떤 파티인가"라
        // 감출 대상이 아니고, 총 인원 하나만으로는 남녀 내역을 되짚을 수 없다.
        sub: Text(
          revealRatio
              ? '남 $currentMale / 여 $currentFemale'
              : '정원 남 $maleCapacity/여 $femaleCapacity',
          textAlign: TextAlign.center,
          style: subStyle,
        ),
      );
    }
    final current = (data['currentParticipants'] as int?) ?? 0;
    final max =
        (data['maxParticipants'] as int?) ?? (data['maxCapacity'] as int? ?? 0);
    final genderLimit = data['genderLimit'] as String? ?? 'all';
    final genderLimitLabel = switch (genderLimit) {
      'male' => '남자만',
      'female' => '여자만',
      _ => '남녀무관',
    };
    if (loggedOut) {
      // 정원이 없는 파티는 보여줄 정원 자체가 없다 — 예전 폴백이던
      // `people`은 "2/40명"으로 저장된 캐시 문자열이라 현재 인원이 그대로
      // 드러나므로 로그인 전에는 쓰지 않는다. 성별 제한은 인원과 무관한
      // 조건이라 그대로 남긴다.
      return (
        label: '모집 정원',
        main: Text(
          max > 0 ? '$max명' : '-',
          textAlign: TextAlign.center,
          style: mainStyle,
        ),
        sub: Text(
          genderLimitLabel,
          textAlign: TextAlign.center,
          style: subStyle,
        ),
      );
    }
    return (
      label: '참여 인원',
      main: Text(
        max > 0 ? '$current/$max명' : (data['people'] as String? ?? '-'),
        textAlign: TextAlign.center,
        style: mainStyle,
      ),
      sub: Text(genderLimitLabel, textAlign: TextAlign.center, style: subStyle),
    );
  }

  /// "한눈에 보기" 카드의 4칸(날짜/장소/참여 인원/참가비) — 실제 데이터
  /// 길이에 맞춰 줄바꿈되도록 maxLines/ellipsis를 강제하지 않는다(짧은
  /// 값은 1줄, 긴 주소·날짜는 2줄 이상으로 자연스럽게 늘어남). 4칸은
  /// 항상 동일한 폭(Expanded, flex 균등)으로 나란히 배치한다.
  /// IntrinsicHeight가 그 중 가장 긴 칸 높이에 맞춰 전체 행(과 세로
  /// 구분선)을 자동으로 늘려준다 — 고정 height가 없으므로 카드 높이도
  /// 내용에 맞춰 늘어난다.
  Widget _summaryStatsRow(
    Map<String, dynamic> data,
    String address, {
    required bool isHost,
  }) {
    final peopleContent = _peopleTileContent(data, isHost: isHost);
    final feeContent = _feeTileContent(data);
    final dateParts = _splitDate(data);
    // 정기 파티는 "특정 날짜"가 없다 — 좁은 칸에는 반복 규칙을 최대한 짧게
    // 요약하고(매일 / 평일 / 목~일 …), 전체 시간표는 아래 '정기 일정' 줄이
    // 맡는다. 요일마다 시작 시각이 다르면 여기서는 대표 문구만 보여준다.
    final recurring = PartySchedule.compactSummary(data);
    final isRecurring = recurring.days.isNotEmpty;
    final locationLines = RegionData.partyLocationLines(data);
    const divider = VerticalDivider(
      width: 14,
      thickness: 1,
      color: PartyChuColors.border,
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatTile(
              icon: isRecurring
                  ? Icons.repeat_rounded
                  : Icons.calendar_month_rounded,
              color: const Color(0xFFFF6FAF),
              label: isRecurring ? '일정' : '날짜',
              // 일회성: "MM.DD(요일)"이 좁은 칸에서도 항상 한 줄로 다 보이도록
              // FittedBox로 필요한 만큼만 폰트를 줄인다(늘리지는 않음).
              // 정기: 요약 문구가 길어질 수 있어 최대 2줄까지 접고 말줄임한다.
              value: isRecurring
                  ? Text(
                      recurring.days,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(dateParts.main, maxLines: 1, softWrap: false),
                    ),
              sub: isRecurring
                  ? Text(
                      recurring.time,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _tileSubStyle,
                    )
                  : dateParts.sub == null
                  ? null
                  : Text(
                      dateParts.sub!,
                      textAlign: TextAlign.center,
                      style: _tileSubStyle,
                    ),
            ),
          ),
          divider,
          Expanded(
            child: _StatTile(
              icon: Icons.location_on_rounded,
              color: const Color(0xFFB06CFF),
              label: '장소',
              // 동/시·구 이름도 한 줄씩만 — 각각 FittedBox로 한 줄 안에
              // 맞춘다.
              value: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(locationLines.dong, maxLines: 1, softWrap: false),
              ),
              sub: locationLines.cityDistrict.isEmpty
                  ? null
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        locationLines.cityDistrict,
                        maxLines: 1,
                        softWrap: false,
                        style: _tileSubStyle,
                      ),
                    ),
            ),
          ),
          divider,
          Expanded(
            child: _StatTile(
              icon: Icons.groups_2_rounded,
              color: const Color(0xFF4ECBA7),
              // 로그인 전에는 '모집 정원'이다 — 현재 인원을 감추므로 라벨도
              // 실제로 보여주는 값에 맞춘다([_peopleTileContent]).
              label: peopleContent.label,
              value: peopleContent.main,
              sub: peopleContent.sub,
            ),
          ),
          divider,
          Expanded(
            child: _StatTile(
              icon: Icons.sell_rounded,
              color: const Color(0xFFFF5FA2),
              label: '참가비',
              value: feeContent.main,
              sub: feeContent.sub,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 파티추 테마(핑크+화이트)에 맞춰 차가운 회색 톤 대신 은은한 핑크
      // 배경톤으로 통일한다.
      backgroundColor: const Color(0xFFFFF7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF5F8),
        elevation: 0,
        foregroundColor: const Color(0xFF3A2E39),
        centerTitle: true,
        actions: [
          // 신고·차단 — 내 파티에서는 위젯이 스스로 아무것도 그리지 않는다.
          SafetyMenuButton(
            targetType: ReportTargetType.party,
            targetId: _activeDocId,
            targetUserId: _reportHostId,
            targetTitle: _reportTitle,
          ),
        ],
        title: const Text(
          '파티 상세',
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
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('parties')
            // 고른 날짜의 문서를 구독한다 — 날짜를 바꾸면 정원·마감·차수·
            // 신청 여부가 통째로 그 문서 기준으로 다시 그려진다.
            .doc(_activeDocId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) {
            return const Center(child: Text('데이터를 찾을 수 없습니다'));
          }

          final userId = UserSession.userId;
          final currentUid = FirebaseAuth.instance.currentUser?.uid ?? userId;
          // 정기 파티는 신청도 정원도 **회차 단위**다 — 8/15에 신청했다고
          // 8/22가 '신청 완료'로 막히면 안 된다. 아직 회차를 고르지 않았으면
          // 화면이 가리키는 회차(다음 회차)를 기준으로 본다.
          final applicants = _applicantsOf(data);
          final isFull = _isFull(data);
          // 취소가 끝난 회차는 파티 문서가 아직 그 사실을 말하지 못해도
          // 신청 상태로 보지 않는다 — 그래야 '신청 취소' 버튼이 곧바로 사라져
          // 이미 취소된 신청을 다시 취소하는 요청이 나가지 않는다.
          final alreadyApplied =
              userId.isNotEmpty &&
              applicants.contains(userId) &&
              !_knownCancelledKeys.contains(_applicationKey(data));

          // 신청이 파티 문서에 반영돼 이 화면까지 내려온 순간 — 마지막 구간.
          // 서버 응답 이후 여기까지 걸리는 시간이 Firestore 전파 지연이고,
          // 그 다음 프레임까지가 실제 UI 갱신이다.
          if (_awaitingApplyReflection && alreadyApplied) {
            _awaitingApplyReflection = false;
            _applyLog('Firestore 반영(applicants)');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _applyLog('UI 갱신 완료(버튼 상태)');
              _applyWatch = null;
              _applyReleaseTimer?.cancel();
              // 여기서 비로소 로딩을 푼다 — 버튼은 곧바로 '신청 완료'가 된다
              // (alreadyApplied가 이미 true라 되돌아가는 깜빡임이 없다).
              if (mounted && _applying) setState(() => _applying = false);
            });
          }
          final isHost =
              currentUid.isNotEmpty &&
              (data['hostUid'] == currentUid || data['hostId'] == currentUid);
          // 상단 바(신고·차단)는 이 StreamBuilder 밖에 있어 파티 문서를 볼 수
          // 없다 — 작성자와 제목만 화면 상태로 옮겨 담는다. 값이 실제로 달라진
          // 첫 프레임에만 setState한다(빌드 중 setState 금지).
          final hostIdForReport =
              (data['hostId'] ?? data['hostUid']) as String? ?? '';
          final titleForReport = data['title'] as String? ?? '';
          if (hostIdForReport != _reportHostId ||
              titleForReport != _reportTitle) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _reportHostId = hostIdForReport;
                _reportTitle = titleForReport;
              });
            });
          }
          // 문서의 `isRecurring`은 **매주 반복이 아니라 "재등록 가능"** 을
          // 뜻하는 옛 이름이다 — 등록 화면이 일회성 파티에도 true를 박아 넣는다.
          // 반복 여부는 언제나 PartySchedule.isRecurring(=scheduleType)으로
          // 판정한다(아래 isRecurringParty). 이름 때문에 두 개념이 섞이지
          // 않도록 여기서 뜻대로 고쳐 받는다.
          final canReregister = data['isRecurring'] as bool? ?? false;
          final lastUsedAt = data['lastUsedAt'] as Timestamp?;
          final reregisterExpired =
              lastUsedAt != null &&
              lastUsedAt.toDate().isBefore(
                DateTime.now().subtract(const Duration(days: 30)),
              );
          // 로그인 전에는 성별/연령을 알 수 없어 checkPartyEligibility가
          // "연령 제한"/"성별 제한"으로 잘못 판정한다(null을 조건 미충족으로
          // 취급하기 때문) — 로그인하지 않은 상태에서는 이 결과를 신청 버튼
          // 비활성화/문구에 쓰지 않고, 대신 로그인부터 유도한다.
          final loggedOut = userId.isEmpty;
          final eligibility = checkPartyEligibility(
            data,
            UserSession.gender,
            UserSession.birthYear,
          );

          final mainImageUrl = data['mainImageUrl'] as String?;
          final imageUrlsList = List<String>.from(
            data['imageUrls'] as List? ?? [],
          );
          final imagesList = List<String>.from(data['images'] as List? ?? []);
          // 갤러리는 images 우선, 없으면 imageUrls 사용
          final images = imagesList.isNotEmpty ? imagesList : imageUrlsList;
          debugPrint(
            '[Detail] "${data['title']}": mainImageUrl=$mainImageUrl, imageUrls=$imageUrlsList, images=$imagesList',
          );
          final videoUrl = data['videoUrl'] as String?;
          final videoThumbnailUrl = data['videoThumbnailUrl'] as String?;

          // 대표 미디어 — 등록/수정 시 이미 images 배열의 맨 앞(index 0)으로
          // 재정렬해 저장하므로 갤러리는 항상 index 0부터 연다. 재정렬 전에
          // 저장된 과거 데이터도 방어적으로 여기서 한 번 더 맞춰준다(대표
          // 사진이 index 0이 아니면 이 화면에서만 맨 앞으로 옮기고, Firestore에
          // 다시 쓰지는 않는다).
          final cover = getPartyCoverMedia(data, tag: 'DetailHero');
          final videoIsCover = cover?.isVideo ?? false;
          if (!videoIsCover && cover?.imageUrl != null) {
            final idx = images.indexOf(cover!.imageUrl!);
            if (idx > 0) {
              images
                ..removeAt(idx)
                ..insert(0, cover.imageUrl!);
            }
          }
          const galleryInitialPage = 0;

          final lat = (data['latitude'] as num?)?.toDouble() ?? 0.0;
          final lng = (data['longitude'] as num?)?.toDouble() ?? 0.0;
          final hasLocation = lat != 0.0 && lng != 0.0;

          final roadAddress = data['roadAddress'] as String? ?? '';
          final address = roadAddress.isNotEmpty
              ? roadAddress
              : (data['address'] as String?)?.isNotEmpty == true
              ? data['address'] as String
              : data['location'] as String? ?? '';
          final detailAddress = data['detailAddress'] as String? ?? '';
          // 이 화면에서 주소를 보여주는 모든 자리(상세 주소 행 · 지도 아래
          // 캡션)와 복사·길찾기가 전부 이 한 값을 쓴다 — 상세주소가 이미
          // 주소에 들어 있으면 중복으로 붙지 않는다.
          final fullAddress = PlaceAddressRow.joinAddress(
            RegionData.shortenRegionPrefix(address),
            detailAddress,
          );

          // 모집 상태는 **회차 기준**이다 — 정기 파티는 호스트가 회차마다 따로
          // 닫을 수 있다([PartyOccurrenceRecruit]). 아직 회차를 고르지 않았으면
          // 화면이 지금 가리키는 회차(다음 회차)의 값이고, 회차 칸이 없는
          // 파티는 예전 그대로 문서의 `recruitStatus`다.
          //
          // 어느 회차를 말하는지는 차수 인원이 이미 쓰는 값 하나
          // ([_roundOccurrenceId])를 그대로 쓴다 — 한 화면이 항목마다 다른
          // 날짜를 말하지 않게.
          final statusOccurrenceId = _roundOccurrenceId(data);
          final recruitStatus = PartyOccurrenceRecruit.statusOf(
            data,
            occurrenceId: statusOccurrenceId,
          );
          // 오픈예정(사전등록) 파티 — 신청·예약·결제를 일절 받지 않고 오픈
          // 알림만 받는다. 서버(partyCapacity.js)도 같은 판정으로 막으므로
          // 여기 UI는 "서버가 거절할 일을 애초에 못 누르게" 하는 역할이다.
          final isPreopen = PartyOpenState.isPreopen(data);
          final isDateTbd = PartyOpenState.isDateTbd(data);
          // 아래 '정기 일정' 영역은 상단 좁은 칸과 달리 반복 규칙 전체를
          // 보여준다 — 시간대가 다른 요일은 그룹별로 한 줄씩. 개별 날짜는
          // 여기서도 풀지 않는다([PartyRecurringSchedule.detailLines]).
          final recurringLines = PartySchedule.detailLines(data);
          final recurringLabel = recurringLines.join('\n');
          final isRecurringParty = PartySchedule.isRecurring(data);
          final now = DateTime.now();

          // 얼리버드 — 예전에는 참가비 아래 별도 카드였고, 지금은 이 정보 카드의
          // 맨 아래 행이다. **보이는 조건도 문구도 그때 그대로**다:
          //   · 지금 할인 중이면            → '얼리버드 D-2' / '오늘 23:59 마감'
          //   · 이번 회차는 끝났지만 뒤 회차가 남았으면 → 'N월 N일(요일) 회차부터 할인'
          //   · 그 외(아예 없음/완전히 끝남) → 행 자체를 그리지 않는다
          // 판정 대상 회차는 참가비 타일과 같은 [_roundBaseDate]이고, 계산은
          // 전부 [EarlyBird]가 그대로 한다(여기서 다시 판정하지 않는다).
          final earlyBirdBase = _roundBaseDate(data);
          final earlyBirdVisible =
              EarlyBird.isActive(data, occurrenceStart: earlyBirdBase) ||
              EarlyBird.firstDiscountedOccurrenceStart(data) != null;
          final earlyBirdRowText = earlyBirdVisible
              ? earlyBirdInfoRowText(
                  EarlyBird.statusLabel(data, occurrenceStart: earlyBirdBase),
                )
              : '';

          // 정기 파티는 회차마다 마감이 새로 열린다 — 사용자가 회차를 골랐으면
          // **그 회차**의 시각을, 아직 안 골랐으면 예전처럼 "다음 회차"의 시각을
          // 쓴다(일회성 파티는 저장된 값 그대로라 기존과 동일).
          final recruitDeadlineAt =
              _applyOccurrence.selected?.deadline ??
              PartyCard.recruitDeadlineAt(data);
          final deadlinePassed =
              recruitDeadlineAt != null && recruitDeadlineAt.isBefore(now);
          // 모집 시작 시각이 아직 오지 않았으면 신청 버튼도 열지 않는다 —
          // 서버(partyCapacity.js)가 같은 판정을 하므로 UI만 열어두면 눌렀을
          // 때 오류가 난다.
          final recruitOpenAt =
              _applyOccurrence.selected?.recruitOpenAt ??
              PartyCard.recruitOpenAt(data);
          final recruitNotStarted =
              recruitOpenAt != null && now.isBefore(recruitOpenAt);

          // ── "아직 날짜를 안 골랐을 뿐"인 상태는 신청을 막지 않는다 ──────────
          //
          // 위 판정들은 **지금 화면이 가리키는 날짜**(정기 파티는 다음 회차,
          // 여러 날짜 게시글은 목록 대표 문서)의 상태다. 예전에는 그 상태가
          // 그대로 신청 버튼에 걸려서, 오늘 회차만 마감됐을 뿐 다음 주 회차는
          // 열려 있는 정기 파티나 첫 날짜만 마감된 여러 날짜 게시글에서 버튼이
          // '모집마감'으로 죽었다 — 정작 사용자에게는 열려 있는 날짜를 고를
          // 방법이 없었다(버튼이 유일한 진입점이므로).
          //
          // 그래서 "신청할 수 있는 날짜가 하나라도 남아 있는데 아직 고르지
          // 않았다면" 버튼을 열어두고, 어느 날짜인지는 신청 플로우 안에서
          // 고르게 한다([_startApplyFlow]). 고른 날짜 기준의 마감·정원은 그
          // 문서로 다시 판정하고, 최종 검증은 예전 그대로 서버가 한다.
          //
          // 정보 표시(상태 배지·'모집 마감' 행·'참가 날짜' 행)는 건드리지
          // 않는다 — 화면이 지금 보여주는 날짜의 사실 그대로여야 한다.

          // **다른 날짜 문서**가 열려 있어서 아직 고르지 않았을 뿐인 상태.
          // 정기 파티의 회차와 달리 날짜 슬롯은 문서가 따로라, 이 문서가
          // 닫혀 있어도 다른 날짜에는 신청할 수 있다.
          final hasUnpickedOpenDateDoc =
              !_scheduleConfirmed &&
              _scheduleOptions.length >= 2 &&
              _scheduleOptions.any((o) => o.recruiting);
          // 정기 파티는 **호스트가 닫아 둔 회차를 뺀** 나머지가 남아 있는지를
          // 본다([PartyOccurrenceRecruit.openOccurrences]) — 9/6만 마감이고
          // 9/13이 열려 있으면 신청 진입은 열려 있어야 하고, 반대로 남은
          // 회차가 전부 닫혔으면 "고르면 되는" 날짜가 없다.
          final hasUnpickedOpenDate =
              (isRecurringParty &&
                  _applyOccurrence.selected == null &&
                  PartyOccurrenceRecruit.openOccurrences(
                    data,
                    PartySchedule.selectableOccurrences(data, now: now),
                    gender: _myGender,
                  ).isNotEmpty) ||
              hasUnpickedOpenDateDoc;

          // ── 성별별 모집 상태 ──────────────────────────────────────────
          //
          // 호스트가 남성 모집과 여성 모집을 따로 닫을 수 있고, 정기 파티는
          // **회차마다 따로** 닫을 수 있다([PartyOccurrenceRecruit]). 그래서
          // 판정 대상은 지금 이 화면이 말하는 회차다(고른 회차 → 없으면 다음
          // 회차). 회차 칸이 없는 파티는 예전 그대로 문서 값을 본다.
          //
          // 정기 파티에서 **다른 회차**가 열려 있으면 신청 진입 자체는 열어
          // 둔다(hasUnpickedOpenDate) — 닫힌 것은 이 회차뿐이고, 날짜를
          // 고르는 자리는 신청 플로우 안에 있기 때문이다.
          //
          // 서버(reserveApplicantSlot)도 같은 규칙으로 막으므로, 여기 UI는
          // "서버가 거절할 일을 애초에 못 누르게" 하는 역할이다.
          final genderRecruitClosed = PartyOccurrenceRecruit.isClosedFor(
            data,
            _myGender,
            occurrenceId: statusOccurrenceId,
          );
          final genderRecruitBlocked =
              genderRecruitClosed && !hasUnpickedOpenDate;
          // 배지에 적을 문구 — 한쪽 성별만 닫힌 회차에서만 알린다.
          // 자기 성별이 모집중이어도 보여줘야 '남성은 마감이고 나는 신청
          // 가능'이 전달된다. 참가자 성비 공개 설정과는 무관하다(그쪽은
          // "지금 참가한 사람들의 남/여 인원"을 감추는 설정이다).
          final genderSplit = PartyOccurrenceRecruit.hasSplit(
            data,
            occurrenceId: statusOccurrenceId,
          );
          final maleClosedHere = PartyOccurrenceRecruit.isMaleClosed(
            data,
            occurrenceId: statusOccurrenceId,
          );
          final genderRecruitLabel = !genderSplit
              ? null
              : isHost
              ? [
                  maleClosedHere
                      ? PartyGenderRecruit.maleClosedLabel
                      : PartyGenderRecruit.maleOpenLabel,
                  maleClosedHere
                      ? PartyGenderRecruit.femaleOpenLabel
                      : PartyGenderRecruit.femaleClosedLabel,
                ].join(' · ')
              : _myGender == PartyGenderRecruit.male
              ? (maleClosedHere
                    ? PartyGenderRecruit.maleClosedLabel
                    : PartyGenderRecruit.maleOpenLabel)
              : _myGender == PartyGenderRecruit.female
              ? (maleClosedHere
                    ? PartyGenderRecruit.femaleOpenLabel
                    : PartyGenderRecruit.femaleClosedLabel)
              : null;

          // 최소 모집 인원 미달로 **이 회차만** 자동 취소된 정기 파티.
          //
          // 파티 문서의 recruitStatus는 '모집중' 그대로다(다른 날짜 회차는
          // 열려 있어야 하므로) — 그래서 취소 여부는 회차 기록을 따로 봐야
          // 알 수 있다. 서버 applyToParty도 같은 기록을 보고 막는다.
          final occurrenceCancelled =
              PartyCard.occurrenceCancellation(
                data,
                occurrenceId: _applyOccurrence.selected?.id,
              ) !=
              null;

          // 신청 버튼을 실제로 막는 이유 — 날짜만 안 골랐을 뿐이면 막지 않는다.
          //
          // 오픈예정만은 "날짜를 안 골랐을 뿐" 예외를 타지 않는다 — 날짜가
          // 남아 있든 말든 아직 모집 자체가 시작되지 않은 파티다.
          //
          // 취소된 회차도 예외를 타지 않는다 — 다만 **고른 회차가 있을 때만**
          // 막는다. 아직 날짜를 안 골랐다면 지금 보이는 회차가 취소됐어도
          // 다른 날짜를 고를 길을 열어둬야 한다(hasUnpickedOpenDate와 같은 뜻).
          final selectedOccurrenceCancelled =
              occurrenceCancelled && _applyOccurrence.selected != null;
          final applyBlockedByDate =
              isPreopen ||
              selectedOccurrenceCancelled ||
              genderRecruitBlocked ||
              (!hasUnpickedOpenDate &&
                  (isFull ||
                      recruitStatus != '모집중' ||
                      deadlinePassed ||
                      recruitNotStarted ||
                      occurrenceCancelled));
          // 이미 신청한 상태에서 취소 가능 여부 — 파티가 아직 시작 전이고,
          // 호스트가 파티 자체를 취소하지 않은 경우에만 참가자가 직접 취소할 수 있다.
          final partyStartedAt = PartyCard.parsePartyDateTime(data);
          final partyStarted =
              partyStartedAt != null && partyStartedAt.isBefore(DateTime.now());
          final canCancelApplication =
              alreadyApplied && !partyStarted && recruitStatus == '모집중';
          // 모집 상태(모집중/모집마감/모집 예정)는 **로그인한 사용자에게만**
          // 보여준다. 로그인 전에는 마감된 파티도 다른 파티와 똑같이 보이고,
          // 아래 '신청하기'를 누르면 로그인 화면부터 이어진다.
          // 마감 여부 데이터와 신청 차단 로직은 그대로다 — 로그인하고 나면
          // 곧바로 실제 상태와 비활성화된 버튼이 보인다.
          final showRecruitState = !loggedOut;
          // 취소·중단처럼 "마감"과 뜻이 다른 상태는 로그인 전에도 그대로
          // 알린다 — "로그인하면 신청할 수 있다"고 오해하게 두면 안 된다.
          final showsPreLoginStatus =
              loggedOut &&
              recruitStatus != '모집중' &&
              !PartyCard.isRecruitClosed(recruitStatus);
          // 연령 제한은 **성별별**이라 한 줄로 합치지 않고 '남성 25~35세 ·
          // 여성 23~32세'처럼 나눠 보여준다(제한이 없는 성별은 '제한 없음').
          // 성별 필드가 없는 기존 파티는 옛 공통 범위가 남녀 양쪽에 같은
          // 값으로 들어와 '남성 25~35세 · 여성 25~35세'로 보인다.
          final ageLabel = PartyAgeRestriction.fromMap(
            data,
          ).summaryLabel(genderLimit: data['genderLimit'] as String? ?? 'all');

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── 미디어 갤러리 (이미지 + 동영상 통합) + 공유·찜 오버레이 ──
                      // 대표 미디어가 사진이든 동영상이든 같은 위치에 뜨도록
                      // MediaGallery 바깥에서 한 번만 오버레이한다(내부 점
                      // 인디케이터는 bottom:12라 bottom:16 오버레이와 겹치지
                      // 않고, 동영상 진행바는 bottom:0이라 역시 안 겹친다).
                      Stack(
                        children: [
                          if (images.isNotEmpty ||
                              (videoUrl != null && videoUrl.isNotEmpty))
                            MediaGallery(
                              images: images,
                              videoUrl: videoUrl,
                              videoThumbnailUrl: videoThumbnailUrl,
                              initialPage: galleryInitialPage,
                              videoFirst: videoIsCover,
                              // 원본 비율 그대로 보여주고(잘리지 않음), 비율
                              // 차이로 남는 여백은 화면 배경(Scaffold
                              // backgroundColor)과 같은 연핑크로 — 다른
                              // 화면(장소대여 상세 등)은 기본값(cover+그라데이션)
                              // 그대로라 영향 없다.
                              videoFit: BoxFit.contain,
                              videoBackgroundColor: const Color(0xFFFFF7FA),
                              // 우측 상단 "1/2" 카운터도 파티추 핑크 톤으로.
                              counterAccentColor: const Color(0xFFFF6FA0),
                            )
                          else
                            Container(
                              width: double.infinity,
                              height: 220,
                              color: const Color(0xFFE9ECF5),
                              child: const Icon(
                                Icons.image_outlined,
                                size: 60,
                                color: Colors.grey,
                              ),
                            ),
                          // bottom:20 — 진행 바(VideoSeekBar, GalleryVideoItem
                          // 내부 bottom:48)보다 아래, 화면 맨 아래 가장자리에
                          // 가깝게 둔다. 순서를 "진행 바 → 스피커·공유·찜
                          // 버튼"으로 바꾸면서 값만 진행 바와 맞바꿨다(겹치지
                          // 않도록 이미 맞춰둔 간격 28px은 그대로 유지).
                          Positioned(
                            right: 16,
                            bottom: 20,
                            child: Row(
                              children: [
                                ShareIconButton(
                                  onTap: () => showPartyShareSheet(
                                    context,
                                    partyId: widget.docId,
                                    partyData: data,
                                  ),
                                  size: 20,
                                  color: PartyChuColors.primary,
                                ),
                                const SizedBox(width: 10),
                                FavoriteStarButton(
                                  itemType: FavoriteType.party,
                                  itemId: widget.docId,
                                  size: 20,
                                  glow: false,
                                ),
                              ],
                            ),
                          ),
                          // 대표 미디어가 동영상일 때만 음소거 버튼을 영상
                          // 왼쪽 아래에 오버레이한다(사진만 있으면 음소거할
                          // 대상이 없으므로 숨김). 공유/찜 버튼과는 반대쪽
                          // 모서리에 둬서 서로 겹치지 않는다. bottom 값은
                          // 위 공유/찜 버튼과 동일하게 맞춰 진행 바 아래에 둔다.
                          if (videoUrl != null && videoUrl.isNotEmpty)
                            const Positioned(
                              left: 16,
                              bottom: 20,
                              child: MuteToggleIconButton(size: 20),
                            ),
                        ],
                      ),

                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 파티 유형 칩 + 모집 상태 배지 — 모집중일 때는
                            // 배지를 아예 그리지 않는다(Wrap 자식에서 빼야
                            // spacing만큼의 빈 간격도 남지 않는다).
                            // 칩이 작아진 만큼 간격도 6으로 좁혀, 가로·세로
                            // 간격이 같은 정돈된 격자로 보이게 한다.
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ..._partyTypeChips(data),
                                if (showRecruitState &&
                                    (occurrenceCancelled ||
                                        deadlinePassed ||
                                        recruitNotStarted ||
                                        recruitStatus != '모집중' ||
                                        genderRecruitLabel != null))
                                  _statusBadge(
                                    occurrenceCancelled
                                        ? '회차 취소'
                                        : deadlinePassed
                                        ? '모집마감'
                                        : recruitNotStarted
                                        ? '모집 예정'
                                        : recruitStatus != '모집중'
                                        ? recruitStatus
                                        // 여기까지 왔으면 파티 전체는 모집중
                                        // 이고, 남/여 중 한쪽만 닫힌 것이다.
                                        : genderRecruitLabel!,
                                  ),
                                // 취소는 마감과 뜻이 달라 로그인 전에도 알린다 —
                                // "로그인하면 신청할 수 있다"고 오해하게 두면 안 된다.
                                if (showsPreLoginStatus)
                                  _statusBadge(recruitStatus),
                                // 그 밖의 모집 상태는 로그인 전에 감추는 대신,
                                // 참가비처럼 "로그인 후 확인"이라고 밝힌다.
                                // 이 배지는 마감·종료 여부와 관계없이 로그인
                                // 전이면 **항상** 붙는다 — 끝난 파티에만
                                // 붙이면 배지의 유무가 곧 종료 여부를 알려주는
                                // 꼴이 되어 감추는 의미가 없다.
                                if (!showRecruitState && !showsPreLoginStatus)
                                  _statusBadge(
                                    '로그인 후 모집 상태 확인',
                                    icon: Icons.lock_outline,
                                  ),
                              ],
                            ),
                            // 칩이 작아졌으므로 제목과의 간격도 함께 줄인다 —
                            // 칩·제목이 한 덩어리로 읽히고, 제목이 이 영역의
                            // 주인공이라는 게 분명해진다.
                            const SizedBox(height: 12),

                            // 제목 — 장식 없이 굵은 텍스트만(미니멀 톤).
                            Text(
                              data['title'] as String? ?? '',
                              style: const TextStyle(
                                fontFamily: PartyChuTitleFont.family,
                                fontSize: 22,
                                fontWeight: PartyChuTitleFont.medium,
                                height: 1.3,
                                color: PartyChuColors.heading,
                                shadows: [
                                  Shadow(
                                    color: PartyChuColors.heading,
                                    offset: Offset(0.3, 0),
                                  ),
                                  Shadow(
                                    color: PartyChuColors.heading,
                                    offset: Offset(-0.3, 0),
                                  ),
                                  Shadow(
                                    color: PartyChuColors.heading,
                                    offset: Offset(0, 0.3),
                                  ),
                                  Shadow(
                                    color: PartyChuColors.heading,
                                    offset: Offset(0, -0.3),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // 파티 핵심 정보 요약 카드 — 세로 목록 대신
                            // 날짜·장소·참여 인원·참가비를 한 줄(1x4)로
                            // 나란히 보여주고, 나이 제한/모집마감처럼 부가
                            // 정보는 카드 하단의 보조 줄로 분리한다.
                            PartyChuCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 22,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 최소 인원 미달로 자동 취소된 파티(또는
                                  // 정기 파티의 그 회차)는 그 사실을 가장
                                  // 먼저 알려준다.
                                  if (PartyCancelReason.labelOf(data) != null ||
                                      occurrenceCancelled)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF5F5),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFE53935),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              occurrenceCancelled
                                                  ? '이 회차는 최소 모집 인원 미달로 취소됐어요'
                                                  : PartyCancelReason.labelOf(
                                                      data,
                                                    )!,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFFE53935),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              occurrenceCancelled
                                                  // 다른 날짜는 그대로 열려
                                                  // 있다는 것을 함께 알려야
                                                  // 파티 자체가 없어진 줄
                                                  // 알고 떠나지 않는다.
                                                  ? '결제한 참가비는 전액 환불 처리됩니다. '
                                                        '다른 날짜 회차는 그대로 신청할 수 있어요.'
                                                  : '결제한 참가비는 전액 환불 처리됩니다.',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                                height: 1.45,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  _summaryStatsRow(
                                    data,
                                    address,
                                    isHost: isHost,
                                  ),
                                  // 모집 현황 — 8/20명 + 최소 모집 + 확정 배지.
                                  // 상단 통계 타일은 좁아서 숫자만 들어가므로,
                                  // 최소 인원과 확정 여부는 여기서 풀어준다.
                                  const SizedBox(height: 14),
                                  PartyCapacityMeter(
                                    // 정기 파티는 고른 회차(없으면 다음 회차)의
                                    // 인원이다 — 날짜를 바꾸면 함께 바뀐다.
                                    status: PartyCard.capacityStatus(
                                      data,
                                      occurrenceId:
                                          _applyOccurrence.selected?.id,
                                    ),
                                    autoCancelPolicy:
                                        PartyCard.autoCancelsBelowMin(data),
                                    // 현재 인원·진행 막대·확정 배지·'N명 더
                                    // 모이면 확정'은 로그인한 사용자에게만 —
                                    // 위 요약 칸('참여 인원')과 같은 기준이다.
                                    revealCounts: !loggedOut,
                                  ),
                                  if (address.isNotEmpty ||
                                      recurringLabel.isNotEmpty ||
                                      recruitDeadlineAt != null ||
                                      recruitNotStarted ||
                                      earlyBirdRowText.isNotEmpty ||
                                      ageLabel.isNotEmpty) ...[
                                    const SizedBox(height: 18),
                                    const Divider(
                                      height: 1,
                                      color: PartyChuColors.border,
                                    ),
                                    const SizedBox(height: 14),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (address.isNotEmpty) ...[
                                          _miniInfoRow(
                                            Icons.location_on_rounded,
                                            '상세 주소',
                                            fullAddress,
                                            color: const Color(0xFFB06CFF),
                                            showChevron: false,
                                            // events·places·파티샵 상세와 완전히
                                            // 같은 복사/길찾기 구현을 그대로
                                            // 쓴다(파티 상세의 라벨 행 디자인과
                                            // 간격은 유지).
                                            trailing: PlaceAddressActions(
                                              address: fullAddress,
                                              placeName:
                                                  data['placeName'] as String?,
                                              latitude: lat,
                                              longitude: lng,
                                              actionColor: const Color(
                                                0xFFB06CFF,
                                              ),
                                              iconSize: 15,
                                            ),
                                          ),
                                          // 접근성 보조 정보 — 다른 상세
                                          // 화면(PlaceAddressRow)과 같은 위젯을
                                          // 쓴다. 파티 상세만 라벨 행 구조라
                                          // 여기서 따로 붙인다. 아이콘(16) +
                                          // 간격(8)만큼 들여써 주소와 세로선을
                                          // 맞춘다.
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 24,
                                            ),
                                            child: PlaceAccessInfo(
                                              latitude: lat,
                                              longitude: lng,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                        ],
                                        if (recurringLabel.isNotEmpty) ...[
                                          _miniInfoRow(
                                            Icons.repeat_rounded,
                                            '정기 일정',
                                            recurringLabel,
                                            color: const Color(0xFF3A8DDE),
                                            showChevron: false,
                                          ),
                                          const SizedBox(height: 12),
                                        ],
                                        // 개별 예정 날짜는 상세에 **나열하지
                                        // 않는다.** 위 '정기 일정' 줄이 반복
                                        // 규칙(매일 / 매주 화·목 …)과 시간을
                                        // 말하고, 실제 참가 날짜는 '신청하기'를
                                        // 누른 뒤 신청 플로우의 달력에서만
                                        // 고른다([_pickOccurrence]).
                                        // 아직 모집 전이면 "언제부터 신청할 수
                                        // 있는지"가 마감보다 먼저 궁금하다.
                                        //
                                        // 로그인 전에는 이 행 자체를 그리지
                                        // 않는다 — 행이 있다는 사실이 곧 "아직
                                        // 모집 전"이라는 상태를 알려준다.
                                        if (showRecruitState &&
                                            recruitNotStarted) ...[
                                          _miniInfoRow(
                                            Icons.event_available_rounded,
                                            recurringLabel.isEmpty
                                                ? '모집 시작'
                                                : '이번 회차 모집 시작',
                                            _formatDeadline(recruitOpenAt),
                                            color: const Color(0xFF4F46E5),
                                            showChevron: false,
                                          ),
                                          const SizedBox(height: 12),
                                        ],
                                        // 모집 마감 — 로그인 전에는 시각도
                                        // D-Day도 가린다. 마감 시각은 지금과
                                        // 견주기만 하면 종료 여부가 그대로
                                        // 드러나기 때문에, 배지만 떼는 것으로는
                                        // 감춘 것이 아니다.
                                        //
                                        // 로그인 전에는 마감 시각이 **있든
                                        // 없든** 이 행을 같은 모습으로 그린다 —
                                        // 행의 유무나 문구 차이가 곧 상태가
                                        // 되어서는 안 된다.
                                        if (!showRecruitState) ...[
                                          _miniInfoRow(
                                            Icons.schedule_rounded,
                                            recurringLabel.isEmpty
                                                ? '모집 마감'
                                                : '이번 회차 모집 마감',
                                            '🔒 로그인 후 확인 가능',
                                            color: const Color(0xFF64B5F6),
                                          ),
                                          const SizedBox(height: 12),
                                        ] else if (recruitDeadlineAt !=
                                            null) ...[
                                          _miniInfoRow(
                                            Icons.schedule_rounded,
                                            recurringLabel.isEmpty
                                                ? '모집 마감'
                                                : '이번 회차 모집 마감',
                                            _formatDeadline(recruitDeadlineAt),
                                            color: const Color(0xFF64B5F6),
                                            trailing: Text(
                                              _dDayLabel(recruitDeadlineAt),
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFFFF5C93),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                        ],
                                        if (ageLabel.isNotEmpty) ...[
                                          _miniInfoRow(
                                            Icons.verified_user_rounded,
                                            '나이 제한',
                                            ageLabel,
                                            color: const Color(0xFFB06CFF),
                                            showChevron: false,
                                          ),
                                          if (earlyBirdRowText.isNotEmpty)
                                            const SizedBox(height: 12),
                                        ],
                                        // 카드의 **맨 아래 줄** — 정기 일정·모집
                                        // 마감과 같은 스타일의 정보행이다.
                                        if (earlyBirdRowText.isNotEmpty)
                                          _miniInfoRow(
                                            Icons.confirmation_number_rounded,
                                            '얼리버드',
                                            earlyBirdRowText,
                                            color: const Color(0xFFD94F7A),
                                            showChevron: false,
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // 파티츄 전용 혜택 · 얼리버드 · 연동 숙소 —
                            // 각각 독립된 둥근 카드로 분리(있을 때만
                            // 렌더링). 환불 규정은 읽는 순서상 가장 뒤라
                            // 페이지 맨 아래로 내렸다.
                            // 파티는 참가자에게 현장에서 주는 혜택이라, 매장
                            // 상세의 "'파티츄 보고 왔어요'라고 말씀해주세요"
                            // 안내를 쓰지 않는다.
                            // 일정 안내 — 같은 게시글의 날짜가 여러 개면 어떤
                            // 날짜에 열리는지 **읽기 전용**으로 알려준다.
                            // 참가할 날짜는 '신청하기' 안에서만 고른다.
                            _scheduleInfo(),
                            // 차수 및 참가비 — 신청 버튼을 누르기 **전에**
                            // 차수별 시간·참가비와 패키지 할인을 다 볼 수 있게
                            // 하는 정본 영역이다. 신청 시트와 같은
                            // PartyRoundOffers 목록을 쓴다.
                            PartyRoundOfferSection(
                              offers: PartyRoundOffers.of(
                                data,
                                gender: UserSession.gender,
                                // 고른 회차(정기) 또는 이 파티의 날짜 기준으로
                                // 차수 시각을 다시 계산한다 — 문서에 캐시된
                                // 과거 시각을 그대로 쓰면 아직 열리지도 않은
                                // 차수가 '종료'로 표시된다.
                                occurrenceStart: _roundBaseDate(data),
                                // 차수 정원도 회차별이라 인원·잔여를 이 회차
                                // 값으로 읽는다(날짜를 바꾸면 함께 바뀐다).
                                occurrenceId: _roundOccurrenceId(data),
                              ),
                              // 차수별 종료·마감도 모집 상태다 — 위 상태 배지와
                              // 같은 기준으로 로그인한 사용자에게만 드러낸다.
                              revealStatus: showRecruitState,
                            ),
                            // 얼리버드 안내는 **위 기본 정보 카드의 맨 아래
                            // 정보행**으로 합쳤다 — 한 줄짜리 안내에 네모 박스를
                            // 따로 띄우면 정기 일정·모집 마감과 같은 성격의
                            // 정보인데도 다른 덩어리처럼 읽혔다.
                            //
                            // '이 파티가 열리는 플레이스'(_linkedEventInfo)는
                            // 여기 있지 않다 — "어디서 열리나"는 지도와 이어서
                            // 읽는 게 맞아 아래 위치 섹션 바로 다음으로 옮겼다.
                            // 신청 자격·1인 1신청 안내 — 차수/참가비 바로 다음,
                            // 즉 "무엇을 얼마에 신청하는가"를 읽은 직후에 둔다.
                            // 환불 규정처럼 맨 아래로 내리면 신청 버튼을 누를
                            // 때까지 한 번도 안 보고 지나갈 수 있다.
                            //
                            // 호스트에게는 그리지 않는다 — 호스트가 볼 안내는
                            // 신청자 목록 화면의 입장 확인 안내다
                            // ([PartyHostIdentityCheckNotice]).
                            if (!isHost) const PartyApplyIdentityNotice(),
                            // 문의하기는 본문이 아니라 아래 **신청 CTA 옆**에
                            // 있다 — 물어보고 신청하는 흐름이 한자리에 모인다.
                            PartychuPerkCard.fromData(
                              data,
                              margin: const EdgeInsets.only(top: 16),
                              audience: PartychuPerkAudience.party,
                            ),
                            _linkedPlaceInfo(data),

                            const SizedBox(height: 24),

                            // 상세 설명 방식 — "간편 자동 꾸미기" 또는 "직접
                            // 상세페이지 만들기" 중 선택된 한쪽만 보여준다
                            // (둘 다 저장돼 있어도 렌더링은 하나만).
                            // detailDescriptionMode가 아예 없는(이 기능
                            // 이전에 등록된) 파티는 오늘과 완전히 동일하게
                            // 보이도록, detailBlocks 유무로만 판단해 기존
                            // 두 갈래(블록 섹션/평문 description) 로직을
                            // 그대로 유지한다 — 새로 "자동 꾸미기"로 보이는
                            // 회귀가 생기지 않는다.
                            ...() {
                              final modeRaw =
                                  data['detailDescriptionMode'] as String?;
                              final detailBlocks =
                                  PartyDetailBlock.listFromDynamic(
                                    data['detailBlocks'],
                                  );

                              final isBlocksMode =
                                  modeRaw == 'blocks' ||
                                  (modeRaw == null && detailBlocks.isNotEmpty);
                              if (isBlocksMode) {
                                if (detailBlocks.isEmpty) return <Widget>[];
                                final detailTheme =
                                    partyDetailThemeKeyFromString(
                                      data['detailTheme'] as String?,
                                    );
                                final detailDecorationIntensity =
                                    partyDetailDecorationIntensityFromString(
                                      data['detailDecorationIntensity']
                                          as String?,
                                    );
                                final detailDecorationVariantSeed =
                                    (data['detailDecorationVariantSeed']
                                            as num?)
                                        ?.toInt() ??
                                    0;
                                return [
                                  _DetailBlockSection(
                                    blocks: detailBlocks,
                                    theme: detailTheme,
                                    intensity: detailDecorationIntensity,
                                    variantSeed: detailDecorationVariantSeed,
                                    partyId: widget.docId,
                                    onImageTap: (block) {
                                      final url = block.imageUrl;
                                      if (url == null || url.isEmpty) return;
                                      Navigator.push(
                                        context,
                                        webFramedRoute(
                                          (_) => FullScreenImageViewer(
                                            imageUrl: url,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ];
                              }

                              if (modeRaw == 'auto') {
                                final description =
                                    (data['description'] as String?)?.trim() ??
                                    '';
                                if (description.isEmpty) return <Widget>[];
                                final style = PartyAutoDescriptionStyle.fromMap(
                                  data['autoDescriptionStyle']
                                      as Map<String, dynamic>?,
                                );
                                // 새 렌더러를 만들지 않고, 소개글 원문을
                                // classifyDescriptionToBlocks로 자동 분석해
                                // (날짜/장소/가격/주의/마감/배너/리스트/본문
                                // 카드) 블록형 상세페이지와 동일한
                                // PartyDetailBlockPreview에 그대로 넣는다.
                                // 원문(description)은 여기서 전혀 가공하지
                                // 않는다 — 분류·이모지는 매번 다시 계산되는
                                // 렌더링 전용 파생물일 뿐 저장되지 않는다.
                                final isRich =
                                    style.intensity ==
                                    PartyDetailDecorationIntensity.rich;
                                final keywords = isRich
                                    ? extractAutoDescriptionKeywords(
                                        description,
                                      )
                                    : const <({String emoji, String label})>[];
                                final detailPalette =
                                    PartyDetailThemeRegistry.fromKey(
                                      style.theme,
                                    );
                                return [
                                  if (keywords.isNotEmpty) ...[
                                    PartyAutoKeywordBadges(
                                      keywords: keywords,
                                      palette: detailPalette,
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  PartyDetailBlockPreview(
                                    blocks: classifyDescriptionToBlocks(
                                      description,
                                      variantSeed: style.variantSeed,
                                      paragraphStyles: style.paragraphStyles,
                                      rich: isRich,
                                    ),
                                    theme: style.theme,
                                    intensity: style.intensity,
                                    variantSeed: style.variantSeed,
                                    partyId: widget.docId,
                                    richAutoDecorations: isRich,
                                  ),
                                ];
                              }

                              // modeRaw == null && detailBlocks.isEmpty —
                              // 레거시 파티, 평문 소개도 카드 안에 담아
                              // 다른 섹션들과 톤을 맞춘다(내용/로직은 동일).
                              return [
                                PartyChuCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _sectionTitle('모임 소개'),
                                      const SizedBox(height: 12),
                                      Text(
                                        (data['description'] as String?)
                                                    ?.isNotEmpty ==
                                                true
                                            ? data['description'] as String
                                            : '등록된 설명이 없습니다.',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: PartyChuColors.muted,
                                          height: 1.7,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ];
                            }(),

                            // 상세 이미지(선택) — 호스트가 캔바·미리캔버스
                            // 등에서 만든 세로형 상세페이지 이미지 1장.
                            //
                            // 소개(자동 꾸미기 / 블록형 / 평문) **바로 다음**에
                            // 온다. 위 분기는 어느 방식을 골랐느냐에 따라 셋 중
                            // 하나만 그리지만, 이 이미지는 방식과 무관하게 늘
                            // 그 아래 붙는다.
                            //
                            // 화면 끝까지(가로폭 100%) 그리기 위해 본문
                            // Padding(all(20))을 되돌린다 — 상단 갤러리와 같은
                            // 폭이라야 "상세페이지 이미지"로 보인다. 세로는
                            // 원본 비율 그대로 길어지고, 그만큼 상세 스크롤이
                            // 길어지는 것이 의도된 동작이다.
                            ...() {
                              final detailImage = PartyDetailImage.fromData(
                                data,
                              );
                              if (detailImage == null) return <Widget>[];
                              return [
                                const SizedBox(height: 24),
                                PartyDetailImageView(
                                  image: detailImage,
                                  fullBleed: true,
                                  horizontalPadding: 40,
                                ),
                              ];
                            }(),

                            // 분위기
                            ...() {
                              final vibes =
                                  (data['vibes'] as List?)?.cast<String>() ??
                                  [];
                              if (vibes.isEmpty) return <Widget>[];
                              return [
                                const SizedBox(height: 24),
                                _sectionTitle('분위기'),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: vibes
                                      .map(
                                        (v) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF3EFFA),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFCFC0E8),
                                            ),
                                          ),
                                          child: Text(
                                            // 저장값은 그대로 두고 보이는
                                            // 글자만 최신 표기로.
                                            PartyConstants.vibeLabelFor(v),
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF7C5CBF),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ];
                            }(),

                            // 태그
                            ...() {
                              final tags =
                                  (data['tags'] as List?)?.cast<String>() ?? [];
                              if (tags.isEmpty) return <Widget>[];
                              return [
                                const SizedBox(height: 24),
                                _sectionTitle('태그'),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: tags
                                      .map(
                                        (t) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF7F8FC),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFDDE1EC),
                                            ),
                                          ),
                                          child: Text(
                                            '#$t',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ];
                            }(),

                            // 이 파티가 열리는 플레이스 — 위치 섹션 **바로 위**.
                            // "어떤 플레이스인지"를 먼저 알고 그 다음에 위치·
                            // 지도·주소·네이버지도 열기로 이어진다.
                            // (연결된 플레이스가 없으면 아무것도 그리지 않는다 —
                            //  카드가 여백을 스스로 갖고 있으므로 그때는 태그 →
                            //  위치가 예전과 똑같이 붙는다.)
                            _linkedEventInfo(data),

                            // ── 위치 지도 ─────────────────────────────
                            if (hasLocation) ...[
                              const SizedBox(height: 24),
                              _sectionTitle('위치'),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(26),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: SizedBox(
                                    height: 200,
                                    child: _PartyLocationMap(
                                      key: ValueKey('map_${lat}_$lng'),
                                      latitude: lat,
                                      longitude: lng,
                                    ),
                                  ),
                                ),
                              ),
                              if (fullAddress.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                // 지도 아래 캡션 — 위 "상세 주소" 행과 완전히
                                // 같은 값을 쓴다(여러 지도 앱 중에 고르는
                                // 길찾기 버튼은 그 행에만 두어 한 화면에 두 번
                                // 나오지 않게 한다).
                                Text(
                                  fullAddress,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: PartyChuColors.muted,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              // 지도 위 초록 NAVER 로고는 SDK 법적 공지용이라
                              // 눌러도 지도가 열리지 않는다 — 사용자가 그 로고를
                              // 눌렀던 자리를 이 버튼이 대신한다.
                              //
                              // 위 "상세 주소" 행의 길찾기 아이콘과 역할이 겹치지
                              // 않는다: 그쪽은 설치된 지도 앱(카카오·T맵·구글
                              // 포함) 중에서 고르는 길찾기이고, 이 버튼은 지금
                              // 보고 있는 이 지도를 네이버지도에서 여는 것이다
                              // (앱이 없으면 네이버지도 웹). 네이버지도를 바로
                              // 여는 버튼은 이 화면에 이것 하나뿐이다.
                              _naverMapButton(
                                placeName: data['placeName'] as String?,
                                address: fullAddress,
                                latitude: lat,
                                longitude: lng,
                              ),
                            ],

                            // 환불 규정 — 상세 내용을 다 읽은 뒤 마지막에
                            // 확인하는 안내라 페이지 최하단에 둔다.
                            _refundPolicyInfo(data),

                            // 💬 참여 후기 — 실제 참여를 마친 게스트만 남길 수
                            // 있다(작성 자격·기한은 서버가 판정한다).
                            // 후기가 0개면 제목과 한 줄 안내만 남아 자리를 거의
                            // 차지하지 않는다.
                            PartyReviewSection(partyId: widget.docId),

                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 파티장: 신청자 목록 + 재등록 버튼 — 메인 CTA답게 좌우 여백을
              // 넉넉히 두고, 은은한 핑크 그림자 + 양옆 반짝이 장식을 더한다.
              if (isHost)
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: const Border(
                      top: BorderSide(color: PartyChuColors.border),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: PartyChuColors.primary.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 앱 공통 PartyChuPrimaryButton — 발바닥 배지/반짝이
                      // 장식 없이 그라데이션 버튼만 미니멀하게 사용한다.
                      PartyChuPrimaryButton(
                        label:
                            '신청자 목록 (${List.from(data['applicants'] ?? []).length}명)',
                        showBadge: false,
                        showSparkle: false,
                        onTap: () {
                          Navigator.push(
                            context,
                            webFramedRoute(
                              (_) => PartyApplicantsScreen(
                                // 신청자는 날짜(문서)별로 따로 관리된다 —
                                // 호스트가 지금 보고 있는 날짜의 신청자를 연다.
                                partyId: _activeDocId,
                                partyTitle: data['title'] as String? ?? '',
                                rounds: (data['rounds'] as List?)
                                    ?.map(
                                      (r) =>
                                          Map<String, dynamic>.from(r as Map),
                                    )
                                    .toList(),
                                partyData: data,
                              ),
                            ),
                          );
                        },
                      ),
                      if (canReregister) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: OutlinedButton.icon(
                            onPressed: reregisterExpired
                                ? null
                                : () async {
                                    // 재등록은 새 파티 문서를 만드는 길이라
                                    // 등록 화면과 **같은 관문**을 지난다.
                                    if (!await PartyCreateEligibility.ensure(
                                      context,
                                    )) {
                                      return;
                                    }
                                    if (!context.mounted) return;
                                    await Navigator.push(
                                      context,
                                      // 재등록은 **파티 등록 화면(정본)** 을
                                      // 재등록 모드로 연다 — 입력 항목·섹션
                                      // 순서·검증·차수·패키지가 등록과 100%
                                      // 같고, 저장만 새 파티 문서로 나간다.
                                      // (예전에는 파티 수정 화면을 재사용해서
                                      //  등록에만 있는 차수 편집기·연령제한
                                      //  시트·미입력 배너가 빠져 있었다.)
                                      webFramedRoute(
                                        (_) => PartyRegisterScreen.reregister(
                                          docId: widget.docId,
                                          data: data,
                                        ),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.repeat, size: 18),
                            label: Text(
                              reregisterExpired ? '재등록 기간 만료 (1개월 초과)' : '재등록',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: reregisterExpired
                                  ? Colors.black38
                                  : const Color(0xFFFF6FA0),
                              side: BorderSide(
                                color: reregisterExpired
                                    ? Colors.black12
                                    : const Color(0xFFFF6FA0),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // 일반 사용자: 신청 버튼
              if (!isHost)
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    12 + MediaQuery.of(context).padding.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: const Border(
                      top: BorderSide(color: PartyChuColors.border),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: PartyChuColors.primary.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  // 오픈예정 파티는 신청 버튼도, 참가비·차수 요약도, 결제수단
                  // 안내도 띄우지 않는다 — 받을 수 없는 돈의 결제수단을
                  // 보여주면 "지금 낼 수 있다"는 뜻이 되기 때문이다. 대신
                  // 오픈 알림 신청 하나만 남긴다.
                  child: isPreopen
                      ? _PreopenAlertBar(
                          partyId: widget.docId,
                          loggedOut: loggedOut,
                          dateTbd: isDateTbd,
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!loggedOut &&
                                eligibility != PartyEligibility.eligible &&
                                !alreadyApplied)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.lock_outline,
                                      size: 14,
                                      color: Color(0xFF7B5EA7),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        eligibilityReason(eligibility),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF7B5EA7),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // 차수가 여러 개면 버튼 위에 '1차 3만원 · 2차 2.5만원 ·
                            // 1+2차 패키지 4.5만원' 요약을 얇게 붙인다. 정본은 위
                            // "차수 및 참가비" 영역이라 여기서는 한 줄로 줄이고,
                            // 넘치면 말줄임한다(버튼 높이를 밀어 올리지 않는다).
                            if (!loggedOut && !alreadyApplied)
                              Builder(
                                builder: (_) {
                                  final summary = PartyRoundOffers.summaryLine(
                                    data,
                                    gender: UserSession.gender,
                                    occurrenceStart: _roundBaseDate(data),
                                    occurrenceId: _roundOccurrenceId(data),
                                  );
                                  if (summary.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      summary,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFFF6FA0),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            // 문의 + 신청을 한 줄에 둔다. 호스트가 문의를 꺼
                            // 뒀거나 내 파티면 왼쪽 칸이 통째로 빠지고 신청
                            // 버튼이 예전처럼 전체 폭을 쓴다.
                            Row(
                              children: [
                                if (GuestInquiryButton.shouldShow(
                                  enabled: ListingInquiry.isEnabled(data),
                                  hostId: data['hostId'] as String? ?? '',
                                )) ...[
                                  SizedBox(
                                    width: 108,
                                    height: 52,
                                    child: GuestInquiryButton(
                                      enabled: true,
                                      compact: true,
                                      // 주 CTA가 핑크라 이쪽은 흰 배경·검정
                                      // 테두리로 둔다('채팅 문의').
                                      mono: true,
                                      target: InquiryTarget.party,
                                      listingId: _activeDocId,
                                      hostId: data['hostId'] as String? ?? '',
                                      hostName:
                                          data['hostName'] as String? ?? '호스트',
                                      listingTitle:
                                          data['title'] as String? ?? '파티',
                                      guide: ListingInquiry.guideOf(data),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: SizedBox(
                                    height: 52,
                                    child: canCancelApplication
                                        ? OutlinedButton(
                                            // 요청이 살아 있는 동안에는 버튼을 죽인다 —
                                            // 연타로 callable이 두 번 나가지 않게 하는 1차
                                            // 방어다(2차는 [_confirmAndCancelApplication]
                                            // 진입부의 _cancelling 검사).
                                            onPressed: _cancelling
                                                ? null
                                                : () =>
                                                      _confirmAndCancelApplication(
                                                        context,
                                                        data,
                                                      ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.red,
                                              side: const BorderSide(
                                                color: Colors.red,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              textStyle: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            child: Text(
                                              _cancelling
                                                  ? '취소 처리 중...'
                                                  : '신청 취소',
                                            ),
                                          )
                                        : ElevatedButton(
                                            // 로그인 전에는 마감·정원·자격을 따지지 않고
                                            // 항상 눌리게 둔다 — 눌러도 아래 핸들러가
                                            // 로그인 화면부터 띄우고 끝난다(신청은 로그인
                                            // 뒤 실제 상태로 다시 판정된다). 마감된 파티만
                                            // 회색으로 죽어 있으면 그 자체가 모집 상태를
                                            // 드러내므로, 다른 파티와 똑같이 보이게 한다.
                                            onPressed:
                                                // 신청이 진행 중이면 어떤 경로든 버튼을
                                                // 죽인다 — 연타로 신청이 두 번 나가지
                                                // 않게 하는 1차 방어다(2차는
                                                // [_startApplyFlow] 진입부).
                                                _applying ||
                                                    (!loggedOut &&
                                                        (alreadyApplied ||
                                                            applyBlockedByDate ||
                                                            eligibility !=
                                                                PartyEligibility
                                                                    .eligible))
                                                ? null
                                                // 버튼은 늘 '신청하기' 하나이고, 로그인·
                                                // 날짜·회차·차수·결제수단 중 **아직 정해지지
                                                // 않은 것만** 신청 플로우가 순서대로 이어
                                                // 받는다([_startApplyFlow]).
                                                : () => _startApplyFlow(
                                                    context,
                                                    data,
                                                  ),
                                            style: ElevatedButton.styleFrom(
                                              // 주 CTA는 앱 브랜드 핑크
                                              // ([PartyChuColors.primary]) — 화면마다
                                              // 색을 새로 고르지 않는다.
                                              backgroundColor:
                                                  PartyChuColors.primary,
                                              foregroundColor: Colors.white,
                                              // 신청 중에도 버튼은 disabled지만, '눌리지
                                              // 않는 버튼'의 회색이 아니라 **일하는 중인
                                              // 버튼**으로 보여야 한다 — 회색으로 죽으면
                                              // 실패한 것처럼 읽힌다.
                                              disabledBackgroundColor: _applying
                                                  ? PartyChuColors.primary
                                                  : Colors.grey.shade300,
                                              disabledForegroundColor: _applying
                                                  ? Colors.white
                                                  : Colors.grey,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              textStyle: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            // 로그인 전에도 같은 '신청하기'다 — 마감된
                                            // 파티도 다른 파티와 똑같이 보이고, 실제 상태는
                                            // 로그인 뒤에 드러난다. 로그인 역시 신청에
                                            // 필요한 단계일 뿐이라 버튼을 누르면 로그인
                                            // 화면부터 순서대로 이어진다(아래 onPressed).
                                            //
                                            // 아래 나머지 문구는 '단계'가 아니라 **버튼이
                                            // 죽어 있는 이유**다(모집마감·신청 완료 등).
                                            // 눌러도 진행되지 않으므로 그대로 둔다.
                                            child: _applying
                                                // 신청 요청이 살아 있는 동안의 표시.
                                                // 문구가 아니라 **움직이는 인디케이터**가
                                                // 있어야 멈춘 게 아니라는 게 전달된다.
                                                ? const Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      ),
                                                      SizedBox(width: 10),
                                                      Text('신청 처리 중...'),
                                                    ],
                                                  )
                                                : Text(
                                                    loggedOut
                                                        ? '신청하기'
                                                        // 이미 신청한 건은 마감·정원보다 먼저
                                                        // 알린다 — 이 사람에게 유효한 사실은
                                                        // "이미 신청했다" 쪽이다.
                                                        : alreadyApplied
                                                        ? '신청 완료'
                                                        // 날짜만 아직 안 골랐을 뿐이면 죽어 있는
                                                        // 버튼이 아니다 — 지금 화면이 가리키는
                                                        // 날짜가 마감이어도 열려 있는 날짜가
                                                        // 남아 있으므로 그대로 '신청하기'다
                                                        // (누르면 날짜부터 고르게 된다).
                                                        // 취소된 회차를 이미 골라 둔
                                                        // 사람에게는 그 사실이
                                                        // 마감보다 먼저 유효하다.
                                                        : selectedOccurrenceCancelled
                                                        ? '취소된 회차'
                                                        // 내 성별의 모집이 닫혔다면
                                                        // 회차를 바꿔도 열리지
                                                        // 않는다(파티 공통 설정) —
                                                        // 날짜 예외보다 앞에 둔다.
                                                        : genderRecruitBlocked
                                                        ? (PartyGenderRecruit.labelFor(
                                                                data,
                                                                _myGender,
                                                              ) ??
                                                              '모집마감')
                                                        : hasUnpickedOpenDate
                                                        ? '신청하기'
                                                        : occurrenceCancelled
                                                        ? '취소된 회차'
                                                        : deadlinePassed
                                                        ? '모집마감'
                                                        : recruitNotStarted
                                                        ? '${formatPartyDeadlineAt(recruitOpenAt)} 모집 시작'
                                                        : recruitStatus != '모집중'
                                                        ? recruitStatus
                                                        : isFull
                                                        ? '모집 마감'
                                                        : eligibility !=
                                                              PartyEligibility
                                                                  .eligible
                                                        ? eligibilityLabel(
                                                            eligibility,
                                                          )
                                                        // 신청할 수 있는 상태면 언제나 '신청하기'
                                                        // 하나다. 날짜·차수가 남아 있어도 문구를
                                                        // 바꾸지 않는다 — 고를 것이 몇 개인지에
                                                        // 따라 버튼 이름이 흔들리면 사용자가 단계
                                                        // 대신 문구 변화를 좇게 된다. 대신 누르면
                                                        // 필요한 선택만 순서대로 이어서 뜬다
                                                        // (아래 onPressed).
                                                        : '신청하기',
                                                  ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// "위치" 영역의 네이버지도 열기 버튼.
  ///
  /// 지도 카드 안의 초록 NAVER 로고는 SDK가 그리는 법적 공지 버튼이라 지도를
  /// 열지 않는다(그래서 이 화면에서는 클릭을 꺼 뒀다 — [_PartyLocationMap]).
  /// 사용자가 기대하는 "네이버지도로 보기"는 이 버튼이 담당한다.
  Widget _naverMapButton({
    String? placeName,
    required String address,
    double? latitude,
    double? longitude,
  }) {
    const naverGreen = Color(0xFF03C75A);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          // 앱이 있으면 앱으로, 없으면 네이버지도 웹으로 — 판단은 서비스가 한다.
          final ok = await MapDirectionsService.openNaver(
            placeName: placeName,
            address: address,
            latitude: latitude,
            longitude: longitude,
          );
          if (!ok && mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('네이버지도를 열 수 없어요.')));
          }
        },
        icon: const Icon(Icons.map_outlined, size: 18),
        label: const Text('네이버지도로 열기'),
        style: OutlinedButton.styleFrom(
          foregroundColor: naverGreen,
          side: const BorderSide(color: naverGreen),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// 모든 섹션 제목에 공통으로 쓰는 스타일 — FontSize 22 / FontWeight.w700로
  /// 통일한다("한눈에 보기"/"환불 규정"/"모임 소개"/"분위기"/"태그"/"위치" 전부 동일).
  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: PartyChuTitleFont.family,
        fontSize: 19,
        fontWeight: PartyChuTitleFont.medium,
        color: PartyChuColors.heading,
        shadows: [
          Shadow(color: PartyChuColors.heading, offset: Offset(0.3, 0)),
          Shadow(color: PartyChuColors.heading, offset: Offset(-0.3, 0)),
          Shadow(color: PartyChuColors.heading, offset: Offset(0, 0.3)),
          Shadow(color: PartyChuColors.heading, offset: Offset(0, -0.3)),
        ],
      ),
    );
  }

  /// 요약 카드 하단의 보조 정보 한 줄(상세주소/모집마감/나이 제한) — 아이콘
  /// + 제목(회색) + 내용(검정) + 오른쪽 chevron 구조로 통일한다. 내용은
  /// 말줄임 없이 전체 표시(주소처럼 길면 자연스럽게 줄바꿈)하고, 왼쪽
  /// 정렬로 읽기 쉽게 둔다. chevron은 순수 장식(탭 동작 없음) — 기존
  /// 기능은 그대로 유지한다.
  Widget _miniInfoRow(
    IconData icon,
    String title,
    String content, {
    required Color color,
    bool showChevron = true,
    // 모집마감 행의 D-Day 배지처럼, 내용 오른쪽 끝에 고정으로 붙이는 보조
    // 위젯 — content는 Expanded라 아무리 길어져도 이 trailing은 밀려나지
    // 않고 항상 제자리에 남는다.
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF8A8A8A),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            content,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
        if (showChevron) ...[
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            size: 17,
            color: Color(0xFFBFBFBF),
          ),
        ],
      ],
    );
  }

  /// 모집마감일까지 남은 일수 — 시간이 아니라 "달력 날짜" 기준으로
  /// 계산한다(오늘이면 D-Day, 지났으면 마감, 남았으면 D-N).
  String _dDayLabel(DateTime deadline) {
    final now = DateTime.now();
    final deadlineDay = DateTime(deadline.year, deadline.month, deadline.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = deadlineDay.difference(today).inDays;
    if (diff < 0) return '마감';
    if (diff == 0) return 'D-Day';
    return 'D-$diff';
  }

  /// BBQ 파티/페스티벌 등 파티 유형 칩 — 연핑크 배경의 둥근 필로 통일한다.
  List<Widget> _partyTypeChips(Map<String, dynamic> data) {
    final types = (data['partyTypes'] as List?)?.cast<String>() ?? [];
    final fallback = data['category'] as String? ?? '';
    final labels = types.isNotEmpty
        ? types
        : (fallback.isNotEmpty ? [fallback] : []);
    return labels
        .map((t) => _PartyChip(PartyConstants.labelFor(t), value: t))
        .toList();
  }

  /// 모집 상태 배지 — 모집중일 때는 호출부에서 아예 그리지 않고(위
  /// _partyTypeChips 옆 Wrap 참고), 모집마감(및 취소 등 그 외 상태)일 때만
  /// 기존 디자인 그대로 보여준다. 기본 Material 아웃라인 칩 대신 부드러운
  /// 핑크 배경의 필 배지로.
  /// [icon]을 넘기면 상태 문구로 고르는 기본 아이콘 대신 그것을 쓴다
  /// (예: 로그인 전 '로그인 후 모집 상태 확인' 배지의 자물쇠).
  Widget _statusBadge(String status, {IconData? icon}) {
    // 유형 태그와 **같은 칩 껍데기**([_MiniChip])를 쓰고, 뜻이 갈리는
    // 마감/취소만 글자·테두리 색으로 구분한다. 예전처럼 배경까지 채우면
    // 옆에 선 유형 태그와 무게가 달라져 한 줄이 두 디자인으로 보인다.
    // '남성 모집마감'처럼 성별을 밝힌 상태도 마감 색을 쓴다
    // ([PartyGenderRecruit]). 호스트가 보는 '남성 모집마감 · 여성 모집중'
    // 요약도 마찬가지다 — 한쪽이라도 닫혔으면 알림 성격의 상태다.
    final bool isClosed = status == '마감' || status.contains('모집마감');
    return _MiniChip(
      icon:
          icon ??
          (isClosed ? Icons.lock_clock_rounded : Icons.info_outline_rounded),
      text: status,
      foreground: isClosed
          ? PartyChuColors.primaryDeep
          : const Color(0xFF8C8C99),
      borderColor: isClosed ? const Color(0xFFF7C9D8) : const Color(0xFFE6E6EA),
    );
  }

  String _formatDeadline(DateTime dt) {
    final h = dt.hour;
    final period = h < 12 ? '오전' : '오후';
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$period ${hour12.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// 참가 취소 최종 확인창 — 적용된 환불 규정/환불 예정 금액/환불되지 않는
// 금액을 취소 전에 반드시 확인시킨다.
/// 다차수(1차/2차/3차) 파티에서 신청 전 참여할 라운드를 고르는 다이얼로그.
/// 여러 개 중복 선택 가능, 최소 1개는 선택해야 "신청하기"가 활성화된다.
/// perRound 정원 모드에서 이미 꽉 찬 라운드는 체크박스를 비활성화한다.
class _RoundSelectionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> rounds;

  /// 앞 단계(날짜 선택)가 있으면 왼쪽 버튼이 '취소'가 아니라 '이전'이 된다 —
  /// 닫는 동작 자체는 같고([_pickRounds]가 결말을 정한다), 문구만 무슨 일이
  /// 일어나는지에 맞춘다.
  final bool canGoBack;

  const _RoundSelectionDialog({required this.rounds, this.canGoBack = false});

  @override
  State<_RoundSelectionDialog> createState() => _RoundSelectionDialogState();
}

class _RoundSelectionDialogState extends State<_RoundSelectionDialog> {
  final Set<int> _selected = {};

  bool _isRoundFull(Map<String, dynamic> round) {
    final maxCapacity = (round['maxCapacity'] as num?)?.toInt();
    if (maxCapacity == null) return false; // 통합 정원 모드 — 라운드 자체엔 정원 정보 없음
    final maleCapacity = (round['maleCapacity'] as num?)?.toInt() ?? 0;
    final femaleCapacity = (round['femaleCapacity'] as num?)?.toInt() ?? 0;
    if (maleCapacity <= 0 && femaleCapacity <= 0) {
      final current = (round['currentParticipants'] as num?)?.toInt() ?? 0;
      return maxCapacity > 0 && current >= maxCapacity;
    }
    final currentMale = (round['currentMaleCount'] as num?)?.toInt() ?? 0;
    final currentFemale = (round['currentFemaleCount'] as num?)?.toInt() ?? 0;
    final maleFull = maleCapacity <= 0 || currentMale >= maleCapacity;
    final femaleFull = femaleCapacity <= 0 || currentFemale >= femaleCapacity;
    return maleFull && femaleFull;
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h < 12 ? '오전' : '오후';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$period $h12:$m';
  }

  static DateTime? _at(dynamic raw) => raw is Timestamp ? raw.toDate() : null;

  /// 차수 한 건의 모집 창구 상태. 차수별 모집 시작/마감이 없던 예전 문서는
  /// 시작 시각만 보고 판정한다(그때는 문서 전체 마감이 그 역할을 했다).
  PartyRoundStatus? _statusOf(Map<String, dynamic> round) {
    final start = _at(round['time']);
    if (start == null) return null;
    final end = _at(round['endAt']) ?? start.add(const Duration(hours: 2));
    return PartyRoundWindow(
      start: start,
      end: end,
      recruitOpenAt: _at(round['recruitOpenAt']),
      recruitCloseAt: _at(round['recruitCloseAt']),
    ).statusAt(DateTime.now());
  }

  /// 지금 신청할 수 있는 차수인지 — 정원이 찼거나 모집 창구 밖이면 못 고른다.
  bool _isSelectable(Map<String, dynamic> round) {
    if (_isRoundFull(round)) return false;
    final status = _statusOf(round);
    // 상태를 알 수 없는 예전 문서는 예전처럼 정원만 보고 판단한다.
    return status == null || status == PartyRoundStatus.open;
  }

  /// 못 고르는 이유를 한 단어로 — 체크박스 옆에 붙인다.
  String? _blockedLabel(Map<String, dynamic> round) {
    if (_isRoundFull(round)) return '정원 마감';
    final status = _statusOf(round);
    if (status == null || status == PartyRoundStatus.open) return null;
    return status.label;
  }

  /// '모집 8월 3일 (월) 오후 6:00까지' — 언제까지 신청할 수 있는지.
  String _recruitLine(Map<String, dynamic> round) {
    final openAt = _at(round['recruitOpenAt']);
    final closeAt = _at(round['recruitCloseAt']);
    if (openAt == null && closeAt == null) return '';
    if (openAt != null && DateTime.now().isBefore(openAt)) {
      return '모집 ${formatPartyDeadlineAt(openAt)}부터';
    }
    if (closeAt != null) return '모집 ${formatPartyDeadlineAt(closeAt)}까지';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        '참여할 라운드를 선택해주세요',
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
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '여러 개 선택할 수 있어요.',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 4),
            ...widget.rounds.map((r) {
              final roundNumber = (r['roundNumber'] as num?)?.toInt() ?? 0;
              final label = r['label'] as String? ?? '$roundNumber차';
              final start = _at(r['time']);
              final end = _at(r['endAt']);
              final blocked = _blockedLabel(r);
              final selectable = _isSelectable(r);
              // 끝난 차수는 이름에 취소선을 긋는다 — 이유 문구('(종료)')는
              // 그대로 두고 회차명만 긋기 위해 한 줄을 두 조각으로 나눈다.
              final ended = _statusOf(r) == PartyRoundStatus.ended;
              // 시간 줄 — 종료 시각이 있으면 '오후 9:00 ~ 오후 11:00'.
              final timeLine = start == null
                  ? ''
                  : end == null
                  ? _fmtTime(start)
                  : '${_fmtTime(start)} ~ ${_fmtTime(end)}';
              final recruitLine = _recruitLine(r);
              return CheckboxListTile(
                value: _selected.contains(roundNumber),
                enabled: selectable,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFFFF6FA0),
                title: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: label,
                        style: ended
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Colors.black38,
                                decorationThickness: 1.5,
                              )
                            : null,
                      ),
                      if (blocked != null) TextSpan(text: ' ($blocked)'),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selectable ? Colors.black87 : Colors.black38,
                  ),
                ),
                subtitle: (timeLine.isEmpty && recruitLine.isEmpty)
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (timeLine.isNotEmpty)
                            Text(
                              timeLine,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          if (recruitLine.isNotEmpty)
                            Text(
                              recruitLine,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Colors.black45,
                              ),
                            ),
                        ],
                      ),
                onChanged: !selectable
                    ? null
                    : (v) => setState(() {
                        if (v == true) {
                          _selected.add(roundNumber);
                        } else {
                          _selected.remove(roundNumber);
                        }
                      }),
              );
            }),
          ],
        ),
      ),
      actions: [
        if (widget.canGoBack)
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('이전'),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ElevatedButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected.toList()..sort()),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6FA0),
            foregroundColor: Colors.white,
          ),
          // 차수를 고르면 곧바로 신청이 이어지므로, 시작 버튼과 같은
          // '신청하기'로 맞춘다(단계마다 문구가 바뀌지 않게).
          child: const Text('신청하기'),
        ),
      ],
    );
  }
}

class _CancelApplicationDialog extends StatelessWidget {
  final int appliedFee;
  final RefundPreview preview;

  const _CancelApplicationDialog({
    required this.appliedFee,
    required this.preview,
  });

  static String _fmt(int v) => formatAmount(v);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        '참가 신청을 취소하시겠습니까?',
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (appliedFee > 0) ...[
            _row(
              '적용된 환불 규정',
              preview.policyMissing
                  ? '호스트가 환불 규정을 등록하지 않았어요'
                  : preview.matchedTier != null
                  ? '파티 시작 ${preview.matchedTier!.daysBefore}일 전부터 '
                        '${preview.matchedTier!.refundPercent}% 환불'
                  : '해당하는 환불 구간이 없어요',
            ),
            const SizedBox(height: 8),
            _row(
              '환불 예정 금액',
              _fmt(preview.refundAmount),
              valueColor: const Color(0xFFFF6FA0),
            ),
            const SizedBox(height: 4),
            _row('환불되지 않는 금액', _fmt(preview.nonRefundableAmount)),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '무료 파티라 환불 없이 참가 취소만 처리돼요.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
          const Text(
            '취소하면 되돌릴 수 없어요.',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('돌아가기'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('신청 취소'),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

// ── 블록형 상세페이지 — 상세페이지/글만보기 전환 ───────────────────────────
// 토글 상태를 이 작은 서브트리 안에만 둬서, 전환할 때마다 부모의
// StreamBuilder(파티 문서 구독)가 다시 빌드되지 않게 한다 — 그래야 화면
// 전체가 다시 로딩되지 않고 스크롤 위치도 튀지 않는다. 선택되지 않은
// 렌더러는 아예 빌드하지 않으므로(둘 다 숨겨서 유지하지 않음), 글만 보기가
// 아니면 사진 블록의 Image.network가 생성되지 않는다.
class _DetailBlockSection extends StatefulWidget {
  final List<PartyDetailBlock> blocks;
  final PartyDetailThemeKey theme;
  final PartyDetailDecorationIntensity intensity;

  /// "디자인 새로고침"으로 호스트가 고른 배경/구분 장식 변형 — 필드가 없는
  /// 기존 파티는 0(항상 지금까지와 동일한 배치).
  final int variantSeed;
  final void Function(PartyDetailBlock block) onImageTap;
  final String partyId;

  const _DetailBlockSection({
    required this.blocks,
    required this.theme,
    required this.intensity,
    this.variantSeed = 0,
    required this.onImageTap,
    required this.partyId,
  });

  @override
  State<_DetailBlockSection> createState() => _DetailBlockSectionState();
}

class _DetailBlockSectionState extends State<_DetailBlockSection> {
  // 초기 임시 기본값 — SharedPreferences 로딩이 끝나기 전까지는 이 값으로
  // 그린다(디자인 보기가 항상 유효한 선택이므로 깜빡임 없이 자연스럽다).
  PartyDetailViewMode _mode = PartyDetailViewMode.designed;

  @override
  void initState() {
    super.initState();
    // SharedPreferences는 initState에서 한 번만 불러온다(build()에서 반복
    // 호출하지 않음). 로딩이 끝나기 전에는 위 임시 기본값(designed)이 그대로
    // 화면에 남아 있어 깜빡임이 없다.
    PartyDetailViewMode.load().then((loaded) {
      if (!mounted) return;
      if (loaded == _mode) return; // 같은 값이면 불필요한 setState 생략
      setState(() => _mode = loaded);
    });
  }

  void _select(PartyDetailViewMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode); // 먼저 즉시 화면에 반영
    unawaited(mode.save()); // 저장은 비동기로 — 실패해도 화면 동작에는 영향 없음
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailBlockViewToggle(
          currentMode: _mode,
          theme: widget.theme,
          onChanged: _select,
        ),
        const SizedBox(height: 16),
        switch (_mode) {
          PartyDetailViewMode.designed => PartyDetailBlockPreview(
            blocks: widget.blocks,
            theme: widget.theme,
            intensity: widget.intensity,
            variantSeed: widget.variantSeed,
            onImageTap: widget.onImageTap,
            partyId: widget.partyId,
          ),
          PartyDetailViewMode.textOnly => PartyDetailBlockTextView(
            blocks: widget.blocks,
            theme: widget.theme,
            partyId: widget.partyId,
          ),
        },
      ],
    );
  }
}

/// "[ 상세페이지 ] [ 글만보기 ]" 세그먼트 토글. 선택 상태를 배경색뿐 아니라
/// 글자 굵기로도 구분해(색만으로 구분하지 않음) 접근성을 확보한다. 선택된
/// 파티의 [theme]에 맞춰 강조색/트랙 배경을 그대로 반영한다.
class _DetailBlockViewToggle extends StatelessWidget {
  final PartyDetailViewMode currentMode;
  final PartyDetailThemeKey theme;
  final ValueChanged<PartyDetailViewMode> onChanged;

  const _DetailBlockViewToggle({
    required this.currentMode,
    required this.theme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = PartyDetailThemeRegistry.fromKey(theme);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.tabTrackBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _segment(palette, PartyDetailViewMode.designed)),
          Expanded(child: _segment(palette, PartyDetailViewMode.textOnly)),
        ],
      ),
    );
  }

  Widget _segment(
    PartyDetailThemeData palette,
    PartyDetailViewMode segmentMode,
  ) {
    final selected = currentMode == segmentMode;
    final segment = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: selected ? palette.selectedTabBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        segmentMode.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          color: selected
              ? palette.selectedTabForeground
              : palette.unselectedTabForeground,
        ),
      ),
    );

    return GestureDetector(
      onTap: () => onChanged(segmentMode),
      behavior: HitTestBehavior.opaque,
      child: segment,
    );
  }
}

// ── 위치 지도 ────────────────────────────────────────────────────────────
class _PartyLocationMap extends StatefulWidget {
  final double latitude;
  final double longitude;

  const _PartyLocationMap({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<_PartyLocationMap> createState() => _PartyLocationMapState();
}

class _PartyLocationMapState extends State<_PartyLocationMap> {
  @override
  Widget build(BuildContext context) {
    return NaverMap(
      options: NaverMapViewOptions(
        initialCameraPosition: NCameraPosition(
          target: NLatLng(widget.latitude, widget.longitude),
          zoom: 15,
        ),
        scrollGesturesEnable: true,
        zoomGesturesEnable: true,
        tiltGesturesEnable: false,
        rotationGesturesEnable: false,
        // 지도 왼쪽 아래 초록색 NAVER 로고는 SDK가 그리는 것이고, 기본값
        // (logoClickEnable: true)이면 누를 때 SDK 법적 공지 다이얼로그
        // (flutter_naver_map / Naver Map SDK / 오픈소스 라이선스)가 뜬다.
        // 이 카드에서는 그 로고가 "네이버지도 열기" 버튼처럼 보여 실제로 그렇게
        // 눌렸다 — 여기서는 클릭만 끄고(로고 표시는 약관대로 유지), 지도를
        // 열려면 아래 "네이버지도로 열기" 버튼을 쓴다.
        //
        // 법적 공지 자체는 로고 클릭이 살아 있는 전체 지도 화면(map_screen.dart)
        // 에서 그대로 볼 수 있다.
        logoClickEnable: false,
      ),
      onMapReady: (controller) async {
        await controller.addOverlay(
          NMarker(
            id: 'party_location',
            position: NLatLng(widget.latitude, widget.longitude),
          ),
        );
      },
    );
  }
}

/// 신청 직전 "날짜를 먼저 골라주세요" 시트의 한 줄 — 라디오 + 날짜
/// (+ 못 고르는 이유). 시트는 폭이 넉넉해 목록형이 읽기 편하다.
///
/// 같은 게시글의 날짜 문서 하나가 곧 일정 하나다([PartyScheduleOption]).
class _ScheduleOptionTile extends StatelessWidget {
  final PartyScheduleOption option;
  final bool selected;
  final VoidCallback? onTap;

  const _ScheduleOptionTile({
    required this.option,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final blocked = option.blockedReason;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF0F5) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? PartyChuColors.primary : const Color(0xFFE8EBF2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: onTap == null
                  ? Colors.black26
                  : (selected ? PartyChuColors.primary : Colors.black38),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                // 날짜만 — '2026년 8월 10일 (월)'. 시작·종료 시각은 다음
                // 단계(차수 선택)에서 차수별로 다시 보여준다.
                option.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: onTap == null
                      ? Colors.black38
                      : const Color(0xFF2D3748),
                ),
              ),
            ),
            if (blocked != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  blocked,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── 요약 카드 대시보드 타일 ─────────────────────────────────────────────
// 날짜·장소·참여 인원·참가비를 2x2로 배치하는 "한눈에 보기" 카드에서
// 각 칸을 그리는 공통 조각. 핑크 원형 배지 안의 아이콘 + 위에 라벨,
// 아래에 값이라는 동일한 구조를 4칸 모두에 재사용해 대시보드다운 통일감을
// 준다.
class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final Widget value;
  final Widget? sub;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    // 아이콘 → 라벨 → 값 → 보조 정보 순으로 세로 중앙 정렬한다. 배경 원
    // 없이 아이콘 자체만 파스텔 컬러로 그리고(미니멀), 값/보조 정보는
    // 가운데 정렬만 하고 maxLines/ellipsis는 강제하지 않는다 — 실제
    // 데이터가 길면 그만큼 줄바꿈되고, 그 높이만큼 부모(IntrinsicHeight
    // Row)와 카드 전체가 자동으로 늘어난다.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 21, color: color),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF8A8A8A),
          ),
        ),
        const SizedBox(height: 4),
        DefaultTextStyle.merge(
          textAlign: TextAlign.center,
          style: _PartyDetailScreenState._tileValueStyle,
          child: value,
        ),
        if (sub != null) ...[const SizedBox(height: 3), sub!],
      ],
    );
  }
}

// 파티 유형(BBQ 파티/페스티벌 등) 칩 — "White Pearl Gloss Tag + Thin Double
// Pink Border". 로고의 흰색 글로스·핑크 테두리를 축소해서 옮긴 느낌으로,
// 강한 네온 핑크 테두리·핑크 글씨·넓은 Glow 대신 얇은 이중 테두리(바깥
// 연핑크 1px + 안쪽 반투명 흰색 1px)와 은은한 상단 광택만 쓴다.
// ─────────────────────────────────────────────────────────────────────────────
// 상세 상단 칩 — 파티 유형 태그와 모집 상태 배지가 **한 껍데기**를 공유한다.
//
// 예전에는 둘이 완전히 다른 모양이었다. 유형 태그는 높이 37에 이중 링 + 유광
// 그라디언트 + 그림자까지 얹은 "버튼 같은" 칩이라 바로 아래 제목보다 시선을
// 먼저 끌었고, 상태 배지는 그냥 평평한 핑크 필이라 둘이 한 화면에 있으면 서로
// 다른 앱에서 온 것처럼 보였다.
//
// 지금은 [_MiniChip] 하나로 통일한다 — 높이 29, 연핑크 1px 테두리, 흰 배경,
// 그림자·유광 없음. 태그는 제목보다 한 단계 아래 정보이므로 글자도 Medium
// 굵기의 진회색으로 낮춘다. 상태 배지는 같은 껍데기를 쓰되 뜻이 갈리는
// 마감/취소만 색으로 구분한다.
//
// 높이를 고정하고 좌우 여백만 두므로, "뮤직 페스티벌"처럼 긴 태그가 와도
// 칩이 세로로 커지지 않고 가로로만 늘어난다.
// ─────────────────────────────────────────────────────────────────────────────

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.text,
    this.emoji,
    this.icon,
    this.leadingWidget,
    this.foreground = _defaultForeground,
    this.borderColor = PartyChuColors.border,
  });

  final String text;

  /// 유형 태그의 이모지("🎵"). [icon]과 함께 쓰지 않는다.
  final String? emoji;

  /// 상태 배지의 아이콘(자물쇠 등). [emoji]와 함께 쓰지 않는다.
  final IconData? icon;

  /// 이모지도 아이콘도 아닌 **이미지**를 앞에 다는 항목('돌싱'). 셋 중
  /// 하나만 쓴다 — 이것이 있으면 나머지 둘보다 앞선다.
  final Widget? leadingWidget;

  final Color foreground;
  final Color borderColor;

  /// 제목(PartyChuColors.heading)보다 한 단계 낮은 진회색 — 태그가 제목보다
  /// 앞서 읽히지 않게 하는 핵심 값이다.
  static const Color _defaultForeground = Color(0xFF6B6B73);

  static const double _height = 29;

  /// 이모지·아이콘을 같은 폭의 상자에 넣어, 글리프마다 다른 원래 폭 때문에
  /// 칩들의 글자 시작선이 들쭉날쭉해지는 것을 막는다.
  static const double _leadingBox = 15;

  @override
  Widget build(BuildContext context) {
    final leading = leadingWidget != null
        ? SizedBox(
            width: _leadingBox,
            child: Center(child: leadingWidget),
          )
        : emoji != null && emoji!.isNotEmpty
        ? SizedBox(
            width: _leadingBox,
            child: Center(
              // 예전 17 → 12.5. 이모지가 글자보다 커서 생기던 "장난감 같은"
              // 인상을 줄이고 텍스트와 같은 눈높이에 두기 위한 크기다.
              child: Text(
                emoji!,
                style: const TextStyle(fontSize: 12.5, height: 1),
              ),
            ),
          )
        : (icon != null
              ? SizedBox(
                  width: _leadingBox,
                  child: Center(
                    child: Icon(icon, size: 12.5, color: foreground),
                  ),
                )
              : null);

    return Container(
      height: _height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_height / 2),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1,
              letterSpacing: -0.1,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// 파티 유형 태그 — 라벨은 "🎭 코스프레"처럼 "이모지 + 공백 + 텍스트"로
/// 저장돼 있어 첫 공백에서 나눈다.
class _PartyChip extends StatelessWidget {
  final String label;

  /// 저장값 원문 — 이미지 아이콘을 붙일 항목인지 가리는 데만 쓴다. 라벨에서
  /// 이모지를 잘라내는 방식으로는 '돌싱'처럼 **글자에 이모지가 없는** 항목을
  /// 알아볼 수 없어서 값이 따로 필요하다.
  final String? value;

  const _PartyChip(this.label, {this.value});

  @override
  Widget build(BuildContext context) {
    final icon = value == null ? null : partyTypeVibeIconFor(value!, size: 13);
    if (icon != null) return _MiniChip(leadingWidget: icon, text: label);
    final spaceIdx = label.indexOf(' ');
    return _MiniChip(
      emoji: spaceIdx > 0 ? label.substring(0, spaceIdx) : null,
      text: spaceIdx > 0 ? label.substring(spaceIdx + 1) : label,
    );
  }
}

// (상세 주소 복사 버튼은 공용 PlaceAddressActions로 통합됐다 —
//  widgets/place_address_row.dart 참고.)

/// 오픈예정 파티의 하단 바 — 신청 버튼 대신 "오픈 알림 받기" 하나만 둔다.
///
/// 알림 신청은 `partyOpenAlerts` 컬렉션의 문서 하나(id: "{uid}_{partyId}")로
/// 저장되고, 호스트가 모집을 오픈하는 순간 서버가 그 문서를 조회해 기존
/// notifications 알림을 **파티당 한 번만** 보낸다. 다시 누르면 취소된다.
class _PreopenAlertBar extends StatefulWidget {
  const _PreopenAlertBar({
    required this.partyId,
    required this.loggedOut,
    required this.dateTbd,
  });

  final String partyId;
  final bool loggedOut;
  final bool dateTbd;

  @override
  State<_PreopenAlertBar> createState() => _PreopenAlertBarState();
}

class _PreopenAlertBarState extends State<_PreopenAlertBar> {
  // 토글 요청이 끝나기 전에 다시 눌리는 것을 막는다(찜 버튼과 같은 방식 —
  // 이 프로젝트에서는 일반 사용자 트랜잭션이 막혀 있어 연타 방어를 여기서 한다).
  bool _busy = false;

  // 서버 반영(스트림)이 도착하기 전까지 버튼이 예전 상태로 보이지 않도록
  // 토글 직후 값을 잠깐 덮어쓴다.
  bool? _optimistic;

  Future<void> _toggle() async {
    if (_busy) return;

    if (widget.loggedOut) {
      await Navigator.push(context, webFramedRoute((_) => LoginPage()));
      return;
    }

    setState(() => _busy = true);
    try {
      final now = await PartyOpenAlertService.toggle(widget.partyId);
      if (!mounted) return;
      setState(() => _optimistic = now);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(now ? '오픈하면 알림으로 알려드릴게요.' : '오픈 알림을 취소했어요.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림 신청에 실패했어요. 잠시 후 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: widget.loggedOut
          ? const Stream<bool>.empty()
          : PartyOpenAlertService.watchSubscribed(widget.partyId),
      builder: (context, snap) {
        final subscribed = _optimistic ?? snap.data ?? false;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule_outlined,
                    size: 15,
                    color: Color(0xFF4F46E5),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.dateTbd
                          ? '아직 준비 중인 파티예요. 날짜가 정해지면 모집이 시작돼요.'
                          : '아직 준비 중인 파티예요. 모집이 시작되면 신청할 수 있어요.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF4F46E5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: subscribed
                  ? OutlinedButton.icon(
                      onPressed: _busy ? null : _toggle,
                      icon: const Icon(Icons.notifications_active, size: 18),
                      label: const Text('오픈 알림 신청됨'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4F46E5),
                        side: const BorderSide(color: Color(0xFF4F46E5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _busy ? null : _toggle,
                      icon: const Icon(Icons.notifications_none, size: 18),
                      label: const Text('오픈 알림 받기'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
            if (subscribed)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '다시 누르면 알림을 취소해요.',
                  style: TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ),
          ],
        );
      },
    );
  }
}
