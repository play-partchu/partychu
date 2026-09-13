import 'package:flutter/material.dart';

import 'package:party_app/screens/place_register_screen.dart';

/// 파티 장소(공간대여) 수정 진입점 — **얇은 래퍼**다.
///
/// 예전에는 이 파일이 place_register_screen.dart와 섹션 빌더 이름·순서까지
/// 똑같은 2,000줄짜리 복사본이었다. 그래서 등록에 기능을 넣으면 수정에는 빠지고
/// (미입력 항목 배너가 대표적이다) 반대도 마찬가지라 계속 갈라졌다.
///
/// 이제 폼은 [PlaceRegisterScreen] 한 곳에만 있고, 이 클래스는 그 화면을 수정
/// 모드로 여는 일만 한다 — 입력 항목·섹션 순서·검증·사진/동영상·운영시간·
/// 룸/공간·상품·이용권·이벤트·정산 계좌·주소가 등록과 100% 같아진다.
///
/// 진행중 상태에서 "수정"으로 열 때도, 숨김 상태에서 "재등록"으로 열 때도 이
/// 화면 하나를 그대로 쓴다. 저장하면 항상 `isActive:true` + `hiddenAt` 삭제가
/// 함께 나가므로(숨김이었다면 재등록, 진행중이었다면 그대로 유지) 별도의
/// "재등록 모드" 분기가 필요 없다.
///
/// 새 코드는 `PlaceRegisterScreen.edit(...)`을 직접 써도 된다. 이 클래스는
/// 기존 호출부(마이페이지 카드, 장소 상세)를 위해 남겨 둔 이름이다.
class PlaceEditScreen extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;

  const PlaceEditScreen({super.key, required this.docId, required this.data});

  @override
  Widget build(BuildContext context) =>
      PlaceRegisterScreen.edit(docId: docId, sourceData: data);
}
