import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/widgets/party_form/party_pricing_section.dart';

void main() {
  group('생성/정규화', () {
    test('같은 금액', () {
      final p = PartyPricing.same(30000);
      expect(p.type, PartyPricingType.same);
      expect(p.price, 30000);
      expect(p.priceFor('male'), 30000);
      expect(p.priceFor('female'), 30000);
      expect(p.priceFor(null), 30000);
      expect(p.hasGenderedPrice, isFalse);
    });

    test('남녀 다른 금액', () {
      final p = PartyPricing.gendered(male: 35000, female: 25000);
      expect(p.type, PartyPricingType.gendered);
      expect(p.malePrice, 35000);
      expect(p.femalePrice, 25000);
      expect(p.priceFor('male'), 35000);
      expect(p.priceFor('female'), 25000);
      // 성별을 모르면 낮은 쪽(최소 참가비)을 대표로 보여준다.
      expect(p.priceFor(null), 25000);
      expect(p.displayPrice, 25000);
      expect(p.maxPrice, 35000);
      expect(p.hasGenderedPrice, isTrue);
    });

    test('무료', () {
      const p = PartyPricing.free();
      expect(p.isFree, isTrue);
      expect(p.price, 0);
      expect(p.priceFor('male'), 0);
      expect(p.priceFor('female'), 0);
    });

    test('0원이면 무료로 정규화된다', () {
      expect(PartyPricing.same(0).type, PartyPricingType.free);
      expect(PartyPricing.same(null).type, PartyPricingType.free);
      expect(
        PartyPricing.gendered(male: 0, female: 0).type,
        PartyPricingType.free,
      );
    });

    test('남녀 금액이 같으면 same으로 정규화된다', () {
      final p = PartyPricing.gendered(male: 20000, female: 20000);
      expect(p.type, PartyPricingType.same);
      expect(p.price, 20000);
    });

    test('한쪽만 유료인 남녀 다른 금액도 유지된다', () {
      final p = PartyPricing.gendered(male: 30000, female: 0);
      expect(p.type, PartyPricingType.gendered);
      expect(p.priceFor('male'), 30000);
      expect(p.priceFor('female'), 0);
      // 0원인 쪽은 대표 금액 계산에서 제외된다(무료 파티처럼 보이지 않게).
      expect(p.displayPrice, 30000);
    });
  });

  group('저장(toMap) — 새 구조 + 레거시 이중 기록', () {
    test('same', () {
      expect(PartyPricing.same(30000).toMap(), {
        'pricingType': 'same',
        'price': 30000,
        'malePrice': null,
        'femalePrice': null,
        'maleFee': 30000,
        'femaleFee': 30000,
      });
    });

    test('gendered', () {
      expect(PartyPricing.gendered(male: 35000, female: 25000).toMap(), {
        'pricingType': 'gendered',
        'price': null,
        'malePrice': 35000,
        'femalePrice': 25000,
        'maleFee': 35000,
        'femaleFee': 25000,
      });
    });

    test('free', () {
      expect(const PartyPricing.free().toMap(), {
        'pricingType': 'free',
        'price': 0,
        'malePrice': 0,
        'femalePrice': 0,
        'maleFee': 0,
        'femaleFee': 0,
      });
    });
  });

  group('읽기(fromMap) — 새 구조', () {
    test('왕복', () {
      for (final p in [
        PartyPricing.same(30000),
        PartyPricing.gendered(male: 35000, female: 25000),
        const PartyPricing.free(),
      ]) {
        expect(PartyPricing.fromMap(p.toMap()), p, reason: p.toString());
      }
    });
  });

  group('기존 데이터 호환', () {
    test('maleFee == femaleFee → same', () {
      final p = PartyPricing.fromMap({'maleFee': 20000, 'femaleFee': 20000});
      expect(p.type, PartyPricingType.same);
      expect(p.price, 20000);
    });

    test('maleFee != femaleFee → gendered', () {
      final p = PartyPricing.fromMap({'maleFee': 30000, 'femaleFee': 20000});
      expect(p.type, PartyPricingType.gendered);
      expect(p.priceFor('male'), 30000);
      expect(p.priceFor('female'), 20000);
    });

    test('한쪽 필드만 있는 문서 → same', () {
      expect(PartyPricing.fromMap({'maleFee': 15000}).price, 15000);
      expect(PartyPricing.fromMap({'femaleFee': 15000}).price, 15000);
    });

    test('아주 오래된 단일 fee 필드 → same', () {
      final p = PartyPricing.fromMap({'fee': 12000});
      expect(p.type, PartyPricingType.same);
      expect(p.price, 12000);
    });

    test('플레이스+파티가 쓰던 단일 price만 있어도 읽힌다', () {
      // 요구사항의 호환 규칙: pricingType 'same', price 유지, 남녀는 null.
      final p = PartyPricing.fromMap({'price': 30000});
      expect(p.type, PartyPricingType.same);
      expect(p.price, 30000);
      expect(p.malePrice, isNull);
      expect(p.femalePrice, isNull);
      expect(p.priceFor('male'), 30000);
    });

    test('참가비 필드가 아예 없거나 0이면 무료', () {
      expect(PartyPricing.fromMap({}).isFree, isTrue);
      expect(PartyPricing.fromMap(null).isFree, isTrue);
      expect(
        PartyPricing.fromMap({'maleFee': 0, 'femaleFee': 0}).isFree,
        isTrue,
      );
    });

    test('pricingType이 있으면 그 값을 우선하되 값이 비면 레거시로 채운다 (중복 확인)', () {
      // 마이그레이션 중간 상태(새 키만 있고 값은 옛 필드에 있는 문서) 방어.
      final p = PartyPricing.fromMap({'pricingType': 'same', 'maleFee': 18000});
      expect(p.price, 18000);

      final g = PartyPricing.fromMap({
        'pricingType': 'gendered',
        'maleFee': 30000,
        'femaleFee': 20000,
      });
      expect(g.priceFor('male'), 30000);
      expect(g.priceFor('female'), 20000);
    });
  });

  group('공통 참가비 섹션 위젯', () {
    /// 섹션을 띄우고, 마지막으로 전달된 값을 읽는 함수를 돌려준다.
    Future<PartyPricing? Function()> pump(
      WidgetTester tester,
      PartyPricing initial, {
      String genderLimit = 'all',
    }) async {
      PartyPricing? latest;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PartyPricingSection(
              value: initial,
              genderLimit: genderLimit,
              onChanged: (v) => latest = v,
            ),
          ),
        ),
      );
      return () => latest;
    }

    testWidgets('무료를 고르면 안내만 보이고 입력칸이 없다', (tester) async {
      final read = await pump(tester, PartyPricing.same(30000));
      await tester.pumpAndSettle();

      await tester.tap(find.text('무료'));
      await tester.pumpAndSettle();

      expect(find.text('참가비 없이 무료로 진행돼요.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(read()!.isFree, isTrue);
    });

    testWidgets('같은 금액을 입력하면 same으로 전달된다', (tester) async {
      final read = await pump(tester, const PartyPricing.free());
      await tester.pumpAndSettle();

      await tester.tap(find.text('같은 금액'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '30000');
      await tester.pump();

      final result = read()!;
      expect(result.type, PartyPricingType.same);
      expect(result.price, 30000);
    });

    testWidgets('남녀 다른 금액은 입력칸이 둘로 나뉜다', (tester) async {
      final read = await pump(tester, const PartyPricing.free());
      await tester.pumpAndSettle();

      await tester.tap(find.text('남녀 다른 금액'));
      await tester.pumpAndSettle();

      expect(find.text('남성 참가비'), findsOneWidget);
      expect(find.text('여성 참가비'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), '35000');
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), '25000');
      await tester.pump();

      final result = read()!;
      expect(result.type, PartyPricingType.gendered);
      expect(result.priceFor('male'), 35000);
      expect(result.priceFor('female'), 25000);
    });

    testWidgets('금액을 지웠다 다시 입력해도 고른 유형이 유지된다', (tester) async {
      // PartyPricing이 0원을 무료로 정규화하기 때문에, 화면의 선택 상태를
      // 저장값에서만 읽으면 입력 도중 칩이 "무료"로 튄다.
      await pump(tester, PartyPricing.same(30000));
      await tester.pumpAndSettle();

      await tester.tap(find.text('같은 금액'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget); // 여전히 "같은 금액" 화면
      expect(find.text('참가비 없이 무료로 진행돼요.'), findsNothing);
    });

    testWidgets('성별 제한 파티에서는 남녀 다른 금액을 숨긴다', (tester) async {
      await pump(tester, const PartyPricing.free(), genderLimit: 'female');
      await tester.pumpAndSettle();

      expect(find.text('무료'), findsOneWidget);
      expect(find.text('같은 금액'), findsOneWidget);
      expect(find.text('남녀 다른 금액'), findsNothing);
    });
  });
}
