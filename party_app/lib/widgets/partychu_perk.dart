import 'package:flutter/material.dart';

/// "파티츄 전용 혜택" — 호스트가 '파티츄 보고 왔어요!' 손님에게 주는 혜택.
///
/// 등록 화면 네 곳(파티 / 플레이스 / 플레이스+파티 / 숙박+파티)이 [
/// PartychuPerkSection]으로 같은 안내 카드와 입력칸을 쓰고, 상세페이지는
/// [PartychuPerkCard]로 크게 노출한다.
///
/// Firestore에는 컬렉션과 무관하게 [kPartychuPerkField] 한 필드로 저장된다 —
/// 예전 문서에는 없으므로 읽는 쪽은 항상 없을 수 있다고 보고 다뤄야 한다
/// ([partychuPerkFrom] 참고).
const String kPartychuPerkField = 'partychuPerk';

const Color _kPink = Color(0xFFFF6FA0);
const Color _kPinkBg = Color(0xFFFFF0F5);
const Color _kPinkBorder = Color(0xFFFFD6E4);

// ── 오픈 이벤트 안내 문구(정본) ──────────────────────────────────────────
// 등록 화면 네 곳이 [PartychuPerkSection] 하나를 쓰므로, 이 두 줄만 고치면
// 모든 화면이 같이 바뀐다. 화면 쪽에 같은 말을 다시 적지 않는다.
//
// 유형(매장/파티)별로 갈리지 않는다 — 어느 쪽이든 받지 않고, 어느 쪽이든
// 파티츄가 부담한다.

/// 오픈 이벤트 첫 줄 — 호스트가 내는 돈이 없다는 사실.
const String kPartychuOpenEventNoCharge = '등록비 · 중개 수수료는 받지 않습니다.';

/// 오픈 이벤트 둘째 줄 — 홍보·광고를 누가 대는지.
const String kPartychuOpenEventAdCoverage = '홍보 · 광고 비용은 파티츄가 전액 부담합니다.';

/// [kPartychuOpenEventAdCoverage] 안에서 특히 눈에 걸려야 하는 대목.
/// 문장을 통째로 굵게만 두면 이 부분이 묻혀서, 여기만 색으로 한 번 더 세운다.
const String kPartychuOpenEventAdEmphasis = '전액 부담합니다';

/// 문서에서 혜택 문구를 꺼낸다 — 없거나 공백뿐이면 null.
String? partychuPerkFrom(Map<String, dynamic>? data) {
  final raw = data?[kPartychuPerkField];
  if (raw is! String) return null;
  final text = raw.trim();
  return text.isEmpty ? null : text;
}

// 목록 카드의 혜택 표시는 **글자 배지가 아니라 왼쪽 위 명판**이다 —
// partychu_perk_plaque.dart의 partychuPerkPlaqueOverlay(로즈골드 명판)를 각 카드
// 껍데기가 덧그린다. 예전의 "🎁 파티츄 전용 혜택" 배지는 카드마다 제목 위 한
// 줄을 통째로 먹어서 없앴고, 그 뒤 잠깐 썼던 카드 전체 액자는 테두리가 사진
// 영역을 먹어 카드 크기가 달라 보였다. 명판은 카드 위에 덧그리기만 하므로
// 카드 크기·여백이 일반 카드와 완전히 같다.
// 혜택 내용 전체는 상세페이지의 [PartychuPerkCard]에서 보여준다.

/// 이 혜택을 **누구에게** 주는 혜택으로 설명할지 — 같은 필드·같은 저장 방식을
/// 쓰지만 안내 문구가 완전히 갈린다.
///
/// 두 쓰임을 한 문구로 뭉개면 어느 쪽이든 틀린 안내가 된다. 매장은 지나가는
/// 손님에게 "파티츄 보고 왔어요"를 받고 혜택을 주는 것이고, 파티는 이미 신청한
/// 참가자에게 현장에서 챙겨 주는 것이다 — 개인 호스트에게 "손님이 매장에서"라고
/// 안내하면 무엇을 적어야 하는지 알 수 없다.
///
/// 문구를 여기 한 곳에 모아 두면 두 변형을 나란히 놓고 비교·수정할 수 있다.
enum PartychuPerkAudience {
  /// 플레이스·장소대여(콤보 등록 포함) — 매장을 방문한 손님에게 주는 혜택.
  store,

