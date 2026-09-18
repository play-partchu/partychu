import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';
import '../utils/responsive.dart';
import '../widgets/stat_card.dart';
import 'members_screen.dart' show OpenMember;

/// "이용 통계" 화면 — 전체 통계 카드 + 인기 지역/시간대 + 사용자별 이용 목록.
/// 가입자/본인확인/활성사용자/신청·승인·참여·취소·노쇼 카운트는 대시보드와
/// 같은 AdminFirestoreService 메서드를 그대로 재사용한다(새로 안 만듦).
class UsageStatsScreen extends StatefulWidget {
  final OpenMember onOpenMember;
  const UsageStatsScreen({super.key, required this.onOpenMember});

  @override
  State<UsageStatsScreen> createState() => _UsageStatsScreenState();
}

enum _TrendGranularity { day, week, month }

class _UsageStatsScreenState extends State<UsageStatsScreen> {
  UsageSortField _sortField = UsageSortField.totalApplications;
  int _pageSize = AdminFirestoreService.pageSizeOptions.first;

  // 가입 추이 카드 — 90일치를 한 번만 받아두고 일/주/월 버튼은 이미 받은
  // 데이터를 클라이언트에서 다시 묶기만 한다(추가 Firestore 읽기 없음).
  _TrendGranularity _trendGranularity = _TrendGranularity.day;
  late final Future<List<MapEntry<String, int>>> _signupTrendFuture =
      AdminFirestoreService.dailySignupTrend(days: 90);

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _pageStartStack = [null];
  int _pageIndex = 0;
  bool _hasNextPage = false;
  bool _loading = true;
  int? _totalCount;

  @override
  void initState() {
    super.initState();
    _loadPage();
    AdminFirestoreService.usageStatsCount().then((v) {
      if (mounted) setState(() => _totalCount = v);
    });
  }

