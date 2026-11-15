import 'dart:typed_data';

enum SearchScope { library, web, all }

enum MediaFilter { all, gif, staticImage }

extension SearchScopeJson on SearchScope {
  String get wireName => switch (this) {
    SearchScope.library => 'library',
    SearchScope.web => 'web',
    SearchScope.all => 'all',
  };

  static SearchScope parse(String? value) => switch (value) {
    'library' => SearchScope.library,
    'web' => SearchScope.web,
    _ => SearchScope.all,
  };
}

extension MediaFilterJson on MediaFilter {
  String get wireName => switch (this) {
    MediaFilter.all => 'all',
    MediaFilter.gif => 'gif',
    MediaFilter.staticImage => 'static',
  };

  static MediaFilter parse(String? value) => switch (value) {
    'gif' => MediaFilter.gif,
    'static' => MediaFilter.staticImage,
    _ => MediaFilter.all,
  };
}

class MemeTag {
  const MemeTag({required this.id, required this.label});

  final String id;
  final String label;

  Map<String, Object?> toJson() => {'id': id, 'label': label};

  factory MemeTag.fromJson(Map<String, Object?> json) => MemeTag(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
  );
}

class MemeAsset {
  const MemeAsset({
    required this.id,
    required this.title,
    required this.origin,
    this.familyId,
    this.familyName,
    this.variant,
    this.filePath,
    this.bundledAssetPath,
    this.originalUrl,
    this.previewUrl,
    this.sourceUrl,
    this.discoveryUrl,
    this.format,
    this.formatHint,
    this.mime,
    this.width,
    this.height,
    this.frames,
    this.bytes,
    this.tags = const [],
    this.aliases = const [],
    this.engines = const [],
    this.providerRanks = const {},
    this.favorite = false,
    this.animated = false,
    this.motionVerified = false,
    this.verified = false,
    this.originalProviderRank = 0,
    this.rankingScore = 0,
    this.inspectionStatus = 'unverified',
    this.inspectionReason,
    this.matchReason,
    this.referenceId,
    this.visualScore,
    this.addedAt,
  });

  final String id;
  final String title;
  final String origin;
  final String? familyId;
  final String? familyName;
  final String? variant;
  final String? filePath;
  final String? bundledAssetPath;
  final String? originalUrl;
  final String? previewUrl;
  final String? sourceUrl;
  final String? discoveryUrl;
  final String? format;
  final String? formatHint;
  final String? mime;
  final int? width;
  final int? height;
  final int? frames;
  final int? bytes;
  final List<MemeTag> tags;
  final List<String> aliases;
  final List<String> engines;
  final Map<String, int> providerRanks;
  final bool favorite;
  final bool animated;
  final bool motionVerified;
  final bool verified;
  final int originalProviderRank;
  final num rankingScore;
  final String inspectionStatus;
  final String? inspectionReason;
  final String? matchReason;
  final String? referenceId;
  final num? visualScore;
  final DateTime? addedAt;

  bool get isGif => (format ?? formatHint ?? '').toUpperCase() == 'GIF';
  bool get isWeb => origin == 'web';
  String get primaryEngine => engines.isEmpty ? '' : engines.first;

  MemeAsset copyWith({
    String? id,
    String? title,
    String? origin,
    String? familyId,
    String? familyName,
    String? variant,
    String? filePath,
    String? bundledAssetPath,
    String? originalUrl,
    String? previewUrl,
    String? sourceUrl,
    String? discoveryUrl,
    String? format,
    String? formatHint,
    String? mime,
    int? width,
    int? height,
    int? frames,
    int? bytes,
    List<MemeTag>? tags,
    List<String>? aliases,
    List<String>? engines,
    Map<String, int>? providerRanks,
    bool? favorite,
    bool? animated,
    bool? motionVerified,
    bool? verified,
    int? originalProviderRank,
    num? rankingScore,
    String? inspectionStatus,
    String? inspectionReason,
    String? matchReason,
    String? referenceId,
    num? visualScore,
    DateTime? addedAt,
  }) => MemeAsset(
    id: id ?? this.id,
    title: title ?? this.title,
    origin: origin ?? this.origin,
    familyId: familyId ?? this.familyId,
    familyName: familyName ?? this.familyName,
    variant: variant ?? this.variant,
    filePath: filePath ?? this.filePath,
    bundledAssetPath: bundledAssetPath ?? this.bundledAssetPath,
    originalUrl: originalUrl ?? this.originalUrl,
    previewUrl: previewUrl ?? this.previewUrl,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    discoveryUrl: discoveryUrl ?? this.discoveryUrl,
    format: format ?? this.format,
    formatHint: formatHint ?? this.formatHint,
    mime: mime ?? this.mime,
    width: width ?? this.width,
    height: height ?? this.height,
    frames: frames ?? this.frames,
    bytes: bytes ?? this.bytes,
    tags: tags ?? this.tags,
    aliases: aliases ?? this.aliases,
    engines: engines ?? this.engines,
    providerRanks: providerRanks ?? this.providerRanks,
    favorite: favorite ?? this.favorite,
    animated: animated ?? this.animated,
    motionVerified: motionVerified ?? this.motionVerified,
    verified: verified ?? this.verified,
    originalProviderRank: originalProviderRank ?? this.originalProviderRank,
    rankingScore: rankingScore ?? this.rankingScore,
    inspectionStatus: inspectionStatus ?? this.inspectionStatus,
    inspectionReason: inspectionReason ?? this.inspectionReason,
    matchReason: matchReason ?? this.matchReason,
    referenceId: referenceId ?? this.referenceId,
    visualScore: visualScore ?? this.visualScore,
    addedAt: addedAt ?? this.addedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'origin': origin,
    'familyId': familyId,
    'familyName': familyName,
    'variant': variant,
    'filePath': filePath,
    'bundledAssetPath': bundledAssetPath,
    'originalUrl': originalUrl,
    'previewUrl': previewUrl,
    'sourceUrl': sourceUrl,
    'discoveryUrl': discoveryUrl,
    'format': format,
    'formatHint': formatHint,
    'mime': mime,
    'width': width,
    'height': height,
    'frames': frames,
    'bytes': bytes,
    'tags': tags.map((tag) => tag.toJson()).toList(),
    'aliases': aliases,
    'engines': engines,
    'providerRanks': providerRanks,
    'favorite': favorite,
    'animated': animated,
    'motionVerified': motionVerified,
    'verified': verified,
    'originalProviderRank': originalProviderRank,
    'rankingScore': rankingScore,
    'inspectionStatus': inspectionStatus,
    'inspectionReason': inspectionReason,
    'matchReason': matchReason,
    'referenceId': referenceId,
    'visualScore': visualScore,
    'addedAt': addedAt?.toIso8601String(),
  };