  /// 일반 파티 등록·수정 — 파티에 신청한 참가자에게 현장에서 주는 혜택.
  party;

  bool get isParty => this == party;

  /// 오픈 이벤트 안내 두 줄([kPartychuOpenEventNoCharge],
  /// [kPartychuOpenEventAdCoverage])은 유형별로 갈리지 않는다 — 매장이든
  /// 파티든 똑같이 받지 않고 똑같이 부담하는 사실이라, 여기서 갈래를 만들면
  /// 정책이 다른 것처럼 읽힌다.

  /// 무엇을 적어야 하는지 한 줄로 말하는 굵은 문구.
  String get pitch => switch (this) {
    store => '고객에게는 매력적인 혜택을 더해 매장을 알려보세요.',
    party => '참가자에게는 매력적인 혜택을 더해 파티를 알려보세요.',
  };

  /// 위 문구를 받쳐 주는 설명 — 효과는 단정하지 않는다("이어질 수 있어요").
  /// 명패 노출과 보조 가중치까지가 우리가 보장할 수 있는 전부다.
  String get pitchDetail => switch (this) {
    store =>
      '생맥주 한 잔, 방문 할인, 웰컴드링크, 안주 서비스처럼 작은 혜택도 '
          '고객에게는 매장을 선택하는 이유가 되고, 새로운 방문과 참여로 이어질 '
          '수 있어요.',
    party =>
      '웰컴드링크, 간단한 간식, 안주 서비스, 기념품처럼 작은 혜택도 '
          '참가자에게는 파티를 선택하는 이유가 되고, 새로운 신청과 참여로 이어질 '
          '수 있어요.',
  };

  /// 강조 박스 첫 줄(굵게).
  String get noticeTitle => switch (this) {
    store => '※ 파티츄 전용 혜택은 현장에서만 이용할 수 있습니다.',
    party => '※ 파티 현장에서 참가자에게 직접 제공하는 혜택입니다.',
  };

  /// 강조 박스 본문 — "이건 아니다"까지 분명히 적는다.
  String get noticeBody => switch (this) {
    store =>
      '손님이 매장에서 "파티츄 보고 왔어요."라고 말씀하시면 제공할 혜택을 '
          '등록해주세요. 온라인 쿠폰이나 예약·결제 단계의 할인이 아닙니다.',
    party =>
      '파티 당일 현장에서 참가자에게 직접 건네주는 혜택입니다. 온라인 쿠폰이 '
          '아니고, 참가비를 깎아주는 할인도 아닙니다 — 참가비 할인은 얼리버드 '
          '기능을 이용해주세요.',
  };

  /// 예시 목록 — 전부 "혜택 내용"만 적는다(안내 문구를 섞으면 상세화면이 붙이는
  /// 안내와 중복된다).
  ///
  /// **현장에서 바로 건네줄 수 있는 것만 넣는다.** 참가비 할인처럼 결제 단계에
  /// 얽히는 예시는 온라인 쿠폰으로 오해되고, 실제로 파티츄가 결제 금액을
  /// 깎아주지도 않으므로 넣지 않는다(참가비 할인은 얼리버드 기능이 담당).
  List<String> get examples => switch (this) {
    store => const [
      '생맥주 1잔 무료',
      '방문 시 10% 할인',
      '웰컴드링크 제공',
      '안주 1종 서비스',
      '디저트 제공',
      '음료 무료 제공',
    ],
    party => const [
      '웰컴드링크 제공',
      '간단한 간식 제공',
      '안주 1종 서비스',
      '기념품 증정',
      '디저트 제공',
      '음료 무료 제공',
    ],
  };

  /// 입력칸 바로 위 안내 — 위 박스를 지나쳤어도 이 줄만 읽고 쓸 수 있어야 한다.
  String get fieldGuide => switch (this) {
    store =>
      '손님이 매장에서 "파티츄 보고 왔어요."라고 말씀하실 때 바로 드릴 수 있는 '
          '혜택을 적어주세요.',
    party =>
      '파티 현장에서 참가자에게 바로 드릴 수 있는 혜택을 적어주세요. '
          "혜택이 없다면 '없음'이라고 적지 말고 비워두시면 됩니다.",
  };

