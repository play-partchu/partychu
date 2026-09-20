import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/business_info.dart';
import '../services/admin_firestore_service.dart';
import '../services/person_identity_service.dart';
import '../theme/admin_theme.dart';
import '../utils/member_identity_sort.dart';
import '../utils/person_identity.dart';
import '../utils/phone_display.dart';
import '../utils/responsive.dart';

typedef OpenMember = void Function(String uid);

/// 회원 목록 '나이' 칸 문구 — `91년생 · 36세`.
///
/// 정본은 **본인확인(NICE)이 저장한 `birthYear` 하나**다(`functions/niceAuth.js`가
/// 인증 결과의 생년월일에서 잘라 넣는다). 나이를 따로 저장하지 않으므로 해가
/// 바뀌면 이 계산이 저절로 한 살을 올린다 — 그래서 여기서 계산한다.
///
/// 한국 나이 = **올해 - 출생연도 + 1**. 생일이 지났는지는 보지 않는다.
///
/// 본인확인 전이라 `birthYear`가 없으면 `-`. 없는 값을 0살이나 올해 출생으로
/// 추측하지 않는다.
///
/// ── 예전에 붙어 있던 `(2)` ─────────────────────────────────────────────────
///
/// 나이 뒤에 `36세 (2)`처럼 숫자가 하나 더 붙어 있었다. 어딘가에서 읽어 온
/// 값이 아니라 **성별과 출생연도로 만들어 낸 주민등록번호 뒷자리 첫 숫자**였다
/// (2000년 이전 출생 남1·여2, 이후 남3·여4). 나이 칸에서 읽을 이유가 없는 값인
/// 데다 민감정보로 오해되기 쉬워, 표시도 계산도 함께 지웠다.
///
/// [now]는 테스트에서만 넘긴다(`test/member_age_label_test.dart`).
String memberAgeLabel(int? birthYear, {DateTime? now}) {
  if (birthYear == null) return '-';
  final yy = (birthYear % 100).toString().padLeft(2, '0');
  final koreanAge = (now ?? DateTime.now()).year - birthYear + 1;
  return '$yy년생 · $koreanAge세';
}

/// 생년월일 표기 — `1991.03.15`. 월/일이 없는 옛 기록은 연도만(`1991`),
/// 본인확인 전이라 연도조차 없으면 `-`.
///
/// 값의 출처는 본인확인(NICE)이 저장한 birthYear/Month/Day뿐이다
/// (`functions/niceAuth.js`). 없는 값을 가입일 등으로 **추측하지 않는다.**
String memberBirthDateLabel(int? year, int? month, int? day) {
  if (year == null) return '-';
  if (month == null || day == null) return '$year';
  return '$year.${month.toString().padLeft(2, '0')}.${day.toString().padLeft(2, '0')}';
}

/// 가입기간/연령대/최근활동은 Firestore 제약상 한 번에 하나만 걸 수 있어
/// (admin_firestore_service.dart의 usersBaseQuery 주석 참고) 이 중 어떤
/// 필터가 "현재 켜진 기간 필터"인지 하나로 관리한다.
enum _RangeFilterType { none, joined, age, activeSince }

class _AgeBucketOption {
  final String label;
  final int? minAge;
  final int? maxAge;
  const _AgeBucketOption(this.label, this.minAge, this.maxAge);
}

const _ageBuckets = [
  _AgeBucketOption('10대 이하', 0, 19),
  _AgeBucketOption('20대', 20, 29),
  _AgeBucketOption('30대', 30, 39),
  _AgeBucketOption('40대', 40, 49),
  _AgeBucketOption('50대 이상', 50, null),
];

/// 활동 배지 라벨/색 — users.activityRoles 배열 값 → 화면 표시.
const _activityRoleLabels = {
  'host_activity': '호스트',
  'guest_activity': '게스트',
  'place_operator': '플레이스',
  'shop_seller': '파티샵',
  'crew_recruiting': '크루 구인',
  'crew_seeking': '크루 구직',
};

const _accountStatusLabels = {
  'active': '정상',
  'dormant': '휴면',
  'restricted': '이용제한',
  'withdrawn': '탈퇴',
};

const _signupProviderLabels = {
  'google': '구글',
  'kakao': '카카오',
  'naver': '네이버',
  'apple': 'Apple',
};

class MembersScreen extends StatefulWidget {
  final OpenMember onOpenMember;
  const MembersScreen({super.key, required this.onOpenMember});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool? _identityVerifiedFilter;
  String? _genderFilter;
  String? _activityRoleFilter;
  String? _accountStatusFilter;
  String? _signupProviderFilter;
  bool _showTestAccounts = false;

  _RangeFilterType _rangeFilterType = _RangeFilterType.none;
  DateTimeRange? _joinedRange;
  _AgeBucketOption? _ageBucket;
  int _activeSinceDays = 7;

  MemberSortField _sortField = MemberSortField.createdAt;

  /// '본인확인' 열의 정렬 — 상단 필터와 **역할이 다르다.**
  /// 상단 필터는 어떤 상태만 골라 볼지(서버 쿼리), 이 값은 그렇게 받아 온
  /// 결과 안에서 완료/미완료 순서를 어떻게 세울지(화면)를 정한다.
  ///
  /// 첫 진입 기본값이 [IdentitySortOrder.verifiedFirst]라, 필터를 건드리지
  /// 않아도 실제 인증된 회원이 위에 온다.
  IdentitySortOrder _identitySort = IdentitySortOrder.verifiedFirst;

  int _pageSize = AdminFirestoreService.pageSizeOptions.first;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  // 목록에서 활동·통계 열을 걷어내면서 userStats 조회도 함께 없앴다 —
  // 페이지를 넘길 때마다 아무도 읽지 않는 문서를 최대 100건씩 받아오던
  // 자리다. 그 수치는 회원 상세와 '이용 통계' 화면이 그대로 보여준다.
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _pageStartStack = [null];
  int _pageIndex = 0;
  bool _hasNextPage = false;
  bool _loading = true;
  bool _searchMode = false;
  String? _searchNotice;

