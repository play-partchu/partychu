// 🎊 공공 축제 상세 — 서버 상세 보강(소개·프로그램·사진·홈페이지·주최 등)을
// 받은 문서와 아직 받지 않은 문서(보강은 회차당 100건씩이라 둘이 섞여 있다)가
// 모두 오류 없이 열리고, 값이 없는 줄·섹션·버튼은 자리째 빠진다.
//
// 사진은 네트워크 이미지라 위젯 테스트에서 400으로 실패한다. 그건 관심사가
// 아니라서 이미지 로드 오류만 걸러 내고 **그 밖의 오류는 없어야** 한다.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/public_event.dart';
import 'package:party_app/screens/public_event_detail_screen.dart';
import 'package:party_app/widgets/media_gallery.dart';

const _rep = 'https://tong.visitkorea.or.kr/cms/resource/61/4081461_image2_1.jpg';
String _img(int n) => 'https://tong.visitkorea.or.kr/cms/resource/$n/${n}_image2_1.jpg';

const _program =
    '1. 메인프로그램\n- 개막식, 축하공연\n\n2. 부대프로그램\n- 먹거리장터';

/// 운영 문서 모양 그대로(Firestore 타입: Timestamp·map·string 배열).
Map<String, dynamic> _baseDoc() => {
  'source': 'tourapi',
  'sourceId': '1100492',
  'sourceType': 'festival',
  'contentTypeId': '15',
  'title': '고양호수예술축제',
  'address': '경기도 고양시 일산동구 호수로 595 (장항동)',
  'addressDetail': '일산호수공원 및 일산문화광장 일원',
  'zipcode': '10400',
  'tel': '1577-7766',
  'regionCode': '41',
  'sigunguCode': '41285',
  'categoryCodes': ['EV', 'EV01', 'EV010200'],
  'location': {'lat': 37.6552847, 'lng': 126.7689083},
  'startDate': '20260918',
  'endDate': '20260920',
  'startAt': Timestamp.fromDate(DateTime.utc(2026, 9, 17, 15)),
  'endAt': Timestamp.fromDate(DateTime.utc(2026, 9, 20, 14, 59, 59, 999)),
  'imageUrl': _rep,
  'thumbnailUrl': _rep.replaceFirst('image2', 'image3'),
  'copyrightType': 'Type3',
  'attribution': '한국관광공사',
  'sourceCreatedTime': '20100928195707',
  'sourceModifiedTime': '20260909211257',
  'contentHash': 'x',
  'schemaVersion': 1,
  'status': 'active',
  'isVisible': true,
  'missingCount': 0,
};

Map<String, dynamic> _enrichedDoc({
  List<String>? images,
  String? homepageUrl = 'https://www.goyang.go.kr/festival',
}) => {
  ..._baseDoc(),
  'overview': '일상 속 공간이 특별한 예술의 리듬으로 채워지는 순간이 펼쳐진다.',
  'program': _program,
  'homepageUrl': homepageUrl,
  'organizer': '고양시',
  'host': '고양문화재단',
  'contactName': '고양시',
  'feeText': '무료',
  'playTime': '14:00~21:00',
  'eventPlace': '일산호수공원',
  'images': images ?? [_rep, _img(55), _img(56)],
  'detailFetchedModifiedTime': '20260909211257',
};

PublicEvent _from(Map<String, dynamic> d) =>
    PublicEvent.tryFromMap('tour_1100492', d)!;

/// 긴 상세가 게으른 슬리버에 잘리지 않게 화면을 크게 잡는다.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 펌프하면서 오류를 모은다 — 네트워크 이미지 실패만 빼고 돌려준다.
Future<List<String>> _pump(WidgetTester tester, Widget w) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (d) => errors.add(d.exceptionAsString());
  try {
    await tester.pumpWidget(w);
    await tester.pump();
  } finally {
    FlutterError.onError = previous;
  }
  tester.takeException();
  return errors
      .where((e) => !e.contains('HTTP request failed') && !e.contains('NetworkImage'))
      .toList();
}

Widget _app(PublicEvent e, {PublicEventUrlOpener? open}) => MaterialApp(
  home: open == null
      ? PublicEventDetailScreen(event: e)
      : PublicEventDetailScreen(event: e, openUrl: open),
);

List<String> _galleryImages(WidgetTester tester) =>
    tester.widget<MediaGallery>(find.byType(MediaGallery)).images;

