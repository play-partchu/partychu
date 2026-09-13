import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:party_app/models/participant_gender_visibility.dart';
import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/party_round.dart';
import 'package:party_app/models/party_round_package.dart';
import 'package:party_app/utils/format_utils.dart';

/// 다차수 파티에서 사용자가 고를 수 있는 **판매 단위 하나** — 차수 하나이거나
/// 여러 차수를 묶은 패키지다.
///
/// ## 이 파일이 존재하는 이유
///
/// 차수 시간·참가비 계산이 화면마다 따로 있으면(상세 / 신청 시트 / 요약 /
/// 참가자 목록) 같은 파티가 화면마다 다른 금액을 보여주게 된다. 실제로 예전에는
/// 신청 시트에 참가비가 아예 없었고, 상세에는 차수 정보가 없었다.
///
/// 그래서 "이 파티에서 무엇을 얼마에 팔고 있는가"를 파티 문서 하나로부터
/// 계산하는 곳을 여기 하나만 둔다([PartyRoundOffers.of]). 화면은 목록을 받아
/// 그리기만 한다.
///
/// 금액 표시는 앱 공통 [formatPrice]("3만원"·"2.5만원"·"무료")를 쓴다 —
/// 저장·결제 금액은 언제나 원 단위 정수 그대로이고, 여기서 바뀌는 것은 표시
/// 형식뿐이다.
enum PartyRoundOfferKind { round, package }

/// 고를 수 없는 이유 — 있으면 신청 시트에서 비활성으로 그린다.
@immutable
class PartyRoundOffer {
  final PartyRoundOfferKind kind;

  /// 차수는 'r1', 패키지는 패키지 id — 선택 상태 추적용 키.
  final String key;

  /// 패키지일 때만 값이 있다(서버에 그대로 보낸다).
  final String? packageId;

  final String title;

  /// 이 판매 단위가 차지하는 차수 번호들. 차수는 1개, 패키지는 2개 이상.
  final List<int> roundNumbers;

  final DateTime? startAt;
  final DateTime? endAt;

  /// 이 사용자가 낼 정상가.
  final int fee;

  /// 얼리버드가 지금 유효하면 그 금액, 아니면 [fee]와 같다.
  final int effectiveFee;

  /// 남녀 금액이 다를 때만 값이 있다(상세에서 "남 3만원 · 여 2만원").
  final int? maleFee;
  final int? femaleFee;

  /// 패키지일 때 — 포함 차수를 개별로 신청했을 때의 합계(참고값).
  final int? individualTotal;

  /// 고를 수 없는 이유('정원 마감', '모집 마감' 등). null이면 선택 가능.
  final String? blockedReason;

  /// 이 차수의 시간이 **이미 지났는지**. 화면은 이 값으로 회차명에 취소선을
  /// 긋는다.
  ///
  /// [blockedReason]과 따로 두는 이유: 못 고르는 이유는 '정원 마감'·'모집
  /// 마감'처럼 아직 시작도 안 한 차수에도 붙는다. 반대로 정원이 찬 채로 끝난
  /// 차수는 이유가 '정원 마감'으로 남지만 실제로는 끝난 차수다 — 문구 하나로
  /// 두 가지를 판단하면 어느 쪽이든 틀린다.
  final bool ended;

  /// 남은 자리. 정원 제한이 없으면 null(표시하지 않는다).
  ///
  /// 정기 파티는 **고른 회차의** 잔여다 — 차수 정원이 회차별로 독립이라
  /// 8/15 1차가 찼어도 8/22 1차는 그대로 남아 있다.
  /// 패키지는 포함 차수 중 가장 적게 남은 쪽이 곧 살 수 있는 수다.
  final int? remaining;

  const PartyRoundOffer({
    required this.kind,
    required this.key,
    required this.title,
    required this.roundNumbers,
    required this.fee,
    required this.effectiveFee,
    this.packageId,
    this.startAt,
    this.endAt,
    this.maleFee,
    this.femaleFee,
    this.individualTotal,
    this.blockedReason,
    this.ended = false,
    this.remaining,
  });

