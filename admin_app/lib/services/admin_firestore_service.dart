import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

const _functionsRegion = 'asia-northeast3';

/// 회원 목록 정렬 기준 — 전부 users 컬렉션 자체 필드다. "실제 이용 횟수순"처럼
/// userStats(별도 컬렉션) 값에 대한 정렬은 여기서 지원하지 않는다 — Firestore는
/// 컬렉션 간 조인 쿼리가 안 되므로, 그런 정렬은 "이용 통계" 화면에서 userStats를
/// 직접 정렬해서 보여준다(아래 UsageSortField).
enum MemberSortField {
  createdAt,
  lastActiveAt,
  lastLoginAt,
  nameLower,
  birthYear,
}

extension on MemberSortField {
  String get fieldPath => switch (this) {
    MemberSortField.createdAt => 'createdAt',
    MemberSortField.lastActiveAt => 'lastActiveAt',
    MemberSortField.lastLoginAt => 'lastLoginAt',
    MemberSortField.nameLower => 'nameLower',
    MemberSortField.birthYear => 'birthYear',
  };

  bool get descending => this != MemberSortField.nameLower;
}

/// "이용 통계 > 사용자별 목록" 화면의 정렬 기준 — userStats 컬렉션 자체 필드.
enum UsageSortField { totalApplications, totalAttended, lastParticipationAt }

extension on UsageSortField {
  String get fieldPath => switch (this) {
    UsageSortField.totalApplications => 'totalApplications',
    UsageSortField.totalAttended => 'totalAttended',
    UsageSortField.lastParticipationAt => 'lastParticipationAt',
  };
}

/// party_app의 RegionData.regionDistricts와 동일한 시/도 17개 — admin_app은
/// 별도 Flutter 프로젝트라 party_app 모델을 import할 수 없어 이름만 복제한다.
const List<String> kRegions1 = [
  '서울',
  '경기',
  '인천',
  '부산',
  '대구',
  '광주',
  '대전',
  '울산',
  '세종',
  '강원',
  '충북',
  '충남',
  '전북',
  '전남',
  '경북',
  '경남',
  '제주',
];

/// 대시보드/회원 목록/본인확인 목록에서 쓰는 Firestore 조회를 모아둔다.
/// 가능한 한 `.count()` 집계 쿼리를 쓰고, 회원 목록은 항상 페이지 단위로만
/// 조회한다(전체 컬렉션을 한 번에 내려받지 않음 — 회원 수천~수만 명 규모 전제).
class AdminFirestoreService {
  AdminFirestoreService._();

  static final _db = FirebaseFirestore.instance;

  // ── 대시보드 ────────────────────────────────────────────────────────

  static Future<int> _count(Query query) async {
    final snap = await query.count().get();
    return snap.count ?? 0;
  }

  // 대시보드 KPI는 전부 실사용자 기준(isTestAccount==false)만 센다 —
  // onUserCreated 트리거가 모든 신규 회원에게 이 필드를 항상 채워두므로
  // 등호 필터로 실사용자가 누락될 걱정은 없다.
  static Future<int> totalUsers() =>
      _count(_db.collection('users').where('isTestAccount', isEqualTo: false));

  static Future<int> verifiedUsers() => _count(
    _db
        .collection('users')
        .where(
          Filter.and(
            Filter('isTestAccount', isEqualTo: false),
            Filter.or(
              Filter('identityVerified', isEqualTo: true),
              Filter('isVerified', isEqualTo: true),
            ),
          ),
        ),
  );

  static Future<int> activeUsersSince(DateTime since) => _count(
    _db
        .collection('users')
        .where('isTestAccount', isEqualTo: false)
        .where(
          'lastActiveAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(since),
        ),
  );

  // onPartyCreated/onPlaceCreated(functions/index.js)가 문서 생성 시 항상
  // isTestAccount를 채워두므로(호스트 계정 기준), 등호 필터로 실사용자가
  // 누락되지 않는다.
  static Future<int> totalParties() => _count(
    _db.collection('parties').where('isTestAccount', isEqualTo: false),
  );

  static Future<int> totalPlaces() =>
      _count(_db.collection('places').where('isTestAccount', isEqualTo: false));

  static Future<int> totalPartyShops() => _count(_db.collection('partyShops'));

  /// applicants 배열 길이 합산 — 초기 규모(파티 수 적음)에선 전체 문서를 읽어도
  /// 무리 없지만, 파티 수가 크게 늘면 카운터 필드로 전환하는 게 좋다.
  static Future<int> totalApplications() async {
    final snap = await _db.collection('parties').get();
    var total = 0;
    for (final doc in snap.docs) {
      final applicants = doc.data()['applicants'] as List?;
      total += applicants?.length ?? 0;
    }
    return total;
  }

