import 'package:flutter/material.dart';

import 'package:party_app/models/mobile_place_schedule.dart';
import 'package:party_app/models/place_weekly_hours.dart' show PlaceWeeklyHours;
import 'package:party_app/widgets/place_address_row.dart';

/// 🚚 **이동형 플레이스 상세의 영업 정보 카드.**
///
/// 고정형 장소는 등록한 주소 한 줄이 곧 "어디서 하는가"의 답이다. 이동형은
/// 날짜마다 답이 달라지므로 그 자리에 이 카드가 들어간다:
///
///     [오늘 여기서 영업 중]  한강공원
///     11:00 ~ 20:00
///     서울 영등포구 여의동로 330       [복사] [길찾기]
///
///     다음 영업 · 10월 14일 (수) 여의도 11:00~20:00
///
///     ─ 날짜별 영업 장소 ─
///     [오늘][수][목][금]…   ← 고른 날짜의 장소·주소·시간
///
/// ── 문서의 기준 주소를 쓰지 않는다 ─────────────────────────────────────
/// ⚠️ 이동형 문서에도 등록 시점의 `address`·`latitude`가 남아 있다. 그 값을
///    "현재 영업 장소"처럼 보여 주면 **손님을 없는 자리로 보낸다.** 이 카드는
///    언제나 [PlaceOpening.stop]의 주소·좌표만 쓴다.
///
/// ── 판정을 하지 않는다 ────────────────────────────────────────────────
/// 상태·우선순위·자정 넘김은 전부 [MobilePlaceSchedule]이 정한다
/// ([MobilePlaceSchedule.statusOn] · [MobilePlaceSchedule.upcomingDays] ·
/// [MobilePlaceSchedule.nextOpeningAfter]). 이 파일에는 시간 계산이 없다.
class MobileScheduleDetailCard extends StatefulWidget {
  const MobileScheduleDetailCard({
    super.key,
    required this.schedule,
    required this.placeName,
    this.focusDate,
    this.now,
    this.visibleDays = 14,
  });

  final MobilePlaceSchedule schedule;

  /// 업체 이름 — 길찾기 목적지 표기에 쓴다.
  final String placeName;

  /// 지도에서 넘어온 **선택 날짜**. 없으면 오늘을 쓴다.
  final DateTime? focusDate;

  /// 지금 — 테스트에서 고정할 수 있게 열어 둔다.
  final DateTime? now;

  /// 날짜 칩을 며칠까지 보여 줄지.
  final int visibleDays;

  /// 날짜 칩 — 테스트가 날짜로 집을 수 있게 둔다.
  static Key dateChipKey(DateTime date) =>
      Key('mobileDateChip-${ScheduleException.dateKeyOf(date)}');

  @override
  State<MobileScheduleDetailCard> createState() =>
      _MobileScheduleDetailCardState();
}

class _MobileScheduleDetailCardState extends State<MobileScheduleDetailCard> {
  late DateTime _selected = _initialDate;

  static const _accent = Color(0xFFFF6FA0);
  static const _softPink = Color(0xFFFFF4F8);
  static const _border = Color(0xFFE8EBF2);

