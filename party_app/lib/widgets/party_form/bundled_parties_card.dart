import 'package:flutter/material.dart';

import 'package:party_app/services/party_bundle_service.dart';

/// 파티 수정 화면의 "함께 등록된 파티" 카드.
///
/// 플레이스(숙박)+파티 통합 등록으로 **같이 만들어진** 파티들을 세로 목록으로
/// 보여주고, 각 항목에서 그 파티의 수정 화면으로 바로 갈 수 있게 한다.
/// 목록은 카드를 눌러 그 자리에서 펼치는 방식이다 — 별도 화면을 새로 만들면
/// 수정 화면의 미저장 상태를 들고 오가야 해서, 현재 구조에서는 인라인 확장이
/// 더 안전하다. 3개를 넘어가면 접힌 목록에는 3개만 두고 나머지는 "전체 보기"
/// 바텀시트에서 스크롤로 본다.
class BundledPartiesCard extends StatefulWidget {
  /// 조회 결과. 아직 로딩 중이면 [loading]이 true다.
  final PartyBundle bundle;
  final bool loading;

  /// "수정"을 누른 파티. 현재 파티를 눌렀을 때도 호출된다(호출부에서 안내만
  /// 띄우고 화면은 그대로 둔다).
  final Future<void> Function(BundledParty party) onEdit;

  /// 접힌 목록에 바로 보여줄 최대 개수.
  static const int previewCount = 3;

  const BundledPartiesCard({
    super.key,
    required this.bundle,
    required this.loading,
    required this.onEdit,
  });

  @override
  State<BundledPartiesCard> createState() => _BundledPartiesCardState();
}

class _BundledPartiesCardState extends State<BundledPartiesCard> {
  bool _expanded = false;

  static const Color _accent = Color(0xFFFF6FA0);

  @override
  Widget build(BuildContext context) {
    final bundle = widget.bundle;
    final parties = bundle.parties;
    final preview = parties.take(BundledPartiesCard.previewCount).toList();
    final hasMore = parties.length > preview.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: widget.loading
                  ? null
                  : () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '함께 등록된 파티',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.loading
                                ? '불러오는 중...'
                                : '이 장소와 함께 등록된 파티 ${parties.length}개',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.loading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.black38,
                      ),
                  ],
                ),
              ),
            ),
            if (_expanded && !widget.loading) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  children: [
                    for (final p in preview) ...[
                      _BundledPartyTile(
                        party: p,
                        onEdit: () => widget.onEdit(p),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (hasMore)
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => _openAll(context),
                          style: TextButton.styleFrom(foregroundColor: _accent),
                          child: Text('전체 보기 (${parties.length}개)'),
                        ),
                      ),
                    // 폴백 기준으로 모았으면 목록이 완전하지 않을 수 있다는
                    // 사실을 감춘 채 보여주지 않는다.
                    if (bundle.basis.isFallback)
                      const Padding(
                        padding: EdgeInsets.only(top: 4, left: 4, right: 4),
                        child: Text(
                          '이 파티에는 통합 등록 식별자(bundleId)가 없어 같은 등록 정보로 '
                          '추정해 묶었어요.',
                          style: TextStyle(fontSize: 11, color: Colors.black38),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openAll(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final parties = widget.bundle.parties;
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Text(
                    '이 장소와 함께 등록된 파티 ${parties.length}개',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: parties.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _BundledPartyTile(
                      party: parties[i],
                      onEdit: () async {
                        Navigator.pop(ctx);
                        await widget.onEdit(parties[i]);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 목록 1행 — 파티명/모집상태/일정/일회성·정기/참가비/인원 + "수정" 버튼.
class _BundledPartyTile extends StatelessWidget {
  final BundledParty party;
  final VoidCallback onEdit;

  const _BundledPartyTile({required this.party, required this.onEdit});

  static const Color _accent = Color(0xFFFF6FA0);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: party.isCurrent
            ? const Color(0xFFFFF3F7)
            : const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: party.isCurrent
              ? _accent.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  party.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (party.isCurrent) ...[
                const SizedBox(width: 6),
                _badge('현재 파티', color: _accent),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _badge(party.status, color: _statusColor(party.status)),
              _badge(party.scheduleKindLabel, color: Colors.black45),
            ],
          ),
          const SizedBox(height: 8),
          _infoLine(Icons.event_outlined, party.dateTimeLabel),
          const SizedBox(height: 4),
          _infoLine(Icons.payments_outlined, party.feeLabel),
          const SizedBox(height: 4),
          _infoLine(Icons.people_alt_outlined, party.capacityLabel),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('수정'),
              style: OutlinedButton.styleFrom(
                foregroundColor: party.isCurrent ? Colors.black45 : _accent,
                side: BorderSide(
                  color: party.isCurrent ? Colors.black26 : _accent,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                minimumSize: const Size(0, 34),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _infoLine(IconData icon, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.black38),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ],
    );
  }

  static Widget _badge(String text, {required Color color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
    ),
  );

  static Color _statusColor(String status) {
    switch (status) {
      case '모집중':
        return const Color(0xFF2E7D32);
      case '취소':
        return const Color(0xFFB00020);
      default:
        return Colors.black45;
    }
  }
}
