// ─────────────────────────────────────────────────────────────────────────────
// 판매 통계 — 관리자가 파티츄 전체와 판매자별 매출을 보는 화면.
//
// 관점 둘을 상단 탭으로 가른다.
//   ① 전체 통계    파티츄 전체 기준 건수·인원·거래금액과 일자별 내역
//   ② 판매자별 통계 호스트 한 명당 한 줄 — 누르면 그 사람 상세로
//
// **숫자를 세는 코드가 여기 없다.** 전부 packages/partychu_sales에 있고, 호스트
// 앱의 판매 통계 화면이 같은 함수를 쓴다. 그래서 어떤 판매자를 눌러 들어가도
// 그 사람이 자기 앱에서 보는 숫자와 같다.
//
// 읽기는 관리자 전용 콜러블(adminGetSalesEntries) 하나로만 한다 — 전 사용자
// 예약을 브라우저가 직접 긁지 않게 하고, 권한 검사를 서버 한 곳에 둔다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:partychu_sales/partychu_sales.dart';

import '../services/admin_sales_service.dart';
import '../theme/admin_theme.dart';
import '../utils/responsive.dart';

final _won = NumberFormat.decimalPattern('ko_KR');

String _money(int v) => '${_won.format(v)}원';

/// 유형 탭 — null은 '통합'(세 유형 합산).
const List<({String label, SalesKind? kind})> _kindTabs = [
  (label: '통합', kind: null),
  (label: '파티', kind: SalesKind.party),
  (label: '플레이스', kind: SalesKind.place),
  (label: '장소대여', kind: SalesKind.rental),
  (label: '파티샵', kind: SalesKind.shop),
];

class SalesStatsScreen extends StatefulWidget {
  const SalesStatsScreen({super.key, this.onOpenMember});

  /// 판매자 상세에서 '회원 상세로' 이동할 때 쓴다(회원 관리 화면 재사용).
  final void Function(String uid)? onOpenMember;

  @override
  State<SalesStatsScreen> createState() => _SalesStatsScreenState();
}

class _SalesStatsScreenState extends State<SalesStatsScreen> {
  HostSalesPeriod _period = HostSalesPeriod.last30;
  DateRange? _customRange;
  SalesKind? _kind;

  /// 0 = 전체 통계, 1 = 판매자별 통계.
  int _view = 0;

  /// 판매자별 표에서 누른 사람. null이면 목록을 보여준다.
  String? _openedSeller;

  String _query = '';
  bool _hideTestAccounts = true;

  AdminSalesData _data = const AdminSalesData();
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateRange get _range =>
      _customRange ??
      _period.rangeAt(DateTime.now()) ??
      HostSalesPeriod.last30.rangeAt(DateTime.now())!;

  Future<void> _load() async {
    final range = _range;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AdminSalesService.fetch(range: range);
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

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final current = _customRange;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
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
    _load();
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
    // 기간이 바뀌면 서버 조회 구간 자체가 달라지므로 반드시 다시 읽는다.
    _load();
  }