  factory MemeAsset.fromJson(Map<String, Object?> json) {
    final rawTags = json['tags'];
    final rawEngines = json['engines'];
    final rawAliases = json['aliases'];
    final rawRanks = json['providerRanks'];
    return MemeAsset(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '제목 없음',
      origin: json['origin'] as String? ?? 'library',
      familyId: json['familyId'] as String?,
      familyName: json['familyName'] as String?,
      variant: json['variant'] as String?,
      filePath: json['filePath'] as String?,
      bundledAssetPath: json['bundledAssetPath'] as String?,
      originalUrl: json['originalUrl'] as String?,
      previewUrl: json['previewUrl'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      discoveryUrl: json['discoveryUrl'] as String?,
      format: json['format'] as String?,
      formatHint: json['formatHint'] as String?,
      mime: json['mime'] as String?,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      frames: (json['frames'] as num?)?.toInt(),
      bytes: (json['bytes'] as num?)?.toInt(),
      tags: rawTags is List
          ? rawTags
                .whereType<Map>()
                .map((tag) => MemeTag.fromJson(Map<String, Object?>.from(tag)))
                .toList(growable: false)
          : const [],
      aliases: rawAliases is List
          ? rawAliases.whereType<String>().toList()
          : const [],
      engines: rawEngines is List
          ? rawEngines.whereType<String>().toList()
          : const [],
      providerRanks: rawRanks is Map
          ? rawRanks.map(
              (key, value) => MapEntry(key.toString(), (value as num).toInt()),
            )
          : const {},
      favorite: json['favorite'] as bool? ?? false,
      animated: json['animated'] as bool? ?? false,
      motionVerified: json['motionVerified'] as bool? ?? false,
      verified: json['verified'] as bool? ?? false,
      originalProviderRank:
          (json['originalProviderRank'] as num?)?.toInt() ?? 0,
      rankingScore: json['rankingScore'] as num? ?? 0,
      inspectionStatus: json['inspectionStatus'] as String? ?? 'unverified',
      inspectionReason: json['inspectionReason'] as String?,
      matchReason: json['matchReason'] as String?,
      referenceId: json['referenceId'] as String?,
      visualScore: json['visualScore'] as num?,
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? ''),
    );
  }
}

class SearchRequest {
  const SearchRequest({
    required this.query,
    this.scope = SearchScope.all,
    this.filter = MediaFilter.all,
    this.similar = false,
    this.tags = const [],
    this.favoritesOnly = false,
    this.recentOnly = false,
  });

  final String query;
  final SearchScope scope;
  final MediaFilter filter;
  final bool similar;
  final List<String> tags;
  final bool favoritesOnly;
  final bool recentOnly;

  String get fullQuery => [
    query.trim(),
    ...tags.map((tag) => '#$tag'),
  ].where((value) => value.isNotEmpty).join(' ');
}

class SearchAttempt {
  const SearchAttempt({
    required this.engine,
    required this.status,
    required this.query,
    this.count = 0,
    this.detail,
  });

  final String engine;
  final String status;
  final String query;
  final int count;
  final String? detail;
}

class SearchResponse {
  const SearchResponse({
    required this.assets,
    required this.attempts,
    required this.scope,
    this.cached = false,
    this.message,
    this.error,
  });

  final List<MemeAsset> assets;
  final List<SearchAttempt> attempts;
  final SearchScope scope;
  final bool cached;
  final String? message;
  final String? error;

  bool get hasError => error != null;
}

class MediaFile {
  const MediaFile({
    required this.bytes,
    required this.path,
    required this.asset,
  });

  final Uint8List bytes;
  final String path;
  final MemeAsset asset;
}

class SettingsState {
  const SettingsState({
    required this.serpApiConfigured,
    required this.serpApiKeySource,
  });

  final bool serpApiConfigured;
  final String serpApiKeySource;
}
