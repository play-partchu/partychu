import 'package:flutter/material.dart';

import 'package:party_app/screens/place_reservation_manage_screen.dart';
import 'package:party_app/screens/visit_reservation_manage_screen.dart';
import 'package:party_app/services/content_delete_service.dart';
import 'package:party_app/widgets/web_frame.dart';

// ══════════════════════════════════════════════════════════════════════════
// 콘텐츠 삭제 UX — 앱 전체가 공유하는 **유일한** 삭제 화면 흐름.
//
// 삭제 버튼 위치·확인 다이얼로그 문구·취소/삭제 버튼 디자인·완료 후 이동과
// 안내가 전부 여기 한 곳에 있다. 화면은 [ContentDeleteAction.run]을 부르거나
// [DeleteContentButton]/[DeleteContentChip]을 놓기만 한다 — 어느 화면에서
// 지우든 동작이 완전히 같아야 하기 때문이다.
//
// 실제 삭제는 [ContentDeleteService](→ Cloud Functions)가 한다. 이 파일에는
// Firestore 접근이 한 줄도 없다.
// ══════════════════════════════════════════════════════════════════════════

/// 삭제 계열 공통 색 — 버튼·확인창 모두 이 값을 쓴다.
const Color kDeleteColor = Color(0xFFE03B4E);

/// 앱 다이얼로그 제목의 공통 스타일(다른 확인창들과 같은 모양).
const TextStyle _kDialogTitleStyle = TextStyle(
  fontFamily: 'SeoulHangang',
  fontSize: 16,
  fontWeight: FontWeight.w500,
  shadows: [
    Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
    Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
    Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
    Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
  ],
);

/// 한글 받침 유무 — '파티를' / '파티샵을'처럼 조사를 맞추기 위한 것.
bool _hasFinalConsonant(String word) {
  if (word.isEmpty) return false;
  final code = word.codeUnitAt(word.length - 1);
  if (code < 0xAC00 || code > 0xD7A3) return false;
  return (code - 0xAC00) % 28 != 0;
}

String _objectParticle(String word) => _hasFinalConsonant(word) ? '을' : '를';
String _topicParticle(String word) => _hasFinalConsonant(word) ? '은' : '는';
String _subjectParticle(String word) => _hasFinalConsonant(word) ? '이' : '가';

class ContentDeleteAction {
  ContentDeleteAction._();

