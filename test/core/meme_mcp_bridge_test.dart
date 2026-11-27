import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:meme_searcher/core/device_app_services.dart';
import 'package:meme_searcher/core/local_library_store.dart';
import 'package:meme_searcher/core/meme_mcp_bridge.dart';
import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/core/safe_media_downloader.dart';
import 'package:meme_searcher/core/web_collectors.dart';
import 'package:path/path.dart' as p;

const _generic = 'https://example.test/generic.png';
const _scene = 'https://example.test/starleague.png';
const _gif = 'https://example.test/whoopah.gif';
const _correction = '스타리그 마인 심어놓고 아 망했어요';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late List<String> searches;
  late Map<String, Uint8List> files;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('meme-mcp-test-');
    searches = [];
    files = {
      _generic: await File('assets/seed-assets/kejang-coming-ruliweb.png')
          .readAsBytes(),
      _scene: await File('assets/seed-assets/helldivers-coming-arca.png')
          .readAsBytes(),
      _gif: await File('assets/seed-assets/approved-knuckles-tenor.gif')
          .readAsBytes(),
    };
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<DeviceAppServices> app() async {
    final naver = NaverImageCollector(
      client: MockClient((request) async {
        expect(request.url.host, 'search.naver.com');
        searches.add(request.url.queryParameters['query']!);
        return http.Response(
          jsonEncode([
            {'originalUrl': _generic, 'title': '그냥 망했어요 리액션'},
            {'originalUrl': _scene, 'title': _correction},
            {'originalUrl': _gif, 'title': 'Whoopah Chandler Friends GIF'},
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    return DeviceAppServices(
      store: await LocalLibraryStore.open(directory: root),
      downloader: _FixtureDownloader(files),
      naverSearch: naver.call,
      googleSearch: (_, _) async => [],
    );
  }

  test(
    'stdio web recommendation and feedback persist into direct app search',
    () async {
      final first = await app();
      final bridge = await MemeMcpBridge.start(first);
      addTearDown(bridge.close);
      final drawer = await first.mcpDrawerDirectory();
      final client = await _McpClient.start(drawer);
      addTearDown(client.close);

      final startup = await client.rpc('initialize', {
        'protocolVersion': '2025-11-25',
      });
      expect(startup['protocolVersion'], '2025-11-25');
      final tools = await client.rpc('tools/list', {});
      expect((tools['tools'] as List).map((entry) => entry['name']), [
        'find_reaction_meme',
        'record_meme_feedback',
      ]);

      final local = await client.search(
        'approval',
        scope: 'auto',
        format: 'gif',
      );
      expect(local['status'], 'ok');
      expect(local['matches'][0]['source'], 'bundled');
      expect(
        searches,
        isEmpty,
        reason: 'auto leaves a good local result offline',
      );
      final formal = await client.search('망했어요', scope: 'web', tone: 'formal');
      expect(formal['status'], 'inappropriate');
      expect(searches, isEmpty);

      final original = await client.search(
        '망했어요',
        scope: 'auto',
        format: 'image',
      );
      expect(original['status'], 'ok');
      final matches = original['matches'] as List;
      expect(matches, hasLength(2));
      expect(matches[0]['source'], 'app_web');
      expect(matches[0]['title'], '그냥 망했어요 리액션');
      expect(matches[0]['markdown'], endsWith('.png)'));
      final sceneId = matches[1]['recommendation_id'] as String;
      final genericId = matches[0]['recommendation_id'] as String;
      expect(searches, ['망했어요 짤']);

      const direct = SearchRequest(
        query: '망했어요',
        filter: MediaFilter.staticImage,
      );
      expect((await client.feedback(sceneId, 'helpful'))['status'], 'saved');
      expect((await first.search(direct)).assets.first.originalUrl, _scene);
      expect((await client.feedback(sceneId, 'wrong'))['status'], 'saved');
      expect((await first.search(direct)).assets.first.originalUrl, _generic);
      expect(
        (await client.feedback('made-up', 'helpful'))['status'],
        'unknown_recommendation',
      );
      expect(
        (await client.feedback(
          genericId,
          'correction',
          correction: _correction,
          alias: '망했어요',
        ))['status'],
        'saved',
      );

      final gif = await client.search(
        'whoopah chandler',
        scope: 'web',
        format: 'gif',
      );
      expect(gif['status'], 'ok');
      expect(gif['matches'][0]['source'], 'app_web');
      expect(gif['matches'][0]['mimeType'], 'image/gif');
      expect(gif['matches'][0]['markdown'], endsWith('.gif)'));

      await client.close();
      await bridge.close();
      final restarted = await app();
      final after = await restarted.search(direct);
      expect(searches.last, '$_correction 짤');
      expect(after.assets.first.originalUrl, _scene);
      expect(
        after.assets.any((asset) => asset.originalUrl == _generic),
        isFalse,
      );
      expect(after.assets.first.submittedQuery, '망했어요');
      expect(after.scope, SearchScope.all);
    },
  );

  test('invalid loopback requests do not invoke a provider', () async {
    final instance = await app();
    final bridge = await MemeMcpBridge.start(instance);
    addTearDown(bridge.close);
    final drawer = await instance.mcpDrawerDirectory();
    final config = jsonDecode(
      await File(p.join(drawer.path, MemeMcpBridge.discoveryFileName))
          .readAsString(),
    ) as Map;
    final uri = Uri.parse('http://127.0.0.1:${config['port']}/v1/search');
    final loopback = IOClient(_LoopbackHttp().createHttpClient(null));
    addTearDown(loopback.close);
    final body = jsonEncode({
      'query': '망했어요',
      'tone': 'requested',
      'scope': 'web',
    });
    final unauthorized = await loopback.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    expect(unauthorized.statusCode, HttpStatus.forbidden);
    final browserHeaders = {
      'content-type': 'application/json',
      'authorization': 'Bearer ${config['token']}',
      'origin': 'http://other.test',
    };
    expect(
      (await loopback.post(
        uri,
        headers: browserHeaders,
        body: body,
      )).statusCode,
      HttpStatus.forbidden,
    );
    browserHeaders.remove('origin');
    expect(
      (await loopback.post(
        uri,
        headers: browserHeaders,
        body: jsonEncode({'scope': 'wrong'}),
      )).statusCode,
      HttpStatus.badRequest,
    );
    expect(searches, isEmpty);
  });

  test(
    'standalone MCP keeps local GIF access when the app is closed',
    () async {
      final client = await _McpClient.start(root);
      addTearDown(client.close);
      final local = await client.search(
        'approval',
        scope: 'local',
        format: 'gif',
      );
      expect(local['status'], 'ok');
      expect(local['matches'][0]['mimeType'], 'image/gif');
      expect(local['matches'][0], isNot(contains('recommendation_id')));
      expect(
        (await client.search('approval', scope: 'web'))['status'],
        'app_required',
      );
      expect(
        (await client.feedback('old-id', 'helpful'))['status'],
        'app_required',
      );
    },
  );
}

class _LoopbackHttp extends HttpOverrides {}

class _FixtureDownloader extends SafeMediaDownloader {
  _FixtureDownloader(this.files);
  final Map<String, Uint8List> files;

  @override
  Future<Uint8List> download(String value) async => files[value]!;
}

class _McpClient {
  _McpClient(this._process)
    : _lines = StreamIterator(
        _process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );

  final Process _process;
  final StreamIterator<String> _lines;
  var _id = 0;
  bool _closed = false;

  static Future<_McpClient> start(Directory drawer) async => _McpClient(
    await Process.start('node', [
      'tools/meme-snatcher-mcp.mjs',
      '--drawer',
      drawer.path,
    ]),
  );

  Future<Map<String, dynamic>> rpc(
    String method,
    Map<String, Object?> params,
  ) async {
    final id = ++_id;
    _process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    await _process.stdin.flush();
    expect(
      await _lines.moveNext().timeout(const Duration(seconds: 15)),
      isTrue,
    );
    final envelope = jsonDecode(_lines.current) as Map<String, dynamic>;
    expect(envelope['id'], id);
    return envelope['result'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> search(
    String query, {
    required String scope,
    String tone = 'requested',
    String format = 'any',
  }) => _call('find_reaction_meme', {
    'query': query,
    'scope': scope,
    'tone': tone,
    'format': format,
  });

  Future<Map<String, dynamic>> feedback(
    String id,
    String feedback, {
    String? correction,
    String? alias,
  }) => _call('record_meme_feedback', {
    'recommendation_id': id,
    'feedback': feedback,
    'correction': ?correction,
    'alias': ?alias,
  });

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final response = await rpc('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    return response['structuredContent'] as Map<String, dynamic>;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _process.stdin.close();
    await _lines.cancel();
    await _process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _process.kill();
        return -1;
      },
    );
  }
}
