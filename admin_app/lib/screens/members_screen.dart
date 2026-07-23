import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';
import '../utils/masking.dart';

typedef OpenMember = void Function(String uid);

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
  int _pageSize = AdminFirestoreService.pageSizeOptions.first;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  Map<String, Map<String, dynamic>> _statsById = {};
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _pageStartStack = [null];
  int _pageIndex = 0;
  bool _hasNextPage = false;
  bool _loading = true;
  bool _searchMode = false;
  String? _searchNotice;

  int? _filteredTotal;

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
        showTestAccounts: _showTestAccounts,
        joinedFrom: _rangeFilterType == _RangeFilterType.joined ? _joinedRange?.start : null,
        joinedTo: _rangeFilterType == _RangeFilterType.joined ? _joinedRange?.end : null,
        ageMin: _rangeFilterType == _RangeFilterType.age ? _ageBucket?.minAge : null,
        ageMax: _rangeFilterType == _RangeFilterType.age ? _ageBucket?.maxAge : null,
        lastLoginSince: _activeSinceThreshold,
        sortField: _sortField,
      );

  Future<void> _loadFilteredTotal() async {
    final total = await AdminFirestoreService.usersCountForFilter(
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
    );
    if (!mounted) return;
    setState(() => _filteredTotal = total);
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
    final stats = await AdminFirestoreService.fetchUserStatsForUids(pageDocs.map((d) => d.id).toList());

    if (!mounted) return;
    setState(() {
      _docs = pageDocs;
      _statsById = stats;
      _hasNextPage = hasNext;
      _loading = false;
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

    final stats = await AdminFirestoreService.fetchUserStatsForUids(results.map((d) => d.id).toList());

    if (!mounted) return;
    setState(() {
      _docs = results;
      _statsById = stats;
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
        Row(
          children: [
            const Text('회원 관리', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            if (_filteredTotal != null)
              Text('전체 ${NumberFormat('#,###').format(_filteredTotal)}명',
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
                : _docs.isEmpty
                    ? const Center(child: Text('회원이 없습니다.', style: TextStyle(color: AdminTheme.textSecondary)))
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
        _searchMode;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
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
        DropdownButton<bool?>(
          value: _identityVerifiedFilter,
          hint: const Text('본인확인'),
          items: const [
            DropdownMenuItem(value: null, child: Text('전체')),
            DropdownMenuItem(value: true, child: Text('완료')),
            DropdownMenuItem(value: false, child: Text('미완료')),
          ],
          onChanged: (v) {
            _identityVerifiedFilter = v;
            _applyFilters();
          },
        ),
        DropdownButton<String?>(
          value: _genderFilter,
          hint: const Text('성별'),
          items: const [
            DropdownMenuItem(value: null, child: Text('전체')),
            DropdownMenuItem(value: 'male', child: Text('남성')),
            DropdownMenuItem(value: 'female', child: Text('여성')),
          ],
          onChanged: (v) {
            _genderFilter = v;
            _applyFilters();
          },
        ),
        // 활동 유형 — "호스트만 보기"/"게스트만 보기"는 별도 화면이 아니라
        // 이 필터 하나로 처리한다(activityRoles array-contains).
        DropdownButton<String?>(
          value: _activityRoleFilter,
          hint: const Text('활동 유형'),
          items: [
            const DropdownMenuItem(value: null, child: Text('전체')),
            for (final entry in _activityRoleLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) {
            _activityRoleFilter = v;
            _applyFilters();
          },
        ),
        DropdownButton<String?>(
          value: _accountStatusFilter,
          hint: const Text('계정 상태'),
          items: [
            const DropdownMenuItem(value: null, child: Text('전체')),
            for (final entry in _accountStatusLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) {
            _accountStatusFilter = v;
            _applyFilters();
          },
        ),
        DropdownButton<String?>(
          value: _signupProviderFilter,
          hint: const Text('가입 경로'),
          items: [
            const DropdownMenuItem(value: null, child: Text('전체')),
            for (final entry in _signupProviderLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
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
              _searchCtrl.clear();
              _applyFilters();
            },
            child: const Text('필터 초기화'),
          ),
      ],
    );
  }

  Widget _buildTable() {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('')),
            DataColumn(label: Text('닉네임')),
            DataColumn(label: Text('이름')),
            DataColumn(label: Text('나이')),
            DataColumn(label: Text('성별')),
            DataColumn(label: Text('전화번호')),
            DataColumn(label: Text('이메일')),
            DataColumn(label: Text('본인확인')),
            DataColumn(label: Text('가입일')),
            DataColumn(label: Text('가입경로')),
            DataColumn(label: Text('활동 배지')),
            DataColumn(label: Text('활동 지역')),
            DataColumn(label: Text('최근 로그인일')),
            DataColumn(label: Text('최근 활동일')),
            DataColumn(label: Text('계정 상태')),
            DataColumn(label: Text('테스트')),
            DataColumn(label: Text('등록 파티')),
            DataColumn(label: Text('신청 수')),
            DataColumn(label: Text('실제 참여')),
            DataColumn(label: Text('등록 플레이스')),
            DataColumn(label: Text('예약 수')),
            DataColumn(label: Text('등록 상품')),
            DataColumn(label: Text('구매 수')),
            DataColumn(label: Text('등록 크루')),
            DataColumn(label: Text('크루 지원')),
            DataColumn(label: Text('받은 찜')),
            DataColumn(label: Text('신고')),
            DataColumn(label: Text('누적 결제')),
            DataColumn(label: Text('누적 환불')),
          ],
          rows: [for (final doc in _docs) _buildRow(doc)],
        ),
      ),
    );
  }

  DataRow _buildRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final photoUrl = d['profileImageUrl'] as String? ?? '';
    final nickname = d['nickname'] as String? ?? '-';
    final name = d['name'] as String? ?? '-';
    final gender = d['gender'] as String?;
    final genderLabel = gender == 'male' ? '남' : gender == 'female' ? '여' : '-';
    final birthYear = (d['birthYear'] as num?)?.toInt();
    // 주민등록번호 뒷자리 첫 숫자: 2000년 이전 출생 남1/여2, 2000년 이후 출생 남3/여4.
    final rrnGenderDigit = birthYear == null
        ? null
        : (birthYear < 2000
            ? (gender == 'male' ? 1 : gender == 'female' ? 2 : null)
            : (gender == 'male' ? 3 : gender == 'female' ? 4 : null));
    final age = birthYear == null
        ? '-'
        : '${DateTime.now().year - birthYear + 1}세${rrnGenderDigit != null ? ' ($rrnGenderDigit)' : ''}';
    final phone = Masking.phone(d['phoneNumber'] as String?);
    final email = d['email'] as String? ?? '-';
    final verified = (d['identityVerified'] as bool?) ?? (d['isVerified'] as bool?) ?? false;
    final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
    final lastLoginAt = (d['lastLoginAt'] as Timestamp?)?.toDate();
    final lastActiveAt = (d['lastActiveAt'] as Timestamp?)?.toDate();
    // "이메일 테스트 계정"(kDebugMode 전용 로그인) — signupProvider 없이
    // isTestAccount만 true인 경우를 이렇게 구분해 표시한다.
    final signupProvider = d['signupProvider'] as String?;
    final isTestAccount = d['isTestAccount'] as bool? ?? false;
    final signupProviderLabel = signupProvider != null
        ? (_signupProviderLabels[signupProvider] ?? signupProvider)
        : (isTestAccount ? '이메일(테스트)' : '-');
    final accountStatus = d['accountStatus'] as String? ?? 'active';
    final activityRoles = (d['activityRoles'] as List?)?.cast<String>() ?? const [];

    // 신청/실제이용 등 상세 수치는 users가 아니라 별도 userStats 컬렉션에서
    // 온다(원본 신청 기록과 요약 통계 분리) — 활동이 전혀 없는 회원은 문서가
    // 아직 없어 0으로 표시한다. 크루 지원/신고는 앱에 기능 자체가 없어
    // 항상 0/"-"로 고정된다(userStats 필드도 예약만 돼 있고 절대 채워지지
    // 않음 — memberManagement.js 상단 주석 참고).
    final stats = _statsById[doc.id];
    int n(String key) => (stats?[key] as num?)?.toInt() ?? 0;
    num money(String key) => (stats?[key] as num?) ?? 0;
    final placeReservations = n('totalPlaceReservationsAsGuest') + n('totalPlaceReservationsAsHost');

    return DataRow(
      onSelectChanged: (_) => widget.onOpenMember(doc.id),
      cells: [
        DataCell(CircleAvatar(
          radius: 14,
          backgroundColor: AdminTheme.accentLight,
          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: photoUrl.isEmpty ? const Icon(Icons.person, size: 14, color: AdminTheme.accent) : null,
        )),
        DataCell(Text(nickname)),
        DataCell(Text(name)),
        DataCell(Text(age)),
        DataCell(Text(genderLabel)),
        DataCell(Text(phone)),
        DataCell(Text(email)),
        DataCell(_VerifiedBadge(verified: verified)),
        DataCell(Text(createdAt == null ? '-' : DateFormat('yyyy.MM.dd').format(createdAt))),
        DataCell(Text(signupProviderLabel)),
        DataCell(_ActivityBadges(roles: activityRoles)),
        DataCell(Text((stats?['favoriteRegion'] as String? ?? '-').replaceAll('_', ' '))),
        DataCell(Text(lastLoginAt == null ? '-' : DateFormat('yyyy.MM.dd').format(lastLoginAt))),
        DataCell(Text(lastActiveAt == null ? '-' : DateFormat('yyyy.MM.dd').format(lastActiveAt))),
        DataCell(_AccountStatusBadge(status: accountStatus)),
        DataCell(Text(isTestAccount ? 'O' : '-')),
        DataCell(Text('${n('totalPartiesCreated')}')),
        DataCell(Text('${n('totalApplications')}')),
        DataCell(Text('${n('totalAttended')}')),
        DataCell(Text('${n('totalPlacesCreated')}')),
        DataCell(Text('$placeReservations')),
        DataCell(Text('${n('totalProductsRegistered')}')),
        DataCell(Text('${n('totalProductPurchases')}')),
        DataCell(Text('${n('totalCrewPostings')}')),
        const DataCell(Text('0')), // 크루 지원 — 기능 미구현, 항상 0
        DataCell(Text('${n('totalFavoritesReceived')}')),
        const DataCell(Text('-')), // 신고 — 기능 미구현, 항상 "-"
        DataCell(Text(NumberFormat('#,###').format(money('cumulativePaymentAmount')))),
        DataCell(Text(NumberFormat('#,###').format(money('cumulativeRefundAmount')))),
      ],
    );
  }

  Widget _buildPagination() {
    final start = _pageIndex * _pageSize + 1;
    final end = _pageIndex * _pageSize + _docs.length;
    final rangeLabel = _docs.isEmpty
        ? '0건'
        : '$start–$end / 전체 ${_filteredTotal == null ? '-' : NumberFormat('#,###').format(_filteredTotal)}명';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
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
      child: Text(
        verified ? '완료' : '미완료',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: verified ? const Color(0xFF17924E) : AdminTheme.textSecondary,
        ),
      ),
    );
  }
}

/// 회원이 실제로 수행한 활동에 따라 자동으로 붙는 배지 — 고정 역할이 아니라
/// users.activityRoles 배열을 그대로 나열한다. 여러 활동을 했으면 여러 개.
class _ActivityBadges extends StatelessWidget {
  final List<String> roles;
  const _ActivityBadges({required this.roles});

  @override
  Widget build(BuildContext context) {
    if (roles.isEmpty) {
      return const Text('-', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 12));
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final role in roles)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AdminTheme.accentLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _activityRoleLabels[role] ?? role,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AdminTheme.accent),
            ),
          ),
      ],
    );
  }
}

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
