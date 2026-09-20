import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/public_event.dart';
import 'package:party_app/services/public_event_service.dart';

/// 운영 publicEvents 문서(tour_1307813, 2026-09-19 동기화)와 같은 모양.
Map<String, dynamic> realDoc({
  String title = '강동선사문화축제',
  DateTime? startAt,
  DateTime? endAt,
  Object? location = const {'lat': 37.5590614, 'lng': 127.1306007},
}) => {
  'source': 'tourapi',
  'sourceId': '1307813',
  'sourceType': 'festival',
  'contentTypeId': '15',
  'title': title,
  'address': '서울특별시 강동구 올림픽로 875 (암사동)',
  'addressDetail': null,
  'zipcode': '05252',
  'tel': '02-3425-5250',
  'regionCode': '11',
  'sigunguCode': '11740',
  'categoryCodes': ['EV', 'EV01', 'EV010200'],
  'location': location,
  'startDate': '20261016',
  'endDate': '20261018',
  'startAt': Timestamp.fromDate(
    startAt ?? DateTime.utc(2026, 10, 15, 15),
  ),
  'endAt': Timestamp.fromDate(
    endAt ?? DateTime.utc(2026, 10, 18, 14, 59, 59, 999),
  ),
  'imageUrl':
      'https://tong.visitkorea.or.kr/cms/resource/77/3541977_image2_1.jpg',
  'thumbnailUrl':
      'https://tong.visitkorea.or.kr/cms/resource/77/3541977_image3_1.jpg',
  'copyrightType': 'Type3',
  'attribution': '한국관광공사',
  'status': 'active',
  'isVisible': true,
  'missingCount': 0,
  'schemaVersion': 1,
  'contentHash': 'x',
  'sourceModifiedTime': '20260801090000',
};

void main() {
  test('운영 문서 모양을 그대로 읽는다', () {
    final e = PublicEvent.tryFromMap('tour_1307813', realDoc())!;
    expect(e.id, 'tour_1307813');
    expect(e.source, 'tourapi');
    expect(e.sourceId, '1307813');
    expect(e.title, '강동선사문화축제');
    expect(e.startAt.toUtc(), DateTime.utc(2026, 10, 15, 15));
    expect(e.endAt.toUtc(), DateTime.utc(2026, 10, 18, 14, 59, 59, 999));
    expect(e.address, '서울특별시 강동구 올림픽로 875 (암사동)');
    expect(e.addressDetail, isNull);
    expect(e.lat, 37.5590614);
    expect(e.lng, 127.1306007);
    expect(e.hasLocation, isTrue);
    expect(e.regionCode, '11');
    expect(e.sigunguCode, '11740');
    expect(e.categoryCodes, ['EV', 'EV01', 'EV010200']);
    expect(e.attribution, '한국관광공사');
    expect(e.status, PublicEvent.statusActive);
    expect(e.isVisible, isTrue);
  });

  test('좌표·지역이 null이어도 읽고, 제목·기간이 없으면 건너뛴다', () {
    final noLoc = PublicEvent.tryFromMap(
      'a',
      realDoc(location: null)
        ..['regionCode'] = null
        ..['sigunguCode'] = null,
    )!;
    expect(noLoc.hasLocation, isFalse);
    expect(noLoc.regionCode, isNull);
    expect(PublicEvent.tryFromMap('b', realDoc(title: '  ')), isNull);
    expect(PublicEvent.tryFromMap('c', realDoc()..remove('endAt')), isNull);
  });

  test('끝난 행사를 빼고, 진행 중 → 곧 시작 순으로, 같으면 곧 끝나는 것부터', () {
    final now = DateTime.utc(2026, 9, 19, 9);
    PublicEvent ev(String id, DateTime start, DateTime end) =>
        PublicEvent.tryFromMap(id, realDoc(startAt: start, endAt: end))!;
    final list = PublicEventService.openSorted([
      ev('later', DateTime.utc(2026, 10, 1), DateTime.utc(2026, 10, 3)),
      ev('ongoingLong', DateTime.utc(2026, 5, 1), DateTime.utc(2026, 12, 1)),
      ev('ended', DateTime.utc(2026, 9, 1), DateTime.utc(2026, 9, 18)),
      ev('soon', DateTime.utc(2026, 9, 20), DateTime.utc(2026, 9, 21)),
      ev('ongoingShort', DateTime.utc(2026, 9, 18), DateTime.utc(2026, 9, 19, 14)),
    ], now: now);
    expect(list.map((e) => e.id), [
      'ongoingShort',
      'ongoingLong',
      'soon',
      'later',
    ]);
  });
}
