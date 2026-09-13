import 'package:party_app/models/participant_gender_visibility.dart';
import 'package:party_app/models/party_capacity_status.dart';
import 'package:party_app/models/party_constants.dart';
import 'package:party_app/models/party_early_bird.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/payment_policy.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/models/party_age_restriction.dart';
import 'package:party_app/utils/refund_policy.dart';

/// 파티 등록 화면들이 **공통으로 저장하는 파티 정보**를 한 곳에 모은 모델.
///
/// 일반 파티 등록(party_register_screen)과 플레이스+파티 등록
/// (지금은 없어진 콤보 등록 화면)이 각자 문서를 조립하다 보니 필드가
/// 계속 어긋났다(성별 조건이 한쪽만 있거나, 유형·분위기가 빈 배열로만
/// 저장되거나…). 이 클래스가 그 공통 부분의 **단일 진실 소스**다.
///
/// ## 이 모델이 담는 것 / 담지 않는 것
/// 담는 것 — 두 화면이 똑같이 저장해야 하는 값:
///   일정 · 성별/정원 · 참가비 · 얼리버드 · 환불 규정 · 연령 제한 ·
///   유형/분위기/태그 · 소개 글
/// 담지 않는 것 — 화면마다 다른 값:
///   미디어(사진/동영상), 장소·주소, 상세페이지 블록, 다차수 라운드,
///   콤보 연결 필드(bundleId 등)
///
/// 새 공통 항목이 생기면 **여기에 필드를 더하고 [toFirestore]에 한 줄 추가**
/// 하면 두 화면 모두에 자동 반영된다.
class PartyRegistrationData {
  // ── 일정 ────────────────────────────────────────────────────────────
  final PartyScheduleType scheduleType;

  /// 정기 파티일 때만 값이 있다.
  final PartyRecurringSchedule? recurringSchedule;

  /// 일회성 파티일 때만 값이 있다.
  final PartySingleSchedule? singleSchedule;

  /// 일회성 파티의 모집 마감 **규칙**. [singleSchedule]에는 계산이 끝난 절대
  /// 마감 시각만 들어가므로, 수정/재등록에서 "무엇을 골랐었는지"를 되살리려면
  /// 규칙도 함께 저장해야 한다.
  final PartyRecruitDeadlineRule? deadlineRule;

  /// 일회성 파티의 모집 **시작** 규칙. [deadlineRule]과 짝이다.
  ///
  /// 예전에는 이 필드가 아예 없어서 [toFirestore]가 `buildSingleFields`를
  /// 마감 규칙만 넘겨 불렀다 — 그래서 이 모델을 거쳐 저장되는 파티
  /// (플레이스+파티 콤보 등록)는 호스트가 일정 에디터에서 모집 시작을 골라도
  /// `recruitOpenRule`/`recruitOpenAt`이 문서에 남지 않았다. 두 등록 화면이
  /// 같은 에디터(PartyScheduleSection)를 쓰는데 저장 결과만 갈렸던 것이다.
  final PartyRecruitDeadlineRule? openRule;

  // ── 성별 / 정원 ─────────────────────────────────────────────────────
  /// 'all' | 'male' | 'female'
  final String genderLimit;

  /// 'unlimited'(통합 정원) | 'separate'(남녀별 정원)
  final String genderCapacityMode;

  /// 성비 맞춤이면 'balanced', 아니면 빈 문자열.
  final String genderMode;

  final int maleCapacity;
  final int femaleCapacity;

  /// 최소 모집 인원. 0이면 정하지 않은 것.
  final int minCapacity;

  final int maxCapacity;

  /// 최소 인원에 못 미친 채 모집이 마감됐을 때의 처리.
  final PartyMinCapacityPolicy minCapacityPolicy;

  /// 게스트에게 현재 참가자의 남/여 인원을 보여줄지
  /// ([ParticipantGenderVisibility]). 기본은 공개 — 이 설정이 생기기 전
  /// 파티와 똑같이 동작한다.
  final bool revealParticipantGenderRatio;

  // ── 금액 ────────────────────────────────────────────────────────────
  final PartyPricing pricing;
  final PartyEarlyBird earlyBird;
  final List<RefundTier> refundTiers;

  /// 결제 방식(전액 온라인 / 현장 / 현장+예약금). **무료 파티에는 뜻이 없다** —
  /// 받을 돈이 없으면 예약금이라는 개념이 성립하지 않으므로 [toMap]에서도
  /// 저장하지 않는다.
  ///
  /// null이면 설정을 남기지 않는다 = 기존 파티와 똑같이 동작한다(참가자가
  /// 무통장입금·현장결제를 자유롭게 선택). 임의로 기본값을 채우지 않는다.
  final PaymentPolicy? paymentPolicy;

  // ── 조건 / 분류 ─────────────────────────────────────────────────────
  /// 연령 제한 — **성별별**이다([PartyAgeRestriction]). 저장 직전에
  /// [genderLimit]에 맞춰 정리되므로(모집하지 않는 성별의 값은 지워진다),
  /// 화면이 성별 모집 설정을 바꿔도 숨겨진 성별의 옛 제한이 남지 않는다.
  final PartyAgeRestriction ageRestriction;

