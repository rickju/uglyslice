import 'dart:convert';
import 'package:http/http.dart' show Response;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:ugly_slice_backend/supabase_client.dart';

const _url = 'https://test.supabase.co';
const _key = 'test-service-role-key';

SupabaseRestClient _client(MockClient mock) =>
    SupabaseRestClient(url: _url, serviceRoleKey: _key, httpClient: mock);

void main() {
  group('SupabaseRestClient.select', () {
    test('returns parsed list', () async {
      final mock = MockClient((_) async =>
          Response(jsonEncode([{'id': 1, 'name': 'Karori Golf Club'}]), 200));
      final rows = await _client(mock).select('course_list');
      expect(rows, hasLength(1));
      expect(rows.first['name'], equals('Karori Golf Club'));
    });

    test('passes column filter as query param', () async {
      late Uri captured;
      final mock = MockClient((req) async {
        captured = req.url;
        return Response('[]', 200);
      });
      await _client(mock).select('courses', columns: 'id,name');
      expect(captured.queryParameters['select'], equals('id,name'));
    });

    test('passes filter as query params', () async {
      late Uri captured;
      final mock = MockClient((req) async {
        captured = req.url;
        return Response('[]', 200);
      });
      await _client(mock).select('courses', filters: 'name=eq.Karori Golf Club');
      expect(captured.queryParameters['name'], equals('eq.Karori Golf Club'));
    });

    test('throws on non-2xx response', () async {
      final mock = MockClient((_) async => Response('Unauthorized', 401));
      expect(
        () => _client(mock).select('courses'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('SupabaseRestClient.upsert', () {
    test('sends POST with rows as JSON body', () async {
      late String capturedBody;
      final mock = MockClient((req) async {
        capturedBody = req.body;
        return Response('', 201);
      });
      await _client(mock).upsert('courses', [
        {'id': 'course_1', 'name': 'Test Course'}
      ]);
      final decoded = jsonDecode(capturedBody) as List;
      expect(decoded.first['id'], equals('course_1'));
    });

    test('does nothing for empty list', () async {
      int callCount = 0;
      final mock = MockClient((_) async {
        callCount++;
        return Response('', 200);
      });
      await _client(mock).upsert('courses', []);
      expect(callCount, equals(0));
    });
  });

  group('SupabaseRestClient.insert', () {
    test('sends POST with Prefer: return=minimal', () async {
      late Map<String, String> capturedHeaders;
      final mock = MockClient((req) async {
        capturedHeaders = req.headers;
        return Response('', 201);
      });
      await _client(mock).insert('course_issues', [
        {'course_id': 'c1', 'severity': 'error', 'message': 'No green'}
      ]);
      expect(capturedHeaders['Prefer'], equals('return=minimal'));
    });

    test('throws on non-2xx response', () async {
      final mock = MockClient((_) async => Response('Error', 400));
      expect(
        () => _client(mock).insert('course_issues', [{'x': 1}]),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('SupabaseRestClient.patch', () {
    test('sends PATCH request to correct URL with filter params', () async {
      late Uri capturedUri;
      late String capturedMethod;
      late String capturedBody;
      final mock = MockClient((req) async {
        capturedUri = req.url;
        capturedMethod = req.method;
        capturedBody = req.body;
        return Response('', 200);
      });
      await _client(mock)
          .patch('courses', 'id=eq.course_123', {'status': 'done'});
      expect(capturedMethod, equals('PATCH'));
      expect(capturedUri.queryParameters['id'], equals('eq.course_123'));
      final body = jsonDecode(capturedBody) as Map;
      expect(body['status'], equals('done'));
    });

    test('throws on non-2xx response', () async {
      final mock = MockClient((_) async => Response('Not found', 404));
      expect(
        () => _client(mock).patch('courses', 'id=eq.x', {'a': 1}),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('SupabaseRestClient.delete', () {
    test('sends DELETE request with filter params', () async {
      late Uri capturedUri;
      late String capturedMethod;
      final mock = MockClient((req) async {
        capturedUri = req.url;
        capturedMethod = req.method;
        return Response('', 200);
      });
      await _client(mock)
          .delete('course_issues', 'course_id=eq.c1&resolved_at=is.null');
      expect(capturedMethod, equals('DELETE'));
      expect(capturedUri.queryParameters['course_id'], equals('eq.c1'));
      expect(capturedUri.queryParameters['resolved_at'], equals('is.null'));
    });

    test('throws on non-2xx response', () async {
      final mock = MockClient((_) async => Response('Error', 500));
      expect(
        () => _client(mock).delete('course_issues', 'id=eq.1'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
