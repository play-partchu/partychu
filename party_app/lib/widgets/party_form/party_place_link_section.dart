import 'package:flutter/material.dart';

import 'package:party_app/screens/place_party_link_screen.dart'
    show pickMyPlace;
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/widgets/party_form/section_summary_row.dart';

/// 파티 ↔ 플레이스 연결 선택 UI — **파티 등록/재등록 화면 공용**.
///
/// ## 이 위젯이 쓰기를 하지 않는 이유
///
/// 연결은 파티 문서와 플레이스 문서를 **함께** 갱신한다
/// ([PlacePartyLink.linkParties]). 그런데 등록·재등록 화면에서는 사용자가
/// 플레이스를 고르는 시점에 파티 문서가 아직 없다 — 그래서 여기서 바로 쓰면
/// "연결됐다고 주장하지만 파티 문서는 없는" 반쪽 상태가 만들어진다.
///
/// 그래서 이 위젯은 **고른 결과만 부모에게 알려주고**([onChanged]), 실제 연결은
/// 파티 문서가 만들어진 뒤 부모가 저장 마무리 단계에서 한 번에 커밋한다.
/// 날짜를 여러 개 골랐으면 그때 만들어진 날짜 문서 전부가 함께 연결된다.
///
/// 반대로 파티 **수정** 화면은 이미 문서가 있으므로 고른 즉시 커밋한다 — 그쪽은
/// 재연결·스냅샷 새로고침·신청자 경고까지 필요해서 자체 흐름을 그대로 둔다.
/// 두 화면이 공유하는 것은 플레이스를 고르는 시트([pickMyPlace])와 연결 규칙을
/// 담은 서비스([PlacePartyLink])다.
///
/// 연결 대상이 진입 시점에 이미 정해진 경우(파티 연결 관리 → 새 파티 만들기)는
/// [PartyPlaceLinkSection.locked]로 같은 자리에 "어디에 붙는지"만 보여준다.
class PartyPlaceLinkSection extends StatelessWidget {
  /// 필수값 검증이 이 줄로 스크롤할 때 쓰는 앵커.
  final GlobalKey? rowKey;

  /// 지금 연결하기로 선택된 공간의 문서 id. null이면 미연결.
  final String? linkedEventId;

  /// 그 문서가 플레이스(events)인지 공간대여(places)인지 — 문구를 가르는 데
  /// 쓴다. 화면이 이름 문자열을 비교하지 않도록 종류를 값으로 받는다.
  final PartyLinkTarget linkedTarget;

  /// 연결된 플레이스 문서 — 이름을 보여주는 데 쓴다. 재등록 진입 직후처럼
  /// 아직 읽어오는 중이면 null일 수 있다.
  final Map<String, dynamic>? linkedPlaceData;

  /// 재등록 진입 시 원본의 연결 정보를 불러오는 중인지.
  final bool loading;

  /// 선택이 바뀌었을 때 — 공간을 골랐으면 그 값, 연결을 해제했으면 null.
  final ValueChanged<PartyPrelinkTarget?> onChanged;

  /// 대상이 이미 정해져 바꿀 수 없는 줄일 때의 종류 이름('플레이스'/'공간대여').
  /// null이면 평소처럼 고를 수 있는 줄이다.
  final String? lockedTargetNoun;

  /// 잠긴 줄에 보여줄 대상 이름.
  final String? lockedTargetName;

  const PartyPlaceLinkSection({
    super.key,
    required this.linkedEventId,
    required this.linkedPlaceData,
    required this.onChanged,
    this.linkedTarget = PartyLinkTarget.place,
    this.rowKey,
    this.loading = false,
  }) : lockedTargetNoun = null,
       lockedTargetName = null;

  /// **연결 대상이 이미 정해진 등록**용 — "파티 연결 관리 → 새 파티 만들기".
  ///
  /// 고르는 시트를 열지 않고 어디에 붙는지만 알린다. 여기서 대상을 바꿀 수
  /// 있게 하면 돌아갈 화면(그 플레이스/공간대여의 연결 목록)과 어긋난다 —
  /// 바꾸고 싶으면 등록을 취소하고 원하는 대상에서 다시 시작하면 된다.
  const PartyPlaceLinkSection.locked({
    super.key,
    required String targetNoun,
    required String targetName,
    this.rowKey,
  }) : lockedTargetNoun = targetNoun,
       lockedTargetName = targetName,
       linkedEventId = null,
       linkedPlaceData = null,
       linkedTarget = PartyLinkTarget.place,
       loading = false,
       onChanged = _ignoreChange;

  /// 잠긴 줄에서는 선택 자체가 없어 호출될 일이 없다(생성자 기본값용).
  static void _ignoreChange(PartyPrelinkTarget? _) {}

