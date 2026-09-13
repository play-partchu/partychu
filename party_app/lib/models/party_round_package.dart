import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:party_app/models/party_early_bird_schedule.dart';

/// "차수 패키지" — 여러 차수를 한 상품으로 묶어 **별도 가격**에 파는 옵션.
///
/// 예: 1차 3만원 / 2차 2.5만원인 파티에서 "1+2차 통합권 4.5만원".
///
/// ## 왜 별도 상품인가
///
/// 개별 차수 금액을 합산해서 자동 계산하지 않는다. 패키지는 호스트가 정한
/// **판매가 하나**이고(얼리버드도 마찬가지로 별도 금액), 개별 합계는 "얼마나
/// 이득인지" 보여주기 위한 참고값으로만 계산한다. 합산으로 유도하면 차수
/// 가격을 고칠 때 패키지 가격이 조용히 따라 움직여, 이미 그 가격을 보고 신청한
/// 사람과 어긋난다.
///
/// ## 저장 형태 (`parties.roundPackages` 배열 원소)
/// ```
/// {
///   id: 'pkg_...',              // 신청 문서가 가리키는 안정적 식별자
///   name: '1+2차 통합권',
///   roundNumbers: [1, 2],       // rounds[].roundNumber 기준(정렬·중복 제거됨)
///   roundIds: ['round_1', ...], // 보조 — 수정/재등록에서 차수 대조용
///   maleFee: 45000,
///   femaleFee: 35000,
///   // 얼리버드 — 할인율이 아니라 "얼리버드 판매가"를 그대로 담는다.
///   earlyBirdEnabled: true,
///   earlyBirdMaleFee: 40000,
///   earlyBirdFemaleFee: 30000,
///   earlyBirdDeadlineRule: { mode: 'daysBefore', days: 3, time: '23:59' },
///   earlyBirdEndAt: Timestamp,  // 위 규칙을 대표 날짜에 적용한 캐시
/// }
/// ```
///
/// 정원은 이 구조에 두지 않는다 — 패키지 신청자는 포함된 **각 차수의 정원을
/// 1명씩** 차지하므로, 정원은 언제나 `rounds[]`의 카운터가 정본이다
/// (서버 `partyCapacity.js`의 `selectedRounds` 경로를 그대로 재사용한다).
@immutable
class PartyRoundPackage {
  final String id;

  /// 비워두면 [defaultNameFor]로 채운다('1+2차 패키지').
  final String name;

  /// 포함 차수 — `rounds[].roundNumber`. 항상 2개 이상이어야 한다.
  final List<int> roundNumbers;

  /// 포함 차수의 `id` — 차수 구성이 바뀌었는지 대조하는 보조 값.
  final List<String> roundIds;

  final int maleFee;
  final int femaleFee;

  /// 얼리버드 판매가 사용 여부.
  final bool earlyBirdEnabled;
  final int earlyBirdMaleFee;
  final int earlyBirdFemaleFee;

  /// 얼리버드 종료 규칙 — 차수 얼리버드와 같은 "시작 전" 상대 규칙이고,
  /// 기준 시각은 **포함된 첫 차수의 시작 시각**이다. 패키지는 여러 차수에
  /// 걸쳐 있어 절대 시각을 하나로 못 박을 수 없기 때문이다.
  final PartyEarlyBirdDeadlineRule earlyBirdRule;

  /// 저장할 때 위 규칙을 대표 날짜에 적용해 넣어둔 종료 시각 캐시
  /// (`earlyBirdEndAt`). 읽는 쪽은 이 값이 있으면 그대로 쓰고, 없으면 규칙을
  /// 그 자리에서 다시 적용한다 — 차수 얼리버드와 같은 방식이다.
  final DateTime? earlyBirdEndAt;

  const PartyRoundPackage({
    required this.id,
    this.name = '',
    this.roundNumbers = const [],
    this.roundIds = const [],
    this.maleFee = 0,
    this.femaleFee = 0,
    this.earlyBirdEnabled = false,
    this.earlyBirdMaleFee = 0,
    this.earlyBirdFemaleFee = 0,
    this.earlyBirdRule = const PartyEarlyBirdDeadlineRule(),
    this.earlyBirdEndAt,
  });

  static int _idCounter = 0;