  /// '2자리 남음' — 정원 제한이 없거나 이미 못 고르는 판매 단위는 빈 문자열.
  String get remainingLabel {
    final left = remaining;
    if (left == null || !selectable) return '';
    return '$left자리 남음';
  }

  bool get isPackage => kind == PartyRoundOfferKind.package;
  bool get selectable => blockedReason == null;
  bool get earlyBirdOn => effectiveFee < fee;
  bool get hasGenderedFee => maleFee != null && femaleFee != null;

  /// 패키지가 개별 합계보다 얼마나 싼지. 0 이하면 할인 표기를 하지 않는다.
  int get discount {
    final total = individualTotal;
    if (total == null) return 0;
    final diff = total - effectiveFee;
    return diff > 0 ? diff : 0;
  }

  /// '오후 7:00 ~ 오후 9:00' / 종료가 없으면 '오후 7:00'. 시각이 없으면 빈 문자열.
  String get timeLabel {
    final s = startAt;
    if (s == null) return '';
    final e = endAt;
    return e == null ? _fmtTime(s) : '${_fmtTime(s)} ~ ${_fmtTime(e)}';
  }

  /// '3만원' / '무료' — 얼리버드가 걸려 있으면 할인가 기준이다.
  String get feeLabel => formatPrice(effectiveFee);

  /// 남녀 금액이 다를 때 쓰는 '남 3만원 · 여 2만원'. 아니면 빈 문자열.
  String get genderedFeeLabel {
    if (!hasGenderedFee) return '';
    return '남 ${formatPrice(maleFee!)} · 여 ${formatPrice(femaleFee!)}';
  }

  static String _fmtTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h < 12 ? '오전' : '오후';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$period $h12:$m';
  }
}

/// 파티 문서 하나에서 [PartyRoundOffer] 목록을 뽑아내는 곳.
class PartyRoundOffers {
  PartyRoundOffers._();

  /// 이 파티가 "차수별 판매"를 하는지 — 차수 패키지·차수별 참가비가 의미를 갖는
  /// 유일한 조건이다.
  ///
  /// 통합 정원 모드(`unified`)는 모든 차수가 문서 최상단의 정원·참가비 하나를
  /// 공유하므로 차수별 금액이라는 개념이 없고, 패키지도 만들 수 없다
  /// (정원을 차수별로 1명씩 차감할 대상이 없다 — 서버도 같은 기준으로 막는다).
  static bool isPerRound(Map<String, dynamic> data) =>
      data['hasMultipleRounds'] == true &&
      (data['roundCapacityMode'] as String?) == 'perRound';

  /// 차수 배열 원소들(정렬됨).
  static List<Map<String, dynamic>> roundsOf(Map<String, dynamic> data) {
    final raw = data['rounds'];
    if (raw is! List) return const [];
    final list = raw
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    list.sort(
      (a, b) => ((a['roundNumber'] as num?)?.toInt() ?? 0).compareTo(
        (b['roundNumber'] as num?)?.toInt() ?? 0,
      ),
    );
    return list;
  }

