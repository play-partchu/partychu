import 'package:party_app/models/party_schedule.dart';

/// 신청 플로우가 들고 있는 **참가 회차 상태** — 상세 화면의 일정 표시와 완전히
/// 분리된 한 곳.
///
/// 예전에는 상세 화면에도 '참가 날짜' 선택 행이 있어서, 거기서 고른 값이 그대로
/// 신청 대상이 됐다. 그러면 '신청하기'를 눌러 들어간 플로우가 그 값을 보고 날짜
/// 단계를 건너뛰거나, 반대로 상세에서 안 골랐으면 플로우에서 또 고르게 되어
/// "같은 선택을 두 번 하는" 화면이 됐다.
///
/// 그래서 역할을 갈랐다 —
///
///  * 상세 화면: 앞으로 열리는 날짜를 **보여주기만** 한다. 이 상태를 만들지도
///    바꾸지도 않는다(읽기 전용이라 이 클래스에 접근할 일이 없다).
///  * 신청 플로우: [beginFlow]로 시작해 달력에서 [select]로 회차를 정한다.
///
/// 규칙은 셋뿐이다.
///  1. 신청 대상은 [selected] 하나다.
///  2. 플로우에 들어올 때마다 [beginFlow]가 그 값을 비운다 — 그래서 '신청하기'를
///     누르면 달력이 **매번 정확히 한 번** 뜬다.
///  3. 직전에 고른 날은 [calendarInitialId]로만 되살아난다 — 달력이 열릴 때의
///     표시 초기값일 뿐, 그 자체로 신청 대상이 되지는 않는다.
class ApplyOccurrenceState {
  PartyOccurrence? _selected;
  String? _lastCalendarId;

  /// 이번 신청의 **실제 참가 회차**. 아직 안 골랐으면 null이다.
  PartyOccurrence? get selected => _selected;

  /// 달력을 열 때 미리 켜 둘 날짜 id.
  ///
  /// 다음 단계(차수)에서 ←를 누르면 흐름이 [clear]로 회차를 비우고 날짜 단계로
  /// 되돌아온다. 그때 달력이 아무것도 안 고른 상태로 열리면 방금 뭘 골랐었는지
  /// 사라지고, 열리는 달도 첫 회차의 달로 되돌아간다.
  String? get calendarInitialId => _selected?.id ?? _lastCalendarId;

  /// 신청 플로우에 **들어올 때마다** 부른다 — 신청 대상만 비우고 기억은 남긴다.
  void beginFlow() => clear();

  /// 달력에서 회차를 골랐다.
  void select(PartyOccurrence occurrence) {
    _selected = occurrence;
    _lastCalendarId = occurrence.id;
  }

  /// 한 칸 앞(날짜 단계)으로 되돌아간다 — 신청 대상만 비우고 기억은 남긴다.
  void clear() => _selected = null;
}
