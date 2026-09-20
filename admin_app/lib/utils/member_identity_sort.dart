// 회원 목록의 '본인확인' 열 — 상태 판정과 열 정렬. 순수 로직만 둔다.
//
// ── 무엇을 보고 '인증완료'라고 하나 ──────────────────────────────────────
//
// 새 필드를 만들지 않는다. 회원 문서에 이미 있는 두 값을 그대로 읽는다:
//   identityVerified (지금 쓰는 필드) ?? isVerified (옛 필드) ?? false
// 이 규칙은 원래 회원 목록과 회원 상세에 같은 식으로 두 번 적혀 있던 것을
// 여기로 모은 것이다 — 두 화면이 서로 다른 답을 내지 않게 하려고.
//
// 옛 필드를 폴백으로 남기는 이유는 운영에 identityVerified가 없고
// isVerified만 true인 계정이 남아 있기 때문이다.
//
// ── 상단 '본인확인' 필터와의 차이 ────────────────────────────────────────
//
// 상단 필터는 Firestore 쿼리(`where('identityVerified', ...)`)라 옛 필드만
// 가진 계정을 '완료'로 잡지 못한다. 그건 이 화면 이전부터의 동작이라
// 여기서 바꾸지 않는다 — 배지와 정렬은 폴백까지 본 값을 쓴다.

/// 이 회원 문서가 본인확인을 마쳤는가.
bool isIdentityVerifiedDoc(Map<String, dynamic> d) =>
    (d['identityVerified'] as bool?) ?? (d['isVerified'] as bool?) ?? false;

/// '본인확인' 열의 정렬 방향.
///
/// [none]은 이 열로 정렬하지 않는 상태 — 상단의 정렬 드롭다운(최근 가입순 등)이
/// 정한 순서를 그대로 둔다. 머리를 계속 누르면 세 상태를 돌아 원래 순서로
/// 돌아올 수 있다.
enum IdentitySortOrder {
  /// 인증완료 → 미인증 (화면 첫 진입 기본값).
  verifiedFirst,

  /// 미인증 → 인증완료.
  unverifiedFirst,

  /// 이 열로 정렬하지 않음.
  none;

  /// 머리를 눌렀을 때 넘어갈 다음 상태.
  IdentitySortOrder get next => switch (this) {
    IdentitySortOrder.verifiedFirst => IdentitySortOrder.unverifiedFirst,
    IdentitySortOrder.unverifiedFirst => IdentitySortOrder.none,
    IdentitySortOrder.none => IdentitySortOrder.verifiedFirst,
  };

  /// DataTable 화살표 방향 — 미인증(false)을 작은 값으로 본다.
  /// 오름차순이면 미인증이 위, 내림차순이면 인증완료가 위.
  bool get ascending => this == IdentitySortOrder.unverifiedFirst;
}

/// [items]를 본인확인 상태로 다시 줄 세운다. **이미 받아 온 목록 안에서만**
/// 순서를 바꾼다 — 서버 쿼리와 페이지 나눔은 건드리지 않는다.
///
/// 같은 상태끼리는 들어온 순서를 지킨다(안정 정렬). 그래서 상단 정렬
/// 드롭다운이 정한 '최근 가입순' 같은 순서가 묶음 안에서 그대로 남는다.
/// Dart의 [List.sort]는 안정성을 보장하지 않아 들어온 위치를 tie-breaker로
/// 같이 비교한다.
List<T> sortByIdentityVerified<T>(
  List<T> items, {
  required bool Function(T) verified,
  required IdentitySortOrder order,
}) {
  if (order == IdentitySortOrder.none || items.length < 2) {
    return List<T>.of(items);
  }
  final verifiedTop = order == IdentitySortOrder.verifiedFirst;
  final indexed = [
    for (var i = 0; i < items.length; i++) (i, items[i], verified(items[i])),
  ];
  indexed.sort((a, b) {
    if (a.$3 != b.$3) {
      final aFirst = a.$3 == verifiedTop;
      return aFirst ? -1 : 1;
    }
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}
