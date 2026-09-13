import 'package:flutter/material.dart';
import 'package:party_app/utils/refund_policy.dart';

/// 호스트가 파티별 환불 규정(기간 → 환불률)을 직접 등록/수정하는 위젯.
/// PartyChu는 환불률을 정하거나 권장하지 않는다 — 기본값 없이 빈 목록에서
/// 시작하며, 호스트가 직접 구간을 추가/삭제/순서 변경/환불률 입력한다.
///
/// 두 가지 배치로 쓴다:
///   - [scrollable] == false (기본): 구간 목록을 Column으로만 그린다. 이미
///     스크롤되는 화면(바텀시트의 SingleChildScrollView 등) 안에 끼워 넣을 때.
///   - [scrollable] == true: 위젯이 스스로 CustomScrollView가 된다. 구간을
///     수십 개 추가해도 목록이 지연 생성(SliverList)돼 오버플로가 없고,
///     키보드가 올라온 만큼 아래 여백이 늘어나 마지막 구간과 "구간 추가"
///     버튼까지 스크롤로 닿는다.
///
/// 어느 배치든 입력칸에 포커스가 가면 그 구간을 스크롤해서 키보드 위로
/// 올려준다(_revealFocusedRow).
class RefundPolicyEditor extends StatefulWidget {
  final List<RefundTier> initialTiers;
  final ValueChanged<List<RefundTier>> onChanged;

  /// 상단 안내 문구 — 파티는 기본값(파티 시작 기준), 숙박 객실 등 다른
  /// 맥락에서 재사용할 때는 그 맥락에 맞는 문구를 넘긴다.
  final String? introText;

  /// 위젯이 스스로 스크롤할지 여부. 바깥에 이미 스크롤 뷰가 있으면 false로
  /// 둬야 한다(스크롤 뷰 중첩 방지).
  final bool scrollable;

  /// [scrollable]일 때 목록 바깥 여백. 키보드 높이는 여기에 자동으로 더해진다.
  final EdgeInsets padding;

