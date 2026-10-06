---
name: sync
description: "작업 종료 시 Git 동기화 — 변경사항을 확인해 커밋 메시지를 작성하고 커밋한 뒤, origin을 다시 fetch해 안전하면 windows/social-login-socialaccount에 push한다. 사용자가 /sync를 직접 입력했을 때만 쓴다."
disable-model-invocation: true
allowed-tools: Bash(git status *) Bash(git fetch *) Bash(git diff *) Bash(git log *) Bash(git add *) Bash(git commit *) Bash(git rev-parse *) Bash(git rev-list *) Bash(git branch *) Bash(git pull --ff-only *) Bash(git ls-files *) Bash(git check-ignore *) Bash(git show *) Bash(git push origin windows/social-login-socialaccount)
---

# /sync — 작업 마무리 동기화

**정상 상황에서는 끝까지 멈추지 않고 진행한다.** 단계마다 승인을 묻지 않는다.
아래 "반드시 멈추는 경우"에 해당할 때만 중단하고 묻는다.

공용 개발 브랜치: `windows/social-login-socialaccount`

## 1. 무엇이 바뀌었는지 본다

```
git status --short
git diff --stat
git diff --stat --cached
```

## 2. 담을 것과 뺄 것을 가른다

**생성·캐시·임시 파일은 담지 않는다.** 경로를 **하나씩 지정해서** `git add`
한다 — `git add -A`나 `git add .`는 쓰지 않는다. 루트 `.gitignore`가 대부분을
막지만, 규칙이 없는 새 생성물이 조용히 섞여 들어가는 것을 막으려면 담을 것을
직접 고르는 편이 안전하다.

담지 않는 것(대부분 `.gitignore`가 이미 막는다):

| 경로 | 이유 |
|---|---|
| `functions/node_modules/`, `platform-tools/` | 추적을 끊었다 — 다시 담지 않는다 |
| `**/build/`, `**/.dart_tool/` | 빌드 산출물 |
| `**/.claude/settings.local.json` | 기기 전용 권한 목록(API 키가 섞인다) |
| `.firebase/*.cache` | Firebase 호스팅 배포 캐시(배포할 때만 갱신) |
| `.DS_Store`, `Thumbs.db` | OS 파일 |
| `*.log`, `hs_err_pid*.log`, `replay_pid*.log` | 로그·JVM 크래시 덤프 |
| `party_app/assets/fonts/WIN_seoul_font2/` | 사용자 개인 보관용 폰트 설치 파일(48MB) |
| `functions/.env*`, `**/key.properties`, `*.jks`, `*.keystore` | 시크릿·서명 키 |
| `functions/scripts/.demo-out/` | 운영 Firestore 문서 원문이 들어간다 |

의심스러운 파일이 있으면 담지 말고 **보고한다.** 빼는 쪽이 언제나 안전하다.

## 3. 커밋

메시지는 **변경 내용을 보고** 직접 쓴다. 한 줄 요약(명령형, 72자 이내) +
필요하면 왜 그렇게 했는지 본문. 커밋 메시지 끝에는 이 세션의 attribution
규칙이 요구하는 줄을 붙인다.

커밋 직전에 무엇을 담았는지 한 줄로 말한다(묻지는 않는다).

## 4. 올리기 전에 원격을 다시 본다

```
git fetch origin
git rev-list --count HEAD..origin/windows/social-login-socialaccount
```

- **0이면** 바로 push.
- **0이 아니면** 다른 기기가 올린 커밋이 있다. `git pull --ff-only`를
  시도한다. 내 커밋이 이미 있으므로 fast-forward는 실패하는 것이 정상이다 →
  **`git pull --rebase`로 내 커밋을 원격 위에 다시 얹는다.**
  충돌이 나면 **즉시 멈춘다**(아래 참조).

`--rebase`를 쓰는 이유: 두 기기를 번갈아 쓰는 한 사람의 저장소라 merge
커밋이 쌓이면 기록이 읽히지 않는다. 다만 **이미 push한 커밋을 rebase하지는
않는다** — 여기서 얹는 것은 방금 만든, 아직 원격에 없는 커밋뿐이다.

## 5. push

```
git push origin windows/social-login-socialaccount
```

`--force`, `--force-with-lease`는 **쓰지 않는다.** 필요해 보이면 멈추고 묻는다.

## 6. 확인

```
git rev-parse HEAD
git rev-parse origin/windows/social-login-socialaccount
```

두 해시가 같은지 확인한다. 같으면:

```
동기화 완료 — <짧은 해시> <커밋 제목>
```

다르면 왜 다른지 조사해서 보고한다(성공했다고 말하지 않는다).

## 반드시 멈추고 묻는 경우

1. **merge/rebase 충돌** — 한쪽 코드를 고르거나 지우지 않는다. 충돌 파일
   목록과 양쪽이 무엇을 바꿨는지 보고한다.
2. **예상하지 못한 대량 삭제** — 이번 작업으로 설명되지 않는 삭제가
   **20개 파일 이상**이거나, `lib/`·`functions/`의 소스가 통째로 사라졌으면 멈춘다.
3. **다른 기기의 변경을 덮어쓸 위험** — rebase가 다른 기기의 커밋을 지우게
   되거나, 같은 파일을 양쪽에서 고쳤으면 멈춘다.
4. **force push가 필요한 상황** — 어떤 이유든 멈춘다.
5. **중요한 파일 삭제** — `firestore.rules`, `firebase.json`,
   `*/pubspec.yaml`, `functions/package.json`, `ios/Runner/Runner.entitlements`,
   `android/app/build.gradle*`, Apple 로그인 관련 파일
   (`lib/utils/apple_sign_in.dart` 등)이 삭제 목록에 있으면 멈춘다.
6. **브랜치가 다름** — 현재 브랜치가 `windows/social-login-socialaccount`가
   아니면 push하지 않고 묻는다.

## 절대 하지 않는다

- `git reset --hard`, `git clean -fd`, `git checkout -- .`
- **`git stash`** — 이 저장소에서 금지(미커밋 작업을 잃은 적이 있다)
- `git push --force*`
- 정상 동작하는 앱 소스·Apple 로그인 코드의 삭제나 덮어쓰기
- 배포(`firebase deploy`) — /sync는 Git만 다룬다
