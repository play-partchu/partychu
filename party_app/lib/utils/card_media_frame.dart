import 'package:flutter/widgets.dart';

import 'package:party_app/widgets/list_card_shell.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 기본 카드(2열 그리드) 미디어 영역의 **비율 정본**.
//
// 사진 크롭([PhotoCropScreen])과 동영상 크롭([VideoCropScreen])은 "카드에서
// 실제로 보이는 만큼"을 사용자에게 미리 보여주고 그 안에서 확대·이동을 받는다.
// 그러니 두 화면이 쓰는 프레임 비율이 실제 카드와 **한 픽셀도 어긋나면 안
// 된다** — 어긋나면 사용자가 맞춘 위치와 목록에 뜨는 위치가 달라진다.
//
// 예전에는 이 계산이 `PartyMediaEditor._cardFrameSize`라는 private 메서드
// 안에만 있었다. 그래서 (1) 다른 등록 화면이 재사용할 수 없었고, (2) 카드
// 높이 130이 [GridCardShell.imageHeight]와 이 파일 두 곳에 각각 적혀 있어
// 한쪽만 바뀌면 조용히 어긋났다. 계산을 여기로 올리고 높이는 카드 정본을
// 그대로 읽는다.
//
// ⚠️ 이 값은 **기본 카드 전용**이다. 작은 카드·큰 카드는 미디어 영역 비율이
// 달라서 크롭 값도 따로 저장한다(`videoCropX/Y/Scale` vs
// `basicCardVideoFocalX/Y/Scale` — party_utils.dart의 [PartyCoverMedia] 주석).
// ─────────────────────────────────────────────────────────────────────────────

/// 목록 2열 그리드에서 카드 한 장이 차지하는 폭.
///
/// 좌우 바깥 여백 16*2 + 카드 사이 간격 10 = 42를 뺀 나머지를 둘로 나눈다.
double basicCardWidth(double screenWidth) => (screenWidth - 42) / 2;

/// 기본 카드 미디어 영역의 가로:세로 비율(폭 / 높이).
double basicCardMediaAspectRatio(BuildContext context) =>
    basicCardWidth(MediaQuery.of(context).size.width) /
    GridCardShell.imageHeight;

/// 크롭 편집 화면에 넘길 **미리보기 프레임 크기**.
///
/// 실제 카드(카드폭 × 130)보다 크게 보여준다 — 손가락으로 확대·이동하기에는
/// 카드 실물 크기가 너무 작다. **비율은 카드와 정확히 같게** 유지하므로,
/// 여기서 맞춘 위치가 목록에서 그대로 재현된다.
Size basicCardCropFrameSize(BuildContext context) {
  final screenWidth = MediaQuery.of(context).size.width;
  // 좌우 24씩 여백을 두고 화면 폭을 거의 다 쓴다.
  final displayWidth = screenWidth - 48;
  return Size(
    displayWidth,
    displayWidth / basicCardMediaAspectRatio(context),
  );
}