  /// 상세·신청 시트·요약이 공유하는 판매 목록. 차수들이 먼저, 패키지가 뒤에 온다.
  ///
  /// [gender]가 'male'/'female'이면 그 성별 금액으로, 모르면 낮은 쪽(최소
  /// 참가비)으로 계산한다 — 실제 결제 금액은 신청 시점에 서버가 다시 계산한다.
  ///
  /// [occurrenceStart]는 **이 목록이 어느 날짜의 파티를 말하는지**다(정기
  /// 파티는 사용자가 고른 회차, 일회성은 그 파티의 날짜). 차수 시각은 이 날짜를
  /// 기준으로 매번 다시 계산된다 — 이유는 [_windowOf] 참고. 넘기지 않으면
  /// 문서에 저장된 절대 시각을 그대로 쓴다(예전 동작).
  /// 정기 파티의 **회차별 차수 인원** 칸을 각 차수 정의에 덮어씌운다.
  ///
  /// 차수 정원·참가비·시간 규칙의 정의는 문서 최상단 `rounds[]` 하나뿐이고,
  /// 인원만 `occurrenceStats.{회차}.rounds.{차수}`에 회차별로 따로 쌓인다
  /// (functions/partyCapacity.js). 그래서 화면은 정의를 그대로 쓰되 인원만
  /// 그 회차 값으로 갈아끼우면 된다 — 잔여 정원·'정원 마감' 판정이 전부
  /// 이 인원을 보므로, 여기 한 곳만 바꾸면 아래 계산이 전부 회차 기준이 된다.
  ///
  /// 회차 칸이 아직 없으면(아무도 신청하지 않은 회차) **0에서 시작한다** —
  /// 최상단 누적값을 그대로 쓰면 아무도 없는 회차가 만석으로 보인다.
  static List<Map<String, dynamic>> _withOccurrenceCounts(
    List<Map<String, dynamic>> rounds,
    Map<String, dynamic>? occurrenceRounds,
  ) {
    if (occurrenceRounds == null) return rounds;
    return [
      for (final r in rounds)
        () {
          final raw = occurrenceRounds['${_numberOf(r)}'];
          final counts = raw is Map ? Map<String, dynamic>.from(raw) : const {};
          return {
            ...r,
            'currentParticipants': (counts['currentParticipants'] as num?) ?? 0,
            'currentMaleCount': (counts['currentMaleCount'] as num?) ?? 0,
            'currentFemaleCount': (counts['currentFemaleCount'] as num?) ?? 0,
          };
        }(),
    ];
  }

  /// 파티 문서에서 [occurrenceId] 회차의 차수 인원 칸을 꺼낸다.
  /// 정기 파티가 아니거나 회차를 모르면 null(= 최상단 인원을 그대로 쓴다).
  ///
  /// **읽기 전용이다.** 이 칸을 쓰는 것은 서버뿐이고(functions/partyCapacity.js의
  /// reserve/releaseApplicantSlot), 앱은 화면에 그릴 인원·잔여를 읽기만 한다.
  /// 정원 판정의 정본도 서버다 — 여기 계산은 사용자가 꽉 찬 차수를 고르고
  /// 결제까지 갔다가 거절당하는 헛걸음을 줄이는 용도다.
  static Map<String, dynamic>? occurrenceRoundsOf(
    Map<String, dynamic> data,
    String? occurrenceId,
  ) {
    if (occurrenceId == null) return null;
    final stats = data['occurrenceStats'];
    if (stats is! Map) return null;
    final stat = stats[occurrenceId];
    // 회차 칸 자체가 없어도 **빈 map**을 돌려준다 — 최상단 누적으로 폴백하면
    // 안 되기 때문이다(아무도 신청하지 않은 회차는 0명이 정답이다).
    if (stat is! Map) return const {};
    final rounds = stat['rounds'];
    return rounds is Map ? Map<String, dynamic>.from(rounds) : const {};
  }

  static List<PartyRoundOffer> of(
    Map<String, dynamic> data, {
    String? gender,
    DateTime? now,
    DateTime? occurrenceStart,
    String? occurrenceId,
  }) {
    if (!isPerRound(data)) return const [];
    final at = now ?? DateTime.now();
    final rounds = _withOccurrenceCounts(
      roundsOf(data),
      occurrenceRoundsOf(data, occurrenceId),
    );
    if (rounds.isEmpty) return const [];

    // 차수 번호 → 그 회차에 실제로 잡히는 일정. 차수와 패키지가 **같은 창구**를
    // 보도록 한 번만 계산해서 둘 다 이걸 쓴다.
    final windows = <int, PartyRoundWindow>{};
    for (final r in rounds) {
      final w = windowOf(r, occurrenceStart);
      if (w != null) windows[_numberOf(r)] = w;
    }

    final offers = <PartyRoundOffer>[
      for (final r in rounds)
        _roundOffer(
          r,
          window: windows[_numberOf(r)],
          gender: gender,
          now: at,
          data: data,
        ),
    ];

    final byNumber = <int, Map<String, dynamic>>{
      for (final r in rounds) _numberOf(r): r,
    };
    for (final pkg in PartyRoundPackage.listFrom(data['roundPackages'])) {
      final offer = _packageOffer(
        pkg,
        byNumber,
        windows: windows,
        roundOffers: offers,
        gender: gender,
        now: at,
      );
      if (offer != null) offers.add(offer);
    }
    return offers;
  }

