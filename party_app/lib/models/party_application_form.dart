/// 승인제 파티의 **승인 방식 + 사전질문** 모델.
///
/// 금지 개인정보 질문 판정은 `functions/applicationQuestions.js`와 **같은
/// 규칙**을 담고 있다. 다만 역할이 다르다 — 여기는 호스트가 저장 버튼을 누르기
/// 전에 알려주기 위한 것이고, **실제로 막는 것은 언제나 서버**다.
/// 파티 문서의 질문 필드는 규칙상 클라이언트가 쓸 수 없고
/// `setPartyApplicationForm` 콜러블만 쓸 수 있다.
///
/// 두 곳의 규칙이 갈라지면 "앱에서는 통과했는데 저장이 안 되는" 상태가 되므로,
/// 목록을 고칠 때는 반드시 양쪽을 함께 고친다.
library;

import 'package:flutter/foundation.dart';

/// 승인 방식 — 플레이스 룸 예약(`RoomApprovalMode`)과 같은 키를 쓴다.
enum PartyApprovalMode {
  /// 신청하면 바로 확정. **필드가 없는 기존 파티는 전부 이 값**이다.
  auto('auto', '즉시 신청 확정', '신청하면 바로 확정돼요'),

  /// 호스트가 승인해야 확정 — 사전질문을 받을 수 있다.
  manual('manual', '호스트 승인제', '내가 승인한 사람만 참가해요');

  const PartyApprovalMode(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  /// 알 수 없는 값은 [auto]로 읽는다 — 오타 하나로 기존 파티의 신청이
  /// 멈추면 안 된다(서버 `approvalModeOf`와 같은 방침).
  static PartyApprovalMode fromKey(String? key) =>
      key == manual.key ? manual : auto;

  /// 파티 문서에서 승인 방식을 읽는다.
  static PartyApprovalMode of(Map<String, dynamic>? party) =>
      fromKey(party?['applicationApprovalMode'] as String?);
}

/// 사전질문 한 개.
class PartyApplicationQuestion {
  final String id;
  final String text;
  final bool required;

  const PartyApplicationQuestion({
    required this.id,
    required this.text,
    this.required = false,
  });

  PartyApplicationQuestion copyWith({String? text, bool? required}) =>
      PartyApplicationQuestion(
        id: id,
        text: text ?? this.text,
        required: required ?? this.required,
      );

  Map<String, dynamic> toMap(int order) => {
    'id': id,
    'text': text,
    'required': required,
    'order': order,
  };

  static PartyApplicationQuestion? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    return PartyApplicationQuestion(
      id: id,
      text: raw['text'] as String? ?? '',
      required: raw['required'] == true,
    );
  }
}

/// 파티 문서에서 "프로필 사진 제출을 요청할지"를 담는 필드 이름.
/// 서버(`applicationQuestions.js`)와 **같은 이름**이어야 한다.
const String kRequireApplicantPhotosField = 'requireApplicantPhotos';

/// 파티 문서에 저장된 승인 방식 + 질문 목록 + 사진 요청 여부.
class PartyApplicationForm {
  final PartyApprovalMode mode;
  final List<PartyApplicationQuestion> questions;

  /// 호스트가 **명시적으로 켠** 경우에만 true.
  ///
  /// 예전에는 승인제이기만 하면 신청 화면에 사진 제출 칸이 떴다. 호스트는
  /// 요청한 적도 없는데 신청자에게 얼굴 사진을 요구하는 셈이라, 이제는
  /// 호스트가 켠 파티에서만 묻는다.
  final bool requirePhotos;

  const PartyApplicationForm({
    this.mode = PartyApprovalMode.auto,
    this.questions = const [],
    this.requirePhotos = false,
  });

  bool get requiresApproval => mode == PartyApprovalMode.manual;

  /// 신청 화면에 물어볼 질문이 있는지. 승인제가 아니면 언제나 false다.
  bool get hasQuestions => requiresApproval && questions.isNotEmpty;

  /// 신청 화면에서 사진을 받아야 하는지. 승인제가 아니면 언제나 false다.
  ///
  /// 질문과 **완전히 독립**이다 — 질문 없이 사진만, 사진 없이 질문만,
  /// 둘 다, 둘 다 아님이 모두 가능하다.
  bool get requiresPhotos => requiresApproval && requirePhotos;