  static String newId() =>
      'pkg_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  /// '1+2차 패키지' — 이름을 비워둔 패키지의 기본 이름.
  static String defaultNameFor(List<int> roundNumbers) {
    if (roundNumbers.isEmpty) return '패키지';
    final sorted = [...roundNumbers]..sort();
    return '${sorted.join('+')}차 패키지';
  }

  String get displayName =>
      name.trim().isEmpty ? defaultNameFor(roundNumbers) : name.trim();

  /// 정렬·중복 제거된 포함 차수 — 저장·검증·서버 전달에 항상 이 값을 쓴다.
  List<int> get normalizedRoundNumbers =>
      (roundNumbers.toSet().toList()..sort());

  PartyRoundPackage copyWith({
    String? id,
    String? name,
    List<int>? roundNumbers,
    List<String>? roundIds,
    int? maleFee,
    int? femaleFee,
    bool? earlyBirdEnabled,
    int? earlyBirdMaleFee,
    int? earlyBirdFemaleFee,
    PartyEarlyBirdDeadlineRule? earlyBirdRule,
  }) => PartyRoundPackage(
    id: id ?? this.id,
    name: name ?? this.name,
    roundNumbers: roundNumbers ?? this.roundNumbers,
    roundIds: roundIds ?? this.roundIds,
    maleFee: maleFee ?? this.maleFee,
    femaleFee: femaleFee ?? this.femaleFee,
    earlyBirdEnabled: earlyBirdEnabled ?? this.earlyBirdEnabled,
    earlyBirdMaleFee: earlyBirdMaleFee ?? this.earlyBirdMaleFee,
    earlyBirdFemaleFee: earlyBirdFemaleFee ?? this.earlyBirdFemaleFee,
    earlyBirdRule: earlyBirdRule ?? this.earlyBirdRule,
  );

