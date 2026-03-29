import 'dart:convert';
import 'package:http/http.dart' show Response;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:ugly_slice_backend/claude_client.dart';
import 'package:ugly_slice_backend/enricher.dart';
import 'package:ugly_slice_backend/supabase_client.dart';
import 'package:ugly_slice_backend/web_search.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _claudeJson(Map<String, dynamic> data) => jsonEncode({
      'content': [
        {'type': 'text', 'text': jsonEncode(data)}
      ],
      'model': 'claude-haiku-4-5-20251001',
      'usage': {'input_tokens': 10, 'output_tokens': 50},
    });

String _braveResults(String url) => jsonEncode({
      'web': {
        'results': [
          {
            'title': 'Test Golf Club',
            'url': url,
            'description': 'Official site'
          }
        ]
      }
    });

// Builds an 18-hole course doc with empty holes_doc entries.
Map<String, dynamic> _courseDoc(String id, String name) => {
      'id': id,
      'name': name,
      'holeCount': 18,
      'boundaryPoints': [],
      'teeInfos': [
        {'name': 'Blue', 'color': 'blue', 'yardage': 0.0, 'courseRating': 0.0, 'slopeRating': 0.0},
        {'name': 'Red', 'color': 'red', 'yardage': 0.0, 'courseRating': 0.0, 'slopeRating': 0.0},
      ],
    };

List<Map<String, dynamic>> _holeDocs18() => List.generate(
      18,
      (i) => {
        'holeNumber': i + 1,
        'par': 4,
        'handicapIndex': 0,
        'pin': {'lat': -41.0, 'lng': 174.0},
        'routingLine': [],
        'teeBoxes': [],
        'teePlatforms': [],
        'fairways': [],
        'greens': [],
      },
    );

