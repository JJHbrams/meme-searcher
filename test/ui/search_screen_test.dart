import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meme_searcher/core/app_services.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/core/serpapi_account.dart';
import 'package:meme_searcher/platform/media_actions.dart';
import 'package:meme_searcher/ui/app_theme.dart';
import 'package:meme_searcher/ui/screens/magic_conch_screen.dart';
import 'package:meme_searcher/ui/screens/search_screen.dart';

void main() {
  Future<void> openApp(
    WidgetTester tester,
    _FakeServices services, {
    MediaActions? actions,
    Size size = const Size(1440, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(
          services: services,
          actions: actions ?? MediaActions(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> searchFromHome(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == '밈 키워드, 문구, 캐릭터를 입력하세요',
      ),
      query,
    );
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
  }

  for (final previewOnly in [false, true]) {
    testWidgets(
      'web result shows format and copies ${previewOnly ? 'labelled preview' : 'original'} by button and Ctrl+C',
      (tester) async {
        final services = _FakeServices()
          ..asset = MemeAsset(
            id: 'web',
            title: 'Web result',
            origin: 'web',
            originalUrl: 'https://images.example/media',
            formatHint: previewOnly ? 'WEBP' : null,
          )
          ..failOriginal = previewOnly;
        final actions = _RecordingActions();
        await openApp(tester, services, actions: actions);
        await tester.tap(find.text('웹'));
        await searchFromHome(tester, 'web result');
        expect(find.text(previewOnly ? 'WEBP' : 'JPEG'), findsOneWidget);
        await tester.ensureVisible(find.text('Web result'));
        await tester.tap(find.text('Web result'));
        await tester.pumpAndSettle();
        final copy = find.text(previewOnly ? '미리보기 이미지 복사' : '복사');
        await tester.ensureVisible(copy);
        await tester.tap(copy);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(actions.copied.map((f) => f.path), [
          previewOnly ? 'preview.png' : 'original.png',
          previewOnly ? 'preview.png' : 'original.png',
        ]);
        expect(find.textContaining('PNG · 2×2'), findsWidgets);
        if (Platform.isWindows) {
          final fileCopy = find.text('파일로 복사');
          if (previewOnly) {
            expect(fileCopy, findsNothing);
          } else {
            await tester.ensureVisible(fileCopy);
            await tester.tap(fileCopy);
            await tester.pump();
            expect(actions.copiedFiles.map((f) => f.path), ['original.png']);
          }
        }
        if (previewOnly) {
          final save = tester.widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '원본 저장'),
          );
          expect(save.onPressed, isNull);
        }
      },
    );
  }

  testWidgets('first run can be deferred and reopened from settings', (
    tester,
  ) async {
    const channel = MethodChannel(MediaActions.channelName);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getAppVersion');
      return '2.4.6.37';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final services = _FakeServices()..deferred = false;
    await openApp(tester, services);
    expect(find.text('Google 이미지 검색 연결'), findsOneWidget);
    expect(find.text('업데이트 확인'), findsNothing);
    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();
    expect(services.deferred, isTrue);
    await tester.pumpWidget(const SizedBox());
    await openApp(tester, services);
    expect(find.text('Google 이미지 검색 연결'), findsNothing);
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    expect(find.text('API 키 페이지 열기'), findsOneWidget);
    expect(find.text('Meme Snatcher · v2.4.6.37'), findsOneWidget);
    expect(find.text('업데이트 확인'), findsOneWidget);
  });

  testWidgets('clipboard connection only imports a key on request', (
    tester,
  ) async {
    final services = _FakeServices()..deferred = false;
    var clipboard = 'some other clipboard content';
    var reads = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        reads++;
        return {'text': clipboard};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await openApp(tester, services);
    expect(reads, 0);
    await tester.tap(find.text('복사한 키로 연결'));
    await tester.pumpAndSettle();
    expect(services.savedKey, isNull);
    expect(find.textContaining('클립보드에서 API 키를 찾지 못했어요'), findsOneWidget);
    clipboard = 'a' * 64;
    await tester.tap(find.text('복사한 키로 연결'));
    await tester.pumpAndSettle();
    expect(services.savedKey, clipboard);
    expect(find.text('Google 이미지 검색 연결'), findsNothing);
  });

  testWidgets(
    'library stays usable when the defer preference cannot be saved',
    (tester) async {
      final services = _FakeServices()
        ..deferred = false
        ..failDeferral = true;
      await openApp(tester, services);
      await tester.tap(find.text('나중에'));
      await tester.pumpAndSettle();
      expect(find.text('Google 이미지 검색 연결'), findsNothing);
      expect(find.text('Recent asset'), findsOneWidget);
    },
  );

  testWidgets('an environment key skips onboarding', (tester) async {
    final services = _FakeServices()
      ..deferred = false
      ..hasEnvironmentKey = true;
    await openApp(tester, services);
    expect(find.text('Google 이미지 검색 연결'), findsNothing);
  });

  testWidgets('examples only prefill and a button press starts a search', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final services = _FakeServices();
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(services: services, actions: MediaActions()),
      ),
    );
    await tester.pumpAndSettle();

    expect(services.searches, 0);
    final page = find.byType(Scrollable).first;
    final example = find.text('approved!');
    await tester.scrollUntilVisible(
      example.hitTestable(),
      200,
      scrollable: page,
    );
    await tester.pumpAndSettle();
    await tester.tap(example);
    await tester.pump();
    expect(services.searches, 0);

    await tester.scrollUntilVisible(
      find.text('검색').hitTestable(),
      -200,
      scrollable: page,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    expect(services.searches, 1);
    expect(find.text('Approved meme'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '이미지'), findsOneWidget);
  });

  testWidgets(
    'Home searches all by default and does not search before submit',
    (tester) async {
      final services = _FakeServices();
      await openApp(tester, services);
      final banner = find.bySemanticsLabel('Meme Snatcher 짤 서랍');
      expect(banner, findsOneWidget);
      final bounds = tester.getRect(banner);
      expect(bounds.topLeft, Offset.zero);
      expect(bounds.width, tester.getSize(find.byType(Scaffold)).width);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('nav-home'))).dy,
        greaterThanOrEqualTo(bounds.bottom),
      );
      expect(find.text('최근 사용'), findsOneWidget);
      expect(find.text('최근 검색'), findsOneWidget);
      expect(find.text('검색').hitTestable(), findsOneWidget);
      expect(services.searches, 0);

      await searchFromHome(tester, 'default scope');
      expect(banner, findsNothing);
      expect(services.requests.single.scope, SearchScope.all);
      expect(services.recordedQueries, ['default scope']);
    },
  );

  testWidgets('conch is reachable on both layouts and does not search', (
    tester,
  ) async {
    const webview = MethodChannel('io.jns.webview.win');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(webview, (call) async {
      expect(call.method, 'getWebViewVersion');
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(webview, null));
    final services = _FakeServices();
    await openApp(tester, services);
    for (final width in [1440.0, 560.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-conch')));
      await tester.pumpAndSettle();
      expect(find.byType(MagicConchScreen), findsOneWidget);
      expect(find.text('WebView2 다운로드'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(services.searches, 0);
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pumpAndSettle();
      expect(find.byType(MagicConchScreen), findsNothing);
      expect(find.text('최근 검색'), findsOneWidget);
    }
  });

  testWidgets(
    'navigation cancels a pending all search and loads its library page',
    (tester) async {
      final services = _FakeServices()
        ..pendingSearch = Completer<SearchResponse>();
      await openApp(tester, services);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == '밈 키워드, 문구, 캐릭터를 입력하세요',
        ),
        'slow query',
      );
      await tester.tap(find.text('검색'));
      await tester.pump();
      expect(services.searches, 1);

      // Search itself selects 전체; tapping it must still invalidate the pending result.
      await tester.tap(find.byKey(const ValueKey('nav-all')));
      await tester.pumpAndSettle();
      expect(find.text('Library asset'), findsOneWidget);
      services.pendingSearch!.complete(
        SearchResponse(
          assets: [services.webAsset],
          attempts: const [],
          scope: SearchScope.all,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Web search result'), findsNothing);
      expect(find.text('Library asset'), findsOneWidget);
    },
  );

  testWidgets('sidebar shows a readable SerpApi quota and can refresh it', (
    tester,
  ) async {
    final services = _FakeServices()
      ..quota = const SerpApiQuota(
        monthlyLimit: 100,
        monthlyRemaining: 8,
        totalRemaining: 11,
        extraCredits: 3,
      );
    await openApp(tester, services);

    final quotaLabel = find.bySemanticsLabel(RegExp('SerpApi 검색 잔여량'));
    expect(quotaLabel, findsWidgets);
    expect(find.text('총 11회 남음'), findsOneWidget);
    expect(find.text('이번 달 8 / 100회 남음'), findsOneWidget);
    expect(find.text('추가 크레딧 3회'), findsOneWidget);
    expect(services.quotaReads, 1);

    await tester.tap(find.byTooltip('SerpApi 잔여량 새로고침'));
    await tester.pumpAndSettle();
    expect(services.quotaReads, 2);

    await tester.binding.setSurfaceSize(const Size(1280, 720));
    await tester.pumpAndSettle();
    expect(find.text('총 11회 남음').hitTestable(), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(1920, 720));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('only web and all searches refresh the SerpApi quota', (
    tester,
  ) async {
    final services = _FakeServices();
    await openApp(tester, services);
    expect(services.quotaReads, 1);

    await tester.tap(find.text('내 짤'));
    await searchFromHome(tester, 'local only');
    expect(services.quotaReads, 1);

    await tester.tap(find.text('웹'));
    await searchFromHome(tester, 'web only');
    expect(services.quotaReads, 2);
  });

  testWidgets('Home limits sections to five and opens a query and an asset', (
    tester,
  ) async {
    final services = _FakeServices()
      ..recent = List.generate(
        6,
        (index) => MemeAsset(
          id: 'recent-$index',
          title: 'Recent $index',
          origin: 'library',
        ),
      )
      ..favorites = List.generate(
        6,
        (index) => MemeAsset(
          id: 'favorite-$index',
          title: 'Favorite $index',
          origin: 'library',
          favorite: true,
        ),
      )
      ..queries = ['repeat query'];
    await openApp(tester, services);
    expect(find.textContaining('Recent '), findsNWidgets(5));
    final viewport = tester.getRect(find.byType(Scaffold));
    await tester.dragFrom(
      viewport.bottomRight - const Offset(100, 70),
      Offset(0, -viewport.height / 2),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Favorite '), findsNWidgets(5));
    await tester.tap(find.text('repeat query'));
    await tester.pumpAndSettle();
    expect(services.requests.single.query, 'repeat query');

    await tester.tap(find.byKey(const ValueKey('nav-home')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent 0'));
    await tester.pumpAndSettle();
    expect(services.markedRecent, contains('recent-0'));
  });

  testWidgets('left menu opens each collection after a completed search', (
    tester,
  ) async {
    final services = _FakeServices();
    await openApp(tester, services);
    await searchFromHome(tester, '지난 검색');
    for (final (nav, title) in [
      ('favorites', 'Favorite asset'),
      ('recent', 'Recent asset'),
      ('all', 'Library asset'),
    ]) {
      await tester.tap(find.byKey(ValueKey('nav-$nav')));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text('검색 결과'), findsNothing);
      expect(find.text('지난 검색'), findsNothing);
      expect(services.searches, 1);
    }
  });

  testWidgets('all browse keeps temporary copies in two rows until expanded', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(560, 1800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final services = _FakeServices()
      ..cached = List.generate(
        7,
        (index) => MemeAsset(
          id: 'cache-$index',
          title: 'provider-file-$index.png',
          submittedQuery: 'Temporary $index',
          origin: 'cache',
          format: 'PNG',
        ),
      );
    await openApp(tester, services, size: const Size(560, 1800));
    await tester.tap(find.byKey(const ValueKey('nav-all')));
    await tester.pumpAndSettle();

    expect(find.text('임시 저장'), findsWidgets);
    expect(find.text('내 짤'), findsWidgets);
    expect(find.textContaining('Temporary '), findsNWidgets(6));
    expect(find.textContaining('provider-file-'), findsNothing);
    expect(find.text('펼치기 (1)'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 1800);
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    await tester.pumpAndSettle();
    expect(find.textContaining('Temporary '), findsNWidgets(4));
    expect(find.text('펼치기 (3)'), findsOneWidget);
    tester.view.physicalSize = const Size(560, 1800);
    await tester.binding.setSurfaceSize(const Size(560, 1800));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('펼치기 (1)'));
    await tester.tap(find.text('펼치기 (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Temporary '), findsNWidgets(7));
  });

  testWidgets('selection delete spans cache and library with cancellation', (
    tester,
  ) async {
    final services = _FakeServices()
      ..cached = const [
        MemeAsset(id: 'cache-delete', title: 'Cache delete', origin: 'cache'),
      ]
      ..allAssets = const [
        MemeAsset(
          id: 'library-delete',
          title: 'Library delete',
          origin: 'library',
        ),
      ];
    await openApp(tester, services);
    await tester.tap(find.byKey(const ValueKey('nav-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('select-delete')));
    await tester.pump();
    await tester.tap(find.text('Cache delete'));
    await tester.pump();
    await tester.tap(find.text('Library delete'));
    await tester.pump();
    expect(find.text('2개 선택'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('local-delete-cancel')));
    await tester.pumpAndSettle();
    expect(services.deletedAssetIds, isEmpty);
    expect(find.text('Cache delete'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-delete')));
    await tester.pumpAndSettle();
    expect(
      services.deletedAssetIds,
      containsAll(['cache-delete', 'library-delete']),
    );
    expect(find.text('Cache delete'), findsNothing);
    expect(find.text('Library delete'), findsNothing);
    expect(find.text('2개 짤을 삭제했어요.'), findsOneWidget);
  });

  testWidgets('preview deletion remains available after media load failure', (
    tester,
  ) async {
    final services = _FakeServices()..failOriginal = true;
    await openApp(tester, services);
    await tester.tap(find.text('Recent asset'));
    await tester.pumpAndSettle();
    final delete = find.byKey(const ValueKey('preview-delete'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-delete')));
    await tester.pumpAndSettle();
    expect(services.deletedAssetIds, contains('recent-asset'));
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('web-only preview never offers local deletion', (tester) async {
    final services = _FakeServices();
    await openApp(tester, services);
    await tester.tap(find.text('웹'));
    await searchFromHome(tester, 'web result');
    await tester.tap(find.text('Approved meme'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-delete')), findsNothing);
  });

  testWidgets('copy uses the durable copy callback', (tester) async {
    final services = _FakeServices();
    final actions = _RecordingActions();
    await openApp(tester, services, actions: actions);
    await tester.tap(find.text('Recent asset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('복사'));
    await tester.pumpAndSettle();
    expect(actions.copied, hasLength(1));
    expect(services.keptCopies, 1);
  });

  testWidgets('a completed copy refreshes all browse after its dialog closes', (
    tester,
  ) async {
    final services = _FakeServices()
      ..cached = const [
        MemeAsset(
          id: 'cached-copy',
          title: 'Cached copy',
          origin: 'cache',
          format: 'PNG',
        ),
      ]
      ..pendingKeep = Completer<bool>();
    await openApp(tester, services, actions: _RecordingActions());
    await tester.tap(find.byKey(const ValueKey('nav-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cached copy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('복사'));
    await tester.pump();
    await tester.tap(find.byTooltip('미리보기 닫기'));
    await tester.pumpAndSettle();
    final readsAfterClose = services.cachedReads;
    services.pendingKeep!.complete(true);
    await tester.pumpAndSettle();
    expect(services.cachedReads, greaterThan(readsAfterClose));
  });

  testWidgets('saving a cached item promotes it into the visible library', (
    tester,
  ) async {
    final services = _FakeServices()
      ..allAssets = const [
        MemeAsset(
          id: 'existing-library',
          title: 'Existing library item',
          origin: 'library',
          format: 'PNG',
        ),
      ]
      ..cached = const [
        MemeAsset(
          id: 'cache-promote',
          title: 'Promote me',
          origin: 'cache',
          format: 'PNG',
        ),
      ];
    await openApp(tester, services);
    await tester.tap(find.byKey(const ValueKey('nav-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Promote me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('내 짤에 저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('미리보기 닫기'));
    await tester.pumpAndSettle();
    expect(find.text('임시 저장'), findsNothing);
    expect(find.text('Promote me'), findsOneWidget);
  });

  testWidgets('preview shows a readable in-dialog copy confirmation', (
    tester,
  ) async {
    final services = _FakeServices();
    final actions = _RecordingActions();
    await openApp(tester, services, actions: actions);
    await tester.tap(find.text('Recent asset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('복사'));
    await tester.pump();

    final feedback = find.text('클립보드에 복사했어요.');
    expect(feedback, findsOneWidget);
    expect(tester.widget<Text>(feedback).style?.color, MemeTheme.text);
    expect(
      find.ancestor(of: feedback, matching: find.byType(Dialog)),
      findsOneWidget,
    );
  });
}

class _RecordingActions extends MediaActions {
  final copied = <MediaFile>[];
  final copiedFiles = <MediaFile>[];

  @override
  Future<MediaActionResult> copyFile(MediaFile file) async {
    copiedFiles.add(file);
    return const MediaActionResult.success();
  }

  @override
  Future<MediaActionResult> copy(MediaFile file) async {
    copied.add(file);
    return const MediaActionResult.success();
  }
}

class _FakeServices implements AppServices {
  int searches = 0;
  final requests = <SearchRequest>[];
  final recordedQueries = <String>[];
  final markedRecent = <String>[];
  Completer<SearchResponse>? pendingSearch;
  bool deferred = true;
  bool hasEnvironmentKey = false;
  bool failDeferral = false;
  String? savedKey;
  bool failOriginal = false;
  SerpApiQuota? quota;
  int quotaReads = 0;
  MemeAsset asset = const MemeAsset(
    id: 'approved',
    title: 'Approved meme',
    origin: 'library',
    format: 'GIF',
    tags: [MemeTag(id: 'sonic', label: 'sonic')],
  );
  final libraryAsset = const MemeAsset(
    id: 'library',
    title: 'Library asset',
    origin: 'library',
    format: 'PNG',
  );
  final webAsset = const MemeAsset(
    id: 'web-result',
    title: 'Web search result',
    origin: 'web',
    format: 'PNG',
  );
  List<MemeAsset> recent = const [
    MemeAsset(
      id: 'recent-asset',
      title: 'Recent asset',
      origin: 'library',
      format: 'PNG',
    ),
  ];
  List<MemeAsset> favorites = const [
    MemeAsset(
      id: 'favorite-asset',
      title: 'Favorite asset',
      origin: 'library',
      favorite: true,
      format: 'GIF',
    ),
  ];
  List<MemeAsset> cached = const [];
  List<MemeAsset>? allAssets;
  final deletedAssetIds = <String>[];
  int keptCopies = 0;
  int cachedReads = 0;
  Completer<bool>? pendingKeep;
  List<String> queries = const [];

  @override
  Future<void> initialize() async {}

  @override
  Future<List<MemeAsset>> library({
    MediaFilter filter = MediaFilter.all,
    bool favoritesOnly = false,
    bool recentOnly = false,
  }) async {
    if (recentOnly) return recent;
    if (favoritesOnly) return favorites;
    return allAssets ?? [libraryAsset];
  }

  @override
  Future<List<MemeAsset>> cachedLibrary({
    MediaFilter filter = MediaFilter.all,
  }) async {
    cachedReads++;
    return cached;
  }

  @override
  Future<int> deleteLocalAssets(Iterable<String> assetIds) async {
    final ids = assetIds.toSet();
    deletedAssetIds.addAll(ids);
    cached = cached.where((asset) => !ids.contains(asset.id)).toList();
    allAssets = (allAssets ?? [libraryAsset])
        .where((asset) => !ids.contains(asset.id))
        .toList();
    recent = recent.where((asset) => !ids.contains(asset.id)).toList();
    favorites = favorites.where((asset) => !ids.contains(asset.id)).toList();
    return ids.length;
  }

  @override
  Future<bool> copyAndKeep(
    MediaFile file,
    Future<bool> Function(MediaFile) copy,
  ) async {
    final copied = await copy(file);
    if (copied) keptCopies++;
    return copied ? (pendingKeep?.future ?? true) : false;
  }

  @override
  Future<MediaFile> loadMedia(
    MemeAsset asset, {
    bool preferCached = true,
  }) async {
    if (failOriginal) throw StateError('Original unavailable');
    return _testFile(asset, 'original.png');
  }

  @override
  Future<String?> probeWebFormat(MemeAsset asset) async => 'JPEG';

  @override
  Future<MediaFile> loadPreviewMedia(MemeAsset asset) =>
      _testFile(asset, 'preview.png');

  Future<MediaFile> _testFile(MemeAsset asset, String path) async {
    final data = await rootBundle.load('assets/app-icon.png');
    return MediaFile(
      bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      path: path,
      asset: asset.copyWith(format: 'PNG', width: 2, height: 2),
    );
  }

  @override
  Future<void> markRecent(String assetId, {MemeAsset? asset}) async {
    markedRecent.add(assetId);
  }

  @override
  Future<List<String>> recentSearches() async => queries;

  @override
  Future<void> recordSearch(String query) async {
    recordedQueries.add(query);
  }

  @override
  Future<String?> readSerpApiKey() async => null;

  @override
  Future<SerpApiQuota?> readSerpApiQuota() async {
    quotaReads += 1;
    return quota;
  }

  @override
  Future<void> deleteSerpApiKey() async {}

  @override
  Future<MemeAsset> saveToLibrary(
    MediaFile file, {
    String? title,
    String? familyId,
    String? familyName,
    List<MemeTag> tags = const [],
    List<String> aliases = const [],
  }) async {
    final saved = file.asset.copyWith(origin: 'library');
    allAssets = [...?allAssets, saved];
    cached = cached.where((item) => item.id != file.asset.id).toList();
    return saved;
  }

  @override
  Future<SearchResponse> search(SearchRequest request) async {
    searches += 1;
    requests.add(request);
    if (pendingSearch != null) return pendingSearch!.future;
    return SearchResponse(
      assets: [asset],
      attempts: const [],
      scope: request.scope,
    );
  }

  @override
  Future<SettingsState> settings() async => SettingsState(
    serpApiConfigured: savedKey != null || hasEnvironmentKey,
    serpApiKeySource: savedKey != null
        ? 'app'
        : hasEnvironmentKey
        ? 'environment'
        : 'none',
    serpApiSetupDeferred: deferred,
  );

  @override
  Future<void> deferSerpApiSetup() async {
    if (failDeferral) throw StateError('storage unavailable');
    deferred = true;
  }

  @override
  Future<MemeAsset> toggleFavorite(String assetId, {MemeAsset? asset}) async =>
      (asset ?? this.asset).copyWith(favorite: !(asset ?? this.asset).favorite);

  @override
  Future<void> writeSerpApiKey(String key) async {
    savedKey = key;
  }
}