void main() {
  group('모델', () {
    test('보강 완료 문서 — 보강 필드를 모두 읽는다(detailFetchedModifiedTime은 담지 않는다)', () {
      final e = _from(_enrichedDoc());
      expect(e.overview, startsWith('일상 속 공간이'));
      expect(e.program, _program, reason: '원본 줄바꿈 그대로');
      expect(e.homepageUrl, 'https://www.goyang.go.kr/festival');
      expect(e.organizer, '고양시');
      expect(e.host, '고양문화재단');
      expect(e.contactName, '고양시');
      expect(e.feeText, '무료');
      expect(e.playTime, '14:00~21:00');
      expect(e.eventPlace, '일산호수공원');
      expect(e.images, [_rep, _img(55), _img(56)]);
    });

    test('보강 전 문서 — 필드가 아예 없어도 null·[]로 열린다', () {
      final e = _from(_baseDoc());
      expect(e.overview, isNull);
      expect(e.program, isNull);
      expect(e.homepageUrl, isNull);
      expect(e.organizer, isNull);
      expect(e.host, isNull);
      expect(e.contactName, isNull);
      expect(e.feeText, isNull);
      expect(e.playTime, isNull);
      expect(e.eventPlace, isNull);
      expect(e.images, isEmpty);
      expect(e.title, '고양호수예술축제');
      expect(e.tel, '1577-7766');
    });

    test('보강됐지만 원본이 빈 값 — 서버의 null·빈 글자·이상한 타입도 null', () {
      final e = _from({
        ..._baseDoc(),
        'overview': null,
        'program': '   ',
        'homepageUrl': null,
        'organizer': 3,
        'host': null,
        'contactName': '',
        'feeText': null,
        'playTime': null,
        'eventPlace': null,
        'images': [_rep, null, '', 7, '  '],
      });
      expect(e.overview, isNull);
      expect(e.program, isNull);
      expect(e.organizer, isNull);
      expect(e.contactName, isNull);
      expect(e.images, [_rep]);
    });
  });

  group('갤러리 사진', () {
    test('images가 있으면 그것, 없으면 대표 사진, 둘 다 없으면 빈 목록 — 중복 제거', () {
      expect(publicEventGalleryImages(_from(_enrichedDoc())), [_rep, _img(55), _img(56)]);
      expect(publicEventGalleryImages(_from(_baseDoc())), [_rep]);
      expect(
        publicEventGalleryImages(_from({..._baseDoc(), 'imageUrl': null})),
        [_rep.replaceFirst('image2', 'image3')],
        reason: '대표 사진이 없으면 썸네일',
      );
      expect(
        publicEventGalleryImages(
          _from({..._baseDoc(), 'imageUrl': null, 'thumbnailUrl': null}),
        ),
        isEmpty,
      );
      expect(
        publicEventGalleryImages(
          _from(_enrichedDoc(images: [_rep, _img(55), _rep, _img(55), _img(56)])),
        ),
        [_rep, _img(55), _img(56)],
      );
    });

    testWidgets('이미지 10장 — 10장 모두 갤러리에, 원본 주소 그대로', (tester) async {
      _tallView(tester);
      final ten = [_rep, for (var i = 1; i < 10; i++) _img(100 + i)];
      final errors = await _pump(tester, _app(_from(_enrichedDoc(images: ten))));
      expect(errors, isEmpty);
      expect(find.byKey(const ValueKey('publicEventGallery')), findsOneWidget);
      expect(_galleryImages(tester), ten);
      expect(find.text('1 / 10'), findsOneWidget);
      expect(find.byKey(const ValueKey('publicEventImagePlaceholder')), findsNothing);
      expect(find.text('출처: 한국관광공사'), findsOneWidget);
    });

    testWidgets('대표 사진 1장뿐 — 한 장짜리 갤러리', (tester) async {
      _tallView(tester);
      final errors = await _pump(tester, _app(_from(_enrichedDoc(images: [_rep]))));
      expect(errors, isEmpty);
      expect(_galleryImages(tester), [_rep]);
    });

    testWidgets('보강 전 문서 — 기존 imageUrl 한 장', (tester) async {
      _tallView(tester);
      final errors = await _pump(tester, _app(_from(_baseDoc())));
      expect(errors, isEmpty);
      expect(_galleryImages(tester), [_rep]);
    });
  });

  group('상세 내용', () {
    testWidgets('보강 완료 — 순서대로 기간·장소·주소·시간·요금, 소개·프로그램·행사 정보', (tester) async {
      _tallView(tester);
      final errors = await _pump(tester, _app(_from(_enrichedDoc())));
      expect(errors, isEmpty);

      expect(find.text('🎊 공공 축제'), findsOneWidget);
      expect(find.text('2026년 9월 18일 (금) ~ 9월 20일 (일)'), findsOneWidget);
      expect(find.text('일산호수공원'), findsOneWidget);
      expect(
        find.text('경기도 고양시 일산동구 호수로 595 (장항동) 일산호수공원 및 일산문화광장 일원'),
        findsOneWidget,
      );
      expect(find.text('14:00~21:00'), findsOneWidget);
      expect(find.text('무료'), findsOneWidget);

      expect(find.text('축제 소개'), findsOneWidget);
      expect(find.text('일상 속 공간이 특별한 예술의 리듬으로 채워지는 순간이 펼쳐진다.'), findsOneWidget);
      expect(find.text('프로그램'), findsOneWidget);
      expect(find.text('행사 정보'), findsOneWidget);
      expect(find.text('주최'), findsOneWidget);
      expect(find.text('주관'), findsOneWidget);
      expect(find.text('고양문화재단'), findsOneWidget);
      expect(find.text('문의'), findsOneWidget);
      // 문의 = 문의처 이름 + 기존 전화번호. '고양시'는 주최·문의 두 줄.
      expect(find.text('고양시'), findsNWidgets(2));
      expect(find.text('1577-7766'), findsOneWidget);

      // 읽는 순서 — 위에서 아래로.
      double y(Finder f) => tester.getTopLeft(f).dy;
      final order = [
        find.text('🎊 공공 축제'),
        find.text('2026년 9월 18일 (금) ~ 9월 20일 (일)'),
        find.text('일산호수공원'),
        find.text('14:00~21:00'),
        find.text('무료'),
        find.byKey(const ValueKey('publicEventHomepageButton')),
        find.text('축제 소개'),
        find.text('프로그램'),
        find.text('행사 정보'),
        find.text('출처: 한국관광공사'),
      ];
      for (var i = 1; i < order.length; i++) {
        expect(y(order[i]), greaterThan(y(order[i - 1])), reason: '$i번째 순서');
      }

      // 파티츄 호스트 기능·없는 데이터 버튼은 없다.
      for (final t in ['신청', '문의하기', '예매', 'SNS', '동영상', '찜']) {
        expect(find.textContaining(t), findsNothing, reason: t);
      }
    });

    testWidgets('program — 원본 줄바꿈을 그대로 보여준다', (tester) async {
      _tallView(tester);
      await _pump(tester, _app(_from(_enrichedDoc())));
      final program = find.descendant(
        of: find.byKey(const ValueKey('publicEventProgram')),
        matching: find.byType(SelectableText),
      );
      final text = tester.widget<SelectableText>(program).data!;
      expect(text, _program);
      expect(text.split('\n'), [
        '1. 메인프로그램',
        '- 개막식, 축하공연',
        '',
        '2. 부대프로그램',
        '- 먹거리장터',
      ]);
    });

    testWidgets('보강 전 문서 — 예전 상세 그대로(섹션·버튼 없음, 전화는 문의 줄)', (tester) async {
      _tallView(tester);
      final errors = await _pump(tester, _app(_from(_baseDoc())));
      expect(errors, isEmpty);
      expect(find.text('고양호수예술축제'), findsNWidgets(2));
      expect(find.text('2026년 9월 18일 (금) ~ 9월 20일 (일)'), findsOneWidget);
      expect(
        find.text('경기도 고양시 일산동구 호수로 595 (장항동) 일산호수공원 및 일산문화광장 일원'),
        findsOneWidget,
      );
      expect(find.text('1577-7766'), findsOneWidget);
      expect(find.text('출처: 한국관광공사'), findsOneWidget);

      expect(find.byKey(const ValueKey('publicEventOverview')), findsNothing);
      expect(find.byKey(const ValueKey('publicEventProgram')), findsNothing);
      expect(find.byKey(const ValueKey('publicEventHomepageButton')), findsNothing);
      expect(find.byIcon(Icons.schedule_outlined), findsNothing);
      expect(find.byIcon(Icons.payments_outlined), findsNothing);
      expect(find.text('주최'), findsNothing);
      expect(find.text('주관'), findsNothing);
      // 전화번호만 있어도 문의 줄은 나온다.
      expect(find.text('행사 정보'), findsOneWidget);
      expect(find.text('문의'), findsOneWidget);
    });

    testWidgets('일부만 있는 문서 — 없는 줄·섹션만 빠진다', (tester) async {
      _tallView(tester);
      final errors = await _pump(
        tester,
        _app(_from({
          ..._enrichedDoc(),
          'overview': null,
          'host': null,
          'playTime': null,
          'eventPlace': null,
          'tel': null,
          'contactName': null,
          'organizer': null,
        })),
      );
      expect(errors, isEmpty);
      expect(find.byKey(const ValueKey('publicEventOverview')), findsNothing);
      expect(find.byKey(const ValueKey('publicEventProgram')), findsOneWidget);
      expect(find.byKey(const ValueKey('publicEventInfo')), findsNothing, reason: '주최·주관·문의가 모두 없으면 섹션째');
      expect(find.byIcon(Icons.schedule_outlined), findsNothing);
      expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
      // 장소 이름이 없으면 주소만(예전처럼).
      expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
      expect(find.text('일산호수공원'), findsNothing);
    });
  });

  group('공식 홈페이지', () {
    testWidgets('있으면 버튼 — 누르면 그 주소를 외부로 연다', (tester) async {
      _tallView(tester);
      final opened = <Uri>[];
      await _pump(
        tester,
        _app(
          _from(_enrichedDoc()),
          open: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      );
      final button = find.byKey(const ValueKey('publicEventHomepageButton'));
      expect(button, findsOneWidget);
      expect(find.text('공식 홈페이지'), findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expect(opened, [Uri.parse('https://www.goyang.go.kr/festival')]);
      expect(find.text('홈페이지를 열지 못했어요.'), findsNothing);
    });

    testWidgets('열지 못하면 안내만 한다', (tester) async {
      _tallView(tester);
      await _pump(tester, _app(_from(_enrichedDoc()), open: (_) async => false));
      await tester.tap(find.byKey(const ValueKey('publicEventHomepageButton')));
      await tester.pump();
      expect(find.text('홈페이지를 열지 못했어요.'), findsOneWidget);
    });

    testWidgets('없거나 잘못된 주소면 버튼 자체가 없다', (tester) async {
      _tallView(tester);
      for (final bad in [null, '', 'javascript:alert(1)', 'www.no-scheme.kr', 'ftp://x.kr']) {
        await _pump(tester, _app(_from(_enrichedDoc(homepageUrl: bad))));
        expect(
          find.byKey(const ValueKey('publicEventHomepageButton')),
          findsNothing,
          reason: '$bad',
        );
      }
    });

    test('주소 판정', () {
      expect(publicEventHomepageUri('http://www.gdsunsa.com/'), Uri.parse('http://www.gdsunsa.com/'));
      expect(publicEventHomepageUri(' https://yctf.kr/2026samgang '), Uri.parse('https://yctf.kr/2026samgang'));
      expect(publicEventHomepageUri(null), isNull);
      expect(publicEventHomepageUri('https://'), isNull);
      expect(publicEventHomepageUri('mailto:a@b.kr'), isNull);
    });
  });

  // ── 보강 구성 2·3 — 값이 있으면 보여주고 없으면 숨긴다 ─────────────────
  group('보강 구성 2·3', () {
    Map<String, dynamic> fullDoc({
      String? bookingUrl = 'https://tickets.interpark.com/goods/26001234',
      String? homepageUrl = 'https://www.goyang.go.kr/festival',
    }) => {
      ..._enrichedDoc(homepageUrl: homepageUrl),
      'ageLimit': '13세 이상',
      'spendTime': '약 90분',
      'bookingInfo': '인터파크 티켓, 현장 판매',
      'bookingUrl': bookingUrl,
      'discountInfo': '단체 20인 이상 20% 할인',
      'subEvent': '먹거리 장터\n플리마켓',
      'placeInfo': '호수공원 한울광장 일대, 주차는 공영주차장',
      'hostTel': '031-960-9600',
      'festivalGrade': '문화관광축제',
      'performers': '폴킴, 권진아, 옥상달빛',
      'extraInfo': [
        {'title': '관람 안내', 'text': '우천 시 실내로 옮깁니다'},
        {'title': '', 'text': '제목 없는 줄'},
        {'title': '비고', 'text': '선택안함'},
        'bad',
      ],
      'detailSchemaVersion': 3,
    };

    test('모델 — 새 필드를 읽고, 자리표시·잘못된 항목은 버린다', () {
      final e = _from(fullDoc());
      expect(e.ageLimit, '13세 이상');
      expect(e.spendTime, '약 90분');
      expect(e.bookingInfo, '인터파크 티켓, 현장 판매');
      expect(e.bookingUrl, 'https://tickets.interpark.com/goods/26001234');
      expect(e.discountInfo, '단체 20인 이상 20% 할인');
      expect(e.subEvent, '먹거리 장터\n플리마켓');
      expect(e.placeInfo, startsWith('호수공원'));
      expect(e.hostTel, '031-960-9600');
      expect(e.festivalGrade, '문화관광축제');
      expect(e.performers, '폴킴, 권진아, 옥상달빛');
      expect(e.extraInfo.length, 1);
      expect(e.extraInfo.single.title, '관람 안내');

      final blank = _from({
        ..._enrichedDoc(),
        'ageLimit': '선택안함',
        'spendTime': '-',
        'festivalGrade': '선택 안함',
        'bookingInfo': '없음',
        'discountInfo': '해당없음',
        'hostTel': '  ',
        'performers': null,
        'extraInfo': 'not a list',
        'feeText': '선택안함',
      });
      expect(blank.ageLimit, isNull);
      expect(blank.spendTime, isNull);
      expect(blank.festivalGrade, isNull);
      expect(blank.bookingInfo, isNull);
      expect(blank.discountInfo, isNull);
      expect(blank.hostTel, isNull);
      expect(blank.performers, isNull);
      expect(blank.extraInfo, isEmpty);
      expect(blank.feeText, isNull);
    });

    testWidgets('전부 있는 문서 — 줄·섹션·버튼이 읽기 순서대로', (tester) async {
      _tallView(tester);
      final errors = await _pump(tester, _app(_from(fullDoc())));
      expect(errors, isEmpty);

      expect(find.byKey(const ValueKey('publicEventGrade')), findsOneWidget);
      expect(find.text('문화관광축제'), findsOneWidget);
      expect(find.text('관람연령'), findsOneWidget);
      expect(find.text('13세 이상'), findsOneWidget);
      expect(find.text('소요시간'), findsOneWidget);
      expect(find.text('약 90분'), findsOneWidget);
      expect(find.text('할인'), findsOneWidget);
      expect(find.text('단체 20인 이상 20% 할인'), findsOneWidget);
      expect(find.text('예매'), findsOneWidget);
      expect(find.text('인터파크 티켓, 현장 판매'), findsOneWidget);
      expect(find.text('예매하기'), findsOneWidget);
      expect(find.text('호수공원 한울광장 일대, 주차는 공영주차장'), findsOneWidget);
      expect(find.text('🎤 출연진'), findsOneWidget);
      expect(find.text('폴킴, 권진아, 옥상달빛'), findsOneWidget);
      expect(find.text('부대행사'), findsOneWidget);
      expect(find.text('먹거리 장터\n플리마켓'), findsOneWidget);
      expect(find.text('관람 안내'), findsOneWidget);
      expect(find.text('우천 시 실내로 옮깁니다'), findsOneWidget);
      expect(find.text('031-960-9600'), findsOneWidget, reason: '주관 전화');
      expect(find.text('제목 없는 줄'), findsNothing);
      expect(find.text('비고'), findsNothing);

      double y(Finder f) => tester.getTopLeft(f).dy;
      final order = [
        find.text('🎊 공공 축제'),
        find.text('일산호수공원'),
        find.byKey(const ValueKey('publicEventPlaceInfo')),
        find.text('14:00~21:00'),
        find.text('약 90분'),
        find.text('13세 이상'),
        find.text('무료'),
        find.byKey(const ValueKey('publicEventDiscount')),
        find.text('인터파크 티켓, 현장 판매'),
        find.byKey(const ValueKey('publicEventBookingButton')),
        find.byKey(const ValueKey('publicEventHomepageButton')),
        find.text('축제 소개'),
        find.text('🎤 출연진'),
        find.text('프로그램'),
        find.text('부대행사'),
        find.text('관람 안내'),
        find.text('행사 정보'),
        find.text('출처: 한국관광공사'),
      ];
      for (var i = 1; i < order.length; i++) {
        expect(y(order[i]), greaterThan(y(order[i - 1])), reason: '$i번째 순서');
      }
      // 주관 전화는 주관 이름 바로 아래.
      expect(y(find.text('031-960-9600')), greaterThan(y(find.text('고양문화재단'))));
      expect(y(find.text('031-960-9600')), lessThan(y(find.text('문의'))));
    });

    testWidgets('예매하기 — bookingUrl을 외부로 연다(홈페이지와 따로)', (tester) async {
      _tallView(tester);
      final opened = <Uri>[];
      await _pump(
        tester,
        _app(
          _from(fullDoc()),
          open: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('publicEventBookingButton')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('publicEventHomepageButton')));
      await tester.pump();
      expect(opened, [
        Uri.parse('https://tickets.interpark.com/goods/26001234'),
        Uri.parse('https://www.goyang.go.kr/festival'),
      ]);
    });

    testWidgets('예매 링크가 없거나 위험하면 글자만, 버튼 없음', (tester) async {
      _tallView(tester);
      for (final url in [null, 'javascript:alert(1)', 'www.no-scheme.kr']) {
        await _pump(tester, _app(_from(fullDoc(bookingUrl: url))));
        expect(find.text('인터파크 티켓, 현장 판매'), findsOneWidget, reason: '$url');
        expect(find.byKey(const ValueKey('publicEventBookingButton')), findsNothing, reason: '$url');
      }
    });

    testWidgets('예전 보강 문서(새 필드 없음) — 새 줄·섹션이 하나도 없다', (tester) async {
      _tallView(tester);
      final errors = await _pump(tester, _app(_from(_enrichedDoc())));
      expect(errors, isEmpty);
      for (final k in [
        'publicEventGrade',
        'publicEventPlaceInfo',
        'publicEventDiscount',
        'publicEventBookingButton',
        'publicEventPerformers',
        'publicEventSubEvent',
        'publicEventExtra0',
      ]) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
      for (final t in ['관람연령', '소요시간', '예매', '할인', '🎤 출연진', '부대행사']) {
        expect(find.text(t), findsNothing, reason: t);
      }
      expect(find.byIcon(Icons.timer_outlined), findsNothing);
      expect(find.byIcon(Icons.person_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.confirmation_number_outlined), findsNothing);
    });

    testWidgets('자리표시 값(선택안함·-·없음)은 화면에 나오지 않는다', (tester) async {
      _tallView(tester);
      await _pump(
        tester,
        _app(_from({
          ..._enrichedDoc(),
          'ageLimit': '선택안함',
          'festivalGrade': '선택안함',
          'spendTime': '-',
          'bookingInfo': '없음',
        })),
      );
      expect(find.textContaining('선택안함'), findsNothing);
      expect(find.text('-'), findsNothing);
      expect(find.text('없음'), findsNothing);
      expect(find.byKey(const ValueKey('publicEventGrade')), findsNothing);
    });

    test('홈페이지 버튼 문구 — 인스타그램·블로그·카페·그 외', () {
      String label(String url) => publicEventHomepageLabel(Uri.parse(url));
      expect(label('https://www.instagram.com/seoulbusking/'), '공식 인스타그램');
      expect(label('https://instagram.com/x'), '공식 인스타그램');
      expect(label('https://blog.naver.com/official_namdang'), '공식 블로그');
      expect(label('https://m.blog.naver.com/official_namdang'), '공식 블로그');
      expect(label('https://cafe.naver.com/some'), '공식 카페');
      expect(label('https://m.cafe.naver.com/some'), '공식 카페');
      expect(label('https://www.gjfac.org/'), '공식 홈페이지');
      expect(label('https://naver.com/'), '공식 홈페이지');
      expect(label('https://notinstagram.com/'), '공식 홈페이지');
    });

    testWidgets('인스타그램 주소면 버튼이 「공식 인스타그램」', (tester) async {
      _tallView(tester);
      await _pump(
        tester,
        _app(_from(fullDoc(homepageUrl: 'https://www.instagram.com/seoulbusking/'))),
      );
      expect(find.text('공식 인스타그램'), findsOneWidget);
      expect(find.text('공식 홈페이지'), findsNothing);
    });
  });
}
