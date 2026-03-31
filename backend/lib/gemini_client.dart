import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Gemini API client (Google Generative Language REST API).
/// Requires GEMINI_API_KEY environment variable.
class GeminiClient {
  static const _defaultModel = 'gemini-2.0-flash';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  final String _apiKey;
  final http.Client _http;

  GeminiClient({String? apiKey, http.Client? httpClient})
      : _apiKey = apiKey ??
            Platform.environment['GEMINI_API_KEY'] ??
            (throw StateError('GEMINI_API_KEY env var not set')),
        _http = httpClient ?? http.Client();

  /// Send a prompt and return the text response.
  Future<String> complete(
    String prompt, {
    String model = _defaultModel,
    int maxTokens = 2048,
  }) async {
    final url = Uri.parse('$_baseUrl/$model:generateContent?key=$_apiKey');
    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {'maxOutputTokens': maxTokens},
    };

    final response = await _http
        .post(url,
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception(
          'Gemini API error: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>;
    if (candidates.isEmpty) throw Exception('Gemini returned no candidates');
    final content = candidates.first['content'] as Map<String, dynamic>;
    final parts = content['parts'] as List<dynamic>;
    return parts.first['text'] as String;
  }

  /// Like [complete] but parses and returns the response as JSON.
  Future<dynamic> completeJson(
    String prompt, {
    String model = _defaultModel,
    int maxTokens = 2048,
  }) async {
    final text = await complete(prompt, model: model, maxTokens: maxTokens);
    final jsonText = _extractJson(text);
    return jsonDecode(jsonText);
  }

  String _extractJson(String text) {
    final fenceMatch =
        RegExp(r'```(?:json)?\s*([\s\S]+?)\s*```').firstMatch(text);
    if (fenceMatch != null) return fenceMatch.group(1)!;
    final objMatch = RegExp(r'(\{[\s\S]+\}|\[[\s\S]+\])').firstMatch(text);
    if (objMatch != null) return objMatch.group(1)!;
    return text.trim();
  }
}
