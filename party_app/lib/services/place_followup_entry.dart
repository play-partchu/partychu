// ─────────────────────────────────────────────────────────────────────────────
// 플레이스를 **새로 등록한 직후** — "이 플레이스에서 파티나 매장 이벤트를
// 여시나요?"
//
// ── 왜 여기서 묻나 ───────────────────────────────────────────────────────────
// 플레이스를 막 올린 사장님이 다음에 하려는 일은 대개 둘 중 하나다 — 그 공간의
// 파티를 열거나, 그 공간의 매장 이벤트를 올리는 것. 그런데 지금까지는 저장하면
// 화면이 그냥 닫혀서, 등록 화면으로 되돌아가 유형을 다시 고르고 **어느
// 플레이스인지 또 골라야** 했다.
//
// ── 다시 묻지 않는다 ─────────────────────────────────────────────────────────
// 여기까지 온 사람은 이미 플레이스를 정한 것이다. 그래서
//
//   · 🎉 파티        → 방금 만든 플레이스가 **prelink된** 등록 폼으로 곧장
//     간다([PartyRegisterScreen.forLink]). "내 플레이스 / 새 파티"를 다시
//     묻지 않는다.
//   · 🎪 매장 이벤트 → 방금 만든 플레이스를 **미리 고른** 이벤트 폼으로
//     곧장 간다([PlaceEventEntry.startRegister]의 target).
//
// 무엇이 무엇인지(모집을 받으면 파티, 아니면 매장 이벤트)를 여기서 다시
// 설명하지 않는다 — 카드와 안내는 등록 화면과 **같은 위젯**이 그린다
// ([HostOfferingChoice]).
//
// ── 새로 만들지 않은 것 ──────────────────────────────────────────────────────
// 연결 스키마도 등록 흐름도 하나도 새로 만들지 않았다. 이 시트가 하는 일은
// 이미 있는 [PartyPrelinkTarget]/[EventPlaceTarget]을 방금 만든 문서로 채워
// 기존 진입점에 넘기는 것뿐이다.
//
// **수정 저장에는 뜨지 않는다** — 새로 만든 플레이스에만 뜬다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/services/party_create_eligibility.dart';
import 'package:party_app/services/place_event_entry.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/widgets/host_offering_choice.dart';
import 'package:party_app/widgets/web_frame.dart';

class PlaceFollowupEntry {
  PlaceFollowupEntry._();

  /// 방금 만든 플레이스로 후속 질문을 띄운다.
  ///
  /// [placeId]/[placeCollection]은 저장이 끝난 **실제 문서**의 값이고,
  /// [placeData]는 그 문서에 쓴 내용이다(주소·좌표·대표이미지를 파티에 복사하고
  /// 소유자를 검사하는 데 쓴다 — [PlacePartyLink.linkParties] 계약).
  ///
  /// 무엇을 고르든, 아무것도 안 고르든 **호출부는 그대로 화면을 닫으면 된다** —
  /// 이 함수는 되돌려줄 값이 없다.
  static Future<void> show(
    BuildContext context, {
    required String placeId,
    required String placeCollection,
    required Map<String, dynamic> placeData,
    required String placeName,
  }) {
    final linkTarget = placeCollection == 'places'
        ? PartyLinkTarget.rental
        : PartyLinkTarget.place;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // 바깥을 눌러 닫을 수 있다 — "나중에 할게요"와 같은 뜻이라 막지 않는다.
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFF7FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD6E4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '이 플레이스에서 파티나 매장 이벤트를 여시나요?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  // 어디에 붙는지 이름으로 못 박아 둔다 — 다시 고르게 하지
                  // 않는 대신, 무엇이 골라져 있는지는 보여야 한다.
                  placeName.isEmpty ? linkTarget.noun : placeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF6FA0),
                  ),
                ),
                const SizedBox(height: 18),
                // 고르는 카드도 안내 문구도 등록 화면과 **같은 위젯**이다
                // ([HostOfferingChoice]) — 두 자리에서 같은 질문을 다르게
                // 설명하면 "이벤트와 파티가 뭐가 다른가"가 다시 흐려진다.
                // 제목은 위에 이미 있으므로 끈다.
                HostOfferingChoice(
                  dense: true,
                  showTitle: false,
                  onSelect: (kind) async {
                    Navigator.pop(ctx);
                    if (!context.mounted) return;
                    switch (kind) {
                      case HostOffering.party:
                        // 콤보가 아닌 단독 플레이스 등록에서도 파티를 만들 수
                        // 있는 자리라, 파티 등록과 같은 관문을 그대로 지난다.
                        if (!await PartyCreateEligibility.ensure(context)) {
                          return;
                        }
                        if (!context.mounted) return;
                        await Navigator.push(
                          context,
                          webFramedRoute(
                            (_) => PartyRegisterScreen.forLink(
                              target: PartyPrelinkTarget(
                                target: linkTarget,
                                targetId: placeId,
                                data: placeData,
                              ),
                            ),
                          ),
                        );
                      case HostOffering.placeEvent:
                        await PlaceEventEntry.startRegister(
                          context,
                          // target을 주므로 "어느 플레이스인가"를 다시 묻지
                          // 않는다.
                          target: EventPlaceTarget.fromDoc(
                            id: placeId,
                            collection: placeCollection,
                            data: placeData,
                          ),
                        );
                    }
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black54,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      '나중에 할게요',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
