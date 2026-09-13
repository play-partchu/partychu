import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/pet_policy.dart';

void main() {
  test('미설정 상태는 null로 유지되고 한 번에 round-trip 된다', () {
    final empty = PetPolicy.empty();
    expect(empty.status, isNull);
    expect(empty.toMap()['status'], isNull);
    final restored = PetPolicy.fromMap(empty.toMap());
    expect(restored.status, isNull);
  });

  test('반려동물 정책 값이 저장 및 복원된다', () {
    final policy = PetPolicy(
      status: PetPolicyStatus.possible,
      allowedAnimals: {'강아지', '기타'},
      sizeLimit: '소형견만',
      maxCount: 2,
      extraFeeEnabled: true,
      extraFeeAmount: 5000,
      requiredConditions: {'매너벨트 필수', '예방접종 완료'},
      notes: '실외 산책 가능',
    );

    final roundTrip = PetPolicy.fromMap(policy.toMap());
    expect(roundTrip.status, PetPolicyStatus.possible);
    expect(roundTrip.allowedAnimals, containsAll(['강아지', '기타']));
    expect(roundTrip.sizeLimit, '소형견만');
    expect(roundTrip.maxCount, 2);
    expect(roundTrip.extraFeeEnabled, isTrue);
    expect(roundTrip.extraFeeAmount, 5000);
    expect(roundTrip.requiredConditions, containsAll(['매너벨트 필수', '예방접종 완료']));
    expect(roundTrip.notes, '실외 산책 가능');
  });
}
