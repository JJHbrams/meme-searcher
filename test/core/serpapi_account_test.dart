import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meme_searcher/core/serpapi_account.dart';

void main() {
  test(
    'validates using the account endpoint without redirects or search',
    () async {
      final client = MockClient((request) async {
        expect(request.url.origin, 'https://serpapi.com');
        expect(request.url.path, '/account.json');
        expect(request.url.queryParameters['api_key'], 'test-key');
        expect(request.followRedirects, isFalse);
        return http.Response(
          '{"account_id":"test-account","total_searches_left":0}',
          200,
        );
      });
      await verifySerpApiKey('test-key', client: client);
    },
  );
  test(
    'rejects denied keys, redirects and invalid account responses',
    () async {
      for (final code in [200, 302, 401, 403, 429, 500]) {
        final client = MockClient(
          (_) async => http.Response('{"error":"sample-secret"}', code),
        );
        await expectLater(
          verifySerpApiKey('sample-secret', client: client),
          throwsA(
            isA<SerpApiSetupException>().having(
              (e) => e.message,
              'message',
              isNot(contains('sample-secret')),
            ),
          ),
        );
      }
    },
  );
}
