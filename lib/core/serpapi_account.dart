import 'dart:convert';

import 'package:http/http.dart' as http;

class SerpApiSetupException implements Exception {
  const SerpApiSetupException(this.message);
  final String message;
}

/// Only quota counters leave the account client. The response also contains
/// the private API key and the account owner's email.
class SerpApiQuota {
  const SerpApiQuota({
    this.monthlyLimit,
    this.monthlyRemaining,
    this.totalRemaining,
    this.extraCredits,
  });

  final int? monthlyLimit;
  final int? monthlyRemaining;
  final int? totalRemaining;
  final int? extraCredits;

  factory SerpApiQuota.fromAccount(Map<String, dynamic> account) {
    int? count(String field) {
      final value = account[field];
      return value is int && value >= 0 ? value : null;
    }

    return SerpApiQuota(
      monthlyLimit: count('searches_per_month'),
      monthlyRemaining: count('plan_searches_left'),
      totalRemaining: count('total_searches_left'),
      extraCredits: count('extra_credits'),
    );
  }
}

Future<void> verifySerpApiKey(String key, {http.Client? client}) async {
  await fetchSerpApiQuota(key, client: client);
}

/// The account endpoint verifies ownership without consuming a search.
Future<SerpApiQuota> fetchSerpApiQuota(
  String key, {
  http.Client? client,
}) async {
  final transport = client ?? http.Client();
  try {
    final request = http.Request(
      'GET',
      Uri.https('serpapi.com', '/account.json', {'api_key': key}),
    )..followRedirects = false;
    final response = await transport
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 400 ||
        response.statusCode == 401 ||
        response.statusCode == 403) {
      throw const SerpApiSetupException(
        'SerpApi가 키를 승인하지 않았어요. 계정에서 키를 다시 복사해 주세요.',
      );
    }
    if (response.statusCode == 429) {
      throw const SerpApiSetupException(
        'SerpApi 요청이 잠시 제한됐어요. 잠시 후 다시 연결해 주세요.',
      );
    }
    if (response.statusCode == 200) {
      final account = jsonDecode(response.body);
      if (account is Map<String, dynamic> &&
          account['account_id'] is String &&
          (account['account_id'] as String).isNotEmpty) {
        return SerpApiQuota.fromAccount(account);
      }
    }
    throw const SerpApiSetupException(
      'SerpApi에서 계정 정보를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.',
    );
  } on SerpApiSetupException {
    rethrow;
  } on FormatException {
    throw const SerpApiSetupException(
      'SerpApi 계정 응답을 읽지 못했어요. 잠시 후 다시 시도해 주세요.',
    );
  } catch (_) {
    // Transport errors can include the full request URI and its secret.
  } finally {
    if (client == null) transport.close();
  }
  throw const SerpApiSetupException(
    'SerpApi에 연결할 수 없어요. 인터넷 연결을 확인하고 다시 시도해 주세요.',
  );
}
