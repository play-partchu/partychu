/// [ApplicantIdentity]를 어디까지 알고 있는지.
enum ApplicantIdentityState {
  /// 신원을 받아 왔다.
  ok,

  /// 탈퇴·삭제되어 **더 이상 불러올 수 없는** 계정.
  withdrawn,

  /// 서버가 신원을 내려주지 않았다(옛 버전 함수 등). 탈퇴와 구분해야 한다 —
  /// 뭉뚱그리면 배포가 어긋난 사이 멀쩡한 신청자가 전부 '탈퇴한 회원'으로 보인다.
  unknown,
}

/// 호스트가 보는 **신청자 표시 신원**.
///
/// 왜 따로 두는가: 호스트 화면은 여러 개인데(신청자 목록, 호스트 허브의 신청자
/// 시트 등) 저마다 신청 문서를 직접 그리다 보니 한쪽에서 **Firebase uid가 그대로
/// 노출**됐다. 표시 규칙을 여기 한 곳에 모아, 어느 화면에서 그리든 같은 문구가
/// 나오게 한다.
///
/// 값의 출처는 서버 `getApplicants` 하나다 — 규칙상 클라이언트는 남의
/// `users/{uid}` 문서를 읽을 수 없다(users 읽기는 본인·관리자뿐). 그래서 화면이
/// 스스로 닉네임·실명·성별을 조회할 방법은 없고, uid로 대신 그리면 안 된다.
/// 그 콜러블이 호스트 본인만 통과시키므로, 여기 담긴 실명도 호스트 전용이다.
class ApplicantIdentity {
  final ApplicantIdentityState state;

  /// **본인확인(NICE)을 마친 계정인지.** 서버가 그대로 내려준다
  /// (functions/applicantIdentity.js).
  ///
  /// 호스트는 입장 확인 때 이 값을 근거로 신분증을 대조하므로 추측하면 안 된다.
  /// 예전에는 화면이 "성별이 비어 있으면 미확인"으로 넘겨짚었는데, 본인확인은
  /// 마쳤는데 성별이 비어 있는 계정에서 곧바로 틀린 답이 나온다.
  final bool verified;

  /// `users/{uid}.nickname`.
  final String nickname;

  /// **본인확인으로 확인된 실명.** 호스트 전용 정보다 — 이 값은 호스트
  /// 권한을 검사하는 `getApplicants` 응답으로만 들어온다(참가자끼리는 서로의
  /// 실명을 볼 수 있는 경로가 없다). 닉네임과 함께 `냥냥이(홍길동)` 꼴로 붙인다.
  final String name;

  /// **본인확인으로 확인된** 성별('male' | 'female'). 프로필에서 임의로 고친
  /// 값이나 신청 시점 스냅샷은 쓰지 않는다(서버에서 이미 걸러 내려온다).
  final String gender;

  /// **본인확인 기준** 생년월일. 월·일은 옛 데이터에 없을 수 있다.
  final int? birthYear;
  final int? birthMonth;
  final int? birthDay;

  const ApplicantIdentity({
    required this.state,
    this.verified = false,
    this.nickname = '',
    this.name = '',
    this.gender = '',
    this.birthYear,
    this.birthMonth,
    this.birthDay,
  });

  /// 탈퇴·삭제되어 정보를 더 이상 불러올 수 없는 신청자.
  static const withdrawn = ApplicantIdentity(
    state: ApplicantIdentityState.withdrawn,
  );

  /// 서버가 신원을 내려주지 않은 경우.
  static const unknown = ApplicantIdentity(
    state: ApplicantIdentityState.unknown,
  );

  factory ApplicantIdentity.fromMap(Map<Object?, Object?>? m) {
    if (m == null) return unknown;
    if (m['available'] != true) return withdrawn;
    final name = m['name'] as String? ?? '';
    final gender = m['gender'] as String? ?? '';
    final birthYear = (m['birthYear'] as num?)?.toInt();
    return ApplicantIdentity(
      state: ApplicantIdentityState.ok,
      // `verified`를 내려주지 않는 **옛 서버 응답**은 예전 판정으로 물러선다 —
      // 본인확인을 마친 계정에만 실명·성별·생년이 실려 오기 때문이다. 배포가
      // 어긋난 사이 멀쩡한 신청자가 전부 '미확인'으로 보이지 않게 하려는 것이고,
      // 새 서버가 올라오면 이 폴백은 쓰이지 않는다.
      verified:
          m['verified'] as bool? ??
          (name.isNotEmpty || gender.isNotEmpty || birthYear != null),
      nickname: m['nickname'] as String? ?? '',
      name: name,
      gender: gender,
      birthYear: birthYear,
      birthMonth: (m['birthMonth'] as num?)?.toInt(),
      birthDay: (m['birthDay'] as num?)?.toInt(),
    );
  }

  /// 정보를 불러올 수 없는 신청자에게 보여줄 문구.
  static const withdrawnLabel = '탈퇴한 회원';

