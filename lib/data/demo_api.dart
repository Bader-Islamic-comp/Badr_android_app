import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Development only. These values are embedded in builds, not secure storage.
class DemoConfig {
  const DemoConfig({this.baseUrl = '', this.token = ''});

  factory DemoConfig.environment() => const DemoConfig(
        baseUrl: String.fromEnvironment('DEMO_API_URL'),
        token: String.fromEnvironment('DEMO_API_TOKEN'),
      );

  final String baseUrl;
  final String token;

  bool get enabled {
    final uri = Uri.tryParse(baseUrl);
    return token.isNotEmpty &&
        uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty &&
        (uri.path.isEmpty || uri.path == '/');
  }
}

class DemoApiException implements Exception {
  const DemoApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DemoApi {
  DemoApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  final DemoConfig config;
  final http.Client _client;
  static String newKey() => const Uuid().v4();

  Future<Map<String, dynamic>> request(String method, String path,
      {Map<String, dynamic>? body, String? key}) async {
    if (!config.enabled) {
      throw const DemoApiException('The development service is not connected.');
    }
    if (method != 'GET' && key == null) {
      throw ArgumentError('Writes require a stable idempotency key.');
    }
    final request =
        http.Request(method, Uri.parse(config.baseUrl).resolve(path));
    // A redirect must not forward the development credential to another host.
    request.followRedirects = false;
    request.headers.addAll({
      'X-Demo-Token': config.token,
      'Accept': 'application/json',
      if (key != null) 'Idempotency-Key': key,
    });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 12)),
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Never expose or log server bodies, request text or credentials.
        throw const DemoApiException(
            'The service could not finish this request.');
      }
      if (response.statusCode == 204) return {};
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const DemoApiException(
            'The service returned an unexpected response.');
      }
      return decoded;
    } on DemoApiException {
      rethrow;
    } catch (_) {
      throw const DemoApiException('Connection unavailable. Please try again.');
    }
  }

  Future<void> bootstrap() async {
    final result = await request('GET', '/v1/bootstrap');
    if (result['mode'] != 'development' ||
        result['characterId'] != 'robert' ||
        result['profileId'] != 'demo-child' ||
        result['contentStatus'] != 'awaiting_review' ||
        result['features'] is! Map ||
        result['features']['voice'] != false ||
        result['features']['generativeAnswers'] != false) {
      throw const DemoApiException(
          'This app requires the development-only service.');
    }
  }

  Future<Map<String, dynamic>> completeLesson(String key) =>
      request('POST', '/v1/lessons/demo-learning/complete', body: {}, key: key);

  Future<Map<String, dynamic>> lessons() => request('GET', '/v1/lessons');
  Future<Map<String, dynamic>> rewards() => request('GET', '/v1/rewards');
  Future<Map<String, dynamic>> inventory() => request('GET', '/v1/inventory');
  Future<Map<String, dynamic>> challenges() =>
      request('GET', '/v1/challenges/today');

  /// Spends earned stars on a look. The service owns the price and the
  /// balance; this never sends either, so a tampered client cannot buy one.
  Future<void> claimCosmetic(String cosmeticId, String key) async {
    final result = await request('POST', '/v1/cosmetics/claim',
        body: {'cosmeticId': cosmeticId}, key: key);
    if (result['cosmeticId'] != cosmeticId || result['owned'] != true) {
      throw const DemoApiException('The service did not confirm this look.');
    }
  }

  /// Wears a look the service already records as owned. Ownership is read back
  /// first so a look is never pushed to the room on the app's say-so.
  Future<void> equipCosmetic(String cosmeticId, String key) async {
    final inventoryResult = await inventory();
    final items = inventoryResult['items'];
    if (items is! List ||
        !items.any((item) =>
            item is Map &&
            item['id'] == cosmeticId &&
            item['characterId'] == 'robert' &&
            item['owned'] == true)) {
      throw const DemoApiException('That look is not earned yet.');
    }
    final result = await request('PUT', '/v1/equipped-cosmetics',
        body: {'cosmeticId': cosmeticId}, key: key);
    if (result['cosmeticId'] != cosmeticId ||
        result['characterId'] != 'robert') {
      throw const DemoApiException(
          'The service did not confirm this appearance.');
    }
  }

  void close() => _client.close();
}