  /// 버튼 위에 붙이는 한 줄 요약 — '1차 3만원 · 2차 2.5만원 · 패키지 4.5만원'.
  /// 판매 단위가 2개 미만이면 빈 문자열(요약할 게 없다).
  static String summaryLine(
    Map<String, dynamic> data, {
    String? gender,
    DateTime? now,
    DateTime? occurrenceStart,
    String? occurrenceId,
  }) {
    final offers = of(
      data,
      gender: gender,
      now: now,
      occurrenceStart: occurrenceStart,
      occurrenceId: occurrenceId,
    );
    if (offers.length < 2) return '';
    return offers.map((o) => '${o.title} ${o.feeLabel}').join(' · ');
  }

  static int _numberOf(Map<String, dynamic> round) =>
      (round['roundNumber'] as num?)?.toInt() ?? 0;

  /// 이 차수가 [date]의 회차에서 실제로 잡히는 일정.
  ///
  /// **`rounds[].time`을 그대로 믿으면 안 된다.** 그 값은 등록 시점의 날짜 하나로
  /// 굳어 있는 캐시라서, 정기 파티의 두 번째 회차부터는(그리고 날짜만 바꿔
  /// 재등록한 문서에서는) 이미 지나간 시각을 가리킨다 — 아직 열리지도 않은
  /// 차수가 '종료'로 표시되던 원인이다. 문서 전체의 `recruitDeadlineAt`을 정기
  /// 파티에 저장하지 않는 것과 같은 이유이고, 차수도 같은 처리를 받아야 한다.
  ///
  /// 그래서 시각과 모집 규칙만 [PartyRound.fromMap]으로 되살리고(새 문서는
  /// `startTime`/`recruitCloseRule` 등에서, 예전 문서는 `time`/`endAt`의 시:분에서
  /// 폴백된다) 날짜는 [date]로 갈아끼운다([PartyRound.resolveOn]). 저장된 값의
  /// 모양과 무관하므로 **데이터 마이그레이션 없이** 예전 문서도 그대로 동작한다.
  ///
  /// [date]가 null인 경우(회차를 알 수 없는 호출부, 더 열릴 회차가 없는 정기
  /// 파티)에만 저장된 절대 시각을 그대로 쓴다.
  ///
  /// "이 일정이 끝났는가" 판정([PartyTimeline])도 같은 계산을 쓴다 — 차수 종료
  /// 시각이 화면(차수 및 참가비)과 지난 일정 판정에서 따로 계산되면 두 곳이
  /// 어긋난다.
  static PartyRoundWindow? windowOf(
    Map<String, dynamic> round,
    DateTime? date,
  ) {
    if (date != null) {
      final parsed = PartyRound.fromMap(round);
      if (parsed != null) return parsed.resolveOn(date);
    }
    final start = _at(round['time']);
    if (start == null) return null;
    return PartyRoundWindow(
      start: start,
      end: _at(round['endAt']) ?? start.add(const Duration(hours: 2)),
      recruitOpenAt: _at(round['recruitOpenAt']),
      recruitCloseAt: _at(round['recruitCloseAt']),
    );
  }

