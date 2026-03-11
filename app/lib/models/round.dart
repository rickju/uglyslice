import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:syncable/syncable.dart';
import 'package:ugly_slice_shared/player.dart';
import 'package:ugly_slice_shared/round_data.dart';
import 'package:uuid/uuid.dart';

import 'course.dart';

export 'package:ugly_slice_shared/round_data.dart' show Shot, HolePlay, LieType;
export 'package:ugly_slice_shared/club.dart' show Club, ClubType;
export 'package:ugly_slice_shared/player.dart' show Player;

class Round extends Equatable implements Syncable {
  @override
  final String id;
  @override
  final String? userId;
  @override
  final DateTime updatedAt;
  @override
  final bool deleted;

  final Player player;
  final Course course;
  final DateTime date;
  final List<HolePlay> holePlays;
  final String status;

  Round({
    String? id,
    this.userId,
    DateTime? updatedAt,
    this.deleted = false,
    required this.player,
    required this.course,
    required this.date,
    this.holePlays = const [],
    this.status = 'in_progress',
  })  : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  /// Constructor invoked by Drift when reading rows (via @UseRowClass).
  factory Round.fromRow({
    required String id,
    String? userId,
    required DateTime updatedAt,
    required bool deleted,
    required String playerName,
    required double playerHandicap,
    required String courseId,
    required String courseName,
    required DateTime date,
    required String status,
    required String data,
  }) {
    final decoded = jsonDecode(data) as Map<String, dynamic>;
    return Round(
      id: id,
      userId: userId,
      updatedAt: updatedAt,
      deleted: deleted,
      player: Player(name: playerName, handicap: playerHandicap),
      course: Course.stub(id: courseId, name: courseName),
      date: date,
      status: status,
      holePlays: (decoded['holePlays'] as List? ?? [])
          .map((hp) => HolePlay.fromMap(hp as Map<String, dynamic>))
          .toList(),
    );
  }

  int get totalScore =>
      holePlays.fold(0, (total, hp) => total + hp.score);

  @override
  List<Object?> get props =>
      [id, userId, updatedAt, deleted, player.name, course.id, date, status];

  // ── Syncable ────────────────────────────────────────────────────────────────

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
        'player_name': player.name,
        'player_handicap': player.handicap,
        'course_id': course.id,
        'course_name': course.name,
        'date': date.toUtc().toIso8601String(),
        'status': status,
        'data': jsonEncode(
            {'holePlays': holePlays.map((hp) => hp.toMap()).toList()}),
      };

  static Round fromJson(Map<String, dynamic> json) {
    final data =
        jsonDecode(json['data'] as String? ?? '{}') as Map<String, dynamic>;
    return Round(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      deleted: json['deleted'] as bool? ?? false,
      player: Player(
        name: json['player_name'] as String,
        handicap: (json['player_handicap'] as num).toDouble(),
      ),
      course: Course.stub(
        id: json['course_id'] as String,
        name: json['course_name'] as String,
      ),
      date: DateTime.parse(json['date'] as String),
      status: json['status'] as String? ?? 'completed',
      holePlays: (data['holePlays'] as List? ?? [])
          .map((hp) => HolePlay.fromMap(hp as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Returns a Drift-compatible companion built from [Variable]s so that
  /// this file does not need to import app_database.dart (avoiding a
  /// circular-import deadlock with the generated part file).
  @override
  UpdateCompanion<Syncable> toCompanion() => _RoundCompanion(this);

  // ── Convenience ─────────────────────────────────────────────────────────────

  Round copyWith({
    String? id,
    String? userId,
    DateTime? updatedAt,
    bool? deleted,
    Player? player,
    Course? course,
    DateTime? date,
    List<HolePlay>? holePlays,
    String? status,
  }) =>
      Round(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
        player: player ?? this.player,
        course: course ?? this.course,
        date: date ?? this.date,
        holePlays: holePlays ?? this.holePlays,
        status: status ?? this.status,
      );

  // ── Legacy (scorecard display) ───────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'courseId': course.id,
        'courseName': course.name,
        'playerName': player.name,
        'playerHandicap': player.handicap,
        'date': date,
        'status': status,
        'holePlays': holePlays.map((hp) => hp.toMap()).toList(),
      };

  static Round fromScoreMap(Map<String, dynamic> m) => Round(
        player: Player(
          name: m['playerName'] as String,
          handicap: (m['playerHandicap'] as num).toDouble(),
        ),
        course: Course.stub(
          id: m['courseId'] as String,
          name: m['courseName'] as String,
        ),
        date: m['date'] as DateTime,
        status: m['status'] as String? ?? 'completed',
        holePlays: (m['holePlays'] as List? ?? [])
            .map((hp) => HolePlay.fromMap(hp as Map<String, dynamic>))
            .toList(),
      );
}

/// Companion built directly from [Variable]s so that [Round] does not need to
/// import the generated app_database.dart (which would create a circular dep).
class _RoundCompanion extends UpdateCompanion<Syncable> {
  final Round _r;
  const _RoundCompanion(this._r);

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final dataJson = jsonEncode(
        {'holePlays': _r.holePlays.map((h) => h.toMap()).toList()});
    // Variable<String> constructor accepts String? — null becomes SQL NULL
    final map = <String, Expression>{
      'id': Variable<String>(_r.id),
      'updated_at': Variable<DateTime>(_r.updatedAt),
      'deleted': Variable<bool>(_r.deleted),
      'player_name': Variable<String>(_r.player.name),
      'player_handicap': Variable<double>(_r.player.handicap),
      'course_id': Variable<String>(_r.course.id),
      'course_name': Variable<String>(_r.course.name),
      'date': Variable<DateTime>(_r.date),
      'status': Variable<String>(_r.status),
      'data': Variable<String>(dataJson),
    };
    // Nullable column: include when present or when explicitly setting to NULL
    if (!nullToAbsent || _r.userId != null) {
      map['user_id'] = Variable<String>(_r.userId!);
    }
    return map;
  }
}
