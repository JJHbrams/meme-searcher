import 'catalog.dart';
import 'meme_search_rules.dart';
import 'models.dart';

String compactMemeText(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll('!', '')
    .replaceAll('?', '')
    .replaceFirst(RegExp(r'[~…．.！？，。〜～]+$'), '');

class QueryPlan {
  const QueryPlan({
    required this.original,
    required this.words,
    required this.rawTags,
    required this.tagTerms,
    required this.tagIds,
    required this.expandedAliases,
    required this.coreTerms,
    required this.contextTerms,
    required this.requiredContext,
    required this.providerQuery,
    required this.filter,
    required this.similar,
    this.learnedSceneTerms = const [],
    this.familyId,
    this.alternateNaverQuery,
    this.memeIntent,
  });

  final String original;
  final String words;
  final List<String> rawTags;
  final List<String> tagTerms;
  final List<String> tagIds;
  final List<String> expandedAliases;
  final List<String> coreTerms;
  final List<String> contextTerms;
  final List<String> requiredContext;
  final String providerQuery;
  final String? alternateNaverQuery;
  final MediaFilter filter;
  final bool similar;
  final List<String> learnedSceneTerms;
  final String? familyId;
  final MemeSearchIntent? memeIntent;

  String get naverQuery => alternateNaverQuery ?? providerQuery;
  bool get isKorean => RegExp(r'[가-힣]').hasMatch(words);

  bool matchesLearnedScene(String text) {
    final required = learnedSceneTerms.length == 1 ? 1 : 2;
    return learnedSceneTerms.where(text.contains).take(required).length ==
        required;
  }
}

class QueryPlanner {
  const QueryPlanner(this.catalog);

  final MemeCatalog catalog;

  QueryPlan plan(
    SearchRequest request, {
    String? learnedScene,
    String? lookupQuery,
    DateTime? now,
  }) {
    final words = <String>[];
    final rawTags = <String>[];
    for (final token in request.fullQuery.split(RegExp(r'\s+'))) {
      if (token.startsWith('#') && token.length > 1) {
        rawTags.add(token.substring(1));
      } else if (token.isNotEmpty) {
        words.add(token);
      }
    }
    final phrase = learnedScene ?? lookupQuery ?? words.join(' ');
    final normalized = compactMemeText(phrase);
    final tagTerms = <String>[];
    final tagIds = <String>[];
    for (final raw in rawTags) {
      CatalogTag? match;
      for (final tag in catalog.tags.values) {
        if (tag.aliases.map(compactMemeText).contains(compactMemeText(raw))) {
          match = tag;
          break;
        }
      }
      if (match == null) {
        tagTerms.add(raw);
      } else {
        tagIds.add(match.id);
        tagTerms.add(match.label);
      }
    }
    MemeFamily? family;
    for (final candidate in catalog.families) {
      final aliases = [
        ...candidate.aliases,
        if (request.similar) ...candidate.similarAliases,
      ];
      if (normalized.isNotEmpty &&
          aliases.any((value) => compactMemeText(value) == normalized)) {
        family = candidate;
        break;
      }
    }
    final expanded = <String>[
      ...?family?.aliases,
      if (request.similar) ...?family?.similarAliases,
    ];
    final memeIntent =
        phrase.isNotEmpty && family == null && learnedScene == null
        ? MemeSearchIntent.resolve(phrase, now ?? DateTime.now())
        : null;
    final terms = <String>[
      if (phrase.isNotEmpty)
        memeIntent?.googleQuery ??
            (memeIntent != null
                ? addDefaultMemeCue(phrase, koreanCue: '밈')
                : phrase),
    ];
    final context = <String>[];
    final required = <String>[];
    if (family?.id == 'approved') {
      terms.addAll(['knuckles', 'stamp', 'gif', 'meme']);
      context.addAll(['knuckles', 'stamp']);
      required.add('knuckles');
    } else if (family?.id == 'mold-breaker') {
      terms.addAll(['짤', '디시콘', '아로나']);
      context.add('아로나');
    } else if (memeIntent == null && RegExp(r'[가-힣]').hasMatch(phrase)) {
      terms.add('짤');
    }
    terms.addAll(tagTerms);
    if (tagIds.contains('arona')) {
      terms.add('블루 아카이브');
      context.add('아로나');
    }
    if (tagIds.contains('helldivers')) {
      context.addAll(['헬다이버즈', 'helldivers']);
    }
    const generic = {
      'gif',
      'meme',
      'reaction',
      'image',
      'images',
      'the',
      'a',
      'an',
      '짤',
      '디시콘',
    };
    final english = RegExp(r'[a-z0-9]{3,}')
        .allMatches(phrase.toLowerCase())
        .map((match) => match.group(0)!)
        .where((term) => !generic.contains(term));
    final korean = RegExp(r'[가-힣]').hasMatch(phrase)
        ? [compactMemeText(phrase)]
        : const <String>[];
    final learnedTerms = learnedScene == null
        ? const <String>[]
        : _unique(
            RegExp(r'[a-z0-9가-힣]{2,}')
                .allMatches(learnedScene.toLowerCase())
                .map((match) => match.group(0)!)
                .where((term) => !generic.contains(term)),
          );
    final naverBase =
        memeIntent?.naverQuery ??
        (memeIntent == null ? null : addDefaultMemeCue(phrase));
    final providerQuery = _providerQuery(terms, request.filter);
    final naverQuery = naverBase == null
        ? null
        : _providerQuery([naverBase, ...terms.skip(1)], request.filter);
    return QueryPlan(
      original: request.fullQuery,
      words: phrase,
      rawTags: List.unmodifiable(rawTags),
      tagTerms: _unique(tagTerms),
      tagIds: _unique(tagIds),
      expandedAliases: _unique(expanded),
      coreTerms: learnedTerms.isEmpty ? [...korean, ...english] : learnedTerms,
      contextTerms: _unique(context),
      requiredContext: _unique(required),
      providerQuery: providerQuery,
      alternateNaverQuery: naverQuery,
      filter: request.filter,
      similar: request.similar,
      learnedSceneTerms: learnedTerms,
      familyId: family?.id,
      memeIntent: memeIntent,
    );
  }

  static String _providerQuery(List<String> terms, MediaFilter filter) {
    var query = _unique(terms).join(' ');
    if (filter == MediaFilter.gif && !compactMemeText(query).contains('gif')) {
      query = query.isEmpty ? 'gif' : '$query gif';
    }
    return query.length > 400 ? query.substring(0, 400) : query;
  }

  static List<String> _unique(Iterable<String> values) =>
      values.where((value) => value.isNotEmpty).fold(<String>[], (all, value) {
        if (!all.contains(value)) all.add(value);
        return all;
      });
}