  // parties/{partyId}/applications 컬렉션 그룹의 보안 규칙은 문서마다 다른
  // partyId로 get()을 호출해 hostId를 확인하는 조건이 있어(firestore.rules),
  // 여러 파티에 걸친 컬렉션 그룹 쿼리를 클라이언트가 직접 실행하면 관리자라도
  // PERMISSION_DENIED가 난다(applicationsForUser가 adminGetUserApplications을
  // 거치는 것과 동일한 제약). 그래서 이 집계도 Admin SDK를 쓰는
  // adminGetApplicationStatusCount onCall을 거친다.
  /// 실제 **현장 출석**을 세라는 특별한 값 — 신청 상태가 아니다.
  ///
  /// 예전의 '실제 참여 수'는 status=='attended'를 셌는데, 그 상태를 쓰는 코드가
  /// 서버·앱 어디에도 없어 언제나 0이었다. 이제 호스트가 QR을 찍으면 신청
  /// 문서에 checkedInAt이 남고 그것이 출석의 정본이다(functions/partyCheckIn.js).
  /// 서버도 같은 문자열을 안다(functions/memberManagement.js의 CHECKED_IN).
  static const checkedInStatus = 'checked_in';

  static Future<int> applicationsByStatus(String status) async {
    final result = await FirebaseFunctions.instanceFor(
      region: _functionsRegion,
    ).httpsCallable('adminGetApplicationStatusCount').call({'status': status});
    return (result.data['count'] as num?)?.toInt() ?? 0;
  }

  static Future<int> pendingFeedbackCount() => _count(
    _db.collection('feedbackRequests').where('status', isEqualTo: 'received'),
  );

  static Future<int> pendingReportCount() =>
      _count(_db.collection('reports').where('status', isEqualTo: 'received'));

  // ── 회원 목록 (페이지네이션) ────────────────────────────────────────

  static const List<int> pageSizeOptions = [50, 100];

  /// 통합 회원 목록의 필터 조합. Firestore는 한 쿼리에서 범위(부등호) 필터를
  /// 한 필드에만 걸 수 있어, 가입기간(createdAt) > 연령대(birthYear) >
  /// 최근활동(lastLoginAt) 순으로 딱 하나만 적용하고 orderBy도 그 필드로
  /// 강제한다 — 화면에서도 이 세 필터를 동시에 켜지 않도록 배타적으로
  /// 보여준다. 나머지(본인확인/성별/활동유형/계정상태/가입경로/테스트계정)는
  /// 전부 등호(==) 조건이라 자유롭게 함께 쓸 수 있다.
  ///
  /// "지역" 필터는 여기 없다 — users 문서 자체엔 지역 필드가 없고(활동 기준
  /// 근사치인 userStats.favoriteRegion만 있음), 목록을 그 필드로 실시간
  /// 필터링하려면 컬렉션 간 조인이 필요해 이번 범위에서는 지원하지 않는다
  /// (지역별 분포는 "이용 통계" 화면의 집계 카드로만 확인 가능).
  /// 이 회원 문서를 "테스트 계정"으로 볼지 — **명시적으로 true일 때만** 그렇다.
  ///
  /// 필드가 없는 문서는 테스트 계정이 아니다. 이 한 줄이 이번 수정의 핵심이다:
  /// 예전에는 서버 쿼리에서 `isTestAccount == false`로 걸렀는데, Firestore의
  /// 등호 필터는 **필드가 없는 문서를 아예 매칭하지 않는다.** 그래서 필드가
  /// 채워지기 전에 만들어진 정상 회원이 목록에서 통째로 사라졌다.
  ///
  /// `!=` 필터로 바꿔도 같은 문제가 남는다(Firestore의 `!=`도 필드가 없는
  /// 문서를 제외한다). 그래서 서버에서는 아예 거르지 않고, 받아온 페이지에서
  /// 이 판정으로 제외한다.
  static bool isTestAccountDoc(Map<String, dynamic> data) =>
      data['isTestAccount'] == true;

