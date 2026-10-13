import 'package:flutter/material.dart';

import 'package:party_app/models/mobile_place_schedule.dart';
import 'package:party_app/models/place_weekly_hours.dart' show PlaceWeeklyHours;

/// 🗓 **예외 일정 편집기** — 특정 날짜만 **다른 한 곳**에서 영업하거나 쉰다.
///
/// 정기 일정(요일 칸)과 눈에 보이게 갈라 둔다. 여기서 만든 것은 날짜 하나에만
/// 걸리고, 지우면 그 날짜가 곧바로 정기 일정으로 돌아간다.
///
/// ── 한 날에 한 곳 ───────────────────────────────────────────────────────
/// 날짜당 예외는 하나이고 그 안의 장소도 **하나**다
/// ([ScheduleException.slot]). 그래서 모드가 둘뿐이다:
///
///     하루 대체 — 이 날은 다른 곳에서
///     휴무     — 이 날은 쉬어요
///
/// "정기에 더한다"(옛 `addSlot`)는 뜻이 설 자리가 없다 — 그 날의 장소가
/// 하나이므로 더하는 것과 바꾸는 것이 같은 결과다.
///
/// ── 판정은 하지 않는다 ────────────────────────────────────────────────
/// 우선순위·자정 넘김·요일 계산은 전부 모델이 한다. 이 파일에는 시간 계산이
/// 없고, 모델이 내놓은 값을 **설명**만 한다.
class MobileExceptionEditor extends StatelessWidget {
  const MobileExceptionEditor({
    super.key,
    required this.schedule,
    required this.onChanged,
    required this.onPickStop,
    required this.onPickTime,
    this.today,
  });

  final MobilePlaceSchedule schedule;
  final ValueChanged<MobilePlaceSchedule> onChanged;

  /// 장소 선택 — 기존 주소 검색 화면을 쓰는 호출부가 넘긴다.
  ///
  /// ⚠️ 지도 핀 직접 지정은 **아직 없다.** 좌표는 주소 검색 결과에서 온다.
  ///    나중에 핀 조정을 붙일 때 바뀌는 곳은 이 콜백의 구현 하나이고,
  ///    [ScheduledStop]이 이미 좌표를 들고 있으므로 자료구조는 그대로 쓴다.
  final Future<ScheduledStop?> Function({ScheduledStop? initial}) onPickStop;

  /// 시간 선택 — 호출부가 기존 휠 시간 선택기를 띄운다. `'HH:mm'`을 돌려준다.
  final Future<String?> Function({
    required String initial,
    required String title,
  })
  onPickTime;

  /// 오늘 — 테스트에서 고정할 수 있게 열어 둔다(비우면 [DateTime.now]).
  final DateTime? today;

  static const _accent = Color(0xFFFF6FA0);
  static const _softPink = Color(0xFFFFF4F8);
  static const _border = Color(0xFFE8EBF2);

  static const String defaultStart = '11:00';
  static const String defaultEnd = '20:00';

  /// 키 — 날짜마다 같은 글자가 붙으므로 테스트가 집을 수 있게 둔다.
  static Key todayButtonKey() => const Key('mobileTodayHereButton');
  static Key addExceptionKey() => const Key('mobileAddException');
  static Key modeKey(String dateKey, ScheduleExceptionMode mode) =>
      Key('mobileExceptionMode-$dateKey-${mode.name}');
  static Key removeExceptionKey(String dateKey) =>
      Key('mobileRemoveException-$dateKey');

