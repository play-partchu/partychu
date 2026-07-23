import 'package:flutter/foundation.dart';

/// 파티/장소대여/파티샵/파티크루 등록 화면이 등록을 완료하고 [MainScreen]
/// 루트로 돌아갈 때, "돌아가면 이 상단 탭을 보여줘"라고 알리는 신호.
///
/// 값 하나만 공유하는 [ValueNotifier]로 구현한 이유: MainScreen은 등록
/// 화면들을 직접 import(desktop 흐름에서 `_handleCategoryAwareRegisterTap`)
/// 하고 있어, 반대로 등록 화면이 MainScreen을 import하면 순환 참조가
/// 생긴다. 이 파일 하나만 양쪽이 공유하면 순환 참조 없이 신호를 주고받을
/// 수 있다.
///
/// 탭 인덱스: 0=파티, 1=플레이스, 2=장소대여, 3=파티크루
/// (MainScreen의 `_topTabController`/`TabBar` 순서와 반드시 같아야 한다).
///
/// 파티샵은 더 이상 독립 탭이 아니라 플레이스 탭(인덱스 1) 안의 카테고리
/// 칩이다 — 파티샵 등록 화면은 인덱스 1과 함께
/// [pendingPlaceShopCategoryAfterRegister]도 true로 켜서, 돌아갔을 때
/// 이벤트가 아니라 파티샵 카테고리가 보이게 한다.
final ValueNotifier<int?> pendingTopTabAfterRegister = ValueNotifier<int?>(
  null,
);

/// 파티샵 등록을 마치고 플레이스 탭(인덱스 1)으로 돌아갈 때, 이벤트가
/// 아니라 파티샵 카테고리를 보여주라는 신호. [pendingTopTabAfterRegister]와
/// 함께(같은 시점에) 설정되고, MainScreen에서 그 리스너 안에서 한 번만
/// 소비된다.
final ValueNotifier<bool> pendingPlaceShopCategoryAfterRegister =
    ValueNotifier<bool>(false);
