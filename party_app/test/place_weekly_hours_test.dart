import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/place_weekly_hours.dart';

void main() {
  test('기본 프리셋은 월~금 08:00~02:00, 토~일 09:00~03:00이다', () {
    final hours = PlaceWeeklyHours.defaultPreset();

    expect(hours.get('월')?.open, const TimeOfDay(hour: 8, minute: 0));
    expect(hours.get('금')?.close, const TimeOfDay(hour: 2, minute: 0));
    expect(hours.get('토')?.open, const TimeOfDay(hour: 9, minute: 0));
    expect(hours.get('일')?.close, const TimeOfDay(hour: 3, minute: 0));
  });

  test('직렬화 후 복원이 동일한 요일별 시간을 유지한다', () {
    final original = PlaceWeeklyHours.defaultPreset();
    final restored = PlaceWeeklyHours.fromMap(original.toMap());

    expect(restored.get('월')?.open, const TimeOfDay(hour: 8, minute: 0));
    expect(restored.get('월')?.close, const TimeOfDay(hour: 2, minute: 0));
    expect(restored.get('토')?.open, const TimeOfDay(hour: 9, minute: 0));
    expect(restored.get('일')?.close, const TimeOfDay(hour: 3, minute: 0));
  });

  test('휴무 상태와 24시간 포맷은 직렬화 후에도 유지된다', () {
    final hours = PlaceWeeklyHours.defaultPreset();
    hours.set(
      '월',
      const TimeOfDay(hour: 8, minute: 0),
      const TimeOfDay(hour: 22, minute: 0),
      isClosed: false,
    );
    hours.set(
      '화',
      const TimeOfDay(hour: 9, minute: 30),
      const TimeOfDay(hour: 18, minute: 45),
      isClosed: true,
    );

    expect(hours.get('화')?.isClosed, isTrue);
    expect(
      PlaceWeeklyHours.formatTime(const TimeOfDay(hour: 14, minute: 5)),
      '14:05',
    );

    final restored = PlaceWeeklyHours.fromMap(hours.toMap());
    expect(restored.get('화')?.isClosed, isTrue);
    expect(restored.get('월')?.open, const TimeOfDay(hour: 8, minute: 0));
    expect(restored.get('월')?.close, const TimeOfDay(hour: 22, minute: 0));
  });
}
