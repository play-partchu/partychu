// 파티 목록 **헤더 한 줄**의 세로 정렬을 고정한다.
//
// 네 요소가 한 줄에 선다 — [ 파티 목록 ][ 🔊 ] … [ 보기방식 ][ 🔍 ].
// 줄 높이를 정하는 것은 오른쪽 버튼들(40)이고 제목 글씨는 20이라, 정렬을
// 잘못 잡으면 **같은 줄인데 왼쪽이 오른쪽보다 10px 아래로** 내려앉는다
// (2026-08-27 실기기에서 그렇게 보였다 — 원인은 `CrossAxisAlignment.end`).
//
// 그래서 여기서는 눈이 아니라 **좌표**로 못 박는다: 네 요소의 세로 중심이
// 같은 값이어야 한다. 좌표를 직접 미는 코드(Transform.translate)가 아니라
// 정렬·여백으로 맞췄으므로, 글꼴이나 아이콘 크기가 바뀌어도 이 테스트는
// 계속 같은 것을 확인한다.
//
// ⚠ 이 파일은 main_screen의 `_buildPartyListHeaderRow`와 **같은 구조를 다시
//   세운다**(그 메서드는 화면 상태에 묶인 private이라 그대로 부를 수 없다).
//   대신 안에 들어가는 것은 전부 화면이 쓰는 그 위젯 그대로다 —
//   [VideoMuteIconButton] · [ViewModeMenuButton] · [SearchEntryIconButton].
//   저 셋 중 하나의 높이가 바뀌면 여기서 곧바로 드러난다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/widgets/main/search_entry_sheet.dart';
import 'package:party_app/widgets/video_mute_button.dart';
import 'package:party_app/widgets/view_mode_switch.dart';

