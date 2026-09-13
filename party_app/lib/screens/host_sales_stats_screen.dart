// ─────────────────────────────────────────────────────────────────────────────
// 📊 판매 통계 — 호스트가 자기 콘텐츠의 신청/예약과 수익을 날짜별로 보는 화면.
//
// 상단 탭 다섯(통합·파티·플레이스·장소대여·파티샵) × 기간 프리셋 다섯을 곱한 모든 조합이
// **한 번 읽어 온 데이터**에서 나온다. 탭이나 기간을 바꿔도 Firestore를 다시
// 읽지 않는다 — 고른 기간이 이미 읽어 온 구간보다 이전으로 내려갈 때만 다시
// 읽는다([_ensureLoaded]).
//
// 숫자를 세는 규칙은 여기 없다. 전부 [HostSalesStats]와 [HostSalesService]에
// 있고, 이 파일은 그 결과를 그리기만 한다.
//
// 플레이스 한 곳의 상품 판매만 보는 [PlaceSalesDashboardScreen]과는 범위가
// 다르다 — 그쪽은 그대로 두고, 이 화면이 호스트 전체를 가로로 본다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:partychu_sales/partychu_sales.dart';
import 'package:party_app/services/host_sales_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/place_product/place_product_card.dart'
    show comma;

const Color _kBg = Color(0xFFF7F7FA);
const Color _kAccent = Color(0xFF7C5CBF);

/// 탭 하나 = 유형 하나. null은 '통합'(네 유형 합산)이다.
const List<({String label, SalesKind? kind})> _tabs = [
  (label: '통합', kind: null),
  (label: '파티', kind: SalesKind.party),
  (label: '플레이스', kind: SalesKind.place),
  (label: '장소대여', kind: SalesKind.rental),
  (label: '파티샵', kind: SalesKind.shop),
];

class HostSalesStatsScreen extends StatefulWidget {
  const HostSalesStatsScreen({super.key});

  @override
  State<HostSalesStatsScreen> createState() => _HostSalesStatsScreenState();
}

class _HostSalesStatsScreenState extends State<HostSalesStatsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: _tabs.length,
    vsync: this,
  )..addListener(_onTabChanged);

  HostSalesPeriod _period = HostSalesPeriod.last30;

  /// [HostSalesPeriod.custom]일 때 사용자가 고른 구간.
  DateRange? _customRange;

  HostSalesData _data = const HostSalesData();
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(_neededSince());
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) setState(() {});
  }

  DateRange get _range =>
      _customRange ?? _period.rangeAt(DateTime.now()) ?? _defaultRange();

  DateRange _defaultRange() =>
      HostSalesPeriod.last30.rangeAt(DateTime.now())!;

  /// 지금 화면이 필요로 하는 가장 이른 시각.
  ///
  /// 프리셋만 쓸 때는 '최근 30일'과 '이번 달' 중 더 이른 쪽까지 한 번에 읽어
  /// 둔다 — 그래야 프리셋 사이를 오갈 때 다시 읽지 않는다.
  DateTime _neededSince() {
    final now = DateTime.now();
    final presets = [
      HostSalesPeriod.last30.rangeAt(now)!.start,
      HostSalesPeriod.thisMonth.rangeAt(now)!.start,
    ];
    var since = presets.reduce((a, b) => a.isBefore(b) ? a : b);
    final custom = _customRange;
    if (custom != null && custom.start.isBefore(since)) since = custom.start;
    return since;
  }

  Future<void> _load(DateTime since) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await HostSalesService.fetch(
        uid: UserSession.userId,
        since: since,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// 고른 기간이 이미 읽어 온 구간보다 이전이면 다시 읽는다.
  void _ensureLoaded() {
    final since = _neededSince();
    final fetched = _data.fetchedSince;
    if (fetched == null || since.isBefore(fetched)) _load(since);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final current = _customRange;
    final picked = await showDateRangePicker(
      context: context,
      // 서비스 시작 이전으로는 내려갈 일이 없다 — 달력을 무한정 열어 두면
      // 잘못 고른 기간 때문에 읽기만 늘어난다.
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: current == null
          ? null
          : DateTimeRange(
              start: current.start,
              end: current.end.subtract(const Duration(days: 1)),
            ),
      helpText: '기간 선택',
      saveText: '적용',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _period = HostSalesPeriod.custom;
      // 고른 끝날을 **포함**해야 하므로 하루를 더해 열린 구간으로 만든다.
      _customRange = DateRange(
        DateTime(picked.start.year, picked.start.month, picked.start.day),
        DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
        ).add(const Duration(days: 1)),
      );
    });
    _ensureLoaded();
  }

  void _selectPeriod(HostSalesPeriod p) {
    if (p == HostSalesPeriod.custom) {
      _pickCustomRange();
      return;
    }
    setState(() {
      _period = p;
      _customRange = null;
    });
    _ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final kind = _tabs[_tabController.index].kind;
    final range = _range;
    final stats = HostSalesStats.from(
      _data.entries,
      range: range,
      kind: kind,
    );

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        title: const Text(
          '📊 판매 통계',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _kAccent,
          unselectedLabelColor: Colors.black45,
          indicatorColor: _kAccent,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          tabs: [for (final t in _tabs) Tab(text: t.label)],
        ),
      ),
      body: Column(
        children: [
          _PeriodBar(
            selected: _period,
            rangeLabel: range.label,
            onSelect: _selectPeriod,
          ),
          Expanded(child: _body(stats, kind, range)),
        ],
      ),
    );
  }

  Widget _body(HostSalesStats stats, SalesKind? kind, DateRange range) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_error != null) {
      return _Message(
        text: '통계를 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
        onRetry: () => _load(_neededSince()),
      );
    }

    return RefreshIndicator(
      color: _kAccent,
      onRefresh: () => _load(_neededSince()),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (_data.hasFailure) _FailureNotice(kinds: _data.failedKinds),
          _SummaryCard(stats: stats, rangeLabel: range.label),
          const SizedBox(height: 10),
          // 유형별 비중은 '통합'에서만 뜻이 있다 — 한 유형만 보고 있으면
          // 그 줄 하나가 총수익과 같은 숫자라 소음이다.
          if (kind == null) ...[
            _KindBreakdown(stats: stats),
            const SizedBox(height: 10),
          ],
          _DailySectionHeader(dayCount: stats.days.length),
          if (stats.isEmpty)
            const _EmptyDays()
          else
            for (final d in stats.days)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _DayTile(day: d),
              ),
        ],
      ),
    );
  }
}

