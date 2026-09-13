import 'package:flutter/material.dart';

import 'package:party_app/models/combo_place_type.dart';
import 'package:party_app/models/draft_type.dart';
import 'package:party_app/services/party_create_eligibility.dart';
import 'package:party_app/services/place_create_eligibility.dart';
import 'package:party_app/services/registration_limits.dart';
import 'package:party_app/services/draft_service.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/screens/place_entry_register_screen.dart';
import 'package:party_app/screens/crew_register_screen.dart';
import 'package:party_app/screens/party_market_register_screen.dart';
import 'package:party_app/screens/party_shop_product_register_screen.dart';
import 'package:party_app/utils/auto_delete_retention.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 마이페이지 → "임시저장". 사용자별 임시저장을 유형(파티/장소/파티샵/
/// 파티크루/플레이스)별로 묶어 보여주고, 이어서 작성·삭제를 제공한다.
///
/// ⚠️ "0건"과 "조회 실패"를 반드시 구분한다 — 예전에는 `snap.data ?? []`로
/// 받아서 권한 오류로 스트림이 죽어도 "임시저장된 작성 내용이 없어요"가 떴다.
/// 작성 중이던 글이 멀쩡히 남아 있는데 없다고 말하는 셈이라, 사용자는 다시
/// 처음부터 쓰게 된다(실제로 drafts 목록 쿼리가 규칙 문제로 늘 거부되고
/// 있었다 — firestore.rules의 drafts get/list 분리 주석 참고).
class DraftsListScreen extends StatefulWidget {
  const DraftsListScreen({super.key});

  @override
  State<DraftsListScreen> createState() => _DraftsListScreenState();
}

class _DraftsListScreenState extends State<DraftsListScreen> {
  static const _accent = Color(0xFFFF6FA0);

  /// '다시 시도'를 누르면 값이 바뀌어 StreamBuilder가 스트림을 새로 만든다 —
  /// 거부된 Firestore 리스너는 스스로 재시도하지 않기 때문에, 다시 구독하는
  /// 것 말고는 복구할 방법이 없다.
  int _retry = 0;

  String _savedAtLabel(DateTime? dt) {
    if (dt == null) return '';
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$mm/$dd $hh:$mi 저장';
  }

