import 'package:flutter/material.dart';

import 'package:party_app/screens/event_register_screen.dart';

/// 플레이스 수정 진입점 — **얇은 래퍼**다.
///
/// 예전에는 이 파일이 event_register_screen.dart와 메서드 이름·섹션 순서까지
/// 똑같은 1,100줄짜리 복사본이었다. 그래서 등록에 기능을 넣으면 수정에는 빠지고,
/// 수정에서 고친 것은 등록에 반영되지 않아 내부 751줄이 이미 어긋나 있었다.
///
/// 이제 폼은 [EventRegisterScreen] 한 곳에만 있고, 이 클래스는 그 화면을
/// 수정 모드로 여는 일만 한다 — 입력 항목·섹션 순서·검증·사진/동영상·운영시간·
/// 상품·이용권·이벤트·주소가 등록과 100% 같아진다.
///
/// 새 코드는 `EventRegisterScreen.edit(...)`을 직접 써도 된다. 이 클래스는
/// 기존 호출부(마이페이지 카드, 플레이스 상세)를 위해 남겨 둔 이름이다.
class EventEditScreen extends StatelessWidget {
  final String eventId;
  final Map<String, dynamic> data;

  const EventEditScreen({super.key, required this.eventId, required this.data});

  @override
  Widget build(BuildContext context) =>
      EventRegisterScreen.edit(eventId: eventId, sourceData: data);
}