  final Set<String> partyTypes;
  final Set<String> vibes;
  final List<String> tags;

  /// 유형을 하나도 고르지 않았을 때 쓸 카테고리(화면마다 다르다 —
  /// 파티 등록은 '기타', 콤보는 '플레이스+파티').
  final String fallbackCategory;

  // ── 내용 ────────────────────────────────────────────────────────────
  final String description;

  PartyRegistrationData({
    required this.scheduleType,
    this.recurringSchedule,
    this.singleSchedule,
    this.deadlineRule,
    this.openRule,
    this.genderLimit = 'all',
    this.genderCapacityMode = 'unlimited',
    this.genderMode = '',
    this.maleCapacity = 0,
    this.femaleCapacity = 0,
    this.minCapacity = 0,
    required this.maxCapacity,
    this.minCapacityPolicy = PartyMinCapacityPolicy.proceed,
    this.revealParticipantGenderRatio =
        ParticipantGenderVisibility.defaultValue,
    required this.pricing,
    this.earlyBird = const PartyEarlyBird.off(),
    this.refundTiers = const [],
    this.paymentPolicy,
    this.ageRestriction = PartyAgeRestriction.off,
    Set<String>? partyTypes,
    Set<String>? vibes,
    List<String>? tags,
    this.fallbackCategory = '기타',
    this.description = '',
  }) : partyTypes = partyTypes ?? const {},
       vibes = vibes ?? const {},
       tags = tags ?? const [];

  bool get isRecurring => scheduleType == PartyScheduleType.recurring;

  /// 유형을 골랐으면 첫 유형의 라벨, 아니면 화면별 기본 카테고리.
  String get category => partyTypes.isEmpty
      ? fallbackCategory
      : PartyConstants.labelFor(partyTypes.first);

  /// 입력값 검증 — 화면이 개별 항목을 자기 위치로 안내한 뒤, 마지막으로
  /// "값끼리 안 맞는" 경우를 확인하는 데 쓴다. 문제가 없으면 null.
  String? validate({DateTime? now}) {
    if (maxCapacity <= 0) return '모집 인원을 입력해주세요.';
    final capacityError = PartyCapacityStatus.validate(
      min: minCapacity,
      max: maxCapacity,
    );
    if (capacityError != null) return capacityError;
    // 연령 제한 — 모집하는 성별의 범위만 본다(숨겨진 성별 값은 저장 전에
    // 지워지므로 뒤집혀 있어도 문서에 남지 않는다). 서버
    // validateAgeRestriction과 같은 규칙이다.
    final ageError = _validateAgeRestriction();
    if (ageError != null) return ageError;
    if (isRecurring) {
      final schedule = recurringSchedule;
      if (schedule == null || !schedule.hasEnabledDay) {
        return '정기 파티의 운영 요일과 시간을 설정해주세요.';
      }
      if (schedule.nextOccurrence(now ?? DateTime.now()) == null) {
        return '운영 종료일이 지나 열릴 회차가 없어요. 기간을 다시 확인해주세요.';
      }
    } else if (singleSchedule == null) {
      return '파티 날짜와 시작 시간을 선택해주세요.';
    }
    // 얼리버드는 일정 유형에 따라 검증 규칙이 다르다(일회성=고정 종료 시각,
    // 정기=회차 기준 상대 규칙). 정기 파티는 다음 회차의 시작/모집 마감까지
    // 넘겨 "모집 마감보다 늦게 끝나는" 설정을 여기서 막는다.
    final occurrence = isRecurring
        ? recurringSchedule?.nextOccurrence(now ?? DateTime.now())
        : null;
    return earlyBird.validate(
      isFree: pricing.isFree,
      isRecurring: isRecurring,
      now: now,
      occurrenceStart: occurrence?.start ?? singleSchedule?.date,
      recruitDeadline:
          occurrence?.deadline ?? singleSchedule?.registrationDeadline,
    );
  }

  /// 성별별 연령 제한의 앞뒤가 맞는지. 화면(연령대 설정 시트)이 애초에
  /// 뒤집힌 값을 만들지 않지만, 임시저장을 손대거나 서버를 직접 부르는
  /// 경로까지 같은 규칙으로 막으려면 모델도 알고 있어야 한다.
  String? _validateAgeRestriction() {
    final eff = ageRestriction.normalizedFor(genderLimit);
    if (!eff.hasAnyLimit) return null;
    for (final (gender, label) in const [('male', '남성'), ('female', '여성')]) {
      final l = eff.limitFor(gender);
      if (!l.enabled) continue;
      final min = l.minBirthYear;
      final max = l.maxBirthYear;
      if (min != null && max != null && min > max) {
        return '$label 연령 제한의 최소 나이가 최대 나이보다 클 수 없어요.';
      }
    }
    return null;
  }

