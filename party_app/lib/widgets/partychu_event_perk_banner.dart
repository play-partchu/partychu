// ─────────────────────────────────────────────────────────────────────────────
// 이벤트 등록 화면 맨 위의 "파티츄 오픈혜택" 영역.
//
// **호스트가 입력하는 칸이 아니다.** 그래서 아래 등록 폼과 색·테두리를 다르게
// 잡고(폼은 흰 바탕 + 회색 테두리, 여기는 금색 계열) 끝에 구분선을 둬서
// "여기까지는 읽는 것, 아래부터는 쓰는 것"이 한눈에 갈리게 한다.
//
// 보여줄 안내가 없으면 **영역째 사라진다** — 빈 카드가 폼 위에 남지 않는다
// (판정은 전부 [PartychuEventPerkService.parse]에 있다).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:party_app/services/partychu_event_perk_service.dart';
import 'package:party_app/widgets/partychu_ui.dart';

class PartychuEventPerkBanner extends StatelessWidget {
  const PartychuEventPerkBanner({super.key});

  // 금색 계열의 정본은 앱 팔레트 하나다 — 상세의 ✨ 매장 이벤트 카드도 같은
  // 선을 두르므로, 같은 값을 두 곳에 적어 두면 언젠가 갈라진다.
  static const Color _bg = PartyChuColors.eventGoldBg;
  static const Color _border = PartyChuColors.eventGold;
  static const Color _ink = Color(0xFF8A6417);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PartychuEventPerk?>(
      stream: PartychuEventPerkService.watch(),
      builder: (context, snapshot) {
        // 아직 못 읽었거나 읽기에 실패했으면 자리만 비운다 — 안내 하나 때문에
        // 등록 화면이 로딩으로 멈추거나 오류를 띄우지 않는다.
        final perk = snapshot.data;
        if (perk == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      perk.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    if (perk.message.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        perk.message,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: Color(0xFF6B5417),
                        ),
                      ),
                    ],
                    for (final item in perk.items) ...[
                      const SizedBox(height: 10),
                      _perkCard(item),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // 읽는 영역과 쓰는 영역의 경계.
              Row(
                children: [
                  const Expanded(child: Divider(height: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '아래부터 내 이벤트 등록',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.black.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(height: 1)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _perkCard(PartychuEventPerkItem item) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _border.withValues(alpha: 0.7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.title.isNotEmpty)
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        if (item.title.isNotEmpty && item.description.isNotEmpty)
          const SizedBox(height: 4),
        if (item.description.isNotEmpty)
          Text(
            item.description,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Colors.black54,
            ),
          ),
      ],
    ),
  );
}
