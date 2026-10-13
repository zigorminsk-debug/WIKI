import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/confluence_settings.dart';
import '../models/knowledge_page.dart';

class ConfluenceClient {
  ConfluenceClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<KnowledgePage>> fetchAllPages({
    required ConfluenceSettings settings,
    required String password,
    required String syncRun,
  }) async {
    if (!settings.isConfigured || password.isEmpty) {
      throw const ConfluenceException('Укажите адрес сервера, логин и пароль.');
    }

    final pages = <KnowledgePage>[];
    var start = 0;
    const limit = 100;
    while (true) {
      final endpoint = settings.baseUri.replace(
        path: '${settings.baseUri.path}/rest/api/content'.replaceAll('//', '/'),
        queryParameters: <String, String>{
          'type': 'page',
          'status': 'current',
          'start': '$start',
          'limit': '$limit',
          'expand': 'body.storage,version,space,ancestors',
        },
      );
      final response = await _client
          .get(
            endpoint,
            headers: <String, String>{
              'Accept': 'application/json',
              'Authorization': 'Basic ${base64Encode(utf8.encode('${settings.username}:$password'))}',
            },
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ConfluenceException('Confluence отклонил логин, пароль или права доступа.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ConfluenceException('Confluence вернул HTTP ${response.statusCode}.');
      }

      final payload = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final results = payload['results'] as List<dynamic>? ?? <dynamic>[];
      final received = results.whereType<Map<String, dynamic>>().map(
        (item) => KnowledgePage.fromConfluence(item, syncRun: syncRun, baseUri: settings.baseUri),
      );
      pages.addAll(received.where((page) => page.id.isNotEmpty));

      // Server/Data Center normally sends `total`; `_links.next` covers API
      // proxies which omit it. Do not stop merely because a proxy caps `limit`.
      final total = (payload['total'] as num?)?.toInt();
      final links = payload['_links'] as Map<String, dynamic>?;
      final hasNext = (links?['next'] as String? ?? '').isNotEmpty;
      if (results.isEmpty ||
          (total != null && start + results.length >= total) ||
          (total == null && !hasNext)) {
        break;
      }
      start += results.length;
    }
    return pages;
  }

  void close() => _client.close();
}

class ConfluenceException implements Exception {
  const ConfluenceException(this.message);

  final String message;

  @override
  String toString() => message;
}