  static Query<Map<String, dynamic>> usersBaseQuery({
    bool? identityVerified,
    String? gender,
    DateTime? joinedFrom,
    DateTime? joinedTo,
    int? ageMin,
    int? ageMax,
    DateTime? lastLoginSince,
    String? activityRole,
    String? accountStatus,
    String? signupProvider,
    MemberSortField sortField = MemberSortField.createdAt,
  }) {
    Query<Map<String, dynamic>> q = _db.collection('users');
    if (identityVerified != null) {
      q = q.where('identityVerified', isEqualTo: identityVerified);
    }
    if (gender != null && gender.isNotEmpty) {
      q = q.where('gender', isEqualTo: gender);
    }
    if (activityRole != null && activityRole.isNotEmpty) {
      q = q.where('activityRoles', arrayContains: activityRole);
    }
    if (accountStatus != null && accountStatus.isNotEmpty) {
      q = q.where('accountStatus', isEqualTo: accountStatus);
    }
    if (signupProvider != null && signupProvider.isNotEmpty) {
      q = q.where('signupProvider', isEqualTo: signupProvider);
    }
    // **여기서 테스트 계정을 거르지 않는다.** 예전에는
    // `isTestAccount == false`를 걸었는데, Firestore 등호 필터는 필드가
    // 없는 문서를 매칭하지 않아서 그 필드가 생기기 전에 가입한 정상
    // 회원이 목록에서 통째로 빠졌다(`!=`로 바꿔도 마찬가지다).
    //
    // 대신 받아온 페이지에서 [isTestAccountDoc]으로 제외한다 — 판정이
    // "명시적으로 true인 것만 테스트"가 되어, 필드가 없는 회원은
    // 정상 회원으로 남는다. 덤으로 이 필터가 빠지면서 최근활동
    // 범위 필터에 필요하던 (isTestAccount + lastLoginAt) 복합 색인도
    // 더 이상 필요 없다.

    final hasJoinedRange = joinedFrom != null || joinedTo != null;
    final hasAgeRange = ageMin != null || ageMax != null;
    final hasLoginRange = lastLoginSince != null;

    var effectiveSort = sortField;
    if (hasJoinedRange) {
      if (joinedFrom != null) {
        q = q.where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(joinedFrom),
        );
      }
      if (joinedTo != null) {
        q = q.where(
          'createdAt',
          isLessThanOrEqualTo: Timestamp.fromDate(joinedTo),
        );
      }
      effectiveSort = MemberSortField.createdAt;
    } else if (hasAgeRange) {
      final thisYear = DateTime.now().year;
      // 나이가 클수록 birthYear는 작다 — ageMax(더 나이 많음) → birthYear 하한.
      if (ageMax != null) {
        q = q.where('birthYear', isGreaterThanOrEqualTo: thisYear - ageMax);
      }
      if (ageMin != null) {
        q = q.where('birthYear', isLessThanOrEqualTo: thisYear - ageMin);
      }
      effectiveSort = MemberSortField.birthYear;
    } else if (hasLoginRange) {
      q = q.where(
        'lastLoginAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(lastLoginSince),
      );
      effectiveSort = MemberSortField.lastLoginAt;
    }

