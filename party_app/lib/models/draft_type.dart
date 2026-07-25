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
  event('event', '플레이스');

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
