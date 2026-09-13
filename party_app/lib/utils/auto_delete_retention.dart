// ─────────────────────────────────────────────────────────────────────────────
// 보관기간과 '자동삭제 D-n' 표시 — **등록물 네 종류와 임시저장이 함께 쓰는 정본.**
//
// 보관기간은 전부 **같은 14일**이고, 세는 기준점만 다르다:
//   · 지난 파티     — 최종 종료 시각(PartySchedule.finalEndAt). 정기 파티는
//                     마지막 회차가 끝난 때다.
//   · 지난 이벤트   — 보이지 않게 된 시각(PlacePromotion.goneAt) — 기간 종료일과
//                     호스트가 감춘 시각 중 먼저 일어난 쪽.
//   · 숨긴 플레이스 / 장소대여 — 숨긴 시각(문서의 hiddenAt).
//   · 임시저장      — 마지막 저장 시각(drafts.updatedAt). 이어서 쓰고 다시
//                     저장하면 문서가 통째로 덮어써지며 기한도 함께 밀린다.
//
// 기준점을 **모르면 아무 말도 하지 않는다**(null) — hiddenAt이 없던 시절에
// 감춰 둔 문서가 그렇다. 서버도 그런 문서는 지우지 않으므로 두 쪽이 맞는다.
//
// ⚠️ **여기는 표시만 한다. 지우는 것은 서버다** — functions/index.js의
//    deleteExpiredParties · deleteExpiredEvents · deleteExpiredPromotions ·
//    deleteExpiredPlaces · deleteExpiredDrafts(매일 새벽). 그래서 이 파일의
//    [window]는 functions/index.js의 RETENTION_DAYS와 반드시 같아야 한다.
//    앱이 'D-3'이라고 써 놓고 서버가 이미 지운 상태가 되면 사용자는 안내를
//    믿을 수 없게 된다.
// ─────────────────────────────────────────────────────────────────────────────

/// 자동삭제까지 남은 기간을 사람이 읽는 한 줄로 바꾸는 계산.
class AutoDeleteRetention {
  AutoDeleteRetention._();

  /// 보관기간 — 지난 파티·임시저장 공통.
  static const Duration window = Duration(days: 14);

  /// 기준점([from])에 보관기간을 더한 **삭제 예정 시각**. 기준점을 모르면
  /// (날짜를 못 읽는 옛 문서 등) null — 그런 문서는 아무 말도 하지 않는다.
  static DateTime? deleteAt(DateTime? from) => from?.add(window);

  /// 오늘부터 삭제일까지 **남은 날 수**(달력 날짜 기준).
  ///
  /// 시각이 아니라 날짜로 세는 이유: 삭제는 새벽 3시에 하루 한 번 도는
  /// 작업이라 "몇 시간 남았나"는 의미가 없고, 사용자도 'D-1'을 '내일'로
  /// 읽는다. 음수면 이미 삭제 예정일이 지난 것이다.
  static int? daysLeft(DateTime? from, {DateTime? now}) {
    final at = deleteAt(from);
    if (at == null) return null;
    final today = _dateOnly(now ?? DateTime.now());
    return _dateOnly(at).difference(today).inDays;
  }

  /// 목록 카드에 붙이는 한 줄.
  ///
  ///   · 남은 날이 있으면      '자동삭제 D-12'
  ///   · 오늘이 삭제일이면      '오늘 자동삭제'
  ///   · 날짜가 지났으면        '삭제 예정'
  ///
  /// **음수 D-day는 절대 만들지 않는다.** 삭제 작업은 하루 한 번이라 기한이
  /// 지나고도 문서가 몇 시간 남아 있는 구간이 정상적으로 존재한다 — 그때
  /// 'D--1'을 보여주면 고장으로 읽힌다. 기준점이 없으면 null(표시 안 함).
  static String? label(DateTime? from, {DateTime? now}) {
    final left = daysLeft(from, now: now);
    if (left == null) return null;
    if (left > 0) return '자동삭제 D-$left';
    if (left == 0) return '오늘 자동삭제';
    return '삭제 예정';
  }

  /// 삭제가 코앞인가 — 카드에서 색을 붉게 바꿀지 정하는 데 쓴다(3일 이하).
  static bool isUrgent(DateTime? from, {DateTime? now}) {
    final left = daysLeft(from, now: now);
    return left != null && left <= 3;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
