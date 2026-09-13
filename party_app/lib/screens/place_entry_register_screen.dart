import 'package:flutter/material.dart';

import 'package:party_app/models/combo_place_type.dart';
import 'package:party_app/screens/event_register_screen.dart';
import 'package:party_app/screens/place_register_screen.dart';
import 'package:party_app/services/draft_service.dart';

/// 통합 "플레이스 등록" 화면 — 파티 없이 **공간만** 올리는 진입점.
///
/// 예전에는 등록 유형 화면에 "플레이스 등록"(매장)과 "파티 장소 등록"(대여
/// 공간)이 서로 다른 카드로 나뉘어 있었다. 두 카드가 하는 일이 "내 공간을
/// 올린다"로 같아서 어느 쪽을 눌러야 하는지 알 수 없었고, 파티룸·대관 공간을
/// 가진 사장님은 "플레이스 등록"을 자기 것이 아니라고 지나쳤다.
///
/// 그래서 **진입은 하나로 합치고, 화면 최상단에서 [ComboPlaceType]을 고르게
/// 한다.** 선택 위젯([SpaceTypeSelector])도 문구(enum의
/// label·kindLabel·examples)도 정본 하나에서 오므로, 두 유형의 선택이 서로
/// 어긋날 수 없다.
///
/// **이제 신규 플레이스를 만드는 등록 화면은 여기 하나뿐이다.** 플레이스와
/// 파티를 한 폼에서 함께 만들던 콤보 등록은 없어졌고, 파티·이벤트는 저장
/// 직후의 후속 질문([PlaceFollowupEntry])이 방금 만든 플레이스를 그대로 물고
/// 이어준다.
///
/// 이 위젯은 얇은 셸이다 — 고른 유형에 맞는 **기존 등록 화면을 그대로** 띄운다.
///  - [ComboPlaceType.venue] → [EventRegisterScreen] : `events`
///  - [ComboPlaceType.stay]  → [PlaceRegisterScreen] : `places` + `placeRooms`
///
/// **저장 스키마·예약 로직은 유형별 화면이 예전 그대로 갖고 있다.** 진입만
/// 합쳤을 뿐, 어떤 컬렉션에 어떤 셰이프로 쓰는지는 전혀 바뀌지 않았다. 룸·요금·
/// 예약 입력은 [PlaceRegisterScreen]의 것이 그대로 쓰이고, 기존 장소대여 문서와
/// 그 예약 흐름(`placeReservationGroups`·`packageBookings`)도 그대로다.
///
/// 임시저장도 유형별로 따로 보관하던 것을 그대로 쓴다
/// ([ComboPlaceType.soloDraftType] — 옛 `DraftType.event` / `DraftType.place`)
/// 이므로, 합치기 전에 만들어둔 임시저장이 그대로 열린다.
///
/// ⚠️ 두 화면은 서로 완전히 다른 폼이라 **공유할 상태가 없다** — 유형을
/// 바꾸면 화면 입력은 전부 사라진다. 대신 바꾸기 직전에 그 유형의 임시저장을
/// 남기므로([DraftableRegister.saveDraftNow]), 돌아오면 "이어서 작성"으로
/// 복구된다([confirmSpaceTypeChange]가 이 사실을 그대로 안내한다).
class PlaceEntryRegisterScreen extends StatefulWidget {
  /// 처음 보여줄 공간 유형 — 마이페이지 임시저장이나 탭별 등록 버튼처럼
  /// 특정 유형으로 바로 열 때 지정한다. 생략하면 임시저장이 남아 있는 유형,
  /// 그것도 없으면 "매장·즐길거리".
  final ComboPlaceType? initialType;

  /// 마이페이지 "임시저장" 목록에서 "이어서 작성"으로 열 때 true —
  /// [initialType]의 임시저장을 묻지 않고 곧바로 복구한다.
  final bool autoRestoreDraft;

  const PlaceEntryRegisterScreen({
    super.key,
    this.initialType,
    this.autoRestoreDraft = false,
  });

  @override
  State<PlaceEntryRegisterScreen> createState() =>
      _PlaceEntryRegisterScreenState();
}

