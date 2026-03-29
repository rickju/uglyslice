import 'dart:io';

import 'package:http/http.dart' as http;
import 'dart:convert';

/// Thin Supabase REST client for the backend (service-role access).
/// Reads SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from environment.
class SupabaseRestClient {
  final String _url;
  final String _serviceRoleKey;
  final http.Client _http;

  SupabaseRestClient({String? url, String? serviceRoleKey, http.Client? httpClient})
      : _url = url ??
            Platform.environment['SUPABASE_URL'] ??
            (throw StateError('SUPABASE_URL env var not set')),
        _serviceRoleKey = serviceRoleKey ??
            Platform.environment['SUPABASE_SERVICE_ROLE_KEY'] ??
            (throw StateError('SUPABASE_SERVICE_ROLE_KEY env var not set')),
        _http = httpClient ?? http.Client();

  Map<String, String> get _headers => {
        'apikey': _serviceRoleKey,
        'Authorization': 'Bearer $_serviceRoleKey',
        'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates',
      };

  /// Select rows from [table] with optional PostgREST [filters] (e.g. 'name=eq.Karori Golf Club').
  Future<List<Map<String, dynamic>>> select(String table,
      {String? filters, String? columns}) async {
    var uri = Uri.parse('$_url/rest/v1/$table');
    final params = <String, String>{};
    if (columns != null) params['select'] = columns;
    if (filters != null) {
      final parts = filters.split('&');
      for (final part in parts) {
        final idx = part.indexOf('=');
        if (idx > 0) params[part.substring(0, idx)] = part.substring(idx + 1);
      }
    }
    if (params.isNotEmpty) uri = uri.replace(queryParameters: params);
    final response = await _http.get(uri, headers: {
      'apikey': _serviceRoleKey,
      'Authorization': 'Bearer $_serviceRoleKey',
      'Accept': 'application/json',
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Supabase select from $table failed: ${response.statusCode} ${response.body}');
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

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

  /// Insert rows into [table] without upsert conflict resolution.
  Future<void> insert(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final uri = Uri.parse('$_url/rest/v1/$table');
    final response = await _http.post(
      uri,
      headers: {
        'apikey': _serviceRoleKey,
        'Authorization': 'Bearer $_serviceRoleKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      },
      body: jsonEncode(rows),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Supabase insert into $table failed: ${response.statusCode} ${response.body}');
    }
  }

  /// Partially update rows in [table] matching [filters] (PostgREST filter string,
  /// e.g. `'id=eq.course_123'`). [patch] contains only the fields to update.
  Future<void> patch(
      String table, String filters, Map<String, dynamic> patch) async {
    var uri = Uri.parse('$_url/rest/v1/$table');
    final params = <String, String>{};
    for (final part in filters.split('&')) {
      final idx = part.indexOf('=');
      if (idx > 0) params[part.substring(0, idx)] = part.substring(idx + 1);
    }
    if (params.isNotEmpty) uri = uri.replace(queryParameters: params);

    final response = await _http.patch(
      uri,
      headers: {
        'apikey': _serviceRoleKey,
        'Authorization': 'Bearer $_serviceRoleKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      },
      body: jsonEncode(patch),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Supabase patch on $table failed: ${response.statusCode} ${response.body}');
    }
  }

  /// Delete rows from [table] matching [filters] (PostgREST filter string,
  /// e.g. `'course_id=eq.course_123&resolved_at=is.null'`).
  Future<void> delete(String table, String filters) async {
    var uri = Uri.parse('$_url/rest/v1/$table');
    final params = <String, String>{};
    for (final part in filters.split('&')) {
      final idx = part.indexOf('=');
      if (idx > 0) params[part.substring(0, idx)] = part.substring(idx + 1);
    }
    if (params.isNotEmpty) uri = uri.replace(queryParameters: params);

    final response = await _http.delete(
      uri,
      headers: {
        'apikey': _serviceRoleKey,
        'Authorization': 'Bearer $_serviceRoleKey',
        'Prefer': 'return=minimal',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Supabase delete from $table failed: ${response.statusCode} ${response.body}');
    }
  }
}
