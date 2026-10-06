/// 특징 강조 칩을 **한 줄에 몇 개까지** 세울지 고르는 계산.
///
/// ── 왜 모델로 빼는가 ──────────────────────────────────────────────────────
/// 이 판정은 눈으로 검사하기가 가장 어려운 종류다. 칩이 한 개 더 들어갔는지,
/// '+2'가 '+3'이어야 하는지는 화면을 봐도 "대충 맞네" 수준으로만 읽힌다.
/// 그래서 폭을 재는 일(TextPainter)만 위젯에 두고, **몇 개를 보일지 정하는
/// 규칙**은 순수 함수로 빼서 테스트가 숫자로 못 박게 한다.
///
/// 폭은 호출부가 [widthOf]/[overflowWidthOf]로 넘긴다 — 여기서 글꼴을 알 필요가
/// 없고, 테스트는 "한 글자 = 10" 같은 가짜 자로 규칙만 확인할 수 있다.
library;

/// 한 줄에 실제로 그릴 칩들과, 뒤로 접힌 개수.
typedef FeatureChipFit = ({List<String> visible, int hidden});

/// [labels]를 [maxWidth] 한 줄에 맞춰 자른다. 넘치면 마지막 자리를 '+N' 칩에
/// 내준다.
///
/// 규칙 셋:
///   ① 다 들어가면 '+N'을 만들지 않는다 — 자리가 남는데 '+0'이 서는 일이 없다.
///   ② '+N'의 폭도 자리 계산에 넣는다. 접힌 개수가 늘면 '+N'이 넓어질 수 있어
///      ('+9' vs '+12') 개수를 줄여 가며 맞춰 본다 — 안 그러면 '+N'이 줄 밖으로
///      밀려 나간다.
///   ③ 한 개도 못 맞추면 **첫 칩은 그래도 보여준다**(줄임표로 잘리더라도).
///      '+4'만 남은 줄은 아무것도 알려주지 않는다.
///
/// 순서는 [labels] 그대로 앞에서부터다 — 호출부가 이미 중요한 것을 앞에 두고
/// 넘긴다(고른 필터가 맨 앞: [PlaceFeatures.highlightLabelsOf]의 `prefer`).
FeatureChipFit fitFeatureChips({
  required List<String> labels,
  required double maxWidth,
  required double spacing,
  required double Function(String label) widthOf,
  required double Function(int hidden) overflowWidthOf,
}) {
  if (labels.isEmpty) return (visible: const <String>[], hidden: 0);

  double rowWidth(int take) {
    var w = 0.0;
    for (var i = 0; i < take; i++) {
      w += (i == 0 ? 0.0 : spacing) + widthOf(labels[i]);
    }
    return w;
  }

  // ① 전부 들어가는가.
  if (rowWidth(labels.length) <= maxWidth) {
    return (visible: List<String>.unmodifiable(labels), hidden: 0);
  }

  // ② '+N' 자리를 남기고 담을 수 있는 최대 개수.
  for (var take = labels.length - 1; take >= 1; take--) {
    final hidden = labels.length - take;
    if (rowWidth(take) + spacing + overflowWidthOf(hidden) <= maxWidth) {
      return (
        visible: List<String>.unmodifiable(labels.take(take)),
        hidden: hidden,
      );
    }
  }

  // ③ 첫 칩 하나는 남긴다.
  return (
    visible: List<String>.unmodifiable([labels.first]),
    hidden: labels.length - 1,
  );
}

/// '+N' 칩의 문구 — 접힌 개수가 0이면 칩 자체를 그리지 않는다.
String featureOverflowLabel(int hidden) => '+$hidden';
