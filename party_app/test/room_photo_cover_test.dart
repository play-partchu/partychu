import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/screens/full_screen_image_viewer.dart';
import 'package:party_app/widgets/room_photo_cover.dart';

/// 장소대여 상세 > 룸 선택 카드의 사진 영역.
///
/// 상세 화면(Firebase 의존)을 통째로 띄우지 않고, 룸 카드가 놓이는 여백
/// (페이지 16 + 룸 섹션 16 + 카드 14 + 선택 테두리 1.5)과 카드 안 정보 줄을
/// 그대로 재현해 모바일 폭별 overflow와 뷰어 동작을 본다.
void main() {
  const images = [
    'https://example.com/room-1.jpg',
    'https://example.com/room-2.jpg',
    'https://example.com/room-3.jpg',
    'https://example.com/room-4.jpg',
  ];

  Widget card(List<String> imgs) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16), // 상세 본문
          child: Container(
            padding: const EdgeInsets.all(16), // 룸 선택 섹션
            color: Colors.white,
            child: Container(
              padding: const EdgeInsets.all(14), // 룸 카드
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFFF6FA0), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RoomPhotoCover(images: imgs),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '프라이빗 파티룸 A (루프탑 대형 단체룸)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '기준 10인 / 최대 30인  ·  1,250,000원 / 시간',
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: const [
                                Chip(label: Text('시간제')),
                                Chip(label: Text('숙박')),
                              ],
                            ),
                            const Text(
                              '오전 10:00 ~ 익일 오전 02:00  ·  30분 단위',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.check_circle, size: 22),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  for (final width in [360.0, 390.0, 412.0, 430.0]) {
    testWidgets('${width.toInt()}px — overflow 없이 카드 폭 16:9로 그린다', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(card(images));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(RoomPhotoCover));
      final inner = width - 2 * (16 + 16 + 14 + 1.5);
      expect(size.width, moreOrLessEquals(inner, epsilon: 0.01));
      expect(size.height, moreOrLessEquals(inner * 9 / 16, epsilon: 0.01));
      // 56px 썸네일보다 확실히 크다(360px에서도 약 150px).
      expect(size.height, greaterThan(140));
      // 여러 장 표시와 확대 아이콘.
      expect(find.text('4'), findsOneWidget);
      expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
      expect(find.byIcon(Icons.zoom_out_map_rounded), findsOneWidget);
    });
  }

  testWidgets('넓은 화면에서는 높이 240에서 멈춘다', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(card(images));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(RoomPhotoCover)).height, 240);
  });

  testWidgets('한 장이면 개수 배지가 없다', (tester) async {
    await tester.pumpWidget(card(images.take(1).toList()));
    await tester.pump();

    expect(find.byIcon(Icons.photo_library_outlined), findsNothing);
    expect(find.byIcon(Icons.zoom_out_map_rounded), findsOneWidget);
  });

  testWidgets('탭하면 전체화면 뷰어 — 1 / 4, 스와이프, 닫기', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(card(images));
    await tester.pump();

    await tester.tap(find.byType(RoomPhotoCover));
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenImageViewer), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);

    // fullscreenDialog라 앱바 왼쪽이 닫기(X)다.
    expect(find.byType(CloseButton), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenImageViewer), findsNothing);
  });
}