// Valid handicaps 1-18 in order.
List<int> get _validHandicaps18 => List.generate(18, (i) => i + 1);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Enricher.processQueue — dry run', () {
    test('dry run skips processing', () async {
      int supabaseSelectCalls = 0;
      final supabaseMock = MockClient((req) async {
        if (req.method == 'GET') supabaseSelectCalls++;
        // Return one pending item.
        return Response(
          jsonEncode([
            {
              'id': 1,
              'course_id': 'course_123',
              'course_name': 'Test Golf Club',
              'fields': ['hole_handicaps']
            }
          ]),
          200,
        );
      });

      final enricher = Enricher(
        supabase: SupabaseRestClient(
            url: 'https://test.sb.co',
            serviceRoleKey: 'key',
            httpClient: supabaseMock),
        search: WebSearch(
            apiKey: 'brave-key',
            httpClient: MockClient((_) async => Response('{}', 200))),
        claude: ClaudeClient(
            apiKey: 'claude-key',
            httpClient: MockClient((_) async => Response('{}', 200))),
      );

      // Should not throw, should skip actual processing.
      await enricher.processQueue(batchSize: 5, dryRun: true);
    });
  });

  group('Enricher.processQueue — empty queue', () {
    test('handles empty queue gracefully', () async {
      final supabaseMock = MockClient((_) async => Response('[]', 200));
      final enricher = Enricher(
        supabase: SupabaseRestClient(
            url: 'https://test.sb.co',
            serviceRoleKey: 'key',
            httpClient: supabaseMock),
        search: WebSearch(
            apiKey: 'key',
            httpClient: MockClient((_) async => Response('{}', 200))),
        claude: ClaudeClient(
            apiKey: 'key',
            httpClient: MockClient((_) async => Response('{}', 200))),
      );
      // Should complete without error.
      await enricher.processQueue();
    });
  });

  group('Enricher — handicap extraction', () {
    test('patches holes_doc when valid handicaps extracted', () async {
      final courseId = 'course_456';
      final holeDocs = _holeDocs18();
      final courseDocData = _courseDoc(courseId, 'Test Golf Club');
      final handicaps = _validHandicaps18;

      // Track PATCH calls.
      final patchBodies = <Map<String, dynamic>>[];

      final supabaseMock = MockClient((req) async {
        if (req.method == 'GET') {
          final path = req.url.path;
          if (path.contains('enrich_queue')) {
            return Response(
              jsonEncode([
                {
                  'id': 1,
                  'course_id': courseId,
                  'course_name': 'Test Golf Club',
                  'fields': ['hole_handicaps']
                }
              ]),
              200,
            );
          }
          if (path.contains('courses')) {
            return Response(
              jsonEncode([
                {
                  'course_doc': courseDocData,
                  'holes_doc': holeDocs,
                }
              ]),
              200,
            );
          }
        }
        if (req.method == 'PATCH') {
          patchBodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        }
        return Response('', 200);
      });

      final searchMock = MockClient((req) async {
        if (req.url.host.contains('brave')) {
          return Response(_braveResults('https://testgolf.co.nz'), 200);
        }
        // Club website — must be >200 chars after HTML stripping.
        return Response(
          '<html><body><h1>Test Golf Club Scorecard</h1>'
          '<p>Hole 1 par 4 handicap 1 yards 420</p>'
          '<p>Hole 2 par 3 handicap 15 yards 180</p>'
          '<p>Hole 3 par 5 handicap 7 yards 520</p>'
          '<p>Hole 4 par 4 handicap 9 yards 390</p>'
          '<p>Hole 5 par 4 handicap 3 yards 410</p>'
          '<p>Blue tees course rating 72.1 slope 131</p>'
          '</body></html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      final claudeMock = MockClient((_) async => Response(
            _claudeJson({'hole_handicaps': handicaps}),
            200,
          ));

      final enricher = Enricher(
        supabase: SupabaseRestClient(
            url: 'https://test.sb.co',
            serviceRoleKey: 'key',
            httpClient: supabaseMock),
        search: WebSearch(apiKey: 'brave-key', httpClient: searchMock),
        claude: ClaudeClient(apiKey: 'claude-key', httpClient: claudeMock),
      );

      await enricher.processQueue(batchSize: 1);

      // At least one PATCH should contain updated holes_doc.
      final holesPatch = patchBodies.firstWhere(
        (b) => b.containsKey('holes_doc'),
        orElse: () => {},
      );
      expect(holesPatch, isNotEmpty,
          reason: 'Expected a PATCH with holes_doc');

      final updatedHoles = holesPatch['holes_doc'] as List;
      expect(updatedHoles[0]['handicapIndex'], equals(1));
      expect(updatedHoles[17]['handicapIndex'], equals(18));
    });
  });

  group('Enricher — tee ratings extraction', () {
    test('patches course_doc when valid tee ratings extracted', () async {
      final courseId = 'course_789';
      final courseDocData = _courseDoc(courseId, 'Test Golf Club');
      final holeDocs = _holeDocs18();

      final patchBodies = <Map<String, dynamic>>[];

      final supabaseMock = MockClient((req) async {
        if (req.method == 'GET') {
          if (req.url.path.contains('enrich_queue')) {
            return Response(
              jsonEncode([
                {
                  'id': 2,
                  'course_id': courseId,
                  'course_name': 'Test Golf Club',
                  'fields': ['tee_ratings']
                }
              ]),
              200,
            );
          }
          if (req.url.path.contains('courses')) {
            return Response(
              jsonEncode([{'course_doc': courseDocData, 'holes_doc': holeDocs}]),
              200,
            );
          }
        }
        if (req.method == 'PATCH') {
          patchBodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        }
        return Response('', 200);
      });

      final searchMock = MockClient((req) async {
        if (req.url.host.contains('brave')) {
          return Response(_braveResults('https://testgolf.co.nz'), 200);
        }
        return Response(
          '<html><body><h1>Test Golf Club</h1>'
          '<p>Blue tees: 6200 yards, Course Rating 72.1, Slope Rating 131</p>'
          '<p>Red tees: 5400 yards, Course Rating 69.5, Slope Rating 121</p>'
          '<p>18 holes par 72 championship course in Wellington New Zealand</p>'
          '<p>Visitors welcome weekdays and weekends by prior arrangement</p>'
          '</body></html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      final claudeMock = MockClient((_) async => Response(
            _claudeJson({
              'tee_ratings': [
                {
                  'name': 'Blue',
                  'yardage': 6200,
                  'course_rating': 72.1,
                  'slope_rating': 131
                }
              ]
            }),
            200,
          ));

      final enricher = Enricher(
        supabase: SupabaseRestClient(
            url: 'https://test.sb.co',
            serviceRoleKey: 'key',
            httpClient: supabaseMock),
        search: WebSearch(apiKey: 'brave-key', httpClient: searchMock),
        claude: ClaudeClient(apiKey: 'claude-key', httpClient: claudeMock),
      );

      await enricher.processQueue(batchSize: 1);

      final coursePatch = patchBodies.firstWhere(
        (b) => b.containsKey('course_doc'),
        orElse: () => {},
      );
      expect(coursePatch, isNotEmpty, reason: 'Expected a PATCH with course_doc');

      final updatedDoc = coursePatch['course_doc'] as Map<String, dynamic>;
      final teeInfos =
          (updatedDoc['teeInfos'] as List).cast<Map<String, dynamic>>();
      final blue = teeInfos.firstWhere((t) => t['name'] == 'Blue');
      expect(blue['yardage'], equals(6200.0));
      expect(blue['courseRating'], equals(72.1));
      expect(blue['slopeRating'], equals(131.0));
    });
  });

  group('Handicap validation', () {
    // Test the validation logic indirectly: invalid handicaps should result in
    // no holes_doc patch (the enricher silently skips invalid data).
    test('rejects handicaps that are not unique 1..N', () async {
      final courseId = 'course_hcp_invalid';
      final holeDocs = _holeDocs18();
      final courseDocData = _courseDoc(courseId, 'Test Golf Club');

      final patchBodies = <Map<String, dynamic>>[];

      final supabaseMock = MockClient((req) async {
        if (req.method == 'GET') {
          if (req.url.path.contains('enrich_queue')) {
            return Response(
              jsonEncode([
                {
                  'id': 3,
                  'course_id': courseId,
                  'course_name': 'Test Golf Club',
                  'fields': ['hole_handicaps']
                }
              ]),
              200,
            );
          }
          if (req.url.path.contains('courses')) {
            return Response(
              jsonEncode([{'course_doc': courseDocData, 'holes_doc': holeDocs}]),
              200,
            );
          }
        }
        if (req.method == 'PATCH') {
          patchBodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        }
        return Response('', 200);
      });

      final searchMock = MockClient((req) async {
        if (req.url.host.contains('brave')) {
          return Response(_braveResults('https://testgolf.co.nz'), 200);
        }
        return Response(
          '<html><body><h1>Test Golf Club Scorecard</h1>'
          '<p>18 holes championship course par 72 in New Zealand Wellington region</p>'
          '<p>Hole information handicap index and yardage data available on request</p>'
          '<p>Green fees and booking information contact the pro shop directly</p>'
          '</body></html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      // Return duplicate handicaps — invalid (all 1s).
      final claudeMock = MockClient((_) async => Response(
            _claudeJson({'hole_handicaps': List.filled(18, 1)}),
            200,
          ));

      final enricher = Enricher(
        supabase: SupabaseRestClient(
            url: 'https://test.sb.co',
            serviceRoleKey: 'key',
            httpClient: supabaseMock),
        search: WebSearch(apiKey: 'brave-key', httpClient: searchMock),
        claude: ClaudeClient(apiKey: 'claude-key', httpClient: claudeMock),
      );

      await enricher.processQueue(batchSize: 1);

      // Should have marked as failed (no holes_doc patch).
      final holesPatch = patchBodies.firstWhere(
        (b) => b.containsKey('holes_doc'),
        orElse: () => {},
      );
      expect(holesPatch, isEmpty,
          reason: 'Should not patch holes_doc for invalid handicaps');
    });
  });
}