class _PlaceEntryRegisterScreenState extends State<PlaceEntryRegisterScreen> {
  /// 지금 보여줄 유형. [PlaceEntryRegisterScreen.initialType]이 없으면
  /// "임시저장이 남아 있는 유형"을 찾아 열기 때문에, 다 정해질 때까지 null이다.
  ComboPlaceType? _type;

  /// 화면 안에서 유형을 한 번이라도 바꿨는지 — 바꾼 뒤에는 "이어서 작성"으로
  /// 들어온 자동 복구를 다시 실행하지 않는다(다른 유형의 임시저장을 엉뚱하게
  /// 되살리게 된다).
  bool _switchedType = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialType;
    if (initial != null) {
      _type = initial;
    } else {
      _resolveTypeFromDrafts();
    }
  }

  /// 유형을 지정받지 않고 들어온 경우(등록 유형 화면의 "플레이스 등록"),
  /// **임시저장이 남아 있는 유형으로 연다.**
  ///
  /// 이게 없으면 항상 "매장·즐길거리"로 열려서, 공간대여·숙박으로 작성해둔
  /// 임시저장은 사용자가 유형을 직접 바꾸기 전까지 존재조차 알 수 없다.
  /// (콤보 셸의 _resolveTypeFromDrafts와 같은 규칙 — 보는 임시저장 종류만
  /// 단독 등록용[soloDraftType]으로 다르다.)
  Future<void> _resolveTypeFromDrafts() async {
    var resolved = ComboPlaceType.venue;
    try {
      final venueType = ComboPlaceType.venue.soloDraftType;
      final stayType = ComboPlaceType.stay.soloDraftType;
      final hasVenue = await DraftService.hasDraft(venueType);
      final hasStay = await DraftService.hasDraft(stayType);
      if (hasStay && !hasVenue) {
        resolved = ComboPlaceType.stay;
      } else if (hasStay && hasVenue) {
        // 둘 다 있으면 더 최근에 저장한 쪽을 연다.
        final venueAt = await DraftService.localUpdatedAt(venueType);
        final stayAt = await DraftService.localUpdatedAt(stayType);
        if (stayAt != null && (venueAt == null || stayAt.isAfter(venueAt))) {
          resolved = ComboPlaceType.stay;
        }
      }
      debugPrint(
        '[place-draft] 진입 유형 결정: ${resolved.key} '
        '(venue=$hasVenue stay=$hasStay)',
      );
    } catch (e) {
      debugPrint('[place-draft] 진입 유형 결정 실패, 기본값 사용: $e');
    }
    if (!mounted) return;
    setState(() => _type = resolved);
  }

  /// 폼이 (확인을 받고, 지금 유형의 임시저장을 남긴 뒤) 호출한다.
  void _onTypeChanged(ComboPlaceType next) {
    if (next == _type) return;
    setState(() {
      _type = next;
      _switchedType = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final type = _type;
    if (type == null) {
      // 어느 유형으로 열지 확인하는 아주 짧은 순간 — 폼이 한 번 깜빡이며
      // 바뀌는 것보다 낫다(콤보 셸과 같은 대기 화면).
      return const Scaffold(
        backgroundColor: Color(0xFFF3F4F6),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFF6FA0))),
      );
    }

    // 유형을 바꾸면 그 폼은 완전히 새로 시작한다(공유하는 상태가 없다).
    // 사라진 입력은 방금 저장한 임시저장에 남아 있으므로, 돌아왔을 때
    // 복구 팝업이 그대로 떠야 한다 — offerDraftRestore는 항상 true다.
    final autoRestore = widget.autoRestoreDraft && !_switchedType;
    return switch (type) {
      ComboPlaceType.venue => EventRegisterScreen(
        key: const ValueKey('place-entry-venue'),
        autoRestoreDraft: autoRestore,
        onSpaceTypeChanged: _onTypeChanged,
      ),
      ComboPlaceType.stay => PlaceRegisterScreen(
        key: const ValueKey('place-entry-stay'),
        autoRestoreDraft: autoRestore,
        onSpaceTypeChanged: _onTypeChanged,
      ),
    };
  }
}