  /// 넘어온 날짜가 **바뀌면** 고른 날짜를 다시 맞춘다.
  ///
  /// [State]는 위젯이 갈릴 때 다시 만들어지지 않으므로, 이게 없으면 호출부가
  /// 새 [MobileScheduleDetailCard.focusDate]로 다시 그려도 화면은 처음 날짜에
  /// 머문다 — 지도에서 넘긴 날짜와 상세가 어긋나는 길이다.
  ///
  /// 값이 그대로일 때는 손대지 않는다. 사용자가 날짜 칩으로 고른 선택을
  /// 부모의 재빌드가 되돌리면 안 된다.
  @override
  void didUpdateWidget(MobileScheduleDetailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusDate != widget.focusDate) {
      _selected = _initialDate;
    }
  }

  DateTime get _now => widget.now ?? DateTime.now();
  DateTime get _today => _dayOf(_now);

  /// 지도에서 넘어온 날짜를 우선 쓴다. 과거면 오늘로 끌어온다 — 지난 날짜의
  /// 영업을 상세 화면 머리에 띄우지 않는다.
  DateTime get _initialDate {
    final focus = widget.focusDate;
    if (focus == null) return _today;
    final day = _dayOf(focus);
    return day.isBefore(_today) ? _today : day;
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _isToday => _selected == _today;

  @override
  Widget build(BuildContext context) {
    final result = widget.schedule.statusOn(_selected, now: _now);
    final days = widget.schedule.upcomingDays(
      _today,
      days: widget.visibleDays,
    );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _softPink,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusHeader(result.status, result.opening),
          if (result.opening case final opening?) ...[
            const SizedBox(height: 8),
            _openingBody(opening),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              _isToday ? '오늘은 영업하지 않아요.' : '이 날은 영업하지 않아요.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          if (_nextLine() case final next?) ...[
            const SizedBox(height: 10),
            next,
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 10),
          const Text(
            '날짜별 영업 장소',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _dateChips(days),
        ],
      ),
    );
  }

  // ── 상태 머리 ────────────────────────────────────────────────────────

  Widget _statusHeader(MobileOpeningStatus status, PlaceOpening? opening) {
    final label = _statusLabel(status);
    final color = switch (status) {
      MobileOpeningStatus.open => const Color(0xFF2E7D32),
      MobileOpeningStatus.beforeOpen => _accent,
      MobileOpeningStatus.afterClose => Colors.black45,
      MobileOpeningStatus.closed => Colors.black45,
    };
    final background = switch (status) {
      MobileOpeningStatus.open => const Color(0xFFE8F5E9),
      MobileOpeningStatus.beforeOpen => Colors.white,
      _ => const Color(0xFFF1F1F4),
    };

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _isToday ? '오늘' : _formatDate(_selected),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
        ),
        if (opening?.isException ?? false)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              '이 날만',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  /// 오늘인지에 따라 말이 달라진다 — "오늘 여기서 영업 중"과 "영업 예정"은
  /// 같은 상태여도 사용자에게 다른 뜻이다.
  String _statusLabel(MobileOpeningStatus status) => switch (status) {
    MobileOpeningStatus.open => '오늘 여기서 영업 중',
    MobileOpeningStatus.beforeOpen => _isToday ? '오늘 영업 전' : '영업 예정',
    MobileOpeningStatus.afterClose => _isToday ? '오늘 영업 종료' : '영업 종료',
    MobileOpeningStatus.closed => '휴무',
  };

  // ── 영업 내용 ────────────────────────────────────────────────────────

  Widget _openingBody(PlaceOpening opening) {
    final stop = opening.stop;
    final address = PlaceAddressRow.joinAddress(
      stop.roadAddress.isNotEmpty ? stop.roadAddress : stop.address,
      stop.detailAddress,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          stop.displayName,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatTime(opening.start)} ~ ${_formatTime(opening.end)}'
          '${_crossesMidnight(opening) ? ' (익일)' : ''}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        if (address.isNotEmpty) ...[
          const SizedBox(height: 8),
          // ⚠️ 좌표도 **그 날 자리**를 넘긴다 — 길찾기가 기준 주소로 가면
          //    손님이 엉뚱한 곳에 도착한다.
          PlaceAddressRow(
            address: address,
            placeName: stop.placeName.isNotEmpty
                ? stop.placeName
                : widget.placeName,
            latitude: stop.latitude,
            longitude: stop.longitude,
          ),
        ],
      ],
    );
  }

  /// 자정을 넘기는가 — 모델이 준 절대 시각으로만 본다(계산하지 않는다).
  static bool _crossesMidnight(PlaceOpening opening) =>
      _dayOf(opening.end) != _dayOf(opening.start);

  // ── 다음 영업 ────────────────────────────────────────────────────────

  Widget? _nextLine() {
    final next = widget.schedule.nextOpeningAfter(_now);
    if (next == null) return null;
    // 지금 보고 있는 날짜의 영업이 곧 "다음"이면 두 번 말하지 않는다.
    final shown = widget.schedule.statusOn(_selected, now: _now).opening;
    if (shown != null && shown.start == next.start) return null;

    return Row(
      children: [
        const Icon(Icons.schedule, size: 13, color: Colors.black38),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            '다음 영업 · ${_formatDate(next.start)} '
            '${next.stop.displayName} '
            '${_formatTime(next.start)}~${_formatTime(next.end)}',
            style: const TextStyle(fontSize: 11, color: Colors.black54),
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  // ── 날짜별 ───────────────────────────────────────────────────────────

  Widget _dateChips(List<({DateTime date, PlaceOpening? opening})> days) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final day in days) ...[
              _dateChip(day),
              const SizedBox(width: 6),
            ],
          ],
        ),
      );

  Widget _dateChip(({DateTime date, PlaceOpening? opening}) day) {
    final selected = day.date == _selected;
    final closed = day.opening == null;
    return GestureDetector
    (
      key: MobileScheduleDetailCard.dateChipKey(day.date),
      onTap: () => setState(() => _selected = day.date),
      child: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _accent : _border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              day.date == _today ? '오늘' : _weekdayLabel(day.date),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : Colors.black54,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${day.date.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 3),
            // 휴무·일정 없는 날은 **장소 이름을 쓰지 않는다** — "없는 영업을
            // 있는 것처럼" 보이지 않게 하는 지점이다.
            Text(
              closed ? '휴무' : day.opening!.stop.displayName,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: closed
                    ? (selected ? Colors.white70 : Colors.black38)
                    : (selected ? Colors.white : _accent),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── 표기 ─────────────────────────────────────────────────────────────

  static String _weekdayLabel(DateTime date) =>
      PlaceWeeklyHours.weekdays[date.weekday - 1];

  static String _formatDate(DateTime date) =>
      '${date.month}월 ${date.day}일 (${_weekdayLabel(date)})';

  static String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
