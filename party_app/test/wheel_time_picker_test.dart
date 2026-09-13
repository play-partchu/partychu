import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/widgets/party_form/wheel_time_picker_sheet.dart';

/// 파티 폼 공통 휠 시간선택기 — 1분 단위 선택, 확인 버튼의 실시간 라벨,
/// 12시간제 → 24시간제 변환.
void main() {
  Widget host(TimeOfDay initial, void Function(TimeOfDay?) onPicked) =>
      MaterialApp(
        home: Builder(
          builder: (c) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    onPicked(
                      await showWheelTimePicker(
                        c,
                        initial: initial,
                        title: '시작 시간',
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      );

  testWidgets('초기 시각이 확인 버튼에 그대로 뜨고 확인하면 그 값이 돌아온다', (tester) async {
    TimeOfDay? picked;
    await tester.pumpWidget(
      host(const TimeOfDay(hour: 15, minute: 40), (v) {
        picked = v;
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('시작 시간'), findsOneWidget);
    expect(find.text('오후 3시 40분 선택'), findsOneWidget);

    await tester.tap(find.text('오후 3시 40분 선택'));
    await tester.pumpAndSettle();
    expect(picked, const TimeOfDay(hour: 15, minute: 40));
  });

  testWidgets('분 휠을 굴리면 1분 단위로 바뀌고 버튼 라벨도 따라온다', (tester) async {
    TimeOfDay? picked;
    await tester.pumpWidget(
      host(const TimeOfDay(hour: 9, minute: 0), (v) {
        picked = v;
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('오전 9시 00분 선택'), findsOneWidget);

    // 분 휠(세 번째)을 3칸(= itemExtent 44 * 3)만큼 위로 굴린다 → 00분 → 03분.
    await tester.drag(
      find.byType(CupertinoPicker).at(2),
      const Offset(0, -44 * 3),
    );
    await tester.pumpAndSettle();

    expect(find.text('오전 9시 03분 선택'), findsOneWidget);

    await tester.tap(find.text('오전 9시 03분 선택'));
    await tester.pumpAndSettle();
    expect(picked, const TimeOfDay(hour: 9, minute: 3));
  });

  testWidgets('오전/오후 휠을 굴리면 24시간제로 12시간이 더해진다', (tester) async {
    TimeOfDay? picked;
    await tester.pumpWidget(
      host(const TimeOfDay(hour: 7, minute: 23), (v) {
        picked = v;
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('오전 7시 23분 선택'), findsOneWidget);

    // 오전(0) → 오후(1).
    await tester.drag(find.byType(CupertinoPicker).first, const Offset(0, -44));
    await tester.pumpAndSettle();

    expect(find.text('오후 7시 23분 선택'), findsOneWidget);
    await tester.tap(find.text('오후 7시 23분 선택'));
    await tester.pumpAndSettle();
    expect(picked, const TimeOfDay(hour: 19, minute: 23));
  });

  testWidgets('오전 12시 / 오후 12시는 각각 0시 · 12시로 저장된다', (tester) async {
    // 오전 12시 05분 → 00:05
    TimeOfDay? picked;
    await tester.pumpWidget(
      host(const TimeOfDay(hour: 0, minute: 5), (v) {
        picked = v;
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('오전 12시 05분 선택'), findsOneWidget);
    await tester.tap(find.text('오전 12시 05분 선택'));
    await tester.pumpAndSettle();
    expect(picked, const TimeOfDay(hour: 0, minute: 5));

    // 오후 12시 40분 → 12:40
    await tester.pumpWidget(
      host(const TimeOfDay(hour: 12, minute: 40), (v) {
        picked = v;
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('오후 12시 40분 선택'), findsOneWidget);
    await tester.tap(find.text('오후 12시 40분 선택'));
    await tester.pumpAndSettle();
    expect(picked, const TimeOfDay(hour: 12, minute: 40));
  });
}