  DateTime get _today {
    final base = today ?? DateTime.now();
    return DateTime(base.year, base.month, base.day);
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = schedule.upcomingExceptions(_today);
    final pastCount = schedule.pastExceptionCount(_today);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '예외 일정',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _softPink,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '정기보다 우선',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '특정 날짜만 다른 곳에서 영업하거나 쉴 수 있어요. 정기 일정은 그대로 남고, 예외를 지우면 바로 돌아와요.',
          style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.45),
        ),
        const SizedBox(height: 12),
        _todayHereButton(context),
        const SizedBox(height: 10),
        for (final e in upcoming) ...[
          _exceptionCard(context, e),
          const SizedBox(height: 8),
        ],
        _addExceptionButton(context),
        if (pastCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '지난 예외 $pastCount건은 목록에서만 숨겼어요(기록은 남아 있어요).',
            style: const TextStyle(fontSize: 10, color: Colors.black38),
          ),
        ],
      ],
    );
  }

  // ── 오늘 여기서 영업해요! ────────────────────────────────────────────

  Widget _todayHereButton(BuildContext context) {
    final todayException = schedule.exceptionFor(_today);
    final active =
        todayException != null &&
        todayException.mode == ScheduleExceptionMode.replaceDay &&
        todayException.slot != null;

    return GestureDetector(
      key: todayButtonKey(),
      onTap: () => _setTodayHere(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: active ? _accent : _softPink,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accent),
        ),
        child: Row(
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 18,
              color: active ? Colors.white : _accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '오늘 여기서 영업해요!',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : _accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    active
                        ? '오늘은 ${todayException.slot!.stop.displayName}에서 영업해요'
                        : '오늘 하루만 장소를 바꿔요. 다음 주 정기 일정은 그대로예요.',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.35,
                      color: active ? Colors.white70 : Colors.black54,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 오늘 날짜 하나에만 걸리는 대체 일정을 세운다.
  ///
  /// 모델의 [MobilePlaceSchedule.withTodayStop]이 **날짜 기준으로 갈아 끼우므로**
  /// 몇 번 눌러도 예외가 쌓이지 않고, 날짜가 박혀 있으므로 내일에는 영향이 없다.
  Future<void> _setTodayHere(BuildContext context) async {
    final stop = await onPickStop();
    if (stop == null) return;
    final start = await onPickTime(initial: defaultStart, title: '오늘 영업 시작 시간');
    final end = await onPickTime(
      initial: start ?? defaultEnd,
      title: '오늘 영업 종료 시간',
    );
    onChanged(
      schedule.withTodayStop(
        _today,
        stop: stop,
        startTime: start ?? defaultStart,
        endTime: end ?? defaultEnd,
      ),
    );
  }

  // ── 예외 카드 ────────────────────────────────────────────────────────

  Widget _exceptionCard(BuildContext context, ScheduleException e) {
    final date = e.date;
    final closed = e.mode == ScheduleExceptionMode.closed;
    final slot = e.slot;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_outlined, size: 16, color: _accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  date == null ? e.dateKey : _formatDate(date),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                key: removeExceptionKey(e.dateKey),
                onPressed: () => _removeException(e),
                icon: const Icon(Icons.close, size: 16),
                color: Colors.black38,
                visualDensity: VisualDensity.compact,
                tooltip: '예외 삭제',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final mode in ScheduleExceptionMode.values)
                _modeChip(e, mode),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _modeDescription(e.mode),
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              color: Colors.black54,
            ),
          ),
          if (_conflictNotice(e) case final notice?) ...[
            const SizedBox(height: 8),
            _notice(notice),
          ],
          if (!closed) ...[
            const SizedBox(height: 8),
            if (slot == null)
              _pickStopButton(context, e)
            else
              _slotRow(context, e, slot),
          ],
        ],
      ),
    );
  }

  Widget _modeChip(ScheduleException e, ScheduleExceptionMode mode) {
    final selected = e.mode == mode;
    return GestureDetector(
      key: modeKey(e.dateKey, mode),
      onTap: selected ? null : () => _setMode(e, mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _accent : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? _accent : _border),
        ),
        child: Text(
          modeLabel(mode),
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }

  static String modeLabel(ScheduleExceptionMode mode) => switch (mode) {
    ScheduleExceptionMode.replaceDay => '하루 대체',
    ScheduleExceptionMode.closed => '휴무',
  };

  static String _modeDescription(ScheduleExceptionMode mode) => switch (mode) {
    ScheduleExceptionMode.replaceDay => '이 날은 정기 장소 대신 아래 한 곳에서 영업해요.',
    ScheduleExceptionMode.closed => '이 날은 쉬어요. 정기 일정도 적용되지 않아요.',
  };

  /// 휴무와 장소 변경이 부딪히지 않도록 **설명**한다 — 막지 않는다.
  ///
  /// 판정은 모델이 이미 정해 두었다(`closed`가 `replaceDay`를 이긴다).
  /// 사용자가 그 결과를 모르는 것이 문제라서 글로만 알린다.
  String? _conflictNotice(ScheduleException e) {
    final date = e.date;
    if (date == null) return '날짜 형식이 올바르지 않아 이 예외는 적용되지 않아요.';

    switch (e.mode) {
      case ScheduleExceptionMode.closed:
        if (e.slot != null) {
          return '휴무로 두는 동안 아래 장소는 적용되지 않아요. 지우지는 않았으니 모드를 바꾸면 돌아와요.';
        }
        return null;
      case ScheduleExceptionMode.replaceDay:
        final weekdayClosed = schedule.closedWeekdays.contains(date.weekday);
        final hasRegular = schedule.regular.containsKey(date.weekday);
        if (!hasRegular || weekdayClosed) {
          return '이 요일에는 정기 장소가 없어요. 대체가 아니라 이 날만 새로 영업하는 것과 같아요.';
        }
        return null;
    }
  }

  Widget _slotRow(BuildContext context, ScheduleException e, ScheduleSlot slot) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _editSlotStop(context, e, slot),
                  child: Text(
                    slot.stop.displayName.isEmpty
                        ? '장소를 선택해주세요'
                        : slot.stop.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: slot.stop.hasCoordinates
                          ? Colors.black87
                          : Colors.black38,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _editSlotStop(context, e, slot),
                child: const Text(
                  '장소 변경',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _timeChip(context, e, slot, isStart: true, label: slot.startTime),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5),
                child: Text('~', style: TextStyle(color: Colors.black38)),
              ),
              _timeChip(context, e, slot, isStart: false, label: slot.endTime),
              if (_crossesMidnight(slot)) ...[
                const SizedBox(width: 6),
                const Text(
                  '익일',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 자정 넘김 판정은 모델의 구간 정본이 한다(여기서 계산하지 않는다).
  static bool _crossesMidnight(ScheduleSlot slot) {
    final interval = slot.interval;
    return interval != null && interval.to > 24 * 60;
  }

  Widget _timeChip(
    BuildContext context,
    ScheduleException e,
    ScheduleSlot slot, {
    required bool isStart,
    required String label,
  }) => GestureDetector(
    onTap: () => _editSlotTime(context, e, slot, isStart: isStart),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
  );

  Widget _pickStopButton(BuildContext context, ScheduleException e) =>
      GestureDetector(
        onTap: () => _editSlotStop(context, e, null),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: const Text(
            '이 날 영업할 장소 선택',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
        ),
      );

  Widget _addExceptionButton(BuildContext context) => GestureDetector(
    key: addExceptionKey(),
    onTap: () => _addException(context),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: const Text(
        '+ 예외 날짜 추가',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black54,
        ),
      ),
    ),
  );

  Widget _notice(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E6),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xFFFFE0A3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 14, color: Color(0xFFB07D18)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 10,
              height: 1.45,
              color: Color(0xFF8A6100),
            ),
          ),
        ),
      ],
    ),
  );

  // ── 편집 동작 ────────────────────────────────────────────────────────

  /// 날짜 선택 → 장소 선택 → 시간 선택.
  ///
  /// 앱의 다른 화면과 같은 [showDatePicker]를 쓴다(main.dart가 한국어로
  /// 맞춰 두었다). 과거 날짜는 고를 수 없다 — 지난 날짜에 예외를 넣으면
  /// 지도에 뜨지도 않고 목록에서도 숨겨져 아무 일도 하지 않는다.
  ///
  /// 같은 날짜를 다시 고르면 **그 날짜의 예외를 갈아 끼운다**(쌓이지 않는다).
  Future<void> _addException(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _today,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 365)),
      helpText: '예외 날짜 선택',
    );
    if (picked == null) return;
    final date = DateTime(picked.year, picked.month, picked.day);

    if (!context.mounted) return;
    final stop = await onPickStop();
    if (stop == null) return;
    final start = await onPickTime(initial: defaultStart, title: '영업 시작 시간');
    final end = await onPickTime(
      initial: start ?? defaultEnd,
      title: '영업 종료 시간',
    );

    final key = ScheduleException.dateKeyOf(date);
    final existing = schedule.exceptionFor(date);
    onChanged(
      schedule.upsertException(
        ScheduleException(
          id: existing?.id ?? 'x-$key',
          dateKey: key,
          // 장소를 골라서 들어왔으므로 '하루 대체'다(휴무는 칩으로 바꾼다).
          mode: ScheduleExceptionMode.replaceDay,
          slot: ScheduleSlot(
            stop: stop,
            startTime: start ?? defaultStart,
            endTime: end ?? defaultEnd,
          ),
        ),
      ),
    );
  }

  Future<void> _editSlotStop(
    BuildContext context,
    ScheduleException e,
    ScheduleSlot? slot,
  ) async {
    final next = await onPickStop(initial: slot?.stop);
    if (next == null) return;
    onChanged(
      schedule.upsertException(
        e.copyWith(
          slot:
              slot?.copyWith(stop: next) ??
              ScheduleSlot(
                stop: next,
                startTime: defaultStart,
                endTime: defaultEnd,
              ),
        ),
      ),
    );
  }

  Future<void> _editSlotTime(
    BuildContext context,
    ScheduleException e,
    ScheduleSlot slot, {
    required bool isStart,
  }) async {
    final picked = await onPickTime(
      initial: isStart ? slot.startTime : slot.endTime,
      title: isStart ? '영업 시작 시간' : '영업 종료 시간',
    );
    if (picked == null) return;
    onChanged(
      schedule.upsertException(
        e.copyWith(
          slot: isStart
              ? slot.copyWith(startTime: picked)
              : slot.copyWith(endTime: picked),
        ),
      ),
    );
  }

  /// 모드만 바꾼다 — **장소는 지우지 않는다.** 휴무로 두었다가 되돌리면
  /// 등록해 둔 장소가 그대로 살아난다.
  void _setMode(ScheduleException e, ScheduleExceptionMode mode) =>
      onChanged(schedule.upsertException(e.copyWith(mode: mode)));

  /// 예외를 지우면 그 날짜는 **정기 일정으로 돌아간다**(모델의 해석이 그렇다).
  void _removeException(ScheduleException e) {
    final date = e.date;
    onChanged(
      date == null
          ? schedule.withExceptions([
              for (final other in schedule.exceptions)
                if (other.dateKey != e.dateKey) other,
            ])
          : schedule.withoutExceptionOn(date),
    );
  }

  /// `10월 20일 (화)` — 요일 라벨은 기존 정본에서 가져온다.
  static String _formatDate(DateTime date) =>
      '${date.month}월 ${date.day}일 '
      '(${PlaceWeeklyHours.weekdays[date.weekday - 1]})';
}
