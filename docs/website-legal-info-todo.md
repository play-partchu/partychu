# TODO — 웹사이트 사업자 고지정보 미비

**B-3(회원 탈퇴)와 무관한 별건입니다.** B-3 배포와 섞지 말고 따로 처리하세요.
2026-08-18 QA 중 발견했고, **현재 운영(https://partychu-30c24.web.app)에 그대로 게시돼 있습니다**
— 이번 배포가 만들어내는 문제가 아니라 이미 나가 있는 상태입니다.

## 고쳐야 할 것

### 1. 미기입 placeholder (index.html)

- [`website/index.html:312`](../website/index.html#L312) — `통신판매업신고번호: [제0000-서울00-0000호]`
  대괄호째 그대로 게시 중. 실제 신고번호로 교체해야 합니다.
- [`website/index.html:305`](../website/index.html#L305) — `<!-- 사업자정보: 실제 정보 확정 시 아래 placeholder를 교체하세요 -->`
  작업 지시 주석이 남아 있습니다. 교체 후 삭제.
- [`website/index.html:253`](../website/index.html#L253) — `<p>[support@partychu.co.kr]</p>`
  대괄호 표기. 주소 자체는 맞지만 placeholder처럼 보입니다.

### 2. 전화번호 누락

사이트 어디에도 전화번호가 없습니다. 전자상거래법 제10조(사업자의 신원 등에 관한 표시)는
**상호·대표자·주소·전화번호·이메일·사업자등록번호·통신판매업신고번호**를 요구합니다.
현재 전화번호와 통신판매업신고번호 둘이 비어 있습니다.

### 3. 페이지마다 고지 수준이 다름

`index.html` 푸터에만 주소·통신판매업신고번호·이메일이 있고,
`privacy.html` · `account-deletion.html` · `terms.html` · `refund.html` 푸터에는
상호·대표자·사업자등록번호 3줄만 있습니다. 푸터를 공통 컴포넌트로 빼거나
네 페이지에 같은 블록을 복사해 맞추는 편이 낫습니다.

## 확인된 정상 항목 (참고 — 다시 볼 필요 없음)

- `privacy.html` / `account-deletion.html` 본문에는 placeholder가 없고,
  개인정보보호책임자 고지(성명 박효정 · 직책 대표 · privacy@partychu.co.kr)도 채워져 있습니다.
- 두 페이지의 링크 18개는 전부 정상 해석됩니다.

## 주의

`firebase deploy --only hosting:website`는 `website/` 전체를 올리므로,
이 항목을 고치지 않은 채 배포하면 placeholder가 그대로 다시 나갑니다.
또한 같은 배포에 `website/.well-known/assetlinks.json`의 패키지명 변경
(`com.example.party_app` → `kr.co.partychu.app`)이 함께 실립니다 —
그 건의 선후 조건은 [`PACKAGE_RENAME_CHECKLIST.md`](../PACKAGE_RENAME_CHECKLIST.md) 참고.
