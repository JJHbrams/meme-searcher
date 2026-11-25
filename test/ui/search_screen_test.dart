import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meme_searcher/core/app_services.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/platform/media_actions.dart';
import 'package:meme_searcher/ui/app_theme.dart';
import 'package:meme_searcher/ui/screens/search_screen.dart';

void main() {
  Future<void> openApp(
    WidgetTester tester,
    _FakeServices services, {
    MediaActions? actions,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
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
    final services = _FakeServices()..deferred = false;
    await openApp(tester, services);
    expect(find.text('Google 이미지 검색 연결'), findsOneWidget);
    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();
    expect(services.deferred, isTrue);
    await tester.pumpWidget(const SizedBox());
    await openApp(tester, services);
    expect(find.text('Google 이미지 검색 연결'), findsNothing);
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    expect(find.text('API 키 페이지 열기'), findsOneWidget);
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
    await tester.tap(find.text('approved!'));
    await tester.pump();
    expect(services.searches, 0);

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
      expect(find.text('최근 사용'), findsOneWidget);
      expect(find.text('최근 검색'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.text('즐겨찾기'),
        ),
        findsOneWidget,
      );
      expect(services.searches, 0);

      await searchFromHome(tester, 'default scope');
      expect(services.requests.single.scope, SearchScope.all);
      expect(services.recordedQueries, ['default scope']);
    },
  );

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
    return [libraryAsset];
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
  Future<void> deleteSerpApiKey() async {}

  @override
  Future<MemeAsset> saveToLibrary(
    MediaFile file, {
    String? title,
    String? familyId,
    String? familyName,
    List<MemeTag> tags = const [],
    List<String> aliases = const [],
  }) async => asset;

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
