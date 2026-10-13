import 'package:flutter/material.dart';

import 'package:party_app/models/address_result.dart';
import 'package:party_app/models/mobile_place_schedule.dart';
import 'package:party_app/models/place_weekly_hours.dart' show PlaceWeeklyHours;
import 'package:party_app/screens/party_location_picker_screen.dart';
import 'package:party_app/widgets/party_form/wheel_time_picker_sheet.dart';
import 'package:party_app/widgets/place_form/mobile_exception_editor.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 🚚 **"장소가 매번 바뀌시나요?"** — 이동형 플레이스의 영업 일정 편집기.
///
/// ── 한 날에 한 곳 ───────────────────────────────────────────────────────
/// 요일마다 장소 **하나**를 정한다(월: 홍대 · 화: 강남 · 수: 여의도 · 목: 휴무).
/// 그래서 버튼이 "장소 추가"가 아니라 **"장소 변경"**이다 — 추가할 자리가
/// 없으므로 중복 등록이 애초에 불가능하다([MobilePlaceSchedule.regular]가
/// 요일을 키로 가진 맵이다).
///
/// ── 기존 등록 흐름을 건드리지 않는다 ───────────────────────────────────
/// [isMobile]의 기본값은 **false**('아니요')다. 그 상태에서는 질문 하나만
/// 보여 주고 아래 일정 UI는 그려지지 않는다 — 고정형 장소를 등록하는 사람에게는
/// 선택지 두 줄이 늘어난 것이 전부다.
///
/// ── 상태는 호출부가 들고 있다 ──────────────────────────────────────────
/// 다른 섹션(`PetPolicySection` 등)과 같은 계약이다. 상태를 보관하지 않고
/// [onChanged]로 **새 일정**을 돌려준다([MobilePlaceSchedule]이 불변이다).
///
/// ── 판정 로직을 복사하지 않는다 ────────────────────────────────────────
/// 요일 좌표·`'HH:mm'` 해석·자정 넘김은 전부 모델 정본을 부른다. 이 파일에는
/// 시간 계산이 없다.
class MobileScheduleSection extends StatelessWidget {
  const MobileScheduleSection({
    super.key,
    required this.isMobile,
    required this.schedule,
    required this.onIsMobileChanged,
    required this.onChanged,
    this.today,
  });

  /// 오늘 — 테스트에서 고정할 수 있게 열어 둔다(비우면 [DateTime.now]).
  final DateTime? today;

  /// '네'를 골랐는가. **기본값은 호출부에서 false**로 둔다.
  final bool isMobile;

  final MobilePlaceSchedule schedule;

  final ValueChanged<bool> onIsMobileChanged;
  final ValueChanged<MobilePlaceSchedule> onChanged;

  static const _accent = Color(0xFFFF6FA0);
  static const _softPink = Color(0xFFFFF4F8);
  static const _border = Color(0xFFE8EBF2);
  static const _fieldFill = Color(0xFFF7F7FA);

  /// 1=월 … 7=일 — [DateTime.weekday]와 같은 좌표.
  static const List<int> _weekdays = [1, 2, 3, 4, 5, 6, 7];

  static String _weekdayLabel(int weekday) =>
      PlaceWeeklyHours.weekdays[weekday - 1];

  /// 요일 휴무 토글. 요일마다 같은 글자가 붙으므로 **키로 집을 수 있게** 둔다.
  static Key closedToggleKey(int weekday) => Key('mobileClosedToggle-$weekday');

