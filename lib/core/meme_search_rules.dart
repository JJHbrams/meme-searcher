import 'meme_search_profiles.dart';
import 'models.dart';

final _separators = RegExp(r"""[\s\-_/.,~…!?():;'"#&+@\[\]{}|%–—’·]+""");
final _memeSuffix = RegExp(r'(?: (?:meme|memes|gif|reaction|짤|밈|움짤|짤방))+$');
final _joinedKoreanSuffix = RegExp(r'(?:움짤|짤방|밈|짤)$');
final _koreanText = RegExp(r'[가-힣]');
final _englishWord = RegExp(r'^[a-z0-9]+$');

String _tokens(String value) =>
    value.toLowerCase().replaceAll(_separators, ' ').trim();

String _key(String value) => _tokens(value).replaceAll(' ', '');

final _profilesByAlias = {
  for (final profile in memeSearchProfiles)
    for (final alias in profile.aliases) _key(alias): profile,
};

class MemeSearchIntent {
  MemeSearchIntent._(this.profile, this.trend, this.subject);

  factory MemeSearchIntent.resolve(String input, DateTime date) {
    final subject = _tokens(input).replaceFirst(_memeSuffix, '');
    final key = subject.replaceAll(' ', '');
    final profile =
        _profilesByAlias[key] ??
        _profilesByAlias[key.replaceFirst(_joinedKoreanSuffix, '')];
    final trend = profile?.trend;
    final today = DateTime(date.year, date.month, date.day);
    return MemeSearchIntent._(
      profile,
      trend != null &&
              !today.isBefore(DateTime.parse(trend.since)) &&
              !today.isAfter(DateTime.parse(trend.through))
          ? trend
          : null,
      subject,
    );
  }

  final MemeSearchProfile? profile;
  final MemeSearchTrend? trend;
  final String subject;

  String? get googleQuery => trend?.query ?? profile?.query;
  String? get naverQuery => profile?.koreanQuery ?? profile?.query;

  bool matchesKnownSubject(String value) => _matchesProfile(_tokens(value));

  bool acceptsNaver(MemeAsset asset) => _matchesProfile(_evidence(asset));

  bool _matchesProfile(String text) {
    final known = profile;
    return known != null &&
        known.anchors.any((anchor) => _contains(text, anchor));
  }

  int candidateScore(MemeAsset asset) {
    if (!asset.isWeb || subject.isEmpty) return 0;
    final text = _evidence(asset);
    final shortVideo = _hostMatches(asset.sourceUrl, _shortVideoHosts);
    final related = profile == null
        ? _matchesInput(text)
        : _matchesProfile(text);
    if (!related) return shortVideo ? -105 : -58;

    final generalCue = _memeCues.any((cue) => _contains(text, cue));
    final scene = profile?.cues.any((cue) => _contains(text, cue)) ?? false;
    final current = trend?.cues.any((cue) => _contains(text, cue)) ?? false;
    final memeSource = _isMemeSource(asset.sourceUrl);
    final coverage =
        _hostMatches(asset.sourceUrl, _newsHosts) ||
        (!memeSource && _reportingCues.any((cue) => _contains(text, cue)));
    if (coverage) return scene || generalCue ? 14 : -30;
    if (current && (generalCue || memeSource || scene)) return 105;
    if (scene) return 75;
    if (generalCue) return 48;
    if (memeSource) return 35;
    if (_portraitCues.any((cue) => _contains(text, cue))) return -45;
    if (shortVideo) return -24;
    return 5;
  }

  bool _matchesInput(String text) {
    if (_contains(text, subject)) return true;
    final words = subject
        .split(' ')
        .where((word) => word.length > 1 && !_stopWords.contains(word))
        .toSet();
    if (words.length < 3) return false;
    return words.where((word) => _contains(text, word)).take(2).length == 2;
  }

  static String _evidence(MemeAsset asset) {
    // The provider's real metadata is evidence. The submitted query and its
    // generated aliases merely describe how the result was found.
    final paths = [
      asset.sourceUrl,
      asset.originalUrl,
    ].map((value) => _pathSegments(value).join(' '));
    return _tokens([asset.title, ...paths].join(' '));
  }

  static bool _contains(String text, String phrase) {
    final term = _tokens(phrase);
    if (term.isEmpty) return false;
    if (_koreanText.hasMatch(term)) {
      return text.replaceAll(' ', '').contains(term.replaceAll(' ', ''));
    }
    final words = term.split(' ');
    if (words.every(_englishWord.hasMatch)) {
      return ' $text '.contains(' $term ');
    }
    return text.contains(term);
  }

  static bool _hostMatches(String? url, Set<String> domains) {
    final host = url == null ? '' : Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return domains.any((domain) => host == domain || host.endsWith('.$domain'));
  }

  static bool _isMemeSource(String? url) {
    if (_hostMatches(url, _memeHosts)) return true;
    if (!_hostMatches(url, const {'reddit.com'})) return false;
    final path = _pathSegments(url);
    return path.length >= 2 &&
        path.first == 'r' &&
        const {
          'memes',
          'memevideos',
          'dankmemes',
          'gamingmemes',
        }.contains(path[1].toLowerCase());
  }

  static List<String> _pathSegments(String? url) {
    if (url == null) return const [];
    try {
      return Uri.tryParse(url)?.pathSegments ?? const [];
    } on FormatException {
      return const [];
    }
  }

  static const _shortVideoHosts = {'tiktok.com', 'instagram.com'};
  static const _memeHosts = {
    'tenor.com',
    'giphy.com',
    'imgflip.com',
    'knowyourmeme.com',
  };
  static const _newsHosts = {
    'news.naver.com',
    'news.daum.net',
    'apnews.com',
    'reuters.com',
    'bbc.com',
    'bbc.co.uk',
    'nvidianews.nvidia.com',
  };
  static const _reportingCues = [
    'meme roundup',
    'memes go viral',
    'meme wave',
    '밈 확산',
    '밈 폭발',
    '밈 쏟아',
    '패러디 게시물',
    '패러디 모음',
    '패러디 총 모음',
  ];
  static const _memeCues = [
    'meme',
    'memes',
    'parody',
    'ai parody',
    'satire',
    'reaction gif',
    'shitpost',
    'edit',
    'reenactment',
    'brainrot',
    '패러디',
    '합성',
    '리액션',
    '밈',
    '움짤',
    '짤방',
    '풍자',
    '드립',
    '디시콘',
  ];
  static const _portraitCues = [
    'headshot',
    'portrait',
    'profile photo',
    'profile picture',
    'biography',
    'press release',
    'interview',
    'keynote',
    'official photo',
    '프로필',
    '인물 사진',
    '보도자료',
    '인터뷰',
    '기자회견',
    '공식 사진',
  ];
  static const _stopWords = {
    'the',
    'and',
    'for',
    'from',
    'with',
    'this',
    'meme',
    'gif',
    '짤',
    '밈',
  };
}

String addDefaultMemeCue(String phrase, {String koreanCue = '짤'}) {
  final words = _tokens(phrase).split(' ');
  if (phrase.isEmpty ||
      words.any(
        const {'meme', 'memes', 'parody', '짤', '밈', '짤방', '움짤', '패러디'}.contains,
      ) ||
      _joinedKoreanSuffix.hasMatch(phrase)) {
    return phrase;
  }
  if (_koreanText.hasMatch(phrase)) return '$phrase $koreanCue';
  return words.any(_englishWord.hasMatch) ? '$phrase meme' : phrase;
}
