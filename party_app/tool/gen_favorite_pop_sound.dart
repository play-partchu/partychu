// 찜 효과음(assets/sounds/favorite_pop.wav)을 **코드로 합성**한다.
//
//   dart run tool/gen_favorite_pop_sound.dart
//
// 외부 음원을 가져다 쓰지 않고 사인파를 직접 그려 만든다 — 출처·라이선스를
// 따질 대상이 없고(전부 이 파일이 만든 값), 파일도 20KB 남짓이라 앱 용량에
// 부담이 없다. 소리를 손보고 싶으면 아래 상수만 바꿔 다시 돌리면 된다.
//
// 소리 설계('뿅')
//  · 음정이 짧게 **올라간다** — 내려가면 실패·취소처럼 들린다.
//  · 붙자마자 최대(4ms)로 올라갔다가 지수로 사라진다 — 길게 울리면 목록에서
//    연달아 누를 때 소리가 겹쳐 시끄럽다.
//  · 2배음을 아주 조금 섞어 '톡' 하는 밝은 기가 남게 한다.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 22050; // UI 효과음에는 충분하고 파일이 작다.
const _durationMs = 260; // 0.2~0.4초 요청 범위 안.
const _startHz = 780.0;
const _endHz = 1560.0; // 한 옥타브 위로 올라간다.
const _peak = 0.55; // 0~1. 1로 올리면 기기에서 거슬린다.
const _decay = 13.0; // 클수록 빨리 사라진다.

void main() {
  final total = (_sampleRate * _durationMs / 1000).round();
  final samples = Int16List(total);

  // 위상을 누적해서 만든다 — 주파수가 변할 때 sin(2πft)로 계산하면 프레임마다
  // 위상이 튀어 '지직' 소리가 난다.
  var phase = 0.0;
  for (var i = 0; i < total; i++) {
    final t = i / total; // 0~1

    // 음정: 앞 70%에서 다 올라가고 나머지는 유지한다.
    final sweep = math.min(t / 0.7, 1.0);
    final hz = _startHz + (_endHz - _startHz) * Curves.easeOut(sweep);
    phase += 2 * math.pi * hz / _sampleRate;

    // 음량: 4ms 어택 뒤 지수 감쇠. 끝 10%는 0까지 직선으로 끌어내려
    // 잘린 파형이 만드는 '틱' 소리를 없앤다.
    final attack = math.min(i / (_sampleRate * 0.004), 1.0);
    final tail = t > 0.9 ? (1 - t) / 0.1 : 1.0;
    final env = attack * math.exp(-_decay * t) * tail;

    final value = math.sin(phase) * 0.85 + math.sin(phase * 2) * 0.15; // 2배음 살짝
    samples[i] = (value * env * _peak * 32767).round().clamp(-32768, 32767);
  }

  final out = File('assets/sounds/favorite_pop.wav');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(_wav(samples));
  stdout.writeln('생성: ${out.path} (${out.lengthSync()} bytes)');
}

/// 16bit mono PCM WAV 한 개.
Uint8List _wav(Int16List samples) {
  final dataBytes = samples.buffer.asUint8List();
  final bytes = BytesBuilder();
  void ascii(String s) => bytes.add(s.codeUnits);
  void u32(int v) => bytes.add(
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little),
  );
  void u16(int v) => bytes.add(
    Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little),
  );

  ascii('RIFF');
  u32(36 + dataBytes.length);
  ascii('WAVE');
  ascii('fmt ');
  u32(16); // PCM 헤더 길이
  u16(1); // PCM
  u16(1); // 모노
  u32(_sampleRate);
  u32(_sampleRate * 2); // byte rate = rate * blockAlign
  u16(2); // blockAlign = 채널 1 * 16bit
  u16(16); // bit depth
  ascii('data');
  u32(dataBytes.length);
  bytes.add(dataBytes);
  return bytes.toBytes();
}

/// flutter 위젯 커브를 쓸 수 없는 순수 dart 스크립트라 필요한 것만 옮겨 둔다.
class Curves {
  static double easeOut(double t) => 1 - math.pow(1 - t, 3).toDouble();
}