  /// 머리줄 '전체 N명' — **실제 회원 수**(동일인 계정은 1명).
  int? _filteredTotal;

  /// 같은 조건의 계정 수 — 사람 수와 다를 때만 곁에 적는다.
  int? _filteredAccountTotal;

  /// 동일인 키 → 그 사람의 계정 전부(본인확인 계정 기준). 행에 '계정 N개'를
  /// 붙이는 데 쓴다. 불러오기 전이나 실패하면 비어 있고, 그때도 같은 페이지
  /// 안의 동일인은 CI 키만으로 묶인다.
  Map<String, PersonGroup> _people = const {};

  /// 페이지별로 이미 그린 사람들 — 다음 페이지에 같은 사람의 다른 계정이
  /// 또 나오면 감추기 위해 남긴다. 페이지는 첫 페이지부터 차례로만 넘어가므로
  /// 앞 페이지 기록이 항상 먼저 채워져 있다.
  final Map<int, Set<String>> _shownKeysByPage = {};

  Set<String> _keysShownBefore(int pageIndex) => {
        for (final e in _shownKeysByPage.entries)
          if (e.key < pageIndex) ...e.value,
      };

  /// 화면에 그리는 행 — 사람 1명당 한 줄. 같은 사람의 다른 계정은 먼저 나온
  /// 줄에 '계정 N개'로 붙고, 상세에서 모두 보인다.
  ({
    List<QueryDocumentSnapshot<Map<String, dynamic>>> rows,
    Map<QueryDocumentSnapshot<Map<String, dynamic>>, PersonGroup> groups,
    int collapsed,
    Set<String> shownKeys,
  }) get _personRows => collapsePageByPerson(
        _visibleDocs,
        read: (d) => (d.id, d.data()),
        peopleByKey: _people,
        alreadyShownKeys: _searchMode ? const {} : _keysShownBefore(_pageIndex),
      );


  /// 화면에 실제로 그리는 행 — 받아온 페이지에서 **명시적으로 테스트로 표시된
  /// 계정만** 뺀다.
  ///
  /// 서버 쿼리에서 거르지 않는 이유는 [AdminFirestoreService.isTestAccountDoc]에
  /// 적어 뒀다: Firestore 등호/부등호 필터는 필드가 없는 문서를 매칭하지 않아,
  /// `isTestAccount == false`로 거르면 그 필드가 생기기 전에 가입한 **정상
  /// 회원까지 목록에서 사라진다.**
  ///
  /// 검색 결과는 거르지 않는다 — UID·이메일을 정확히 찍어 찾은 것이라 "찾았는데
  /// 안 보인다"가 더 나쁘다(예전 동작도 그랬다). 대신 그때는 '테스트' 열을 켜서
  /// 어느 줄이 테스트 계정인지 밝힌다.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visibleDocs =>
      (_showTestAccounts || _searchMode)
          ? _docs
          : _docs
              .where((d) => !AdminFirestoreService.isTestAccountDoc(d.data()))
              .toList();

  /// 이 페이지에서 테스트 계정이라 감춘 수 — 페이지 수가 덜 차 보이는 이유를
  /// 하단에 밝히는 데 쓴다.
  int get _hiddenTestCount => _docs.length - _visibleDocs.length;

  /// '테스트' 열을 그릴지 — 테스트 계정이 화면에 섞여 나올 수 있는 때만.
  bool get _showTestColumn => _showTestAccounts || _searchMode;

  bool get _hasRangeFilter => _rangeFilterType != _RangeFilterType.none;

  DateTime? get _activeSinceThreshold =>
      _rangeFilterType == _RangeFilterType.activeSince
          ? DateTime.now().subtract(Duration(days: _activeSinceDays))
          : null;

  @override
  void initState() {
    super.initState();
    _loadPage();
    _loadFilteredTotal();
    _loadPeople();
  }

  Future<void> _loadPeople() async {
    try {
      final people = await PersonIdentityService.peopleByKey();
      if (!mounted) return;
      setState(() {
        _people = people;
        _recordShownKeys();
      });
    } catch (e) {
      // 묶음 정보가 없어도 목록은 그대로 쓸 수 있다 — 같은 페이지 안의
      // 동일인은 여전히 CI 키로 묶인다.
      // ignore: avoid_print
      print('[MembersScreen] 동일인 묶음 조회 실패: $e');
    }
  }

