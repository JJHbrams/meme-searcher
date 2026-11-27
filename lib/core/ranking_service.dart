// ignore_for_file: curly_braces_in_flow_control_structures, prefer_collection_literals

import 'models.dart';
import 'query_plan.dart';

class RankingService {
  const RankingService();

  static const maxProbes = 12;

  List<MemeAsset> mergeAndRank(List<List<MemeAsset>> groups, QueryPlan plan) {
    final merged = <String, MemeAsset>{};
    for (final group in groups) {
      for (final candidate in group) {
        final url = candidate.isPreviewOnly
            ? candidate.previewUrl
            : candidate.originalUrl;
        final address = canonicalOriginalUrl(url ?? '');
        final key = address.isEmpty ? 'local:${candidate.id}' : address;
        final existing = merged[key];
        if (existing == null) {
          merged[key] = candidate;
          continue;
        }
        final ranks = {...existing.providerRanks};
        candidate.providerRanks.forEach((engine, rank) {
          ranks[engine] = ranks.containsKey(engine)
              ? (ranks[engine]! < rank ? ranks[engine]! : rank)
              : rank;
        });
        final engines = [
          ...existing.engines,
          ...candidate.engines,
        ].toSet().toList();
        final winner = cheapScore(candidate, plan) > cheapScore(existing, plan)
            ? candidate
            : existing;
        merged[key] = winner.copyWith(engines: engines, providerRanks: ranks);
      }
    }
    return rank(merged.values.toList(), plan);
  }

  List<MemeAsset> rank(List<MemeAsset> candidates, QueryPlan plan) {
    final scored = candidates
        .map((asset) => asset.copyWith(rankingScore: cheapScore(asset, plan)))
        .toList(growable: false);
    scored.sort(_stableCompare);
    if (plan.googleRecentDays == null ||
        scored.length < 4 ||
        !scored
            .take(3)
            .every((asset) => _fromGoogle(asset) && !_fromNaver(asset))) {
      return scored;
    }

    final evergreenIndex = scored.indexWhere(
      (asset) =>
          asset.isWeb &&
          _fromNaver(asset) &&
          !_commercial(asset) &&
          (plan.memeIntent?.candidateScore(asset) ?? 0) >= 35,
      3,
    );
    if (evergreenIndex < 0) return scored;

    // Keep an all-time candidate visible when the recent Google results
    // would otherwise fill the first row. User feedback still applies later.
    final hasDatedMeme = scored
        .take(3)
        .any(
          (asset) =>
              (plan.memeIntent?.candidateScore(asset) ?? 0) >= 35 &&
              _hasRecentSourceDate(asset.sourceUrl, plan),
        );
    final balanced = scored.toList();
    final evergreen = balanced.removeAt(evergreenIndex);
    balanced.insert(hasDatedMeme ? 2 : 0, evergreen);
    return balanced;
  }

  List<MemeAsset> probeTargets(List<MemeAsset> candidates) {
    final groups = <String, List<MemeAsset>>{};
    for (final candidate in candidates) {
      final key = candidate.primaryEngine.isEmpty
          ? 'unknown'
          : candidate.primaryEngine;
      (groups[key] ??= []).add(candidate);
    }
    for (final group in groups.values) {
      group.sort(_stableCompare);
    }
    final result = <MemeAsset>[];
    final engines = groups.keys.toList()..sort();
    while (result.length < maxProbes &&
        groups.values.any((group) => group.isNotEmpty)) {
      for (final engine in engines) {
        final group = groups[engine]!;
        if (group.isNotEmpty && result.length < maxProbes)
          result.add(group.removeAt(0));
      }
    }
    return result;
  }

  num cheapScore(MemeAsset asset, QueryPlan plan) {
    final text = _compact(
      '${asset.title} ${asset.sourceUrl ?? ''} ${asset.originalUrl ?? ''}',
    );
    final core = plan.coreTerms
        .map(_compact)
        .where((value) => value.isNotEmpty);
    final tags = plan.tagTerms.map(_compact).where((value) => value.isNotEmpty);
    final context = plan.contextTerms
        .map(_compact)
        .where((value) => value.isNotEmpty);
    final knownWebSubject = asset.isWeb && plan.memeIntent?.profile != null;
    var score = knownWebSubject
        ? 0
        : core.where((value) => text.contains(value)).length * 18;
    score += tags.where((value) => text.contains(value)).length * 10;
    score += context.where((value) => text.contains(value)).length * 7;
    final memeEvidence = plan.memeIntent?.candidateScore(asset) ?? 0;
    score += memeEvidence;
    if (_fromGoogle(asset) &&
        memeEvidence >= 35 &&
        _hasRecentSourceDate(asset.sourceUrl, plan)) {
      score += 25;
    }
    if ((asset.formatHint ?? '').toUpperCase() == 'GIF' ||
        (asset.originalUrl ?? '')
            .toLowerCase()
            .split('?')
            .first
            .endsWith('.gif'))
      score += 5;
    if (_commercial(asset)) score -= 250;
    if (asset.visualScore != null)
      score += 220 + (asset.visualScore! * 100).round();
    if (plan.filter == MediaFilter.gif) {
      if (asset.motionVerified)
        score += 110;
      else if (asset.inspectionStatus == 'static')
        score -= 75;
      else if (asset.inspectionStatus == 'unavailable')
        score -= 35;
    }
    return score;
  }

