import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/widgets/party_detail_theme.dart';

void main() {
  group('partyDetailThemeKeyFromString', () {
    test('유효한 값은 그대로 파싱된다', () {
      expect(
        partyDetailThemeKeyFromString('partychu'),
        PartyDetailThemeKey.partychu,
      );
      expect(
        partyDetailThemeKeyFromString('lovely'),
        PartyDetailThemeKey.lovely,
      );
      expect(
        partyDetailThemeKeyFromString('premiumDark'),
        PartyDetailThemeKey.premiumDark,
      );
      expect(
        partyDetailThemeKeyFromString('clubNeon'),
        PartyDetailThemeKey.clubNeon,
      );
      expect(
        partyDetailThemeKeyFromString('minimal'),
        PartyDetailThemeKey.minimal,
      );
    });

    test('null이면(기존 파티) partychu로 대체된다', () {
      expect(partyDetailThemeKeyFromString(null), PartyDetailThemeKey.partychu);
    });

    test('알 수 없는 값이어도 크래시 없이 partychu로 대체된다', () {
      expect(
        partyDetailThemeKeyFromString('galaxy'),
        PartyDetailThemeKey.partychu,
      );
      expect(partyDetailThemeKeyFromString(''), PartyDetailThemeKey.partychu);
      expect(
        partyDetailThemeKeyFromString('PartyChu'),
        PartyDetailThemeKey.partychu,
      ); // 대소문자 불일치도 안전 처리
    });
  });

  group('PartyDetailThemeRegistry', () {
    test('5개 테마 모두 등록되어 있다', () {
      final all = PartyDetailThemeRegistry.all;
      expect(all, hasLength(5));
      expect(all.map((t) => t.key).toSet(), PartyDetailThemeKey.values.toSet());
    });

    test('fromKey는 각 key에 대응하는 팔레트를 돌려준다', () {
      for (final key in PartyDetailThemeKey.values) {
        final palette = PartyDetailThemeRegistry.fromKey(key);
        expect(palette.key, key);
      }
    });

    test('fromString(null)은 partychu 팔레트를 돌려준다', () {
      final palette = PartyDetailThemeRegistry.fromString(null);
      expect(palette.key, PartyDetailThemeKey.partychu);
    });

    test('fromString(알 수 없는 값)은 partychu 팔레트로 안전하게 대체된다', () {
      final palette = PartyDetailThemeRegistry.fromString('does-not-exist');
      expect(palette.key, PartyDetailThemeKey.partychu);
    });

    test('각 테마의 본문 색상은 배경과 다르다(최소한의 대비 확인)', () {
      for (final theme in PartyDetailThemeRegistry.all) {
        expect(
          theme.bodyColor,
          isNot(equals(theme.sectionBackground)),
          reason: '${theme.label} 테마의 본문 색이 배경과 동일하면 안 됨',
        );
      }
    });
  });
}
