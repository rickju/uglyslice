import 'dart:io';

import 'package:http/http.dart' as http;
import 'dart:convert';

/// Thin Supabase REST client for the backend (service-role access).
/// Reads SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from environment.
class SupabaseRestClient {
  final String _url;
  final String _serviceRoleKey;
  final http.Client _http;

  SupabaseRestClient({http.Client? httpClient})
      : _url = Platform.environment['SUPABASE_URL'] ??
            (throw StateError('SUPABASE_URL env var not set')),
        _serviceRoleKey =
            Platform.environment['SUPABASE_SERVICE_ROLE_KEY'] ??
                (throw StateError(
                    'SUPABASE_SERVICE_ROLE_KEY env var not set')),
        _http = httpClient ?? http.Client();

  Map<String, String> get _headers => {
        'apikey': _serviceRoleKey,
        'Authorization': 'Bearer $_serviceRoleKey',
        'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates',
      };

  /// Upsert rows into [table]. [rows] must be a list of JSON-serialisable maps.
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final uri = Uri.parse('$_url/rest/v1/$table');
    final response = await _http.post(
      uri,
      headers: _headers,
      body: jsonEncode(rows),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Supabase upsert to $table failed: ${response.statusCode} ${response.body}');
    }
  }
}