  String get genderLabel => switch (gender) {
    'female' => '여성',
    'male' => '남성',
    _ => '',
  };

  /// 생년월일 기준 **만 나이**.
  ///
  /// 저장하지 않고 부를 때마다 계산한다 — 한 번 계산해 문서에 박아 두면 해가
  /// 바뀌어도 옛 나이가 그대로 남는다.
  ///
  /// 월·일이 없는 옛 데이터는 만 나이를 확정할 수 없어(생일이 지났는지 알 수
  /// 없다) 연 나이(연도 차)로 물러선다. [now]는 테스트에서 시점을 고정하려고
  /// 받는다.
  int? ageAt([DateTime? now]) {
    final year = birthYear;
    if (year == null || year <= 0) return null;
    final today = now ?? DateTime.now();
    var age = today.year - year;
    final month = birthMonth;
    final day = birthDay;
    if (month != null && day != null) {
      final hadBirthday =
          today.month > month || (today.month == month && today.day >= day);
      if (!hadBirthday) age -= 1;
    }
    return age < 0 ? null : age;
  }

  /// 호스트 화면에 그대로 쓰는 한 줄 — `여성 · 냥냥이 · 1991년생 (35세)`.
  ///
  /// 비어 있는 항목은 조용히 빠진다(본인확인 전이라 성별을 모르거나, 닉네임을
  /// 아직 정하지 않은 경우). 모두 비면 uid를 대신 그리지 않고 [unknownLabel]을
  /// 쓴다 — 화면에 uid가 새어 나가지 않게 하는 것이 이 클래스의 목적이다.
  static const unknownLabel = '정보 없음';

  String displayLabel([DateTime? now]) {
    if (state == ApplicantIdentityState.withdrawn) return withdrawnLabel;
    if (state == ApplicantIdentityState.unknown) return unknownLabel;
    final year = birthYear;
    final parts = <String>[
      if (genderLabel.isNotEmpty) genderLabel,
      if (_whoLabel.isNotEmpty) _whoLabel,
      if (year != null) _birthLabel(year, now),
    ];
    return parts.isEmpty ? unknownLabel : parts.join(' · ');
  }

  /// 누구인지 — `냥냥이(홍길동)`. 둘 중 하나만 있으면 있는 쪽만 쓴다.
  ///
  /// 닉네임이 앞이다: 호스트도 평소에는 닉네임으로 사람을 기억하고, 실명은
  /// 입금자명 대조처럼 확인이 필요할 때 보는 값이다.
  String get _whoLabel {
    if (nickname.isEmpty) return name;
    if (name.isEmpty || name == nickname) return nickname;
    return '$nickname($name)';
  }

  /// **이름만** — 성별·나이를 뺀 `냥냥이(홍길동)`.
  ///
  /// 통합 신청자·예약자 관리처럼 한 줄에 유형·콘텐츠명·날짜·상태가 이미 들어가
  /// 있는 목록이 쓴다. 거기서 [displayLabel]을 그대로 쓰면 한 줄에 정보가 너무
  /// 많아 정작 "누가 신청했는지"가 묻힌다. 예약 문서의 `requesterName`과 같은
  /// 자리에 들어가는 값이라, 유형이 달라도 목록에서 같은 층으로 읽힌다.
  ///
  /// uid로 물러서지 않는 원칙은 [displayLabel]과 같다.
  String get personLabel {
    if (state == ApplicantIdentityState.withdrawn) return withdrawnLabel;
    if (state == ApplicantIdentityState.unknown) return unknownLabel;
    return _whoLabel.isEmpty ? unknownLabel : _whoLabel;
  }

  /// 입장 확인 때 신분증과 대조할 **본인확인 실명**. 확인 전이거나 탈퇴한
  /// 계정이면 null이라 호출부가 줄 자체를 빼면 된다.
  ///
  /// 신분증 대조에 필요한 것은 이름 하나다 — 주민등록번호·생년월일 전체 같은
  /// 값은 [ApplicantIdentity]가 애초에 들고 있지도 않고(서버가 연·월·일을
  /// 나눠 내려주며 월·일은 나이 계산에만 쓴다), 어떤 화면에도 그리지 않는다.
  String? get verifiedName {
    if (!verified) return null;
    return name.isEmpty ? null : name;
  }

  /// 출생연도는 **뒤 두 자리만** 쓴다 — `1996 → 96`, `2004 → 04`, `2000 → 00`.
  ///
  /// `padLeft`가 핵심이다. 그냥 나머지 연산만 하면 2004년생이 `4년생`, 2000년생이
  /// `0년생`으로 나와 읽히지 않는다.
  static String shortYear(int year) => (year % 100).toString().padLeft(2, '0');

  String _birthLabel(int year, DateTime? now) {
    final born = '${shortYear(year)}년생';
    final age = ageAt(now);
    return age == null ? born : '$born ($age세)';
  }
}