  /// 이 성별이 낼 정상가. 성별을 모르면 낮은 쪽(최소 참가비)을 대표로 쓴다 —
  /// 목록·상세의 기존 "최소 참가비" 표기와 같은 규칙이다.
  int feeFor(String? gender) {
    if (gender == 'male') return maleFee;
    if (gender == 'female') return femaleFee;
    final values = [maleFee, femaleFee].where((v) => v > 0).toList();
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a < b ? a : b);
  }

  int earlyBirdFeeFor(String? gender) {
    if (gender == 'male') return earlyBirdMaleFee;
    if (gender == 'female') return earlyBirdFemaleFee;
    final values = [
      earlyBirdMaleFee,
      earlyBirdFemaleFee,
    ].where((v) => v > 0).toList();
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a < b ? a : b);
  }

  bool get hasGenderedFee => maleFee != femaleFee;

  bool get isFree => maleFee <= 0 && femaleFee <= 0;

  /// 입력이 덜 됐거나 앞뒤가 맞지 않으면 문구를 돌려준다(없으면 null).
  ///
  /// [availableRoundNumbers]는 지금 화면에 있는 차수들 — 없어진 차수를
  /// 가리키는 패키지는 저장할 수 없다(재등록에서 차수 구성이 바뀌는 경우).
  String? validate({
    required List<int> availableRoundNumbers,
    required bool separateGenderFee,
  }) {
    final rounds = normalizedRoundNumbers;
    if (rounds.length < 2) {
      return '패키지에 포함할 차수를 2개 이상 선택해주세요.';
    }
    final missing = rounds.where((n) => !availableRoundNumbers.contains(n));
    if (missing.isNotEmpty) {
      return '${missing.map((n) => '$n차').join(', ')}가 없어졌어요. 포함 차수를 다시 선택해주세요.';
    }
    if (maleFee % 1000 != 0 ||
        femaleFee % 1000 != 0 ||
        maleFee < 0 ||
        femaleFee < 0) {
      return '패키지 참가비를 1,000원 단위로 입력해주세요. (무료면 0)';
    }
    if (earlyBirdEnabled) {
      if (isFree) {
        return '무료 패키지에는 얼리버드를 설정할 수 없어요.';
      }
      if (earlyBirdMaleFee % 1000 != 0 || earlyBirdFemaleFee % 1000 != 0) {
        return '패키지 얼리버드 금액을 1,000원 단위로 입력해주세요.';
      }
      if (earlyBirdMaleFee > maleFee ||
          (separateGenderFee && earlyBirdFemaleFee > femaleFee)) {
        return '얼리버드 금액이 정상 패키지 금액보다 클 수 없어요.';
      }
    }
    return null;
  }

  /// Firestore `parties.roundPackages` 배열 원소.
  ///
  /// [firstRoundStart]는 포함된 첫 차수의 시작 시각 — 얼리버드 종료 시각
  /// 캐시(`earlyBirdEndAt`)를 여기서 미리 계산해 둔다(차수 저장 방식과 동일).
  Map<String, dynamic> toMap({DateTime? firstRoundStart}) {
    final endAt = earlyBirdEnabled && firstRoundStart != null
        ? earlyBirdRule.resolve(firstRoundStart)
        : null;
    return {
      'id': id,
      'name': displayName,
      'roundNumbers': normalizedRoundNumbers,
      'roundIds': roundIds,
      'maleFee': maleFee,
      'femaleFee': femaleFee,
      'earlyBirdEnabled': earlyBirdEnabled,
      'earlyBirdMaleFee': earlyBirdEnabled ? earlyBirdMaleFee : 0,
      'earlyBirdFemaleFee': earlyBirdEnabled ? earlyBirdFemaleFee : 0,
      'earlyBirdDeadlineRule': earlyBirdEnabled ? earlyBirdRule.toMap() : null,
      'earlyBirdEndAt': endAt == null ? null : Timestamp.fromDate(endAt),
    };
  }

  /// 임시저장용 — Timestamp를 쓸 수 없어 규칙만 담는다.
  Map<String, dynamic> toDraftMap() => {
    'id': id,
    'name': name,
    'roundNumbers': normalizedRoundNumbers,
    'roundIds': roundIds,
    'maleFee': maleFee,
    'femaleFee': femaleFee,
    'earlyBirdEnabled': earlyBirdEnabled,
    'earlyBirdMaleFee': earlyBirdMaleFee,
    'earlyBirdFemaleFee': earlyBirdFemaleFee,
    'earlyBirdDeadlineRule': earlyBirdRule.toMap(),
  };

  /// 문서/임시저장 어느 쪽에서든 복원한다(두 포맷의 차이는 Timestamp뿐이다).
  static PartyRoundPackage? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final numbers =
        (m['roundNumbers'] as List?)
            ?.map((e) => (e as num?)?.toInt())
            .whereType<int>()
            .toList() ??
        const <int>[];
    if (numbers.isEmpty) return null;
    final ruleRaw = m['earlyBirdDeadlineRule'];
    return PartyRoundPackage(
      id: (m['id'] as String?)?.trim().isNotEmpty == true
          ? m['id'] as String
          : newId(),
      name: m['name'] as String? ?? '',
      roundNumbers: numbers,
      roundIds:
          (m['roundIds'] as List?)?.whereType<String>().toList() ??
          const <String>[],
      maleFee: (m['maleFee'] as num?)?.toInt() ?? 0,
      femaleFee: (m['femaleFee'] as num?)?.toInt() ?? 0,
      earlyBirdEnabled: m['earlyBirdEnabled'] == true,
      earlyBirdMaleFee: (m['earlyBirdMaleFee'] as num?)?.toInt() ?? 0,
      earlyBirdFemaleFee: (m['earlyBirdFemaleFee'] as num?)?.toInt() ?? 0,
      earlyBirdRule:
          (ruleRaw is Map
              ? PartyEarlyBirdDeadlineRule.fromMap(
                  Map<String, dynamic>.from(ruleRaw),
                )
              : null) ??
          const PartyEarlyBirdDeadlineRule(),
      earlyBirdEndAt: m['earlyBirdEndAt'] is Timestamp
          ? (m['earlyBirdEndAt'] as Timestamp).toDate().toLocal()
          : null,
    );
  }

  /// 지금 얼리버드 판매가가 유효한 종료 시각 — 저장된 캐시가 있으면 그대로,
  /// 없으면 [firstRoundStart]에 규칙을 적용해 계산한다.
  DateTime? resolveEarlyBirdEndAt(DateTime? firstRoundStart) {
    if (!earlyBirdEnabled) return null;
    if (earlyBirdEndAt != null) return earlyBirdEndAt;
    if (firstRoundStart == null) return null;
    return earlyBirdRule.resolve(firstRoundStart);
  }

  /// 파티 문서에서 패키지 목록을 읽는다 — 없거나 깨진 원소는 조용히 버린다.
  static List<PartyRoundPackage> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map(fromMap)
        .whereType<PartyRoundPackage>()
        .where((p) => p.normalizedRoundNumbers.length >= 2)
        .toList();
  }
}