  /// 삭제 흐름 전체를 실행한다 — 실제로 삭제됐으면 true.
  ///
  /// 1. 여러 일정을 가진 콘텐츠면 "이 일정만 / 전체 일정" 선택 시트
  /// 2. 확인 다이얼로그(취소 / 삭제)
  /// 3. 삭제 진행(진행 중에는 화면을 막는다)
  /// 4. 성공 안내 또는 실패 사유 안내
  ///
  /// 호출한 화면이 상세/수정 화면이라면, true를 받았을 때 그 화면을 pop해
  /// 목록으로 돌아가면 된다(목록은 snapshots() 스트림이라 곧바로 갱신된다).
  ///
  /// 1번 단계가 나타날지는 화면이 아니라
  /// [ContentDeleteService.scheduleCount]가 정한다 — 같은 파티인데 어떤
  /// 화면에서만 선택지가 뜨는 일이 없도록. 화면은 알고 있으면 [seriesId]를
  /// 넘기기만 하면 되고(없으면 문서 id로 조회한다), 장소·파티샵처럼 일정
  /// 분할이 없는 유형은 항상 확인창 하나로 끝난다.
  static Future<bool> run(
    BuildContext context, {
    required DeletableContent type,
    required String id,
    String? seriesId,
    String? scheduleScopeLabel,
    String? contentName,
    WidgetBuilder? blockerScreen,
  }) async {
    var scope = DeleteScope.single;

    final scheduleCount = await ContentDeleteService.scheduleCount(
      type: type,
      id: id,
      seriesId: seriesId,
    );
    if (!context.mounted) return false;

    if (scheduleCount > 1) {
      final picked = await showModalBottomSheet<DeleteScope>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) =>
            _ScopeSheet(type: type, scopeLabel: scheduleScopeLabel ?? '일정'),
      );
      if (picked == null || !context.mounted) return false;
      scope = picked;
    }

    final confirmed = await _confirm(context, type, scope);
    if (confirmed != true || !context.mounted) return false;

    // 진행 중에는 되돌아가기·중복 탭을 막는다 — 삭제는 되돌릴 수 없다.
    // 진행 표시를 닫을 Navigator를 미리 잡아 둔다: await 도중 화면이 사라지면
    // context로는 더 이상 닫을 수 없어 진행 표시가 영영 남는다.
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator(color: kDeleteColor)),
      ),
    );

    try {
      final result = await ContentDeleteService.delete(
        type: type,
        id: id,
        scope: scope,
      );
      rootNavigator.pop(); // 진행 표시 닫기

      final label = type.label;
      final done = result.deletedCount > 1
          ? '$label 일정 ${result.deletedCount}건이 삭제되었습니다.'
          : '$label${_subjectParticle(label)} 삭제되었습니다.';
      // 결제·예약 기록은 법정 보존 대상이라 함께 지워지지 않는다 — "다
      // 지웠는데 왜 내역이 남지?" 하고 놀라지 않도록 함께 알린다.
      final kept = result.preservedCount > 0
          ? ' 결제·예약 내역 ${result.preservedCount}건은 보관됩니다.'
          : '';
      messenger.showSnackBar(
        SnackBar(
          content: Text('$done$kept'),
          duration: Duration(seconds: result.preservedCount > 0 ? 4 : 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return true;
    } on ContentDeleteException catch (e) {
      rootNavigator.pop();
      if (!context.mounted) return false;
      await _showFailure(
        context,
        type,
        e,
        blockerScreen: blockerScreen ??
            _defaultBlockerScreen(
              type: type,
              id: id,
              contentName: contentName,
              blocker: e.blocker,
            ),
      );
      return false;
    }
  }

  /// 삭제를 막고 있는 내역을 볼 수 있는 **기존** 관리 화면. 새 화면을 만들지
  /// 않고 이미 있는 것으로 보낸다 — 보낼 곳이 없으면 null이고, 그러면 버튼도
  /// 뜨지 않는다(엉뚱한 화면으로 보내느니 안 보내는 쪽).
  ///
  /// 파티·파티샵은 목적지 화면이 제목·문서 데이터까지 요구해서 여기서는 만들
  /// 수 없다 — 그 값을 쥐고 있는 화면이 [run]의 `blockerScreen`으로 직접
  /// 넘긴다(party_edit_screen 등).
  static WidgetBuilder? _defaultBlockerScreen({
    required DeletableContent type,
    required String id,
    required String? contentName,
    required DeleteBlockerKind blocker,
  }) {
    final isPlaceLike =
        type == DeletableContent.place || type == DeletableContent.event;
    switch (blocker) {
      case DeleteBlockerKind.placeReservation:
        if (!isPlaceLike) return null;
        return (_) => PlaceReservationManageScreen(
              focusPlaceId: id,
              focusPlaceName: contentName,
            );
      case DeleteBlockerKind.placeVisit:
        if (!isPlaceLike) return null;
        // 방문예약 관리는 아직 장소별로 좁혀 볼 수 없다 — 목록 전체로 보낸다.
        return (_) => const VisitReservationManageScreen();
      case DeleteBlockerKind.placeProductOrder:
      case DeleteBlockerKind.partyApplication:
      case DeleteBlockerKind.shopOrder:
      case DeleteBlockerKind.unknown:
        return null;
    }
  }

  static Future<bool?> _confirm(
    BuildContext context,
    DeletableContent type,
    DeleteScope scope,
  ) {
    final label = type.label;
    final object = _objectParticle(label);
    final topic = _topicParticle(label);
    final body = scope == DeleteScope.series
        ? '이 $label의 전체 일정을 삭제하시겠습니까? 삭제한 $label$topic 복구할 수 없습니다.'
        : '이 $label$object 삭제하시겠습니까? 삭제한 $label$topic 복구할 수 없습니다.';

    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$label 삭제', style: _kDialogTitleStyle),
        content: Text(body, style: const TextStyle(fontSize: 14, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Colors.black54),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: kDeleteColor),
            child: const Text(
              '삭제',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// 실패는 스낵바 대신 확인창으로 보여준다 — "결제한 신청자가 남아 있어
  /// 삭제할 수 없습니다" 같은 안내는 읽고 나서 조치해야 하는 내용이라
  /// 2초 뒤 사라지면 안 된다.
  static Future<void> _showFailure(
    BuildContext context,
    DeletableContent type,
    ContentDeleteException e, {
    WidgetBuilder? blockerScreen,
  }) {
    // 원인을 볼 곳이 있을 때만 바로가기를 준다 — "먼저 정리하라"고만 하고
    // 어디 있는지 안 알려주면 사용자는 목록을 뒤지는 수밖에 없다.
    final showsShortcut = e.blockedByLinkedData && blockerScreen != null;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          e.blockedByLinkedData ? '아직 삭제할 수 없어요' : '${type.label} 삭제 실패',
          style: _kDialogTitleStyle,
        ),
        content: Text(
          e.message,
          style: const TextStyle(fontSize: 14, height: 1.45),
        ),
        actions: [
          if (showsShortcut)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                // 웹에서도 다른 화면들과 같은 틀 안에서 열리도록 앱 공통
                // 라우트를 쓴다.
                Navigator.of(context).push(webFramedRoute<void>(blockerScreen));
              },
              style: TextButton.styleFrom(
                foregroundColor: kDeleteColor,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('신청/예약 내역 보기'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}

/// "이 일정만 / 전체 일정" 선택 시트.
class _ScopeSheet extends StatelessWidget {
  final DeletableContent type;
  final String scopeLabel;

  const _ScopeSheet({required this.type, required this.scopeLabel});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE3E3E8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
            child: Text(
              '${type.label} 삭제',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '이 ${type.label}는 $scopeLabel이 여러 건입니다. 무엇을 삭제할지 골라주세요.',
              style: const TextStyle(fontSize: 12.5, color: Colors.black45),
            ),
          ),
          _ScopeTile(
            icon: Icons.event_busy_rounded,
            title: '이 $scopeLabel만 삭제',
            subtitle: '지금 보고 있는 $scopeLabel 하나만 지웁니다.',
            onTap: () => Navigator.pop(context, DeleteScope.single),
          ),
          _ScopeTile(
            icon: Icons.delete_sweep_rounded,
            title: '이 ${type.label}의 전체 $scopeLabel 삭제',
            subtitle: '함께 등록된 $scopeLabel을 모두 지웁니다.',
            onTap: () => Navigator.pop(context, DeleteScope.series),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ScopeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ScopeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 22, color: kDeleteColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Colors.black26),
          ],
        ),
      ),
    );
  }
}

