import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'query_plan.dart';

const _mcpProtocolVersion = '2025-06-18';
const _maxProviderResults = 32;

/// Collects Google Images through SerpApi's stateful, official MCP endpoint.
class SerpApiMcpCollector {
  SerpApiMcpCollector({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  static final Uri endpoint = Uri.parse('https://mcp.serpapi.com/mcp');
  String? _sessionId;

  Future<List<MemeAsset>> call(QueryPlan plan, String apiKey) async {
    final baseHeaders = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json, text/event-stream',
      'MCP-Protocol-Version': _mcpProtocolVersion,
    };
    final initialize = await _rpc(
      baseHeaders,
      1,
      'initialize',
      <String, dynamic>{
        'protocolVersion': _mcpProtocolVersion,
        'capabilities': <String, dynamic>{},
        'clientInfo': <String, dynamic>{
          'name': 'meme-drawer',
          'version': '1.0',
        },
      },
    );
    final protocol = initialize['protocolVersion'] is String
        ? initialize['protocolVersion'] as String
        : _mcpProtocolVersion;

    // Initialization notifications must remain unauthenticated.
    await _post(baseHeaders, <String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
      'params': <String, dynamic>{},
    });

    final authHeaders = Map<String, String>.from(baseHeaders)
      ..['authorization'] = 'Bearer $apiKey';
    final params = <String, dynamic>{
      'engine': 'google_images',
      'q': plan.providerQuery,
      'gl': _countryFor(plan),
      'hl': _languageFor(plan),
      if (plan.filter == MediaFilter.gif) 'tbs': 'ift:gif',
    };
    final result = await _rpc(authHeaders, 2, 'tools/call', <String, dynamic>{
      'name': 'search',
      'arguments': <String, dynamic>{'params': params, 'mode': 'complete'},
      '_meta': <String, dynamic>{'protocolVersion': protocol},
    });
    return _assetsFromMcp(result);
  }

