import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meme_searcher/core/app_services.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/platform/media_actions.dart';
import 'package:meme_searcher/ui/screens/search_screen.dart';

void main() {
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

class _FakeServices implements AppServices {
  int searches = 0;
  final asset = const MemeAsset(
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
  }) async => MediaFile(bytes: Uint8List(0), path: '', asset: asset);

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
  Future<SettingsState> settings() async =>
      const SettingsState(serpApiConfigured: false, serpApiKeySource: '');

  @override
  Future<MemeAsset> toggleFavorite(String assetId) async => asset;

  @override
  Future<void> writeSerpApiKey(String key) async {}
}
