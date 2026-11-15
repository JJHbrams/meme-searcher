import 'catalog.dart';
import 'models.dart';

String compactMemeText(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll('!', '')
    .replaceAll('?', '');

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
    this.familyId,
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
  final MediaFilter filter;
  final bool similar;
  final String? familyId;
}

class QueryPlanner {
  const QueryPlanner(this.catalog);

  final MemeCatalog catalog;

  QueryPlan plan(SearchRequest request) {
    final words = <String>[];
    final rawTags = <String>[];
    for (final token in request.fullQuery.split(RegExp(r'\s+'))) {
      if (token.startsWith('#') && token.length > 1) {
        rawTags.add(token.substring(1));
      } else if (token.isNotEmpty) {
        words.add(token);
      }
    }
    final phrase = words.join(' ');
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
    final terms = <String>[if (phrase.isNotEmpty) phrase];
    final context = <String>[];
    final required = <String>[];
    if (family?.id == 'approved') {
      terms.addAll(['knuckles', 'stamp', 'gif', 'meme']);
      context.addAll(['knuckles', 'stamp']);
      required.add('knuckles');
    } else if (family?.id == 'mold-breaker') {
      terms.addAll(['짤', '디시콘', '아로나']);
      context.add('아로나');
    } else if (RegExp(r'[가-힣]').hasMatch(phrase)) {
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
    if (request.filter == MediaFilter.gif &&
        !compactMemeText(phrase).contains('gif')) {
      terms.add('gif');
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
    final providerTerms = _unique(terms).join(' ');
    return QueryPlan(
      original: request.fullQuery,
      words: phrase,
      rawTags: List.unmodifiable(rawTags),
      tagTerms: _unique(tagTerms),
      tagIds: _unique(tagIds),
      expandedAliases: _unique(expanded),
      coreTerms: [...korean, ...english],
      contextTerms: _unique(context),
      requiredContext: _unique(required),
      providerQuery: providerTerms.length > 400
          ? providerTerms.substring(0, 400)
          : providerTerms,
      filter: request.filter,
      similar: request.similar,
      familyId: family?.id,
    );
  }

  static List<String> _unique(Iterable<String> values) =>
      values.where((value) => value.isNotEmpty).fold(<String>[], (all, value) {
        if (!all.contains(value)) all.add(value);
        return all;
      });
}