  /// 두 화면이 공통으로 기록하는 파티 문서 필드.
  ///
  /// 날짜 종속 필드(`date`/`partyDateTime`/`rounds`)는 화면마다 계산 방식이
  /// 달라(파티 등록은 날짜 슬롯별로 문서를 나눈다) 여기서 만들지 않는다 —
  /// 대신 일정 **유형** 필드(scheduleType/recurringSchedule/singleSchedule)는
  /// 여기서 함께 채운다.
  Map<String, dynamic> toFirestore() => {
    // 일정 유형 — 호출부가 일정 객체를 넘기지 않으면 **아무것도 쓰지 않는다**
    // (파티 등록 화면은 날짜 슬롯마다 문서를 나눠 자기가 채우므로 여기서
    // 덮어쓰면 안 된다).
    //
    // 예전에는 정기일 때 `recurringSchedule!`를 무조건 썼다 — 일정 객체 없이
    // 부르면 "Null check operator used on a null value"(_TypeError)가 나면서
    // 등록 전체가 실패했고, 그 예외는 분류되지 않아 화면에는 "등록 중 문제가
    // 발생했습니다"만 떴다. null이면 조용히 건너뛴다.
    if (isRecurring && recurringSchedule != null)
      ...PartySchedule.buildRecurringFields(recurringSchedule!)
    else if (!isRecurring && singleSchedule != null)
      // 모집 시작 규칙도 반드시 함께 넘긴다 — 빼먹으면 이 모델을 거쳐 저장되는
      // 파티만 조용히 규칙을 잃는다([openRule] 주석 참고).
      ...PartySchedule.buildSingleFields(
        singleSchedule!,
        deadlineRule: deadlineRule,
        openRule: openRule,
      ),

    // 성별 / 정원
    'people': '0/$maxCapacity명',
    'genderLimit': genderLimit,
    'genderCapacityMode': genderCapacityMode,
    'genderMode': genderMode,
    'maleCapacity': maleCapacity,
    'femaleCapacity': femaleCapacity,
    'currentMaleCount': 0,
    'currentFemaleCount': 0,
    // 참가자 현황 공개 — 신규 파티는 값을 그대로 적는다("필드 없음 = 공개"
    // 폴백은 이 설정이 생기기 전 파티만을 위한 장치다).
    ParticipantGenderVisibility.field: revealParticipantGenderRatio,
    // 최소 모집 인원 — **호스트가 직접 정한 파티 전체 값 하나**다.
    // 차수별 최소 인원(rounds[].minCapacity)은 여기에 절대 합산하지 않는다
    // ([PartyMinCapacity] 주석 참고). 옛 필드도 같은 값으로 함께 써서, 이
    // 문서를 예전 코드가 읽어도 어긋나지 않게 한다.
    PartyMinCapacity.field: minCapacity,
    'minCapacity': minCapacity,
    'maxCapacity': maxCapacity,
    // 최소 인원을 안 정했으면 미달이라는 개념 자체가 없다.
    //
    // 정기 파티도 이제 자동 취소를 쓸 수 있다 — 취소 단위가 파티 문서 전체가
    // 아니라 **미달된 그 회차 하나**이기 때문이다(다른 날짜 회차는 그대로
    // 열린다). 서버 autoCancelUnderfilledParties가 회차 단위로 판정한다.
    'minCapacityPolicy': minCapacity > 0
        ? minCapacityPolicy.key
        : PartyMinCapacityPolicy.proceed.key,
    'maxParticipants': maxCapacity,
    'currentParticipants': 0,

    // 금액
    ...pricing.toMap(),
    // 일회성은 고정 종료 시각(earlyBirdEndAt), 정기는 회차 규칙
    // (earlyBirdDeadlineRule) — 한 문서에 둘이 섞이지 않게 유형을 넘긴다.
    ...earlyBird.toMapFor(isRecurring: isRecurring),
    'refundPolicy': RefundTier.listToMaps(refundTiers),
    // 결제 방식 — 유료 파티에서 호스트가 설정했을 때만 남긴다. 무료 파티나
    // 미설정은 필드를 아예 만들지 않아 서버가 기존 동작(참가자 수단 자유
    // 선택)을 그대로 태운다.
    if (!pricing.isFree && paymentPolicy != null) ...paymentPolicy!.toMap(),

    // 조건 / 분류
    // 연령 제한은 **선택 항목**이자 **성별별**이다 — 고르지 않으면
    // ageRestrictionEnabled: false 하나만 쓰고 출생연도 필드는 아예 남기지
    // 않는다(읽는 쪽은 모두 그 스위치를 먼저 보므로 예전 값이 남아 있어도
    // 적용되지 않는다 — party_eligibility.dart 참고).
    //
    // 모집하지 않는 성별의 값은 여기서 지워진다(PartyAgeRestriction.toFields).
    // 구버전 앱을 위한 옛 공통 필드도 표현할 수 있을 때 함께 남는다.
    ...ageRestriction.toFields(genderLimit: genderLimit),
    'category': category,
    'partyTypes': partyTypes.toList(),
    'vibes': vibes.toList(),
    'tags': tags,

    // 내용
    'description': description,
  };
}