  Future<Map<String, dynamic>> _rpc(
    Map<String, String> headers,
    int id,
    String method,
    Map<String, dynamic> params,
  ) async {
    final response = await _post(headers, <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    final decoded = _decodeRpc(response.body);
    if (decoded['error'] != null) {
      throw StateError('SerpApi MCP request failed');
    }
    final result = decoded['result'];
    if (result is! Map) {
      throw const FormatException('Invalid SerpApi MCP response');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<http.Response> _post(
    Map<String, String> headers,
    Map<String, dynamic> request,
  ) async {
    final requestHeaders = Map<String, String>.from(headers);
    final session = _sessionId;
    if (session != null && session.isNotEmpty) {
      requestHeaders['Mcp-Session-Id'] = session;
    }
    late http.Response response;
    try {
      response = await _client
          .post(endpoint, headers: requestHeaders, body: jsonEncode(request))
          .timeout(const Duration(seconds: 20));
    } on SocketException {
      throw StateError('SerpApi MCP connection failed');
    } on HttpException {
      throw StateError('SerpApi MCP connection failed');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('SerpApi MCP request failed');
    }
    final nextSession = response.headers['mcp-session-id'];
    if (nextSession != null && nextSession.isNotEmpty) _sessionId = nextSession;
    return response;
  }

  Map<String, dynamic> _decodeRpc(String body) {
    final clean = body.trim();
    if (clean.isEmpty) throw const FormatException('Invalid MCP response');
    if (clean.startsWith('{')) return _jsonMap(clean);
    Map<String, dynamic>? last;
    for (final rawLine in clean.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trimLeft();
      if (!line.startsWith('data:')) continue;
      try {
        last = _jsonMap(line.substring(5).trim());
      } on FormatException {
        // Ignore malformed intermediate SSE events; retain the last valid event.
      }
    }
    if (last == null) throw const FormatException('Invalid MCP response');
    return last;
  }

  Map<String, dynamic> _jsonMap(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) throw const FormatException('Invalid MCP response');
    return Map<String, dynamic>.from(decoded);
  }

  List<MemeAsset> _assetsFromMcp(Map<String, dynamic> result) {
    if (result['isError'] == true) throw StateError('SerpApi search failed');
    dynamic payload = _structuredPayload(result['structuredContent']);
    payload ??= _contentPayload(result['content']);
    if (payload is Map && payload['error'] != null) {
      throw StateError('SerpApi search failed');
    }
    if (payload is! Map) return const [];
    final images = payload['images_results'] ?? payload['imagesResults'];
    if (images is! List) return const [];
    final seen = <String>{};
    final assets = <MemeAsset>[];
    for (final item in images) {
      if (item is! Map || assets.length >= _maxProviderResults) continue;
      final asset = _fromGoogle(
        Map<String, dynamic>.from(item),
        assets.length + 1,
      );
      if (asset == null || !seen.add(asset.originalUrl!)) continue;
      assets.add(asset);
    }
    return assets;
  }

  dynamic _structuredPayload(dynamic structured) {
    dynamic value;
    if (structured is Map) {
      value = structured['result'] ?? structured;
    } else if (structured is String) {
      value = structured;
    }
    if (value is String) {
      try {
        return jsonDecode(value);
      } on FormatException {
        return null;
      }
    }
    return value;
  }

  dynamic _contentPayload(dynamic content) {
    if (content is! List) return null;
    for (final item in content) {
      if (item is! Map || item['text'] is! String) continue;
      try {
        return jsonDecode(item['text'] as String);
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  MemeAsset? _fromGoogle(Map<String, dynamic> item, int rank) {
    final original = safePublicUrl(
      _string(item['original']) ?? _string(item['original_image']),
    );
    if (original == null) return null;
    final preview = safePublicUrl(_string(item['thumbnail']));
    final source = safePublicUrl(_string(item['link']));
    final title = cleanText(_string(item['title'])) ?? 'Google 이미지';
    final format = (_string(item['format']) ?? _formatFromUrl(original))
        ?.toUpperCase();
    return MemeAsset(
      id: 'web-google-${original.hashCode}',
      title: title,
      origin: 'web',
      originalUrl: original,
      previewUrl: preview,
      sourceUrl: source,
      formatHint: format,
      engines: const ['google'],
      providerRanks: {'google': rank},
      originalProviderRank: rank,
      animated: format == 'GIF',
    );
  }
}

/// Collects image metadata embedded in Naver image search documents.
class NaverImageCollector {
  NaverImageCollector({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;

  Future<List<MemeAsset>> call(QueryPlan plan) async {
    final uri = Uri.https('search.naver.com', '/search.naver', <String, String>{
      'where': 'image',
      'query': plan.providerQuery,
    });
    final response = await _client
        .get(uri, headers: const {'user-agent': 'Mozilla/5.0'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Naver image search failed');
    }
    return _assetsFromHtml(response.body, plan);
  }

  List<MemeAsset> _assetsFromHtml(String html, QueryPlan plan) {
    final seen = <String>{};
    final assets = <MemeAsset>[];
    var providerRank = 0;
    for (final item in _objectsWithOriginalUrl(html)) {
      if (assets.length >= _maxProviderResults) break;
      final original = safePublicUrl(_string(item['originalUrl']));
      if (original == null || !seen.add(original)) continue;
      final source = safePublicUrl(_string(item['link']));
      final preview =
          safePublicUrl(_string(item['viewerThumb'])) ??
          safePublicUrl(_string(item['thumb332'])) ??
          safePublicUrl(_string(item['thumb280']));
      final title =
          cleanText(_string(item['title'])) ??
          cleanText(_string(item['writerTitle'])) ??
          '웹 이미지';
      final hint = (_string(item['iconInfo']) ?? _formatFromUrl(original))
          ?.toUpperCase();
      final rank = ++providerRank;
      final asset = MemeAsset(
        id: 'web-naver-${original.hashCode}',
        title: title,
        origin: 'web',
        originalUrl: original,
        previewUrl: preview,
        sourceUrl: source,
        formatHint: hint,
        engines: const ['naver'],
        providerRanks: {'naver': rank},
        originalProviderRank: rank,
        animated: hint == 'GIF',
      );
      if (!_matchesConcept(asset, plan)) continue;
      assets.add(asset);
    }
    return assets;
  }

  Iterable<Map<String, dynamic>> _objectsWithOriginalUrl(String value) sync* {
    final key = RegExp(r'"originalUrl"\s*:');
    for (final match in key.allMatches(value)) {
      final object = _objectAt(value, match.start);
      if (object == null) continue;
      try {
        final decoded = jsonDecode(object);
        if (decoded is Map) yield Map<String, dynamic>.from(decoded);
      } on FormatException {
        continue;
      }
    }
  }

  String? _objectAt(String value, int keyOffset) {
    final start = value.lastIndexOf('{', keyOffset);
    if (start < 0) return null;
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (var index = start; index < value.length; index++) {
      final char = value[index];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          quoted = false;
        }
        continue;
      }
      if (char == '"') {
        quoted = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}' && --depth == 0) {
        return value.substring(start, index + 1);
      }
    }
    return null;
  }
}

bool _matchesConcept(MemeAsset asset, QueryPlan plan) {
  final text = compactMemeText(
    '${asset.title} ${asset.sourceUrl ?? ''} ${asset.originalUrl ?? ''}',
  );
  final core = plan.coreTerms
      .map(compactMemeText)
      .where((term) => term.isNotEmpty);
  final context = plan.contextTerms
      .map(compactMemeText)
      .where((term) => term.isNotEmpty);
  final required = plan.requiredContext
      .map(compactMemeText)
      .where((term) => term.isNotEmpty);
  final tags = plan.tagTerms
      .map(compactMemeText)
      .where((term) => term.isNotEmpty);
  if (tags.isNotEmpty && !tags.any(text.contains)) return false;
  if (required.isNotEmpty && !required.every(text.contains)) return false;
  if (core.isNotEmpty) return core.any(text.contains);
  return context.isEmpty || context.any(text.contains);
}

String? safePublicUrl(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  final address = InternetAddress.tryParse(uri.host);
  if (address != null && !_isPublicAddress(address)) return null;
  return uri.toString();
}

bool _isPublicAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    final first = bytes[0];
    final second = bytes[1];
    if (first == 0 || first == 10 || first == 127 || first >= 224) return false;
    if (first == 169 && second == 254) return false;
    if (first == 172 && second >= 16 && second <= 31) return false;
    if (first == 192 && second == 168) return false;
    if (first == 100 && second >= 64 && second <= 127) return false;
  } else if (bytes.isNotEmpty && (bytes[0] & 0xfe) == 0xfc) {
    return false;
  }
  return true;
}

String? cleanText(String? value) {
  if (value == null) return null;
  final text = value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.isEmpty ? null : text;
}

String? _string(dynamic value) => value is String ? value : null;

String? _formatFromUrl(String value) {
  final path = Uri.tryParse(value)?.path.toLowerCase() ?? '';
  return RegExp(r'\.([a-z0-9]{2,5})$').firstMatch(path)?.group(1);
}

String _countryFor(QueryPlan plan) =>
    RegExp(r'[가-힣]').hasMatch(plan.words) ? 'kr' : 'us';
String _languageFor(QueryPlan plan) =>
    RegExp(r'[가-힣]').hasMatch(plan.words) ? 'ko' : 'en';
