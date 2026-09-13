import 'package:party_app/models/party_gender_recruit.dart';
import 'package:party_app/models/party_schedule.dart';

/// 정기 파티의 **회차별 모집 상태** — 'YYYY-MM-DD' 하나마다 전체 상태와
/// 성별별 모집을 따로 둔다(Firestore `occurrenceRecruit`).
///
/// ## 왜 새 필드인가 (기존 구조를 먼저 확인했다)
///
/// 파티의 날짜 저장 구조는 두 갈래고, 둘의 성질이 다르다.
///
///  · **날짜 슬롯**(등록에서 날짜를 여러 개 고른 게시글) — 날짜 1개 = `parties`
///    문서 1개이고 같은 `seriesId`로 묶인다. 모집 상태(`recruitStatus`)와
///    성별 모집(`genderRecruitStatus`)은 **이미 문서마다 따로**다
///    ([PartySlotSyncService.perDateStateKeys]). 여기는 새 구조가 필요 없다.
///  · **정기 파티**(`scheduleType: 'recurring'`) — 문서 **하나**가 모든 회차를
///    담는다. 그래서 위 두 필드는 문서에 한 벌뿐이고, 9/6만 마감하려 해도
///    8/30·9/13까지 함께 닫혔다. 이 파일이 그 구멍을 메운다.
///
/// 회차 단위로 값을 두는 칸은 이미 둘 있지만 **둘 다 쓰면 안 된다**.
///
///  · `occurrenceStats.{회차}` — 인원 카운터·신청자 명단. 쓰는 주체가 서버의
///    reserve/releaseApplicantSlot 하나뿐인 칸이라(partyCapacity.js 상단
///    '정원 카운터의 소유권') 호스트 설정을 섞으면 소유권이 흐려진다.
///  · `occurrenceCancellations.{회차}` — **서버가** 최소 인원 미달로 자동
///    취소한 기록(partyMinCapacity.js). 호스트가 쓰는 칸이 아니고, 지우면
///    자동 취소 이력이 사라진다.
///
/// 그래서 호스트가 쓰는 칸을 하나 더 둔다 — 이 파일이 그 칸이고, 저 둘은
/// 읽기만 한다.
///
/// ## 저장 형태
///
/// ```
/// occurrenceRecruit: {
///   '2026-09-06': {
///     status: '모집중' | '마감' | '취소',
///     genderRecruitStatus: { male: 'open'|'closed', female: 'open'|'closed' },
///   },
/// }
/// ```
///
/// **두 키는 서로를 건드리지 않는다.** 전체 상태를 '마감'으로 바꿔도 그 회차에
/// 저장된 남/여 값은 그대로 남고, 다시 '모집중'으로 되돌리면 그 값이 그대로
/// 되살아난다(호스트가 남/여를 다시 고르지 않아도 된다).
///
/// ## 없으면 문서 값으로 폴백한다 — 마이그레이션이 없다
///
/// 회차 칸이 없으면 예전 그대로 문서의 `recruitStatus`/`genderRecruitStatus`를
/// 읽는다. 그래서 **이 기능 이전에 만들어진 파티는 아무것도 바뀌지 않고**,
/// 호스트가 한 회차를 건드린 순간 그 회차만 문서 값과 달라진다. 반대로 문서
/// 값(전체 설정)을 바꾸면 손대지 않은 회차는 그 값을 그대로 따라간다.
///
/// ## 서버와 같은 규칙이어야 한다
///
/// 최종 차단은 서버(`functions/partyOccurrenceRecruit.js` →
/// reserveApplicantSlot)가 한다. 이 클래스는 그 거울이라, 한쪽만 고치면
/// 화면과 실제 신청 결과가 어긋난다.
class PartyOccurrenceRecruit {
  PartyOccurrenceRecruit._();

  /// Firestore 필드명.
  static const field = 'occurrenceRecruit';

  /// 회차 칸 안의 키 — 성별 키는 문서 최상단과 **같은 이름**을 쓴다. 같은 뜻의
  /// 값에 다른 이름을 붙이면 읽는 쪽이 두 벌이 된다.
  static const statusKey = 'status';
  static const genderKey = PartyGenderRecruit.field;

  /// 전체 모집 상태 값 — 기존 `recruitStatus`와 **같은 문자열**이다. 새 값을
  /// 만들지 않아야 이 값을 읽는 배지·필터·서버가 그대로 동작한다.
  static const statusOpen = '모집중';
  static const statusClosed = '마감';
  static const statusCancelled = '취소';

  static const statuses = <String>[statusOpen, statusClosed, statusCancelled];

  /// 이 파티가 회차별 설정을 쓸 수 있는가 — **정기 파티만**이다.
  ///
  /// 날짜 슬롯 게시글은 날짜마다 문서가 따로라 이 칸이 필요 없다(위 주석).
  /// 일회성 파티도 마찬가지다.
  static bool supports(Map<String, dynamic> data) =>
      PartySchedule.isRecurring(data);

