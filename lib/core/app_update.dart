import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _repository = 'JJHbrams/meme-searcher';
final _versionPattern = RegExp(r'^\d+\.\d+\.\d+\.\d+$');

class WindowsRelease {
  const WindowsRelease(this.tag, {required this.hasZip});

  final String tag;
  final bool hasZip;

  static String zipName(String tag) => 'meme-searcher-$tag-windows-x64.zip';

  Uri get url => Uri.https(
    'github.com',
    hasZip
        ? '/$_repository/releases/download/$tag/${zipName(tag)}'
        : '/$_repository/releases/tag/$tag',
  );
}

List<int> _versionParts(String version) {
  if (!_versionPattern.hasMatch(version)) {
    throw const FormatException('Expected a four-part Windows version.');
  }
  return version.split('.').map(int.parse).toList();
}

Future<WindowsRelease?> checkForAppUpdate(
  String installedVersion, {
  http.Client? client,
}) async {
  final installed = _versionParts(installedVersion);
  final uri = Uri.https(
    'api.github.com',
    '/repos/$_repository/releases/latest',
  );
  final transport = client ?? http.Client();
  try {
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
    final latest = _versionParts(tag.substring(1));
    for (var i = 0; i < installed.length; i++) {
      if (latest[i] < installed[i]) return null;
      if (latest[i] > installed[i]) {
        final assets = data['assets'];
        final hasZip =
            assets is List &&
            assets.any(
              (asset) =>
                  asset is Map &&
                  asset['name'] == WindowsRelease.zipName(tag) &&
                  asset['state'] == 'uploaded',
            );
        return WindowsRelease(tag, hasZip: hasZip);
      }
    }
    return null;
  } finally {
    if (client == null) transport.close();
  }
}