  /// 그 요일의 장소를 고르거나 바꾸는 버튼.
  static Key stopButtonKey(int weekday) => Key('mobileStopButton-$weekday');

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '장소가 매번 바뀌시나요?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            '푸드트럭, 이동식 팝업스토어 등 여러 장소에서 운영하는 경우 선택해 주세요.',
            style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.45),
          ),
          const SizedBox(height: 14),
          // 두 선택지는 문장이라 칩으로 두면 좁은 화면에서 줄이 지저분하게
          // 끊긴다 — 전체 폭을 쓰는 줄 두 개로 둔다.
          _choice(
            label: '아니요, 고정된 장소에서 운영해요.',
            selected: !isMobile,
            onTap: () => onIsMobileChanged(false),
          ),
          const SizedBox(height: 8),
          _choice(
            label: '네, 여러 장소를 이동하며 운영해요.',
            selected: isMobile,
            onTap: () => onIsMobileChanged(true),
          ),
          if (isMobile) ...[
            const SizedBox(height: 20),
            _regularEditor(context),
            // 정기와 예외를 눈에 보이게 가른다 — 같은 카드 안에서 섞이면
            // "이게 매주인가, 이번 주만인가"를 알 수 없다.
            const SizedBox(height: 20),
            const Divider(height: 1, color: _border),
            const SizedBox(height: 16),
            MobileExceptionEditor(
              schedule: schedule,
              onChanged: onChanged,
              today: today,
              onPickStop: ({ScheduledStop? initial}) =>
                  _pickStop(context, initial: initial),
              onPickTime: ({required String initial, required String title}) =>
                  _pickTime(context, initial: initial, title: title),
            ),
          ],
        ],
      ),
    );
  }

  // ── 선택지 ───────────────────────────────────────────────────────────

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: selected ? _softPink : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? _accent : _border),
      ),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 18,
            color: selected ? _accent : Colors.black26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? _accent : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // ── 정기 일정 ────────────────────────────────────────────────────────

  Widget _regularEditor(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '정기 영업 일정',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      // 요일당 한 곳이라는 규칙을 문구로도 분명히 한다 — "추가"가 아니라
      // "변경"이라는 것을 버튼을 누르기 전에 알 수 있어야 한다.
      const Text(
        '요일마다 영업하는 장소 한 곳과 시간을 등록해 주세요. 하루에 한 장소만 등록할 수 있어요.',
        style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.45),
      ),
      const SizedBox(height: 12),
      for (final weekday in _weekdays) ...[
        _weekdayBlock(context, weekday),
        if (weekday != _weekdays.last) const SizedBox(height: 10),
      ],
    ],
  );

  Widget _weekdayBlock(BuildContext context, int weekday) {
    final closed = schedule.closedWeekdays.contains(weekday);
    final slot = schedule.regular[weekday];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: _fieldFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: closed ? Colors.black12 : _accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _weekdayLabel(weekday),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: closed ? Colors.black38 : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  // 버튼과 같은 낱말을 쓰지 않는다 — '휴무' 글자가 두 번 뜨면
                  // 어느 쪽이 눌리는 것인지 알 수 없다.
                  closed
                      ? '이 요일은 쉬어요'
                      : (slot == null ? '등록된 장소가 없어요' : '한 곳'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: closed ? Colors.black38 : Colors.black54,
                  ),
                ),
              ),
              // 휴무 토글 — 켜면 그 요일 일정이 **지워지지 않고** 쉬는 것으로만
              // 표시된다(되돌리면 그대로 살아난다).
              _closedToggle(weekday, closed),
            ],
          ),
          if (!closed) ...[
            const SizedBox(height: 10),
            if (slot == null)
              _pickStopButton(context, weekday)
            else
              _stopRow(context, weekday, slot),
          ],
        ],
      ),
    );
  }

  Widget _closedToggle(int weekday, bool closed) => GestureDetector(
    key: closedToggleKey(weekday),
    onTap: () => onChanged(schedule.withClosedWeekday(weekday, !closed)),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: closed ? _accent : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: closed ? _accent : _border),
      ),
      child: Text(
        '휴무',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: closed ? Colors.white : Colors.black54,
        ),
      ),
    ),
  );

  Widget _stopRow(BuildContext context, int weekday, ScheduleSlot slot) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 16, color: _accent),
              const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  key: stopButtonKey(weekday),
                  onTap: () => _changeStop(context, weekday, slot),
                  child: Text(
                    slot.stop.displayName.isEmpty
                        ? '장소를 선택해주세요'
                        : slot.stop.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: slot.stop.hasCoordinates
                          ? Colors.black87
                          : Colors.black38,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _changeStop(context, weekday, slot),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '장소 변경',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _accent,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => onChanged(schedule.withoutRegular(weekday)),
                icon: const Icon(Icons.close, size: 16),
                color: Colors.black38,
                visualDensity: VisualDensity.compact,
                tooltip: '삭제',
              ),
            ],
          ),
          if (slot.stop.detailAddress.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 22, bottom: 2),
              child: Text(
                slot.stop.detailAddress,
                style: const TextStyle(fontSize: 11, color: Colors.black45),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Row(
              children: [
                _timeButton(
                  context,
                  weekday: weekday,
                  slot: slot,
                  isStart: true,
                  label: slot.startTime,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('~', style: TextStyle(color: Colors.black38)),
                ),
                _timeButton(
                  context,
                  weekday: weekday,
                  slot: slot,
                  isStart: false,
                  label: slot.endTime,
                ),
                if (_crossesMidnight(slot)) ...[
                  const SizedBox(width: 8),
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
          ),
        ],
      ),
    );
  }

  /// 자정을 넘기는가 — 판정은 모델의 구간 정본이 한다(여기서 계산하지 않는다).
  static bool _crossesMidnight(ScheduleSlot slot) {
    final interval = slot.interval;
    return interval != null && interval.to > 24 * 60;
  }

  Widget _timeButton(
    BuildContext context, {
    required int weekday,
    required ScheduleSlot slot,
    required bool isStart,
    required String label,
  }) => GestureDetector(
    onTap: () => _editTime(context, weekday, slot, isStart: isStart),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _softPink,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    ),
  );

  Widget _pickStopButton(BuildContext context, int weekday) => GestureDetector(
    key: stopButtonKey(weekday),
    onTap: () => _changeStop(context, weekday, null),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: const Text(
        '장소 선택',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _accent,
        ),
      ),
    ),
  );

  // ── 편집 동작 ────────────────────────────────────────────────────────

  /// 장소 선택 — 파티가 쓰는 화면을 그대로 재사용한다
  /// ([PartyLocationPickerScreen] = 주소 검색 + 상세주소). 좌표는 검색 결과에서
  /// 온다. 기존 고정형 장소 등록도 같은 경로로 좌표를 받는다.
  ///
  /// ⚠️ 지도에서 핀을 끌어 조정하는 화면은 아직 없다. 붙일 때 바뀌는 곳은 이
  ///    메서드 하나이고, [ScheduledStop]이 좌표를 들고 있으므로 자료구조는
  ///    그대로 쓴다.
  Future<ScheduledStop?> _pickStop(
    BuildContext context, {
    ScheduledStop? initial,
  }) async {
    final selection = await Navigator.push<PartyLocationSelection>(
      context,
      webFramedRoute(
        (_) => PartyLocationPickerScreen(
          initialPlace: initial == null || !initial.hasCoordinates
              ? null
              : AddressResult(
                  placeName: initial.placeName,
                  address: initial.address,
                  roadAddress: initial.roadAddress,
                  jibunAddress: '',
                  latitude: initial.latitude,
                  longitude: initial.longitude,
                ),
          initialDetailAddress: initial?.detailAddress ?? '',
        ),
      ),
    );
    if (selection == null) return null;
    final place = selection.place;
    return ScheduledStop(
      placeName: place.placeName,
      address: place.address,
      roadAddress: place.roadAddress,
      detailAddress: selection.detailAddress,
      latitude: place.latitude,
      longitude: place.longitude,
    );
  }

  /// 시간 선택 — 기존 휠 시간 선택기를 그대로 쓴다. `'HH:mm'`을 돌려준다.
  /// 예외 일정 편집기도 이 한 곳을 거치므로 시간 입력 방식이 갈라지지 않는다.
  Future<String?> _pickTime(
    BuildContext context, {
    required String initial,
    required String title,
  }) async {
    final picked = await showWheelTimePicker(
      context,
      initial: _parse(initial),
      title: title,
    );
    return picked == null ? null : PlaceWeeklyHours.formatTime(picked);
  }

  /// 그 요일의 장소를 **바꾼다**(없으면 넣는다). 요일당 하나이므로 누를 때마다
  /// 늘어나지 않고 **갈아 끼운다**([MobilePlaceSchedule.withRegular]).
  Future<void> _changeStop(
    BuildContext context,
    int weekday,
    ScheduleSlot? slot,
  ) async {
    final stop = await _pickStop(context, initial: slot?.stop);
    if (stop == null) return;
    onChanged(
      schedule.withRegular(
        weekday,
        slot?.copyWith(stop: stop) ??
            ScheduleSlot(
              stop: stop,
              startTime: _defaultStart,
              endTime: _defaultEnd,
            ),
      ),
    );
  }

  Future<void> _editTime(
    BuildContext context,
    int weekday,
    ScheduleSlot slot, {
    required bool isStart,
  }) async {
    final picked = await _pickTime(
      context,
      initial: isStart ? slot.startTime : slot.endTime,
      title: isStart ? '영업 시작 시간' : '영업 종료 시간',
    );
    if (picked == null) return;
    onChanged(
      schedule.withRegular(
        weekday,
        isStart
            ? slot.copyWith(startTime: picked)
            : slot.copyWith(endTime: picked),
      ),
    );
  }

  // ── 작은 재료 ────────────────────────────────────────────────────────

  static const String _defaultStart = '11:00';
  static const String _defaultEnd = '20:00';

  /// `'HH:mm'` → [TimeOfDay]. 형식이 아니면 기본값을 쓴다(시간 선택기는
  /// 반드시 시작값이 필요하다).
  static TimeOfDay _parse(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null && h >= 0 && h <= 23 && m >= 0 && m <= 59) {
        return TimeOfDay(hour: h, minute: m);
      }
    }
    return const TimeOfDay(hour: 11, minute: 0);
  }
}
