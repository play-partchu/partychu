import 'package:flutter_test/flutter_test.dart';
import 'package:party_app/models/reservation_modes.dart';

// 예약 방식 복수 선택(숙박/시간제/패키지) 해석·직렬화와 숙박 설정 계산.
// 서버(functions/roomAvailability.js의 normalizeReservationModes)와 같은
// 규칙이어야 하므로, 하위호환 케이스를 특히 촘촘히 확인한다.

void main() {
  group('parseReservationModes', () {
    test('reservationModes 배열이 정본이다', () {
      expect(
        parseReservationModes({
          'reservationModes': ['stay', 'hourly'],
        }),
        {ReservationMode.stay, ReservationMode.hourly},
      );
    });

    test('알 수 없는 값은 무시하고, 전부 무효면 구 필드로 넘어간다', () {
      expect(
        parseReservationModes({
          'reservationModes': ['stay', 'weekly'],
        }),
        {ReservationMode.stay},
      );
      expect(
        parseReservationModes({
          'reservationModes': ['weekly'],
          'reservationMode': 'package',
        }),
        {ReservationMode.package},
      );
    });

    test('구 스키마 reservationMode 문자열을 해석한다', () {
      expect(parseReservationModes({'reservationMode': 'both'}), {
        ReservationMode.hourly,
        ReservationMode.package,
      });
      expect(parseReservationModes({'reservationMode': 'hourly'}), {
        ReservationMode.hourly,
      });
      expect(parseReservationModes({'reservationMode': 'package'}), {
        ReservationMode.package,
      });
      // 옛 하루단위 대여는 숙박으로 본다.
      expect(parseReservationModes({'reservationMode': 'daily'}), {
        ReservationMode.stay,
      });
    });

    test('아무 값도 없으면 패키지 유무로 추론한다', () {
      expect(parseReservationModes({}), {ReservationMode.hourly});
      expect(
        parseReservationModes({
          'packages': [
            {'id': 'p1'},
          ],
        }),
        {ReservationMode.package},
      );
    });
  });

  group('직렬화', () {
    test('키는 항상 숙박 → 시간제 → 패키지 순으로 정렬된다', () {
      expect(
        reservationModeKeys({ReservationMode.package, ReservationMode.stay}),
        ['stay', 'package'],
      );
    });

    test('구버전 앱용 미러는 시간제/패키지를 우선한다', () {
      expect(legacyReservationMode({ReservationMode.stay}), 'stay');
      expect(legacyReservationMode({ReservationMode.hourly}), 'hourly');
      expect(legacyReservationMode({ReservationMode.package}), 'package');
      expect(
        legacyReservationMode({
          ReservationMode.hourly,
          ReservationMode.package,
        }),
        'both',
      );
      // 숙박+시간제는 구버전 앱에서 시간제로라도 예약이 되게 축약한다.
      expect(
        legacyReservationMode({ReservationMode.stay, ReservationMode.hourly}),
        'hourly',
      );
    });

    test('저장 → 복원 왕복이 같은 선택을 유지한다', () {
      const modes = {ReservationMode.stay, ReservationMode.package};
      final saved = {
        'reservationModes': reservationModeKeys(modes),
        'reservationMode': legacyReservationMode(modes),
      };
      expect(parseReservationModes(saved), modes);
    });
  });

  group('StayConfig', () {
    test('기본값은 체크인 16:00 / 체크아웃 11:00', () {
      final stay = StayConfig.fromMap({});
      expect(stay.checkInTime, '16:00');
      expect(stay.checkOutTime, '11:00');
      expect(stay.minNights, 1);
      expect(stay.maxNights, isNull);
    });

    test('2박은 자정 기준 960분 ~ 3540분을 점유한다', () {
      final stay = StayConfig.fromMap({
        'stayCheckInTime': '16:00',
        'stayCheckOutTime': '11:00',
      });
      expect(stay.checkInMinutes, 960);
      // 2 × 1440 + 660(11:00) - 960(16:00) = 2580분
      expect(stay.minutesForNights(2), 2580);
      expect(stay.checkInMinutes + stay.minutesForNights(2), 3540);
    });

    test('가격은 1박 요금 × 박수', () {
      final stay = StayConfig.fromMap({'stayPricePerNight': 120000});
      expect(stay.priceForNights(3), 360000);
    });

    test('숙박일 후보는 최소~최대 범위, 최대가 없으면 fallback까지', () {
      expect(
        StayConfig.fromMap({
          'stayMinNights': 2,
          'stayMaxNights': 4,
        }).nightOptions(),
        [2, 3, 4],
      );
      expect(StayConfig.fromMap({}).nightOptions(fallbackMax: 3), [1, 2, 3]);
    });

    test('toMap → fromMap 왕복', () {
      const original = StayConfig(
        pricePerNight: 90000,
        checkInTime: '15:00',
        checkOutTime: '12:00',
        minNights: 2,
        maxNights: 5,
      );
      final restored = StayConfig.fromMap(original.toMap());
      expect(restored.pricePerNight, 90000);
      expect(restored.checkInTime, '15:00');
      expect(restored.checkOutTime, '12:00');
      expect(restored.minNights, 2);
      expect(restored.maxNights, 5);
    });
  });

  group('placePriceSummary', () {
    test('시간제 룸이 하나라도 있으면 시간당 최저가', () {
      final summary = placePriceSummary([
        {
          'reservationModes': ['stay'],
          'stayPricePerNight': 100000,
        },
        {
          'reservationModes': ['hourly'],
          'pricePerHour': 30000,
        },
        {
          'reservationModes': ['hourly'],
          'pricePerHour': 50000,
        },
      ]);
      expect(summary.price, 30000);
      expect(summary.unit, 'hour');
    });

    test('숙박 전용이면 1박 최저가', () {
      final summary = placePriceSummary([
        {
          'reservationModes': ['stay'],
          'stayPricePerNight': 150000,
        },
        {
          'reservationModes': ['stay', 'package'],
          'stayPricePerNight': 90000,
        },
      ]);
      expect(summary.price, 90000);
      expect(summary.unit, 'night');
    });

    test('가격 정보가 없으면 0원/시간당', () {
      final summary = placePriceSummary([
        {
          'reservationModes': ['package'],
        },
      ]);
      expect(summary.price, 0);
      expect(summary.unit, 'hour');
    });
  });
}