  static PartyRoundOffer _roundOffer(
    Map<String, dynamic> round, {
    required PartyRoundWindow? window,
    String? gender,
    required DateTime now,
    Map<String, dynamic> data = const {},
  }) {
    final number = _numberOf(round);
    final start = window?.start;
    // 종료 시각을 따로 저장하지 않은 예전 문서는 창구 계산에서만 '시작+2시간'을
    // 가정하고, 화면에는 예전처럼 시작 시각만 보여준다(없는 값을 지어내지 않는다).
    final end = _at(round['endAt']) == null && round['endTime'] == null
        ? null
        : window?.end;
    // 참가비는 **차수 자신의 값이 정본**이다. 차수별 참가비를 저장하기 전에
    // 만들어진 라운드 파티는 1차 가격이 문서 최상단에만 있으므로, 차수에 값이
    // 아예 없을 때만 그 값으로 폴백한다(0원으로 보이지 않게).
    // 서버 computeAppliedFeeForRounds와 같은 규칙이다.
    final hasOwnFee = round['maleFee'] != null || round['femaleFee'] != null;
    final male =
        ((hasOwnFee ? round['maleFee'] : data['maleFee']) as num?)?.toInt() ??
        0;
    final female =
        ((hasOwnFee ? round['femaleFee'] : data['femaleFee']) as num?)
            ?.toInt() ??
        0;
    final fee = _feeFor(gender, male: male, female: female);

    // 차수 얼리버드는 그 차수 자신의 시작 시각·규칙으로 계산한다 — 서버
    // partyCapacity.js의 applyRoundEarlyBird와 같은 기준이다. 얼리버드 필드가
    // 아예 없는 차수만 문서 최상단 규칙으로 폴백한다(필드가 있고 false면 그
    // 차수는 할인을 끈 것이므로 폴백하지 않는다).
    final ebSource = round['earlyBirdEnabled'] != null ? round : data;
    var effective = fee;
    if (fee > 0 && ebSource['earlyBirdEnabled'] == true && start != null) {
      final endAt = resolveEarlyBirdEndAt(ebSource, occurrenceStart: start);
      if (endAt != null && endAt.isAfter(now)) {
        final pct =
            (ebSource['earlyBirdDiscountPercent'] as num?)?.toInt() ?? 0;
        final discounted = (fee * (100 - pct) / 100).round();
        effective = discounted < 0 ? 0 : discounted;
      }
    }

    final block = _roundBlock(round, window: window, gender: gender, now: now);

    return PartyRoundOffer(
      kind: PartyRoundOfferKind.round,
      key: 'r$number',
      title: (round['label'] as String?)?.trim().isNotEmpty == true
          ? round['label'] as String
          : '$number차',
      roundNumbers: [number],
      startAt: start,
      endAt: end,
      fee: fee,
      effectiveFee: effective,
      maleFee: male != female ? male : null,
      femaleFee: male != female ? female : null,
      blockedReason: block.reason,
      ended: block.ended,
      // 성비를 감춘 파티에서는 **내 성별 기준 잔여**를 쓰지 않는다 — 남자
      // 정원 10에 '2자리 남음'이면 남자 참가자가 8명이라는 뜻이고, 화면에
      // 함께 뜨는 총 인원(8/20)과 맞추면 여자 인원까지 그대로 드러난다.
      // 대신 총 잔여를 적는다(그 값은 이미 보이는 8/20에서 나오는 수라
      // 새로 알려주는 것이 없다). 신청 가능 여부 판정은 이 값이 아니라
      // 성별을 그대로 보는 [_isRoundFull]이 하므로 막히는 조건은 그대로다.
      remaining: _roundRemaining(
        round,
        gender: ParticipantGenderVisibility.of(data) ? gender : null,
      ),
    );
  }

