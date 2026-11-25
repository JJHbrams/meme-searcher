# Meme Searcher for Windows

밈 키워드로 이미지와 GIF를 찾고, 결과를 Windows 클립보드에 복사하는 데스크톱 앱입니다.

## 설치와 실행

Windows 10/11 x64에서 [최신 릴리스](https://github.com/JJHbrams/meme-searcher/releases/latest)의 `windows-x64.zip`으로 끝나는 파일을 내려받으세요. **압축을 폴더 전체로 푼 뒤** 그 안의 `meme_searcher.exe`를 실행하세요. DLL과 `data` 폴더도 실행 파일 옆에 있어야 합니다.

배포본은 코드 서명되지 않은 portable ZIP입니다. Windows SmartScreen 경고가 표시될 수 있습니다.

Windows에 `VCRUNTIME` 또는 `MSVCP` DLL이 없다는 오류가 나면 [Microsoft Visual C++ v14 x64 Redistributable](https://aka.ms/vc14/vc_redist.x64.exe)를 설치하세요. 지원되는 최신 런타임 안내는 [Microsoft 문서](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist/)에서 확인할 수 있습니다. 별도 설치 프로그램은 배포 ZIP에 포함하지 않습니다.

## 사용 방법

1. 첫 실행의 **Google 이미지 검색 연결**에서 SerpApi에 가입하거나 로그인합니다. **API 키 페이지 열기**에서 본인 키를 복사한 뒤 앱으로 돌아와 **복사한 키로 연결**을 누르세요. 앱이 검색 횟수를 쓰지 않는 계정 API로 키를 확인한 뒤 Windows 보안 저장소에 저장합니다. 직접 입력도 가능합니다. **나중에**를 선택하면 바로 내 짤을 이용할 수 있고 설정에서 언제든 연결할 수 있습니다. 이미 저장된 키나 `SERPAPI_API_KEY` 환경 변수가 있으면 첫 실행 안내를 건너뜁니다.
2. 홈에서 키워드와 필요하면 `#헬다2`처럼 태그를 입력하고 검색합니다. 기본 범위인 **모두**는 내 짤과 웹을 함께 검색합니다. 홈의 **최근 사용**, **최근 검색**, **즐겨찾기**에는 각각 최대 5개가 표시됩니다. 최근 검색어를 누르면 다시 검색하고, 짤을 누르면 미리보기가 열립니다. 미리보기의 별 버튼으로 즐겨찾기를 관리하세요.
3. 결과의 미리보기에서 **복사** 또는 **Ctrl+C**를 누른 뒤, 메신저 입력란에서 **Ctrl+V**로 붙여넣습니다. 일반 이미지는 PNG와 Windows 비트맵으로 전달합니다. 파일 첨부가 필요하면 **파일로 복사**를 선택하세요. GIF는 기본 복사만으로 탐색기에서 복사한 원본 파일처럼 전달되어 애니메이션이 유지됩니다.

검색 API 사용량·요금·원본 사이트의 접근 가능 여부는 각 서비스와 결과 사이트의 정책·상태에 따릅니다. 원본 URL이 차단되거나 내려가면 해당 결과는 열거나 복사하지 못할 수 있습니다.

웹 결과는 검색 엔진이 제공한 이미지 형식을 표시합니다. 형식 정보가 없는 결과는 화면에 나타날 때 원본의 첫 바이트를 확인합니다. 짤을 열면 실제 파일에서 확인한 형식과 크기가 표시됩니다. **복사**와 **Ctrl+C**는 같은 동작입니다. 원본을 열 수 있고 지원하는 형식이면 원본을 사용합니다. 원본을 열 수 없어 별도의 썸네일을 표시하는 경우에는 **미리보기 이미지 복사**로 그 해상도의 이미지를 복사할 수 있습니다.

## 개발 빌드

필요한 도구는 Flutter 3.50, Dart 3.14, Visual Studio C++ Build Tools입니다.

```powershell
flutter pub get
powershell -NoProfile -File .\tools\prepare-flutter-windows.ps1
flutter build windows --release
```

일반 사용자 권한에서 첫 `flutter pub get`이 플러그인 symlink 생성 때문에 실패할 수 있지만, 필요한 manifest는 먼저 작성됩니다. 그 경우 보조 스크립트를 실행해 디렉터리 junction을 준비한 뒤 `flutter pub get`을 한 번 더 실행하고 빌드하세요. Developer Mode나 시스템 전체 보안 설정을 변경하지 않습니다. `flutter_secure_storage_windows`는 Visual Studio ATL 선택 구성 요소 없이 빌드되도록 로컬에 vendoring한 패치를 사용하며, 동작과 라이선스 정보는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에 기록했습니다.

Python 서버는 필요하지 않습니다. 앱은 Flutter 네이티브 코드로 실행됩니다.

Windows 탐색기의 **속성 → 자세히**에서 파일 버전과 제품 버전을 확인할 수 있습니다. 네 자리 중 앞 세 자리는 저장소 루트의 `VERSION`, 마지막 자리는 CI 빌드 번호 또는 로컬 Git 커밋 수입니다.

릴리스 빌드가 끝나면 프로젝트 루트의 `meme_searcher.exe`를 바로 실행할 수 있습니다. `powershell -NoProfile -File .\tools\package-windows-release.ps1`을 실행하면 `dist`에 배포 ZIP과 `SHA256SUMS.txt`가 생깁니다.

GitHub에 배포하려면 최종 커밋에서 빌드한 뒤 아래 명령을 실행하세요. 주석 태그에 입력한 변경 사항이 릴리스 노트가 됩니다.

```powershell
$tag = 'v' + (Get-Item .\meme_searcher.exe).VersionInfo.FileVersion
git tag -a $tag
git push origin $tag
powershell -NoProfile -File .\tools\package-windows-release.ps1 -Publish
```

## 라이선스와 콘텐츠

이 저장소의 자체 소스에는 별도 라이선스가 지정되어 있지 않습니다. 포함된 서드파티 소프트웨어와 시드 밈 미디어의 권리는 각각의 권리자에게 있으며, 상세 고지와 원본 링크는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 참고하세요.
