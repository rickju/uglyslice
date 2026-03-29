import 'dart:convert';
import 'package:http/http.dart' show Response;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:ugly_slice_backend/web_search.dart';

WebSearch _search(MockClient mock) =>
    WebSearch(apiKey: 'test-brave-key', httpClient: mock);

String _braveResponse(List<Map<String, String>> results) => jsonEncode({
      'web': {
        'results': results
            .map((r) => {
                  'title': r['title'] ?? '',
                  'url': r['url'] ?? '',
                  'description': r['description'] ?? '',
                })
            .toList()
      }
    });

void main() {
  group('WebSearch.search', () {
    test('returns parsed results', () async {
      final mock = MockClient((_) async => Response(
              _braveResponse([
                {
                  'title': 'Karori Golf Club',
                  'url': 'https://karori.co.nz',
                  'description': 'Golf in Wellington'
                },
              ]),
              200));
      final results = await _search(mock).search('Karori Golf');
      expect(results, hasLength(1));
      expect(results.first.title, equals('Karori Golf Club'));
      expect(results.first.url, equals('https://karori.co.nz'));
    });

    test('sends correct auth header', () async {
      late Map<String, String> headers;
      final mock = MockClient((req) async {
        headers = req.headers;
        return Response(_braveResponse([]), 200);
      });
      await _search(mock).search('test query');
      expect(headers['X-Subscription-Token'], equals('test-brave-key'));
    });

    test('passes query as q param', () async {
      late Uri captured;
      final mock = MockClient((req) async {
        captured = req.url;
        return Response(_braveResponse([]), 200);
      });
      await _search(mock).search('Karori Golf Club scorecard');
      expect(captured.queryParameters['q'],
          equals('Karori Golf Club scorecard'));
    });

    test('respects count parameter', () async {
      late Uri captured;
      final mock = MockClient((req) async {
        captured = req.url;
        return Response(_braveResponse([]), 200);
      });
      await _search(mock).search('test', count: 3);
      expect(captured.queryParameters['count'], equals('3'));
    });

    test('throws on non-200 response', () async {
      final mock = MockClient((_) async => Response('Forbidden', 403));
      expect(
          () => _search(mock).search('test'), throwsA(isA<Exception>()));
    });
  });

  group('WebSearch.fetchText', () {
    test('strips HTML tags from response', () async {
      const html = '<html><body><h1>Welcome</h1><p>Hole 1 par 4</p></body></html>';
      final mock = MockClient((_) async =>
          Response(html, 200, headers: {'content-type': 'text/html'}));
      final text = await _search(mock).fetchText('https://example.com');
      expect(text, isNotNull);
      expect(text, isNot(contains('<h1>')));
      expect(text, contains('Welcome'));
      expect(text, contains('Hole 1 par 4'));
    });

    test('removes script tags and their content', () async {
      const html =
          '<body><script>alert("xss")</script><p>Real content</p></body>';
      final mock = MockClient((_) async =>
          Response(html, 200, headers: {'content-type': 'text/html'}));
      final text = await _search(mock).fetchText('https://example.com');
      expect(text, isNotNull);
      expect(text, isNot(contains('alert')));
      expect(text, contains('Real content'));
    });

    test('decodes common HTML entities', () async {
      const html = '<p>Golf &amp; Country Club &nbsp; Course Rating: 72.4</p>';
      final mock = MockClient((_) async =>
          Response(html, 200, headers: {'content-type': 'text/html'}));
      final text = await _search(mock).fetchText('https://example.com');
      expect(text, contains('Golf & Country Club'));
      expect(text, contains('Course Rating: 72.4'));
    });

    test('returns null on non-200', () async {
      final mock = MockClient((_) async => Response('Not found', 404,
          headers: {'content-type': 'text/html'}));
      final text = await _search(mock).fetchText('https://example.com');
      expect(text, isNull);
    });

    test('returns null for non-text content type', () async {
      final mock = MockClient((_) async => Response(
          'binary', 200, headers: {'content-type': 'application/octet-stream'}));
      final text = await _search(mock).fetchText('https://example.com');
      expect(text, isNull);
    });

    test('truncates output to maxChars', () async {
      final longContent = 'a' * 10000;
      final html = '<p>$longContent</p>';
      final mock = MockClient((_) async =>
          Response(html, 200, headers: {'content-type': 'text/html'}));
      final text = await _search(mock).fetchText(
        'https://example.com',
        maxChars: 100,
      );
      expect(text, isNotNull);
      expect(text!.length, lessThanOrEqualTo(100));
    });
  });
}