  /// 신청 흐름에서 제출 화면을 띄워야 하는지.
  ///
  /// **"승인제니까"가 아니라 "받을 것이 있으니까"** 띄운다 — 질문도 사진도
  /// 없는 승인제 파티는 이 화면을 건너뛰고 곧바로 다음 단계로 간다.
  bool get needsSubmissionStep => hasQuestions || requiresPhotos;

  /// 파티 문서에서 읽는다.
  ///
  /// 승인제가 아니면 **질문도 사진 요청도 없다** — 승인제로 만들었다가
  /// 되돌린 파티에 정의가 남아 있어도 신청 화면에 뜨지 않는다(서버
  /// `questionsOf`와 같은 규칙).
  factory PartyApplicationForm.fromParty(Map<String, dynamic>? party) {
    final mode = PartyApprovalMode.of(party);
    if (mode != PartyApprovalMode.manual) {
      return const PartyApplicationForm();
    }
    final raw = party?['applicationQuestions'];
    final list = <PartyApplicationQuestion>[];
    if (raw is List) {
      final entries = <MapEntry<int, PartyApplicationQuestion>>[];
      for (var i = 0; i < raw.length; i++) {
        final q = PartyApplicationQuestion.fromMap(raw[i]);
        if (q == null) continue;
        final order = (raw[i] as Map)['order'];
        entries.add(MapEntry(order is int ? order : i, q));
      }
      entries.sort((a, b) => a.key.compareTo(b.key));
      list.addAll(entries.map((e) => e.value));
    }
    return PartyApplicationForm(
      mode: mode,
      questions: list.take(PartyApplicationLimits.maxQuestions).toList(),
      // **필드가 없으면 OFF**다. 이 기본값이 이번 정책의 핵심이다 — 예전
      // 승인제 파티는 이 설정 자체가 없었고, 그때도 사진은 "내면 좋은 것"일
      // 뿐 없어도 신청이 됐다(서버도 최소 장수를 요구하지 않았다). 그러니
      // 미설정을 ON으로 읽으면 기존 파티의 신청자만 갑자기 못 내게 된다.
      requirePhotos: party?[kRequireApplicantPhotosField] == true,
    );
  }
}

/// 서버(`applicationQuestions.js`)와 **같은 값**이어야 하는 제한들.
class PartyApplicationLimits {
  const PartyApplicationLimits._();

  static const int maxQuestions = 5;
  static const int maxQuestionLength = 100;
  static const int maxAnswerLength = 500;
  static const int maxPhotos = 5;
}

/// 호스트에게 항상 보여주는 개인정보 경고 문구.
const String kApplicationQuestionPrivacyNotice =
    '전화번호, 카카오톡·SNS 아이디, 상세 주소, 주민등록번호·신분증 정보, '
    '계좌·카드정보 등 파티 참여에 불필요한 개인정보는 요구하지 마세요. '
    '위반 질문은 등록이 제한될 수 있어요.';

/// 호스트의 신청자 사진 화면에 붙는 보호 안내 — **플랫폼마다 다르다.**
///
/// 실제로 되는 만큼만 말하는 것이 이 문구의 전부다. Android는 OS가 캡처를
/// 막아 주니 '제한'이라고 말할 수 있지만, iOS는 스크린샷을 사전에 막을 공식
/// 방법이 없다. 같은 문장을 그대로 쓰면 iOS 사용자에게는 거짓말이 되므로,
/// 그쪽은 '감지해서 가린다'로 정확히 적는다.
const String kApplicantPhotoHostNoticeAndroid =
    '🔒 신청자 보호를 위해 사진의 저장·공유 및 화면 캡처를 제한하고 있어요. '
    '사진은 참가 승인 확인 용도로만 이용해주세요.';

const String kApplicantPhotoHostNoticeIos =
    '🔒 신청자 보호를 위해 사진의 저장·공유 기능을 제공하지 않고, '
    '화면 캡처·녹화를 감지해 사진을 가리는 보호 조치를 적용해요. '
    '사진은 참가 승인 확인 용도로만 이용해주세요.';

/// 캡처를 감지할 방법조차 없는 곳(웹 등) — 되는 것만 적는다.
const String kApplicantPhotoHostNoticeOther =
    '🔒 신청자 보호를 위해 사진의 저장·공유 기능을 제공하지 않아요. '
    '사진은 참가 승인 확인 용도로만 이용해주세요.';

/// 지금 기기에서 **실제로 적용되는** 보호 수준에 맞는 문구.
String applicantPhotoHostNotice() {
  if (kIsWeb) return kApplicantPhotoHostNoticeOther;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => kApplicantPhotoHostNoticeAndroid,
    TargetPlatform.iOS => kApplicantPhotoHostNoticeIos,
    _ => kApplicantPhotoHostNoticeOther,
  };
}