// ── 기간 선택 줄 ──────────────────────────────────────────────────────────

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.selected,
    required this.rangeLabel,
    required this.onSelect,
  });

  final HostSalesPeriod selected;
  final String rangeLabel;
  final ValueChanged<HostSalesPeriod> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                for (final p in HostSalesPeriod.values) ...[
                  _PeriodChip(
                    label: p.label,
                    selected: p == selected,
                    icon: p == HostSalesPeriod.custom
                        ? Icons.calendar_today_outlined
                        : null,
                    onTap: () => onSelect(p),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
            child: Text(
              rangeLabel,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _kAccent : const Color(0xFFF1F0F6),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 13,
                  color: selected ? Colors.white : Colors.black54,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 요약 카드 ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.stats, required this.rangeLabel});

  final HostSalesStats stats;
  final String rangeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAccent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: '신청/예약',
                  value: '${comma(stats.count)}건',
                ),
              ),
              Container(width: 1, height: 30, color: const Color(0xFFEDEBF3)),
              Expanded(
                child: _Metric(
                  label: '총 인원',
                  value: '${comma(stats.headcount)}명',
                ),
              ),
            ],
          ),
          const Divider(height: 22, color: Color(0xFFEDEBF3)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '총수익',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
              const Spacer(),
              Text(
                '₩${comma(stats.confirmedRevenue)}',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  color: _kAccent,
                ),
              ),
            ],
          ),
          // 아직 안 들어온 돈은 **총수익과 섞지 않는다**. 입금대기·승인대기·
          // 현장결제 예정과 예약금 건의 현장 잔금이 여기 잡힌다.
          if (stats.pendingRevenue > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.schedule,
                  size: 13,
                  color: Colors.black38,
                ),
                const SizedBox(width: 4),
                Text(
                  '미확정 ₩${comma(stats.pendingRevenue)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '$rangeLabel · 결제가 확인된 금액만 총수익에 넣어요',
            style: const TextStyle(fontSize: 11.5, color: Colors.black38),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black45),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

/// 유형별 매출 비중 — 막대 하나로 비율을, 유형별 줄로 금액을 보여준다.
class _KindBreakdown extends StatelessWidget {
  const _KindBreakdown({required this.stats});

  final HostSalesStats stats;

  // SalesKind 전부에 색이 있어야 한다 — 아래 막대·범례가 `_colors[k]!`로 읽는다.
  static const _colors = {
    SalesKind.party: Color(0xFFFF6FA0),
    SalesKind.place: Color(0xFF39B98A),
    SalesKind.rental: Color(0xFF7C5CBF),
    SalesKind.shop: Color(0xFFF2A03D),
  };

