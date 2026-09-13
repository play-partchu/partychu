#!/usr/bin/env bash
# R2 CORS 검증 — 적용 "전"에도 "후"에도 같은 명령으로 돌린다.
#
# 브라우저 없이 확인할 수 있는 것만 여기서 한다(A·B·G, 그리고 동영상 경로가
# R2와 무관하다는 확인). 실제 업로드(D·F)와 화면 표시(C·E)는 로그인이 필요해
# docs/web-app-hosting.md 의 체크리스트를 따른다.
#
# 사용:  bash tool/verify-r2-cors.sh
set -uo pipefail

ACCOUNT_ID=0010035a696042d03abfd8926e3d4a77
BUCKET=partychu-images
PUBLIC_HOST=pub-c00f710b36c24bdbbea4bb02247c9c5b.r2.dev

# 이미 올라가 있는 아무 이미지 하나(읽기 확인용). 지워졌으면 다른 키로 바꾼다.
SAMPLE_KEY=party_images/ws3COMBLLXPlI4IyhLnwtGF1evS2/1785896509801.jpg

ORIGIN_PROD=https://partychu.co.kr
ORIGIN_EVIL=https://evil.example.com

S3_URL="https://${ACCOUNT_ID}.r2.cloudflarestorage.com/${BUCKET}/${SAMPLE_KEY}"
PUB_URL="https://${PUBLIC_HOST}/${SAMPLE_KEY}"

pass=0; fail=0
hdr() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }

# 응답 헤더를 통째로 받아 온다(대소문자 무시하고 뒤에서 grep).
fetch_headers() { curl -s -o /dev/null -D - -m 25 "$@" 2>/dev/null; }
status_of()     { printf '%s' "$1" | head -1 | awk '{print $2}'; }
header_of()     { printf '%s' "$1" | grep -i "^$2:" | head -1 | sed "s/^[^:]*: *//" | tr -d '\r'; }

# ── A. presigned PUT 대상 호스트의 preflight ───────────────────────────────
hdr "A. OPTIONS preflight (PUT) — ${ACCOUNT_ID}.r2.cloudflarestorage.com"
res=$(fetch_headers -X OPTIONS -H "Origin: ${ORIGIN_PROD}" \
        -H "Access-Control-Request-Method: PUT" \
        -H "Access-Control-Request-Headers: content-type" "$S3_URL")
code=$(status_of "$res"); acao=$(header_of "$res" access-control-allow-origin)
acam=$(header_of "$res" access-control-allow-methods)
acah=$(header_of "$res" access-control-allow-headers)
echo "  status=$code allow-origin=${acao:-<없음>} allow-methods=${acam:-<없음>} allow-headers=${acah:-<없음>}"
case "$code" in 2*) ok "preflight 2xx";; *) bad "preflight가 2xx가 아니다 ($code) — 웹 업로드 불가";; esac
[ "$acao" = "$ORIGIN_PROD" ] && ok "allow-origin이 요청 origin과 일치" \
  || bad "allow-origin이 '$ORIGIN_PROD' 와 다르다 (${acao:-없음})"
printf '%s' "$acam" | grep -qi PUT && ok "PUT 허용" || bad "PUT이 allow-methods에 없다"
printf '%s' "$acah" | grep -qi content-type && ok "content-type 허용" || bad "content-type이 allow-headers에 없다"

# ── B. 공개 읽기 호스트의 GET 응답에 ACAO가 붙는가 ─────────────────────────
hdr "B. GET (이미지 표시) — ${PUBLIC_HOST}"
res=$(fetch_headers -H "Origin: ${ORIGIN_PROD}" "$PUB_URL")
code=$(status_of "$res"); acao=$(header_of "$res" access-control-allow-origin)
echo "  status=$code allow-origin=${acao:-<없음>}"
case "$code" in 2*) ok "이미지 GET 2xx";; *) bad "이미지 GET 실패 ($code) — SAMPLE_KEY가 아직 존재하는지 확인";; esac
[ "$acao" = "$ORIGIN_PROD" ] && ok "allow-origin이 요청 origin과 일치" \
  || bad "GET 응답에 allow-origin이 없다/다르다 (${acao:-없음}) — 카드 이미지가 비어 보인다"

# ── G. 다른 origin은 허용되지 않아야 한다 ─────────────────────────────────
hdr "G. 임의 origin 차단 — ${ORIGIN_EVIL}"
res=$(fetch_headers -X OPTIONS -H "Origin: ${ORIGIN_EVIL}" \
        -H "Access-Control-Request-Method: PUT" \
        -H "Access-Control-Request-Headers: content-type" "$S3_URL")
code=$(status_of "$res"); acao=$(header_of "$res" access-control-allow-origin)
echo "  status=$code allow-origin=${acao:-<없음>}"
if [ -z "$acao" ]; then ok "preflight에 allow-origin이 없다(차단)"
elif [ "$acao" = "*" ]; then bad "'*' 로 열려 있다 — 정책을 다시 확인할 것"
else bad "예상치 못한 allow-origin: $acao"; fi

res=$(fetch_headers -H "Origin: ${ORIGIN_EVIL}" "$PUB_URL")
acao=$(header_of "$res" access-control-allow-origin)
if [ -z "$acao" ]; then ok "GET 응답에도 allow-origin이 없다(차단)"
elif [ "$acao" = "*" ]; then bad "GET이 '*' 로 열려 있다"
else bad "예상치 못한 allow-origin: $acao"; fi

# ── F(사전확인). 동영상 경로는 R2와 무관하다 ──────────────────────────────
hdr "F(사전확인). Cloudflare Stream — R2 정책과 무관한지"
res=$(fetch_headers -X OPTIONS -H "Origin: ${ORIGIN_PROD}" \
        -H "Access-Control-Request-Method: POST" \
        -H "Access-Control-Request-Headers: content-type" \
        "https://upload.videodelivery.net/0000000000000000000000000000000000")
code=$(status_of "$res"); acao=$(header_of "$res" access-control-allow-origin)
echo "  status=$code allow-origin=${acao:-<없음>}"
[ -n "$acao" ] && ok "Stream 업로드 엔드포인트가 이미 CORS를 허용한다(추가 설정 불필요)" \
  || bad "Stream 업로드 엔드포인트에 CORS가 없다 — 동영상 업로드를 따로 확인할 것"

printf '\n통과 %d · 실패 %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