  /// 입력칸 placeholder.
  String get hintText => switch (this) {
    store => '예) 생맥주 1잔 무료 (현장에서 제공)',
    party => '예) 참가자 웰컴드링크 제공',
  };

  /// 상세페이지 혜택 카드 아래에 붙는 안내 — 손님/참가자가 읽는 줄이다.
  String get detailFootnote => switch (this) {
    store =>
      "현장에서만 제공되는 혜택입니다. 방문하실 때 '파티츄 보고 왔어요!'라고 "
          '말씀해주세요.',
    party => '파티 현장에서 참가자에게 제공되는 혜택입니다.',
  };
}

/// 등록 화면 공통 "파티츄 전용 혜택" 섹션 — 연핑크 안내 카드 + 입력칸.
///
/// 각 등록 화면의 카드 스타일과 섞이지 않도록 자기 배경/여백을 직접 갖는다.
/// 그래서 어느 화면의 ListView에든 그대로 끼워 넣을 수 있다.
///
/// 문구는 [audience]에만 달려 있다 — 레이아웃·저장 방식은 두 쓰임이 완전히
/// 같으므로 한 위젯으로 두고 말만 갈아 끼운다.
class PartychuPerkSection extends StatelessWidget {
  final TextEditingController controller;

  /// 누구에게 주는 혜택인지 — 기본값은 매장(플레이스·장소대여).
  final PartychuPerkAudience audience;

  const PartychuPerkSection({
    super.key,
    required this.controller,
    this.audience = PartychuPerkAudience.store,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: _kPinkBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPinkBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🌟 파티츄 오픈 이벤트!',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _kPink,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          // 오픈 이벤트의 알맹이 두 줄 — 비용 이야기라 지나치면 안 되는 자리다.
          // 다른 문단(0xFF4A5568 보통 굵기)과 달리 진한 글자에 굵게 두고,
          // '전액 부담합니다'만 한 단계 더 세워 눈에 먼저 걸리게 한다.
          const Text(
            kPartychuOpenEventNoCharge,
            style: TextStyle(
              fontSize: 13.5,
              color: Color(0xFF2D3748),
              height: 1.6,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          _adCoverageLine(),
          const SizedBox(height: 10),
          Text(
            audience.pitch,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF2D3748),
              height: 1.6,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          // 효과는 단정하지 않는다 — 실제로는 명패 노출과 보조 가중치까지가
          // 우리가 보장할 수 있는 전부다(아래 노출 안내 문구와 같은 톤).
          Text(
            audience.pitchDetail,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4A5568),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          // 현장 전용이라는 점은 안내문 중에서 가장 오해가 잦은 지점이라, 다른
          // 문단과 달리 색 채운 박스로 따로 세워 눈에 걸리게 한다.
          _onSiteOnlyNotice(),
          const SizedBox(height: 12),
          // 실제 동작과 정확히 맞춘 문구 — 명패는 확정(목록 카드에 항상 붙는다),
          // 우선 노출은 "같은 검색 조건 안에서만" 주는 보조 가중치라 단정하지
          // 않는다(PartychuPerkRanking 참고).
          const Text(
            "혜택을 등록하면 목록 카드에 '파티츄 혜택' 명패가 표시되며, 동일한 "
            '검색 조건에서는 혜택이 있는 게시물이 우선 노출될 수 있습니다.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF4A5568),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '예시 혜택 — 현장에서 바로 제공 가능한 것',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: _kPink,
                  ),
                ),
                const SizedBox(height: 8),
                for (final example in audience.examples)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(fontSize: 13, color: Colors.black45),
                        ),
                        Expanded(
                          child: Text(
                            example,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF4A5568),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '파티츄 전용 혜택',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          // 입력 바로 위에서 한 번 더 짚어준다 — 위 안내 박스를 지나쳤어도
          // 무엇을 적어야 하는지 이 줄만 읽고 알 수 있어야 한다.
          Text(
            audience.fieldGuide,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF7A8394),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: 2,
            decoration: InputDecoration(
              // 혜택 "내용"만 적게 한다 — 상세화면이 혜택 아래에 안내
              // ([PartychuPerkAudience.detailFootnote])를 항상 자동으로
              // 붙여주므로, 혜택 내용에 같은 말이 또 들어가면 중복된다.
              hintText: audience.hintText,
              hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kPinkBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kPink, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "홍보 · 광고 비용은 파티츄가 **전액 부담합니다**." 한 줄.
  ///
  /// 문장 전체가 굵어서 그 안의 핵심이 묻히지 않도록,
  /// [kPartychuOpenEventAdEmphasis] 대목만 강조색으로 한 단계 더 세운다.
  /// 강조할 대목은 문장에서 찾아 쪼갠다 — 문구를 고칠 때 두 상수만 맞춰 두면
  /// 여기는 따라오고, 못 찾으면 굵은 한 줄로 그대로 그린다.
  Widget _adCoverageLine() {
    const base = TextStyle(
      fontSize: 13.5,
      color: Color(0xFF2D3748),
      height: 1.6,
      fontWeight: FontWeight.bold,
    );
    const emphasis = TextStyle(
      fontSize: 13.5,
      color: _kPink,
      height: 1.6,
      fontWeight: FontWeight.w900,
    );

    const line = kPartychuOpenEventAdCoverage;
    const mark = kPartychuOpenEventAdEmphasis;
    final at = line.indexOf(mark);
    if (at < 0) return const Text(line, style: base);

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: line.substring(0, at)),
          TextSpan(text: mark, style: emphasis),
          TextSpan(text: line.substring(at + mark.length)),
        ],
      ),
    );
  }

