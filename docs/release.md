# Windows 릴리스 규칙

> Windows 릴리스의 완료 기준은 실행 가능한 ZIP이 GitHub Assets에 게시되고 익명 다운로드 해시까지 일치하는 것이다.

## 배포물

`meme-searcher-v<PE 네 자리 버전>-windows-x64.zip`이 실행 배포물이다. ZIP에는 `meme_searcher.exe`, `meme_updater.exe`, Flutter 및 플러그인 DLL, WebView2 로더, `data`, 런타임 라이선스, `README.md`, `THIRD_PARTY_NOTICES.md`, `RELEASE-BUILD.json`이 들어간다. GitHub의 Source code ZIP은 개발용 소스다.

## 필수 순서

1. 깨끗한 최종 커밋에서 `VERSION`을 확정하고 `git rev-list --count HEAD`로 네 번째 버전 숫자를 정한다.
2. `tools/build-windows-release.ps1 -ExpectedTag vX.Y.Z.N`을 실행한다. 이 스크립트는 의존성, 분석, 전체 테스트, Windows Release 빌드와 PE/출처 기록을 검증한다.
3. `tools/package-windows-release.ps1 -ExpectedTag vX.Y.Z.N`을 실행한다. 이 스크립트는 EXE·DLL·data·라이선스·출처가 모두 있는지, ZIP을 다시 읽을 수 있는지와 SHA-256을 확인한다.
4. 새 폴더에 ZIP을 풀어 실행 파일이 기동하는지 확인한다. ZIP과 `SHA256SUMS.txt`에서 해시를 대조한다.
5. 최종 커밋에만 주석 태그를 만들고 푸시한다. 기존 태그와 릴리스를 덮어쓰지 않는다.
6. 초안 릴리스에 ZIP과 `SHA256SUMS.txt`를 올리고 업로드한 asset의 크기·digest를 대조한 뒤 공개한다.
7. 로그인하지 않은 상태로 asset을 내려받아 SHA-256을 다시 대조한다.

`gh`가 있으면 패키지 스크립트의 `-Publish`가 5~7단계를 실행한다. 없으면 인증된 GitHub REST 도구로 같은 순서를 수행한다. API 키, 사용자 데이터, 개인 경로, PDB 파일은 소스와 ZIP에 넣지 않는다.

## 실패 처리

PE 버전·태그·출처 커밋·해시가 하나라도 다르면 게시하지 않는다. 누락 런타임 파일이나 ZIP 재열기 실패도 중단 사유다. 이미 공개된 릴리스가 있으면 새 버전을 만들어야 하며 덮어쓰지 않는다.
