# Windows release rule

Windows 릴리스 작업은 소스 태그만 게시해 완료로 처리하면 안 된다. `tools/build-windows-release.ps1`로 최종 커밋을 검사·빌드하고, `tools/package-windows-release.ps1`가 만든 `meme-searcher-v…-windows-x64.zip`과 `SHA256SUMS.txt`를 같은 태그의 GitHub Release Assets에 올린다.

ZIP에는 `meme_searcher.exe`, 필요한 DLL, `data`, 라이선스와 `RELEASE-BUILD.json`이 함께 있어야 한다. 기존 릴리스·태그를 수정하거나 덮어쓰지 않는다. 공개 전에는 출처·PE 버전·체크섬을 확인하고, 공개 후에는 로그인하지 않은 다운로드의 SHA-256을 대조한다. GitHub 자동 Source code ZIP은 실행 배포본이 아니다.

Windows Release 빌드 후에는 저장소 루트에 `meme_searcher.exe`와 실행에 필요한 DLL·`data`를 함께 둔다. 격리된 빌드 worktree를 사용했다면 검증한 런타임 파일을 사용자가 사용하는 기본 저장소·작업 공간 루트에도 복사하고 해시를 대조한다. 이 산출물은 Git의 추적 대상에 추가하지 않는다.

정식 릴리스에는 같은 커밋과 태그로 빌드한 서명 Android APK도 함께 넣는다. `tools/build-android-release.ps1`로 서명과 APK 버전을 확인한다. Codex용 MCP는 같은 릴리스에 `meme-searcher-v…-mcp.zip`이라는 독립 에셋으로 올린다. `tools/package-windows-release.ps1 -IncludeAndroid`로 세 배포 파일의 체크섬을 생성한다. Android 릴리스 서명 키와 속성 파일은 저장소 밖에 보관한다.

## Codex 밈 리액션

`meme_snatcher` MCP가 연결되어 있으면, 사용자가 짤을 요청하거나 가벼운 대화에서 장난스러운 축하·맞장구·드립이 자연스러울 때 `find_reaction_meme`을 한 번 호출한다. 예를 들어 사용자가 친한 말투로 승인 소식을 자랑하는 데 답할 때는 짤이나 리액션을 직접 요청하지 않아도 호출할 수 있다. 원하는 반응을 `approval`, `지금 간다`, `틀깨기`처럼 짧은 검색어로 보내고, 적합한 후보가 있으면 결과의 `markdown`으로 짤 한 장을 답변에 표시한다. 결과가 비거나 맞는 짤이 없으면 문장으로만 답한다.

고객 안내, 업무상 공식 문서, 민감한 주제, 기술 작업과 일반 설명에서는 호출을 건너뛴다. 대화에 가벼운 표현이 섞여 있어도 문서의 목적과 독자를 기준으로 판단한다.

평소 리액션은 `scope: local`을 사용한다. 찾을 만한 특정 짤이나 장면이 있고 서랍 밖까지 볼 필요가 있으면 `scope: auto`를 사용한다. 사용자가 웹에서 찾아 달라고 하면 `scope: web`을 사용한다. 웹 후보는 앱의 웹 검색에서 받은 결과로 고른다.

사용자가 실제로 보여 준 짤을 평가하거나 원하는 장면을 교정하면 추천 결과의 `recommendation_id`로 `record_meme_feedback`을 호출한다. 사용자가 직접 준 내용만 저장하고, 장면 교정은 앱에서 검색할 수 있는 짧은 표현을 보낸다. 저장 성공은 도구 결과로 확인한다.
