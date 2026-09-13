import 'package:party_app/models/party_early_bird_schedule.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/utils/format_utils.dart' as fmt;

/// 얼리버드 할인 계산 공통 유틸.
/// 등록/수정/메인 리스트/상세/검색/결제 전 구간에서 동일한 로직을 사용해야
/// "표시 가격"과 "실제 결제 가격"이 항상 일치한다.
///
/// 종료 시각은 **문서에서 바로 읽지 않고** [resolveEarlyBirdEndAt]으로 구한다 —
/// 정기 파티는 회차마다 종료 시각이 달라지기 때문이다(일회성은 예전처럼
/// 저장된 `earlyBirdEndAt` 그대로).
///
/// ## occurrenceStart를 반드시 넘겨야 하는 이유
///
/// 정기 파티에서 사용자가 **고른 회차**가 아니라 "지금 기준 다음 회차"로
/// 판정하면 셋이 서로 다른 답을 낸다. 실제로 그랬다(2026-08-21):
///   · 상세 안내: [firstDiscountedOccurrenceStart]로 회차를 순회 → '8/24 회차부터 할인'
///   · 참가비·신청 금액: 회차를 안 넘겨 다음 회차(8/21)로 판정 → 할인 없음(정상가)
///   · 서버 `computeAppliedFee(data, gender, now, occurrence)`: 고른 회차로 판정 → 할인 적용
/// 그 결과 8/25 회차를 골라도 신청 화면엔 정상가가 뜨고, 예약금 정책이 걸린
/// 파티는 서버의 `assertClientAmountMatches`에 걸려 신청 자체가 막혔다.
///
/// 그래서 회차를 고를 수 있는 화면(상세·신청)은 **반드시** [occurrenceStart]에
/// 그 회차 시작 시각을 넘긴다. 목록 카드처럼 회차 개념이 없는 자리는 예전처럼
/// 생략하면 되고(= 다음 회차 기준), 일회성 파티는 넘기든 말든 결과가 같다.
class EarlyBird {
  EarlyBird._();

  /// 얼리버드가 현재 시점에 유효한지 여부.
  /// enabled 플래그와 (회차 기준으로 계산한) 종료 시각만으로 판단 — 별도
  /// 배치/스케줄러 없이 매 조회 시점에 자동으로 종료/재개된다.
  static bool isActive(
    Map<String, dynamic> data, {
    DateTime? now,
    DateTime? occurrenceStart,
  }) {
    if (data['earlyBirdEnabled'] != true) return false;
    final end = endAt(data, now: now, occurrenceStart: occurrenceStart);
    if (end == null) return false;
    return end.isAfter(now ?? DateTime.now());
  }

  static int discountPercent(Map<String, dynamic> data) =>
      (data['earlyBirdDiscountPercent'] as num?)?.toInt() ?? 0;

  /// 이 파티의 얼리버드 종료 시각.
  ///
  /// [occurrenceStart]를 주면 **그 회차** 기준, 없으면 [now] 기준 다음 회차다.
  static DateTime? endAt(
    Map<String, dynamic> data, {
    DateTime? now,
    DateTime? occurrenceStart,
  }) => resolveEarlyBirdEndAt(data, now: now, occurrenceStart: occurrenceStart);

  /// 정상가 대비 얼리버드가 유효할 때만 할인된 가격을 반환 (0원 미만 불가).
  /// 무료(baseFee <= 0)인 경우 항상 그대로 반환.
  static int effectivePrice(
    int baseFee,
    Map<String, dynamic> data, {
    DateTime? now,
    DateTime? occurrenceStart,
  }) {
    if (baseFee <= 0) return baseFee;
    if (!isActive(data, now: now, occurrenceStart: occurrenceStart)) {
      return baseFee;
    }
    final pct = discountPercent(data);
    final discounted = (baseFee * (100 - pct) / 100).round();
    return discounted < 0 ? 0 : discounted;
  }

  /// "2일 13시간" 형태의 잔여시간 라벨. 이미 종료됐으면 빈 문자열.
  static String remainingLabel(
    Map<String, dynamic> data, {
    DateTime? now,
    DateTime? occurrenceStart,
  }) {
    final n = now ?? DateTime.now();
    final end = endAt(data, now: n, occurrenceStart: occurrenceStart);
    if (end == null) return '';
    final diff = end.difference(n);
    if (diff.isNegative) return '';
    final days = diff.inDays;
    final hours = diff.inHours.remainder(24);
    final minutes = diff.inMinutes.remainder(60);
    if (days > 0) return '$days일 $hours시간';
    if (hours > 0) return '$hours시간 $minutes분';
    return '$minutes분';
  }

