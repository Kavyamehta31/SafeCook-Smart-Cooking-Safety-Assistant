import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../agent/safecook_tools.dart';

class WebSearchResult {
  final String title;
  final String url;
  final String snippet;

  WebSearchResult({required this.title, required this.url, required this.snippet});

  factory WebSearchResult.fromJson(Map<String, dynamic> json) {
    return WebSearchResult(
      title: json['title'] as String? ?? 'Untitled',
      url: json['url'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
    );
  }
}

class WebSearchResponse {
  final List<WebSearchResult> results;
  final String? answer;

  WebSearchResponse({required this.results, this.answer});
}

class WebSearchService {
  static final WebSearchService _instance = WebSearchService._internal();
  factory WebSearchService() => _instance;
  WebSearchService._internal();

  static const String _dartDefineProxyUrl = String.fromEnvironment('SAFECOOK_SEARCH_PROXY');
  String _baseUrl = _dartDefineProxyUrl.isNotEmpty ? _dartDefineProxyUrl : 'https://safecook-search-backend.kavyamehta105.workers.dev';

  /// Allow runtime configuration (e.g. in tests)
  void setBaseUrl(String url) {
    _baseUrl = url;
  }

  Future<ToolResult> search(String query) async {
    if (query.trim().isEmpty) {
      return const ToolResult.fail('Search query cannot be empty.');
    }

    final url = Uri.parse('$_baseUrl/search');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.postUrl(url);
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode({'query': query}));

      final response = await request.close();
      if (response.statusCode != 200) {
        client.close();
        return ToolResult.fail('Backend proxy error: HTTP ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join();
      client.close();

      final parsed = jsonDecode(body);
      if (parsed['success'] != true) {
        return ToolResult.fail(parsed['error'] as String? ?? 'Unknown backend search failure.');
      }

      final resultsRaw = parsed['results'] as List? ?? [];
      final results = resultsRaw.map((r) => WebSearchResult.fromJson(r as Map<String, dynamic>)).toList();
      final answer = parsed['answer'] as String?;

      return ToolResult.ok(
        'Web search succeeded.',
        data: WebSearchResponse(results: results, answer: answer),
      );
    } on SocketException catch (e) {
      client.close();
      return ToolResult.fail('Network unavailable or proxy server offline: ${e.message}');
    } on HandshakeException catch (e) {
      client.close();
      return ToolResult.fail('SSL handshake failed: ${e.message}');
    } on TimeoutException {
      client.close();
      return const ToolResult.fail('Web search request timed out.');
    } catch (e) {
      client.close();
      return ToolResult.fail('Web search failed: $e');
    }
  }
}