  /// 이 차수에 남은 자리. 정원이 0(제한 없음)이면 null.
  /// 인원은 호출부가 이미 회차 값으로 갈아끼운 [round]에서 읽는다.
  static int? _roundRemaining(Map<String, dynamic> round, {String? gender}) {
    int intOf(String k) => (round[k] as num?)?.toInt() ?? 0;
    final maleCapacity = intOf('maleCapacity');
    final femaleCapacity = intOf('femaleCapacity');
    if (maleCapacity > 0 || femaleCapacity > 0) {
      // 남녀별 정원 — 내 성별 자리만 의미가 있다. 성별을 모르면 합계로 본다.
      if (gender == 'male') {
        return (maleCapacity - intOf('currentMaleCount')).clamp(0, 1 << 30);
      }
      if (gender == 'female') {
        return (femaleCapacity - intOf('currentFemaleCount')).clamp(0, 1 << 30);
      }
      final left =
          (maleCapacity + femaleCapacity) -
          (intOf('currentMaleCount') + intOf('currentFemaleCount'));
      return left.clamp(0, 1 << 30);
    }
    final max = intOf('maxCapacity');
    if (max <= 0) return null; // 0 = 제한 없음
    final current = intOf('currentParticipants') != 0
        ? intOf('currentParticipants')
        : intOf('currentMaleCount') + intOf('currentFemaleCount');
    return (max - current).clamp(0, 1 << 30);
  }

  static PartyRoundOffer? _packageOffer(
    PartyRoundPackage pkg,
    Map<int, Map<String, dynamic>> byNumber, {
    required Map<int, PartyRoundWindow> windows,
    required List<PartyRoundOffer> roundOffers,
    String? gender,
    required DateTime now,
  }) {
    final numbers = pkg.normalizedRoundNumbers;
    // 차수가 사라진 패키지는 아예 보여주지 않는다 — 신청해도 서버가 막는다.
    if (numbers.any((n) => !byNumber.containsKey(n))) return null;

    final fee = pkg.feeFor(gender);
    var effective = fee;
    // 포함 차수와 **같은 회차 기준**으로 계산된 시각을 쓴다(문서의 절대 시각이
    // 아니다) — 그래야 얼리버드 종료도 차수 쪽과 어긋나지 않는다.
    final firstStart = windows[numbers.first]?.start;
    if (fee > 0 && pkg.earlyBirdEnabled) {
      // 패키지 얼리버드는 **별도 판매가**다(개별 차수 할인 합산이 아니다).
      final endAt = pkg.resolveEarlyBirdEndAt(firstStart);
      if (endAt != null && endAt.isAfter(now)) {
        final ebFee = pkg.earlyBirdFeeFor(gender);
        if (ebFee > 0 && ebFee < fee) effective = ebFee;
      }
    }

    // 포함 차수를 개별로 신청했을 때의 합계 — 얼리버드까지 반영한 실제 금액
    // 기준으로 비교해야 "10,000원 할인"이 사실과 맞는다.
    final individual = roundOffers
        .where((o) => numbers.contains(o.roundNumbers.first))
        .fold<int>(0, (total, o) => total + o.effectiveFee);

    // 포함된 차수 중 하나라도 못 고르면 패키지도 못 고른다(정원·모집 창구).
    final blocked = numbers
        .map((n) => roundOffers.firstWhere((o) => o.roundNumbers.first == n))
        .where((o) => !o.selectable)
        .toList();

    final ends = numbers
        .map((n) => windows[n]?.end)
        .whereType<DateTime>()
        .toList();

    return PartyRoundOffer(
      kind: PartyRoundOfferKind.package,
      key: pkg.id,
      packageId: pkg.id,
      title: pkg.displayName,
      roundNumbers: numbers,
      startAt: firstStart,
      endAt: ends.isEmpty ? null : ends.reduce((a, b) => a.isAfter(b) ? a : b),
      fee: fee,
      effectiveFee: effective,
      maleFee: pkg.hasGenderedFee ? pkg.maleFee : null,
      femaleFee: pkg.hasGenderedFee ? pkg.femaleFee : null,
      individualTotal: individual > 0 ? individual : null,
      blockedReason: blocked.isEmpty
          ? null
          : '${blocked.first.title} ${blocked.first.blockedReason}',
      // 포함 차수가 하나라도 끝났으면 이 패키지는 더 이상 살 수 없다 —
      // 남은 차수가 있어도 "1+2차"를 다 갈 수는 없으므로 끝난 것으로 본다.
      ended: blocked.any((o) => o.ended),
      // 패키지는 포함 차수를 **전부** 잡아야 하므로, 가장 적게 남은 차수가
      // 곧 이 패키지로 살 수 있는 수다.
      remaining: () {
        final lefts = numbers
            .map(
              (n) => roundOffers
                  .firstWhere((o) => o.roundNumbers.first == n)
                  .remaining,
            )
            .whereType<int>()
            .toList();
        return lefts.isEmpty ? null : lefts.reduce((a, b) => a < b ? a : b);
      }(),
    );
  }

