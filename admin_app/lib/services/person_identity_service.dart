import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/person_identity.dart';
import 'admin_firestore_service.dart';

/// 동일인(실제 회원 1명) 기준 조회·집계.
///
/// 판별 규칙은 utils/person_identity.dart에 있다. 여기서는 그 규칙에 넣을
/// users 문서를 가져오기만 한다 — **읽기만 한다.** 서버·규칙·데이터는 그대로다.
///
/// ── 왜 본인확인 계정만 읽나 ──────────────────────────────────────────────
///
/// 동일인이 될 수 있는 계정은 CI를 가진 계정뿐이고, CI는 본인확인을 마친
/// 계정에만 있다. 그래서 "중복 계정 수"는 본인확인 계정만 보고 계산할 수
/// 있고, 전체 회원을 내려받을 필요가 없다. 사람 수 = `.count()` 계정 수 − 중복.
///
/// identityLinks 컬렉션은 쓰지 않는다 — 규칙이 클라이언트 읽기를 막아 두었고,
/// 최신 uid 하나와 탈퇴 이력(previousUids)만 들고 있어 현역 계정 여러 개를
/// 묶는 데 쓸 수 없다. 정본은 users 문서의 identityCiHash/ci다.
class PersonIdentityService {
  PersonIdentityService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _cache;
  static DateTime? _cachedAt;

  /// 대시보드·회원 목록이 연달아 부를 때 같은 문서를 두 번 받지 않게 잠깐만
  /// 들고 있는다. 오래 들고 있으면 새 본인확인이 반영되지 않는다.
  static const _cacheTtl = Duration(seconds: 60);

  /// 본인확인을 마친 계정 전부 — 동일인 판별 근거(CI)가 있을 수 있는 계정.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> verifiedAccountDocs() {
    final now = DateTime.now();
    final cached = _cache;
    if (cached != null && _cachedAt != null && now.difference(_cachedAt!) < _cacheTtl) {
      return cached;
    }
    final future = _db
        .collection('users')
        .where(
          Filter.or(
            Filter('identityVerified', isEqualTo: true),
            Filter('isVerified', isEqualTo: true),
          ),
        )
        .get()
        .then((s) => s.docs);
    _cache = future;
    _cachedAt = now;
    // 실패한 조회를 캐시에 남기지 않는다.
    future.catchError((_) {
      if (identical(_cache, future)) _cache = null;
      return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    });
    return future;
  }

  /// 테스트에서 캐시를 비운다.
  static void resetCache() {
    _cache = null;
    _cachedAt = null;
  }

  /// 동일인 키 → 그 사람의 계정 전부(본인확인 계정 기준).
  static Future<Map<String, PersonGroup>> peopleByKey() async {
    final docs = await verifiedAccountDocs();
    final groups = groupAccountsByPerson(docs.map((d) => (d.id, d.data())));
    return {
      for (final g in groups)
        if (g.key != null) g.key!: g,
    };
  }

  /// [where]를 통과한 본인확인 계정 가운데 "같은 사람의 두 번째 이후 계정" 수.
  static Future<int> duplicateAccounts({
    required bool Function(Map<String, dynamic> data) where,
  }) async {
    final docs = await verifiedAccountDocs();
    return duplicateAccountCount(docs.map((d) => d.data()).where(where));
  }

  // ── 대시보드 KPI ──────────────────────────────────────────────────────
  //
  // 계정 수 쿼리(AdminFirestoreService)는 그대로 두고 중복만 뺀다. 조건도
  // 계정 수 쿼리와 **똑같이** 맞춘다 — 그 쿼리는 `isTestAccount == false`를
  // 등호로 걸어서 필드가 명시적으로 false인 계정만 센다.

  static bool _countedAsRealAccount(Map<String, dynamic> d) => d['isTestAccount'] == false;

  /// 전체 가입자 — 실제 회원 수(동일인 계정은 1명).
  static Future<int> totalPersons() async {
    final results = await Future.wait([
      AdminFirestoreService.totalUsers(),
      duplicateAccounts(where: _countedAsRealAccount),
    ]);
    return results[0] - results[1];
  }

  /// 본인확인 완료 — 실제 회원 수. 본인확인 계정은 모두 이 집계 대상이라
  /// 중복도 같은 조건으로 뺀다.
  static Future<int> verifiedPersons() async {
    final results = await Future.wait([
      AdminFirestoreService.verifiedUsers(),
      duplicateAccounts(where: _countedAsRealAccount),
    ]);
    return results[0] - results[1];
  }

  // ── 회원 상세 ─────────────────────────────────────────────────────────

  /// 이 계정의 주인이 가진 계정 전부(자기 자신 포함).
  ///
  /// 목록용 캐시가 아니라 **직접 조회**한다 — 상세는 방금 인증한 계정까지
  /// 정확해야 한다. 해시로 한 번, 해시 필드 도입 전 회원을 위해 CI 원문으로
  /// 한 번 찾는다(둘 다 단일 필드 등호라 자동 색인으로 조회된다). CI 원문은
  /// 쿼리 값으로만 쓰고 화면에 내보내지 않는다.
  static Future<PersonGroup> accountsOfPerson(String uid, Map<String, dynamic> data) async {
    final key = personKeyOf(data);
    if (key == null) {
      return PersonGroup(key: null, accounts: [MemberAccount.fromUserDoc(uid, data)]);
    }
    final users = _db.collection('users');
    final ci = data['ci'];
    final snaps = await Future.wait([
      users.where('identityCiHash', isEqualTo: key).get(),
      if (ci is String && ci.trim().isNotEmpty) users.where('ci', isEqualTo: ci).get(),
    ]);
    final found = <String, Map<String, dynamic>>{uid: data};
    for (final s in snaps) {
      for (final d in s.docs) {
        // 쿼리가 무엇을 돌려주든 같은 규칙으로 다시 확인한다.
        if (personKeyOf(d.data()) == key) found[d.id] = d.data();
      }
    }
    final groups = groupAccountsByPerson(found.entries.map((e) => (e.key, e.value)));
    return groups.single;
  }
}
