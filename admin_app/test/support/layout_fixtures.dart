// 모바일 레이아웃 테스트가 함께 쓰는 가짜 신청서 데이터와 검사 도구.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 요청받은 검증 폭(대표 안드로이드 기기 폭).
const deviceWidths = [360.0, 390.0, 412.0, 430.0];

/// 일부러 길게 둔 값들 — 짧은 값만 넣으면 넘침이 숨는다.
const longStoreName = '강남역 루프탑 파티하우스 프리미엄 라운지점';
const longEmail = 'verylonghostaddress.partychu@example-domain.co.kr';

final _pre1 = <String, dynamic>{
  'status': 'new',
  'serialNumber': 1024,
  'submittedAt': DateTime(2026, 9, 17, 14, 32).millisecondsSinceEpoch,
  'storeName': longStoreName,
  'businessRegistrationNumber': '1234567890',
  'hostName': '박효정',
  'hostEmail': longEmail,
  'hostPhone': '01012345678',
  'sameAsRepresentative': false,
  'representativeName': '김대표',
  'representativePhone': '01098765432',
  'representativeEmail': 'representative@example.co.kr',
  'deviceType': 'both',
  'importState': 'ok',
  'hostUid': 'AbCdEfGhIjKlMnOpQrStUvWxYz12',
  'memo': '',
};

final _pre2 = <String, dynamic>{
  'status': 'representativeVerificationRequired',
  'serialNumber': 1025,
  'submittedAt': DateTime(2026, 9, 16, 9, 5).millisecondsSinceEpoch,
  'storeName': '홍대 파티룸',
  'businessRegistrationNumber': '9876543210',
  'hostName': '이호스트',
  'hostEmail': 'host2@example.com',
  'deviceType': 'android',
  'importState': 'ok',
};

final fakeCollections = <String, List<(String, Map<String, dynamic>)>>{
  'hostPreRegistrations': [('pre_1', _pre1), ('pre_2', _pre2)],
  'hostPreRegistrationConfig': [
    (
      'formhug',
      {
        'fields': {'storeName': 'field_1'},
      }
    ),
  ],
};

/// 관리자 업무 알림 2건 — 하나는 uidAdminA가 이미 읽었다.
/// (서버가 만드는 문서 모양 그대로: functions/adminNotifications.js)
final fakeAdminNotifications = <(String, Map<String, dynamic>)>[
  (
    'host_pre_registration__formhug_Sbyrul_9',
    {
      'type': 'host_pre_registration',
      'title': '새로운 사전등록 신청',
      'body': '파티츄 홍대점에서 새로운 사전등록 신청이 들어왔습니다.',
      'refCollection': 'hostPreRegistrations',
      'refId': 'formhug_Sbyrul_9',
      'readBy': <String>[],
      'createdAt': DateTime.now().subtract(const Duration(minutes: 3)).millisecondsSinceEpoch,
    }
  ),
  (
    'host_pre_registration__formhug_Sbyrul_8',
    {
      'type': 'host_pre_registration',
      'title': '새로운 사전등록 신청',
      // 아직 import 전이라 업체명이 없는 상태 — 실제로 생기는 모양이다.
      'body': '새로운 호스트 사전등록 신청이 들어왔습니다.',
      'refCollection': 'hostPreRegistrations',
      'refId': 'formhug_Sbyrul_8',
      'readBy': <String>['uidAdminA'],
      'createdAt': DateTime.now().subtract(const Duration(hours: 5)).millisecondsSinceEpoch,
    }
  ),
];

Map<String, dynamic> detailPayload() => {
      'preRegistration': {'id': 'pre_1', ..._pre1},
      'host': {
        'uid': 'AbCdEfGhIjKlMnOpQrStUvWxYz12',
        'nickname': '파티하우스',
        'email': longEmail,
        'identityVerified': true,
        'businessStatus': 'approved',
        'authorization': 'representative',
      },
      'candidates': <dynamic>[],
      'history': [
        {
          'at': DateTime(2026, 9, 17, 14, 32).millisecondsSinceEpoch,
          'actor': 'system',
          'message': 'FormHug 신청서가 접수되어 신청 내용을 가져왔습니다.',
        },
      ],
    };

/// 페이지가 통째로 좌우로 움직이지는 않는지 — 가로 스크롤은 표(DataTable)를
/// 감싼 것만 있어야 한다는 요구사항을 구조로 확인한다.
void expectHorizontalScrollOnlyAroundTables() {
  final horizontal = find.byWidgetPredicate(
    (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
  );
  for (final element in horizontal.evaluate()) {
    final hasTable = find
        .descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(DataTable),
        )
        .evaluate()
        .isNotEmpty;
    expect(
      hasTable,
      isTrue,
      reason: '표가 아닌 영역에 가로 스크롤이 생겼습니다 — 페이지가 통째로 움직입니다.',
    );
  }
}
