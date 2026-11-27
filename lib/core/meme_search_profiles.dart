/// Curated, source-backed scene metadata used to turn remembered sounds and
/// paraphrases into stable meme-search queries.  This list intentionally has
/// no ranking logic: callers decide how aliases, anchors and cues are scored.
class MemeSearchProfile {
  const MemeSearchProfile({
    required this.id,
    required this.aliases,
    required this.query,
    this.koreanQuery,
    required this.anchors,
    required this.cues,
    this.trend,
  });

  final String id;
  final List<String> aliases;
  final String query;
  final String? koreanQuery;
  final List<String> anchors;
  final List<String> cues;
  final MemeSearchTrend? trend;
}

class MemeSearchTrend {
  const MemeSearchTrend({
    required this.query,
    required this.cues,
    required this.since,
    required this.through,
  });

  final String query;
  final List<String> cues;
  final String since;

  /// Inclusive ISO-8601 date after which the caller must stop boosting it.
  final String through;
}

const List<MemeSearchProfile> memeSearchProfiles = [
  // Tenor: https://tenor.com/view/whoopah-chandler-friends-woop-gif-9170443
  MemeSearchProfile(
    id: 'chandler-whoopah',
    aliases: ['wapa', 'wah-pah', 'whoopah', 'whoopah chandler'],
    query: 'Chandler Bing whoopah whip sound Friends meme',
    koreanQuery: '프렌즈 챈들러 빙 채찍 소리 흉내',
    anchors: ['Chandler Bing', 'Whoopah Chandler', '챈들러 빙', '챈들러 채찍'],
    cues: ['whoopah', 'whip sound imitation', 'mouth sound effect'],
  ),
  // Harry Potter and the Goblet of Fire scene; the common wording is
  // "Dumbledore asked calmly" rather than a literal subtitle search.
  MemeSearchProfile(
    id: 'dumbledore-asked-calmly',
    aliases: ['ask camly', 'asked calmly', 'dumbledore asked calmly'],
    query: 'Dumbledore asked calmly Goblet of Fire meme',
    koreanQuery: '덤블도어 침착하게 물었다 불의 잔 밈',
    anchors: ['Dumbledore', '덤블도어'],
    cues: ['asked calmly', 'angry book adaptation', 'did you put your name'],
  ),
  // https://nvidianews.nvidia.com/news/nvidia-board-reinstates-jensen-huang-as-president-ceo-and-board-director/
  // Creator parody: https://www.youtube.com/watch?v=xmcNIQD4sdw
  MemeSearchProfile(
    id: 'jensen-huang-comeback',
    aliases: ['Jensen Huang', 'Jenson Hwang', '젠슨 황', 'Jen-Hsun Huang'],
    query: 'Jensen Huang meme',
    koreanQuery: '젠슨 황 밈',
    anchors: ['Jensen Huang', 'Jenson Hwang', 'Jen-Hsun Huang', '젠슨 황'],
    cues: ['kitchen keynote', 'gpu oven', 'jensen been cooking', '주방 GPU'],
    trend: MemeSearchTrend(
      query: 'Jensen Huang comeback AI parody',
      cues: ['comeback', 'reinstatement', 'joins the office', '복귀', '출근'],
      since: '2026-11-23',
      through: '2026-12-31',
    ),
  ),
  // NVIDIA creator video: https://www.youtube.com/watch?v=So7TNRhIYJ8
  MemeSearchProfile(
    id: 'jensen-huang-kitchen-gpu',
    aliases: ['Jensen kitchen', 'GPU kitchen', '젠슨 황 주방'],
    query: 'Jensen Huang kitchen GPU meme',
    koreanQuery: '젠슨 황 주방 GPU 밈',
    anchors: ['Jensen Huang', '젠슨 황', 'jensen been cooking'],
    cues: ['kitchen', 'gpu oven', 'jensen been cooking', '주방'],
  ),
  // MBC official: https://www.youtube.com/watch?v=5CsArA3seoE
  MemeSearchProfile(
    id: 'mu-yaho',
    aliases: ['무야호', 'mu yaho', '무야호 외치는 할아버지'],
    query: '무야호 최규재 MBC 무한도전 밈',
    koreanQuery: '무야호 무한도전 최규재',
    anchors: ['무야호', '최규재'],
    cues: ['무야호', '환호', '야호 외침'],
  ),
  // Game Generation source history: https://www.gamegeneration.or.kr/article/67ce1289-5071-43be-b55e-105dbb565b1c
  MemeSearchProfile(
    id: 'deft-never-give-up',
    aliases: ['중꺾마', '중요한 것은 꺾이지 않는 마음', 'deft never give up'],
    query: 'Deft important thing unbreakable heart Worlds meme',
    koreanQuery: '데프트 중꺾마 월즈 밈',
    anchors: ['Deft', '데프트', '중꺾마', '중요한 건 꺾이지 않는 마음'],
    cues: ['unbreakable heart', 'important thing', 'underdog victory'],
  ),
  // Official video: https://www.youtube.com/watch?v=dQw4w9WgXcQ
  MemeSearchProfile(
    id: 'rickroll',
    aliases: [
      'rickroll',
      '릭롤',
      'never gonna give you up',
      'Rick Astley',
      '릭 애슬리',
    ],
    query: 'Rick Astley Never Gonna Give You Up rickroll meme',
    koreanQuery: '릭 애슬리 네버 고나 기브 유 업 릭롤',
    anchors: ['Rick Astley', 'Never Gonna Give You Up'],
    cues: ['rickroll', '1987 music video', 'unexpected link'],
  ),
  // Official video: https://www.youtube.com/watch?v=uxpDa-c-4Mc
  MemeSearchProfile(
    id: 'drake-hotline-bling',
    aliases: ['Drake', '드레이크', 'drake no yes', '드레이크 yes no', 'hotline bling'],
    query: 'Drake Hotline Bling no yes reaction meme',
    koreanQuery: '드레이크 핫라인 블링 싫어 좋아 밈',
    anchors: ['Drake', 'Hotline Bling'],
    cues: ['hotline bling', '핫라인 블링', 'reject gesture', 'two panel reaction'],
  ),
  // Know Your Meme: https://knowyourmeme.com/memes/distracted-boyfriend
  MemeSearchProfile(
    id: 'distracted-boyfriend',
    aliases: ['distracted boyfriend', '바람난 남친', '남친 힐끗'],
    query: 'Distracted Boyfriend stock photo meme',
    koreanQuery: '한눈 파는 남자친구 밈',
    anchors: ['Distracted Boyfriend', 'Antonio Guillem'],
    cues: ['looking back', 'jealous girlfriend', 'three people street'],
  ),
  // Official video: https://www.youtube.com/watch?v=J---aiyznGQ
  MemeSearchProfile(
    id: 'keyboard-cat',
    aliases: ['keyboard cat', '키보드 치는 고양이', 'piano cat'],
    query: 'Keyboard Cat Play Him Off meme',
    koreanQuery: '키보드 치는 고양이 밈',
    anchors: ['Keyboard Cat', 'Play Him Off'],
    cues: ['cat keyboard', 'piano outro', 'play him off'],
  ),
  MemeSearchProfile(
    id: 'bernie-sanders-mittens',
    aliases: [
      'Bernie Sanders',
      '버니 샌더스',
      'Bernie mittens',
      '버니 샌더스 장갑',
      'bernie sitting',
    ],
    query: 'Bernie Sanders inauguration mittens chair meme',
    koreanQuery: '버니 샌더스 취임식 장갑 의자 밈',
    anchors: ['Bernie Sanders', '버니 샌더스'],
    cues: ['mittens', 'folding chair', 'winter coat'],
  ),
  MemeSearchProfile(
    id: 'hide-the-pain-harold',
    aliases: ['hide the pain harold', '해롤드 아저씨', '고통을 숨기는 해롤드'],
    query: 'Hide the Pain Harold smile stock photo meme',
    koreanQuery: '고통을 숨기는 해롤드 밈',
    anchors: ['Hide the Pain Harold', 'András Arató'],
    cues: ['forced smile', 'stock photo', 'hidden pain'],
  ),
  MemeSearchProfile(
    id: 'disaster-girl',
    aliases: ['disaster girl', '재난 소녀', '불난 집 소녀'],
    query: 'Disaster Girl burning house smile meme',
    koreanQuery: '불난 집 앞 미소 소녀 밈',
    anchors: ['Disaster Girl', 'Zoe Roth'],
    cues: ['burning house', 'smirking girl', 'fire background'],
  ),
  MemeSearchProfile(
    id: 'this-is-fine',
    aliases: ['this is fine', '디스 이즈 파인', '불타는 방 강아지'],
    query: 'This Is Fine dog burning room meme',
    koreanQuery: '불타는 방 괜찮아 강아지 밈',
    anchors: ['This Is Fine', 'KC Green', 'On Fire comic'],
    cues: ['dog coffee', 'burning room', 'everything is fine'],
  ),
  MemeSearchProfile(
    id: 'woman-yelling-cat',
    aliases: ['woman yelling at cat', '소리치는 여자 고양이', '흰 고양이 식탁'],
    query: 'Woman Yelling At Cat dinner table meme',
    koreanQuery: '소리치는 여자 흰 고양이 식탁 밈',
    anchors: ['Woman Yelling At Cat', 'Taylor Armstrong', 'Smudge the Cat'],
    cues: ['pointing woman', 'white cat', 'dinner table'],
  ),
  MemeSearchProfile(
    id: 'expanding-brain',
    aliases: ['expanding brain', '점점 커지는 뇌', 'galaxy brain'],
    query: 'Expanding Brain four panel meme',
    koreanQuery: '점점 커지는 뇌 4칸 밈',
    anchors: ['Expanding Brain', 'Galaxy Brain'],
    cues: ['four panels', 'glowing brain', 'increasing enlightenment'],
  ),
  MemeSearchProfile(
    id: 'success-kid',
    aliases: ['success kid', '성공한 아기', '주먹 쥔 아기'],
    query: 'Success Kid fist beach meme',
    koreanQuery: '해변에서 주먹 쥔 아기 밈',
    anchors: ['Success Kid', 'Sammy Griner'],
    cues: ['fist pump', 'beach', 'determined baby'],
  ),
  MemeSearchProfile(
    id: 'surprised-pikachu',
    aliases: ['surprised pikachu', '놀란 피카츄', '피카츄 충격'],
    query: 'Surprised Pikachu shocked face meme',
    koreanQuery: '놀란 피카츄 밈',
    anchors: ['Surprised Pikachu', 'Pokémon'],
    cues: ['open mouth', 'shocked face', 'yellow character'],
  ),
  MemeSearchProfile(
    id: 'two-buttons',
    aliases: ['two buttons', '버튼 두 개', '땀 흘리는 남자'],
    query: 'Two Buttons sweating choice meme',
    koreanQuery: '두 버튼 사이 땀 흘리는 남자 밈',
    anchors: ['Two Buttons', 'Daily Struggle'],
    cues: ['sweating man', 'two red buttons', 'difficult choice'],
  ),
  MemeSearchProfile(
    id: 'change-my-mind',
    aliases: ['change my mind', '내 생각 바꿔봐', '테이블 논쟁'],
    query: 'Change My Mind Steven Crowder table meme',
    koreanQuery: '스티븐 크라우더 내 생각 바꿔봐 밈',
    anchors: ['Change My Mind', 'Steven Crowder'],
    cues: ['folding table', 'challenge sign', 'campus debate'],
  ),
  MemeSearchProfile(
    id: 'spider-man-pointing',
    aliases: ['spiderman pointing', '스파이더맨 서로 가리키기', 'spider man pointing'],
    query: 'Spider-Man pointing at Spider-Man meme',
    koreanQuery: '서로 가리키는 스파이더맨 밈',
    anchors: ['Spider-Man', 'Spider-Man 1967'],
    cues: ['two Spider-Men', 'pointing pose', 'identical accusation'],
  ),
  MemeSearchProfile(
    id: 'jim-halpert-look-camera',
    aliases: ['jim look camera', '짐 카메라 쳐다보기', 'the office stare'],
    query: 'Jim Halpert looks at camera The Office reaction meme',
    koreanQuery: '더 오피스 짐 카메라 쳐다보기 밈',
    anchors: ['Jim Halpert', 'The Office'],
    cues: ['looks at camera', 'deadpan', 'mockumentary reaction'],
  ),
  // The broadcast was CJ Super Fight, with Lim Yo-hwan and Park Jeong-wook.
  // https://www.youtube.com/watch?v=-RwqG5P8hjI
  MemeSearchProfile(
    id: 'starleague-ruined',
    aliases: ['망했어요', '아 망했어요', '스타리그 망했어요', '망했어요 스타', '박정욱 망했어요'],
    query: '박정욱 CJ 슈퍼파이트 마인 망했어요 짤',
    koreanQuery: '박정욱 망했어요',
    anchors: ['스타리그', 'starleague', '슈퍼파이트', '박정욱', '마인 심어놓고'],
    cues: ['마인 심어놓고', '망했어요', 'defeat commentary'],
  ),
  MemeSearchProfile(
    id: 'shrek-smash-mouth',
    aliases: ['somebody once told me', '슈렉 노래', 'all star shrek'],
    query: 'Shrek Smash Mouth All Star meme',
    koreanQuery: '슈렉 올스타 스매시 마우스 밈',
    anchors: ['Shrek', 'Smash Mouth', 'All Star'],
    cues: ['somebody once told me', 'opening song', 'green ogre'],
  ),
  MemeSearchProfile(
    id: 'confused-nick-young',
    aliases: ['confused nick young', '닉 영 물음표', '당황한 농구선수'],
    query: 'Confused Nick Young question marks meme',
    koreanQuery: '물음표 뜬 닉 영 밈',
    anchors: ['Nick Young', 'Confused Nick Young'],
    cues: ['question marks', 'confused basketball player', 'side glance'],
  ),
  MemeSearchProfile(
    id: 'leonardo-dicaprio-toast',
    aliases: ['leonardo toast', '디카프리오 건배', 'great gatsby cheers'],
    query: 'Leonardo DiCaprio Great Gatsby toast meme',
    koreanQuery: '위대한 개츠비 디카프리오 건배 밈',
    anchors: ['Leonardo DiCaprio', 'The Great Gatsby'],
    cues: ['champagne glass', 'toast', 'party suit'],
  ),
];