  void _recordShownKeys() {
    if (_searchMode) return;
    _shownKeysByPage[_pageIndex] = _personRows.shownKeys;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> get _filteredQuery => AdminFirestoreService.usersBaseQuery(
        identityVerified: _identityVerifiedFilter,
        gender: _genderFilter,
        activityRole: _activityRoleFilter,
        accountStatus: _accountStatusFilter,
        signupProvider: _signupProviderFilter,
        joinedFrom: _rangeFilterType == _RangeFilterType.joined ? _joinedRange?.start : null,
        joinedTo: _rangeFilterType == _RangeFilterType.joined ? _joinedRange?.end : null,
        ageMin: _rangeFilterType == _RangeFilterType.age ? _ageBucket?.minAge : null,
        ageMax: _rangeFilterType == _RangeFilterType.age ? _ageBucket?.maxAge : null,
        lastLoginSince: _activeSinceThreshold,
        sortField: _sortField,
      );

  Future<void> _loadFilteredTotal() async {
    final accounts = await AdminFirestoreService.usersCountForFilter(
      identityVerified: _identityVerifiedFilter,
      gender: _genderFilter,
      activityRole: _activityRoleFilter,
      accountStatus: _accountStatusFilter,
      signupProvider: _signupProviderFilter,
      showTestAccounts: _showTestAccounts,
      joinedFrom: _rangeFilterType == _RangeFilterType.joined ? _joinedRange?.start : null,
      joinedTo: _rangeFilterType == _RangeFilterType.joined ? _joinedRange?.end : null,
      ageMin: _rangeFilterType == _RangeFilterType.age ? _ageBucket?.minAge : null,
      ageMax: _rangeFilterType == _RangeFilterType.age ? _ageBucket?.maxAge : null,
      lastLoginSince: _activeSinceThreshold,
      sortField: _sortField,
    );
    // 같은 조건 안에 든 동일인 계정만 뺀다 — 조건 밖 계정까지 빼면 한 계정만
    // 조건에 걸린 사람이 사라진다.
    var duplicates = 0;
    try {
      duplicates = await PersonIdentityService.duplicateAccounts(
        where: (d) =>
            (_showTestAccounts || !AdminFirestoreService.isTestAccountDoc(d)) &&
            AdminFirestoreService.matchesUsersFilter(
              d,
              identityVerified: _identityVerifiedFilter,
              gender: _genderFilter,
              activityRole: _activityRoleFilter,
              accountStatus: _accountStatusFilter,
              signupProvider: _signupProviderFilter,
              joinedFrom: _rangeFilterType == _RangeFilterType.joined ? _joinedRange?.start : null,
              joinedTo: _rangeFilterType == _RangeFilterType.joined ? _joinedRange?.end : null,
              ageMin: _rangeFilterType == _RangeFilterType.age ? _ageBucket?.minAge : null,
              ageMax: _rangeFilterType == _RangeFilterType.age ? _ageBucket?.maxAge : null,
              lastLoginSince: _activeSinceThreshold,
              sortField: _sortField,
            ),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[MembersScreen] 동일인 중복 집계 실패 — 계정 수로 표시: $e');
    }
    if (!mounted) return;
    setState(() {
      _filteredAccountTotal = accounts;
      _filteredTotal = accounts - duplicates;
    });
  }

  Future<void> _loadPage() async {
    setState(() => _loading = true);
    final cursor = _pageStartStack[_pageIndex];
    var query = _filteredQuery.limit(_pageSize + 1);
    if (cursor != null) query = query.startAfterDocument(cursor);

    final snap = await query.get();
    final docs = snap.docs;
    final hasNext = docs.length > _pageSize;
    final pageDocs = hasNext ? docs.sublist(0, _pageSize) : docs;

    if (!mounted) return;
    setState(() {
      _docs = pageDocs;
      _hasNextPage = hasNext;
      _loading = false;
      _recordShownKeys();
    });
  }

  void _goFirst() {
    if (_pageIndex == 0) return;
    setState(() => _pageIndex = 0);
    _loadPage();
  }

  void _goNext() {
    if (!_hasNextPage || _docs.isEmpty) return;
    setState(() {
      if (_pageStartStack.length == _pageIndex + 1) {
        _pageStartStack.add(_docs.last);
      }
      _pageIndex++;
    });
    _loadPage();
  }

  void _goPrev() {
    if (_pageIndex == 0) return;
    setState(() => _pageIndex--);
    _loadPage();
  }

  void _resetPaging() {
    _pageStartStack
      ..clear()
      ..add(null);
    _pageIndex = 0;
    _shownKeysByPage.clear();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(value));
  }

  Future<void> _runSearch(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchMode = false;
        _searchNotice = null;
      });
      _resetPaging();
      _loadPage();
      _loadFilteredTotal();
      return;
    }

    setState(() {
      _loading = true;
      _searchMode = true;
      _searchNotice = null;
    });

    List<QueryDocumentSnapshot<Map<String, dynamic>>> results = [];
    String? notice;

    if (AdminFirestoreService.looksLikeUid(trimmed)) {
      final doc = await AdminFirestoreService.findByUid(trimmed);
      if (doc != null) results = [doc];
    }

    if (results.isEmpty && trimmed.contains('@')) {
      final snap = await AdminFirestoreService.emailExactQuery(trimmed.toLowerCase()).limit(_pageSize).get();
      results = snap.docs;
      notice = '이메일 정확히 일치하는 결과입니다.';
    }

    if (results.isEmpty && !trimmed.contains('@')) {
      final lower = trimmed.toLowerCase();
      final nicknameSnap = await AdminFirestoreService.nicknamePrefixQuery(lower).limit(_pageSize).get();
      if (nicknameSnap.docs.isNotEmpty) {
        results = nicknameSnap.docs;
        notice = '닉네임 검색 결과입니다.';
        if (results.length >= _pageSize) notice = '$notice 결과가 많습니다 — 검색어를 더 구체적으로 입력해주세요.';
      } else {
        final nameSnap = await AdminFirestoreService.namePrefixQuery(lower).limit(_pageSize).get();
        results = nameSnap.docs;
        notice = '이름 검색 결과입니다.';
        if (results.length >= _pageSize) notice = '$notice 결과가 많습니다 — 검색어를 더 구체적으로 입력해주세요.';
      }
    }


    if (!mounted) return;
    setState(() {
      _docs = results;
      _hasNextPage = false;
      _loading = false;
      _searchNotice = notice ?? (results.isEmpty ? '검색 결과가 없습니다.' : null);
    });
  }

  void _applyFilters() {
    _resetPaging();
    setState(() {
      _searchMode = false;
      _searchNotice = null;
    });
    _searchCtrl.clear();
    _loadPage();
    _loadFilteredTotal();
  }

  Future<void> _pickJoinedRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: now,
      initialDateRange: _joinedRange,
    );
    if (range != null) {
      setState(() {
        _joinedRange = range;
        _rangeFilterType = _RangeFilterType.joined;
      });
      _applyFilters();
    }
  }

  void _onRangeFilterTypeChanged(_RangeFilterType? type) {
    if (type == null) return;
    setState(() {
      _rangeFilterType = type;
      if (type != _RangeFilterType.joined) _joinedRange = null;
      if (type != _RangeFilterType.age) _ageBucket = null;
    });
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('회원 관리', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (_filteredTotal != null)
              Text(
                  '전체 ${NumberFormat('#,###').format(_filteredTotal)}명'
                  '${_filteredAccountTotal != null && _filteredAccountTotal != _filteredTotal ? ' (계정 ${NumberFormat('#,###').format(_filteredAccountTotal)}개)' : ''}',
                  style: const TextStyle(fontSize: 13, color: AdminTheme.textSecondary)),
          ],
        ),
        const SizedBox(height: 16),
        _buildToolbar(),
        if (_searchNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_searchNotice!, style: const TextStyle(fontSize: 12, color: AdminTheme.textSecondary)),
          ),
        if (_hasRangeFilter && !_searchMode)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('가입기간·연령대·최근활동 필터는 한 번에 하나만 적용되며, 켜져 있는 동안은 정렬이 그 기준으로 고정됩니다.',
                style: TextStyle(fontSize: 12, color: AdminTheme.textSecondary)),
          ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminTheme.cardBorder),
            ),
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AdminTheme.accent))
                : _visibleDocs.isEmpty || (!_isWithdrawnView && _personRows.rows.isEmpty)
                    ? Center(
                        child: Text(
                          _docs.isEmpty
                              ? '회원이 없습니다.'
                              : _visibleDocs.isEmpty
                                  ? '이 페이지는 모두 테스트 계정입니다. 다음 페이지를 확인하세요.'
                                  : '이 페이지는 앞에서 보여 준 회원의 다른 계정뿐입니다. 다음 페이지를 확인하세요.',
                          style: const TextStyle(color: AdminTheme.textSecondary),
                        ),
                      )
                    : _buildTable(),
          ),
        ),
        if (!_searchMode) _buildPagination(),
      ],
    );
  }

  Widget _buildToolbar() {
    final hasAnyFilter = _identityVerifiedFilter != null ||
        _genderFilter != null ||
        _activityRoleFilter != null ||
        _accountStatusFilter != null ||
        _signupProviderFilter != null ||
        _showTestAccounts ||
        _hasRangeFilter ||
        _sortField != MemberSortField.createdAt ||
        _identitySort != IdentitySortOrder.verifiedFirst ||
        _searchMode;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: context.fluid(260),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: '닉네임 · 이름 · 이메일 · UID 검색',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        _LabeledDropdown<bool?>(
          label: '본인확인',
          value: _identityVerifiedFilter,
          options: const [
            (value: null, text: '전체'),
            (value: true, text: '완료'),
            (value: false, text: '미완료'),
          ],
          onChanged: (v) {
            _identityVerifiedFilter = v;
            _applyFilters();
          },
        ),
        _LabeledDropdown<String?>(
          label: '성별',
          value: _genderFilter,
          options: const [
            (value: null, text: '전체'),
            (value: 'male', text: '남성'),
            (value: 'female', text: '여성'),
          ],
          onChanged: (v) {
            _genderFilter = v;
            _applyFilters();
          },
        ),
        // 활동 유형 — "호스트만 보기"/"게스트만 보기"는 별도 화면이 아니라
        // 이 필터 하나로 처리한다(activityRoles array-contains).
        _LabeledDropdown<String?>(
          label: '활동 유형',
          value: _activityRoleFilter,
          options: [
            const (value: null, text: '전체'),
            for (final entry in _activityRoleLabels.entries)
              (value: entry.key, text: entry.value),
          ],
          onChanged: (v) {
            _activityRoleFilter = v;
            _applyFilters();
          },
        ),
        _LabeledDropdown<String?>(
          label: '계정 상태',
          value: _accountStatusFilter,
          options: [
            const (value: null, text: '전체'),
            for (final entry in _accountStatusLabels.entries)
              (value: entry.key, text: entry.value),
          ],
          onChanged: (v) {
            _accountStatusFilter = v;
            _applyFilters();
          },
        ),
        _LabeledDropdown<String?>(
          label: '가입 경로',
          value: _signupProviderFilter,
          options: [
            const (value: null, text: '전체'),
            for (final entry in _signupProviderLabels.entries)
              (value: entry.key, text: entry.value),
          ],
          onChanged: (v) {
            _signupProviderFilter = v;
            _applyFilters();
          },
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: _showTestAccounts,
              onChanged: (v) {
                _showTestAccounts = v ?? false;
                _applyFilters();
              },
            ),
            const Text('테스트 계정 보기', style: TextStyle(fontSize: 13)),
          ],
        ),
        // 가입기간/연령대/최근활동 — 한 번에 하나만(Firestore 제약, 상단 안내 참고).
        DropdownButton<_RangeFilterType>(
          value: _rangeFilterType,
          items: const [
            DropdownMenuItem(value: _RangeFilterType.none, child: Text('기간 필터 없음')),
            DropdownMenuItem(value: _RangeFilterType.joined, child: Text('가입 기간')),
            DropdownMenuItem(value: _RangeFilterType.age, child: Text('연령대')),
            DropdownMenuItem(value: _RangeFilterType.activeSince, child: Text('최근 활동')),
          ],
          onChanged: _onRangeFilterTypeChanged,
        ),
        if (_rangeFilterType == _RangeFilterType.joined)
          OutlinedButton.icon(
            onPressed: _pickJoinedRange,
            icon: const Icon(Icons.date_range, size: 16),
            label: Text(_joinedRange == null
                ? '기간 선택'
                : '${DateFormat('yy.MM.dd').format(_joinedRange!.start)} ~ ${DateFormat('yy.MM.dd').format(_joinedRange!.end)}'),
          ),
        if (_rangeFilterType == _RangeFilterType.age)
          DropdownButton<_AgeBucketOption>(
            value: _ageBucket,
            hint: const Text('연령대 선택'),
            items: [
              for (final b in _ageBuckets) DropdownMenuItem(value: b, child: Text(b.label)),
            ],
            onChanged: (v) {
              setState(() => _ageBucket = v);
              _applyFilters();
            },
          ),
        if (_rangeFilterType == _RangeFilterType.activeSince)
          DropdownButton<int>(
            value: _activeSinceDays,
            items: const [
              DropdownMenuItem(value: 7, child: Text('최근 7일')),
              DropdownMenuItem(value: 30, child: Text('최근 30일')),
            ],
            onChanged: (v) {
              _activeSinceDays = v ?? 7;
              _applyFilters();
            },
          ),
        DropdownButton<MemberSortField>(
          value: _sortField,
          items: const [
            DropdownMenuItem(value: MemberSortField.createdAt, child: Text('최근 가입순')),
            DropdownMenuItem(value: MemberSortField.lastActiveAt, child: Text('최근 활동순')),
            DropdownMenuItem(value: MemberSortField.lastLoginAt, child: Text('최근 로그인순')),
            DropdownMenuItem(value: MemberSortField.nameLower, child: Text('이름순')),
          ],
          onChanged: _hasRangeFilter
              ? null
              : (v) {
                  if (v == null) return;
                  _sortField = v;
                  _applyFilters();
                },
        ),
        DropdownButton<int>(
          value: _pageSize,
          items: [
            for (final size in AdminFirestoreService.pageSizeOptions)
              DropdownMenuItem(value: size, child: Text('페이지당 $size명')),
          ],
          onChanged: (v) {
            if (v == null) return;
            _pageSize = v;
            _applyFilters();
          },
        ),
        if (hasAnyFilter)
          TextButton(
            onPressed: () {
              _identityVerifiedFilter = null;
              _genderFilter = null;
              _activityRoleFilter = null;
              _accountStatusFilter = null;
              _signupProviderFilter = null;
              _showTestAccounts = false;
              _rangeFilterType = _RangeFilterType.none;
              _joinedRange = null;
              _ageBucket = null;
              _sortField = MemberSortField.createdAt;
              _identitySort = IdentitySortOrder.verifiedFirst;
              _searchCtrl.clear();
              _applyFilters();
            },
            child: const Text('필터 초기화'),
          ),
      ],
    );
  }

  /// 계정 상태 필터가 '탈퇴'면 **다른 표를 그린다.**
  ///
  /// 탈퇴 회원은 닉네임·이름·연락처·사업자 정보가 전부 지워져 있어서 평소 표를
  /// 그대로 쓰면 30여 개 열이 거의 '-'로 찬다. 운영이 실제로 봐야 하는 것은
  /// "언제 가입해 언제 나갔고, 왜 나갔고, 어떤 유형이었나"뿐이라 그 열만 남긴다.
  /// 쿼리·색인·필터는 그대로 재사용한다(accountStatus + createdAt 복합 색인).
  bool get _isWithdrawnView => _accountStatusFilter == 'withdrawn';

  /// '본인확인' 머리를 누를 때 — 완료 먼저 → 미완료 먼저 → 정렬 안 함.
  ///
  /// 서버 쿼리를 다시 던지지 않는다. 지금 화면에 있는 결과만 다시 세우므로
  /// 페이지 위치·필터·검색어가 그대로 남는다.
  void _cycleIdentitySort() {
    setState(() => _identitySort = _identitySort.next);
  }

  Widget _buildTable() {
    if (_isWithdrawnView) return _buildWithdrawnTable();
    final people = _personRows;
    final columns = _memberColumns();
    // 열 위치를 숫자로 박아 두면 열을 하나 끼울 때 화살표가 엉뚱한 머리에
    // 붙는다 — 머리글로 찾는다.
    final identityIndex = columns.indexWhere(
      (c) => c.label is Text && (c.label as Text).data == '본인확인',
    );
    // 이미 받아 온 이 페이지 안에서만 다시 줄 세운다 — 쿼리·페이지 나눔은 그대로.
    final rows = sortByIdentityVerified(
      people.rows,
      verified: (doc) => isIdentityVerifiedDoc(doc.data()),
      order: _identitySort,
    );
    return _ScrollableTable(
      child: DataTable(
        // 생년월일 칸이 두 줄(생년월일 + 나이)이라 기본 행 높이(48)로는 넘친다.
        dataRowMinHeight: 46,
        dataRowMaxHeight: 62,
        sortColumnIndex: _identitySort == IdentitySortOrder.none ? null : identityIndex,
        sortAscending: _identitySort.ascending,
        columns: columns,
        rows: [for (final doc in rows) _buildRow(doc, people.groups[doc])],
      ),
    );
  }

  List<DataColumn> _memberColumns() {
    return [
      // 맨 앞 체크박스 칸은 DataTable이 onSelectChanged가 있는 행에
      // 자동으로 붙인다 — 여기서 선언하지 않는다.
      const DataColumn(label: Text('이름')),
      const DataColumn(label: Text('생년월일 / 나이')),
      const DataColumn(label: Text('성별')),
      const DataColumn(label: Text('닉네임')),
      const DataColumn(label: Text('UID')),
      const DataColumn(label: Text('전화번호')),
      const DataColumn(label: Text('이메일')),
      // 머리를 누르면 이 페이지 안에서 완료/미완료 순서가 바뀐다. 화살표는
      // DataTable이 sortColumnIndex/sortAscending을 보고 직접 그린다.
      DataColumn(
        label: const Text('본인확인'),
        tooltip: '누르면 지금 보고 있는 결과 안에서 인증완료 → 미인증 → 정렬 안 함 순으로 바뀝니다.',
        onSort: (_, _) => _cycleIdentitySort(),
      ),
      // 사업자/일반회원 구분 — users.businessVerification 맵을 그대로
      // 읽는다(추가 조회 없음). 맵이 없으면 일반회원.
      const DataColumn(label: Text('회원 구분')),
      const DataColumn(label: Text('사업자번호')),
      const DataColumn(label: Text('상호명')),
      const DataColumn(label: Text('가입일')),
      const DataColumn(label: Text('가입경로')),
      // '테스트 계정 보기'를 켰을 때만 붙는다. 꺼져 있으면 모든 행이
      // 실사용자라 칸을 쓸 이유가 없고, 켜면 섞여 나오므로 반드시 필요하다
      // (본인확인 목록과 회원 관리가 달라 보였던 원인이 이 구분이다).
      if (_showTestColumn) const DataColumn(label: Text('테스트')),
    ];
  }

  // ── 탈퇴 회원 표 ──────────────────────────────────────────────────────────
  //
  // 여기 있는 값은 전부 users 비석에 남는 것들이다(accountWithdrawal.js가
  // 완전 탈퇴 때 일부러 지우지 않는 필드). 개인정보는 이미 지워져 있어서
  // 이 표에는 사람을 특정할 수 있는 값이 없다 — 식별은 UID로만 한다.

  static const _withdrawalReasonLabels = <String, String>{
    'no_longer_use': '미이용',
    'few_listings': '원하는 파티 없음',
    'privacy': '개인정보 우려',
    'bad_experience': '불쾌한 경험',
    'app_issue': '앱 불편·오류',
    'price': '비용 부담',
    'switch_account': '계정 이전',
    'other': '기타',
  };

  Widget _buildWithdrawnTable() {
    return _ScrollableTable(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('UID')),
          DataColumn(label: Text('가입일')),
          DataColumn(label: Text('탈퇴 신청일')),
          DataColumn(label: Text('최종 탈퇴일')),
          DataColumn(label: Text('탈퇴 당시 유형')),
          DataColumn(label: Text('탈퇴 사유')),
          DataColumn(label: Text('탈퇴 직전 상태')),
        ],
        rows: [for (final doc in _docs) _buildWithdrawnRow(doc)],
      ),
    );
  }

  DataRow _buildWithdrawnRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    String date(String key) {
      final t = (d[key] as Timestamp?)?.toDate();
      return t == null ? '-' : DateFormat('yyyy.MM.dd').format(t);
    }

    final memberType = d['withdrawnMemberType'] as String?;
    // 유형이 비어 있는 건 이 기능 이전에 탈퇴한 계정이다. '일반회원'으로 단정하면
    // 사업자였던 사람을 잘못 표시하게 되므로 '-'로 둔다.
    final memberTypeLabel = memberType == 'business'
        ? '사업자'
        : memberType == 'individual'
            ? '일반'
            : '-';

    final reasonCode = d['withdrawalReasonCode'] as String?;
    final reasonLabel = reasonCode == null
        ? ((d['withdrawalReasonProvided'] as bool? ?? false) ? '(서술만)' : '-')
        : (_withdrawalReasonLabels[reasonCode] ?? reasonCode);

    final fromStatus = d['withdrawnFromStatus'] as String?;

    return DataRow(
      onSelectChanged: (_) => widget.onOpenMember(doc.id),
      cells: [
        DataCell(SelectableText(
          doc.id,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        )),
        DataCell(Text(date('createdAt'))),
        DataCell(Text(date('withdrawalRequestedAt'))),
        DataCell(Text(date('withdrawnAt'))),
        DataCell(Text(memberTypeLabel)),
        DataCell(Text(reasonLabel)),
        // 제재 중이던 회원이 탈퇴했는지 — 재가입 심사에서 가장 먼저 볼 값이다.
        DataCell(fromStatus == null || fromStatus == 'active'
            ? const Text('-')
            : _AccountStatusBadge(status: fromStatus)),
      ],
    );
  }

  /// [person]은 이 계정의 주인이 가진 계정 전부 — 동일인 판별 근거(CI)가
  /// 없으면 null이다.
  DataRow _buildRow(QueryDocumentSnapshot<Map<String, dynamic>> doc, PersonGroup? person) {
    final d = doc.data();
    final nickname = d['nickname'] as String? ?? '-';
    final name = d['name'] as String? ?? '-';
    final gender = d['gender'] as String?;
    final genderLabel = gender == 'male' ? '남' : gender == 'female' ? '여' : '-';
    // 관리자 화면은 전체 번호 — 회원 확인·CS에 필요하다(phone_display.dart).
    final phone = adminPhoneNumber(d['phoneNumber'] as String?);
    final email = d['email'] as String? ?? '-';
    final verified = isIdentityVerifiedDoc(d);
    final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
    // "이메일 테스트 계정"(kDebugMode 전용 로그인) — signupProvider 없이
    // isTestAccount만 true인 경우를 이렇게 구분해 표시한다.
    final signupProvider = d['signupProvider'] as String?;
    final isTestAccount = d['isTestAccount'] as bool? ?? false;
    final multi = person != null && person.hasMultipleAccounts;
    // 여러 계정을 가진 회원은 그 사람의 로그인 수단을 모두 적는다.
    final signupProviderLabel = multi
        ? person.providersLabel
        : signupProvider != null
            ? (_signupProviderLabels[signupProvider] ?? signupProvider)
            : (isTestAccount ? '이메일(테스트)' : '-');
    // 사업자 정보는 이 회원 문서 안에 이미 들어 있다 — 추가 조회가 없다.
    final biz = BusinessInfo.fromUserDoc(d);

    return DataRow(
      onSelectChanged: (_) => widget.onOpenMember(doc.id),
      cells: [
        DataCell(multi ? _NameWithAccounts(name: name, count: person.accountCount) : Text(name)),
        // 생년월일·성별은 본인확인(NICE)이 저장한 값이 유일한 출처다 —
        // 인증 전 회원에게는 이 칸에 채울 근거가 없어 '-'로 둔다.
        DataCell(_BirthCell(
          year: (d['birthYear'] as num?)?.toInt(),
          month: (d['birthMonth'] as num?)?.toInt(),
          day: (d['birthDay'] as num?)?.toInt(),
        )),
        DataCell(Text(genderLabel)),
        DataCell(Text(nickname)),
        // 문의·장애 대응에서 그대로 복사해 쓰는 값이라 선택 가능해야 한다.
        DataCell(SelectableText(
          doc.id,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        )),
        DataCell(Text(phone)),
        DataCell(Text(email)),
        DataCell(_VerifiedBadge(verified: verified)),
        DataCell(_BusinessBadge(info: biz)),
        DataCell(Text(biz.isBusiness ? biz.formattedBusinessNumber : '-')),
        DataCell(Text(
          biz.businessName.isNotEmpty ? biz.businessName : '-',
          overflow: TextOverflow.ellipsis,
        )),
        DataCell(Text(createdAt == null ? '-' : DateFormat('yyyy.MM.dd').format(createdAt))),
        DataCell(Text(signupProviderLabel)),
        if (_showTestColumn) DataCell(Text(isTestAccount ? 'O' : '-')),
      ],
    );
  }

  Widget _buildPagination() {
    final start = _pageIndex * _pageSize + 1;
    final end = _pageIndex * _pageSize + _docs.length;
    // 위치(start–end)는 **받아온 페이지 기준** 그대로다 — 테스트 계정을
    // 화면에서만 빼기 때문에, 감춘 수를 따로 밝혀야 "50명씩인데 왜 47줄"이
    // 설명된다.
    final hidden = _hiddenTestCount;
    // 같은 사람의 다른 계정이라 한 줄로 합친 수 — "50명씩인데 왜 48줄"의 나머지 이유.
    final collapsed = _isWithdrawnView ? 0 : _personRows.collapsed;
    final rangeLabel = _docs.isEmpty
        ? '0건'
        : '$start–$end / 전체 ${_filteredTotal == null ? '-' : NumberFormat('#,###').format(_filteredTotal)}명'
            '${hidden == 0 ? '' : ' · 테스트 계정 $hidden명 숨김'}'
            '${collapsed == 0 ? '' : ' · 동일인 계정 $collapsed개 합침'}';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      // 숨김·합침 안내가 붙으면 폰 폭을 넘는다 — 넘치면 다음 줄로 내린다.
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            onPressed: _pageIndex == 0 ? null : _goFirst,
            icon: const Icon(Icons.first_page, size: 18),
            label: const Text('첫 페이지'),
          ),
          TextButton.icon(
            onPressed: _pageIndex == 0 ? null : _goPrev,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('이전'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(rangeLabel, style: const TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary)),
          ),
          TextButton.icon(
            onPressed: _hasNextPage ? _goNext : null,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('다음'),
          ),
        ],
      ),
    );
  }
}

