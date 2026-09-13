// 이벤트(placePromotions)의 **문의 설정**과 **대표 미디어**가 저장·복원되는
// 규칙. 두 가지를 한 파일에서 보는 이유는 둘 다 "기존 문서를 깨지 않는가"가
// 핵심이라서다 — 필드가 없던 옛 이벤트가 그대로 읽혀야 한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_inquiry_notice.dart';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/widgets/party_media_editor.dart' show PartyCoverPick;

PlacePromotion _promo(Map<String, dynamic> d) =>
    PlacePromotion.fromMap('promo1', d);

void main() {
  group('InquiryTarget.event', () {
    test('플레이스와 다른 relatedType을 쓴다 — 방이 섞이지 않는다', () {
      expect(InquiryTarget.event.relatedType, 'event');
      expect(InquiryTarget.event.collection, 'placePromotions');
      // place(events/places)와 값이 겹치면 호스트 목록에서 구분되지 않는다.
      expect(
        InquiryTarget.event.relatedType,
        isNot(InquiryTarget.place.relatedType),
      );
    });

    test('기존 세 대상의 값은 그대로다 — 기존 채팅방이 갈라지지 않는다', () {
      expect(InquiryTarget.party.relatedType, 'party');
      expect(InquiryTarget.place.relatedType, 'place');
      expect(InquiryTarget.rental.relatedType, 'place');
    });

    // ── 앱↔서버 드리프트 가드 ────────────────────────────────────────────
    // 컬렉션을 실제로 고르는 쪽은 **서버**다(functions/chatRooms.js의
    // LISTING_COLLECTIONS). 앱의 InquiryTarget이 서버 표에 없는 relatedType을
    // 보내면 콜러블이 invalid-argument로 막아 문의가 통째로 죽는다. 주석으로만
    // "같아야 한다"고 적어 두면 한쪽만 고쳐지므로 **파일을 직접 읽어** 대조한다.
    test('모든 InquiryTarget이 서버 LISTING_COLLECTIONS에 있다', () {
      final source = File(
        '../functions/chatRooms.js',
      ).readAsStringSync();
      final table = RegExp(
        r'const LISTING_COLLECTIONS = \{(.*?)\n\};',
        dotAll: true,
      ).firstMatch(source);
      expect(table, isNotNull, reason: '서버의 LISTING_COLLECTIONS를 찾지 못했다');

      final body = table!.group(1)!;
      final entries = <String, List<String>>{};
      for (final m in RegExp(
        r'^\s*(\w+):\s*\[([^\]]*)\]',
        multiLine: true,
      ).allMatches(body)) {
        entries[m.group(1)!] = m
            .group(2)!
            .split(',')
            .map((s) => s.trim().replaceAll(RegExp("['\"]"), ''))
            .where((s) => s.isNotEmpty)
            .toList();
      }
      expect(entries, isNotEmpty, reason: '서버 표를 파싱하지 못했다');

      for (final target in InquiryTarget.values) {
        final collections = entries[target.relatedType];
        expect(
          collections,
          isNotNull,
          reason:
              '앱이 보내는 relatedType "${target.relatedType}"(${target.name})가 '
              '서버 표에 없다 — createChatRoom이 invalid-argument로 막는다',
        );
        expect(
          collections,
          contains(target.collection),
          reason:
              '${target.name}의 컬렉션(${target.collection})이 서버 표'
              '($collections)와 어긋난다',
        );
      }
    });

    test('이벤트는 서버 표에서 placePromotions 하나만 본다', () {
      final source = File('../functions/chatRooms.js').readAsStringSync();
      expect(source.contains("event: ['placePromotions']"), isTrue);
      // place가 placePromotions까지 뒤지게 되면 방이 섞인다.
      expect(source.contains("place: ['events', 'places']"), isTrue);
    });
  });

  group('EventInquiryNotice — OFF 안내', () {
    test('프리셋 키는 저장값이라 바뀌면 안 된다', () {
      expect(EventInquiryNotice.visitToAsk.key, 'visit_to_ask');
      expect(EventInquiryNotice.visitAll.key, 'visit_all');
      expect(EventInquiryNotice.noInquiryNeeded.key, 'no_inquiry_needed');
      expect(EventInquiryNotice.custom.key, 'custom');
    });

    test('모르는 키·없는 값은 기본 프리셋으로 읽는다', () {
      expect(EventInquiryNoticeFields.noticeOf(null), EventInquiryNotice.visitToAsk);
      expect(
        EventInquiryNoticeFields.noticeOf({'inquiryOffNotice': '뭔가이상한값'}),
        EventInquiryNotice.visitToAsk,
      );
    });

    test('문의를 켜면 OFF 안내 두 필드를 지운다', () {
      final map = EventInquiryNoticeFields.toMap(
        inquiryEnabled: true,
        notice: EventInquiryNotice.custom,
        customText: '전화로만 받아요',
      );
      expect(map['inquiryOffNotice'], isNull);
      expect(map['inquiryOffNoticeText'], isNull);
    });

    test('프리셋을 고르면 직접입력 문구는 함께 지운다', () {
      final map = EventInquiryNoticeFields.toMap(
        inquiryEnabled: false,
        notice: EventInquiryNotice.visitAll,
        customText: '예전에 적어둔 글',
      );
      expect(map['inquiryOffNotice'], 'visit_all');
      expect(map['inquiryOffNoticeText'], '');
    });

    test('직접 입력은 상한으로 자른다', () {
      final long = 'ㄱ' * (EventInquiryNoticeFields.maxTextLength + 30);
      final map = EventInquiryNoticeFields.toMap(
        inquiryEnabled: false,
        notice: EventInquiryNotice.custom,
        customText: long,
      );
      expect(
        (map['inquiryOffNoticeText'] as String).length,
        EventInquiryNoticeFields.maxTextLength,
      );
    });

    test('직접 입력인데 문구가 비면 보여줄 것이 없다', () {
      final text = EventInquiryNoticeFields.displayTextOf({
        'inquiryOffNotice': 'custom',
        'inquiryOffNoticeText': '   ',
      });
      expect(text, '');
    });
  });

  group('PlacePromotion — 문의 설정', () {
    test('필드가 없던 옛 이벤트는 문의가 켜진 것으로 읽힌다', () {
      final p = _promo({'title': '옛 이벤트'});
      expect(p.inquiryEnabled, isTrue);
      expect(p.showsInquiryButton, isTrue);
      // 켜져 있으면 OFF 안내는 보여줄 것이 없다.
      expect(p.inquiryOffText, '');
    });

    test('끄면 고른 프리셋 문구가 버튼 자리에 온다', () {
      final p = _promo({
        'inquiryEnabled': false,
        'inquiryOffNotice': 'no_inquiry_needed',
      });
      expect(p.showsInquiryButton, isFalse);
      expect(p.inquiryOffText, '별도 문의 없이 이용 가능');
    });

    test('직접 입력을 고르면 적어둔 문구가 온다', () {
      final p = _promo({
        'inquiryEnabled': false,
        'inquiryOffNotice': 'custom',
        'inquiryOffNoticeText': '예약은 전화로만 받아요',
      });
      expect(p.inquiryOffText, '예약은 전화로만 받아요');
    });

    test('저장 → 복원이 값을 보존한다', () {
      final saved = _promo({
        'inquiryEnabled': false,
        'inquiryOffNotice': 'visit_all',
      }).toMap();
      final back = _promo(Map<String, dynamic>.from(saved));
      expect(back.inquiryEnabled, isFalse);
      expect(back.inquiryOffNotice, EventInquiryNotice.visitAll);
    });

    test('문서에 쓰는 ON/OFF 필드는 공용 필드명 하나다', () {
      final map = _promo({'inquiryEnabled': false}).toMap();
      expect(map.containsKey(ListingInquiry.field), isTrue);
      // 기존 세 도메인의 "문의 전 안내"는 건드리지 않는다.
      expect(map.containsKey(ListingInquiry.guideField), isFalse);
    });
  });

  group('PlacePromotion — 대표 미디어', () {
    test('지정이 없는 옛 이벤트: 사진이 있으면 대표는 사진이다', () {
      final p = _promo({
        'imageUrls': ['a.jpg', 'b.jpg'],
        'videoUrl': 'v.m3u8',
      });
      expect(p.coverIsVideo, isFalse);
    });

    test('지정이 없고 사진이 하나도 없으면 동영상이 대표다 (기존 규칙)', () {
      final p = _promo({'imageUrls': <String>[], 'videoUrl': 'v.m3u8'});
      expect(p.coverIsVideo, isTrue);
    });

    test('미디어가 아예 없어도 안전하다', () {
      final p = _promo({'title': '미디어 없는 이벤트'});
      expect(p.coverIsVideo, isFalse);
      expect(p.allImageUrls, isEmpty);
      expect(p.hasVideo, isFalse);
    });

    test('대표를 동영상으로 지정하면 그대로 읽는다', () {
      final p = _promo({
        'imageUrls': ['a.jpg'],
        'videoUrl': 'v.m3u8',
        'coverMediaType': 'video',
        'coverVideoUrl': 'v.m3u8',
      });
      expect(p.coverIsVideo, isTrue);
    });

    test('대표가 video인데 영상이 없어졌으면 동영상 대표로 보지 않는다', () {
      final p = _promo({
        'imageUrls': ['a.jpg'],
        'coverMediaType': 'video',
      });
      expect(p.coverIsVideo, isFalse);
    });

    test('크롭 표는 저장·복원된다', () {
      final p = _promo({
        'basicCardPhotoCrops': {
          'a.jpg': {'x': 0.2, 'y': 0.8, 'scale': 1.5},
        },
      });
      expect(p.basicCardPhotoCrops['a.jpg'], {
        'x': 0.2,
        'y': 0.8,
        'scale': 1.5,
      });
    });

    test('모양이 깨진 크롭 값은 버리고 나머지는 읽는다', () {
      final p = _promo({
        'basicCardPhotoCrops': {
          'a.jpg': '문자열이라 잘못됨',
          'b.jpg': {'x': 0.3},
        },
      });
      expect(p.basicCardPhotoCrops.containsKey('a.jpg'), isFalse);
      expect(p.basicCardPhotoCrops['b.jpg'], {
        'x': 0.3,
        'y': 0.5,
        'scale': 1.0,
      });
    });

    test('대표 필드명은 파티·플레이스와 같다 — 읽는 함수가 하나다', () {
      final map = _promo({'coverMediaType': 'image'}).toMap();
      for (final key in [
        'coverMediaType',
        'coverImageUrl',
        'coverVideoUrl',
        'coverVideoUid',
        'coverThumbnailUrl',
        'basicCardPhotoCrops',
      ]) {
        expect(map.containsKey(key), isTrue, reason: '$key가 빠졌다');
      }
    });
  });

  group('MediaUploadService.resolveCoverFields', () {
    test('고르지 않으면 사진 우선', () {
      final c = MediaUploadService.resolveCoverFields(
        coverPick: null,
        imageUrls: ['a.jpg', 'b.jpg'],
        uploadedImageUrls: const [],
        videoUrl: 'v.m3u8',
      );
      expect(c['coverMediaType'], 'image');
      expect(c['coverImageUrl'], 'a.jpg');
    });

    test('고르지 않았고 사진이 없으면 동영상', () {
      final c = MediaUploadService.resolveCoverFields(
        coverPick: null,
        imageUrls: const [],
        uploadedImageUrls: const [],
        videoUrl: 'v.m3u8',
        videoUid: 'uid1',
      );
      expect(c['coverMediaType'], 'video');
      expect(c['coverVideoUrl'], 'v.m3u8');
      expect(c['coverVideoUid'], 'uid1');
    });

    test('기존 사진을 대표로 고르면 그 URL이 대표다', () {
      final c = MediaUploadService.resolveCoverFields(
        coverPick: const PartyCoverPick(existingImageUrl: 'b.jpg'),
        imageUrls: ['a.jpg', 'b.jpg'],
        uploadedImageUrls: const [],
      );
      expect(c['coverImageUrl'], 'b.jpg');
    });

    test('새로 올린 n번째 사진을 대표로 고르면 그 순번의 URL이 온다', () {
      final c = MediaUploadService.resolveCoverFields(
        coverPick: const PartyCoverPick(newImageOrdinal: 1),
        imageUrls: ['old.jpg', 'new0.jpg', 'new1.jpg'],
        uploadedImageUrls: ['new0.jpg', 'new1.jpg'],
      );
      expect(c['coverImageUrl'], 'new1.jpg');
    });

    test('순번이 범위를 넘으면 첫 사진으로 되돌린다 — 대표가 비지 않는다', () {
      final c = MediaUploadService.resolveCoverFields(
        coverPick: const PartyCoverPick(newImageOrdinal: 9),
        imageUrls: ['a.jpg'],
        uploadedImageUrls: const [],
      );
      expect(c['coverImageUrl'], 'a.jpg');
    });

    test('동영상을 대표로 골랐는데 영상이 지워졌으면 사진으로 되돌린다', () {
      final c = MediaUploadService.resolveCoverFields(
        coverPick: const PartyCoverPick(isExistingVideo: true),
        imageUrls: ['a.jpg'],
        uploadedImageUrls: const [],
        videoUrl: null,
      );
      expect(c['coverMediaType'], 'image');
      expect(c['coverImageUrl'], 'a.jpg');
    });

    test('미디어가 하나도 없으면 대표도 비어 있다', () {
      final c = MediaUploadService.resolveCoverFields(
        coverPick: null,
        imageUrls: const [],
        uploadedImageUrls: const [],
      );
      expect(c['coverImageUrl'], isNull);
      expect(c['coverVideoUrl'], isNull);
    });
  });
}
