import 'package:flutter/material.dart';

import 'package:party_app/models/party_filter.dart';

/// 📅🕐 조건을 **알약 한 줄**로 줄인 표기 — 지도 홈의 날짜·시간 버튼이 쓴다.
///
///   날짜만   : '오늘' · '내일' · '모레' · '9.20' (여러 날이면 '오늘 외 2')
///   시간만   : '19:00'(지정 시간) · '18:00–22:00'(지정 구간) · '~22:00'
///   둘 다    : '오늘 · 19:00'
///   조건 없음: null — 부르는 쪽이 기본 문구('📅 날짜 · 시간')를 쓴다.
///
/// 새 조건을 만들지 않는다 — 목록 탭 빠른필터와 같은 [PartyFilter] 칸
/// (selectedDates · timeOfDayStart/End)을 읽을 뿐이다. 상세검색의 예전 날짜
/// 옵션(dateOptions: '오늘'·'이번주말' …)이 남아 있으면 그것도 그대로 적는다.
String? dateTimeFilterLabel(PartyFilter f, {DateTime? now}) {
  final date = _datePart(f, now ?? DateTime.now());
  final time = _timePart(f.timeOfDayStart, f.timeOfDayEnd);
  final parts = [?date, ?time];
  return parts.isEmpty ? null : parts.join(' · ');
}

String? _datePart(PartyFilter f, DateTime now) {
  String more(int n) => n > 1 ? ' 외 ${n - 1}' : '';
  final days = f.selectedDatesSorted;
  if (days.isNotEmpty) {
    final today = PartyFilter.dateOnly(now);
    final d = days.first;
    final label = switch (PartyFilter.dateOnly(d).difference(today).inDays) {
      0 => '오늘',
      1 => '내일',
      2 => '모레',
      _ => '${d.month}.${d.day}',
    };
    return '$label${more(days.length)}';
  }
  if (f.dateOptions.isNotEmpty) {
    return '${f.dateOptions.first}${more(f.dateOptions.length)}';
  }
  return null;
}

String? _timePart(TimeOfDay? s, TimeOfDay? e) {
  String hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (s != null && e == null) return hhmm(s);
  if (s == null && e != null) return '~${hhmm(e)}';
  if (s != null && e != null) return '${hhmm(s)}–${hhmm(e)}';
  return null;
}
