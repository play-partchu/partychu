# partychu — 저장소 안내

Windows 데스크톱과 MacBook **두 기기에서 번갈아** 개발한다. 이 파일은 두 기기의
Claude Code가 같은 규칙으로 움직이게 하려고 둔다.

## 구성

| 경로 | 무엇인가 |
|---|---|
| `party_app/` | 사용자 앱(Flutter · iOS/Android/Web) |
| `admin_app/` | 관리자 웹(Flutter web → Firebase Hosting `admin` 타깃) |
| `functions/` | Cloud Functions(Node) |
| `website/` | 랜딩 페이지 소스. `website/app/`은 Flutter Web 빌드 산출물이고 **Git에 없다**(아래 지뢰 참조) |
| `firestore.rules` / `firestore.indexes.json` / `storage.rules` | Firebase 규칙·색인 |
| `packages/` | 앱·관리자가 함께 쓰는 Dart 패키지 |
| `tool/` | 운영 스크립트·미디어 원본 |

---

## Git 동기화 규칙

**공용 개발 브랜치: `windows/social-login-socialaccount`**
(기본 브랜치는 `master`지만 지금 작업은 전부 이 브랜치에서 한다.)

두 개의 명령으로 감싼다 — 세부 절차는 각 파일에 있다.

| 명령 | 언제 | 정의 |
|---|---|---|
| `/start` | 작업 **시작** 전 | `.claude/skills/start/SKILL.md` |
| `/sync` | 작업 **종료** 시 | `.claude/skills/sync/SKILL.md` |

`.claude/`는 저장소에 함께 추적되므로 두 기기가 같은 명령을 공유한다.
저장소 하위 디렉터리(`party_app/` 등)에서 Claude Code를 실행해도 상위
디렉터리의 `.claude/skills/`를 찾는다.

### 시작할 때

- 반드시 `git status`와 **현재 브랜치**를 먼저 확인한다.
- `git fetch origin`으로 원격 상태를 본다.
- 작업 트리가 clean이고 원격이 앞서 있으면 **`git pull --ff-only`**로 받는다
  (fast-forward가 안 되면 아무 일도 일어나지 않고 실패한다 — 조용한 merge가
  생기지 않는다).
- **미커밋 변경이 있으면 pull·reset·checkout을 자동으로 하지 않는다.**
  변경 파일 목록을 사용자에게 먼저 알린다.
- 다른 기기의 변경을 발견하면 임의로 덮어쓰지 않는다.

### 끝낼 때

- `git status`·`git diff`로 무엇이 바뀌었는지 확인한다.
- **소스와 필요한 프로젝트 파일만** 커밋한다. 경로를 하나씩 지정해 `git add`
  하고 `git add -A`·`git add .`는 쓰지 않는다(아래 "지뢰" 참조).
- 커밋 전에 무엇을 담는지 한 줄로 설명한다.
- push 전에 **origin을 다시 fetch**해 다른 기기의 새 커밋을 확인한다.
- 원격이 앞서 있으면 먼저 안전하게 합친 뒤 push한다.
- push 후 로컬 `HEAD`와 `origin/windows/social-login-socialaccount`가 **같은
  커밋인지 확인**한다. 같지 않으면 성공했다고 말하지 않는다.

### 금지

- **`git stash` 금지.** 이 저장소는 작업 트리가 HEAD보다 앞서 있는 일이 잦아,
  stash가 미커밋 작업을 통째로 숨겨 잃은 적이 있다.
- `git reset --hard`, `git clean -fd`, `git checkout -- .` — 사용자의 명시적
  승인 없이 실행하지 않는다.
- `git push --force` / `--force-with-lease` — 승인 없이 쓰지 않는다.
- merge conflict가 났을 때 한쪽을 임의로 고르거나 지우는 일.
- 정상 동작하는 앱 소스와 **Apple 로그인 코드**의 삭제·덮어쓰기.

---

## 커밋하지 않는 것

생성·캐시·임시·시크릿 파일은 담지 않는다. 루트 `.gitignore`와 각 앱의
`.gitignore`가 대부분 막아 주지만, **이미 추적 중인 파일은 `.gitignore`가
막지 못한다** — 아래 지뢰를 보고 손으로 가린다.

```
node_modules/            **/build/            **/.dart_tool/
.DS_Store  Thumbs.db     *.log                .firebase/*.cache
functions/.env*          key.properties  *.jks  *.keystore
functions/scripts/.demo-out/     (운영 Firestore 원문이 들어간다)
party_app/assets/fonts/WIN_seoul_font2/   (개인 보관용 48MB 설치 파일)
```

---

## 지뢰 — 두 기기 모두 알아야 하는 것

**`functions/node_modules/`가 Git에 추적되고 있다(약 9,600개 파일).**
최초 커밋에 들어가 버려서 `functions/.gitignore`의 `node_modules/` 규칙이
무력하다. 그래서 `functions/node_modules/.package-lock.json`이 `npm` 명령마다
수정 상태로 뜬다. **커밋에 담지 말고 그대로 둔다.** 정리는 사용자 승인이
필요한 별도 작업이다.

**`platform-tools/`는 Windows 전용 바이너리(adb.exe 등 16MB)가 추적된 것이다.**
Mac에서는 쓸 수 없다. Mac에서는 Homebrew 등으로 따로 설치하고 이 디렉터리는
건드리지 않는다.

**`website/app/`은 Git에 없다.** `website/.gitignore`가 `/app/`을 막는다.
새로 clone한 기기에는 이 디렉터리가 아예 없으므로, 호스팅 `website` 타깃을
배포하기 전에 **`tool/build-web-app.sh`를 먼저 돌려야 한다** — 안 돌리면
`/app/` 없이, 또는 낡은 빌드로 배포된다. `admin_app/build/web`도 같다
(추적되지 않으므로 `flutter build web`을 먼저 돌린다).

**배포 상태를 Git으로 판단하지 않는다.** 운영에만 있고 저장소에는 없는 코드가
실제로 있었다. 무엇이 배포돼 있는지는 배포본 원문을 받아 대조해야 안다.

**`flutter test`는 ASCII 경로의 TEMP가 필요하다.** 사용자 홈 경로에 한글이
있어 기본 TEMP로는 실패한다 — `TEMP=C:/fluttertest_tmp`처럼 지정해 실행한다.
Gradle APK 빌드는 프로젝트 경로 자체가 ASCII여야 한다.

**기본 검증은 `flutter analyze` + 관련 테스트만.** `party_app` 전체 테스트는
돌리지 않는다.

**기존 실패 테스트가 있다.** `party_app/test/place_weekly_hours_test.dart`의
기본 프리셋 2건은 이번 작업과 무관하게 깨져 있다 — 내 변경 탓으로 오진하지 않는다.

**커밋·push·배포는 요청받았을 때만 한다.** 스토어 제출은 하지 않는다.

---

## 두 기기 모두에서 쓰는 준비 명령

받아온 뒤 의존성이 바뀌었으면(`/start`가 알려준다):

```sh
# Cloud Functions
cd functions && npm ci

# Flutter 앱 / 관리자 웹
cd party_app && flutter pub get
cd admin_app && flutter pub get
```

Windows는 Git Bash 또는 PowerShell, macOS는 zsh에서 그대로 동작한다.
`firebase` CLI가 PATH에 없을 수 있다 — Windows에서는
`& "$env:APPDATA\npm\firebase.cmd"`로 부른다.
