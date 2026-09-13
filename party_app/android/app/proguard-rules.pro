# ProGuard/R8 규칙 — release 빌드에서만 적용된다.
#
# 이 파일은 Flutter Gradle 플러그인이 **존재하면 자동으로** 릴리즈 빌드에
# 붙인다(FlutterPlugin.kt: `if (File(".../proguard-rules.pro").exists())
# proguardFile("proguard-rules.pro")`). 그래서 android/app/build.gradle.kts에는
# 아무것도 더 적지 않는다 — 거기에 proguardFiles를 또 쓰면 같은 파일이 두 번
# 들어간다.
#
# ── 왜 필요했나 ────────────────────────────────────────────────────────
# 네이버 로그인이 **release(Play 설치본)에서만** "창이 열렸다 그냥 닫힘"으로
# 실패했다. 디버그는 정상이었다. 릴리즈 산출물의 usage.txt를 보니 R8이
# com.navercorp.nid 클래스를 32개 통째로 지웠다:
#
#   NidOAuthQuery / NidOAuthIntent / NidOAuthConstants     (요청 생성)
#   NidOAuthApi / NidOAuthLoginService$DefaultImpls        (토큰 교환)
#   NidProfileApi / NidProfileService                      (프로필 조회)
#   NidOAuthCookieManager / NidOAuthException
#
# 반면 keep된 것은 매니페스트에서 유도된 액티비티 두 개(NidOAuthBridgeActivity,
# NidOAuthCustomTabActivity)뿐이었다. 그래서 **네이버 앱은 열리는데 돌아온
# 뒤의 처리가 없는** 상태가 됐고, 증상이 정확히 그 모양이었다.
#
# 근본 원인은 이 SDK들이 consumer proguard 규칙을 제공하지 않는다는 것이다
# (flutter_naver_login 2.1.1 · com.navercorp.nid:oauth 5.10.0 둘 다 없음).
# Retrofit 인터페이스는 리플렉션(동적 프록시)으로만 쓰이므로 R8이 참조를 못
# 보고 "안 쓰는 코드"로 판단한다 — 규칙으로 직접 남겨 주는 수밖에 없다.

# ── 네이버 로그인 SDK ──────────────────────────────────────────────────
-keep class com.navercorp.nid.** { *; }
-keep interface com.navercorp.nid.** { *; }
-dontwarn com.navercorp.nid.**

# ── flutter_naver_login 플러그인 ───────────────────────────────────────
# 패키지명이 실제로 `com.example.*`이다(플러그인이 그대로 배포됐다) — 오타가
# 아니므로 고치지 말 것.
-keep class com.example.flutter_naver_login.** { *; }
-dontwarn com.example.flutter_naver_login.**

# ── 리플렉션에 필요한 속성 ────────────────────────────────────────────
# Retrofit이 제네릭 시그니처와 메서드 애노테이션을 런타임에 읽는다. retrofit2가
# 자체 규칙으로 일부를 이미 넣지만, 위 keep이 실제로 동작하려면 이 속성들이
# 남아 있어야 한다.
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
