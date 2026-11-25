# Windows release rule

Windows 릴리스 작업은 소스 태그만 게시해 완료로 처리하면 안 된다. `tools/build-windows-release.ps1`로 최종 커밋을 검사·빌드하고, `tools/package-windows-release.ps1`가 만든 `meme-searcher-v…-windows-x64.zip`과 `SHA256SUMS.txt`를 같은 태그의 GitHub Release Assets에 올린다.

ZIP에는 `meme_searcher.exe`, 필요한 DLL, `data`, 라이선스와 `RELEASE-BUILD.json`이 함께 있어야 한다. 기존 릴리스·태그를 수정하거나 덮어쓰지 않는다. 공개 전에는 출처·PE 버전·체크섬을 확인하고, 공개 후에는 로그인하지 않은 다운로드의 SHA-256을 대조한다. GitHub 자동 Source code ZIP은 실행 배포본이 아니다.
