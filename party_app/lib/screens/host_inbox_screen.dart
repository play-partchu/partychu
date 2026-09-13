import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:party_app/screens/party_applicants_screen.dart';
import 'package:party_app/screens/place_reservation_manage_screen.dart';
import 'package:party_app/screens/visit_reservation_manage_screen.dart';
import 'package:party_app/services/host_inbox_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 호스트용 **통합 신청자·예약자 관리**.
///
/// 파티 신청 · 플레이스 방문 예약 · 장소대여 예약 · 숙박+파티 콤보를 한 목록으로
/// 보여준다. 지금까지는 종류마다 다른 화면으로 들어가야 해서 "어디에 처리할 게
/// 남았는지"를 호스트가 기억해야 했다.
///
/// 이 화면은 **보여주기만 한다.** 승인·거절·입금확인은 줄을 눌러 기존 관리
/// 화면으로 넘어가서 하고, 그 화면들이 쓰는 콜러블도 그대로다 — 같은 동작을
/// 두 곳에 만들면 한쪽만 고쳐지는 순간 호스트가 보는 결과가 갈린다.
///
/// 목록을 만드는 규칙은 [HostInboxService]에 있다.
class HostInboxScreen extends StatefulWidget {
  const HostInboxScreen({super.key, this.initialFilter = HostInboxFilter.all});

  /// 알림을 눌러 들어온 경우 '처리 필요'로 열린다 — 알림이 말한 일이 바로
  /// 보여야 하기 때문이다(notification_route.dart).
  final HostInboxFilter initialFilter;

  @override
  State<HostInboxScreen> createState() => _HostInboxScreenState();
}

class _HostInboxScreenState extends State<HostInboxScreen> {
  late HostInboxFilter _filter = widget.initialFilter;

  /// 파티 신청은 콜러블이라 스트림이 스스로 갱신되지 않는다. 새로 고침은
  /// 스트림을 통째로 다시 만든다(party_applicants_screen이 Future를 갈아끼우는
  /// 것과 같은 방식).
  late Stream<HostInboxSnapshot> _stream = HostInboxService.watch(
    UserSession.userId,
  );

  void _reload() {
    setState(() => _stream = HostInboxService.watch(UserSession.userId));
  }

