import 'package:flutter_test/flutter_test.dart';
import 'package:meme_searcher/core/catalog.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/core/query_plan.dart';
import 'package:meme_searcher/core/ranking_service.dart';

void main() {
  const planner = QueryPlanner(MemeCatalog.bundled);
  const ranking = RankingService();
  final activeDate = DateTime(2026, 11, 27);

  group('meme search rules', () {
    test('Jensen aliases share the active trend and Korean Naver query', () {
      for (final alias in ['젠슨 황', 'Jensen Huang', 'Jenson Hwang']) {
        final plan = planner.plan(SearchRequest(query: alias), now: activeDate);

        expect(plan.memeIntent?.profile?.id, 'jensen-huang-comeback');
        expect(
          plan.memeIntent?.trend?.query,
          'Jensen Huang comeback AI parody',
        );
        expect(plan.providerQuery, contains('comeback AI parody'));
        expect(plan.naverQuery, startsWith('젠슨 황 밈'));
      }
    });

    test('expired Jensen trend returns to the evergreen provider query', () {
      final plan = planner.plan(
        const SearchRequest(query: '젠슨 황'),
        now: DateTime(2027, 1, 1),
      );

      expect(plan.memeIntent?.profile?.id, 'jensen-huang-comeback');
      expect(plan.memeIntent?.trend, isNull);
      expect(plan.providerQuery, 'Jensen Huang meme');
      expect(plan.naverQuery, '젠슨 황 밈');
    });

    test(
      'keeps existing family controls and unregistered English meme cue',
      () {
        final approved = planner.plan(
          const SearchRequest(query: 'approved', filter: MediaFilter.gif),
          now: activeDate,
        );
        final deft = planner.plan(
          const SearchRequest(query: 'deft never give up'),
          now: activeDate,
        );
        final unknownEnglish = planner.plan(
          const SearchRequest(query: 'unregistered astronaut'),
          now: activeDate,
        );
        final unknownKorean = planner.plan(
          const SearchRequest(query: '처음 보는 우주인'),
          now: activeDate,
        );

        expect(approved.familyId, 'approved');
        expect(
          approved.providerQuery,
          allOf(contains('knuckles'), contains('gif')),
        );
        expect(deft.memeIntent?.profile?.id, 'deft-never-give-up');
        expect(unknownEnglish.providerQuery, 'unregistered astronaut meme');
        expect(unknownKorean.providerQuery, '처음 보는 우주인 밈');
        expect(unknownKorean.naverQuery, '처음 보는 우주인 짤');
      },
    );

    test(
      'scene aliases normalize punctuation and preserve format and tags',
      () {
        final whoopah = planner.plan(
          const SearchRequest(
            query: 'wapa~',
            filter: MediaFilter.gif,
            tags: ['헬다2'],
          ),
          now: activeDate,
        );
        final moldBreaker = planner.plan(
          const SearchRequest(query: '틀깨기…'),
          now: activeDate,
        );
        final feedbackOverride = planner.plan(
          const SearchRequest(
            query: 'wapa',
            filter: MediaFilter.gif,
            tags: ['헬다2'],
          ),
          learnedScene: 'Friends Chandler Bing whip sound imitation',
          now: activeDate,
        );

        expect(whoopah.memeIntent?.profile?.id, 'chandler-whoopah');
        expect(
          whoopah.providerQuery,
          allOf(contains('Chandler Bing'), contains('gif')),
        );
        expect(whoopah.tagIds, contains('helldivers'));
        expect(whoopah.contextTerms, containsAll(['헬다이버즈', 'helldivers']));
        expect(moldBreaker.familyId, 'mold-breaker');
        expect(feedbackOverride.memeIntent, isNull);
        expect(
          feedbackOverride.learnedSceneTerms,
          containsAll(['friends', 'chandler']),
        );
        expect(
          feedbackOverride.providerQuery,
          allOf(contains('whip sound imitation'), contains('gif')),
        );
        expect(feedbackOverride.tagIds, contains('helldivers'));
      },
    );

    test('ranks known parody and classic evidence above portrait and generic TikTok', () {
      final currentPlan = planner.plan(
        const SearchRequest(query: 'Jenson Hwang'),
        now: activeDate,
      );
      final oldPlan = _preDictionaryPlan(currentPlan);
      const portrait = MemeAsset(
        id: 'portrait',
        title: 'Jensen Huang official portrait',
        origin: 'web',
        sourceUrl: 'https://nvidianews.nvidia.com/photos/jensen-huang.jpg',
        originalUrl: 'https://images.nvidia.com/jensen.jpg',
        engines: ['google'],
        providerRanks: {'google': 1},
        originalProviderRank: 1,
      );
      const currentParody = MemeAsset(
        id: 'current-parody',
        title: 'Jensen Huang comeback joins The Office AI parody',
        origin: 'web',
        sourceUrl: 'https://www.youtube.com/watch?v=xmcNIQD4sdw',
        originalUrl: 'https://i.ytimg.com/vi/xmcNIQD4sdw/hqdefault.jpg',
        engines: ['google'],
        providerRanks: {'google': 4},
        originalProviderRank: 4,
      );
      const classicMeme = MemeAsset(
        id: 'classic-meme',
        title: 'Jensen Huang kitchen GPU oven meme',
        origin: 'web',
        sourceUrl: 'https://imgflip.com/memegenerator/jensen-kitchen',
        originalUrl: 'https://i.imgflip.com/jensen-kitchen.jpg',
        engines: ['google'],
        providerRanks: {'google': 3},
        originalProviderRank: 3,
      );
      const genericTikTok = MemeAsset(
        id: 'generic-tiktok',
        title: 'AI trend clip',
        origin: 'web',
        sourceUrl: 'https://www.tiktok.com/@random/video/123',
        originalUrl: 'https://cdn.tiktok.com/cover.jpg',
        engines: ['google'],
        providerRanks: {'google': 2},
        originalProviderRank: 2,
      );
      const relevantReddit = MemeAsset(
        id: 'reddit-variant',
        title: 'Jensen Huang kitchen GPU oven meme template',
        origin: 'web',
        sourceUrl: 'https://www.reddit.com/r/nvidia/comments/jensen_kitchen/',
        originalUrl: 'https://preview.redd.it/jensen-kitchen.jpg',
        engines: ['google'],
        providerRanks: {'google': 5},
        originalProviderRank: 5,
      );
      final candidates = [
        portrait,
        currentParody,
        classicMeme,
        genericTikTok,
        relevantReddit,
      ];

      final oldOrder = ranking
          .rank(candidates, oldPlan)
          .map((asset) => asset.id)
          .toList();
      final newOrder = ranking
          .rank(candidates, currentPlan)
          .map((asset) => asset.id)
          .toList();

      expect(
        oldOrder.first,
        'portrait',
        reason: 'provider order was the old tie-breaker',
      );
      expect(newOrder.take(2), ['current-parody', 'classic-meme']);
      expect(
        newOrder.indexOf('portrait'),
        greaterThan(newOrder.indexOf('classic-meme')),
      );
      expect(
        newOrder.indexOf('reddit-variant'),
        lessThan(newOrder.indexOf('portrait')),
      );
      expect(newOrder.last, 'generic-tiktok');
    });

    test('keeps a held-out name searchable while requiring metadata for meme source boosts', () {
      final plan = planner.plan(
        const SearchRequest(query: 'Tim Cook'),
        now: activeDate,
      );
      const memeSubreddit = MemeAsset(
        id: 'meme-subreddit',
        title: 'Tim Cook',
        origin: 'web',
        sourceUrl: 'https://www.reddit.com/r/memes/comments/tim_cook/',
        originalUrl: 'https://preview.redd.it/tim-cook.jpg',
      );
      const ordinarySubreddit = MemeAsset(
        id: 'ordinary-subreddit',
        title: 'Tim Cook',
        origin: 'web',
        sourceUrl: 'https://www.reddit.com/r/nvidia/comments/tim_cook/',
        originalUrl: 'https://preview.redd.it/tim-cook-news.jpg',
      );
      const unrelatedTikTok = MemeAsset(
        id: 'unrelated-tiktok',
        title: 'phone trend clip',
        origin: 'web',
        sourceUrl: 'https://www.tiktok.com/@random/video/456',
        originalUrl: 'https://cdn.tiktok.com/cover-456.jpg',
      );

      final result = ranking.rank([
        ordinarySubreddit,
        unrelatedTikTok,
        memeSubreddit,
      ], plan);

      expect(plan.memeIntent?.profile, isNull);
      expect(plan.providerQuery, 'Tim Cook meme');
      expect(result.map((asset) => asset.id), [
        'meme-subreddit',
        'ordinary-subreddit',
        'unrelated-tiktok',
      ]);
    });
  });
}

QueryPlan _preDictionaryPlan(QueryPlan source) => QueryPlan(
  original: source.original,
  words: source.words,
  rawTags: source.rawTags,
  tagTerms: source.tagTerms,
  tagIds: source.tagIds,
  expandedAliases: source.expandedAliases,
  coreTerms: const ['jensen', 'huang'],
  contextTerms: source.contextTerms,
  requiredContext: source.requiredContext,
  providerQuery: source.providerQuery,
  filter: source.filter,
  similar: source.similar,
);
