// 승인제 파티의 **프로필 사진 제출은 호스트 선택 옵션**이다.
//
// 예전에는 승인제로 설정하기만 하면 신청 화면에 사진 제출 칸이 떴다. 호스트가
// 요청한 적도 없는데 신청자에게 얼굴 사진을 요구하는 셈이었고, 정작 등록/수정
// 화면에는 그걸 끌 방법이 없었다.
//
// 이제 판정은 `requireApplicantPhotos` 한 필드다.
//  · 필드가 없으면 OFF — 기존 승인제 파티는 예전처럼 사진 없이 신청된다.
//  · 사전질문과 **완전히 독립** — 넷 중 어떤 조합도 가능하다.
//  · 즉시확정 파티에는 옵션도 사진 요구도 없다.
//
// 다만 **호스트 심사 화면의 표시 조건만은 옵션이 아니다.** 옵션을 끄면 신규
// 신청자에게는 제출 칸이 사라지지만, 이미 제출된 사진은 그대로 보인다 —
// 파일도 신청 문서의 photos도 지우지 않으니 화면에서만 감추면 호스트에게는
// 제출물이 사라진 것처럼 보인다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_application_form.dart';

void main() {
  Map<String, dynamic> party({
    String mode = 'manual',
    List<Map<String, dynamic>>? questions,
    bool? requirePhotos,
  }) => {
    'applicationApprovalMode': mode,
    'applicationQuestions': ?questions,
    kRequireApplicantPhotosField: ?requirePhotos,
  };

  List<Map<String, dynamic>> oneQuestion() => [
    {'id': 'q1', 'text': '참여 이유가 무엇인가요?', 'required': true, 'order': 0},
  ];

  group('필드 읽기', () {
    test('필드 이름은 앱과 서버가 같은 값을 쓴다', () {
      expect(kRequireApplicantPhotosField, 'requireApplicantPhotos');
    });

    test('기존 승인제 파티 — 필드가 없으면 OFF', () {
      final form = PartyApplicationForm.fromParty(party());
      expect(form.requiresApproval, isTrue);
      expect(form.requirePhotos, isFalse);
      expect(form.requiresPhotos, isFalse);
    });

    test('호스트가 켰으면 ON', () {
      final form = PartyApplicationForm.fromParty(party(requirePhotos: true));
      expect(form.requiresPhotos, isTrue);
    });

    test('호스트가 껐으면 OFF', () {
      final form = PartyApplicationForm.fromParty(party(requirePhotos: false));
      expect(form.requiresPhotos, isFalse);
    });

    test('즉시확정 파티는 플래그가 남아 있어도 요구하지 않는다', () {
      final form = PartyApplicationForm.fromParty(
        party(mode: 'auto', requirePhotos: true),
      );
      expect(form.requiresApproval, isFalse);
      expect(form.requiresPhotos, isFalse);
      expect(form.needsSubmissionStep, isFalse);
    });

    test('일반(필드 자체가 없는) 파티도 그대로 즉시확정이다', () {
      final form = PartyApplicationForm.fromParty(const {});
      expect(form.requiresApproval, isFalse);
      expect(form.requiresPhotos, isFalse);
      expect(form.needsSubmissionStep, isFalse);
    });

    test('수정 화면이 저장된 값을 그대로 불러온다', () {
      // 저장 → 다시 읽기. 화면은 이 값을 그대로 토글 상태로 쓴다.
      for (final saved in [true, false]) {
        final form = PartyApplicationForm.fromParty(
          party(questions: oneQuestion(), requirePhotos: saved),
        );
        expect(form.requirePhotos, saved, reason: '$saved');
        expect(form.questions.length, 1);
      }
    });
  });

  group('사전질문과 사진은 독립이다', () {
    test('질문 있음 + 사진 OFF → 질문만 받는다', () {
      final form = PartyApplicationForm.fromParty(
        party(questions: oneQuestion(), requirePhotos: false),
      );
      expect(form.hasQuestions, isTrue);
      expect(form.requiresPhotos, isFalse);
      expect(form.needsSubmissionStep, isTrue);
    });

    test('질문 없음 + 사진 ON → 사진만 받는다', () {
      final form = PartyApplicationForm.fromParty(party(requirePhotos: true));
      expect(form.hasQuestions, isFalse);
      expect(form.requiresPhotos, isTrue);
      expect(form.needsSubmissionStep, isTrue);
    });

    test('질문 있음 + 사진 ON → 둘 다 받는다', () {
      final form = PartyApplicationForm.fromParty(
        party(questions: oneQuestion(), requirePhotos: true),
      );
      expect(form.hasQuestions, isTrue);
      expect(form.requiresPhotos, isTrue);
      expect(form.needsSubmissionStep, isTrue);
    });

    test('질문 없음 + 사진 OFF → 제출 화면 자체를 건너뛴다', () {
      final form = PartyApplicationForm.fromParty(party());
      expect(form.requiresApproval, isTrue, reason: '승인제인 것은 맞다');
      expect(form.needsSubmissionStep, isFalse, reason: '받을 게 없으면 안 묻는다');
    });
  });

  group('"승인제니까 사진"으로 판정하는 곳이 없다', () {
    String read(String path) => File(path).readAsStringSync();

    /// 주석을 걷어낸 코드만 — 설명 문구에 남은 옛 이름까지 잡으면 안 된다.
    String code(String path) => read(
      path,
    ).split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

    test('신청 흐름은 needsSubmissionStep으로만 연다', () {
      final src = code('lib/screens/party_detail_screen.dart');
      expect(src.contains('form.needsSubmissionStep'), isTrue);
      expect(
        src.contains('form.requiresApproval'),
        isFalse,
        reason: '승인제 자체로 제출 화면을 열면 안 된다',
      );
    });

    test('제출 화면의 사진 칸은 requiresPhotos로만 열린다', () {
      final src = read('lib/screens/party_application_answer_screen.dart');
      expect(src.contains('widget.form.requiresPhotos'), isTrue);
      expect(src.contains('_photosRequested'), isTrue);
    });

    test('등록·수정 화면 둘 다 같은 옵션을 들고 있다', () {
      for (final path in [
        'lib/screens/party_register_screen.dart',
        'lib/screens/party_edit_screen.dart',
      ]) {
        final src = read(path);
        expect(src.contains('_requireApplicantPhotos'), isTrue, reason: path);
        expect(
          src.contains('requirePhotos: _requireApplicantPhotos'),
          isTrue,
          reason: '$path — 시트/저장에 값을 넘겨야 한다',
        );
      }
    });

    test('호스트 심사 화면은 옵션이 아니라 저장된 사진으로 영역을 연다', () {
      // 옵션을 끄면 신규 신청자에게는 제출 칸이 사라지지만, 이미 받아 둔
      // 사진은 계속 심사할 수 있어야 한다. 파일도 문서도 지우지 않으므로
      // 화면에서만 감추는 것은 "없어진 것처럼 보이는" 상태를 만든다.
      final src = code('lib/screens/party_applicants_screen.dart');
      expect(
        src.contains('final photos = info.photoIds ?? const <String>[]'),
        isTrue,
        reason: '저장된 사진 그대로 그린다',
      );
      expect(
        src.contains('requiresPhotos'),
        isFalse,
        reason: '파티의 현재 사진 요청 옵션으로 가리면 안 된다',
      );
      expect(src.contains('showPhotos'), isFalse, reason: '가림 스위치가 남으면 안 된다');
      // 줄을 눌러 상세를 여는 조건에도 사진이 들어 있어야 한다 — 옵션을 끈
      // 파티에서 사진만 낸 신청은 이 조건이 없으면 열리지 않는다.
      expect(
        src.contains('(photoIds != null && photoIds!.isNotEmpty)'),
        isTrue,
        reason: 'hasSubmission이 저장된 사진을 세야 한다',
      );
    });

    test('서버도 같은 필드로 판정한다', () {
      final src = read('../functions/applicationQuestions.js');
      expect(
        src.contains("REQUIRE_PHOTOS_FIELD = 'requireApplicantPhotos'"),
        isTrue,
      );
      expect(src.contains('function requiresApplicantPhotos('), isTrue);

      final index = read('../functions/index.js');
      expect(index.contains('requiresApplicantPhotos(data)'), isTrue);
      expect(
        index.contains('validatePhotos(photos, { required: true })'),
        isTrue,
      );
    });
  });
}
