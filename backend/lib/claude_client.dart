import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Claude API client (Anthropic Messages API).
/// Requires ANTHROPIC_API_KEY environment variable.
class ClaudeClient {
  static const _defaultModel = 'claude-haiku-4-5-20251001';
  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  final String _apiKey;
  final http.Client _http;

  ClaudeClient({String? apiKey, http.Client? httpClient})
      : _apiKey = apiKey ??
            Platform.environment['ANTHROPIC_API_KEY'] ??
            (throw StateError('ANTHROPIC_API_KEY env var not set')),
        _http = httpClient ?? http.Client();

  /// Send a user message and return the assistant text response.
  Future<String> complete(
    String prompt, {
    String model = _defaultModel,
    int maxTokens = 2048,
    String? systemPrompt,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    };
    if (systemPrompt != null) body['system'] = systemPrompt;

    final response = await _http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'x-api-key': _apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception(
          'Claude API error: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = (data['content'] as List<dynamic>).first as Map<String, dynamic>;
    return content['text'] as String;
  }

  /// Like [complete] but parses and returns the response as JSON.
  /// Throws if the response is not valid JSON.
  Future<dynamic> completeJson(
    String prompt, {
    String model = _defaultModel,
    int maxTokens = 2048,
    String? systemPrompt,
  }) async {
    final text = await complete(
      prompt,
      model: model,
      maxTokens: maxTokens,
      systemPrompt: systemPrompt,
    );

    // Extract JSON from the response (may be wrapped in markdown code fences)
    final jsonText = _extractJson(text);
    return jsonDecode(jsonText);
  }

  String _extractJson(String text) {
    // Try to find a JSON block in markdown code fences
    final fenceMatch =
        RegExp(r'```(?:json)?\s*([\s\S]+?)\s*```').firstMatch(text);
    if (fenceMatch != null) return fenceMatch.group(1)!;

    // Try to find raw JSON object or array
    final objMatch = RegExp(r'(\{[\s\S]+\}|\[[\s\S]+\])').firstMatch(text);
    if (objMatch != null) return objMatch.group(1)!;

    return text.trim();
  }
}