/// 사진을 내는 게스트에게 보여주는 안심 안내 — 제목/본문/보조문구.
///
/// 사진을 **고르기 전에** 보이는 자리에 둔다. 이미 낸 신청 내역에서도 같은
/// 문구를 다시 확인할 수 있어야 해서, 화면마다 따로 쓰지 않고 여기 모아 둔다.
///
/// '지원되는 기기에서는'이라는 단서를 뺄 수 없다 — iOS에서는 스크린샷 자체가
/// 막히지 않기 때문이다.
const String kApplicantPhotoGuestNoticeTitle = '🔒 제출 사진은 안전하게 보호돼요';

const String kApplicantPhotoGuestNoticeBody =
    '해당 파티 호스트만 확인할 수 있으며 다른 게스트에게 공개되지 않아요. '
    '저장·공유 기능은 제공하지 않고, 지원되는 기기에서는 화면 캡처와 녹화도 '
    '제한해요.';

const String kApplicantPhotoGuestNoticeSub = '사진은 파티 참가 승인 확인을 위한 용도로만 이용해주세요.';

/// 신청자에게 항상 보여주는 주의 문구.
const String kApplicationAnswerPrivacyNotice =
    '파티 참여에 불필요한 개인정보(전화번호·카카오톡 아이디·상세 주소·'
    '주민등록번호·계좌번호 등)는 답변에 적지 마세요. '
    '요구받으셨다면 신고해주세요.';

// ── 금지 개인정보 질문 탐지 ──────────────────────────────────────────────────
//
// 오탐이 더 나쁘다. "연락 가능한 시간대", "어떤 일을 하시나요?", "참여 이유"
// 같은 정상 질문까지 막으면 호스트가 기능 자체를 못 쓴다. 그래서 2단으로 나눈다.
// 자세한 근거는 functions/applicationQuestions.js 주석 참고.

const List<String> _bannedAlone = [
  '주민등록번호',
  '주민번호',
  '신분증',
  '여권번호',
  '운전면허',
  '계좌번호',
  '카드번호',
  '카드정보',
  '카드번',
  '카톡아이디',
  '카톡id',
  '카카오톡아이디',
  '카카오톡id',
  '카카오아이디',
  '오픈카톡',
  '오픈채팅방',
  '인스타아이디',
  '인스타id',
  '인스타그램아이디',
  '텔레그램아이디',
  '라인아이디',
  '상세주소',
  '집주소',
  '자택주소',
  '거주지주소',
  '우편번호',
];

/// 조합 차단용 명사. **'연락'이 아니라 '연락처'** 인 점이 중요하다 —
/// "연락 가능한 시간대"는 정상 질문이고 반드시 통과해야 한다.
/// 같은 이유로 '번호' 단독은 넣지 않는다("몇 번 참여하셨나요"가 걸린다).
const List<String> _sensitiveNouns = [
  '전화번호',
  '휴대폰',
  '휴대전화',
  '핸드폰',
  '폰번호',
  '연락처',
  '계좌',
  '카드',
  '아이디',
  '주소',
  '생년월일',
  '실명',
];

const List<String> _demandVerbs = [
  '적어',
  '써주',
  '써주세요',
  '알려',
  '입력',
  '기입',
  '기재',
  '남겨',
  '남기',
  '보내',
  '공유',
  '제출',
  '작성',
  '올려',
  '첨부',
];

/// 질문 문구가 금지 개인정보를 요구하면 안내 문구를, 아니면 null을 돌려준다.
///
/// 판정 전에 공백을 모두 지운다 — '카톡 아이디'와 '카톡아이디'가 갈리면
/// 띄어쓰기 하나로 우회된다.
String? bannedQuestionReason(String text) {
  final s = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  if (s.isEmpty) return null;

  for (final word in _bannedAlone) {
    if (s.contains(word)) {
      return "'$word'처럼 파티 참여에 불필요한 개인정보는 질문으로 만들 수 없어요.";
    }
  }

  for (final noun in _sensitiveNouns) {
    if (!s.contains(noun)) continue;
    for (final verb in _demandVerbs) {
      if (s.contains(verb)) {
        return "'$noun'를 요구하는 질문은 만들 수 없어요. "
            '파티 참여에 꼭 필요한 내용만 물어주세요.';
      }
    }
  }
  return null;
}