  /// 목록 맨 위 보관기간 안내 — 지난 파티 탭의 배너와 같은 모양·같은 규칙
  /// (my_host_hub_screen의 _pastWarningBanner). 카드마다 붙는 'D-n'이
  /// 무엇을 세는 값인지 여기서 한 번 말해 준다.
  static Widget _retentionBanner() => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E0),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFCC80)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFE65100)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '임시저장은 마지막 저장일로부터 ${AutoDeleteRetention.window.inDays}일간 '
            '보관되며, 지나면 자동으로 삭제됩니다. '
            '이어서 작성하고 다시 저장하면 기간이 새로 시작돼요.',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFBF360C),
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );

  /// 카드 아래 붙는 '자동삭제 D-n' 한 줄. 기준점을 모르는 옛 문서는 아무
  /// 말도 하지 않는다(빈 목록을 돌려준다) — 모르는 채로 날짜를 지어내면
  /// 안 된다.
  ///
  /// 삭제가 3일 안으로 다가오면 붉게 바꾼다. 그 아래(오늘·지남)까지 같은
  /// 색이라 "오늘 자동삭제"도 같은 무게로 읽힌다.
  static List<Widget> _autoDeleteLine(DateTime? updatedAt) {
    final label = AutoDeleteRetention.label(updatedAt);
    if (label == null) return const [];
    final urgent = AutoDeleteRetention.isUrgent(updatedAt);
    return [
      const SizedBox(height: 3),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: urgent ? const Color(0xFFD84315) : Colors.black38,
        ),
      ),
    ];
  }

  /// 이 임시저장을 이어 쓰면 **새 파티 문서가 만들어지는가.**
  ///
  /// 지금은 파티 등록 하나뿐이다 — 플레이스와 파티를 한 폼에서 함께 만들던
  /// 콤보 등록 두 종류(플레이스+파티 / 숙박+파티)는 등록 방식 자체가
  /// 없어졌다. 그 임시저장 종류도 [DraftType]에서 빠져서, 남아 있는 옛
  /// 문서는 목록에 아예 올라오지 않는다(DraftService.watchAllDrafts가
  /// 모르는 key를 건너뛴다).
  static bool _createsParty(DraftType type) => type == DraftType.party;

  /// 새 **플레이스**를 만드는 임시저장인가.
  ///
  /// 예전 이름 그대로다: event = 옛 "플레이스 등록"(`events`),
  /// place = 옛 "파티 장소 등록"(`places`).
  static bool _createsPlace(DraftType type) =>
      type == DraftType.event || type == DraftType.place;

  Future<void> _continue(BuildContext context, DraftRecord record) async {
    // 임시저장 이어쓰기도 결국 **새 파티를 만드는 길**이라 등록 화면과 같은
    // 관문을 지난다 — 여기가 열려 있으면 개인 호스트가 임시저장으로 우회한다.
    // (파티를 만들지 않는 유형은 예전 그대로 지나간다.)
    if (_createsParty(record.type)) {
      if (!await PartyCreateEligibility.ensure(context)) return;
      if (!context.mounted) return;
    }

    // 플레이스도 같다 — 이어쓰기는 **새 플레이스를 만드는 길**이므로 등록
    // 화면과 같은 사업자 관문을 지난다([PlaceCreateEligibility]).
    if (_createsPlace(record.type)) {
      // 임시저장 종류가 곧 만들려는 유형이라 등록 개수도 함께 본다
      // (event = 플레이스 / place = 장소대여, 각각 10개).
      if (!await PlaceCreateEligibility.ensure(
        context,
        kind: record.type == DraftType.event
            ? RegistrationKind.placeListing
            : RegistrationKind.rentalListing,
      )) {
        return;
      }
      if (!context.mounted) return;
    }

    // 유형에 맞는 등록 화면으로 이동하며, 다시 묻지 않고 곧바로 복구하도록
    // autoRestoreDraft: true로 연다.
    final Widget target;
    switch (record.type) {
      case DraftType.party:
        target = const PartyRegisterScreen(autoRestoreDraft: true);
        break;
      // 공간 단독 등록 임시저장 두 종류도 통합 "플레이스 등록" 화면 하나로
      // 열되, 저장해둔 유형이 이미 선택된 상태로 들어간다(임시저장 종류가 곧
      // 공간 유형이다 — 콤보 임시저장과 같은 규칙).
      //
      // 예전 이름 그대로다: event = 옛 "플레이스 등록", place = 옛 "파티 장소
      // 등록". 합치기 전에 저장해둔 임시저장이 그대로 열린다.
      case DraftType.place:
      case DraftType.event:
        target = PlaceEntryRegisterScreen(
          initialType: ComboPlaceType.fromDraftType(record.type),
          autoRestoreDraft: true,
        );
        break;
      case DraftType.crewRecruit:
        target = const CrewRegisterScreen(
          autoRestoreDraft: true,
          initialCrewType: '구인',
        );
        break;
      case DraftType.crewSeek:
        target = const CrewRegisterScreen(
          autoRestoreDraft: true,
          initialCrewType: '구직',
        );
        break;
      case DraftType.market:
        target = const PartyMarketRegisterScreen(autoRestoreDraft: true);
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
        title: const Text(
          '임시저장',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<List<DraftRecord>>(
        key: ValueKey(_retry),
        stream: DraftService.watchAllDrafts(UserSession.userId),
        builder: (context, snap) {
          // 오류를 **먼저** 본다 — 스트림이 에러로 끝나면 hasData는 영원히
          // false라, 아래 로딩/빈 목록 분기가 이 상태를 대신 삼켜버린다.
          if (snap.hasError) {
            logFirestoreStreamError('DraftsList', snap.error, snap.stackTrace);
            return _ErrorState(onRetry: () => setState(() => _retry++));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _accent),
            );
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
              _retentionBanner(),
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
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
            color: Color(0x0FFF6FA0),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
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
                    ? Image.network(
                        cover,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, e, st) => _coverPlaceholder(),
                      )
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEAF1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          record.type.label,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Flexible이 없으면 유형 배지(예: "파티크루 구인")가 긴
                      // 경우 이 줄이 카드 밖으로 넘쳐 오버플로 줄무늬가 뜬다.
                      // 목록 조회가 늘 실패하고 있어서(위 rules 주석 참고) 카드
                      // 자체가 그려진 적이 없었고, 그래서 지금까지 안 보였다.
                      Flexible(
                        child: Text(
                          _savedAtLabel(record.updatedAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Colors.black45,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 자동삭제까지 남은 기간 — 기준점은 **마지막 저장 시각**이다
                  // (이어서 쓰고 다시 저장하면 기한도 함께 밀린다). 실제로
                  // 지우는 것은 서버의 deleteExpiredDrafts다.
                  ..._autoDeleteLine(record.updatedAt),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _continue(context, record),
              child: const Text(
                '이어서 작성',
                style: TextStyle(color: _accent, fontWeight: FontWeight.w700),
              ),
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
    child: const Center(child: Icon(Icons.edit_note, color: Color(0xFFFFB8CF))),
  );
}

/// 조회 실패 — "0건"과 절대 같은 화면을 쓰지 않는다.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.black26),
          const SizedBox(height: 12),
          const Text(
            '임시저장을 불러오지 못했어요.\n작성 중이던 내용은 그대로 남아 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black45, height: 1.5),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('다시 시도'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF6FA0),
              side: const BorderSide(color: Color(0xFFFFC2D6)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