/// 이름 아래 '계정 N개' — 한 사람이 여러 로그인 계정을 가졌다는 표시.
class _NameWithAccounts extends StatelessWidget {
  final String name;
  final int count;
  const _NameWithAccounts({required this.name, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: AdminTheme.accentLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '계정 $count개',
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AdminTheme.accent),
          ),
        ),
      ],
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  final bool verified;
  const _VerifiedBadge({required this.verified});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: verified ? const Color(0xFFE6F7ED) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (verified) ...[
            const Icon(Icons.check, size: 13, color: Color(0xFF17924E)),
            const SizedBox(width: 3),
          ],
          Text(
            verified ? '인증완료' : '미인증',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: verified ? const Color(0xFF17924E) : AdminTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 사업자/일반회원 구분 배지.
///
/// "사업자"의 근거는 users.businessVerification 맵이 있느냐 하나뿐이다 —
/// settlementInfo.hostType('개인'/'사업자')은 사용자가 정산 화면에서 직접
/// 고르는 자기신고 값이라 여기 쓰지 않는다(business_info.dart 주석 참고).
///
/// 인증 통과(verified)와 그 외(심사 필요·실패·휴폐업)를 색으로 갈라서, 목록만
/// 훑어도 "사업자라고 넣었는데 아직 통과 못 한 사람"이 눈에 띄게 한다.
class _BusinessBadge extends StatelessWidget {
  final BusinessInfo info;
  const _BusinessBadge({required this.info});

  @override
  Widget build(BuildContext context) {
    if (!info.isBusiness) {
      return const Text('일반회원',
          style: TextStyle(fontSize: 11.5, color: AdminTheme.textSecondary));
    }
    // ok는 **권한까지 열린 경우만**이다 — 대표자 확인이 필요한 계정을
    // 파란 '인증 완료'로 그리면 목록만 보고 권한이 있다고 오해한다.
    final ok = info.isVerified;
    final warn = info.status == BizStatus.suspended || info.status == BizStatus.failed;
    final (bg, fg) = ok
        ? (const Color(0xFFE6F0FF), const Color(0xFF2D5BD1))
        : warn
            ? (const Color(0xFFFDECEC), const Color(0xFFC03A3A))
            : (const Color(0xFFFFF4E2), const Color(0xFFB2701A));
    return Tooltip(
      message: '사업자 · ${info.statusLabel}'
          '${info.ntsStatusLabel.isNotEmpty ? ' (${info.ntsStatusLabel})' : ''}'
          '${info.needsOwnerApproval ? ' — 국세청 확인은 끝났으나 본인 명의가 아니라 권한이 열리지 않았습니다.' : ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(
          '사업자 · ${info.statusLabel}',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: fg),
        ),
      ),
    );
  }
}

