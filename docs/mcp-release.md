# Meme Snatcher MCP

Codex와 Claude에서 기본 짤과 내 즐겨찾기로 리액션을 고를 수 있어요. Node.js가 필요합니다. 기본 짤은 이 ZIP에 들어 있고 인터넷 검색이나 API 키 없이 사용할 수 있어요.

## Codex에 연결하기

ZIP을 풀고 그 폴더에서 PowerShell을 열어 다음 명령을 실행하세요.

```powershell
$server = (Resolve-Path -LiteralPath './tools/meme-snatcher-mcp.mjs').Path
codex mcp add --env "APPDATA=$env:APPDATA" meme_snatcher -- node $server
```

새 Codex 세션에서 “친구한테 치킨 먹으러 지금 간다고 신나게 답해줘” 같은 가벼운 메시지를 써보세요. 짤을 더 자연스럽게 쓰게 하고 싶다면 해당 프로젝트의 `AGENTS.md`에 아래 문구를 추가할 수 있어요.

> 가벼운 축하나 장난스러운 리액션에 어울릴 때 `find_reaction_meme`을 한 번 호출하고, 어울리는 후보의 Markdown을 답변에 넣어 줘. 공식 문서와 민감한 대화는 글로만 답해 줘.

## Claude에 연결하기

Meme Snatcher 소스 프로젝트를 Claude Code에서 열면 `.mcp.json`의 `meme_snatcher`를 발견합니다. 처음에는 프로젝트 서버에 대한 승인 안내가 표시될 수 있어요. ZIP으로 설치했다면 MCP 파일의 전체 경로를 지정해, 사용할 프로젝트에서 `claude mcp add --transport stdio --scope local meme_snatcher -- node "C:/path/to/tools/meme-snatcher-mcp.mjs"`를 실행하세요. 연결 상태는 `/mcp`에서 확인할 수 있어요.

Claude Desktop에서는 앱의 로컬 MCP 설정인 `%APPDATA%\Claude\claude_desktop_config.json`의 `mcpServers`에 `meme_snatcher`를 추가하세요. `command`에는 `node.exe`의 전체 경로를, `args` 배열에는 압축을 푼 `tools/meme-snatcher-mcp.mjs`의 전체 경로를 지정하면 돼요. 설정을 저장한 뒤 Claude Desktop을 다시 열면 연결을 확인할 수 있어요.

## 웹 검색과 피드백

Windows 앱이 열려 있으면 `auto`와 `web`으로 앱의 웹 검색 모드를 사용할 수 있어요. Google 이미지 검색은 앱에서 연결한 SerpApi 설정을 사용해요. 평소에는 기본 짤과 로컬에 파일이 남은 즐겨찾기를 찾아요. 그림과 GIF가 답변에 표시되는 방식은 Codex 화면에 따라 달라요.

추천한 짤에 “이게 딱이야”, “다른 장면이야”, “망했어요는 스타리그 마인 장면이야”처럼 명확히 답하면 Codex가 앱에 피드백을 기록할 수 있어요. Codex 설정에 따라 저장 승인 요청이 표시될 수 있어요. 다음에는 앱 검색과 MCP가 같은 규칙을 사용해요. 앱과 연결된 추천의 피드백은 앱을 닫기 전에 기록하세요. 저장된 규칙은 앱을 재실행해도 유지돼요.

연결을 해제하려면 `codex mcp remove meme_snatcher`를 실행하세요. 예시 짤의 출처는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에서 볼 수 있어요.
