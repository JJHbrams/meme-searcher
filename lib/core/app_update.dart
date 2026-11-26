import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _repository = 'JJHbrams/meme-searcher';
final _versionPattern = RegExp(r'^\d+\.\d+\.\d+\.\d+$');
final _sha256Pattern = RegExp(r'^sha256:([a-f0-9]{64})$');
final _publishedSha256Pattern = RegExp(r'^sha256:([a-fA-F0-9]{64})$');

/// A published release that can always be opened in the browser, and may be
/// installed by the current platform after its package is verified.
abstract interface class AppRelease {
  String get tag;
  Uri get releasePage;
  bool get canInstall;
}

class WindowsRelease implements AppRelease {
  const WindowsRelease(this.tag, {required this.hasZip, this.zipSha256});

  @override
  final String tag;
  final bool hasZip;
  final String? zipSha256;

  @override
  bool get canInstall =>
      hasZip &&
      tag.startsWith('v') &&
      _versionPattern.hasMatch(tag.substring(1)) &&
      _sha256Pattern.hasMatch('sha256:$zipSha256');

  static String zipName(String tag) => 'meme-searcher-$tag-windows-x64.zip';

  @override
  Uri get releasePage =>
      Uri.https('github.com', '/$_repository/releases/tag/$tag');

  Uri get url => Uri.https(
    'github.com',
    hasZip
        ? '/$_repository/releases/download/$tag/${zipName(tag)}'
        : '/$_repository/releases/tag/$tag',
  );
}

class AndroidRelease implements AppRelease {
  const AndroidRelease(this.tag, {required this.hasApk, this.apkSha256});

  @override
  final String tag;
  final bool hasApk;
  final String? apkSha256;

  @override
  bool get canInstall =>
      hasApk &&
      tag.startsWith('v') &&
      _versionPattern.hasMatch(tag.substring(1)) &&
      _sha256Pattern.hasMatch('sha256:$apkSha256');

  static String apkName(String tag) => 'meme-searcher-$tag-android.apk';

  @override
  Uri get releasePage =>
      Uri.https('github.com', '/$_repository/releases/tag/$tag');

  Uri get url => Uri.https(
    'github.com',
    hasApk
        ? '/$_repository/releases/download/$tag/${apkName(tag)}'
        : '/$_repository/releases/tag/$tag',
  );
}

List<int> _versionParts(String version) {
  if (!_versionPattern.hasMatch(version)) {
    throw const FormatException('Expected a four-part app version.');
  }
  return version.split('.').map(int.parse).toList();
}

/// Compares four-part application versions numerically.
int compareAppVersions(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  for (var i = 0; i < leftParts.length; i++) {
    final comparison = leftParts[i].compareTo(rightParts[i]);
    if (comparison != 0) return comparison;
  }
  return 0;
}

class _PublishedRelease {
  const _PublishedRelease(this.tag, this.assets);

  final String tag;
  final List<Map> assets;

  Map? asset(String name) => assets
      .where((asset) => asset['name'] == name && asset['state'] == 'uploaded')
      .firstOrNull;
}

Future<_PublishedRelease?> _checkLatestStableRelease(
  String installedVersion,
  http.Client transport,
) async {
  _versionParts(installedVersion);
  final uri = Uri.https(
    'api.github.com',
    '/repos/$_repository/releases/latest',
  );
  final response = await transport
      .get(
        uri,
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Meme-Snatcher/$installedVersion',
        },
      )
      .timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    throw HttpException('GitHub returned ${response.statusCode}', uri: uri);
  }
  final data = jsonDecode(utf8.decode(response.bodyBytes));
  if (data is! Map<String, dynamic> ||
      data['draft'] != false ||
      data['prerelease'] != false ||
      data['tag_name'] is! String) {
    throw const FormatException('Expected a published stable release.');
  }
  final tag = data['tag_name'] as String;
  if (!tag.startsWith('v')) {
    throw const FormatException('Invalid release tag.');
  }
  final latestVersion = tag.substring(1);
  if (compareAppVersions(latestVersion, installedVersion) <= 0) return null;
  final assets = data['assets'];
  return _PublishedRelease(
    tag,
    assets is List ? assets.whereType<Map>().toList() : const [],
  );
}

Future<WindowsRelease?> checkForAppUpdate(
  String installedVersion, {
  http.Client? client,
}) async {
  final transport = client ?? http.Client();
  try {
    final published = await _checkLatestStableRelease(
      installedVersion,
      transport,
    );
    if (published == null) return null;
    final zip = published.asset(WindowsRelease.zipName(published.tag));
    final digest = zip?['digest'];
    return WindowsRelease(
      published.tag,
      hasZip: zip != null,
      zipSha256: digest is String
          ? _sha256Pattern.firstMatch(digest)?.group(1)
          : null,
    );
  } finally {
    if (client == null) transport.close();
  }
}

/// Looks up the latest stable Android package.  A release without a matching
/// checksum remains useful as a browser fallback, but is never installable in
/// the app.
Future<AndroidRelease?> checkForAndroidAppUpdate(
  String installedVersion, {
  http.Client? client,
}) async {
  final transport = client ?? http.Client();
  try {
    final published = await _checkLatestStableRelease(
      installedVersion,
      transport,
    );
    if (published == null) return null;
    final apk = published.asset(AndroidRelease.apkName(published.tag));
    final sums = published.asset('SHA256SUMS.txt');
    final checksum = apk != null && sums != null
        ? await _readAndroidChecksum(transport, published.tag)
        : null;
    final digest = apk?['digest'];
    final publishedDigest = digest is String
        ? _publishedSha256Pattern.firstMatch(digest)?.group(1)?.toLowerCase()
        : null;
    return AndroidRelease(
      published.tag,
      hasApk: apk != null,
      apkSha256: publishedDigest == null || publishedDigest == checksum
          ? checksum
          : null,
    );
  } finally {
    if (client == null) transport.close();
  }
}

Future<String?> _readAndroidChecksum(http.Client client, String tag) async {
  final uri = Uri.https(
    'github.com',
    '/$_repository/releases/download/$tag/SHA256SUMS.txt',
  );
  try {
    final response = await client
        .get(uri, headers: {'User-Agent': 'Meme-Snatcher'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 || response.bodyBytes.length > 1024 * 1024) {
      return null;
    }
    final name = RegExp.escape(AndroidRelease.apkName(tag));
    final matches = RegExp(
      '^([a-fA-F0-9]{64})\\s+\\*?$name\\s*'
      r'$',
      multiLine: true,
    ).allMatches(utf8.decode(response.bodyBytes));
    if (matches.length != 1) return null;
    return matches.single.group(1)?.toLowerCase();
  } on SocketException {
    return null;
  } on TimeoutException {
    return null;
  } on http.ClientException {
    return null;
  } on FormatException {
    return null;
  }
}