  /// 테스트 계정 판매자의 건은 기본으로 숨긴다 — 대시보드 KPI가 실사용자만
  /// 세는 것과 같은 기준이다(AdminFirestoreService의 isTestAccount 필터).
  Iterable<SalesEntry> get _visibleEntries {
    if (!_hideTestAccounts) return _data.entries;
    return _data.entries.where(
      (e) => !_data.sellerOf(e.hostId).isTestAccount,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '판매 통계',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 14),
            _ViewToggle(
              selected: _view,
              onSelect: (i) => setState(() {
                _view = i;
                _openedSeller = null;
              }),
            ),
            const Spacer(),
            IconButton(
              tooltip: '새로고침',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _FilterBar(
          period: _period,
          rangeLabel: _range.label,
          kind: _kind,
          hideTestAccounts: _hideTestAccounts,
          onPeriod: _selectPeriod,
          onKind: (k) => setState(() => _kind = k),
          onHideTest: (v) => setState(() => _hideTestAccounts = v),
        ),
        const SizedBox(height: 14),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AdminTheme.accent),
      );
    }
    if (_error != null) {
      return _ErrorState(error: _error!, onRetry: _load);
    }

    final entries = _visibleEntries;
    final range = _range;

    final opened = _openedSeller;
    if (_view == 1 && opened != null) {
      return _SellerDetail(
        identity: _data.sellerOf(opened),
        entries: entries.where((e) => e.hostId == opened),
        range: range,
        kind: _kind,
        onBack: () => setState(() => _openedSeller = null),
        onOpenMember: widget.onOpenMember,
      );
    }

    return ListView(
      children: [
        if (_data.truncated)
          _Notice(
            text:
                '조회 상한(소스당 5,000건)에 걸려 일부가 빠졌어요 — '
                '${_data.truncatedSources.join(', ')}. '
                '아래 숫자는 실제보다 작습니다. 기간을 좁혀 보세요.',
          ),
        if (_view == 0)
          ..._overallSlivers(entries, range)
        else
          _SellerTable(
            rows: SellerSales.group(entries, range: range, kind: _kind),
            data: _data,
            query: _query,
            onQuery: (q) => setState(() => _query = q),
            onOpen: (uid) => setState(() => _openedSeller = uid),
          ),
      ],
    );
  }

  List<Widget> _overallSlivers(Iterable<SalesEntry> entries, DateRange range) {
    final stats = HostSalesStats.from(entries, range: range, kind: _kind);
    return [
      _SummaryGrid(stats: stats, kind: _kind),
      const SizedBox(height: 14),
      const _SettlementNotice(),
      const SizedBox(height: 14),
      _DailyTable(stats: stats),
    ];
  }
}

// ── 상단 필터 ─────────────────────────────────────────────────────────────

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('전체 통계')),
        ButtonSegment(value: 1, label: Text('판매자별 통계')),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onSelect(s.first),
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.period,
    required this.rangeLabel,
    required this.kind,
    required this.hideTestAccounts,
    required this.onPeriod,
    required this.onKind,
    required this.onHideTest,
  });

  final HostSalesPeriod period;
  final String rangeLabel;
  final SalesKind? kind;
  final bool hideTestAccounts;
  final ValueChanged<HostSalesPeriod> onPeriod;
  final ValueChanged<SalesKind?> onKind;
  final ValueChanged<bool> onHideTest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminTheme.cardBorder),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final t in _kindTabs)
            ChoiceChip(
              label: Text(t.label),
              selected: kind == t.kind,
              onSelected: (_) => onKind(t.kind),
            ),
          const SizedBox(width: 12),
          const VerticalDivider(width: 1),
          for (final p in HostSalesPeriod.values)
            ChoiceChip(
              avatar: p == HostSalesPeriod.custom
                  ? const Icon(Icons.calendar_today_outlined, size: 14)
                  : null,
              label: Text(p.label),
              selected: period == p,
              onSelected: (_) => onPeriod(p),
            ),
          const SizedBox(width: 8),
          Text(
            rangeLabel,
            style: const TextStyle(
              fontSize: 12.5,
              color: AdminTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          // 대시보드 KPI와 같은 기준으로 실사용자만 보게 한다.
          FilterChip(
            label: const Text('테스트 계정 제외'),
            selected: hideTestAccounts,
            onSelected: onHideTest,
          ),
        ],
      ),
    );
  }
}

// ── 전체 통계 ─────────────────────────────────────────────────────────────

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.stats, required this.kind});

  final HostSalesStats stats;
  final SalesKind? kind;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Tile(label: '총 신청/예약', value: '${_won.format(stats.count)}건'),
        _Tile(label: '총 이용 인원', value: '${_won.format(stats.headcount)}명'),
        _Tile(
          label: '확정 거래금액',
          value: _money(stats.confirmedRevenue),
          emphasis: true,
          caption: '결제가 확인된 금액만',
        ),
        _Tile(
          label: '미확정 금액',
          value: _money(stats.pendingRevenue),
          caption: '입금·승인·현장결제 대기',
        ),
        _Tile(
          label: '취소·거절 건수',
          value: '${_won.format(stats.cancelledCount)}건',
        ),
        _Tile(
          label: '환불 금액(기록분)',
          value: _money(stats.refundedAmount),
          caption: '파티·콤보만 기록됨',
        ),
        // 유형별은 '통합'에서만 뜻이 있다 — 한 유형만 보고 있으면 그 값이
        // 확정 거래금액과 같은 숫자라 소음이다.
        if (kind == null)
          for (final k in SalesKind.values)
            _Tile(
              label: '${k.label} 거래금액',
              value: _money(stats.revenueByKind[k] ?? 0),
            ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    this.caption,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final String? caption;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: emphasis ? AdminTheme.accent : AdminTheme.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AdminTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: emphasis ? AdminTheme.accent : AdminTheme.textPrimary,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9AA1AE)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 정산 항목을 **일부러 비워 둔 이유**를 화면에 밝힌다.