  bool get _locked => lockedTargetNoun != null;

  bool get _linked => linkedEventId != null;

  String _summary() {
    if (_locked) return '$lockedTargetName — 등록하면 자동으로 연결돼요';
    if (loading) return '연결 정보를 불러오는 중...';
    if (!_linked) return '연결 안 함 (직접 입력한 장소 사용)';
    final kind = linkedTarget.listingKind;
    final name = (linkedPlaceData?['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return '연결된 ${linkedTarget.noun}';
    return '${kind.emoji} ${kind.label} · $name';
  }

  @override
  Widget build(BuildContext context) {
    return SectionSummaryRow(
      rowKey: rowKey,
      title: _locked
          ? '$lockedTargetNoun 연결'
          : (_linked ? '연결된 ${linkedTarget.noun}' : '내 공간 연결 (선택)'),
      summary: _summary(),
      // 불러오는 중에는 눌러도 아무 일도 하지 않는다 — 아직 원본의 연결 정보를
      // 모르는 상태에서 시트를 열면 "연결 안 함"으로 잘못 보인다.
      onTap: () {
        if (loading) return;
        if (_locked) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('이 화면에서 등록하는 파티는 $lockedTargetName에 자동으로 연결돼요.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        _openSheet(context);
      },
    );
  }

  Future<void> _openSheet(BuildContext context) =>
      showPartySpaceLinkSheet(
        context,
        linkedEventId: linkedEventId,
        onChanged: onChanged,
      );
}

/// 연결 대상을 고르거나 해제하는 시트 — **등록 폼의 두 곳이 함께 쓴다**
/// (맨 위 [LinkedSpaceBanner]의 "변경", 장소 아래 [PartyPlaceLinkSection] 줄).
/// 두 자리가 각자 시트를 그리면 한쪽만 고쳐졌을 때 같은 동작이 갈린다.
///
/// [linkedEventId]가 null이 아니면 "다른 공간으로 변경 / 연결 해제"를, null이면
/// "내 공간에서 선택"만 보여준다.
Future<void> showPartySpaceLinkSheet(
  BuildContext context, {
  required String? linkedEventId,
  required ValueChanged<PartyPrelinkTarget?> onChanged,
}) async {
  final linked = linkedEventId != null;
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '내 공간 연결',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.storefront_outlined,
              color: Color(0xFFFF6FA0),
            ),
            title: Text(linked ? '다른 공간으로 변경' : '내 공간에서 선택'),
            subtitle: const Text('등록한 플레이스·공간대여와 연결하고 장소 정보를 가져와요'),
            onTap: () => Navigator.pop(ctx, 'pick'),
          ),
          if (linked)
            ListTile(
              leading: const Icon(Icons.link_off, color: Color(0xFFB00020)),
              title: const Text('연결 해제'),
              subtitle: const Text('장소는 직접 입력한 값으로 두고 연결만 뺍니다'),
              onTap: () => Navigator.pop(ctx, 'unlink'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'pick':
      // 등록 폼은 두 종류를 모두 다룬다 — 저장 뒤 커밋하는
      // [PlacePartyLink.linkParties]가 `target`만 갈아 끼우면 되기 때문이다.
      final picked = await pickMyPlace(
        context,
        excludeEventId: linkedEventId,
        targets: PartyLinkTarget.values.toSet(),
      );
      if (picked != null) onChanged(picked);
    case 'unlink':
      onChanged(null);
  }
}

/// 등록 폼 **맨 위**에 붙는 "지금 이 파티가 어디에 연결되는지" 한 줄.
///
/// 연결이 있을 때만 보인다 — 공간을 하나도 안 가진 호스트의 등록 화면은
/// 지금까지와 픽셀 하나 다르지 않다. 장소 아래의 [PartyPlaceLinkSection] 줄과
/// 중복처럼 보이지만 역할이 다르다: 그쪽은 "장소를 어디서 가져왔는지"를
/// 장소 항목 옆에서 설명하고, 이쪽은 폼을 다 채우기 전에도 연결 대상이
/// 눈에 남아 있게 한다. 누르는 시트는 [showPartySpaceLinkSheet] 하나다.
class LinkedSpaceBanner extends StatelessWidget {
  final PartyLinkTarget target;
  final String name;

  /// "변경"을 눌렀을 때 — 호출부가 [showPartySpaceLinkSheet]로 잇는다.
  final VoidCallback onChange;

  const LinkedSpaceBanner({
    super.key,
    required this.target,
    required this.name,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final kind = target.listingKind;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: kind.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kind.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Text(kind.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '연결된 ${target.noun}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: kind.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(
              foregroundColor: kind.color,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
            ),
            child: const Text(
              '변경',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
