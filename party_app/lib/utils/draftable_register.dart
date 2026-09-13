import 'package:flutter/material.dart';

import 'package:party_app/models/draft_type.dart';
import 'package:party_app/services/draft_service.dart';

/// 등록 화면에 자동 임시저장(Draft)을 붙이는 공통 State 믹스인.
///
/// 파티 등록(party_register_screen.dart)이 인라인으로 갖고 있는 것과 동일한
/// 동작 — 1초 debounce 자동저장, 앱 백그라운드/종료·뒤로가기 시 즉시 저장,
/// 재진입 복구 팝업(이어서/새로/취소), 임시저장 버튼, "자동 저장됨 · HH:mm"
/// 표시, 미디어 재선택 배너 — 을 여러 등록 화면이 재사용할 수 있게 뽑아낸
/// 것이다. 파티 등록은 이미 잘 동작하므로 건드리지 않고, 나머지 등록 화면
/// (장소·파티샵·파티크루·이벤트)이 이 믹스인을 쓴다.
///
/// 사용하는 화면은:
///  1. `class _XState extends State<X> with WidgetsBindingObserver, DraftableRegister<X>`
///  2. `initState`에서 `initDraft()`, `dispose`에서 `disposeDraft()` 호출
///  3. `setState`를 오버라이드해 `markDraftDirty()` 호출(텍스트 입력은
///     컨트롤러 리스너로 별도로 `markDraftDirty` 연결)
///  4. 아래 6개 추상 멤버 구현
///  5. build를 `PopScope(canPop: !draftDirty, onPopInvokedWithResult: ...)`로
///     감싸고, AppBar에 `draftSaveAction()`/`buildAutoSaveIndicator()`,
///     본문 상단에 `if (draftMediaNeedsReselect) buildMediaReselectBanner()`
///  6. 최종 등록 성공 시 `deleteCurrentDraft()` 호출
mixin DraftableRegister<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  // ── 화면이 구현해야 하는 계약 ──────────────────────────────────────
  DraftType get draftType;

  /// 화면 전체 작성 상태를 순수 JSON 맵으로 직렬화.
  Map<String, dynamic> buildDraftPayload();

  /// payload로 화면 상태를 복원. 로컬 파일이 사라진 미디어가 있으면
  /// `draftMediaNeedsReselect = true`로 세팅한다.
  void applyDraftPayload(Map<String, dynamic> payload);

  /// 목록 표시용 제목(없으면 '제목 없음'으로 대체됨).
  String get draftTitle;

  /// 목록 표시용 대표 이미지 URL(없으면 null).
  String? get draftCoverImageUrl;

  /// 마이페이지 "이어서 작성"으로 열렸는지 — true면 복구 여부를 묻지 않고
  /// 곧바로 불러온다. 화면은 보통 `widget.autoRestoreDraft`를 반환한다.
  bool get draftAutoRestore;

  /// 진입할 때 "작성 중인 내용이 있습니다" 복구 팝업을 띄울지.
  ///
  /// 기본값 true — 대부분의 등록 화면은 예전 그대로 동작한다. 통합
  /// 플레이스+파티 등록처럼 **한 화면 안에서 유형을 바꿔** 본문이 새로
  /// 마운트되는 경우에만 false로 내려서, 방금 입력하던 공통 정보를 예전
  /// 임시저장이 덮어쓰지 않게 한다([draftAutoRestore]가 true면 그쪽이 우선).
  bool get draftOfferRestore => true;

  // ── 믹스인 내부 상태 ───────────────────────────────────────────────
  DraftAutosaver? _autosaver;
  bool _draftReady = false;
  bool _draftDirty = false;

  /// 복구 시 로컬 파일이 사라져 다시 선택해야 하는 미디어가 있으면 true.
  bool draftMediaNeedsReselect = false;

  bool get draftDirty => _draftDirty;

  /// 뭔가 하나라도 바뀌었음을 표시하고 자동저장을 예약한다. 화면의 setState
  /// 오버라이드와 컨트롤러 리스너에서 호출한다.
  void markDraftDirty() {
    _draftDirty = true;
    _scheduleAutosave();
  }

  void _scheduleAutosave() {
    if (!_draftReady) return;
    _autosaver?.schedule(_snapshot);
  }

  DraftSnapshot _snapshot() => DraftSnapshot(
    title: draftTitle.trim(),
    coverImageUrl: draftCoverImageUrl,
    payload: buildDraftPayload(),
  );

  // ── 수명주기 훅 ────────────────────────────────────────────────────
  /// initState에서 호출.
  void initDraft() {
    _autosaver = DraftAutosaver(type: draftType);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferRestore());
  }

  /// dispose에서 호출.
  void disposeDraft() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaver?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_draftReady) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _autosaver?.flushNow(_snapshot);
    }
  }

  // ── 복구 ───────────────────────────────────────────────────────────
  Future<void> _maybeOfferRestore() async {
    final has = await DraftService.hasDraft(draftType);
    if (!mounted) {
      _draftReady = true;
      return;
    }
    if (!has) {
      _draftReady = true;
      return;
    }

    // 마이페이지 목록에서 "이어서 작성"으로 들어온 경우 — 다시 묻지 않는다.
    if (draftAutoRestore) {
      await _restoreNow();
      _draftReady = true;
      return;
    }

    // 화면 안에서 유형만 바꿔 다시 마운트된 경우 — 지금 입력 중인 내용을
    // 예전 임시저장이 덮어쓰면 안 되므로 묻지 않고 그냥 둔다.
    if (!draftOfferRestore) {
      _draftReady = true;
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('작성 중인 내용이 있습니다', style: _dialogTitleStyle),
        content: const Text('이어서 작성하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'new'),
            child: const Text('새로 작성'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'continue'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6FA0),
              foregroundColor: Colors.white,
            ),
            child: const Text('이어서 작성'),
          ),
        ],
      ),
    );
    if (!mounted) {
      _draftReady = true;
      return;
    }

    if (choice == 'continue') {
      await _restoreNow();
    } else if (choice == 'new') {
      final confirmNew = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          content: const Text('저장된 임시저장 내용을 지우고 새로 작성할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('삭제하고 새로 작성'),
            ),
          ],
        ),
      );
      if (confirmNew == true) {
        await DraftService.deleteDraft(draftType);
      }
    } else {
      if (mounted) Navigator.of(context).maybePop();
    }
    _draftReady = true;
  }

  Future<void> _restoreNow() async {
    final record = await DraftService.loadDraft(draftType);
    if (!mounted || record == null) return;
    setState(() => applyDraftPayload(record.payload));
    if (draftMediaNeedsReselect) {
      _showSnack('임시저장된 사진 / 동영상 일부는 다시 선택해주세요.');
    }
  }

  // ── 저장/버튼/표시 ─────────────────────────────────────────────────
  /// AppBar용 '임시저장' 액션 버튼.
  Widget draftSaveAction() {
    return TextButton(
      onPressed: () async {
        await _autosaver?.flushNow(_snapshot);
        if (mounted) _showSnack('임시저장되었습니다');
      },
      child: const Text(
        '임시저장',
        style: TextStyle(color: Color(0xFFFF6FA0), fontWeight: FontWeight.w700),
      ),
    );
  }

  /// AppBar 하단의 "자동 저장됨 · HH:mm" 표시.
  PreferredSizeWidget? buildAutoSaveIndicator() {
    final saver = _autosaver;
    if (saver == null) return null;
    return PreferredSize(
      preferredSize: const Size.fromHeight(22),
      child: ValueListenableBuilder<DateTime?>(
        valueListenable: saver.lastSavedAt,
        builder: (context, savedAt, _) {
          if (savedAt == null) return const SizedBox(height: 22);
          final synced = saver.lastSaveSynced.value;
          final hh = savedAt.hour.toString().padLeft(2, '0');
          final mm = savedAt.minute.toString().padLeft(2, '0');
          return SizedBox(
            height: 22,
            child: Center(
              child: Text(
                synced ? '자동 저장됨 · $hh:$mm' : '기기에 보관됨 · $hh:$mm',
                style: TextStyle(
                  fontSize: 11,
                  color: synced ? Colors.black45 : const Color(0xFFC26A00),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 복구 시 로컬 파일이 사라진 사진/동영상 안내 배너.
  Widget buildMediaReselectBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD8A8)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFFC26A00)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '임시저장된 사진 / 동영상 일부는 다시 선택해주세요.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF8A5A00)),
            ),
          ),
        ],
      ),
    );
  }

  /// 뒤로가기 시 — 내용을 버리지 않고 먼저 저장한 뒤 나가기/계속을 묻는다.
  Future<bool> confirmLeaveWithDraftSave() async {
    if (!_draftDirty) return true;
    await _autosaver?.flushNow(_snapshot);
    if (!mounted) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('작성 중인 내용이 임시저장되었습니다', style: _dialogTitleStyle),
        content: const Text('나중에 이어서 작성할 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 작성'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  /// 지금 상태를 즉시 임시저장한다(debounce를 기다리지 않음).
  ///
  /// 통합 등록 화면에서 유형을 바꾸기 직전에 호출한다 — 화면에서 사라지는
  /// 유형 전용 입력값이 그 유형의 임시저장에는 남아 있게 한다.
  Future<void> saveDraftNow() async {
    await _autosaver?.flushNow(_snapshot);
  }

  /// 최종 등록 성공 시 이 유형의 임시저장을 삭제한다.
  Future<void> deleteCurrentDraft() async {
    _draftDirty = false;
    await DraftService.deleteDraft(draftType);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  static const TextStyle _dialogTitleStyle = TextStyle(
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

  // ── 시간 직렬화 헬퍼(화면들이 공유) ─────────────────────────────────
  static Map<String, int>? timeToMap(TimeOfDay? t) =>
      t == null ? null : {'h': t.hour, 'm': t.minute};

  static TimeOfDay? timeFromMap(Object? raw) {
    if (raw is Map) {
      final h = (raw['h'] as num?)?.toInt();
      final m = (raw['m'] as num?)?.toInt();
      if (h != null && m != null) return TimeOfDay(hour: h, minute: m);
    }
    return null;
  }
}