///
/// 지금 파티 참가비와 예약금은 호스트가 자기 계좌로 직접 받고, 플랫폼 정산
/// 기록(수수료율·정산 회차·지급 완료 시각)을 남기는 컬렉션이 아직 없다.
/// 정산 완료/예정 금액을 보여주려면 그 값을 추정해야 하는데, 추정한 금액이
/// 관리자 화면에 뜨면 정산 근거로 쓰이게 된다. 그래서 만들지 않는다.
class _SettlementNotice extends StatelessWidget {
  const _SettlementNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0DFB8)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 17, color: Color(0xFFB8860B)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '정산 완료·정산 예정 금액은 표시하지 않습니다 — 수수료율과 정산 회차가 '
              '아직 정해지지 않았고, 지급 기록을 남기는 데이터도 없습니다. '
              '추정값을 띄우면 정산 근거로 쓰이게 되므로 정책이 확정된 뒤에 추가합니다.\n'
              '환불 금액은 파티 신청과 숙박+파티 콤보에만 기록이 남습니다 — '
              '장소대여 단독·플레이스 방문 예약의 환불액은 저장되는 자리가 없어 '
              '위 금액은 실제 환불 총액의 하한입니다.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF7A5B12), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyTable extends StatelessWidget {
  const _DailyTable({required this.stats});

  final HostSalesStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return const _Empty(text: '이 기간에 들어온 신청·예약이 없습니다.');
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              '날짜별',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          for (final d in stats.days) _DayRow(day: d),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// 하루 한 줄 — 펼치면 그날의 건별 내역이 나온다.
class _DayRow extends StatefulWidget {
  const _DayRow({required this.day});

  final DailySales day;

  @override
  State<_DayRow> createState() => _DayRowState();
}

class _DayRowState extends State<_DayRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: AdminTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: context.isCompact ? 84 : 130,
                  child: Text(
                    d.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                Text(
                  '${d.count}건',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AdminTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 18),
                Text(
                  '${d.headcount}명',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AdminTheme.textSecondary,
                  ),
                ),
                const Spacer(),
                // 금액이 길어도 행이 넘치지 않게 남는 폭 안에서 줄어든다.
                if (d.pendingRevenue > 0)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Text(
                        '미확정 ${_money(d.pendingRevenue)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9AA1AE),
                        ),
                      ),
                    ),
                  ),
                Text(
                  _money(d.confirmedRevenue),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AdminTheme.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Container(
            color: const Color(0xFFFAFBFD),
            padding: const EdgeInsets.fromLTRB(42, 4, 16, 10),
            child: Column(
              children: [for (final e in d.entries) _EntryRow(entry: e)],
            ),
          ),
        const Divider(height: 1, color: AdminTheme.cardBorder),
      ],
    );
  }
}

