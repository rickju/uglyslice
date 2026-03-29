import 'dart:convert';
import 'package:http/http.dart' show Response;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:ugly_slice_backend/claude_client.dart';

ClaudeClient _client(MockClient mock) =>
    ClaudeClient(apiKey: 'test-key', httpClient: mock);

String _claudeResponse(String text) => jsonEncode({
      'id': 'msg_test',
      'type': 'message',
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': text}
      ],
      'model': 'claude-haiku-4-5-20251001',
      'stop_reason': 'end_turn',
      'usage': {'input_tokens': 10, 'output_tokens': 20},
    });

void main() {
  group('ClaudeClient.complete', () {
    test('returns text content from response', () async {
      final mock =
          MockClient((_) async => Response(_claudeResponse('Hello!'), 200));
      final result = await _client(mock).complete('say hello');
      expect(result, equals('Hello!'));
    });

    test('sends correct headers', () async {
      late Map<String, String> headers;
      final mock = MockClient((req) async {
        headers = req.headers;
        return Response(_claudeResponse('ok'), 200);
      });
      await _client(mock).complete('test');
      expect(headers['x-api-key'], equals('test-key'));
      expect(headers['anthropic-version'], equals('2023-06-01'));
      expect(headers['content-type'], equals('application/json'));
    });

    test('includes system prompt when provided', () async {
      late Map<String, dynamic> body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return Response(_claudeResponse('ok'), 200);
      });
      await _client(mock)
          .complete('question', systemPrompt: 'You are helpful.');
      expect(body['system'], equals('You are helpful.'));
    });

    test('throws on non-200 response', () async {
      final mock =
          MockClient((_) async => Response('{"error": "overloaded"}', 529));
      expect(() => _client(mock).complete('test'), throwsA(isA<Exception>()));
    });
  });

  group('ClaudeClient.completeJson', () {
    test('parses bare JSON object', () async {
      final mock = MockClient((_) async =>
          Response(_claudeResponse('{"holes": [1, 2, 3]}'), 200));
      final result = await _client(mock).completeJson('extract');
      expect((result as Map)['holes'], equals([1, 2, 3]));
    });

    test('parses JSON wrapped in markdown code fence', () async {
      final mock = MockClient((_) async => Response(
          _claudeResponse('```json\n{"key": "value"}\n```'), 200));
      final result = await _client(mock).completeJson('extract');
      expect((result as Map)['key'], equals('value'));
    });

    test('parses JSON in plain code fence (no language tag)', () async {
      final mock = MockClient((_) async =>
          Response(_claudeResponse('```\n[1, 2, 3]\n```'), 200));
      final result = await _client(mock).completeJson('extract');
      expect(result, equals([1, 2, 3]));
    });

    test('parses JSON array', () async {
      final mock = MockClient(
          (_) async => Response(_claudeResponse('[{"a": 1}, {"b": 2}]'), 200));
      final result = await _client(mock).completeJson('extract');
      expect(result, hasLength(2));
    });

    test('throws FormatException for invalid JSON', () async {
      final mock = MockClient(
          (_) async => Response(_claudeResponse('not json at all'), 200));
      expect(
          () => _client(mock).completeJson('extract'),
          throwsA(isA<FormatException>()));
    });
  });
}
