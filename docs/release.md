# Windows 릴리스 규칙

> Windows 릴리스의 완료 기준은 실행 가능한 ZIP이 GitHub Assets에 게시되고 익명 다운로드 해시까지 일치하는 것이다.

## 배포물

같은 태그의 Windows ZIP과 Android APK를 GitHub Assets에 올린다. Windows ZIP에는 `meme_searcher.exe`, `meme_updater.exe`, Flutter 및 플러그인 DLL, WebView2 로더, `data`, 런타임 라이선스, `README.md`, `THIRD_PARTY_NOTICES.md`, `RELEASE-BUILD.json`이 들어간다. Android 배포 파일은 `meme-searcher-v<버전>-android.apk`다.

## 필수 순서

1. 깨끗한 최종 커밋에서 `VERSION`을 확정하고 `git rev-list --count HEAD`로 네 번째 버전 숫자를 정한다.
2. `tools/build-windows-release.ps1 -ExpectedTag vX.Y.Z.N`을 실행한다. 이 스크립트는 의존성, 분석, 전체 테스트, Windows Release 빌드와 PE/출처 기록을 검증한다.
3. `tools/build-android-release.ps1 -ExpectedTag vX.Y.Z.N`으로 서명 APK를 빌드한다. Android 버전 이름도 `X.Y.Z.N`이고 버전 코드는 `N`이다.
4. `tools/package-windows-release.ps1 -ExpectedTag vX.Y.Z.N -IncludeAndroid`를 실행한다. Windows ZIP을 새 폴더에 풀어 실행하고 Android에서 APK 설치·실행을 확인한다. `SHA256SUMS.txt`에 두 파일의 해시가 들어간다.
5. 최종 커밋에만 주석 태그를 만들고 푸시한다. 기존 태그와 릴리스를 덮어쓰지 않는다.
6. 초안 릴리스에 Windows ZIP, Android APK, `SHA256SUMS.txt`를 올리고 업로드한 에셋의 크기·해시를 대조한 뒤 공개한다.
7. 로그인하지 않은 상태로 asset을 내려받아 SHA-256을 다시 대조한다.

태그를 푸시한 뒤 패키지 스크립트에 `-IncludeAndroid -Publish`를 함께 전달하면 `gh`가 초안 생성부터 익명 다운로드 확인까지 실행한다. API 키, 사용자 데이터, 개인 경로, PDB 파일은 소스와 배포 파일에 넣지 않는다.

## Android 릴리스 서명

빌드에 Android SDK와 JDK가 필요하다. `ANDROID_HOME`에는 SDK 경로, `MEME_ANDROID_SIGNING_PROPERTIES`에는 저장소 밖에 있는 릴리스 서명 속성 파일의 절대 경로를 지정한다. 속성 파일에는 `storeFile`, `storePassword`, `keyAlias`, `keyPassword`를 둔다. 앱이 기존 설치 위에 업데이트되려면 다음 릴리스에도 같은 서명 키를 사용해야 한다.

## 실패 처리

PE 버전·태그·출처 커밋·해시가 하나라도 다르면 게시하지 않는다. 누락 런타임 파일이나 ZIP 재열기 실패도 중단 사유다. 이미 공개된 릴리스가 있으면 새 버전을 만들어야 하며 덮어쓰지 않는다.
