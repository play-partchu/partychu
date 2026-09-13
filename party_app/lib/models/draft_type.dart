/// 등록 화면 임시저장(Draft)의 종류.
///
/// 사용자당·종류당 임시저장 1개만 유지하기 위해, 각 종류는 Firestore 문서
/// ID에 쓰이는 안정적인 문자열 [key]를 갖는다(문서 ID = `{userId}__{key}`).
/// 파티크루는 구인/구직이 완전히 다른 폼이라 별도 종류로 나눈다.
enum DraftType {
  party('party', '파티'),
  place('place', '장소대여'),
  shop('shop', '파티샵 상품'),
  crewRecruit('crew_recruit', '파티크루 구인'),
  crewSeek('crew_seek', '파티크루 구직'),
  event('event', '플레이스'),
  // 파티샵 "샵 자체" 등록 — 위 [shop]('파티샵 상품')은 이미 만들어진 샵에
  // 상품을 추가하는 화면이라 서로 다른 폼이다.
  market('market', '파티샵');

  // ⚠️ 콤보 등록 두 종류(`stay_party_combo` / `place_party_combo`)는 뺐다 —
  // 플레이스와 파티를 한 폼에서 함께 만드는 등록 방식 자체가 없어졌다
  // (플레이스를 먼저 올리고 [PlaceFollowupEntry]가 파티·이벤트로 이어준다).
  //
  // **두 key를 다시 쓰지 않는다.** 예전에 저장된 `drafts/{uid}__stay_party_combo`
  // 문서가 아직 남아 있고, 같은 key를 다른 폼에 붙이면 엉뚱한 payload를
  // 복원하게 된다. 남은 문서는 [fromKey]가 null을 돌려주어 목록에서 조용히
  // 빠진다(DraftService.watchAllDrafts) — 지우지도 않고, 열리지도 않는다.

  const DraftType(this.key, this.label);

  /// Firestore 문서 ID·SharedPreferences 키에 쓰는 안정적 식별자.
  final String key;

  /// 마이페이지 임시저장 목록 등에서 보여줄 한국어 라벨.
  final String label;

  /// 마이페이지 목록에서 유형 그룹을 묶을 때 쓰는 상위 구분(파티크루 구인/구직을
  /// 하나의 "파티크루" 그룹으로 합친다).
  String get groupLabel => switch (this) {
    DraftType.crewRecruit || DraftType.crewSeek => '파티크루',
    _ => label,
  };

  static DraftType? fromKey(String? key) {
    for (final t in DraftType.values) {
      if (t.key == key) return t;
    }
    return null;
  }
}