/// 회원이 실제로 수행한 활동에 따라 자동으로 붙는 배지 — 고정 역할이 아니라
/// users.activityRoles 배열을 그대로 나열한다. 여러 활동을 했으면 여러 개.

class _AccountStatusBadge extends StatelessWidget {
  final String status;
  const _AccountStatusBadge({required this.status});

  static const _colors = {
    'active': Color(0xFFE6F7ED),
    'dormant': Color(0xFFF3F4F6),
    'restricted': Color(0xFFFFF3E0),
    'withdrawn': Color(0xFFFDECEC),
  };
  static const _textColors = {
    'active': Color(0xFF17924E),
    'dormant': AdminTheme.textSecondary,
    'restricted': Color(0xFFB56A00),
    'withdrawn': Color(0xFFC62828),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _colors[status] ?? _colors['active'],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _accountStatusLabels[status] ?? status,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: _textColors[status] ?? _textColors['active'],
        ),
      ),
    );
  }
}

/// 표를 카드 안에서 **가로·세로 모두** 스크롤할 수 있게 감싼다.
///
/// 열이 화면보다 넓을 때 오른쪽 끝(가입경로)까지 볼 수 없던 이유가 세 가지였다.
///
///   1. 데스크톱 웹의 기본 `ScrollBehavior`는 **마우스 드래그로 스크롤하지
///      않는다**(dragDevices에 mouse가 없다) — 표를 잡아끌어도 움직이지 않는다.
///   2. 휠은 세로 축에만 걸린다. 가로로 밀려면 Shift+휠을 알고 있어야 한다.
///   3. `SingleChildScrollView`는 스크롤바를 스스로 그리지 않아서, **오른쪽에
///      더 있다는 사실 자체가 화면에 나타나지 않는다.**
///
/// 그래서 축마다 스크롤바를 하나씩 항상 띄우고(thumbVisibility), 마우스 드래그도
/// 허용한다. 가로 스크롤바는 세로 스크롤 뷰 **바깥**에 있어 카드 아래쪽에 붙어
/// 있고, 세로로 내려도 함께 사라지지 않는다.
///
/// 표 자체는 예전처럼 자기 자연 너비를 그대로 쓴다 — 페이지를 늘리거나 열을
/// 찌그러뜨리지 않고, 넘치는 만큼만 카드 안에서 밀린다.
class _ScrollableTable extends StatefulWidget {
  final Widget child;

