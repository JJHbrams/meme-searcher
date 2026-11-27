import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'device_app_services.dart';
import 'media_inspector.dart';
import 'meme_feedback_store.dart';
import 'models.dart';

/// Connects a same-user stdio MCP to the app's search and library owner.
class MemeMcpBridge {
  MemeMcpBridge._(this._app, this._server, this._discovery, this._token);

  static const discoveryFileName = 'mcp-connection.json';
  static const _maxBody = 4096;
  static const _maxRecommendations = 256;

  final DeviceAppServices _app;
  final HttpServer _server;
  final File _discovery;
  final String _token;
  final _recommendations = <String, _Recommendation>{};
  var _activeSearches = 0;

  static Future<MemeMcpBridge> start(DeviceAppServices app) async {
    final directory = await app.mcpDrawerDirectory();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final file = File(p.join(directory.path, discoveryFileName));
    final token = _randomToken(32);
    final temporary = File('${file.path}.${_randomToken(12)}.tmp');
    try {
      final bridge = MemeMcpBridge._(app, server, file, token);
      server.idleTimeout = const Duration(seconds: 5);
      server.listen((request) => unawaited(bridge._handle(request)));
      await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'port': server.port,
          'pid': pid,
          'token': token,
        }),
        flush: true,
      );
      await temporary.rename(file.path);
      return bridge;
    } catch (_) {
      await server.close(force: true);
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> close() async {
    await _server.close(force: true);
    try {
      final data = jsonDecode(await _discovery.readAsString());
      if (data is Map && data['token'] == _token) await _discovery.delete();
    } on FileSystemException {
      // A missing or stale discovery file cannot authorize a new connection.
    } on FormatException {
      // Leave an unrelated or corrupted discovery file intact.
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    response.headers.set('cache-control', 'no-store');
    try {
      if (request.connectionInfo?.remoteAddress.isLoopback != true ||
          request.headers.value(HttpHeaders.hostHeader) !=
              '127.0.0.1:${_server.port}' ||
          request.headers.value('origin') != null ||
          !_sameToken(request.headers.value(HttpHeaders.authorizationHeader))) {
        response.statusCode = HttpStatus.forbidden;
        response.write(jsonEncode({'status': 'forbidden'}));
        return;
      }
      if (request.method != 'POST' ||
          request.uri.hasQuery ||
          request.headers.contentType?.mimeType != 'application/json') {
        throw const FormatException('Invalid request.');
      }
      final body = await _readBody(request);
      if (request.uri.path == '/v1/search' && _activeSearches >= 2) {
        response.statusCode = HttpStatus.tooManyRequests;
        response.write(jsonEncode(_results('busy')));
        return;
      }
      final result = switch (request.uri.path) {
        '/v1/search' => await _runSearch(body),
        '/v1/feedback' => await _feedback(body),
        _ => throw const FormatException('Unknown route.'),
      };
      response.write(jsonEncode(result));
    } on FormatException {
      response.statusCode = HttpStatus.badRequest;
      response.write(jsonEncode({'status': 'invalid_request'}));
    } on TimeoutException {
      response.statusCode = HttpStatus.requestTimeout;
      response.write(jsonEncode({'status': 'timeout'}));
    } catch (_) {
      response.statusCode = HttpStatus.internalServerError;
      response.write(jsonEncode({'status': 'app_error'}));
    } finally {
      try {
        await response.close();
      } catch (_) {
        // The client can quit while the app is collecting web candidates.
      }
    }
  }

  Future<Map<String, dynamic>> _readBody(HttpRequest request) async {
    if (request.contentLength > _maxBody) {
      throw const FormatException('Request too large.');
    }
    final bytes = <int>[];
    await for (final chunk in request.timeout(const Duration(seconds: 3))) {
      if (bytes.length + chunk.length > _maxBody) {
        throw const FormatException('Request too large.');
      }
      bytes.addAll(chunk);
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object.');
    }
    return decoded;
  }

  Future<Map<String, Object?>> _runSearch(Map<String, dynamic> body) async {
    _activeSearches++;
    try {
      return await _search(body);
    } finally {
      _activeSearches--;
    }
  }

  Future<Map<String, Object?>> _search(Map<String, dynamic> body) async {
    final query = _text(body['query']);
    final tone = body['tone'];
    final scope = body['scope'];
    final filter = switch (body['format']) {
      'image' => MediaFilter.staticImage,
      'gif' => MediaFilter.gif,
      'any' || null => MediaFilter.all,
      _ => throw const FormatException('Unknown media format.'),
    };
    if (query == null ||
        !['casual', 'requested', 'formal', 'sensitive'].contains(tone) ||
        !['local', 'auto', 'web'].contains(scope)) {
      throw const FormatException('Search parameters are invalid.');
    }
    if (tone == 'formal' || tone == 'sensitive') {
      return _results('inappropriate');
    }

    if (scope != 'web') {
      final local = await _app.searchMcpLibrary(query, filter);
      final matches = await _attachments(
        query,
        filter,
        local.assets,
        web: false,
      );
      if (matches.isNotEmpty) return _results('ok', matches);
      if (scope == 'local') return _results('no_match');
    }
    final remote = await _app.search(
      SearchRequest(query: query, scope: SearchScope.web, filter: filter),
    );
    final matches = await _attachments(query, filter, remote.assets, web: true);
    if (matches.isNotEmpty) return _results('ok', matches);
    return _results(remote.hasError ? 'web_failed' : 'no_match');
  }

  Future<List<Map<String, Object?>>> _attachments(
    String query,
    MediaFilter filter,
    List<MemeAsset> assets, {
    required bool web,
  }) async {
    final candidates = assets.where((asset) => !asset.isPreviewOnly).take(6);
    final checked = await Future.wait(
      candidates.map((asset) async {
        try {
          final media = await _app
              .loadMedia(asset, allowDownload: web)
              .timeout(const Duration(seconds: 7));
          final signature = MediaInspector.signatureFormat(media.bytes);
          final mime = switch (signature) {
            'GIF' => 'image/gif',
            'PNG' => 'image/png',
            'JPEG' || 'JPG' => 'image/jpeg',
            'WEBP' => 'image/webp',
            _ => null,
          };
          final gif = signature == 'GIF';
          if (mime == null ||
              (filter == MediaFilter.gif && !gif) ||
              (filter == MediaFilter.staticImage && gif)) {
            return null;
          }
          return (asset: asset, file: media, mime: mime, gif: gif);
        } catch (_) {
          return null;
        }
      }),
    );

    final matches = <Map<String, Object?>>[];
    final files = <String>{};
    for (final candidate in checked.nonNulls) {
      if (!files.add(candidate.file.path)) continue;
      final id = _randomToken(18);
      if (_recommendations.length >= _maxRecommendations) {
        _recommendations.remove(_recommendations.keys.first);
      }
      _recommendations[id] = _Recommendation(query, candidate.asset);
      matches.add({
        'id': candidate.asset.id,
        'recommendation_id': id,
        'title': candidate.asset.title,
        'source': web
            ? 'app_web'
            : candidate.asset.favorite
            ? 'favorite'
            : 'bundled',
        'path': candidate.file.path,
        'mimeType': candidate.mime,
        'format': candidate.gif ? 'gif' : 'image',
        if (web && candidate.asset.sourceUrl != null)
          'source_url': candidate.asset.sourceUrl,
      });
      if (matches.length == 3) break;
    }
    return matches;
  }

  Future<Map<String, Object?>> _feedback(Map<String, dynamic> body) async {
    final id = _text(body['recommendation_id']);
    final recommendation = _recommendations[id];
    if (recommendation == null) return {'status': 'unknown_recommendation'};

    final kind = switch (body['feedback']) {
      'helpful' => MemeFeedbackKind.helpful,
      'wrong' => MemeFeedbackKind.wrong,
      'correction' => MemeFeedbackKind.correction,
      _ => throw const FormatException('Unknown feedback.'),
    };
    final correction = _text(body['correction']);
    final alias = _text(body['alias']);
    if ((kind == MemeFeedbackKind.correction && correction == null) ||
        (body['alias'] != null && alias == null) ||
        (kind != MemeFeedbackKind.correction &&
            (body['correction'] != null || body['alias'] != null))) {
      throw const FormatException('Invalid feedback details.');
    }
    await _app.recordMemeFeedback(
      query: recommendation.query,
      asset: recommendation.asset,
      kind: kind,
      correction: correction,
      alias: alias,
    );
    return {'status': 'saved'};
  }

  bool _sameToken(String? authorization) {
    final expected = 'Bearer $_token';
    if (authorization == null || authorization.length != expected.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < expected.length; index++) {
      difference |=
          expected.codeUnitAt(index) ^ authorization.codeUnitAt(index);
    }
    return difference == 0;
  }

  static String? _text(Object? value) {
    if (value is! String || value.trim().isEmpty || value.length > 160) {
      return null;
    }
    return value.trim();
  }

  static Map<String, Object?> _results(
    String status, [
    List<Map<String, Object?>> matches = const [],
  ]) => {'status': status, 'matches': matches};

  static String _randomToken(int length) {
    final random = Random.secure();
    return base64Url
        .encode(List.generate(length, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}

class _Recommendation {
  const _Recommendation(this.query, this.asset);

  final String query;
  final MemeAsset asset;
}
