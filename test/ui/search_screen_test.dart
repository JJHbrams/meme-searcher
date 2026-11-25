import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meme_searcher/core/app_services.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/platform/media_actions.dart';
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
      expect(find.text('Approved meme'), findsOneWidget);
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

    expect(services.searches, 1);
    await tester.tap(find.text('approved!'));
    await tester.pump();
    expect(services.searches, 1);

    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();
    expect(services.searches, 2);
    expect(find.text('Approved meme'), findsOneWidget);
  });
}

class _RecordingActions extends MediaActions {
  final copied = <MediaFile>[];
  @override
  Future<MediaActionResult> copy(MediaFile file) async {
    copied.add(file);
    return const MediaActionResult.success();
  }
}

class _FakeServices implements AppServices {
  int searches = 0;
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

  @override
  Future<void> initialize() async {}

  @override
  Future<List<MemeAsset>> library({
    MediaFilter filter = MediaFilter.all,
    bool favoritesOnly = false,
    bool recentOnly = false,
  }) async => [asset];

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
  Future<void> markRecent(String assetId) async {}

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
  Future<MemeAsset> toggleFavorite(String assetId) async => asset;

  @override
  Future<void> writeSerpApiKey(String key) async {
    savedKey = key;
  }
}
