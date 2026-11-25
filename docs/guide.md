# Meme Snatcher Windows 사용 가이드

## 설치와 실행

1. Windows 10/11 x64에서 최신 릴리스의 **Assets**를 열고 `windows-x64.zip`으로 끝나는 파일을 받으세요. [최신 릴리스](https://github.com/JJHbrams/meme-searcher/releases/latest)
2. ZIP을 폴더 전체로 압축 해제하세요. DLL과 `data` 폴더가 함께 있는 상태에서 `meme_searcher.exe`를 실행합니다.
3. 첫 실행에서 **나중에**를 누르면 키 없이 기본 제공 짤부터 검색할 수 있습니다.

창의 **X**를 누르면 작업 표시줄의 알림 영역(트레이)에 숨겨집니다. EXE를 다시 실행하거나 트레이의 **Meme Snatcher** 아이콘을 클릭하면 보던 창이 열립니다. 아이콘이 보이지 않으면 시계 옆 **∧**를 펼치세요. 트레이에서 우클릭 후 **종료**를 누르면 앱을 완전히 끝냅니다.

**설정 → 업데이트 확인**을 누르면 실행 중인 버전과 GitHub 최신 정식 릴리스를 비교합니다. 새 버전이 있으면 **Windows ZIP 다운로드**를 누르고, 압축을 새 폴더에 풀어 실행하세요. 기존 앱은 트레이 메뉴의 **종료**로 닫을 수 있습니다.

## Google 이미지 연결

1. **Google 이미지 검색 연결**에서 SerpApi에 가입하거나 로그인하세요. 첫 실행 안내를 넘겼다면 왼쪽 **설정**에서 열 수 있습니다.
2. **API 키 페이지 열기**를 눌러 본인 키를 복사하고, 앱에서 **복사한 키로 연결**을 선택하세요. 직접 입력도 가능합니다.
3. **웹** 또는 **모두**로 검색하면 Google 이미지 결과를 함께 찾습니다.

왼쪽 아래에서 이번 달 남은 검색 횟수와 추가 크레딧을 확인하세요. 웹 검색을 마치면 자동 갱신되며, 새로고침 버튼으로 다른 앱에서 사용한 횟수도 반영할 수 있습니다. 잔여량 조회는 검색 횟수를 차감하지 않습니다. [SerpApi 계정 API](https://serpapi.com/account-api)

앱은 SerpApi 계정 API로 키를 확인하고 Windows 보안 저장소에 저장합니다. `SERPAPI_API_KEY` 환경 변수도 사용할 수 있습니다. 웹 검색 사용량과 요금은 연결한 서비스의 계정 정책을 따릅니다.

## 검색과 저장

- **전체**에서 최근에 사용한 **임시 저장** 짤 두 줄을 먼저 볼 수 있습니다. **펼치기**를 누르면 나머지도 보이고, 아래 **내 짤**에는 복사하거나 직접 보관한 짤이 모입니다. **내 짤** 검색에는 두 곳이 모두 포함됩니다.
- 웹에서 짤을 **복사**, **파일로 복사** 또는 `Ctrl+C`로 복사하면 내 짤에 자동 보관됩니다. 원본을 열 수 없어 **미리보기 이미지 복사**를 선택한 경우에는 그 해상도의 이미지가 보관됩니다.
- 검색이나 미리보기에서 받은 파일은 256 MiB까지 임시 보관하며, 한도를 넘으면 가장 오래 사용하지 않은 파일부터 지웁니다. 이전 버전에서 직접 보관한 짤은 내 짤에 유지되고, 이전에 내려받은 파일은 임시 저장에서 찾아볼 수 있습니다.

- 기본 검색 범위 **모두**는 내 짤과 웹 결과를 한 화면에 표시합니다. **전체 / GIF / 이미지**로 형식을 고르고, 검색어에 `#헬다2` 같은 태그를 붙여 범위를 좁힐 수 있습니다.
- 홈에는 최근 사용한 짤, 최근 검색어, 즐겨찾기가 각각 최대 5개씩 표시됩니다. 검색어를 누르면 다시 검색하고, 짤을 누르면 미리보기가 열립니다.
- 미리보기의 **복사** 또는 `Ctrl+C`로 이미지를 복사합니다. 원본 파일을 첨부하려면 **파일로 복사**를, 파일을 PC에 받으려면 **원본 저장**을 누르세요. GIF는 원본 파일로 복사합니다.
- 웹 원본을 열 수 없고 썸네일만 남아 있으면 **미리보기 이미지 복사**로 표시된 해상도의 이미지를 복사할 수 있습니다.

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

아래 명령은 `dist`에 배포 ZIP과 `SHA256SUMS.txt`를 생성합니다.

```powershell
powershell -NoProfile -File .\tools\package-windows-release.ps1
```

GitHub에 게시하려면 최종 커밋에서 빌드한 뒤 주석 태그에 릴리스 노트를 입력하고 배포하세요.

```powershell
$tag = 'v' + (Get-Item .\meme_searcher.exe).VersionInfo.FileVersion
git tag -a $tag
git push origin $tag
powershell -NoProfile -File .\tools\package-windows-release.ps1 -Publish
```

자체 소스에는 별도 라이선스가 지정되어 있지 않습니다. 포함된 소프트웨어와 밈의 권리자 및 원본 출처는 [서드파티 고지](../THIRD_PARTY_NOTICES.md)에서 확인할 수 있습니다.