  @override
  Widget build(BuildContext context) {
    final uid = UserSession.userId;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '신청자 · 예약자 관리',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: uid.isEmpty
          ? const Center(
              child: Text(
                '로그인 후 이용할 수 있어요.',
                style: TextStyle(fontSize: 13.5, color: Colors.black45),
              ),
            )
          : StreamBuilder<HostInboxSnapshot>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  logFirestoreStreamError(
                    'HostInbox',
                    snap.error,
                    snap.stackTrace,
                  );
                  return _Message(text: '신청·예약을 불러오지 못했어요.', onRetry: _reload);
                }
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: PartyChuColors.primary,
                    ),
                  );
                }
                return _body(snap.data!);
              },
            ),
    );
  }

  Widget _body(HostInboxSnapshot data) {
    final items = data.entries.where(_filter.matches).toList();
    return Column(
      children: [
        _FilterBar(
          value: _filter,
          counts: {
            for (final f in HostInboxFilter.values)
              f: data.entries.where(f.matches).length,
          },
          onChanged: (f) => setState(() => _filter = f),
        ),
        // 파티만 못 불러온 경우 — 예약 목록은 그대로 두고 사실만 말한다.
        // 조용히 비워 두면 호스트는 "신청이 없다"고 읽는다.
        if (data.partyFailed)
          _Notice(text: '파티 신청을 불러오지 못했어요. 예약만 표시하고 있어요.', onRetry: _reload),
        if (data.truncated) const _Notice(text: '최근 파티 신청 300건만 보여주고 있어요.'),
        Expanded(
          child: RefreshIndicator(
            color: PartyChuColors.primary,
            onRefresh: () async => _reload(),
            child: items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(40, 90, 40, 0),
                        child: Text(
                          _filter.emptyText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: Colors.black45,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(14),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _EntryTile(
                      entry: items[i],
                      onTap: () => _open(items[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// 기존 관리 화면으로 그대로 넘긴다 — 승인/거절/입금확인은 거기에 이미 있다.
  Future<void> _open(HostInboxEntry entry) async {
    switch (entry.kind) {
      case HostInboxKind.visit:
        await Navigator.push(
          context,
          webFramedRoute((_) => const VisitReservationManageScreen()),
        );
      case HostInboxKind.rental:
      case HostInboxKind.package:
        await Navigator.push(
          context,
          webFramedRoute((_) => const PlaceReservationManageScreen()),
        );
      case HostInboxKind.party:
        await _openPartyApplicants(entry);
    }
    // 돌아오면 파티 신청을 다시 받는다 — 방금 승인한 건이 목록에 남아 있으면
    // 호스트는 승인이 안 된 줄 안다(예약 3종은 스트림이라 이미 최신이다).
    if (mounted) _reload();
  }

  /// 파티 신청자 화면은 파티 문서를 필요로 한다(모집 현황·회차 라벨). 신청
  /// 문서에는 없으므로 이 시점에 한 번 읽는다 — 파티 문서는 공개 읽기라
  /// 별도 권한이 필요 없다.
  Future<void> _openPartyApplicants(HostInboxEntry entry) async {
    final partyId = entry.partyId;
    if (partyId == null || partyId.isEmpty) return;

    Map<String, dynamic>? data;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('parties')
          .doc(partyId)
          .get();
      data = doc.data();
    } catch (e) {
      debugPrintThrottled('[HostInbox] 파티 문서 조회 실패 $partyId: $e');
    }
    if (!mounted) return;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('파티를 불러오지 못했어요. 삭제된 파티일 수 있어요.')),
      );
      return;
    }

    final rounds = (data['rounds'] as List?)
        ?.whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();

    await Navigator.push(
      context,
      webFramedRoute(
        (_) => PartyApplicantsScreen(
          partyId: partyId,
          partyTitle: data!['title'] as String? ?? entry.contentTitle,
          rounds: rounds,
          partyData: data,
        ),
      ),
    );
  }
}

// ── 상단 필터 ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.value,
    required this.counts,
    required this.onChanged,
  });

  final HostInboxFilter value;
  final Map<HostInboxFilter, int> counts;
  final ValueChanged<HostInboxFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          for (final f in HostInboxFilter.values) ...[
            if (f != HostInboxFilter.values.first) const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(f),
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: f == value
                        ? PartyChuColors.primary
                        : const Color(0xFFF6F7FA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${f.label} ${counts[f] ?? 0}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: f == value
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: f == value ? Colors.white : Colors.black54,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 한 줄 ────────────────────────────────────────────────────────────────────

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final HostInboxEntry entry;
  final VoidCallback onTap;

  static const _kindColor = {
    HostInboxKind.party: Color(0xFFFF6FA0),
    HostInboxKind.visit: Color(0xFF3FA9F5),
    HostInboxKind.rental: Color(0xFF7C5CBF),
    HostInboxKind.package: Color(0xFF2FB380),
  };

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  /// `8월 22일(금) 오후 7시` — 날짜가 없으면 빈 문자열.
  static String _when(DateTime? at) {
    if (at == null) return '';
    final weekday = _weekdays[at.weekday - 1];
    final ampm = at.hour < 12 ? '오전' : '오후';
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final time = at.minute == 0 ? '$hour시' : '$hour시 ${at.minute}분';
    return '${at.month}월 ${at.day}일($weekday) $ampm $time';
  }

  @override
  Widget build(BuildContext context) {
    final accent = _kindColor[entry.kind] ?? PartyChuColors.primary;
    final when = _when(entry.at);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Badge(text: entry.kind.label, color: accent),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      entry.contentTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 미처리는 상태 칩 자체를 강조한다 — 별도 아이콘을 더하면
                  // 한 줄에 신호가 둘이 되어 오히려 눈에 덜 띈다.
                  _StatusChip(
                    text: entry.statusLabel,
                    highlighted: entry.unhandled,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                [
                  entry.personLabel,
                  if (when.isNotEmpty) when,
                  if (entry.subtitle != null && entry.subtitle!.isNotEmpty)
                    entry.subtitle!,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, required this.highlighted});

  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted ? PartyChuColors.primary : const Color(0xFFF1F2F6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: highlighted ? Colors.white : Colors.black54,
        ),
      ),
    );
  }
}

// ── 안내 줄 ──────────────────────────────────────────────────────────────────

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF4E5),
      padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A5A00)),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('다시 시도', style: TextStyle(fontSize: 12)),
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
            style: const TextStyle(fontSize: 13.5, color: Colors.black45),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