void main() {
  /// main_screen의 제목 글씨와 **같은 style·strutStyle**.
  /// 줄 상자를 글자 크기에 맞춰 조이는 것이 가운데 맞춤의 전제다 — 글꼴이
  /// 기본으로 얹는 여분 줄높이는 글자 위아래로 고르게 붙지 않아서, 조이지
  /// 않으면 가운데 맞춤을 해도 글자가 줄 중심보다 아래에 앉는다.
  Widget title({bool night = false}) => Text(
    '파티 목록',
    strutStyle: const StrutStyle(
      fontFamily: 'SeoulHangang',
      fontSize: 20,
      height: 1,
      forceStrutHeight: true,
    ),
    style: TextStyle(
      fontFamily: 'SeoulHangang',
      fontSize: 20,
      height: 1,
      fontWeight: FontWeight.w500,
      color: night ? Colors.white : null,
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  /// main_screen의 헤더 줄 + 그 바깥 여백(16, 4, 16, 0)을 그대로.
  Widget headerRow({bool night = false, bool titleHidden = false}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  alignment: Alignment.centerLeft,
                  child: titleHidden
                      ? const SizedBox.shrink()
                      : title(night: night),
                ),
              ),
              const VideoMuteIconButton(),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ViewModeMenuButton(
              currentIcon: Icons.view_agenda_rounded,
              label: '보기 방식 · 기본 카드',
              options: [
                ViewModeOption(
                  icon: Icons.view_agenda_rounded,
                  label: '기본 카드',
                  selected: true,
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(width: 8),
            SearchEntryIconButton(onTap: () {}, active: false),
          ],
        ),
      ],
    ),
  );

  Future<void> pumpAt(
    WidgetTester tester,
    double width, {
    bool night = false,
    bool titleHidden = false,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: night ? Colors.black : const Color(0xFFFFF4F8),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [headerRow(night: night, titleHidden: titleHidden)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 위젯 하나의 **세로 중심** y좌표.
  double centerY(WidgetTester tester, Finder f) => tester.getRect(f).center.dy;

  // 스피커·보기방식은 **버튼 상자**로 잰다 — 둘 다 아이콘을 대칭 여백
  // (스피커 EdgeInsets.all(8) · 알약 EdgeInsets.all(3)) 안에 넣으므로
  // 상자의 세로 중심이 곧 아이콘의 세로 중심이다. 돋보기는 그려지는 글리프를
  // 직접 잰다(IconButton이 20짜리 아이콘을 40 상자 한가운데에 놓는다).
  final muteIcon = find.byType(VideoMuteIconButton);
  final viewModeIcon = find.byType(ViewModeMenuButton);
  final searchIcon = find.byIcon(Icons.search_rounded);

  group('네 요소가 한 줄의 세로 중앙에 선다', () {
    for (final width in [320.0, 360.0, 390.0]) {
      for (final night in [false, true]) {
        final mode = night ? '밤' : '낮';

        testWidgets('${width.toInt()}dp · $mode 모드 — 중심이 모두 같다', (
          tester,
        ) async {
          await pumpAt(tester, width, night: night);

          final titleY = centerY(tester, find.text('파티 목록'));
          final muteY = centerY(tester, muteIcon);
          final viewY = centerY(tester, viewModeIcon);
          final searchY = centerY(tester, searchIcon);

          // 1px 미만 오차만 허용한다 — 예전 바닥 맞춤에서는 제목이 오른쪽
          // 버튼보다 10px 아래에 있었다.
          expect(
            titleY,
            closeTo(searchY, 0.5),
            reason: '제목이 돋보기와 다른 높이에 있다 (제목 $titleY / 돋보기 $searchY)',
          );
          expect(
            titleY,
            closeTo(viewY, 0.5),
            reason: '제목이 보기방식과 다른 높이에 있다 (제목 $titleY / 보기방식 $viewY)',
          );
          expect(
            muteY,
            closeTo(titleY, 0.5),
            reason: '스피커가 제목 글자의 세로 중앙에 없다 (스피커 $muteY / 제목 $titleY)',
          );
        });

        testWidgets('${width.toInt()}dp · $mode 모드 — 넘침 없음', (tester) async {
          await pumpAt(tester, width, night: night);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('헤더 덩어리가 예전보다 낮아졌다 — 필터 줄이 아래로 밀리지 않는다', () {
    testWidgets('줄 높이 40 + 위 여백 4 = 44 (예전 8 + 48 = 56)', (tester) async {
      await pumpAt(tester, 360);
      // 바깥 Padding까지 포함한 헤더 덩어리 전체 높이.
      final block = tester.getRect(find.byType(Padding).first).height;
      expect(
        block,
        lessThanOrEqualTo(44.0),
        reason:
            '헤더 덩어리가 44를 넘었다($block) — 예전 56에서 줄인 값이라, '
            '넘는 순간 아래 날짜/시간/인원 줄이 그만큼 밀린다',
      );
    });

    testWidgets('줄 높이를 정하는 것은 오른쪽 버튼(40)이다', (tester) async {
      await pumpAt(tester, 360);
      final view = tester.getRect(find.byType(ViewModeMenuButton)).height;
      final search = tester.getRect(find.byType(SearchEntryIconButton)).height;
      final text = tester.getRect(find.text('파티 목록')).height;
      final mute = tester.getRect(find.byType(VideoMuteIconButton)).height;
      expect(view, 40.0, reason: '보기방식 높이가 바뀌었다: $view');
      expect(search, 40.0, reason: '돋보기 높이가 바뀌었다: $search');
      // 제목 글씨는 줄 상자를 20으로 조여 두었다(그래야 중심이 맞는다).
      expect(text, 20.0, reason: '제목 줄 상자가 20이 아니다: $text');
      // 스피커는 줄 높이를 정하지 않는다(40보다 낮아야 한다).
      expect(mute, lessThan(40.0), reason: '스피커가 줄 높이를 밀어올린다: $mute');
    });
  });

  group('제목을 접어도 나머지가 흐트러지지 않는다', () {
    testWidgets('전체 숨김 — 스피커·보기방식·돋보기가 같은 높이로 남는다', (tester) async {
      await pumpAt(tester, 360, titleHidden: true);
      expect(find.text('파티 목록'), findsNothing);

      final muteY = centerY(tester, muteIcon);
      final searchY = centerY(tester, searchIcon);
      expect(muteY, closeTo(searchY, 0.5));
      expect(tester.takeException(), isNull);
    });
  });
}
