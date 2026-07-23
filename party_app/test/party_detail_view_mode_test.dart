import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/utils/party_detail_view_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PartyDetailViewMode.load', () {
    test('저장된 값이 없으면 designed를 기본값으로 반환한다', () async {
      SharedPreferences.setMockInitialValues({});
      final mode = await PartyDetailViewMode.load();
      expect(mode, PartyDetailViewMode.designed);
    });

    test('저장된 값이 유효하면 그 값을 그대로 반환한다', () async {
      SharedPreferences.setMockInitialValues({
        'party_detail_view_mode': PartyDetailViewMode.textOnly.name,
      });
      final mode = await PartyDetailViewMode.load();
      expect(mode, PartyDetailViewMode.textOnly);
    });

    test('폐지된 imagesOnly(예전 버전의 값)가 저장돼 있어도 크래시 없이 designed로 대체한다', () async {
      SharedPreferences.setMockInitialValues({
        'party_detail_view_mode': 'imagesOnly',
      });
      final mode = await PartyDetailViewMode.load();
      expect(mode, PartyDetailViewMode.designed);
    });

    test('알 수 없는(또는 예전 버전의) 값이 저장돼 있어도 크래시 없이 designed로 대체한다', () async {
      SharedPreferences.setMockInitialValues({
        'party_detail_view_mode': 'photosOnly_legacy_value',
      });
      final mode = await PartyDetailViewMode.load();
      expect(mode, PartyDetailViewMode.designed);
    });
  });

  group('PartyDetailViewMode.save', () {
    test('enum name 문자열로 저장하고 load()로 다시 불러올 수 있다', () async {
      SharedPreferences.setMockInitialValues({});
      await PartyDetailViewMode.textOnly.save();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('party_detail_view_mode'), 'textOnly');

      final loaded = await PartyDetailViewMode.load();
      expect(loaded, PartyDetailViewMode.textOnly);
    });

    test('다른 값으로 다시 저장하면 이전 값을 덮어쓴다', () async {
      SharedPreferences.setMockInitialValues({});
      await PartyDetailViewMode.textOnly.save();
      await PartyDetailViewMode.designed.save();

      final loaded = await PartyDetailViewMode.load();
      expect(loaded, PartyDetailViewMode.designed);
    });
  });

  group('PartyDetailViewMode.label', () {
    test('각 모드가 사람이 읽을 수 있는 한글 라벨을 갖는다', () {
      expect(PartyDetailViewMode.designed.label, '상세페이지');
      expect(PartyDetailViewMode.textOnly.label, '글만보기');
    });
  });
}