    return q.orderBy(
      effectiveSort.fieldPath,
      descending: effectiveSort.descending,
    );
  }

  /// [usersBaseQuery]와 **같은 조건**을 이미 받아 온 문서 하나에 건다.
  ///
  /// 필터가 걸린 목록의 '전체 N명'을 사람 수로 바꿀 때, 조건 안에 든 동일인
  /// 계정만 골라 빼기 위해 쓴다. 쿼리와 어긋나면 숫자가 틀리므로 한 줄씩
  /// 대응시켜 둔다 — Firestore 등호·범위 필터는 필드가 없는 문서를 매칭하지
  /// 않고, orderBy는 정렬 필드가 없는 문서를 뺀다.
  static bool matchesUsersFilter(
    Map<String, dynamic> d, {
    bool? identityVerified,
    String? gender,
    DateTime? joinedFrom,
    DateTime? joinedTo,
    int? ageMin,
    int? ageMax,
    DateTime? lastLoginSince,
    String? activityRole,
    String? accountStatus,
    String? signupProvider,
    MemberSortField sortField = MemberSortField.createdAt,
  }) {
    if (identityVerified != null && d['identityVerified'] != identityVerified) return false;
    if (gender != null && gender.isNotEmpty && d['gender'] != gender) return false;
    if (activityRole != null && activityRole.isNotEmpty) {
      final roles = d['activityRoles'];
      if (roles is! List || !roles.contains(activityRole)) return false;
    }
    if (accountStatus != null && accountStatus.isNotEmpty && d['accountStatus'] != accountStatus) {
      return false;
    }
    if (signupProvider != null && signupProvider.isNotEmpty && d['signupProvider'] != signupProvider) {
      return false;
    }

    DateTime? ts(String k) => d[k] is Timestamp ? (d[k] as Timestamp).toDate() : null;

    var effectiveSort = sortField;
    if (joinedFrom != null || joinedTo != null) {
      final t = ts('createdAt');
      if (t == null) return false;
      if (joinedFrom != null && t.isBefore(joinedFrom)) return false;
      if (joinedTo != null && t.isAfter(joinedTo)) return false;
      effectiveSort = MemberSortField.createdAt;
    } else if (ageMin != null || ageMax != null) {
      final y = d['birthYear'];
      if (y is! num) return false;
      final thisYear = DateTime.now().year;
      if (ageMax != null && y < thisYear - ageMax) return false;
      if (ageMin != null && y > thisYear - ageMin) return false;
      effectiveSort = MemberSortField.birthYear;
    } else if (lastLoginSince != null) {
      final t = ts('lastLoginAt');
      if (t == null || t.isBefore(lastLoginSince)) return false;
      effectiveSort = MemberSortField.lastLoginAt;
    }
    return d.containsKey(effectiveSort.fieldPath);
  }

  /// 필터가 적용된 상태에서 "조건에 맞는 전체 회원 수" — 머리줄의 '전체 N명'.
  ///
  /// **목록과 똑같은 쿼리를 세어야 한다.** 그래서 [usersBaseQuery]를 그대로
  /// 재사용한다. 예전에는 필터 조건을 여기에 한 벌 더 적어 뒀는데, 그 사본에는
  /// `orderBy`가 없었다 — Firestore는 정렬 필드가 **없는 문서를 목록에서
  /// 제외**하므로, 목록은 못 가져오는 문서까지 총계에만 잡혀 "전체 5명인데
  /// 2줄"이 될 수 있었다(정렬 필드가 빠진 문서가 실제로 있다).
  ///
  /// 테스트 계정은 목록과 같은 기준으로 뺀다 — 조건에 맞는 전체에서
  /// **명시적으로 `isTestAccount == true`인 수**만 뺀다. 등호는 필드가 없는
  /// 문서를 매칭하지 않으므로, 필드 없는 정상 회원이 총계에서 빠지지 않는다.
  static Future<int> usersCountForFilter({
    bool? identityVerified,
    String? gender,
    DateTime? joinedFrom,
    DateTime? joinedTo,
    int? ageMin,
    int? ageMax,
    DateTime? lastLoginSince,
    String? activityRole,
    String? accountStatus,
    String? signupProvider,
    bool showTestAccounts = false,
    MemberSortField sortField = MemberSortField.createdAt,
  }) async {
    final q = usersBaseQuery(
      identityVerified: identityVerified,
      gender: gender,
      joinedFrom: joinedFrom,
      joinedTo: joinedTo,
      ageMin: ageMin,
      ageMax: ageMax,
      lastLoginSince: lastLoginSince,
      activityRole: activityRole,
      accountStatus: accountStatus,
      signupProvider: signupProvider,
      sortField: sortField,
    );
    final total = await _count(q);
    if (showTestAccounts) return total;
    try {
      return total - await _count(q.where('isTestAccount', isEqualTo: true));
    } catch (e) {
      // 이 조합에 쓸 복합 색인이 없으면 뺄셈을 포기하고 전체 수를 돌려준다.
      // 목록(정본)은 클라이언트에서 이미 걸러지므로 화면이 깨지지는 않고,
      // 머리줄 숫자만 테스트 계정을 포함한 값이 된다.
      // ignore: avoid_print
      print('[AdminFirestoreService] 테스트 계정 수 집계 실패 — 총계에 포함됨: $e');
      return total;
    }
  }

  // ── 회원 검색 ───────────────────────────────────────────────────────
  //
  // 전체 컬렉션을 내려받아 로컬 필터링하지 않는다 — UID/이메일은 정확히
  // 일치하는 인덱스 조회, 닉네임/이름은 nicknameLower/nameLower에 대한
  // prefix 범위 쿼리만 사용한다. 닉네임으로 먼저 찾고 없으면 이름으로
  // 재검색한다(두 필드를 한 쿼리로 동시에 OR 검색하려면 Algolia 등 별도
  // 검색 인덱스가 필요해 1단계 범위를 넘어간다).

  static bool looksLikeUid(String s) =>
      RegExp(r'^[A-Za-z0-9]{10,40}$').hasMatch(s);

  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?> findByUid(
    String uid,
  ) async {
    final snap = await _db
        .collection('users')
        .where(FieldPath.documentId, isEqualTo: uid)
        .get();
    return snap.docs.isEmpty ? null : snap.docs.first;
  }

  static Query<Map<String, dynamic>> emailExactQuery(String emailLower) {
    return _db
        .collection('users')
        .where('emailLower', isEqualTo: emailLower)
        .orderBy('createdAt', descending: true);
  }

  static Query<Map<String, dynamic>> nicknamePrefixQuery(String lower) {
    return _db
        .collection('users')
        .orderBy('nicknameLower')
        .startAt([lower])
        .endAt(['$lower']);
  }

  static Query<Map<String, dynamic>> namePrefixQuery(String lower) {
    return _db.collection('users').orderBy('nameLower').startAt([lower]).endAt([
      '$lower',
    ]);
  }

  // ── 본인확인 사용자 목록 ────────────────────────────────────────────

  static Query<Map<String, dynamic>> verifiedUsersQuery() {
    return _db
        .collection('users')
        .where('identityVerified', isEqualTo: true)
        .orderBy('identityVerifiedAt', descending: true);
  }

  // ── 의견·버그 신고 (feedbackRequests) ───────────────────────────────
  //
  // 앱의 '의견 보내기'가 쌓는 컬렉션이다(party_app의 FeedbackService.submit).
  // 개선 제안·버그 신고·이용 문의·기타가 **한 컬렉션에 유형(type)으로만**
  // 갈려 들어온다 — '시스템 오류'(systemFunctionErrors, 스케줄 함수 실패
  // 로그)와는 아무 관계가 없다.
  //
  // 첨부 이미지는 Firebase Storage가 아니라 **Cloudflare R2 공개 URL**이
  // `imageUrls` 배열에 그대로 들어 있다(앱이 업로드 후 URL만 저장).
  //
  // 작성자는 `userId`(UID)만 저장된다 — 닉네임은 없으므로 화면에서
  // [fetchUsersForUids]로 users 문서를 붙여 보여준다.

  /// 접수 순(최신)으로 전부 가져온다 — **유형·상태 필터는 서버에 걸지 않는다.**
  ///
  /// `where('type'|'status') + orderBy('createdAt')`에는 복합 색인이 필요한데,
  /// firestore.indexes.json에 정의된 이 컬렉션의 색인은 앱 '내 의견'용
  /// `(userId ASC, createdAt DESC)` 하나뿐이다(그 조합은 실제로
  /// FAILED_PRECONDITION으로 실패하는 것을 확인했다). 색인을 새로 배포하지
  /// 않고도 화면이 동작하도록 필터는 화면에서 건다 — 접수 건수가 적어 200건
  /// 상한으로 충분하다.
  ///
  /// ── 서버 필터로 옮길 때 필요한 색인 ────────────────────────────────────
  ///
  /// 건수가 늘어 200건 상한이 모자라지면 아래를 firestore.indexes.json의
  /// `indexes` 배열에 넣고 `firebase deploy --only firestore:indexes`로 배포한
  /// 뒤, 이 함수에 type/status 파라미터를 되살리면 된다.
  ///
  /// ```json
  /// { "collectionGroup": "feedbackRequests", "queryScope": "COLLECTION",
  ///   "fields": [ { "fieldPath": "type",      "order": "ASCENDING" },
  ///               { "fieldPath": "createdAt", "order": "DESCENDING" } ] },
  /// { "collectionGroup": "feedbackRequests", "queryScope": "COLLECTION",
  ///   "fields": [ { "fieldPath": "status",    "order": "ASCENDING" },
  ///               { "fieldPath": "createdAt", "order": "DESCENDING" } ] }
  /// ```
  ///
  /// 유형과 상태를 **동시에** 서버에서 걸려면 세 번째로
  /// `(type ASC, status ASC, createdAt DESC)`도 필요하다 — 두 필드짜리 색인
  /// 두 벌로는 그 조합이 처리되지 않는다.
  static Query<Map<String, dynamic>> feedbackRequestsQuery() =>
      _db.collection('feedbackRequests').orderBy('createdAt', descending: true);

  /// 목록에 붙일 작성자 표시용 users 문서 — uid → 문서 데이터.
  ///
  /// [fetchUserStatsForUids]와 같은 방식이다(문서 ID whereIn, 30개씩 나눠서).
  /// 없는 uid는 결과에서 빠지고, 호출부가 '(알 수 없음)'으로 그린다 —
  /// **uid를 닉네임 자리에 대신 넣지 않는다.**
  static Future<Map<String, Map<String, dynamic>>> fetchUsersForUids(
    List<String> uids,
  ) async {
    if (uids.isEmpty) return {};
    final result = <String, Map<String, dynamic>>{};
    const chunkSize = 30;
    final chunks = <List<String>>[];
    for (var i = 0; i < uids.length; i += chunkSize) {
      chunks.add(
        uids.sublist(
          i,
          i + chunkSize > uids.length ? uids.length : i + chunkSize,
        ),
      );
    }
    final snaps = await Future.wait(
      chunks.map(
        (chunk) => _db
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
      ),
    );
    for (final snap in snaps) {
      for (final doc in snap.docs) {
        result[doc.id] = doc.data();
      }
    }
    return result;
  }

  /// 처리 상태·메모·답변만 고친다.
  ///
  /// firestore.rules가 관리자에게도 `status`/`userReply`/`adminMemo`/
  /// `updatedAt` **네 필드만** 허용한다 — 원문·작성자·첨부는 위변조할 수 없다.
  /// 여기서 그 넷만 보내는 이유이고, 더 보내면 규칙이 통째로 거부한다.
  static Future<void> updateFeedbackRequest(
    String id, {
    required String status,
    String? adminMemo,
    String? userReply,
  }) => _db.collection('feedbackRequests').doc(id).update({
    'status': status,
    'adminMemo': ?adminMemo,
    'userReply': ?userReply,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  // ── 신고(reports) ─────────────────────────────────────────────────────
  //
  // 앱의 신고 제출은 party_app/lib/services/report_service.dart 하나뿐이고,
  // 문서 id는 "{신고자}_{대상종류}_{대상id}"다 — 같은 사람이 같은 대상을 두 번
  // 신고할 수 없게 하는 장치이고, 관리자도 이 id를 그대로 본다.
  //
  // 정렬 필드가 하나뿐이라 복합 색인이 필요 없다. 유형·상태 필터와 검색은
  // 화면에서 건다(feedbackRequestsQuery와 같은 이유).

  static Query<Map<String, dynamic>> reportsQuery() =>
      _db.collection('reports').orderBy('createdAt', descending: true);

  /// 신고 처리상태 변경 — **상태와 메모만** 바꾼다.
  ///
  /// ⚠️ 신고 처리는 대상 문서나 상대 계정을 건드리지 않는다. 신고가 곧
  /// 처벌이 되면 신고 자체가 공격 수단이 되기 때문이다(자동 삭제·자동 정지
  /// 경로를 만들지 않는다는 결정 — firestore.rules의 reports 주석 참고).
  /// 규칙도 status/adminMemo/updatedAt/resolvedAt 외의 필드 변경을 막는다.
  static Future<void> updateReport(
    String id, {
    required String status,
    String? adminMemo,
  }) {
    // 종료 상태로 넘어갈 때만 처리 시각을 남긴다 — 되돌려도 지우지 않는다
    // (언제 한 번 닫혔는지가 기록으로 남는 편이 낫다).
    final closing = status == 'resolved' || status == 'rejected';
    return _db.collection('reports').doc(id).update({
      'status': status,
      'adminMemo': ?adminMemo,
      'updatedAt': FieldValue.serverTimestamp(),
      if (closing) 'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── 차단 내역(userBlocks) ─────────────────────────────────────────────
  //
  // ⚠️ **전체 차단 관계를 볼 수 있는 것은 관리자뿐이다.** 규칙의 list 조건이
  // "resource.data.blockerId == uid() || isAdmin()"이라, 일반 사용자는 자기가
  // 건 차단만 조회할 수 있고 "누가 나를 차단했는지"는 어떤 쿼리로도 알 수
  // 없다(firestore.rules의 userBlocks 주석). 이 화면이 그 유일한 예외다.
  //
  // **조회만 한다.** 관리자가 남의 차단을 풀거나 새로 거는 경로는 두지 않는다 —
  // 차단은 그 사람이 자기 화면을 위해 건 것이고 운영이 대신 판단할 일이 아니다.
  static Query<Map<String, dynamic>> userBlocksQuery() =>
      _db.collection('userBlocks').orderBy('createdAt', descending: true);

  // ── 시스템 오류(스케줄 함수 실패) 목록 ────────────────────────────────
  // logScheduledFunctionError(memberActivityHelpers.js)가 Admin SDK로만
  // 기록한다 — 정렬 필드가 하나뿐이라 별도 복합 인덱스가 필요 없다.
  static Query<Map<String, dynamic>> systemFunctionErrorsQuery({
    int limit = 100,
  }) {
    return _db
        .collection('systemFunctionErrors')
        .orderBy('occurredAt', descending: true)
        .limit(limit);
  }

  static Future<int> recentSystemFunctionErrorsCount({
    Duration within = const Duration(hours: 24),
  }) => _count(
    _db
        .collection('systemFunctionErrors')
        .where(
          'occurredAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            DateTime.now().subtract(within),
          ),
        ),
  );

  // ── 회원 상세 ───────────────────────────────────────────────────────

  // parties/{partyId}/applications 컬렉션 그룹의 보안 규칙이 get()으로 파티
  // 문서의 hostId를 조회하는 조건을 포함하고 있어, 클라이언트가 이 컬렉션
  // 그룹을 직접 쿼리하면 관리자라도 PERMISSION_DENIED가 난다(party_app의
  // party_applicants_screen.dart가 getApplicants Function으로 전환했던 것과
  // 동일한 제약). 그래서 이 조회만 Admin SDK를 쓰는 adminGetUserApplications
  // onCall을 거친다 — 반환값은 ISO 문자열이라 Timestamp로 다시 감싼다.

  /// 탈퇴·재가입으로 이어진 계정들.
  ///
  /// identityLinks는 보안 규칙이 read/write를 전부 막아 둔 컬렉션이라(해시만으로
  /// "이 CI가 가입돼 있나"를 조회하는 채널이 되면 안 된다) 클라이언트가 직접
  /// 읽을 수 없다. Admin SDK를 거치는 onCall이 유일한 통로다.
  ///
  /// 본인확인을 마치지 않은 회원은 CI가 없어 연결 자체가 없다 — `linked: false`로
  /// 돌아오며, 오류가 아니라 "추적할 근거가 없음"을 뜻한다.
  static Future<Map<String, dynamic>> accountLinkHistory(String uid) async {
    final result = await FirebaseFunctions.instanceFor(
      region: _functionsRegion,
    ).httpsCallable('adminGetAccountLinkHistory').call({'targetUid': uid});
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<List<Map<String, dynamic>>> applicationsForUser(
    String uid,
  ) async {
    final result = await FirebaseFunctions.instanceFor(
      region: _functionsRegion,
    ).httpsCallable('adminGetUserApplications').call({'targetUid': uid});
    final list = (result.data['applications'] as List?) ?? const [];
    Timestamp? parseTs(dynamic v) =>
        v is String ? Timestamp.fromDate(DateTime.parse(v)) : null;
    return list.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      return {
        'partyId': m['partyId'],
        'status': m['status'],
        'region': m['region'],
        'appliedAt': parseTs(m['appliedAt']),
        'statusUpdatedAt': parseTs(m['statusUpdatedAt']),
        'partyDateTime': parseTs(m['partyDateTime']),
      };
    }).toList();
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  favoritesForUser(String uid) async {
    final snap = await _db
        .collection('favorites')
        .where('userId', isEqualTo: uid)
        .get();
    return snap.docs;
  }

  // ── userStats (요약 이용 통계, users와 분리된 컬렉션) ────────────────

  /// 페이지에 보이는 회원들의 신청/실제이용 횟수 컬럼을 채우기 위해 uid 목록을
  /// 한 번에 조회한다. Firestore documentId whereIn은 최대 30개까지만 지원해
  /// 페이지당 최대 100명이면 4번까지 청크로 나눠 병렬 조회한다(행마다 개별
  /// 조회하는 N+1 패턴을 피하기 위함).
  static Future<Map<String, Map<String, dynamic>>> fetchUserStatsForUids(
    List<String> uids,
  ) async {
    if (uids.isEmpty) return {};
    final result = <String, Map<String, dynamic>>{};
    const chunkSize = 30;
    final chunks = <List<String>>[];
    for (var i = 0; i < uids.length; i += chunkSize) {
      chunks.add(
        uids.sublist(
          i,
          i + chunkSize > uids.length ? uids.length : i + chunkSize,
        ),
      );
    }
    final snaps = await Future.wait(
      chunks.map(
        (chunk) => _db
            .collection('userStats')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
      ),
    );
    for (final snap in snaps) {
      for (final doc in snap.docs) {
        result[doc.id] = doc.data();
      }
    }
    return result;
  }

  static Future<Map<String, dynamic>?> userStatsForUser(String uid) async {
    final doc = await _db.collection('userStats').doc(uid).get();
    return doc.data();
  }

  // ── 이용 통계 화면 ──────────────────────────────────────────────────

  static Query<Map<String, dynamic>> usageStatsBaseQuery({
    UsageSortField sortField = UsageSortField.totalApplications,
  }) {
    return _db
        .collection('userStats')
        .orderBy(sortField.fieldPath, descending: true);
  }

  static Future<int> usageStatsCount() => _count(_db.collection('userStats'));

  /// 인기 지역 Top N — regionStats는 전 기간 누적이라 문서 몇 개만 읽으면 된다
  /// (매번 applications 전체를 스캔하지 않음).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> topRegions({
    int limit = 5,
  }) async {
    final snap = await _db
        .collection('regionStats')
        .orderBy('totalApplications', descending: true)
        .limit(limit)
        .get();
    return snap.docs;
  }

  /// 시간대별 통계 24개 문서 전체 — 문서 id가 "0".."23" 문자열이라 그대로
  /// 정렬하면 사전식 순서("10"<"2")로 어긋나므로 hour 필드 기준으로 다시
  /// 정렬한다.
  static Future<List<Map<String, dynamic>>> hourlyStatsAll() async {
    final snap = await _db.collection('hourlyStats').get();
    final list = snap.docs.map((d) => d.data()).toList();
    list.sort(
      (a, b) => ((a['hour'] as num?) ?? 0).compareTo((b['hour'] as num?) ?? 0),
    );
    return list;
  }

  /// 전체 조회수 — hourlyStats.partyViews 합산(regionStats.totalViews는 조회
  /// 이벤트에 지역 정보가 없을 때가 많아 신청 기준 집계만큼 촘촘하지 않다).
  static Future<int> totalPartyViewsAllTime() async {
    final hours = await hourlyStatsAll();
    var total = 0;
    for (final h in hours) {
      total += (h['partyViews'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  // ── 회원 통계 보강 (성별 · 연령대 · 가입 경로 · 가입 추이 · 지역) ────

  /// 성별 인원수 — {'male': n, 'female': n}. 본인인증 전에는 gender가 없어
  /// 두 값의 합이 totalUsers보다 작을 수 있다.
  static Future<Map<String, int>> genderCounts() async {
    final male = await _count(
      _db.collection('users').where('gender', isEqualTo: 'male'),
    );
    final female = await _count(
      _db.collection('users').where('gender', isEqualTo: 'female'),
    );
    return {'male': male, 'female': female};
  }

  /// 연령대 분포 — birthYear 기준 5개 구간(본인인증 완료자만 birthYear가
  /// 있어, 미인증 회원은 어느 구간에도 잡히지 않는다).
  static Future<Map<String, int>> ageBucketCounts() async {
    final thisYear = DateTime.now().year;
    const buckets = <String, (int minAge, int? maxAge)>{
      '10대 이하': (0, 19),
      '20대': (20, 29),
      '30대': (30, 39),
      '40대': (40, 49),
      '50대 이상': (50, null),
    };
    final result = <String, int>{};
    for (final entry in buckets.entries) {
      final (minAge, maxAge) = entry.value;
      Query<Map<String, dynamic>> q = _db
          .collection('users')
          .where('birthYear', isLessThanOrEqualTo: thisYear - minAge);
      if (maxAge != null) {
        q = q.where('birthYear', isGreaterThanOrEqualTo: thisYear - maxAge);
      }
      result[entry.key] = await _count(q);
    }
    return result;
  }

  /// 가입 경로 인원수 — {'google': n, 'kakao': n, 'naver': n}. 이 필드
  /// 도입 이전 가입자는 signupProvider가 없어 세 값에 잡히지 않는다.
  static Future<Map<String, int>> signupProviderCounts() async {
    final result = <String, int>{};
    for (final provider in const ['google', 'kakao', 'naver']) {
      result[provider] = await _count(
        _db.collection('users').where('signupProvider', isEqualTo: provider),
      );
    }
    return result;
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 최근 [days]일간 일별 신규 가입자 수 — dailyStats 문서 id가 "yyyy-MM-dd"라
  /// 사전순 정렬이 곧 날짜순이라 문서 id 범위 쿼리로 바로 가져온다. 주별/월별
  /// 합산은 화면에서 이 리스트를 그대로 묶어 계산한다(추가 Firestore 읽기 없음).
  static Future<List<MapEntry<String, int>>> dailySignupTrend({
    int days = 30,
  }) async {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: days - 1));
    final snap = await _db
        .collection('dailyStats')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: _dateKey(start))
        .where(FieldPath.documentId, isLessThanOrEqualTo: _dateKey(now))
        .get();
    final byDate = {
      for (final d in snap.docs)
        d.id: (d.data()['newUsers'] as num?)?.toInt() ?? 0,
    };
    return [
      for (var i = 0; i < days; i++)
        MapEntry(
          _dateKey(start.add(Duration(days: i))),
          byDate[_dateKey(start.add(Duration(days: i)))] ?? 0,
        ),
    ];
  }

  /// 지역별 가입자 수(근사치) — 실제 거주지 필드가 없어 userStats.favoriteRegion
  /// ("가장 신청을 많이 한 지역", "{region1}_{region2}" 형식)로 대체한다.
  /// 신청 이력이 전혀 없는 회원은 favoriteRegion 자체가 없어 잡히지 않으므로,
  /// 엄밀히는 "가입자 수"가 아니라 "활동 지역별 회원 수"에 가깝다.
  static Future<Map<String, int>> signupRegionCounts() async {
    final counts = await Future.wait(
      kRegions1.map((region) {
        final q = _db
            .collection('userStats')
            .where('favoriteRegion', isGreaterThanOrEqualTo: '${region}_')
            .where('favoriteRegion', isLessThan: '${region}_');
        return _count(q);
      }),
    );
    return {for (var i = 0; i < kRegions1.length; i++) kRegions1[i]: counts[i]};
  }

  // ── 회원 상세 — 통합 활동 타임라인 ───────────────────────────────────

  /// 이 회원의 통합 활동 타임라인(가입/로그인/파티·플레이스·상품·크루
  /// 등록/신청·승인·취소/찜/공유/관리자 상태변경 등) 최신순 N건.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  activityLogsForUser(String uid, {int limit = 50}) async {
    final snap = await _db
        .collection('userActivityLogs')
        .where('uid', isEqualTo: uid)
        .orderBy('occurredAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs;
  }
}
