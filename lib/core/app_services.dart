import 'models.dart';

abstract interface class AppServices {
  Future<void> initialize();

  Future<SearchResponse> search(SearchRequest request);

  Future<List<MemeAsset>> library({
    MediaFilter filter = MediaFilter.all,
    bool favoritesOnly = false,
    bool recentOnly = false,
  });

  Future<MediaFile> loadMedia(MemeAsset asset, {bool preferCached = true});

  Future<MemeAsset> saveToLibrary(
    MediaFile file, {
    String? title,
    String? familyId,
    String? familyName,
    List<MemeTag> tags = const [],
    List<String> aliases = const [],
  });

  Future<MemeAsset> toggleFavorite(String assetId);

  Future<void> markRecent(String assetId);

  Future<SettingsState> settings();

  Future<String?> readSerpApiKey();

  Future<void> writeSerpApiKey(String key);

  Future<void> deleteSerpApiKey();
}
