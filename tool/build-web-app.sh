#!/usr/bin/env bash
# party_app(Flutter Web)을 홈페이지의 /app/ 자리로 빌드해 넣는다.
#
# 왜 이렇게 하나:
#   partychu.co.kr은 Firebase Hosting 타깃 하나(website)가 통째로 서비스한다.
#   한 도메인에 두 타깃을 붙일 수 없으므로, 앱 빌드 산출물을 website/app/에
#   **넣어서** 같은 타깃으로 함께 올린다. 별도 서브도메인을 만들지 않는다는
#   결정의 결과다.
#
#   --base-href /app/ 이 반드시 필요하다. 빠뜨리면 앱이 /main.dart.js 처럼
#   루트 기준으로 자원을 찾아 홈페이지 index.html을 받아오고, 화면이 하얗게
#   뜬 채 끝난다.
#
# 사용:  bash tool/build-web-app.sh
# 그 다음: firebase deploy --only hosting:website
set -euo pipefail

# Windows Git Bash는 "/app/" 같은 인자를 윈도우 경로로 바꿔버린다
# (실제로 --base-href가 "C:/Program Files/Git/app/"으로 들어가 빌드가 죽었다).
export MSYS_NO_PATHCONV=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/website/app"

echo "[build-web-app] flutter build web --base-href /app/"
(cd "$ROOT/party_app" && flutter build web --release --base-href /app/)

echo "[build-web-app] website/app/ 갈아끼우기"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -r "$ROOT/party_app/build/web/." "$OUT/"

echo "[build-web-app] 완료 — $OUT"