  /// "현장 전용" 안내 — 이 섹션에서 가장 오해가 잦은 내용이라 본문 문단과
  /// 다르게 생긴 박스로 세운다. 섹션 배경([_kPinkBg])보다 한 톤 진한 분홍에
  /// 진한 핑크 테두리라, 흰 배경인 "예시 혜택" 박스와도 확실히 구분된다.
  ///
  /// 온라인 쿠폰·할인으로 착각한 채 등록하면 손님/참가자와 호스트 사이에서 바로
  /// 분쟁이 되므로, 아니라는 말까지 분명히 적는다.
  Widget _onSiteOnlyNotice() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE7EF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _kPink),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          audience.noticeTitle,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: _kPink,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          audience.noticeBody,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF4A5568),
            height: 1.6,
          ),
        ),
      ],
    ),
  );
}

/// 상세페이지에서 "파티츄 전용 혜택"을 크게 보여주는 카드.
///
/// 혜택이 없으면 [SizedBox.shrink]를 돌려주므로 호출하는 쪽에서 따로
/// 분기하지 않아도 된다.
class PartychuPerkCard extends StatelessWidget {
  final String? perk;

  /// 화면마다 카드 바깥 여백이 달라 호출하는 쪽에서 넘긴다.
  final EdgeInsets margin;

  /// 카드 아래 안내 한 줄을 가르는 값 — 매장 상세는 "'파티츄 보고 왔어요'라고
  /// 말씀해주세요", 파티 상세는 "참가자에게 제공되는 혜택"이다. 파티에는 매장
  /// 응대 문구가 맞지 않아 반드시 갈라 준다.
  final PartychuPerkAudience audience;

  const PartychuPerkCard({
    super.key,
    required this.perk,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.audience = PartychuPerkAudience.store,
  });

  /// 문서 맵에서 바로 만들 때 쓰는 편의 생성자.
  PartychuPerkCard.fromData(
    Map<String, dynamic>? data, {
    super.key,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.audience = PartychuPerkAudience.store,
  }) : perk = partychuPerkFrom(data);

  @override
  Widget build(BuildContext context) {
    final text = perk?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: _kPinkBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPink, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🎁', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text(
                '파티츄 전용 혜택',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kPink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D3748),
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 등록 화면과 같은 톤으로 "현장 전용"임을 여기서도 밝힌다 — 온라인
          // 쿠폰처럼 알고 갔다가 현장에서 어긋나는 일을 막는다.
          Text(
            audience.detailFootnote,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF7A8394),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
