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
        final key = canonicalOriginalUrl(candidate.originalUrl ?? '').isNotEmpty
            ? canonicalOriginalUrl(candidate.originalUrl ?? '')
            : 'local:${candidate.id}';
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
    return scored;
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
    var score = core.where((value) => text.contains(value)).length * 18;
    score += tags.where((value) => text.contains(value)).length * 10;
    score += context.where((value) => text.contains(value)).length * 7;
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

  static String canonicalOriginalUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          fragment: '',
        )
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
