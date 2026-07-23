import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/party_detail_block.dart';

void main() {
  group('PartyDetailBlock 라운드트립', () {
    test('heading', () {
      const b = PartyDetailBlock(id: '1', type: PartyDetailBlockType.heading, text: '제목');
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.id, '1');
      expect(restored.type, PartyDetailBlockType.heading);
      expect(restored.text, '제목');
    });

    test('subheading', () {
      const b = PartyDetailBlock(id: '2', type: PartyDetailBlockType.subheading, text: '소제목');
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.type, PartyDetailBlockType.subheading);
      expect(restored.text, '소제목');
    });

    test('paragraph', () {
      const b = PartyDetailBlock(id: '3', type: PartyDetailBlockType.paragraph, text: '본문 내용');
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.type, PartyDetailBlockType.paragraph);
      expect(restored.text, '본문 내용');
    });

    test('notice', () {
      const b = PartyDetailBlock(id: '4', type: PartyDetailBlockType.notice, text: '외부 음식 반입 불가');
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.type, PartyDetailBlockType.notice);
      expect(restored.text, '외부 음식 반입 불가');
    });

    test('image (모든 필드)', () {
      const b = PartyDetailBlock(
        id: '5',
        type: PartyDetailBlockType.image,
        imageUrl: 'https://example.com/a.jpg',
        imageWidth: 1200,
        imageHeight: 1600,
        caption: '입구 사진',
      );
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.type, PartyDetailBlockType.image);
      expect(restored.imageUrl, 'https://example.com/a.jpg');
      expect(restored.imageWidth, 1200);
      expect(restored.imageHeight, 1600);
      expect(restored.caption, '입구 사진');
    });

    test('image (선택 필드 없이)', () {
      const b = PartyDetailBlock(
        id: '6',
        type: PartyDetailBlockType.image,
        imageUrl: 'https://example.com/b.jpg',
      );
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.imageUrl, 'https://example.com/b.jpg');
      expect(restored.imageWidth, isNull);
      expect(restored.imageHeight, isNull);
      expect(restored.caption, isNull);
    });

    test('divider', () {
      const b = PartyDetailBlock(id: '7', type: PartyDetailBlockType.divider);
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.type, PartyDetailBlockType.divider);
    });
  });

  group('알 수 없는 type 안전 처리', () {
    test('unknown으로 분류되고 원본 데이터가 보존된다', () {
      final raw = {'id': 'x', 'type': 'faceRecognition', 'videoUrl': 'https://example.com/v.mp4', 'extra': 123};
      final block = PartyDetailBlock.fromMap(raw);
      expect(block.type, PartyDetailBlockType.unknown);
      expect(block.rawUnknown, isNotNull);
      expect(block.rawUnknown!['type'], 'faceRecognition');
      expect(block.rawUnknown!['videoUrl'], 'https://example.com/v.mp4');
      expect(block.rawUnknown!['extra'], 123);
    });

    test('재직렬화해도 원본과 동일하게 복원된다', () {
      final raw = {'id': 'x', 'type': 'faceRecognition', 'question': 'Q', 'answer': 'A'};
      final block = PartyDetailBlock.fromMap(raw);
      final restored = PartyDetailBlock.fromMap(block.toMap());
      expect(restored.type, PartyDetailBlockType.unknown);
      expect(restored.rawUnknown!['type'], 'faceRecognition');
      expect(restored.rawUnknown!['question'], 'Q');
      expect(restored.rawUnknown!['answer'], 'A');
    });
  });

  group('필드 누락/타입 불일치 시 크래시 방지', () {
    test('빈 맵', () {
      final block = PartyDetailBlock.fromMap({});
      expect(block.id, isNotEmpty);
      expect(block.type, PartyDetailBlockType.unknown);
    });

    test('type만 있고 text 없음', () {
      final block = PartyDetailBlock.fromMap({'type': 'heading'});
      expect(block.type, PartyDetailBlockType.heading);
      expect(block.text, '');
    });

    test('type이 문자열이 아님', () {
      final block = PartyDetailBlock.fromMap({'type': 123});
      expect(block.type, PartyDetailBlockType.unknown);
    });

    test('id가 문자열이 아님 — 안전하게 문자열로 변환', () {
      final block = PartyDetailBlock.fromMap({'id': 456, 'type': 'image'});
      expect(block.id, '456');
      expect(block.type, PartyDetailBlockType.image);
    });
  });

  group('listFromDynamic 방어', () {
    test('null이면 빈 리스트 (detailBlocks 없는 기존 파티 문서)', () {
      expect(PartyDetailBlock.listFromDynamic(null), isEmpty);
    });

    test('List가 아니면 빈 리스트', () {
      expect(PartyDetailBlock.listFromDynamic('not a list'), isEmpty);
    });

    test('잘못된 원소는 조용히 건너뛰고 유효한 것만 파싱', () {
      final result = PartyDetailBlock.listFromDynamic([
        1,
        'x',
        {'type': 'divider'},
      ]);
      expect(result, hasLength(1));
      expect(result.first.type, PartyDetailBlockType.divider);
    });
  });

  group('순서 보존', () {
    test('listFromDynamic → listToMaps → listFromDynamic 왕복 후에도 순서 유지', () {
      final original = [
        const PartyDetailBlock(id: '1', type: PartyDetailBlockType.divider),
        const PartyDetailBlock(id: '2', type: PartyDetailBlockType.heading, text: '제목'),
        const PartyDetailBlock(id: '3', type: PartyDetailBlockType.image, imageUrl: 'u'),
        const PartyDetailBlock(id: '4', type: PartyDetailBlockType.notice, text: '주의'),
      ];
      final round1 = PartyDetailBlock.listFromDynamic(PartyDetailBlock.listToMaps(original));
      final round2 = PartyDetailBlock.listFromDynamic(PartyDetailBlock.listToMaps(round1));
      expect(round2.map((b) => b.type).toList(), [
        PartyDetailBlockType.divider,
        PartyDetailBlockType.heading,
        PartyDetailBlockType.image,
        PartyDetailBlockType.notice,
      ]);
    });
  });

  group('checklist 블록', () {
    test('라운드트립', () {
      const b = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.checklist,
        checklist: PartyDetailChecklistPayload(
          title: '이런 점이 좋아요',
          items: ['웰컴드링크 제공', '남녀 성비 관리', '전문 진행자 운영'],
        ),
      );
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.type, PartyDetailBlockType.checklist);
      expect(restored.checklist!.title, '이런 점이 좋아요');
      expect(restored.checklist!.items, ['웰컴드링크 제공', '남녀 성비 관리', '전문 진행자 운영']);
    });

    test('제목 없이도 저장/복원된다', () {
      const b = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.checklist,
        checklist: PartyDetailChecklistPayload(items: ['주차 가능']),
      );
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.checklist!.title, isNull);
      expect(restored.checklist!.items, ['주차 가능']);
    });

    test('빈/공백 항목은 파싱 시 걸러진다', () {
      final raw = {
        'id': '1',
        'type': 'checklist',
        'items': ['좋아요', '', '  ', null, 123],
      };
      final block = PartyDetailBlock.fromMap(raw);
      expect(block.checklist!.items, ['좋아요', '123']);
    });

    test('items가 List가 아니면 크래시 없이 빈 리스트로 처리한다', () {
      final block = PartyDetailBlock.fromMap({'id': '1', 'type': 'checklist', 'items': 'oops'});
      expect(block.checklist!.items, isEmpty);
    });
  });

  group('FAQ 블록', () {
    test('라운드트립 + 항목 순서 유지', () {
      const b = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.faq,
        faq: PartyDetailFaqPayload(
          title: '자주 묻는 질문',
          items: [
            PartyDetailFaqItem(id: 'a', question: '혼자 가도 되나요?', answer: '네, 혼자 오시는 분이 많습니다.'),
            PartyDetailFaqItem(id: 'b', question: '주차 되나요?', answer: '네.'),
          ],
        ),
      );
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.faq!.title, '자주 묻는 질문');
      expect(restored.faq!.items.map((i) => i.question).toList(), ['혼자 가도 되나요?', '주차 되나요?']);
      expect(restored.faq!.items.map((i) => i.answer).toList(), ['네, 혼자 오시는 분이 많습니다.', '네.']);
    });

    test('질문/답변이 모두 빈 쌍은 안전하게 제외된다', () {
      final raw = {
        'id': '1',
        'type': 'faq',
        'items': [
          {'question': 'Q1', 'answer': 'A1'},
          {'question': '', 'answer': ''},
          {'question': '  ', 'answer': ''},
        ],
      };
      final block = PartyDetailBlock.fromMap(raw);
      expect(block.faq!.items, hasLength(1));
      expect(block.faq!.items.first.question, 'Q1');
    });

    test('items 원소가 Map이 아니어도 크래시 없이 건너뛴다', () {
      final block = PartyDetailBlock.fromMap({
        'id': '1',
        'type': 'faq',
        'items': ['not a map', 42, null],
      });
      expect(block.faq!.items, isEmpty);
    });
  });

  group('타임라인 블록', () {
    test('라운드트립 + 순서 유지', () {
      const b = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.timeline,
        timeline: PartyDetailTimelinePayload(
          title: '진행 일정',
          items: [
            PartyDetailTimelineItem(id: 'a', time: '19:00', title: '입장 및 웰컴드링크', description: '간단한 안내 후 입장합니다.'),
            PartyDetailTimelineItem(id: 'b', time: '20:00', title: 'BBQ 파티', description: ''),
          ],
        ),
      );
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.timeline!.items.map((i) => i.time).toList(), ['19:00', '20:00']);
      expect(restored.timeline!.items[0].description, '간단한 안내 후 입장합니다.');
      expect(restored.timeline!.items[1].description, '');
    });

    test('시간/제목/설명이 모두 빈 항목은 제외된다', () {
      final raw = {
        'id': '1',
        'type': 'timeline',
        'items': [
          {'time': '19:00', 'title': '입장', 'description': ''},
          {'time': '', 'title': '', 'description': ''},
        ],
      };
      final block = PartyDetailBlock.fromMap(raw);
      expect(block.timeline!.items, hasLength(1));
    });
  });

  group('정보 카드 블록', () {
    test('라운드트립', () {
      const b = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.infoCard,
        infoCard: PartyDetailInfoCardPayload(title: '준비물', text: '신분증을 반드시 지참해주세요.', icon: 'badge'),
      );
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.infoCard!.title, '준비물');
      expect(restored.infoCard!.text, '신분증을 반드시 지참해주세요.');
      expect(restored.infoCard!.icon, 'badge');
    });

    test('허용되지 않은 아이콘 이름은 크래시 없이 null로 대체된다', () {
      final block = PartyDetailBlock.fromMap({
        'id': '1',
        'type': 'infoCard',
        'title': '제목',
        'text': '본문',
        'icon': 'not_a_real_icon',
      });
      expect(block.infoCard!.icon, isNull);
    });

    test('7개 아이콘 후보 모두 유효하게 저장/복원된다', () {
      for (final name in partyDetailInfoCardIconNames) {
        final block = PartyDetailBlock.fromMap({'id': '1', 'type': 'infoCard', 'title': 't', 'text': 'x', 'icon': name});
        expect(block.infoCard!.icon, name);
      }
    });
  });

  group('동영상 블록', () {
    test('라운드트립(모든 필드)', () {
      const b = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.video,
        video: PartyDetailVideoPayload(
          videoUid: 'uid-1',
          videoUrl: 'https://example.com/v.m3u8',
          thumbnailUrl: 'https://example.com/thumb.jpg',
          aspectRatio: 0.5625,
          caption: '입장 영상',
        ),
      );
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.video!.videoUid, 'uid-1');
      expect(restored.video!.videoUrl, 'https://example.com/v.m3u8');
      expect(restored.video!.thumbnailUrl, 'https://example.com/thumb.jpg');
      expect(restored.video!.aspectRatio, 0.5625);
      expect(restored.video!.caption, '입장 영상');
    });

    test('선택 필드 없이도 안전하게 라운드트립된다', () {
      const b = PartyDetailBlock(
        id: '1',
        type: PartyDetailBlockType.video,
        video: PartyDetailVideoPayload(videoUrl: 'https://example.com/v.m3u8'),
      );
      final restored = PartyDetailBlock.fromMap(b.toMap());
      expect(restored.video!.videoUrl, 'https://example.com/v.m3u8');
      expect(restored.video!.videoUid, isNull);
      expect(restored.video!.thumbnailUrl, isNull);
      expect(restored.video!.aspectRatio, isNull);
      expect(restored.video!.caption, isNull);
    });
  });

  group('확장 블록 공통 안전성', () {
    test('필드가 통째로 누락돼도 크래시 없이 빈 payload를 만든다', () {
      for (final type in ['checklist', 'faq', 'timeline', 'infoCard', 'video']) {
        final block = PartyDetailBlock.fromMap({'id': '1', 'type': type});
        expect(block.type.name, type);
      }
    });

    test('기존 6종과 새 5종이 섞인 배열도 순서를 그대로 유지한다', () {
      final raw = [
        {'id': '1', 'type': 'heading', 'text': '제목'},
        {'id': '2', 'type': 'checklist', 'items': ['a']},
        {'id': '3', 'type': 'image', 'imageUrl': 'u'},
        {'id': '4', 'type': 'video', 'videoUrl': 'v'},
        {'id': '5', 'type': 'faq', 'items': [{'question': 'q', 'answer': 'a'}]},
      ];
      final blocks = PartyDetailBlock.listFromDynamic(raw);
      expect(blocks.map((b) => b.type).toList(), [
        PartyDetailBlockType.heading,
        PartyDetailBlockType.checklist,
        PartyDetailBlockType.image,
        PartyDetailBlockType.video,
        PartyDetailBlockType.faq,
      ]);
    });
  });
}
