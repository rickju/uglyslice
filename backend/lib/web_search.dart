import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class SearchResult {
  final String title;
  final String url;
  final String description;

  const SearchResult({
    required this.title,
    required this.url,
    required this.description,
  });
}

/// Brave Search API client.
/// Requires BRAVE_SEARCH_API_KEY environment variable.
class WebSearch {
  final String _apiKey;
  final http.Client _http;

  WebSearch({String? apiKey, http.Client? httpClient})
      : _apiKey = apiKey ??
            Platform.environment['BRAVE_SEARCH_API_KEY'] ??
            (throw StateError('BRAVE_SEARCH_API_KEY env var not set')),
        _http = httpClient ?? http.Client();

  /// Search the web and return up to [count] results.
  Future<List<SearchResult>> search(String query, {int count = 5}) async {
    final uri = Uri.parse('https://api.search.brave.com/res/v1/web/search')
        .replace(queryParameters: {
      'q': query,
      'count': '$count',
      'text_decorations': '0',
      'search_lang': 'en',
    });

    final response = await _http.get(uri, headers: {
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip',
      'X-Subscription-Token': _apiKey,
    }).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
          'Brave Search failed: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final webResults =
        (data['web']?['results'] as List<dynamic>?) ?? [];

    return webResults.take(count).map((r) {
      final m = r as Map<String, dynamic>;
      return SearchResult(
        title: (m['title'] as String?) ?? '',
        url: (m['url'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
      );
    }).toList();
  }

  /// Fetch a URL and return extracted plain text (HTML stripped).
  /// Returns null on error or if content is too large.
  Future<String?> fetchText(String url,
      {int maxChars = 8000}) async {
    try {
      final uri = Uri.parse(url);
      final response = await _http
          .get(uri, headers: {'User-Agent': 'Mozilla/5.0 (compatible; UglySliceBot/1.0)'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('text')) return null;

      var body = response.body;

      // Remove script/style blocks
      body = body.replaceAll(
          RegExp(r'<(script|style)[^>]*>.*?</(script|style)>',
              caseSensitive: false, dotAll: true),
          ' ');

      // Strip HTML tags
      body = body.replaceAll(RegExp(r'<[^>]+>'), ' ');

      // Decode HTML entities
      body = body
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&#39;', "'")
          .replaceAll('&quot;', '"');

      // Collapse whitespace
      body = body.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (body.length > maxChars) body = body.substring(0, maxChars);
      return body;
    } catch (_) {
      return null;
    }
  }
}