  static int _feeFor(String? gender, {required int male, required int female}) {
    if (gender == 'male') return male;
    if (gender == 'female') return female;
    final values = [male, female].where((v) => v > 0).toList();
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a < b ? a : b);
  }

  /// 차수 하나를 지금 고를 수 있는지 — 정원과 모집 창구를 본다. 끝난 차수인지도
  /// 함께 돌려준다([PartyRoundOffer.ended]).
  ///
  /// 판정 규칙은 서버 `partyCapacity.js`(roundMaxCapacityOf/isRoundRecruitOpen)와
  /// 같은 기준이다.
  ///
  /// 표시 이유는 정원이 우선이다('정원 마감'이 왜 못 고르는지를 더 잘 설명한다).
  /// 다만 종료 여부는 정원과 무관하게 시간으로만 판정한다 — 정원이 찬 채로 끝난
  /// 차수도 끝난 차수다.
  static ({String? reason, bool ended}) _roundBlock(
    Map<String, dynamic> round, {
    required PartyRoundWindow? window,
    String? gender,
    required DateTime now,
  }) {
    final full = _isRoundFull(round, gender: gender);
    // 시각을 모르는 예전 문서는 시간으로 막지 않는다(정원만 본다).
    if (window == null) return (reason: full ? '정원 마감' : null, ended: false);
    final status = window.statusAt(now);
    final ended = status == PartyRoundStatus.ended;
    if (full) return (reason: '정원 마감', ended: ended);
    return (
      reason: status == PartyRoundStatus.open ? null : status.label,
      ended: ended,
    );
  }

  /// 남녀별 정원이 있으면 그 성별 자리만 보고, 없으면 전체 인원으로 판정한다.
  static bool _isRoundFull(Map<String, dynamic> round, {String? gender}) {
    final maleCapacity = (round['maleCapacity'] as num?)?.toInt() ?? 0;
    final femaleCapacity = (round['femaleCapacity'] as num?)?.toInt() ?? 0;
    final separate = maleCapacity > 0 || femaleCapacity > 0;
    if (separate) {
      final currentMale = (round['currentMaleCount'] as num?)?.toInt() ?? 0;
      final currentFemale = (round['currentFemaleCount'] as num?)?.toInt() ?? 0;
      if (gender == 'male') return currentMale >= maleCapacity;
      if (gender == 'female') return currentFemale >= femaleCapacity;
      // 성별을 모르면 양쪽 다 찼을 때만 마감으로 본다.
      return currentMale >= maleCapacity && currentFemale >= femaleCapacity;
    }
    final max = (round['maxCapacity'] as num?)?.toInt() ?? 0;
    if (max <= 0) return false; // 0 = 제한 없음
    final current =
        (round['currentParticipants'] as num?)?.toInt() ??
        ((round['currentMaleCount'] as num?)?.toInt() ?? 0) +
            ((round['currentFemaleCount'] as num?)?.toInt() ?? 0);
    return current >= max;
  }

  static DateTime? _at(dynamic raw) =>
      raw is Timestamp ? raw.toDate().toLocal() : null;
}