  const _ScrollableTable({required this.child});

  @override
  State<_ScrollableTable> createState() => _ScrollableTableState();
}

class _ScrollableTableState extends State<_ScrollableTable> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
        // 스크롤바는 아래에서 축마다 직접 붙인다 — 기본 동작에 맡기면 세로만
        // 붙고, 여기에 또 겹치면 같은 자리에 두 개가 그려진다.
        scrollbars: false,
      ),
      child: Scrollbar(
        controller: _vertical,
        thumbVisibility: true,
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          // 가로 스크롤 알림은 세로 스크롤 뷰를 한 번 지나 올라온다(depth 1).
          // 이 조건이 없으면 세로 스크롤에 가로 스크롤바가 반응한다.
          notificationPredicate: (n) => n.depth == 1,
          child: SingleChildScrollView(
            controller: _vertical,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 생년월일 + 한국 나이 두 줄 — `1991.03.15` / `91년생 · 36세`.
///
/// 값의 출처는 본인확인(NICE)이 저장한 birthYear/Month/Day 하나뿐이다
/// (`functions/niceAuth.js`). 인증 전 회원은 이 값이 아예 없으므로 `-`로 두고,
/// 가입일이나 다른 필드로 **추측하지 않는다.**
///
/// 나이는 저장하지 않고 [memberAgeLabel]이 매번 계산한다 — 해가 바뀌면 저절로
/// 한 살이 오른다.
class _BirthCell extends StatelessWidget {
  final int? year;
  final int? month;
  final int? day;

  const _BirthCell({this.year, this.month, this.day});

  @override
  Widget build(BuildContext context) {
    final y = year;
    if (y == null) return const Text('-');
    final date = memberBirthDateLabel(y, month, day);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(date),
        Text(
          memberAgeLabel(y),
          style: const TextStyle(fontSize: 11.5, color: AdminTheme.textSecondary),
        ),
      ],
    );
  }
}
/// 필터 이름이 **항상 보이는** 드롭다운.
///
/// 예전에는 필터 이름을 [DropdownButton.hint]에만 넣었는데, 선택지에
/// `value: null`인 '전체' 항목이 함께 있으면 hint는 그려지지 않는다(값이 null
/// 이어도 그 항목에 매칭되기 때문이다). 그래서 툴바에 '전체'만 다섯 개
/// 늘어서서 각각이 무슨 필터인지 알 수 없었다.
///
/// 그래서 버튼 표면에는 '성별 전체'처럼 **이름과 현재 값을 함께** 그리고
/// ([DropdownButton.selectedItemBuilder]), 펼친 메뉴에는 값만 보여준다
/// ('전체 / 남성 / 여성').
///
/// 라벨을 별도 위젯으로 떼어내지 않은 것이 핵심이다 — 이름과 값이 같은
/// DropdownButton 안에 있으므로 **어디를 눌러도 그대로 메뉴가 열린다.**
/// 폭도 selectedItemBuilder가 만드는 '이름 + 값' 기준으로 잡혀서
/// '본인확인 미완료' 같은 긴 조합도 잘리지 않는다.
///
/// ⚠️ 표시 전용이다. 필터 판정·검색·정렬·페이지네이션은 이 위젯을 거치지
/// 않는다 — [onChanged]가 예전과 똑같은 값을 그대로 돌려준다.
class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  /// 필터 이름 — 버튼에 항상 붙는다.
  final String label;

  final T value;

  /// 값과 표기. 나열 순서가 곧 메뉴 순서다.
  final List<({T value, String text})> options;

  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      onChanged: onChanged,
      // 펼친 메뉴 — 값만 보여준다. 이름은 버튼에 이미 붙어 있어서 항목마다
      // 반복하면 '성별 전체 / 성별 남성 / 성별 여성'처럼 읽힌다.
      items: [
        for (final o in options)
          DropdownMenuItem<T>(value: o.value, child: Text(o.text)),
      ],
      // 버튼 표면 — '이름 값'. items와 **순서가 같아야** 선택값과 짝이 맞는다.
      selectedItemBuilder: (context) => [
        for (final o in options)
          Align(
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label ',
                    style: const TextStyle(
                      color: AdminTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextSpan(
                    text: o.text,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              maxLines: 1,
            ),
          ),
      ],
    );
  }
}
