import 'models.dart';
import 'serpapi_account.dart';

abstract interface class AppServices {
  Future<void> initialize();

  Future<SearchResponse> search(SearchRequest request);

  Future<List<MemeAsset>> library({
    MediaFilter filter = MediaFilter.all,
    bool favoritesOnly = false,
    bool recentOnly = false,
  });

  Future<List<MemeAsset>> cachedLibrary({MediaFilter filter = MediaFilter.all});

  Future<bool> copyAndKeep(
    MediaFile file,
    Future<bool> Function(MediaFile) copy,
  );

  Future<MediaFile> loadMedia(MemeAsset asset, {bool preferCached = true});

  Future<MediaFile> loadPreviewMedia(MemeAsset asset);

  Future<String?> probeWebFormat(MemeAsset asset);

  Future<MemeAsset> saveToLibrary(
    MediaFile file, {
    String? title,
    String? familyId,
    String? familyName,
    List<MemeTag> tags = const [],
    List<String> aliases = const [],
  });

  Future<MemeAsset> toggleFavorite(String assetId, {MemeAsset? asset});

  Future<void> markRecent(String assetId, {MemeAsset? asset});

  /// Removes only assets currently owned by the local library/cache.
  ///
  /// Callers supply stable asset IDs, never file paths.  The return value is
  /// the number of live entries that were removed (so retries are idempotent).
  Future<int> deleteLocalAssets(Iterable<String> assetIds);

  Future<List<String>> recentSearches();

  Future<void> recordSearch(String query);

  Future<SettingsState> settings();

  Future<String?> readSerpApiKey();

  Future<SerpApiQuota?> readSerpApiQuota();

  Future<void> writeSerpApiKey(String key);

  Future<void> deferSerpApiSetup();

  Future<void> deleteSerpApiKey();
}