  /// "D-2" 형태의 디데이 라벨 (달력일 기준). 이미 종료됐으면 빈 문자열.
  static String dDayLabel(
    Map<String, dynamic> data, {
    DateTime? now,
    DateTime? occurrenceStart,
  }) {
    final n = now ?? DateTime.now();
    final end = endAt(data, now: n, occurrenceStart: occurrenceStart);
    if (end == null) return '';
    final today = DateTime(n.year, n.month, n.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final days = endDay.difference(today).inDays;
    if (days < 0) return '';
    return 'D-$days';
  }

  /// 남은 시간이 얼마 없어 "마감 임박"으로 강조할 구간인지(24시간 이내).
  static bool isClosingSoon(
    Map<String, dynamic> data, {
    DateTime? now,
    DateTime? occurrenceStart,
  }) {
    final n = now ?? DateTime.now();
    if (!isActive(data, now: n, occurrenceStart: occurrenceStart)) return false;
    final end = endAt(data, now: n, occurrenceStart: occurrenceStart)!;
    return end.difference(n) <= const Duration(hours: 24);
  }

  /// 카드·상세에 한 줄로 붙이는 상태 라벨.
  ///
  ///  · 진행 중이고 오늘 끝남 → '얼리버드 오늘 23:59 마감'
  ///  · 진행 중이고 며칠 남음 → '얼리버드 D-2'
  ///  · 정기 파티인데 이번 회차는 끝났고 다음 회차가 남음 → '다음 회차 얼리버드 진행 중'
  ///  · 그 외(끝남/없음) → '얼리버드 마감' 또는 빈 문자열
  ///
  /// 얼리버드를 아예 안 쓰는 파티는 빈 문자열을 돌려주므로, 호출부는
  /// `isNotEmpty`일 때만 그리면 된다.
  static String statusLabel(
    Map<String, dynamic> data, {
    DateTime? now,
    DateTime? occurrenceStart,
  }) {
    if (data['earlyBirdEnabled'] != true) return '';
    final n = now ?? DateTime.now();
    final end = endAt(data, now: n, occurrenceStart: occurrenceStart);

    if (end != null && end.isAfter(n)) {
      final today = DateTime(n.year, n.month, n.day);
      final endDay = DateTime(end.year, end.month, end.day);
      final days = endDay.difference(today).inDays;
      if (days <= 0) {
        final hh = end.hour.toString().padLeft(2, '0');
        final mm = end.minute.toString().padLeft(2, '0');
        return '얼리버드 오늘 $hh:$mm 마감';
      }
      return '얼리버드 D-$days';
    }

    // 정기 파티는 이번 회차 얼리버드가 끝나도 뒤 회차에서 다시 열린다.
    //
    // 예전에는 '다음 회차 얼리버드 진행 중'이라고만 했는데, "다음"이 실제로
    // 며칠인지는 반복 규칙(매일/화·목/주말…)에 따라 전부 달라서 사용자가
    // 알 수 없었다 — 실제 회차 날짜를 계산해서 보여준다.
    final firstStart = firstDiscountedOccurrenceStart(data, now: n);
    if (firstStart != null) {
      return '${_occurrenceDateLabel(firstStart, now: n)} 회차부터 얼리버드 할인';
    }
    return '얼리버드 마감';
  }

  /// 지금(또는 [now]) 기준으로 **얼리버드가 실제로 적용되는 가장 빠른 회차**의
  /// 시작 시각. 없으면 null.
  ///
  /// 정기 파티 전용이다 — 일회성·여러 날짜 파티는 문서 하나가 곧 날짜 하나라
  /// "몇 번째 회차부터"라는 개념이 없고, 기존 동작(종료 시각 하나)이 그대로
  /// 맞다. 그래서 정기가 아니면 곧바로 null을 돌려준다.
  ///
  /// 판정 기준은 서버 `computeAppliedFee`와 **같다** — 회차 O의 시작 시각에
  /// 얼리버드 규칙을 적용한 종료 시각이 지금보다 뒤면 그 회차는 할인가로
  /// 결제된다. 그래서 이 함수가 고른 회차는 실제 결제 금액과 어긋나지 않는다.
  ///
  /// 회차 열거는 [PartySchedule.selectableOccurrences]가 하므로 매일·화목·주말
  /// 같은 반복 규칙이 무엇이든 **실제 회차 날짜**만 후보가 된다.
  static DateTime? firstDiscountedOccurrenceStart(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    if (data['earlyBirdEnabled'] != true) return null;
    if (!PartySchedule.isRecurring(data)) return null;
    // 고정 날짜 방식(예전 문서 폴백 포함)은 회차별로 달라지지 않는다 —
    // 종료 시각이 하나뿐이라 "몇 회차부터"를 물을 수 없다.
    final rule = earlyBirdRuleOf(data);
    if (rule == null) return null;

    final n = now ?? DateTime.now();
    // 얼리버드 종료가 회차 시작보다 한참 앞설 수 있어(예: 30일 전) 기본
    // 60일 지평으로는 후보를 못 찾는 설정이 있다 — 넉넉히 본다.
    for (final o in PartySchedule.selectableOccurrences(
      data,
      now: n,
      horizonDays: 180,
    )) {
      if (rule.resolve(o.start).isAfter(n)) return o.start;
    }
    return null;
  }

  /// 회차 날짜 한 줄 — '8월 29일(토)'. 해가 바뀌면 연도까지 붙인다
  /// ('2026년 9월 3일(목)') — 반복 파티는 몇 달 뒤 회차가 나올 수 있어서
  /// 연도가 없으면 언제인지 헷갈린다.
  static String _occurrenceDateLabel(DateTime d, {required DateTime now}) {
    final w = _weekdayChars[d.weekday - 1];
    if (d.year != now.year) return '${d.year}년 ${d.month}월 ${d.day}일($w)';
    return '${d.month}월 ${d.day}일($w)';
  }

  static const _weekdayChars = ['월', '화', '수', '목', '금', '토', '일'];

  static String formatEndAt(DateTime end) {
    final m = end.month.toString().padLeft(2, '0');
    final d = end.day.toString().padLeft(2, '0');
    final h = end.hour.toString().padLeft(2, '0');
    final mi = end.minute.toString().padLeft(2, '0');
    return '${end.year}.$m.$d $h:$mi';
  }

  /// 앱 전체 공통 포맷(lib/utils/format_utils.dart)으로 위임 — 여기 있던
  /// 자체 구현은 다른 화면들의 중복 구현과 함께 통일했다.
  static String formatPrice(int price) => fmt.formatPrice(price);
}
