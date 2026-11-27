import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:meme_searcher/core/models.dart';
import 'package:meme_searcher/core/query_plan.dart';
import 'package:meme_searcher/core/web_collectors.dart';

QueryPlan plan({
  MediaFilter filter = MediaFilter.all,
  String words = 'approved',
  List<String> coreTerms = const [],
  List<String> contextTerms = const [],
  List<String> requiredContext = const [],
  List<String> tagTerms = const [],
  int? googleRecentDays,
}) => QueryPlan(
  original: words,
  words: words,
  rawTags: const [],
  tagTerms: tagTerms,
  tagIds: const [],
  expandedAliases: const [],
  coreTerms: coreTerms,
  contextTerms: contextTerms,
  requiredContext: requiredContext,
  providerQuery: words,
  filter: filter,
  similar: false,
  googleRecentDays: googleRecentDays,
);

http.Response rpc(
  Map<String, dynamic> result, {
  Map<String, String>? headers,
}) => http.Response(
  jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}),
  200,
  headers: headers ?? const {},
);

void main() {
  group('SerpApiMcpCollector', () {
    test(
      'uses the official stateful MCP sequence and GIF parameters',
      () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          switch (body['method']) {
            case 'initialize':
              return rpc(
                {'protocolVersion': '2025-06-18'},
                headers: {'mcp-session-id': 'session-1'},
              );
            case 'notifications/initialized':
              return http.Response('', 202);
            case 'tools/call':
              return rpc({
                'structuredContent': {
                  'result': {
                    'images_results': [
                      {
                        'original': 'https://images.example/approved.gif',
                        'thumbnail': 'https://thumb.example/a.gif',
                        'link': 'https://source.example/a',
                        'title': 'Approved',
                        'format': 'GIF',
                      },
                    ],
                  },
                },
              });
          }
          return http.Response('{}', 400);
        });
        final results = await SerpApiMcpCollector(client: client)
            .call(plan(filter: MediaFilter.gif), 'secret');
        expect(results.single.title, 'Approved');
        expect(results.single.isGif, isTrue);
        expect(requests, hasLength(3));
        expect(requests[0].headers['authorization'], isNull);
        expect(requests[0].headers['mcp-protocol-version'], '2025-06-18');
        expect(requests[1].headers['authorization'], isNull);
        expect(requests[1].headers['mcp-session-id'], 'session-1');
        expect(requests[2].headers['authorization'], 'Bearer secret');
        expect(requests[2].headers['mcp-session-id'], 'session-1');
        final arguments =
            (jsonDecode(requests[2].body) as Map)['params']['arguments'] as Map;
        expect(arguments['mode'], 'complete');
        expect(arguments['params'], containsPair('engine', 'google_images'));
        expect(arguments['params'], containsPair('tbs', 'ift:gif'));
        expect(arguments['params'], containsPair('gl', 'us'));
        expect(arguments['params'], isNot(contains('period_unit')));
      },
    );

    test(
      'uses one Google Images search with a date window and GIF filter',
      () async {
        final searches = <Map>[];
        final client = MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          switch (body['method']) {
            case 'initialize':
              return rpc({'protocolVersion': '2025-06-18'});
            case 'notifications/initialized':
              return http.Response('', 202);
            case 'tools/call':
              searches.add(body['params']['arguments']['params'] as Map);
              return rpc({
                'structuredContent': {
                  'result': {'images_results': []},
                },
              });
            default:
              return http.Response('{}', 400);
          }
        });
        await SerpApiMcpCollector(client: client).call(
          plan(
            words: 'Elon Musk meme',
            filter: MediaFilter.gif,
            googleRecentDays: 30,
          ),
          'secret',
        );
        expect(searches, hasLength(1));
        expect(searches.single, containsPair('period_unit', 'd'));
        expect(searches.single, containsPair('period_value', 30));
        expect(searches.single, containsPair('tbs', 'ift:gif'));
      },
    );

    test('accepts structured string and final valid SSE data', () async {
      var step = 0;
      final client = MockClient((request) async {
        step++;
        if (step == 1) return rpc({'protocolVersion': '2025-06-18'});
        if (step == 2) return http.Response('', 202);
        final first = jsonEncode({
          'jsonrpc': '2.0',
          'result': {
            'structuredContent': {
              'result': jsonEncode({'images_results': []}),
            },
          },
        });
        final finalData = jsonEncode({
          'jsonrpc': '2.0',
          'result': {
            'structuredContent': {
              'result': jsonEncode({
                'images_results': [
                  {'original': 'https://cdn.example/a.png', 'title': 'final'},
                ],
              }),
            },
          },
        });
        return http.Response(
          'data: not-json\n\ndata: $first\n\ndata: $finalData\n',
          200,
        );
      });
      final result = await SerpApiMcpCollector(client: client)
          .call(plan(), 'secret');
      expect(result.single.title, 'final');
    });

    test('rejects protocol, provider and unsafe-original failures', () async {
      Future<void> expectFailure(http.Response Function(int) reply) async {
        var step = 0;
        final client = MockClient((_) async => reply(++step));
        await expectLater(
          SerpApiMcpCollector(client: client).call(plan(), 'secret'),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
        );
      }

      await expectFailure(
        (_) => http.Response('{"jsonrpc":"2.0","error":{"message":"no"}}', 200),
      );
      await expectFailure(
        (step) => step == 1
            ? rpc({'protocolVersion': '2025-06-18'})
            : step == 2
            ? http.Response('', 202)
            : rpc({'isError': true}),
      );
      await expectFailure(
        (step) => step == 1
            ? rpc({'protocolVersion': '2025-06-18'})
            : step == 2
            ? http.Response('', 202)
            : http.Response('not-json', 200),
      );

      var step = 0;
      final client = MockClient((_) async {
        step++;
        if (step == 1) return rpc({'protocolVersion': '2025-06-18'});
        if (step == 2) return http.Response('', 202);
        return rpc({
          'structuredContent': {
            'result': {
              'images_results': [
                {'original': 'http://127.0.0.1/a.gif'},
                {'original': 'https://user:pass@safe.example/a.gif'},
                {'original': 'https://safe.example/good.gif'},
              ],
            },
          },
        });
      });
      final results = await SerpApiMcpCollector(client: client)
          .call(plan(), 'secret');
      expect(results.map((asset) => asset.originalUrl), [
        'https://safe.example/good.gif',
      ]);
    });
  });

  test(
    'Naver keeps neighboring object metadata associated with each original URL',
    () async {
      const html = r'''
      junk {"originalUrl":"https:\/\/cdn.example\/first.gif","link":"https:\/\/source.example\/one","viewerThumb":"https:\/\/thumb.example\/one.jpg","title":"<b>First &amp; Meme</b>","iconInfo":"GIF"}
      {"originalUrl":"https:\/\/cdn.example\/second.png","link":"https:\/\/source.example\/two","viewerThumb":"https:\/\/thumb.example\/two.jpg","title":"Second title","iconInfo":"PNG"}
      {"originalUrl":"http:\/\/127.0.0.1\/blocked.png","title":"Blocked"}
    ''';
      final results = await NaverImageCollector(
        client: MockClient((_) async => http.Response(html, 200)),
      ).call(plan(words: '틀깨기'));
      expect(results, hasLength(2));
      expect(results[0].title, 'First & Meme');
      expect(results[0].originalUrl, 'https://cdn.example/first.gif');
      expect(results[0].previewUrl, 'https://thumb.example/one.jpg');
      expect(results[0].sourceUrl, 'https://source.example/one');
      expect(results[0].isGif, isTrue);
      expect(results[1].title, 'Second title');
      expect(results[1].originalUrl, 'https://cdn.example/second.png');
    },
  );

  test(
    'Naver applies required context, core, and tag concept filters',
    () async {
      const html = r'''
      {"originalUrl":"https:\/\/cdn.example\/approved-stamp.gif","title":"Approved stamp","iconInfo":"GIF"}
      {"originalUrl":"https:\/\/cdn.example\/knuckles-approved.gif","title":"Knuckles approved","iconInfo":"GIF"}
      {"originalUrl":"https:\/\/cdn.example\/knuckles-tagless.gif","title":"Knuckles approved","link":"https:\/\/source.example\/plain","iconInfo":"GIF"}
      {"originalUrl":"https:\/\/cdn.example\/knuckles-tagged.gif","title":"Knuckles approved","link":"https:\/\/source.example\/sonic","iconInfo":"GIF"}
    ''';
      final collector = NaverImageCollector(
        client: MockClient((_) async => http.Response(html, 200)),
      );
      final required = await collector.call(
        plan(coreTerms: ['approved'], requiredContext: ['knuckles']),
      );
      expect(
        required.map((asset) => asset.title),
        everyElement(contains('Knuckles')),
      );

      final tagged = await collector.call(
        plan(
          coreTerms: ['approved'],
          requiredContext: ['knuckles'],
          tagTerms: ['sonic'],
        ),
      );
      expect(tagged, hasLength(1));
      expect(tagged.single.originalUrl, contains('tagged'));
    },
  );
}
