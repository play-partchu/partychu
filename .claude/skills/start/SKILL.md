---
name: start
description: "작업 시작 전 Git 동기화 — 현재 브랜치·상태를 확인하고 origin/windows/social-login-socialaccount의 최신 커밋을 fast-forward로만 받아온다. 사용자가 /start를 직접 입력했을 때만 쓴다."
disable-model-invocation: true
allowed-tools: Bash(git status *) Bash(git fetch *) Bash(git log *) Bash(git diff *) Bash(git rev-parse *) Bash(git branch *) Bash(git pull --ff-only *) Bash(git remote *)
---

# /start — 작업 시작 동기화

Windows와 MacBook을 번갈아 쓰는 저장소다. **다른 기기가 올려둔 커밋 위에서
작업을 시작**하는 것이 이 명령의 유일한 목적이다.

공용 개발 브랜치: `windows/social-login-socialaccount`

## 순서대로 실행한다

1. **현재 위치 확인**

   ```
   git rev-parse --show-toplevel
   git status -sb
   ```

   저장소 루트가 아니어도 상관없다(git은 어디서 실행해도 같은 저장소를 본다).

2. **원격 상태 받아오기** — 가져오기만 하고 합치지 않는다.

   ```
   git fetch origin
   ```

3. **브랜치 확인.** 현재 브랜치가 `windows/social-login-socialaccount`가
   아니면 **거기서 멈추고** 현재 브랜치 이름과 미커밋 변경 여부를 보고한다.
   자동으로 `checkout`하지 않는다 — 다른 브랜치에서 일부러 작업 중일 수 있고,
   미커밋 변경이 있으면 checkout이 실패하거나 변경을 끌고 넘어간다.

4. **앞뒤 차이 세기**

   ```
   git rev-list --count HEAD..origin/windows/social-login-socialaccount   # 받을 것
   git rev-list --count origin/windows/social-login-socialaccount..HEAD   # 올릴 것
   ```

5. **판단**

   | 상태 | 할 일 |
   |---|---|
   | 받을 것 0 · 올릴 것 0 | "이미 최신" 보고하고 작업 시작 |
   | 받을 것 >0 · 작업 트리 clean | `git pull --ff-only` 실행 |
   | 받을 것 >0 · **미커밋 변경 있음** | **멈춘다.** pull 하지 않고 변경 파일 목록을 보고한다 |
   | 양쪽 다 >0 (갈라짐) | **멈춘다.** 두 쪽 커밋을 각각 보여주고 어떻게 합칠지 묻는다 |

   `--ff-only`를 쓰는 이유: fast-forward가 불가능하면 **아무 일도 일어나지 않고
   실패**한다. 자동 merge 커밋이나 rebase가 조용히 생기지 않는다.

6. **받아온 뒤**에는 무엇이 바뀌었는지 한 줄로 알려준다.

   ```
   git log --oneline HEAD@{1}..HEAD
   ```

   의존성·생성 파일에 영향이 있는 변경이면 함께 알린다:
   - `functions/package.json`·`package-lock.json` → `npm ci` 필요
   - `party_app/pubspec.yaml` → `flutter pub get` 필요

## 절대 하지 않는다

- `git reset --hard`, `git clean -fd`, `git checkout -- .`, `git stash`
  — 어느 것도 사용자의 명시적 지시 없이는 쓰지 않는다.
  특히 **`git stash`는 이 저장소에서 금지**다: 작업 트리가 HEAD보다 앞서 있는
  일이 잦아 stash가 미커밋 작업을 통째로 숨겨 잃은 적이 있다.
- 미커밋 변경이 있는 상태에서의 pull·merge·rebase·checkout.
- 다른 기기의 커밋을 덮어쓰는 모든 동작.

## 멈췄을 때 보고할 내용

- 현재 브랜치
- 미커밋 변경 파일 목록(`git status --short`)
- 받을 커밋 / 올릴 커밋 개수와 제목
- 다음에 할 수 있는 선택지(커밋하고 pull / 변경을 되돌리고 pull / 그대로 작업)

선택지는 **제시만** 하고 고르지 않는다.
