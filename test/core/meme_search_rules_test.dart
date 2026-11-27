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
    test('dates only the Google search for name-shaped unregistered input', () {
      for (final name in ['Elon Musk', 'pedro pascal', 'Rihanna', '김두한']) {
        final plan = planner.plan(SearchRequest(query: name), now: activeDate);
        expect(plan.memeIntent?.profile, isNull, reason: name);
        expect(plan.googleRecentDays, 30, reason: name);
        expect(plan.naverQuery, startsWith(name), reason: name);
      }
      for (final query in [
        '과일 먹는 짤',
        '고양이',
        'Jim Carrey laughing',
        'Jim Carrey classic',
        'Drake',
        '젠슨 황',
        'Elon Musk #인터뷰',
      ]) {
        expect(
          planner
              .plan(SearchRequest(query: query), now: activeDate)
              .googleRecentDays,
          isNull,
          reason: query,
        );
      }
      expect(
        planner
            .plan(
              const SearchRequest(query: 'Elon Musk'),
              learnedScene: 'a named reaction',
              now: activeDate,
            )
            .googleRecentDays,
        isNull,
      );
    });

    test(
      'keeps a credible all-time meme among the first three recent results',
      () {
        final plan = planner.plan(
          const SearchRequest(query: 'Elon Musk'),
          now: activeDate,
        );
        MemeAsset candidate(
          String id,
          String engine,
          String title,
          String host,
          int rank,
        ) => MemeAsset(
          id: id,
          title: title,
          origin: 'web',
          sourceUrl:
              'https://$host/${engine == 'google' ? '2026/11/25/' : ''}$id',
          originalUrl: 'https://example.test/$id.png',
          engines: [engine],
          providerRanks: {engine: rank},
          originalProviderRank: rank,
        );
        final recent = [
          for (var rank = 1; rank <= 4; rank++)
            candidate(
              'recent-$rank',
              'google',
              'Elon Musk reaction meme $rank',
              'tenor.com',
              rank,
            ),
        ];
        final undated = recent
            .map(
              (asset) =>
                  asset.copyWith(sourceUrl: 'https://tenor.com/${asset.id}'),
            )
            .toList();
        final classic = candidate(
          'classic',
          'naver',
          'Elon Musk old reaction meme',
          'giphy.com',
          8,
        );
        final portrait = candidate(
          'photo',
          'naver',
          'Elon Musk official portrait',
          'example.test',
          1,
        );
        final product = candidate(
          'product',
          'naver',
          'Elon Musk meme print',
          'www.etsy.com',
          1,
        );
        expect(
          ranking
              .rank([...recent, classic, portrait, product], plan)
              .take(3)
              .map((asset) => asset.id),
          ['recent-1', 'recent-2', 'classic'],
        );
        expect(ranking.rank([...undated, classic], plan).first.id, 'classic');
        expect(
          ranking
              .rank([...recent, portrait, product], plan)
              .take(3)
              .map((asset) => asset.id),
          ['recent-1', 'recent-2', 'recent-3'],
        );
      },
    );

    test('uses a corroborating source date for the recent bonus', () {
      final plan = planner.plan(
        const SearchRequest(query: 'Elon Musk'),
        now: activeDate,
      );
      const post = MemeAsset(
        id: 'post',
        title: 'Elon Musk reaction meme',
        origin: 'web',
        engines: ['google'],
        providerRanks: {'google': 1},
      );
      final undated = post.copyWith(sourceUrl: 'https://example.test/meme');
      final current = post.copyWith(
        sourceUrl: 'https://example.test/2026/11/25/meme',
      );
      final invalidDay = post.copyWith(
        sourceUrl: 'https://example.test/2026/10/32/meme',
      );
      final oldX = post.copyWith(
        sourceUrl: 'https://x.com/elonmusk/status/2086305001110954244',
      );
      const snowflakeEpoch = 1288834974657;
      final recentMillis = DateTime.utc(2026, 11, 20).millisecondsSinceEpoch;
      final recentId = BigInt.from(recentMillis - snowflakeEpoch) << 22;
      final recentX = post.copyWith(
        sourceUrl: 'https://x.com/creator/status/$recentId',
      );
      final score = ranking.cheapScore(undated, plan);
      expect(ranking.cheapScore(current, plan), score + 25);
      expect(ranking.cheapScore(recentX, plan), score + 25);
      expect(ranking.cheapScore(oldX, plan), score);
      expect(ranking.cheapScore(invalidDay, plan), score);
    });

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
