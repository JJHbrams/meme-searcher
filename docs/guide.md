# Meme Snatcher Windows 사용 가이드

## 설치와 실행

1. Windows 10/11 x64에서 최신 릴리스의 **Assets**를 열고 `windows-x64.zip`으로 끝나는 파일을 받으세요. [최신 릴리스](https://github.com/JJHbrams/meme-searcher/releases/latest)
2. ZIP을 폴더 전체로 압축 해제하세요. DLL과 `data` 폴더가 함께 있는 상태에서 `meme_searcher.exe`를 실행합니다.
3. 첫 실행에서 **나중에**를 누르면 키 없이 기본 제공 짤부터 검색할 수 있습니다.

창의 **X**를 누르면 작업 표시줄의 알림 영역(트레이)에 숨겨집니다. EXE를 다시 실행하거나 트레이의 **Meme Snatcher** 아이콘을 클릭하면 보던 창이 열립니다. 아이콘이 보이지 않으면 시계 옆 **∧**를 펼치세요. 트레이에서 우클릭 후 **종료**를 누르면 앱을 완전히 끝냅니다.

Windows가 트레이 아이콘을 등록할 수 없으면 앱이 작업 표시줄로 최소화됩니다. 작업 표시줄을 클릭하거나 EXE를 다시 실행하면 복원됩니다.

NVIDIA 드라이버 `32.0.16.1088`을 사용하는 PC에서는 앱이 시작할 때 이 EXE 경로에만 임시 Direct3D 설정을 적용해 Windows 소프트웨어 렌더러(WARP)를 선택합니다. 그래픽 장치를 만든 뒤 임시 설정을 지웁니다.

**설정 → 업데이트 확인 → 업데이트 설치**를 누르면 새 버전을 받아 검증하고, 현재 실행 폴더에 설치한 뒤 앱을 다시 엽니다. 내 짤과 설정은 이어서 사용할 수 있습니다. 앱에서 설치하려면 현재 실행 폴더에 쓸 수 있어야 합니다.

ZIP 다운로드 버튼만 표시되는 이전 버전은 최신 릴리즈 ZIP의 압축을 한 번 풀어 실행하세요. 이후부터 앱 안에서 설치할 수 있습니다.

## Google 이미지 연결

1. **Google 이미지 검색 연결**에서 SerpApi에 가입하거나 로그인하세요. 첫 실행 안내를 넘겼다면 왼쪽 **설정**에서 열 수 있습니다.
2. **API 키 페이지 열기**를 눌러 본인 키를 복사하고, 앱에서 **복사한 키로 연결**을 선택하세요. 직접 입력도 가능합니다.
3. **웹** 또는 **모두**로 검색하면 Google 이미지 결과를 함께 찾습니다.

왼쪽 아래에서 이번 달 남은 검색 횟수와 추가 크레딧을 확인하세요. 웹 검색을 마치면 자동 갱신되며, 새로고침 버튼으로 다른 앱에서 사용한 횟수도 반영할 수 있습니다. 잔여량 조회는 검색 횟수를 차감하지 않습니다. [SerpApi 계정 API](https://serpapi.com/account-api)

앱은 SerpApi 계정 API로 키를 확인하고 Windows 보안 저장소에 저장합니다. `SERPAPI_API_KEY` 환경 변수도 사용할 수 있습니다. 웹 검색 사용량과 요금은 연결한 서비스의 계정 정책을 따릅니다.

## 검색과 저장

- **전체**에는 **임시 저장** 짤이 처음 저장된 시각을 기준으로 최신순 두 줄까지 보입니다. 카드에서 해당 짤을 찾은 검색어를 확인할 수 있습니다. **펼치기**를 누르면 나머지도 보이고, 아래 **내 짤**에는 복사하거나 직접 보관한 짤이 모입니다. **내 짤** 검색에는 두 곳이 모두 포함됩니다.
- 웹에서 짤을 **복사**, **파일로 복사** 또는 `Ctrl+C`로 복사하면 내 짤에 자동 보관됩니다. 원본을 열 수 없어 **미리보기 이미지 복사**를 선택한 경우에는 그 해상도의 이미지가 보관됩니다.
- 임시 저장이나 내 짤에서 한 장을 지우려면 미리보기를 열고 **삭제**를 누르세요. 여러 장을 지우려면 목록 오른쪽 위의 **선택 삭제**를 누르고 카드를 고른 뒤 삭제할 개수를 확인하세요.
- 검색이나 미리보기에서 받은 파일은 256 MiB까지 임시 보관하며, 한도를 넘으면 가장 오래 사용하지 않은 파일부터 지웁니다. 이전 버전에서 직접 보관한 짤은 내 짤에 유지되고, 이전에 내려받은 파일은 임시 저장에서 찾아볼 수 있습니다.

- 기본 검색 범위 **모두**는 내 짤과 웹 결과를 한 화면에 표시합니다. **전체 / GIF / 이미지**로 형식을 고르고, 검색어에 `#헬다2` 같은 태그를 붙여 범위를 좁힐 수 있습니다.
- 홈에는 최근 사용한 짤, 최근 검색어, 즐겨찾기가 각각 최대 5개씩 표시됩니다. 검색어를 누르면 다시 검색하고, 짤을 누르면 미리보기가 열립니다.
- 미리보기의 **복사** 또는 `Ctrl+C`로 이미지를 복사합니다. 원본 파일을 첨부하려면 **파일로 복사**를, 파일을 PC에 받으려면 **원본 저장**을 누르세요. GIF는 원본 파일로 복사합니다.
- 웹 원본을 열 수 없고 썸네일만 남아 있으면 **미리보기 이미지 복사**로 표시된 해상도의 이미지를 복사할 수 있습니다.

## Codex에서 밈 쓰기

릴리스의 Assets에서 `…-mcp.zip`을 별도로 받아 풉니다. ZIP 안의 `README.md`에 Codex 연결 명령이 들어 있습니다. Node.js와 Codex CLI가 필요합니다. [최신 릴리스](https://github.com/JJHbrams/meme-searcher/releases/latest)

이 저장소를 신뢰하는 Codex 프로젝트로 열면 프로젝트 설정으로도 `meme_snatcher` MCP가 연결됩니다. 설정을 추가하기 전에 열어 둔 세션이라면 새 세션에서 적용을 확인할 수 있습니다.

Codex에 친구와 주고받을 리액션이나 가벼운 축하를 부탁하면 어울리는 기본 짤 또는 즐겨찾기를 답변에 한 장 넣습니다. 고객 안내나 민감한 대화에서는 짤을 쓰지 않습니다. 이미지와 GIF를 모두 지원하며 실제 표시 방식은 Codex 화면에 따라 다릅니다.

“우는 짤 하나 보여줘”처럼 짤을 요청하면 기본 짤과 즐겨찾기를 먼저 찾고, 없으면 실행 중인 Windows 앱의 웹 검색으로 이어집니다. 서랍에서만 찾거나 웹에서 바로 찾도록 따로 요청할 수도 있습니다. Google 이미지는 앱의 SerpApi 설정을 사용합니다.

Codex가 추천한 짤에 대해 명확히 평가하거나 원하는 장면을 알려주면 앱에 피드백을 저장합니다. 새로 저장한 규칙은 Codex 추천과 앱의 직접 검색에 함께 적용됩니다.

## 마법의 소라고동

**마법의 소라고동**은 왼쪽 메뉴에서 열 수 있습니다. 창 폭이 좁으면 하단의 **소라고동**을 누르세요. 질문을 쓴 뒤 그림 속 고리를 당겼다가 놓으면 대답합니다. 키보드로는 고리에 포커스를 옮기고 Space를 눌렀다 놓으세요. **원 위시 윌로우**에서는 하루 한 번 가지를 꺾어 소원을 빌 수 있습니다. 두 놀이는 PC에서 동작하며 검색 횟수를 쓰지 않습니다.

## 실행 문제

소라고동 화면에서 런타임 설치 안내가 보이면 [Microsoft Edge WebView2 런타임](https://developer.microsoft.com/microsoft-edge/webview2/)을 설치한 뒤 메뉴를 다시 여세요.

배포 ZIP은 코드 서명되지 않아 Windows SmartScreen 경고가 표시될 수 있습니다. 실행할 때 `VCRUNTIME` 또는 `MSVCP` DLL이 없다는 오류가 뜨면 Microsoft의 x64 런타임을 설치하세요. [VC++ v14 x64 다운로드](https://aka.ms/vc14/vc_redist.x64.exe) · [Microsoft 런타임 안내](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist/)

## 개발 빌드

Flutter 3.50, Dart 3.14, Visual Studio C++ Build Tools가 필요합니다.

```powershell
flutter pub get
powershell -NoProfile -File .\tools\prepare-flutter-windows.ps1
flutter build windows --release
```

일반 사용자 권한에서 첫 `flutter pub get`이 플러그인 심볼릭 링크 생성 중 실패하면 위 보조 스크립트로 디렉터리 junction을 준비한 뒤 `flutter pub get`과 빌드를 다시 실행하세요. Windows 보안 저장소 플러그인에는 Visual Studio ATL 없이 빌드하기 위한 로컬 패치가 포함되어 있습니다.

빌드한 EXE는 프로젝트 루트에서 바로 실행할 수 있습니다. 탐색기의 **속성 → 자세히**에서 네 자리 버전을 확인할 수 있습니다. 앞 세 자리는 `VERSION`, 마지막 자리는 CI 빌드 번호 또는 Git 커밋 수입니다.

## 릴리스

배포 단위는 EXE 하나가 아니라 `meme_searcher.exe`, DLL, `data`와 라이선스를 함께 담은 `meme-searcher-v…-windows-x64.zip`입니다. GitHub가 자동으로 제공하는 **Source code (zip)**은 실행용 파일이 아닙니다.

릴리스용 빌드는 깨끗한 최종 커밋에서 다음 스크립트로 만드세요. 이 과정은 의존성 준비, 분석, 전체 테스트, Windows Release 빌드와 빌드 출처 기록을 차례로 확인합니다.

```powershell
$tag = 'vX.Y.Z.N' # VERSION의 세 자리 + 이번 커밋의 네 자리 빌드 번호로 바꾸세요.
powershell -NoProfile -File .\tools\build-windows-release.ps1 -ExpectedTag $tag
powershell -NoProfile -File .\tools\build-android-release.ps1 -ExpectedTag $tag
powershell -NoProfile -File .\tools\package-windows-release.ps1 -ExpectedTag $tag -IncludeAndroid
```

`dist\SHA256SUMS.txt`의 해시, ZIP을 새 폴더에 풀었을 때의 실행, 그리고 ZIP 안의 `RELEASE-BUILD.json`을 확인한 뒤에만 게시합니다. 실제 태그의 네 번째 숫자는 `git rev-list --count HEAD`이며 65534 이하여야 합니다.

GitHub에 게시할 때는 태그와 PE 버전을 확인하고, 초안에 배포 파일과 체크섬을 올린 뒤 공개 및 익명 다운로드 해시 검증까지 마쳐야 합니다. `gh`를 쓸 수 있다면 아래 명령을 실행하세요.

```powershell
$tag = 'v' + (Get-Item .\build\windows\x64\runner\Release\meme_searcher.exe).VersionInfo.FileVersion
git tag -a $tag -m "Meme Snatcher $tag"
git push origin $tag
powershell -NoProfile -File .\tools\package-windows-release.ps1 -ExpectedTag $tag -IncludeAndroid -Publish
```

`gh`가 없는 환경에서는 인증된 GitHub REST 도구로 초안 생성, Windows ZIP·Android APK·MCP ZIP·체크섬 업로드와 해시 대조, 공개, 익명 다운로드 해시 대조를 차례로 수행합니다. 어떤 경로든 기존 태그나 릴리스를 덮어쓰지 않습니다. 전체 절차와 완료 기준은 [Windows 릴리스 규칙](release.md)을 참고하세요.

자체 소스에는 별도 라이선스가 지정되어 있지 않습니다. 포함된 소프트웨어와 밈의 권리자 및 원본 출처는 [서드파티 고지](../THIRD_PARTY_NOTICES.md)에서 확인할 수 있습니다.