  static Map<String, dynamic>? _all(Map<String, dynamic> data) {
    final raw = data[field];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  /// [occurrenceId] 회차에 저장된 칸. 없으면 null(= 문서 값을 따른다).
  static Map<String, dynamic>? entryOf(
    Map<String, dynamic> data,
    String? occurrenceId,
  ) {
    if (occurrenceId == null || occurrenceId.isEmpty) return null;
    final entry = _all(data)?[occurrenceId];
    return entry is Map ? Map<String, dynamic>.from(entry) : null;
  }

  /// 이 회차의 전체 모집 상태 — 회차 칸이 없으면 문서의 `recruitStatus`.
  ///
  /// [occurrenceId]가 null이면(일회성·날짜 슬롯 파티, 또는 아직 회차를 고르지
  /// 않은 화면) 예전 그대로 문서 값이다.
  static String statusOf(
    Map<String, dynamic> data, {
    String? occurrenceId,
  }) {
    final stored = entryOf(data, occurrenceId)?[statusKey];
    if (stored is String && statuses.contains(stored)) return stored;
    return data['recruitStatus'] as String? ?? statusOpen;
  }

  /// 이 회차가 취소됐는가 — 호스트가 내린 '취소'와 **서버가 최소 인원 미달로
  /// 자동 취소한 기록**([PartyCard.occurrenceCancellation]의 그 칸) 둘 다다.
  ///
  /// 자동 취소 기록은 여기서 **읽기만** 한다 — 지우거나 덮어쓰지 않는다.
  static bool isCancelled(
    Map<String, dynamic> data, {
    String? occurrenceId,
  }) {
    if (statusOf(data, occurrenceId: occurrenceId) == statusCancelled) {
      return true;
    }
    if (occurrenceId == null || occurrenceId.isEmpty) return false;
    final all = data['occurrenceCancellations'];
    return all is Map && all[occurrenceId] != null;
  }

  /// 이 회차의 성별 모집 칸 — 없으면 문서 최상단 값(폴백).
  static Map<String, dynamic>? _genderMap(
    Map<String, dynamic> data,
    String? occurrenceId,
  ) {
    final raw = entryOf(data, occurrenceId)?[genderKey];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    final doc = data[genderKey];
    return doc is Map ? Map<String, dynamic>.from(doc) : null;
  }

  static bool isMaleClosed(Map<String, dynamic> data, {String? occurrenceId}) =>
      PartyGenderRecruit.isClosedIn(
        _genderMap(data, occurrenceId),
        PartyGenderRecruit.male,
      );

  static bool isFemaleClosed(
    Map<String, dynamic> data, {
    String? occurrenceId,
  }) => PartyGenderRecruit.isClosedIn(
    _genderMap(data, occurrenceId),
    PartyGenderRecruit.female,
  );

  /// 이 성별에게 이 회차의 모집이 닫혀 있는가.
  ///
  /// 성별을 모르면 **양쪽 다 닫힌 경우에만** 닫힘이다 — 문서 단위 판정
  /// ([PartyGenderRecruit.isClosedFor])과 같은 규칙이다.
  static bool isClosedFor(
    Map<String, dynamic> data,
    String? gender, {
    String? occurrenceId,
  }) {
    if (gender == PartyGenderRecruit.male) {
      return isMaleClosed(data, occurrenceId: occurrenceId);
    }
    if (gender == PartyGenderRecruit.female) {
      return isFemaleClosed(data, occurrenceId: occurrenceId);
    }
    return isMaleClosed(data, occurrenceId: occurrenceId) &&
        isFemaleClosed(data, occurrenceId: occurrenceId);
  }

  /// 성별 설정만으로 이 회차가 통째로 닫혔는가 — 문서 단위 판정
  /// ([PartyGenderRecruit.isFullyClosed])과 같은 규칙이다. 성별 제한 파티는
  /// 받는 성별 하나만 닫혀도 전체 마감이다.
  static bool isFullyClosed(
    Map<String, dynamic> data, {
    String? occurrenceId,
  }) {
    final limit = data['genderLimit'] as String? ?? 'all';
    if (limit == PartyGenderRecruit.male) {
      return isMaleClosed(data, occurrenceId: occurrenceId);
    }
    if (limit == PartyGenderRecruit.female) {
      return isFemaleClosed(data, occurrenceId: occurrenceId);
    }
    return isMaleClosed(data, occurrenceId: occurrenceId) &&
        isFemaleClosed(data, occurrenceId: occurrenceId);
  }

  /// 한쪽만 닫힌 회차인가 — 성별에 따라 답이 갈리는 회차에서만 상태를 알린다
  /// ([PartyGenderRecruit.hasSplit]과 같은 뜻, 회차 단위).
  static bool hasSplit(Map<String, dynamic> data, {String? occurrenceId}) =>
      isMaleClosed(data, occurrenceId: occurrenceId) !=
      isFemaleClosed(data, occurrenceId: occurrenceId);

  /// 이 회차가 **지금 이 사람의** 신청을 받는가 — 전체 상태·취소·성별을 한 번에.
  ///
  /// 마감 시각·정원처럼 시간과 인원이 걸린 조건은 여기서 보지 않는다. 그건
  /// 예전 그대로 [PartyOccurrence.isRecruitingAt]과 정원 판정이 한다.
  static bool accepts(
    Map<String, dynamic> data, {
    required String? occurrenceId,
    String? gender,
  }) {
    if (statusOf(data, occurrenceId: occurrenceId) != statusOpen) return false;
    if (isCancelled(data, occurrenceId: occurrenceId)) return false;
    return !isClosedFor(data, gender, occurrenceId: occurrenceId);
  }

  /// 신청할 수 있는 회차만 남긴다 — 신청 플로우의 달력이 이 목록만 보여준다.
  ///
  /// 넘기는 [occurrences]는 일정 계산의 정본
  /// ([PartySchedule.selectableOccurrences] — 아직 오지 않았고 모집 창구가 열린
  /// 회차)이고, 여기서는 **호스트가 내린 상태**만 더 걸러낸다. 일정 계산을 다시
  /// 하지 않는다.
  static List<PartyOccurrence> openOccurrences(
    Map<String, dynamic> data,
    List<PartyOccurrence> occurrences, {
    String? gender,
  }) => [
    for (final occ in occurrences)
      if (accepts(data, occurrenceId: occ.id, gender: gender)) occ,
  ];

  /// 호스트 달력 한 칸에 붙는 짧은 상태 — '모집중' / '마감' / '취소' /
  /// '여성 마감'처럼.
  static String shortLabelOf(
    Map<String, dynamic> data, {
    required String occurrenceId,
  }) {
    if (isCancelled(data, occurrenceId: occurrenceId)) return statusCancelled;
    final status = statusOf(data, occurrenceId: occurrenceId);
    if (status != statusOpen) return status;
    final male = isMaleClosed(data, occurrenceId: occurrenceId);
    final female = isFemaleClosed(data, occurrenceId: occurrenceId);
    if (male && female) return '남녀 마감';
    if (male) return '남성 마감';
    if (female) return '여성 마감';
    return statusOpen;
  }

  /// 고른 회차들의 값이 하나로 모이면 그 값, 서로 다르면 null(= 혼합).
  ///
  /// 호스트 화면의 라디오·스위치가 "여러 날짜의 서로 다른 상태"를 한 값으로
  /// 잘못 보여주지 않게 하는 자리다 — null이면 아무것도 켜지 않고, 호스트가
  /// 직접 고른 값만 저장한다.
  static String? commonStatusOf(
    Map<String, dynamic> data,
    Iterable<String> occurrenceIds,
  ) => _common([
    for (final id in occurrenceIds) statusOf(data, occurrenceId: id),
  ]);

  static bool? commonMaleClosedOf(
    Map<String, dynamic> data,
    Iterable<String> occurrenceIds,
  ) => _common([
    for (final id in occurrenceIds) isMaleClosed(data, occurrenceId: id),
  ]);

  static bool? commonFemaleClosedOf(
    Map<String, dynamic> data,
    Iterable<String> occurrenceIds,
  ) => _common([
    for (final id in occurrenceIds) isFemaleClosed(data, occurrenceId: id),
  ]);

  static T? _common<T>(List<T> values) {
    if (values.isEmpty) return null;
    final first = values.first;
    return values.every((v) => v == first) ? first : null;
  }

  /// 고른 회차들에 저장할 필드 — **점 표기 경로**라 다른 회차와 다른 키를
  /// 건드리지 않는다(`occurrenceRecruit.2026-09-06.status`).
  ///
  /// [status]가 null이면 전체 상태를 바꾸지 않고, [maleClosed]/[femaleClosed]가
  /// null이면 성별 값을 바꾸지 않는다 — 호스트가 손대지 않은 값(혼합 상태
  /// 포함)이 그대로 남는다.
  ///
  /// **지우는 값이 없다.** 남녀가 모두 모집중이어도 필드를 지우지 않고
  /// `{male:'open', female:'open'}`을 적는다 — 지우면 문서 최상단 값으로
  /// 폴백해서, 전체 설정이 마감인 파티의 한 회차만 여는 일이 불가능해진다.
  static Map<String, dynamic> updateFields({
    required Iterable<String> occurrenceIds,
    String? status,
    bool? maleClosed,
    bool? femaleClosed,
  }) {
    final fields = <String, dynamic>{};
    for (final id in occurrenceIds) {
      if (id.isEmpty) continue;
      if (status != null) {
        fields['$field.$id.$statusKey'] = status;
      }
      if (maleClosed != null || femaleClosed != null) {
        fields['$field.$id.$genderKey'] = {
          if (maleClosed != null)
            PartyGenderRecruit.male: maleClosed
                ? PartyGenderRecruit.closed
                : PartyGenderRecruit.open,
          if (femaleClosed != null)
            PartyGenderRecruit.female: femaleClosed
                ? PartyGenderRecruit.closed
                : PartyGenderRecruit.open,
        };
      }
    }
    return fields;
  }
}