  @override
  Widget build(BuildContext context) {
    final total = stats.confirmedRevenue;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '유형별 매출',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.black45,
            ),
          ),
          const SizedBox(height: 10),
          // 총수익이 0이면 비율이 없다 — 막대를 그리면 전부 0인데 뭔가 찬
          // 것처럼 보이므로 아예 빼고 금액 줄만 남긴다.
          if (total > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 7,
                child: Row(
                  children: [
                    for (final k in SalesKind.values)
                      if ((stats.revenueByKind[k] ?? 0) > 0)
                        Expanded(
                          flex: stats.revenueByKind[k]!,
                          child: ColoredBox(color: _colors[k]!),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final k in SalesKind.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _colors[k],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    k.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (total > 0)
                    Text(
                      '${((stats.revenueByKind[k] ?? 0) * 100 / total).round()}%',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.black38,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    '₩${comma(stats.revenueByKind[k] ?? 0)}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── 날짜별 ───────────────────────────────────────────────────────────────

class _DailySectionHeader extends StatelessWidget {
  const _DailySectionHeader({required this.dayCount});

  final int dayCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Row(
        children: [
          const Text(
            '날짜별',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 6),
          if (dayCount > 0)
            Text(
              '$dayCount일',
              style: const TextStyle(fontSize: 12, color: Colors.black38),
            ),
        ],
      ),
    );
  }
}

/// 하루 한 줄 — 누르면 그날의 상세 내역이 그 자리에서 펼쳐진다.
class _DayTile extends StatefulWidget {
  const _DayTile({required this.day});

  final DailySales day;

  @override
  State<_DayTile> createState() => _DayTileState();
}

class _DayTileState extends State<_DayTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.label,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '신청/예약 ${d.count}건 · 총 ${d.headcount}명',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${comma(d.confirmedRevenue)}원',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: _kAccent,
                        ),
                      ),
                      if (d.pendingRevenue > 0)
                        Text(
                          '미확정 ${comma(d.pendingRevenue)}원',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black38,
                          ),
                        ),
                    ],
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    color: Colors.black38,
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1, color: Color(0xFFF0EFF5)),
            for (final e in d.entries) _EntryRow(entry: e),
          ],
        ],
      ),
    );
  }
}

/// 상세 내역 한 줄 — 콘텐츠명 · 유형 · 인원 · 건별 금액 · 상태.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final SalesEntry entry;

  @override
  Widget build(BuildContext context) {
    final excluded = entry.revenueState == SalesRevenueState.excluded;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.kind.emoji,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        entry.contentTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          // 취소·환불 건은 흐리게 — 목록에는 남기되 "이건
                          // 돈이 아니다"가 한눈에 보이게 한다.
                          color: excluded ? Colors.black38 : Colors.black87,
                          decoration: excluded
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    entry.kind.label,
                    if (entry.subtitle != null) entry.subtitle!,
                    '${entry.headcount}명',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Colors.black45),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                // 건별 금액은 **확정 여부와 무관하게 그 건의 총액**을 보여준다.
                // 상태 배지가 그 돈이 들어왔는지 말해주므로, 미확정 건을 0원으로
                // 그리면 "얼마짜리 예약인지"를 알 수 없게 된다.
                '${comma(entry.totalAmount)}원',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: excluded ? Colors.black26 : Colors.black87,
                  decoration: excluded ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 3),
              _StatusBadge(entry: entry),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.entry});

  final SalesEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.revenueState) {
      SalesRevenueState.confirmed => const Color(0xFF39B98A),
      SalesRevenueState.pending => const Color(0xFFE8A33D),
      SalesRevenueState.excluded => Colors.black26,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        entry.statusLabel,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

// ── 빈 상태 · 에러 ────────────────────────────────────────────────────────

class _EmptyDays extends StatelessWidget {
  const _EmptyDays();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        children: [
          Text('📭', style: TextStyle(fontSize: 30)),
          SizedBox(height: 8),
          Text(
            '이 기간에 들어온 신청·예약·주문이 없어요.',
            style: TextStyle(fontSize: 13, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

/// 일부 유형만 못 불러왔을 때 — 나머지 숫자는 그대로 보여주고 이 사실만 알린다.
class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.kinds});

  final Set<SalesKind> kinds;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFFD98324)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '${kinds.map((k) => k.label).join('·')} 통계를 불러오지 못해 '
              '아래 숫자에서 빠져 있어요.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9A5B0E)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: _kAccent),
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}