  Future<void> _loadPage() async {
    setState(() => _loading = true);
    final cursor = _pageStartStack[_pageIndex];
    var query = AdminFirestoreService.usageStatsBaseQuery(sortField: _sortField).limit(_pageSize + 1);
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
    });
  }

  void _resetPaging() {
    _pageStartStack
      ..clear()
      ..add(null);
    _pageIndex = 0;
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfToday.subtract(Duration(days: startOfToday.weekday - 1));
    final startOfMonth = DateTime(now.year, now.month, 1);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('이용 통계', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          const Text('전체 통계', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.textSecondary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(width: 220, child: StatCard(label: '전체 가입자', future: AdminFirestoreService.totalUsers())),
              SizedBox(width: 220, child: StatCard(label: '본인확인 사용자', future: AdminFirestoreService.verifiedUsers())),
              SizedBox(width: 220, child: StatCard(label: '오늘 활성 사용자', future: AdminFirestoreService.activeUsersSince(startOfToday))),
              SizedBox(width: 220, child: StatCard(label: '이번 주 활성 사용자', future: AdminFirestoreService.activeUsersSince(startOfWeek))),
              SizedBox(width: 220, child: StatCard(label: '이번 달 활성 사용자', future: AdminFirestoreService.activeUsersSince(startOfMonth))),
              SizedBox(width: 220, child: StatCard(label: '조회 수', future: AdminFirestoreService.totalPartyViewsAllTime())),
              SizedBox(width: 220, child: StatCard(label: '신청 수', future: AdminFirestoreService.totalApplications())),
              SizedBox(width: 220, child: StatCard(label: '승인 수', future: AdminFirestoreService.applicationsByStatus('approved'))),
              SizedBox(width: 220, child: StatCard(label: '실제 참여 수', future: AdminFirestoreService.applicationsByStatus(AdminFirestoreService.checkedInStatus))),
              SizedBox(width: 220, child: StatCard(label: '취소 수', future: AdminFirestoreService.applicationsByStatus('cancelled'))),
              SizedBox(width: 220, child: StatCard(label: '노쇼 수', future: AdminFirestoreService.applicationsByStatus('no_show'))),
            ],
          ),
          const SizedBox(height: 28),
          ResponsiveRow(children: [_topRegionsCard(), _hourlyStatsCard()]),
          const SizedBox(height: 28),
          const Text('회원 통계 보강',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.textSecondary)),
          const SizedBox(height: 10),
          ResponsiveRow(children: [
            _countBreakdownCard('성별 비율', AdminFirestoreService.genderCounts()),
            _countBreakdownCard('연령대 분포', AdminFirestoreService.ageBucketCounts()),
            _countBreakdownCard('가입 경로', AdminFirestoreService.signupProviderCounts()),
          ]),
          const SizedBox(height: 16),
          ResponsiveRow(children: [_signupTrendCard(), _regionMemberCountCard()]),
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('사용자별 이용 현황',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.textSecondary)),
              if (_totalCount != null)
                Text('전체 ${NumberFormat('#,###').format(_totalCount)}명(활동 기록 있는 회원만)',
                    style: const TextStyle(fontSize: 12, color: AdminTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          _buildToolbar(),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminTheme.cardBorder),
            ),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator(color: AdminTheme.accent)),
                  )
                : _docs.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('아직 이용 기록이 없습니다.', style: TextStyle(color: AdminTheme.textSecondary))),
                      )
                    : _buildTable(),
          ),
          _buildPagination(),
        ],
      ),
    );
  }

  Widget _topRegionsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('인기 지역 Top 5', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            future: AdminFirestoreService.topRegions(limit: 5),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AdminTheme.accent));
              final docs = snap.data!;
              if (docs.isEmpty) {
                return const Text('아직 데이터가 없습니다.', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 13));
              }
              return Column(
                children: [
                  for (final doc in docs)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${doc.data()['region1'] ?? '-'} ${doc.data()['region2'] ?? ''}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text('신청 ${doc.data()['totalApplications'] ?? 0} · 참여 ${doc.data()['totalAttended'] ?? 0}',
                              style: const TextStyle(fontSize: 12, color: AdminTheme.textSecondary)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _hourlyStatsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('인기 이용 시간대', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: AdminFirestoreService.hourlyStatsAll(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AdminTheme.accent));
              final hours = List<Map<String, dynamic>>.from(snap.data!)
                ..sort((a, b) => ((b['applications'] as num?) ?? 0).compareTo((a['applications'] as num?) ?? 0));
              final top = hours.take(5).toList();
              if (top.isEmpty || top.every((h) => ((h['applications'] as num?) ?? 0) == 0)) {
                return const Text('아직 데이터가 없습니다.', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 13));
              }
              return Column(
                children: [
                  for (final h in top)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text('${h['hour']}시대', style: const TextStyle(fontSize: 13))),
                          Text(
                              '신청 ${h['applications'] ?? 0} · 참여 ${h['attended'] ?? 0} · 조회 ${h['partyViews'] ?? 0}',
                              style: const TextStyle(fontSize: 12, color: AdminTheme.textSecondary)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── 회원 통계 보강 카드 4종 ────────────────────────────────────────

  static String _breakdownLabel(String key) => switch (key) {
        'male' => '남성',
        'female' => '여성',
        'google' => '구글',
        'kakao' => '카카오',
        'naver' => '네이버',
        _ => key, // 연령대 버킷("20대" 등)은 이미 화면에 보여줄 한글 라벨 그대로.
      };

  /// 성별/연령대/가입경로처럼 "라벨 → 인원수" 맵 하나를 비율과 함께 순위로
  /// 보여주는 공용 카드 — 기존 인기 지역/시간대 카드와 같은 시각 스타일.
  Widget _countBreakdownCard(String title, Future<Map<String, int>> future) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, int>>(
            future: future,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AdminTheme.accent));
              final data = snap.data!;
              final total = data.values.fold<int>(0, (a, b) => a + b);
              if (total == 0) {
                return const Text('아직 데이터가 없습니다.', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 13));
              }
              final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
              return Column(
                children: [
                  for (final e in entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(_breakdownLabel(e.key), style: const TextStyle(fontSize: 13))),
                          Text(
                            '${e.value}명 (${(e.value / total * 100).toStringAsFixed(1)}%)',
                            style: const TextStyle(fontSize: 12, color: AdminTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 일별 90일치를 미리 받아두고, 버튼으로 일/주/월 단위로 다시 묶어 보여준다.
  List<MapEntry<String, int>> _bucketTrend(List<MapEntry<String, int>> daily, _TrendGranularity g) {
    if (g == _TrendGranularity.day) {
      final recent = daily.length > 14 ? daily.sublist(daily.length - 14) : daily;
      return recent.reversed.toList();
    }
    if (g == _TrendGranularity.month) {
      final byMonth = <String, int>{};
      for (final e in daily) {
        final month = e.key.substring(0, 7); // 'yyyy-MM'
        byMonth[month] = (byMonth[month] ?? 0) + e.value;
      }
      return (byMonth.entries.toList()..sort((a, b) => b.key.compareTo(a.key)));
    }
    // 주별 — 오늘을 기준으로 최근 7일씩 묶는다(달력 주가 아니라 최근 N일 단위).
    final weekCount = ((daily.length - 1) ~/ 7) + 1;
    final sums = List<int>.filled(weekCount, 0);
    for (var i = 0; i < daily.length; i++) {
      final weekIndex = (daily.length - 1 - i) ~/ 7;
      sums[weekIndex] += daily[i].value;
    }
    return [
      for (var w = 0; w < weekCount; w++) MapEntry(w == 0 ? '이번 주' : '$w주 전', sums[w]),
    ];
  }

  Widget _trendToggleButton(_TrendGranularity g, String label) {
    final selected = _trendGranularity == g;
    return GestureDetector(
      onTap: () => setState(() => _trendGranularity = g),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AdminTheme.accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AdminTheme.accent : AdminTheme.cardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AdminTheme.accent : AdminTheme.textSecondary,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _signupTrendCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('가입 추이', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
              _trendToggleButton(_TrendGranularity.day, '일별'),
              const SizedBox(width: 6),
              _trendToggleButton(_TrendGranularity.week, '주별'),
              const SizedBox(width: 6),
              _trendToggleButton(_TrendGranularity.month, '월별'),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<MapEntry<String, int>>>(
            future: _signupTrendFuture,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AdminTheme.accent));
              final bucketed = _bucketTrend(snap.data!, _trendGranularity);
              if (bucketed.isEmpty || bucketed.every((e) => e.value == 0)) {
                return const Text('아직 데이터가 없습니다.', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 13));
              }
              return Column(
                children: [
                  for (final e in bucketed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(e.key, style: const TextStyle(fontSize: 13))),
                          Text('신규 가입 ${e.value}명',
                              style: const TextStyle(fontSize: 12, color: AdminTheme.textSecondary)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _regionMemberCountCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('지역별 회원 수', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          const Text(
            '신청 활동 기준 최다 지역 근사치입니다 — 활동 이력이 없는 회원은 제외됩니다.',
            style: TextStyle(fontSize: 11, color: AdminTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, int>>(
            future: AdminFirestoreService.signupRegionCounts(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AdminTheme.accent));
              final entries = snap.data!.entries.where((e) => e.value > 0).toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              if (entries.isEmpty) {
                return const Text('아직 데이터가 없습니다.', style: TextStyle(color: AdminTheme.textSecondary, fontSize: 13));
              }
              return Column(
                children: [
                  for (final e in entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(e.key, style: const TextStyle(fontSize: 13))),
                          Text('${e.value}명', style: const TextStyle(fontSize: 12, color: AdminTheme.textSecondary)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<UsageSortField>(
          value: _sortField,
          items: const [
            DropdownMenuItem(value: UsageSortField.totalApplications, child: Text('신청 횟수순')),
            DropdownMenuItem(value: UsageSortField.totalAttended, child: Text('실제 이용 횟수순')),
            DropdownMenuItem(value: UsageSortField.lastParticipationAt, child: Text('최근 참여순')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _sortField = v);
            _resetPaging();
            _loadPage();
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
            setState(() => _pageSize = v);
            _resetPaging();
            _loadPage();
          },
        ),
      ],
    );
  }

  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('닉네임')),
          DataColumn(label: Text('이름')),
          DataColumn(label: Text('총 신청')),
          DataColumn(label: Text('승인')),
          DataColumn(label: Text('실제 이용')),
          DataColumn(label: Text('취소')),
          DataColumn(label: Text('찜')),
          DataColumn(label: Text('주 이용 지역')),
          DataColumn(label: Text('주 이용 시간')),
          DataColumn(label: Text('최근 활동일')),
        ],
        rows: [for (final doc in _docs) _buildRow(doc)],
      ),
    );
  }

  DataRow _buildRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    int n(String key) => (d[key] as num?)?.toInt() ?? 0;
    final favoriteRegion = (d['favoriteRegion'] as String? ?? '-').replaceAll('_', ' ');
    final mostUsedHour = d['mostUsedHour'] != null ? '${d['mostUsedHour']}시대' : '-';
    final lastActiveAt = (d['lastActiveAt'] as Timestamp?)?.toDate();

    return DataRow(
      onSelectChanged: (_) => widget.onOpenMember(doc.id),
      cells: [
        DataCell(Text(d['nickname'] as String? ?? '-')),
        DataCell(Text(d['name'] as String? ?? '-')),
        DataCell(Text('${n('totalApplications')}')),
        DataCell(Text('${n('totalConfirmed')}')),
        DataCell(Text('${n('totalAttended')}')),
        DataCell(Text('${n('totalCancelled')}')),
        DataCell(Text('${n('totalFavorites')}')),
        DataCell(Text(favoriteRegion)),
        DataCell(Text(mostUsedHour)),
        DataCell(Text(lastActiveAt == null ? '-' : DateFormat('yyyy.MM.dd').format(lastActiveAt))),
      ],
    );
  }

  Widget _buildPagination() {
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
            child: Text('${_pageIndex + 1} 페이지', style: const TextStyle(fontSize: 12.5, color: AdminTheme.textSecondary)),
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