/// 등록·수정 화면 **하단**에 놓는 삭제 버튼.
///
/// 삭제에 성공하면 기본적으로 그 화면을 pop해 목록으로 돌려보낸다
/// ([popOnDeleted]가 false면 [onDeleted]만 부른다).
class DeleteContentButton extends StatelessWidget {
  final DeletableContent type;
  final String id;

  /// 파티처럼 여러 문서로 나뉠 수 있는 콘텐츠의 시리즈 id — 알고 있으면
  /// 넘긴다(없으면 문서 id로 조회한다). 여러 건이면 범위 선택 시트가 먼저
  /// 뜬다.
  final String? seriesId;

  /// 삭제 성공 후 이 화면을 닫을지.
  final bool popOnDeleted;

  /// 삭제 성공 시 추가로 할 일(목록 갱신 신호 등).
  final VoidCallback? onDeleted;

  /// 예약/신청 때문에 삭제가 막혔을 때 안내창에 뜨는 바로가기용 — 지금 이
  /// 콘텐츠의 이름과, 목적지 화면(기본 경로로 못 정하는 파티·파티샵만).
  final String? contentName;
  final WidgetBuilder? blockerScreen;

  const DeleteContentButton({
    super.key,
    required this.type,
    required this.id,
    this.seriesId,
    this.popOnDeleted = true,
    this.onDeleted,
    this.contentName,
    this.blockerScreen,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () async {
            final deleted = await ContentDeleteAction.run(
              context,
              type: type,
              id: id,
              seriesId: seriesId,
              contentName: contentName,
              blockerScreen: blockerScreen,
            );
            if (!deleted) return;
            onDeleted?.call();
            if (popOnDeleted && context.mounted)
              Navigator.of(context).pop(true);
          },
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: Text('${type.label} 삭제'),
          style: OutlinedButton.styleFrom(
            foregroundColor: kDeleteColor,
            side: const BorderSide(color: Color(0xFFF3C2C8)),
            backgroundColor: const Color(0xFFFFF5F6),
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}

/// 목록 카드의 관리 버튼 줄에 놓는 아이콘형 삭제 버튼 — 흐름·문구·권한
/// 검사는 [DeleteContentButton]과 완전히 같고, 카드 한 줄에 들어가도록
/// 모양만 다르다.
class DeleteContentIconButton extends StatelessWidget {
  final DeletableContent type;
  final String id;
  final String? seriesId;
  final VoidCallback? onDeleted;
  final String? contentName;
  final WidgetBuilder? blockerScreen;

  const DeleteContentIconButton({
    super.key,
    required this.type,
    required this.id,
    this.seriesId,
    this.onDeleted,
    this.contentName,
    this.blockerScreen,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '${type.label} 삭제',
      // 목록 카드의 좁은 한 줄에 들어가야 해서 기본 48dp 히트박스를 줄인다.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      visualDensity: VisualDensity.compact,
      icon: const Icon(
        Icons.delete_outline_rounded,
        size: 21,
        color: kDeleteColor,
      ),
      onPressed: () async {
        final deleted = await ContentDeleteAction.run(
          context,
          type: type,
          id: id,
          seriesId: seriesId,
          contentName: contentName,
          blockerScreen: blockerScreen,
        );
        if (deleted) onDeleted?.call();
      },
    );
  }
}
