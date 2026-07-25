import 'package:flutter/material.dart';

import 'package:party_app/models/draft_type.dart';
import 'package:party_app/services/draft_service.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/screens/place_register_screen.dart';
import 'package:party_app/screens/event_register_screen.dart';
import 'package:party_app/screens/crew_register_screen.dart';
import 'package:party_app/screens/party_shop_product_register_screen.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 마이페이지 → "임시저장". 사용자별 임시저장을 유형(파티/장소/파티샵/
/// 파티크루/플레이스)별로 묶어 보여주고, 이어서 작성·삭제를 제공한다.
class DraftsListScreen extends StatelessWidget {
  const DraftsListScreen({super.key});

  static const _accent = Color(0xFFFF6FA0);

  String _savedAtLabel(DateTime? dt) {
    if (dt == null) return '';
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$mm/$dd $hh:$mi 저장';
  }

  Future<void> _continue(BuildContext context, DraftRecord record) async {
    // 유형에 맞는 등록 화면으로 이동하며, 다시 묻지 않고 곧바로 복구하도록
    // autoRestoreDraft: true로 연다.
    final Widget target;
    switch (record.type) {
      case DraftType.party:
        target = const PartyRegisterScreen(autoRestoreDraft: true);
        break;
      case DraftType.place:
        target = const PlaceRegisterScreen(autoRestoreDraft: true);
        break;
      case DraftType.event:
        target = const EventRegisterScreen(autoRestoreDraft: true);
        break;
      case DraftType.crewRecruit:
        target = const CrewRegisterScreen(
            autoRestoreDraft: true, initialCrewType: '구인');
        break;
      case DraftType.crewSeek:
        target = const CrewRegisterScreen(
            autoRestoreDraft: true, initialCrewType: '구직');
        break;
      case DraftType.shop:
        // 파티샵 상품은 특정 샵에 속하므로 payload에 저장해둔 샵 정보로 연다.
        final shopId = record.payload['shopId'] as String?;
        final shopName = record.payload['shopName'] as String? ?? '';
        if (shopId == null || shopId.isEmpty) return;
        target = PartyShopProductRegisterScreen(
          shopId: shopId,
          shopName: shopName,
          autoRestoreDraft: true,
        );
        break;
    }
    await Navigator.push(context, webFramedRoute((_) => target));
  }

  Future<void> _delete(BuildContext context, DraftRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text('${record.type.label} 임시저장을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DraftService.deleteDraft(record.type);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text('임시저장',
            style: TextStyle(
                fontFamily: 'SeoulHangang',
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                  Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                  Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                ])),
        centerTitle: true,
      ),
      body: StreamBuilder<List<DraftRecord>>(
        stream: DraftService.watchAllDrafts(UserSession.userId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _accent));
          }
          final drafts = snap.data ?? const [];
          if (drafts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '임시저장된 작성 내용이 없어요.',
                  style: TextStyle(color: Colors.black45),
                ),
              ),
            );
          }

          // 유형 그룹(파티/장소/파티샵/파티크루/플레이스)으로 묶는다.
          final groups = <String, List<DraftRecord>>{};
          for (final d in drafts) {
            groups.putIfAbsent(d.type.groupLabel, () => []).add(d);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54),
                  ),
                ),
                ...entry.value.map((d) => _draftCard(context, d)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _draftCard(BuildContext context, DraftRecord record) {
    final title = record.title.trim().isEmpty ? '제목 없음' : record.title.trim();
    final cover = record.coverImageUrl;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0FFF6FA0), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: (cover != null && cover.isNotEmpty)
                    ? Image.network(cover, fit: BoxFit.cover,
                        errorBuilder: (ctx, e, st) => _coverPlaceholder())
                    : _coverPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEAF1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(record.type.label,
                            style: const TextStyle(
                                fontSize: 11,
                                color: _accent,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Text(_savedAtLabel(record.updatedAt),
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.black45)),
                    ],
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _continue(context, record),
              child: const Text('이어서 작성',
                  style: TextStyle(color: _accent, fontWeight: FontWeight.w700)),
            ),
            IconButton(
              onPressed: () => _delete(context, record),
              icon: const Icon(Icons.delete_outline, color: Colors.black38),
              tooltip: '삭제',
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder() => Container(
        color: const Color(0xFFFFEAF1),
        child: const Center(
          child: Icon(Icons.edit_note, color: Color(0xFFFFB8CF)),
        ),
      );
}
