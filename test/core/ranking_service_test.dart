import 'package:flutter_test/flutter_test.dart';
import 'package:meme_searcher/core/catalog.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/core/query_plan.dart';
import 'package:meme_searcher/core/ranking_service.dart';

void main() {
  const ranking = RankingService();
  final plan = QueryPlanner(MemeCatalog.bundled)
      .plan(const SearchRequest(query: '좋다 지금 간다 기다려라', tags: ['헬다2']));
  test('keeps local assets without original urls during merge', () {
    const seed = MemeAsset(
      id: 'seed',
      title: '좋다 지금 간다 기다려라',
      origin: 'seed',
      tags: [MemeTag(id: 'helldivers', label: '헬다이버즈')],
    );
    expect(
      ranking
          .mergeAndRank([
            [seed],
          ], plan)
          .single
          .id,
      'seed',
    );
  });
  test('fragment only URLs are deduplicated', () {
    const a = MemeAsset(
      id: 'a',
      title: 'a',
      origin: 'web',
      originalUrl: 'https://x.test/a.gif#first',
    );
    const b = MemeAsset(
      id: 'b',
      title: 'b',
      origin: 'web',
      originalUrl: 'https://x.test/a.gif#second',
    );
    expect(
      ranking.mergeAndRank([
        [a],
        [b],
      ], plan),
      hasLength(1),
    );
  });
  test('commercial result is demoted', () {
    const shop = MemeAsset(
      id: 'shop',
      title: '상품',
      origin: 'web',
      originalUrl: 'https://shopping.naver.com/a',
    );
    const meme = MemeAsset(
      id: 'meme',
      title: '헬다이버즈',
      origin: 'web',
      originalUrl: 'https://example.test/a',
    );
    expect(ranking.rank([shop, meme], plan).first.id, 'meme');
  });
  test('a saved thumbnail does not mask the full original in search', () {
    const original = MemeAsset(
      id: 'online',
      title: 'reaction',
      origin: 'web',
      originalUrl: 'https://example.test/meme.gif',
      previewUrl: 'https://example.test/thumbnail.jpg',
    );
    final thumbnail = original.copyWith(
      id: 'saved',
      origin: 'library',
      isPreviewOnly: true,
      format: 'JPEG',
    );
    final result = ranking.mergeAndRank([
      [thumbnail],
      [original],
    ], plan);
    expect(result.map((item) => item.id), unorderedEquals(['online', 'saved']));
  });
}