  static bool _fromGoogle(MemeAsset asset) =>
      asset.isWeb && asset.providerRanks.containsKey('google');

  static bool _fromNaver(MemeAsset asset) =>
      asset.isWeb && asset.providerRanks.containsKey('naver');

  static bool _hasRecentSourceDate(String? url, QueryPlan plan) {
    final days = plan.googleRecentDays;
    final searchedAt = plan.searchedAt;
    if (days == null || searchedAt == null) return false;
    final uri = Uri.tryParse(url ?? '');
    if (uri == null || !uri.hasAuthority) return false;
    final date = _publicationDate(uri);
    return date != null &&
        !date.isBefore(searchedAt.subtract(Duration(days: days))) &&
        !date.isAfter(searchedAt);
  }

  static DateTime? _publicationDate(Uri uri) {
    if (const {
      'x.com',
      'www.x.com',
      'twitter.com',
      'www.twitter.com',
    }.contains(uri.host)) {
      final token = _postId.firstMatch(uri.path)?.group(1);
      final id = token == null ? null : BigInt.tryParse(token);
      if (id != null) {
        // X post identifiers reserve the upper bits for milliseconds.
        return DateTime.fromMillisecondsSinceEpoch(
          (id >> 22).toInt() + 1288834974657,
          isUtc: true,
        );
      }
    }

    final match = _datedPath.firstMatch(uri.path);
    if (match == null) return null;
    final day = '${match[1]}-${match[3]}-${match[4]}';
    final parsed = DateTime.tryParse("${day}T00:00:00Z");
    return parsed != null && parsed.toIso8601String().startsWith(day)
        ? parsed
        : null;
  }

  static final _postId = RegExp(r'/status/(\d{16,19})(?:/|$)');
  static final _datedPath = RegExp(
    r'/((?:19|20)\d{2})([-/])(\d{2})\2(\d{2})(?:/|-|$)',
  );

  static String canonicalOriginalUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
    return uri
        .replace(scheme: uri.scheme.toLowerCase(), host: uri.host.toLowerCase())
        .removeFragment()
        .toString();
  }

  static int _stableCompare(MemeAsset left, MemeAsset right) {
    final score = right.rankingScore.compareTo(left.rankingScore);
    if (score != 0) return score;
    final rank = left.originalProviderRank.compareTo(
      right.originalProviderRank,
    );
    if (rank != 0) return rank;
    final engine = left.primaryEngine.compareTo(right.primaryEngine);
    if (engine != 0) return engine;
    return (left.originalUrl ?? '').compareTo(right.originalUrl ?? '');
  }

  static String _compact(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static bool _commercial(MemeAsset asset) {
    const hosts = [
      'shopping.naver.com',
      'smartstore.naver.com',
      'amazon.com',
      'ebay.com',
      'etsy.com',
      'aliexpress.com',
      'taobao.com',
      'bookshop.org',
      'yes24.com',
      'aladin.co.kr',
      'kyobobook.co.kr',
      'redbubble.com',
      'gettyimages.com',
      'scholastic.com',
      'scholasticstore.com',
    ];
    const terms = ['상품', '도서', '서적', '가격', '쇼핑', '굿즈'];
    final urls = [asset.sourceUrl, asset.originalUrl].whereType<String>();
    for (final url in urls) {
      final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
      if (hosts.any((domain) => host == domain || host.endsWith('.$domain')))
        return true;
    }
    final text =
        '${asset.title} ${asset.sourceUrl ?? ''} ${asset.originalUrl ?? ''}'
            .toLowerCase();
    return terms.any(text.contains) ||
        RegExp(
          r'\b(products?|merch(?:andise)?|kindle|isbn|hardcover|paperback|books?|bookstore)\b',
        ).hasMatch(text);
  }
}
