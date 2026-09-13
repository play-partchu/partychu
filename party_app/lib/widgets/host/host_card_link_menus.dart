/// 마이 > 파티츄 호스트의 **플레이스 / 공간대여 카드 아래 관리 메뉴 한 줄**.
///
/// 여기 서는 것은 두 칸이다 — `🎉 연결 파티 N개`와 `✨ 연결 이벤트 N개`.
/// 둘 다 "등록물을 통째로 다시 수정하지 않고 부속 화면에서 끝내는" 같은 급의
/// 기능이라 **같은 부품**(HostCardMenuAction)으로 그린다.
///
/// ⚠️ **정본은 하나로 합치지 않는다.** 파티는 파티 문서의 연결 필드
/// (parties.linkedEventId / linkedPlaceId)가 정본이고, 이벤트는 이벤트 문서의
/// 소속 필드(placePromotions.placeId + placeCollection)가 정본이다. 두 관계는
/// 의미부터 다르다 — 파티는 독립 문서를 나중에 **붙였다 뗐다** 하는 것이고,
/// 이벤트는 애초에 그 장소의 것으로 **태어난다**(만든 뒤에는 소속을 바꿀 수
/// 없다 — firestore.rules가 placeId/placeCollection/hostId 변경을 거부한다).
/// 그래서 겉모양만 같은 줄에 세우고, 조회·이동은 각자 기존 정본을 쓴다.
library;

import 'package:flutter/material.dart';

import 'package:party_app/services/place_event_entry.dart';
import 'package:party_app/services/place_promotion_service.dart';

/// 카드 아래 한 줄에 놓이는 관리 메뉴 한 칸 — `🎉 연결 파티 1개`처럼 그린다.
///
/// 아이콘 크기·글자 크기·여백을 **여기 한 곳에서만** 정한다.
class HostCardMenuAction extends StatelessWidget {
  final String emoji;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const HostCardMenuAction({
    super.key,
    required this.emoji,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        foregroundColor: accent,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// `✨ 연결 이벤트 N개` 메뉴에 적을 글자.
///
///  · 아직 못 셌으면 숫자를 비워 둔다 — '확인 중...' 같은 긴 문구를 넣으면 그
///    사이 줄이 밀린다(연결 파티 메뉴와 같은 규칙).
///  · **0개면 개수를 말하지 않는다.** '연결 이벤트 0개'는 없는 것을 굳이
///    세어 보여주는 말이라, 그 자리에는 호스트가 지금 할 수 있는 일
///    ('이벤트 추가')을 적는다 — 플레이스 상세의 호스트 진입점이 쓰는 말과
///    같은 계열이다(PlaceOfferingHostActions의 '✨ 매장 이벤트 추가').
///  · 1개 이상이면 파티와 같은 모양으로 개수를 적는다.
String linkedEventMenuLabel(int? count) => switch (count) {
  null => '연결 이벤트',
  0 => '이벤트 추가',
  _ => '연결 이벤트 $count개',
};

/// `✨ 연결 이벤트 N개` 메뉴 — 개수를 세어 보여주고, 누르면 **기존 이벤트 관리
/// 화면**을 연다. 돌아오면 개수를 다시 센다.
///
/// 개수를 여기서 들고 있는 이유는 연결 파티 메뉴와 같다: 카드 자체는 개수를
/// 쓰지 않는데 그것 때문에 카드가 상태를 갖게 되면, 플레이스·공간대여 두
/// 카드가 똑같은 상태 관리 코드를 각자 갖게 된다.
///
/// ## 새 화면을 만들지 않는다
///
/// 눌렀을 때 열리는 것은 이벤트 등록·관리의 **유일한 문**([PlaceEventEntry])
/// 이 여는 기존 관리 화면이다 — 목록 확인·수정·숨김/종료·삭제·새 이벤트
/// 만들기가 모두 거기 이미 있고, '새 이벤트'는 지금 이 장소가 고정된 채로
/// 열린다([EventPlaceTarget]). 관리 UI를 여기서 복제하지 않는다.
///
/// ## '기존 이벤트 연결'과 '연결 해제'가 없는 이유
///
/// 이벤트는 파티처럼 붙였다 뗐다 하는 독립 문서가 아니다. 소속
/// (`placeId`/`placeCollection`/`hostId`)은 만들 때 정해지고 **그 뒤로 바꿀 수
/// 없다** — firestore.rules가 update에서 세 필드의 변경을 거부한다(자기 uid로
/// 남의 placeId를 가리키는 문서를 만들어 남의 매장 상세에 노출시키는 우회를
/// 막기 위해서다). 그래서 파티 연결 화면의 '기존 파티 추가 연결'·'연결 해제'에
/// 해당하는 동작이 이벤트에는 존재하지 않는다. 겉모양만 복제해 두면 누를 수
/// 없는 버튼이 생긴다.
class LinkedEventMenu extends StatefulWidget {
  const LinkedEventMenu({super.key, required this.target, this.countLoader});

  /// 어느 장소의 이벤트인가 — 이벤트 등록·관리 흐름이 쓰는 정본 값 묶음
  /// (원본 장소 문서에서 읽은 placeId/placeCollection/hostId/이름).
  final EventPlaceTarget target;

  /// 개수를 세는 길 — 운영에서는 항상 null이고
  /// [PlacePromotionService.countForPlace]를 쓴다. 테스트에서만 갈아 끼운다
  /// (이 프로젝트의 Dart 테스트에는 Firestore 페이크가 없다).
  @visibleForTesting
  final Future<int> Function()? countLoader;

  @override
  State<LinkedEventMenu> createState() => _LinkedEventMenuState();
}

class _LinkedEventMenuState extends State<LinkedEventMenu> {
  /// 연결된 이벤트 수 — 아직 못 읽었으면 null.
  int? _count;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loader = widget.countLoader;
      final count = loader != null
          ? await loader()
          : await PlacePromotionService.countForPlace(
              placeId: widget.target.placeId,
              placeCollection: widget.target.placeCollection,
            );
      if (!mounted) return;
      setState(() => _count = count);
    } catch (_) {
      // 개수는 보조 정보라 실패해도 메뉴 자체는 그대로 보여준다
      // (연결 파티 메뉴와 같은 방침).
    }
  }

  Future<void> _open() async {
    // 이벤트 관리로 가는 길은 [PlaceEventEntry] 하나뿐이다 — 등록 화면·
    // 플레이스 상세·여기가 모두 이 함수를 부른다.
    await PlaceEventEntry.openManage(context, widget.target);
    // 관리 화면에서 새로 만들거나 지웠을 수 있다 — 돌아오면 다시 센다.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => HostCardMenuAction(
    emoji: '✨',
    label: linkedEventMenuLabel(_count),
    accent: widget.target.accent,
    onTap: _open,
  );
}
