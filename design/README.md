# 디자인 원본

앱에 **번들되지 않는** 원본 그림을 두는 곳이다. `party_app/assets/` 아래는
`pubspec.yaml`이 폴더째 가져가므로 원본을 거기 두면 그대로 앱 용량이 된다.

## partychu_perk_frame_source.png

"파티츄 전용 혜택" 로즈골드 액자 원본(892×1200). 바깥 여백은 흰색, 가운데는
분홍으로 **채워져 있다**.

앱이 쓰는 것은 이 그림에서 두 배경을 투명하게 파낸
`party_app/assets/images/partychu_perk_frame.png` 쪽이다. 색으로 일괄 제거하면
띠에 박힌 잔다이아(거의 흰색)까지 지워지므로, 바깥과 가운데에서 각각 연결된
영역만 flood fill로 파내고 경계를 1px 페더했다.

액자를 새로 그리면 잘라 쓰는 좌표(띠 두께·모서리 조각 크기·명판 위치)를 다시
재야 한다 — `party_app/lib/widgets/partychu_perk_frame.dart` 위쪽의 상수 표에
모여 있고, 왜 그 값인지도 거기 적혀 있다.