  const RefundPolicyEditor({
    super.key,
    required this.initialTiers,
    required this.onChanged,
    this.introText,
    this.scrollable = false,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<RefundPolicyEditor> createState() => _RefundPolicyEditorState();
}

class _RefundPolicyEditorState extends State<RefundPolicyEditor>
    with WidgetsBindingObserver {
  late List<RefundTier> _tiers;

  /// 지금 화면에 보여줘야 할 구간의 id — 입력칸에 포커스가 갔거나 방금 추가한
  /// 구간. 키보드가 올라오는 동안 뷰포트 높이가 여러 번 바뀌므로, id로 들고
  /// 있다가 매 변화마다 다시 스크롤해 확실히 키보드 위로 올린다.
  /// (RefundTier.id는 UniqueKey라 타입이 Object다.)
  Object? _revealTargetId;

  /// 구간별 GlobalKey — Scrollable.ensureVisible에 넘길 BuildContext를 얻는 용도.
  final Map<Object, GlobalKey> _rowKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tiers = widget.initialTiers
        .map(
          (t) => RefundTier(
            daysBefore: t.daysBefore,
            refundPercent: t.refundPercent,
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 키보드가 올라오거나 내려가서 뷰포트가 바뀔 때 호출된다 — 지금 입력 중인
  /// 구간이 키보드에 가려지지 않도록 다시 스크롤한다.
  @override
  void didChangeMetrics() {
    _revealAfterFrame();
  }

  GlobalKey _rowKey(Object id) => _rowKeys.putIfAbsent(id, () => GlobalKey());

  void _revealAfterFrame() {
    final id = _revealTargetId;
    if (id == null) return;
    // 레이아웃(키보드 인셋 반영)이 끝난 다음에 스크롤해야 목표 위치가 맞다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _revealTargetId != id) return;
      final ctx = _rowKeys[id]?.currentContext;
      if (ctx == null) return;
      // 바깥에 스크롤 뷰가 없는 배치(테스트 등)에서는 조용히 넘어간다.
      if (Scrollable.maybeOf(ctx) == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5, // 뷰포트 가운데로 — 위아래 어느 쪽에서든 가려지지 않게
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _notify() => widget.onChanged(_tiers);

  void _addTier() {
    final tier = RefundTier(daysBefore: 0, refundPercent: 0);
    setState(() {
      _tiers.add(tier);
      // 새로 추가한 구간이 화면 밖에 생기지 않도록 바로 보여준다.
      _revealTargetId = tier.id;
    });
    _revealAfterFrame();
    _notify();
  }

  void _removeTier(int index) {
    final removed = _tiers[index];
    setState(() {
      _tiers.removeAt(index);
      _rowKeys.remove(removed.id);
      if (_revealTargetId == removed.id) _revealTargetId = null;
    });
    _notify();
  }

  void _moveTier(int index, int delta) {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _tiers.length) return;
    setState(() {
      final item = _tiers.removeAt(index);
      _tiers.insert(newIndex, item);
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return widget.scrollable ? _buildScrollable(context) : _buildColumn();
  }

  // ── 배치 1: 바깥 스크롤 뷰에 끼워 넣는 Column ────────────────────────────

  Widget _buildColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(),
        const SizedBox(height: 12),
        if (_tiers.isEmpty) _emptyState(),
        for (var i = 0; i < _tiers.length; i++) ...[
          if (i != 0) const SizedBox(height: 8),
          _tierRow(i),
        ],
        const SizedBox(height: 10),
        _addButton(),
      ],
    );
  }

  // ── 배치 2: 스스로 스크롤하는 CustomScrollView ───────────────────────────

  Widget _buildScrollable(BuildContext context) {
    // Scaffold(resizeToAvoidBottomInset: true) 안에서는 이미 body가 줄어들어
    // 이 값이 0으로 들어온다 — 이중 여백이 생기지 않는다. 바텀시트처럼 body가
    // 줄지 않는 곳에서는 실제 키보드 높이가 들어와 그만큼 더 스크롤된다.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final p = widget.padding;

    return CustomScrollView(
      // 목록을 끌어내리면 키보드가 닫혀 화면을 더 넓게 볼 수 있다.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(p.left, p.top, p.right, 12),
          sliver: SliverToBoxAdapter(child: _intro()),
        ),
        if (_tiers.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: p.left),
            sliver: SliverToBoxAdapter(child: _emptyState()),
          ),
        // 구간이 수십 개여도 화면에 보이는 만큼만 만들어진다.
        SliverPadding(
          padding: EdgeInsets.only(left: p.left, right: p.right),
          sliver: SliverList.separated(
            itemCount: _tiers.length,
            itemBuilder: (_, i) => _tierRow(i),
            separatorBuilder: (_, _) => const SizedBox(height: 8),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            p.left,
            10,
            p.right,
            // 키보드가 올라와도 마지막 구간과 "구간 추가" 버튼까지 닿는다.
            p.bottom + keyboardInset,
          ),
          sliver: SliverToBoxAdapter(child: _addButton()),
        ),
      ],
    );
  }

  // ── 조각 ────────────────────────────────────────────────────────────────

  Widget _intro() => Text(
    widget.introText ??
        'PartyChu는 환불률을 정하거나 권장하지 않습니다. 파티 시작 기준 며칠 전부터 '
            '몇 %를 환불할지 직접 구간을 등록해주세요. 참가자는 결제 전 이 규정을 확인할 수 '
            '있고, 구간이 없으면 참가자가 취소해도 환불이 계산되지 않습니다.',
    style: const TextStyle(fontSize: 12, color: Colors.black45, height: 1.5),
  );

  Widget _emptyState() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F7FA),
      borderRadius: BorderRadius.circular(12),
    ),
    alignment: Alignment.center,
    // 최소 개수도 문구도 공용 규칙([RefundPolicyRule]) 하나에서 가져온다 —
    // 이 에디터를 쓰는 모든 등록/수정 화면이 같은 말을 하게 된다.
    child: const Text(
      '등록된 환불 구간이 없어요 · ${RefundPolicyRule.requiredMessage}',
      style: TextStyle(fontSize: 12, color: Color(0xFFE53935)),
    ),
  );

  Widget _addButton() => OutlinedButton.icon(
    onPressed: _addTier,
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFFFF6FA0),
      side: const BorderSide(color: Color(0xFFFF6FA0)),
    ),
    icon: const Icon(Icons.add, size: 18),
    label: const Text('구간 추가'),
  );

  Widget _tierRow(int index) {
    final tier = _tiers[index];
    return Focus(
      // 구간 identity 키 — 순서 변경/삭제 때 입력칸 상태가 엉뚱한 구간으로
      // 옮겨가지 않도록 목록 항목의 최상위에 둔다.
      key: ValueKey(tier.id),
      // 이 Focus는 자식 입력칸의 포커스를 관찰하기만 한다 — 스스로 포커스를
      // 받거나 탭 순서에 끼어들지 않는다.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          _revealTargetId = tier.id;
          _revealAfterFrame();
        } else if (_revealTargetId == tier.id) {
          _revealTargetId = null;
        }
      },
      child: Container(
        key: _rowKey(tier.id),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFE1EC)),
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: index == 0 ? null : () => _moveTier(index, -1),
                  child: Icon(
                    Icons.keyboard_arrow_up,
                    size: 18,
                    color: index == 0 ? Colors.black26 : Colors.black54,
                  ),
                ),
                InkWell(
                  onTap: index == _tiers.length - 1
                      ? null
                      : () => _moveTier(index, 1),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: index == _tiers.length - 1
                        ? Colors.black26
                        : Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            const Text(
              '시작',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 56,
              child: TextFormField(
                initialValue: tier.daysBefore.toString(),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  tier.daysBefore = int.tryParse(v) ?? 0;
                  _notify();
                },
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              '일 전부터',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: TextFormField(
                initialValue: tier.refundPercent.toString(),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final n = int.tryParse(v) ?? 0;
                  tier.refundPercent = n.clamp(0, 100);
                  _notify();
                },
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              '%',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => _removeTier(index),
              icon: const Icon(Icons.close, size: 18, color: Colors.black38),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}

/// 참가자에게 보여주는 읽기 전용 환불 규정 요약 — 파티 상세 화면과 취소
/// 확인창에서 재사용한다.
class RefundPolicyView extends StatelessWidget {
  final List<RefundTier> tiers;

  /// 기준 시점 라벨 — 파티는 기본값('파티 시작'), 숙박 객실은 '이용' 등.
  final String subjectLabel;

  const RefundPolicyView({
    super.key,
    required this.tiers,
    this.subjectLabel = '파티 시작',
  });

  @override
  Widget build(BuildContext context) {
    if (tiers.isEmpty) {
      return const Text(
        '호스트가 환불 규정을 등록하지 않았어요. 취소해도 환불되지 않을 수 있어요.',
        style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.5),
      );
    }
    final sorted = [...tiers]
      ..sort((a, b) => b.daysBefore.compareTo(a.daysBefore));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '$subjectLabel ${t.daysBefore}일 전부터: ${t.refundPercent}% 환불',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
      ],
    );
  }
}