/// 건별 한 줄 — 콘텐츠명 · 유형 · 인원 · 금액 · 상태.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final SalesEntry entry;

  @override
  Widget build(BuildContext context) {
    final excluded = entry.revenueState == SalesRevenueState.excluded;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: Text(
              '${entry.kind.emoji} ${entry.contentTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: excluded ? const Color(0xFF9AA1AE) : null,
                decoration: excluded ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              entry.kind.label,
              style: const TextStyle(
                fontSize: 12,
                color: AdminTheme.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: 180,
            child: Text(
              entry.subtitle ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9AA1AE)),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              '${entry.headcount}명',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              _money(entry.totalAmount),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: excluded ? const Color(0xFFB6BCC7) : null,
                decoration: excluded ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 14),
          _StatusChip(entry: entry),
          if (entry.refundAmount > 0) ...[
            const SizedBox(width: 10),
            Text(
              '환불 ${_money(entry.refundAmount)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFFC2410C)),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.entry});

  final SalesEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.revenueState) {
      SalesRevenueState.confirmed => const Color(0xFF16A34A),
      SalesRevenueState.pending => const Color(0xFFD97706),
      SalesRevenueState.excluded => const Color(0xFF9AA1AE),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        entry.statusLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

// ── 판매자별 통계 ─────────────────────────────────────────────────────────

class _SellerTable extends StatelessWidget {
  const _SellerTable({
    required this.rows,
    required this.data,
    required this.query,
    required this.onQuery,
    required this.onOpen,
  });

  final List<SellerSales> rows;
  final AdminSalesData data;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onOpen;

  /// 닉네임 / 실명 / UID / 콘텐츠명으로 거른다.
  List<SellerSales> get _filtered {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((r) {
      if (data.sellerOf(r.hostId).matches(q)) return true;
      return r.contentTitles.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: context.fluid(420),
          child: TextField(
            decoration: const InputDecoration(
              hintText: '닉네임 · 실명 · UID · 콘텐츠명으로 검색',
              prefixIcon: Icon(Icons.search, size: 19),
              isDense: true,
            ),
            onChanged: onQuery,
          ),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const _Empty(text: '조건에 맞는 판매자가 없습니다.')
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminTheme.cardBorder),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 26,
                columns: const [
                  DataColumn(label: Text('판매자')),
                  DataColumn(label: Text('UID')),
                  DataColumn(label: Text('파티'), numeric: true),
                  DataColumn(label: Text('플레이스'), numeric: true),
                  DataColumn(label: Text('장소대여'), numeric: true),
                  DataColumn(label: Text('파티샵'), numeric: true),
                  DataColumn(label: Text('통합 총수익'), numeric: true),
                  DataColumn(label: Text('건수'), numeric: true),
                  DataColumn(label: Text('인원'), numeric: true),
                  DataColumn(label: Text('취소'), numeric: true),
                ],
                rows: [
                  for (final r in filtered)
                    DataRow(
                      onSelectChanged: (_) => onOpen(r.hostId),
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              Text(data.sellerOf(r.hostId).displayLabel),
                              if (data.sellerOf(r.hostId).isTestAccount) ...[
                                const SizedBox(width: 6),
                                const _TestBadge(),
                              ],
                            ],
                          ),
                        ),
                        DataCell(
                          SelectableText(
                            r.hostId,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AdminTheme.textSecondary,
                            ),
                          ),
                        ),
                        DataCell(Text(_money(r.revenueOf(SalesKind.party)))),
                        DataCell(Text(_money(r.revenueOf(SalesKind.place)))),
                        DataCell(Text(_money(r.revenueOf(SalesKind.rental)))),
                        DataCell(Text(_money(r.revenueOf(SalesKind.shop)))),
                        DataCell(
                          Text(
                            _money(r.confirmedRevenue),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AdminTheme.accent,
                            ),
                          ),
                        ),
                        DataCell(Text('${r.count}건')),
                        DataCell(Text('${r.headcount}명')),
                        DataCell(Text('${r.cancelledCount}건')),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TestBadge extends StatelessWidget {
  const _TestBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: const Color(0xFFEEF0F4),
      borderRadius: BorderRadius.circular(5),
    ),
    child: const Text(
      '테스트',
      style: TextStyle(fontSize: 10, color: AdminTheme.textSecondary),
    ),
  );
}

/// 판매자 한 명의 상세 — 날짜별·콘텐츠별 매출과 건별 내역.
///
/// 여기 숫자는 그 판매자가 자기 앱의 판매 통계에서 보는 것과 **같은 함수**로
/// 나온다([HostSalesStats.from]). 같은 기간을 고르면 같은 금액이어야 한다.
class _SellerDetail extends StatelessWidget {
  const _SellerDetail({
    required this.identity,
    required this.entries,
    required this.range,
    required this.kind,
    required this.onBack,
    this.onOpenMember,
  });

  final SellerIdentity identity;
  final Iterable<SalesEntry> entries;
  final DateRange range;
  final SalesKind? kind;
  final VoidCallback onBack;
  final void Function(String uid)? onOpenMember;

  @override
  Widget build(BuildContext context) {
    final stats = HostSalesStats.from(entries, range: range, kind: kind);

    // 콘텐츠별 매출 — 같은 이름의 콘텐츠를 한 줄로 묶는다.
    final byContent = <String, List<SalesEntry>>{};
    for (final e in entries) {
      if (kind != null && e.kind != kind) continue;
      if (!range.contains(e.bookedAt)) continue;
      (byContent['${e.kind.name}|${e.contentTitle}'] ??= []).add(e);
    }
    final contentRows = byContent.values.toList()
      ..sort((a, b) {
        int rev(List<SalesEntry> l) =>
            l.fold(0, (s, e) => s + e.confirmedAmount);
        return rev(b).compareTo(rev(a));
      });

    return ListView(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 20),
              tooltip: '판매자 목록으로',
            ),
            const SizedBox(width: 4),
            Text(
              identity.displayLabel,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 10),
            SelectableText(
              identity.uid,
              style: const TextStyle(
                fontSize: 12,
                color: AdminTheme.textSecondary,
              ),
            ),
            if (onOpenMember != null) ...[
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: () => onOpenMember!(identity.uid),
                icon: const Icon(Icons.person_outline, size: 16),
                label: const Text('회원 상세'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        _SummaryGrid(stats: stats, kind: kind),
        const SizedBox(height: 18),
        const Text(
          '콘텐츠별 매출',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (contentRows.isEmpty)
          const _Empty(text: '이 기간에 매출이 없습니다.')
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminTheme.cardBorder),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 26,
                columns: const [
                  DataColumn(label: Text('콘텐츠')),
                  DataColumn(label: Text('유형')),
                  DataColumn(label: Text('건수'), numeric: true),
                  DataColumn(label: Text('인원'), numeric: true),
                  DataColumn(label: Text('확정 매출'), numeric: true),
                  DataColumn(label: Text('미확정'), numeric: true),
                  DataColumn(label: Text('취소'), numeric: true),
                  DataColumn(label: Text('환불'), numeric: true),
                ],
                rows: [
                  for (final items in contentRows)
                    DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 280,
                            child: Text(
                              items.first.contentTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(Text(items.first.kind.label)),
                        DataCell(Text('${items.length}건')),
                        DataCell(
                          Text('${items.fold(0, (s, e) => s + e.headcount)}명'),
                        ),
                        DataCell(
                          Text(
                            _money(
                              items.fold(0, (s, e) => s + e.confirmedAmount),
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AdminTheme.accent,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            _money(items.fold(0, (s, e) => s + e.pendingAmount)),
                          ),
                        ),
                        DataCell(
                          Text(
                            '${items.where((e) => e.revenueState == SalesRevenueState.excluded).length}건',
                          ),
                        ),
                        DataCell(
                          Text(
                            _money(items.fold(0, (s, e) => s + e.refundAmount)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 18),
        const Text(
          '날짜별 매출',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _DailyTable(stats: stats),
      ],
    );
  }
}

// ── 공통 ─────────────────────────────────────────────────────────────────

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFF3C9C9)),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded, size: 17, color: Color(0xFFC2410C)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A3412)),
          ),
        ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 46),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AdminTheme.cardBorder),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AdminTheme.textSecondary, fontSize: 13),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // 관리자가 아닌 계정으로 열면 서버가 permission-denied를 돌려준다 —
    // 권한 문제와 일시적 오류를 구분해 보여준다.
    final denied = error.toString().contains('permission-denied');
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            denied
                ? '관리자 계정만 판매 통계를 볼 수 있습니다.'
                : '통계를 불러오지 못했습니다.\n잠시 후 다시 시도해주세요.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AdminTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          if (!denied)
            ElevatedButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
