import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'models/round.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'models/course.dart';
import 'services/course_repository.dart';
import 'services/round_repository.dart';
import 'services/watch_service.dart';
import 'round_scorecard_page.dart';
import 'main.dart' show db;

// page widget
class RoundPage extends StatefulWidget {
  final String courseId;
  final String courseName;
  /// Non-null when opening an existing round for review/editing.
  final Round? reviewRound;

  const RoundPage({
    super.key,
    required this.courseId,
    required this.courseName,
    this.reviewRound,
  });

  @override
  State<RoundPage> createState() => _RoundPageState();
}

// state
class _RoundPageState extends State<RoundPage> {
  bool _isLoading = true;

  Round? _round;
  int _currentHoleIndex = 0;
  LatLng? _currentPlayerPos;
  LatLng? _selectedTee;
  LatLng? _rulerTarget;
  bool _isSatellite = true;
  final Map<int, int> _strokes = {}; // hole index → stroke count
  bool _strokeEditing = false;
  final List<LatLng> _breadcrumb = [];
  final List<LatLng> _hitPositions = [];
  // shot position dragging (review mode)
  int? _draggingShotIdx;
  final Map<int, LatLng> _draggedShotPositions = {};   // live during drag
  final Map<int, LatLng> _committedShotPositions = {}; // updates on release

  String? _errorMessage;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadCourse();
  }

  Future<void> _loadCourse() async {
    final repo = CourseRepository(db);
    final Course? golfCourse = await repo.fetchCourse(widget.courseId);

    if (golfCourse == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Course data not found. Please go back and re-select the course.';
      });
      return;
    }

    final review = widget.reviewRound;
    setState(() {
      if (review != null) {
        _round = review.copyWith(course: golfCourse);
        for (int i = 0; i < review.holePlays.length; i++) {
          _strokes[i] = review.holePlays[i].score;
        }
      } else {
        _round = Round(
            player: Player(name: 'Rick'), course: golfCourse, date: DateTime.now());
      }
      _breadcrumb.addAll(_round!.trail);
      _hitPositions.addAll(_round!.hitPositions);
      _isLoading = false;
    });
    if (review != null) _initCommittedPositionsForHole();
    debugPrint('Holes loaded for ${widget.courseName}: ${_round!.course.holes.length}');

    if (review == null) _determinePosition();

    WatchService.instance.listen(onHit: recordHit);
    _pushWatchContext();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_round!.course.holes.isNotEmpty) _fitMapToHoleView(0);
    });
  } // _loadCourse

  Future<void> _determinePosition() async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      // GPS
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).listen((Position position) {
        final newPos = LatLng(position.latitude, position.longitude);
        debugPrint('new pos: $newPos.toString()');
        setState(() {
          _currentPlayerPos = newPos;
          _breadcrumb.add(newPos);
        });

        if (_round != null && _round!.course.holes.isNotEmpty) {
          final targetGreen = _round!.course.holes[_currentHoleIndex].pin;
          final bearing = const Distance().bearing(newPos, targetGreen);
          _mapController.rotate(-bearing);
        }
      });
    } else {
      // failover while no gps
      if (_round != null && _round!.course.holes.isNotEmpty) {
        final firstHole = _round!.course.holes[0];
        LatLng fallbackPosition;

        if (firstHole.teeBoxes.isNotEmpty) {
          fallbackPosition = firstHole.teeBoxes[0].position;
        } else if (firstHole.routingLine.isNotEmpty) {
          fallbackPosition = firstHole.routingLine.first;
        } else {
          fallbackPosition = firstHole.pin;
        }

        setState(() {
          debugPrint('Failover to course hole #1 tee');
          _currentPlayerPos = fallbackPosition;
        });
      } else {
        setState(() {
          // Fake pos: Karori golf, Wellington, NZ
          debugPrint('Failover to Karori course');
          _currentPlayerPos = const LatLng(-41.2866, 174.7772);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Loading ${widget.courseName}...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_round == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _errorMessage ?? 'Failed to load course data.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    int? distFront, distPin, distBack;
    if (_round!.course.holes.isNotEmpty && _currentPlayerPos != null) {
      final hole = _round!.course.holes[_currentHoleIndex];
      final pos = _currentPlayerPos!;
      final dist = const Distance();

      distPin = (dist.as(LengthUnit.Meter, pos, hole.pin) * 1.09361).round();

      // Front = green polygon point closest to player
      // Back  = green polygon point farthest from player
      // Filter to points within 60m of pin to exclude outlier polygon nodes.
      final greenPoints = hole.greens
          .expand((g) => g.points)
          .where((pt) => dist.as(LengthUnit.Meter, hole.pin, pt) < 60)
          .toList();
      if (greenPoints.isNotEmpty) {
        double minM = double.infinity, maxM = 0;
        for (final pt in greenPoints) {
          final m = dist.as(LengthUnit.Meter, pos, pt);
          if (m < minM) minM = m;
          if (m > maxM) maxM = m;
        }
        distFront = (minM * 1.09361).round();
        distBack  = (maxM * 1.09361).round();
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            // ---- MAP ---
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(-41.2895, 174.6938),
              initialZoom: 16.0,
              interactionOptions: InteractionOptions(
                flags: _draggingShotIdx != null
                    ? InteractiveFlag.none
                    : InteractiveFlag.all,
              ),
              onTap: (tapPosition, point) => setState(() {
                _rulerTarget = point;
              }),
            ),
            children: [
              // --- map tiles ---
              TileLayer(
                urlTemplate: _isSatellite
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.golfapp',
              ),
              PolygonLayer(
                polygons: [
                  for (final hole in _round!.course.holes) ...[
                    for (final fw in hole.fairways)
                      Polygon(
                        points: fw.points,
                        color: _getColorForFeature(fw.tags['golf']),
                        borderColor: Colors.white,
                        borderStrokeWidth: 1,
                      ),
                    for (final g in hole.greens)
                      Polygon(
                        points: g.points,
                        color: _getColorForFeature(g.tags['golf']),
                        borderColor: Colors.white,
                        borderStrokeWidth: 1,
                      ),
                    for (final tp in hole.teePlatforms)
                      if (tp.points.isNotEmpty)
                        Polygon(
                          points: tp.orientedRect(
                            hole.routingLine.length >= 2
                                ? const Distance().bearing(
                                    hole.routingLine.first,
                                    hole.routingLine[1])
                                : 0.0,
                          ),
                          color: _getColorForFeature(tp.tags['golf']),
                          borderColor: Colors.white,
                          borderStrokeWidth: 0.5,
                        ),
                  ],
                ],
              ),
              PolylineLayer(
                polylines: [
                  // --- cart paths ---
                  for (final path in _round!.course.cartPaths)
                    Polyline(
                      points: path,
                      color: Colors.brown.withValues(alpha: 0.7),
                      strokeWidth: 2,
                    ),
                  // --- play line for current hole ---
                  if (_round!.course.holes.isNotEmpty)
                    Polyline(
                      points: _round!.course.holes[_currentHoleIndex].routingLine,
                      color: Colors.white.withValues(alpha: 0.7),
                      strokeWidth: 2,
                      pattern: StrokePattern.dashed(segments: const [12, 6]),
                    ),
                  // --- GPS breadcrumb trail ---
                  if (_breadcrumb.length >= 2)
                    Polyline(
                      points: _breadcrumb,
                      color: Colors.cyan.withValues(alpha: 0.6),
                      strokeWidth: 2,
                      pattern: StrokePattern.dashed(segments: const [6, 12]),
                    ),
                  // --- parabolic shot arcs for current hole (review mode) ---
                  if (widget.reviewRound != null)
                    for (final (i, shot) in _currentHoleShots().indexed)
                      if (shot.endLocation != null)
                        Polyline(
                          points: _arcPoints(
                            _committedShotPositions[i] ?? shot.startLocation,
                            // Shot i ends where shot i+1 starts — use the
                            // committed position of i+1 if it was moved.
                            _committedShotPositions[i + 1] ?? shot.endLocation!,
                            i,
                          ),
                          color: Colors.greenAccent.withValues(alpha: 1.0),
                          strokeWidth: 2,
                        ),
                ],
              ),
              if (_currentPlayerPos != null) // --- curr pos ---
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPlayerPos!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              if (_round!.course.holes.isNotEmpty) ...[
                // --- pin ---
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _round!.course.holes[_currentHoleIndex].pin,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.flag, color: Colors.red, size: 30),
                    ),
                  ],
                ),
                // --- tee: teeBox nodes first, teePlatform centroids as fallback ---
                Builder(builder: (context) {
                  final hole = _round!.course.holes[_currentHoleIndex];
                  final List<LatLng> teePositions = [
                    ...hole.teeBoxes.map((t) => t.position),
                    if (hole.teeBoxes.isEmpty)
                      for (final tp in hole.teePlatforms.where((tp) => tp.points.isNotEmpty))
                        LatLng(
                          tp.points.map((p) => p.latitude).reduce((a, b) => a + b) / tp.points.length,
                          tp.points.map((p) => p.longitude).reduce((a, b) => a + b) / tp.points.length,
                        ),
                  ];
                  return MarkerLayer(
                    markers: [
                      for (final pos in teePositions)
                        Marker(
                          point: pos,
                          width: 40,
                          height: 40,
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _selectedTee = pos);
                              _fitMapToHole();
                            },
                            child: const SizedBox.shrink(),
                          ),
                        ),
                    ],
                  );
                }),
              ],
              if (_rulerTarget != null) // --- ruler ---
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _rulerTarget!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.orange,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              // --- shot distance labels (review mode) ---
              if (widget.reviewRound != null)
                MarkerLayer(
                  markers: [
                    for (final (i, shot) in _currentHoleShots().indexed)
                      if (shot.endLocation != null)
                        Marker(
                          point: _arcMidpoint(
                            _committedShotPositions[i] ?? shot.startLocation,
                            _committedShotPositions[i + 1] ?? shot.endLocation!,
                            i,
                          ),
                          width: 48,
                          height: 20,
                          child: _DistanceLabel(
                            yards: (const Distance().as(
                                      LengthUnit.Meter,
                                      _committedShotPositions[i] ??
                                          shot.startLocation,
                                      _committedShotPositions[i + 1] ??
                                          shot.endLocation!,
                                    ) *
                                    1.09361)
                                .round(),
                          ),
                        ),
                  ],
                ),
              // --- hit-detected position markers ---
              if (_hitPositions.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final pos in _hitPositions)
                      Marker(
                        point: pos,
                        width: 20,
                        height: 20,
                        child: const _HitMarker(),
                      ),
                  ],
                ),
              // --- shot markers for current hole (review mode) ---
              if (widget.reviewRound != null)
                MarkerLayer(
                  markers: [
                    for (final (i, shot) in _currentHoleShots().indexed)
                      Marker(
                        point: _draggedShotPositions[i] ?? shot.startLocation,
                        width: 28,
                        height: 28,
                        child: GestureDetector(
                          onTap: () => _showShotEditor(i),
                          onPanStart: (_) =>
                              setState(() => _draggingShotIdx = i),
                          onPanUpdate: (d) => _onShotDragUpdate(i, d),
                          onPanEnd: (_) => _onShotDragEnd(),
                          child: _ShotMarker(
                            label: _clubLabel(shot.club),
                            dragging: _draggingShotIdx == i,
                            penalty: shot.penalty,
                            isTeeShot: shot.isTeeShot,
                            isRecovery: shot.isRecovery,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          // --- satellite toggle: top-left ---
          Positioned(
            top: 10,
            left: 16,
            child: GestureDetector(
              onTap: () => setState(() => _isSatellite = !_isSatellite),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _isSatellite ? Icons.map : Icons.satellite,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          // --- distance badge: top-right (play mode only) ---
          if (widget.reviewRound == null)
          Positioned(
            top: 10,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _currentPlayerPos == null
                  ? const Text('Locating...',
                      style: TextStyle(color: Colors.white70, fontSize: 14))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (distBack != null)
                          _DistRow(label: 'B', value: distBack!, color: Colors.white70),
                        _DistRow(label: 'P', value: distPin ?? 0, color: Colors.greenAccent),
                        if (distFront != null)
                          _DistRow(label: 'F', value: distFront!, color: Colors.white70),
                      ],
                    ),
            ),
          ),
          // --- hole nav: bottom ---
          if (_round!.course.holes.isNotEmpty)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 15),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        final total = _round!.course.holes.length;
                        setState(() {
                          _currentHoleIndex = (_currentHoleIndex - 1 + total) % total;
                          _selectedTee = null;
                          _initCommittedPositionsForHole();
                        });
                        _fitMapToHoleView(_currentHoleIndex);
                        _pushWatchContext();
                      },
                    ),
                    GestureDetector(
                      onTap: () => _showHoleMenu(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            'Hole ${_round!.course.holes[_currentHoleIndex].holeNumber}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Par ${_round!.course.holes[_currentHoleIndex].par}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward, color: Colors.white),
                      onPressed: () {
                        final total = _round!.course.holes.length;
                        setState(() {
                          _currentHoleIndex = (_currentHoleIndex + 1) % total;
                          _selectedTee = null;
                          _initCommittedPositionsForHole();
                        });
                        _fitMapToHoleView(_currentHoleIndex);
                        _pushWatchContext();
                      },
                    ),
                  ],
                ),
              ),
            ),
          // --- stroke editor: bottom-right, above hole nav ---
          if (_round!.course.holes.isNotEmpty)
            Positioned(
              bottom: 90,
              right: 16,
              child: _strokeEditing
                  ? Container(
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, color: Colors.white),
                            onPressed: () => setState(() {
                              final cur = _strokes[_currentHoleIndex] ?? 0;
                              if (cur > 0) _strokes[_currentHoleIndex] = cur - 1;
                            }),
                          ),
                          Text(
                            '${_strokes[_currentHoleIndex] ?? 0}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, color: Colors.white),
                            onPressed: () => setState(() {
                              final cur = _strokes[_currentHoleIndex] ?? 0;
                              _strokes[_currentHoleIndex] = cur + 1;
                            }),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.greenAccent),
                            onPressed: () => setState(() => _strokeEditing = false),
                          ),
                        ],
                      ),
                    )
                  : GestureDetector(
                      onTap: () => setState(() => _strokeEditing = true),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Center(
                          child: Text(
                            '${_strokes[_currentHoleIndex] ?? 0}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  void _showHoleMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.white),
              title: const Text('Exit to main page',
                  style: TextStyle(color: Colors.white)),
              onTap: () async {
                if (_round != null) {
                  final isReview = widget.reviewRound != null;
                  final updated = _round!.copyWith(
                    trail: isReview
                        ? _round!.trail
                        : List.unmodifiable(_breadcrumb),
                    hitPositions: isReview
                        ? _round!.hitPositions
                        : List.unmodifiable(_hitPositions),
                    holePlays: _buildHolePlaysFromStrokes(),
                  );
                  await RoundRepository(db).updateRound(_round!.id, updated);
                }
                if (context.mounted) {
                  Navigator.pop(context); // close sheet
                  Navigator.pop(context); // exit round page
                }
              },
            ),
            if (widget.reviewRound != null && _round != null)
              ListTile(
                leading: const Icon(Icons.table_rows, color: Colors.white),
                title: const Text('View scorecard',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RoundScorecardPage(round: _round!),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.sports_golf, color: Colors.white),
              title: const Text('Manage clubs',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                // TODO: navigate to club manager
              },
            ),
          ],
        ),
      ),
    );
  }

  /// LatLng at the peak (t=0.5) of the shot arc bezier.
  LatLng _arcMidpoint(LatLng start, LatLng end, int idx) {
    final dlat = end.latitude - start.latitude;
    final dlon = end.longitude - start.longitude;
    final sign = idx.isEven ? 1.0 : -1.0;
    final perpLat = -dlon * 0.20 * sign;
    final perpLon = dlat * 0.20 * sign;
    final ctrlLat = (start.latitude + end.latitude) / 2 + perpLat;
    final ctrlLon = (start.longitude + end.longitude) / 2 + perpLon;
    return LatLng(
      0.25 * start.latitude + 0.5 * ctrlLat + 0.25 * end.latitude,
      0.25 * start.longitude + 0.5 * ctrlLon + 0.25 * end.longitude,
    );
  }

  /// Quadratic bezier arc between [start] and [end].
  /// Control point is offset 8% of chord length perpendicular to the line,
  /// alternating sides per shot index to avoid overlapping chips/putts.
  List<LatLng> _arcPoints(LatLng start, LatLng end, int idx,
      {int steps = 14}) {
    final dlat = end.latitude - start.latitude;
    final dlon = end.longitude - start.longitude;
    final sign = idx.isEven ? 1.0 : -1.0;
    // Perpendicular to chord, scaled to 8% of chord length
    final perpLat = -dlon * 0.20 * sign;
    final perpLon = dlat * 0.20 * sign;
    final ctrlLat = (start.latitude + end.latitude) / 2 + perpLat;
    final ctrlLon = (start.longitude + end.longitude) / 2 + perpLon;
    return [
      for (int i = 0; i <= steps; i++)
        () {
          final t = i / steps;
          final mt = 1 - t;
          return LatLng(
            mt * mt * start.latitude + 2 * mt * t * ctrlLat + t * t * end.latitude,
            mt * mt * start.longitude + 2 * mt * t * ctrlLon + t * t * end.longitude,
          );
        }(),
    ];
  }

  /// Seed _committedShotPositions from the current hole's shot starts so that
  /// arcs and markers share the exact same LatLng objects from the first render,
  /// avoiding floating-point drift from the JSON round-trip.
  void _initCommittedPositionsForHole() {
    _committedShotPositions.clear();
    _draggedShotPositions.clear();
    _draggingShotIdx = null;
    final shots = _currentHoleShots();
    for (int i = 0; i < shots.length; i++) {
      _committedShotPositions[i] = shots[i].startLocation;
    }
  }

  void _onShotDragUpdate(int shotIdx, DragUpdateDetails details) {
    final shots = _currentHoleShots();
    if (shotIdx >= shots.length) return;
    final currentPos =
        _draggedShotPositions[shotIdx] ?? shots[shotIdx].startLocation;
    final camera = _mapController.camera;
    // Markers live inside MobileLayerTransformer (Transform.rotate).
    // Flutter's hit-test inverse means details.delta is already in the
    // pre-rotation Stack space, which is world-pixel space (east=+x, south=+y).
    // No rotation correction needed — just offset the world pixel position.
    final worldPx = camera.projectAtZoom(currentPos);
    setState(() {
      _draggingShotIdx = shotIdx;
      _draggedShotPositions[shotIdx] =
          camera.unprojectAtZoom(worldPx + details.delta);
    });
  }

  void _onShotDragEnd() {
    if (_round == null || _draggedShotPositions.isEmpty) {
      setState(() => _draggingShotIdx = null);
      return;
    }
    final holeNum = _currentHoleIndex + 1;
    final updatedHolePlays = _round!.holePlays.map((hp) {
      if (hp.holeNumber != holeNum) return hp;
      final shots = List.generate(hp.shots.length, (i) {
        final newPos = _draggedShotPositions[i];
        if (newPos == null) return hp.shots[i];
        final s = hp.shots[i];
        return s.copyWith(startLocation: newPos);
      });
      return HolePlay(holeNumber: holeNum, shots: shots);
    }).toList();
    setState(() {
      _round = _round!.copyWith(holePlays: updatedHolePlays);
      _committedShotPositions.addAll(_draggedShotPositions);
      _draggingShotIdx = null;
    });
    RoundRepository(db).updateRound(_round!.id, _round!);
  }

  List<Shot> _currentHoleShots() {
    if (_round == null) return [];
    final holeNum = _currentHoleIndex + 1;
    return _round!.holePlays
        .where((hp) => hp.holeNumber == holeNum)
        .expand((hp) => hp.shots)
        .toList();
  }

  /// Call this when a swing/hit is detected to record the current GPS position.
  void recordHit() {
    if (_currentPlayerPos == null) return;
    setState(() => _hitPositions.add(_currentPlayerPos!));
  }

  void _pushWatchContext() {
    if (_round == null || _round!.course.holes.isEmpty) return;
    final hole = _round!.course.holes[_currentHoleIndex];
    final dist = _currentPlayerPos != null
        ? (const Distance().as(LengthUnit.Meter, _currentPlayerPos!, hole.pin) * 1.09361).round()
        : 0;
    WatchService.instance.sendContext(
      holeNumber: hole.holeNumber,
      par: hole.par,
      distanceYards: dist,
    );
  }

  void _showShotEditor(int shotIdx) {
    final shots = _currentHoleShots();
    if (shotIdx >= shots.length) return;
    final shot = shots[shotIdx];
    showModalBottomSheet<Shot?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShotEditorSheet(shot: shot),
    ).then((updated) {
      if (updated == null) return;
      final holeNum = _currentHoleIndex + 1;
      final updatedHolePlays = _round!.holePlays.map((hp) {
        if (hp.holeNumber != holeNum) return hp;
        final newShots = List<Shot>.from(hp.shots);
        newShots[shotIdx] = updated;
        return HolePlay(holeNumber: holeNum, shots: newShots);
      }).toList();
      setState(() => _round = _round!.copyWith(holePlays: updatedHolePlays));
      RoundRepository(db).updateRound(_round!.id, _round!);
    });
  }

  String _clubLabel(Club? club) {
    if (club == null) return 'Pen';
    for (final (label, c) in _kBagClubs) {
      if (c.name == club.name) return label;
    }
    switch (club.type) {
      case ClubType.driver:
        return 'Dr';
      case ClubType.wood:
        return '${club.number}w';
      case ClubType.hybrid:
        return '${club.number}h';
      case ClubType.putter:
        return 'P';
      default:
        return club.number.isNotEmpty ? '${club.number}i' : '?';
    }
  }

  /// Rebuild holePlays from the stroke counter, preserving existing shot data.
  List<HolePlay> _buildHolePlaysFromStrokes() {
    if (_round == null) return [];
    final holeCount = _round!.course.holes.isNotEmpty
        ? _round!.course.holes.length
        : (_strokes.keys.isEmpty ? 0 : _strokes.keys.reduce((a, b) => a > b ? a : b) + 1);
    return List.generate(holeCount, (i) {
      final holeNum = i + 1;
      final target = _strokes[i] ?? 0;
      final existing =
          _round!.holePlays.where((hp) => hp.holeNumber == holeNum).firstOrNull;
      if (target == 0) return existing ?? HolePlay(holeNumber: holeNum, shots: []);
      final shots = existing?.shots ?? [];
      if (shots.length == target) return existing!;
      if (shots.length > target) {
        return HolePlay(holeNumber: holeNum, shots: shots.sublist(0, target));
      }
      final base = shots.isNotEmpty ? shots.last : null;
      final extra = List.generate(
        target - shots.length,
        (_) => Shot(
          startLocation: base?.endLocation ?? base?.startLocation ??
              _currentPlayerPos ?? const LatLng(0, 0),
          club: base?.club,
          lieType: LieType.fairway,
        ),
      );
      return HolePlay(holeNumber: holeNum, shots: [...shots, ...extra]);
    });
  }

  Color _getColorForFeature(String? featureType) {
    switch (featureType) {
      case 'green':
        return Colors.green.withOpacity(0.5);
      case 'tee':
        return Colors.green.withOpacity(0.7);
      case 'fairway':
        return Colors.lightGreen.withOpacity(0.5);
      case 'bunker':
        return Colors.yellow.withOpacity(0.5);
      case 'water_hazard':
        return Colors.blue.withOpacity(0.7);
      default:
        return Colors.grey.withOpacity(0.5);
    }
  }

  void _fitMapToHole() {
    if (_selectedTee == null ||
        _round == null ||
        _round!.course.holes.isEmpty) {
      debugPrint(
        'round_page::_fitMapToHole: selected tee: $_selectedTee, round: $_round',
      );
      return;
    }

    final pin = _round!.course.holes[_currentHoleIndex].pin;
    final bounds = LatLngBounds.fromPoints([_selectedTee!, pin]);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
    );
  }

  void _fitMapToHoleView(int holeIndex) {
    if (_round == null || _round!.course.holes.isEmpty) return;

    final hole = _round!.course.holes[holeIndex];
    final pin = hole.pin;
    final routing = hole.routingLine;

    // Use the OSM routing line for bearing — it's oriented tee→pin by the parser.
    final double bearing = routing.length >= 2
        ? const Distance().bearing(routing.first, routing[1])
        : 0.0;

    // Hole length drives zoom — fitCamera + rotation is unreliable for large
    // bearing angles because the rotated viewport clips the axis-aligned bounds.
    final double meters = routing.length >= 2
        ? const Distance().as(LengthUnit.Meter, routing.first, routing.last)
        : 300.0;

    final double zoom = meters < 120
        ? 18.5
        : meters < 200
            ? 18.0
            : meters < 300
                ? 17.5
                : meters < 420
                    ? 17.0
                    : meters < 520
                        ? 16.5
                        : 16.0;

    // Centre on routing midpoint so both tee and pin are equidistant from centre.
    final mid = routing.length >= 2
        ? LatLng(
            (routing.first.latitude + routing.last.latitude) / 2,
            (routing.first.longitude + routing.last.longitude) / 2,
          )
        : pin;

    _mapController.moveAndRotate(mid, zoom, -bearing);
  }
}

class _DistRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _DistRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 11)),
        const SizedBox(width: 6),
        Text('$value',
            style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        Text('yds',
            style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 11)),
      ],
    );
  }
}

class _ShotMarker extends StatelessWidget {
  final String label;
  final bool dragging;
  final bool penalty;
  final bool isTeeShot;
  final bool isRecovery;

  const _ShotMarker({
    required this.label,
    this.dragging = false,
    this.penalty = false,
    this.isTeeShot = false,
    this.isRecovery = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = penalty
        ? Colors.redAccent
        : isTeeShot
            ? Colors.lightBlueAccent
            : isRecovery
                ? Colors.orangeAccent
                : Colors.yellow;
    final borderColor = dragging ? Colors.white : accent;
    final borderWidth = dragging ? 2.5 : 1.5;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: dragging ? accent.withValues(alpha: 0.25) : Colors.black87,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: accent,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Club bag used in the shot editor
// ---------------------------------------------------------------------------

final _kBagClubs = [
  ('Dr',  Club(name: 'Driver',  brand: '', number: '1',  type: ClubType.driver, loft: 10)),
  ('3w',  Club(name: '3 Wood',  brand: '', number: '3',  type: ClubType.wood,   loft: 15)),
  ('5w',  Club(name: '5 Wood',  brand: '', number: '5',  type: ClubType.wood,   loft: 18)),
  ('7w',  Club(name: '7 Wood',  brand: '', number: '7',  type: ClubType.wood,   loft: 21)),
  ('3h',  Club(name: '3 Hybrid', brand: '', number: '3', type: ClubType.hybrid, loft: 19)),
  ('4h',  Club(name: '4 Hybrid', brand: '', number: '4', type: ClubType.hybrid, loft: 22)),
  ('5h',  Club(name: '5 Hybrid', brand: '', number: '5', type: ClubType.hybrid, loft: 25)),
  ('3i',  Club(name: '3 Iron',  brand: '', number: '3',  type: ClubType.iron,   loft: 21)),
  ('4i',  Club(name: '4 Iron',  brand: '', number: '4',  type: ClubType.iron,   loft: 24)),
  ('5i',  Club(name: '5 Iron',  brand: '', number: '5',  type: ClubType.iron,   loft: 27)),
  ('6i',  Club(name: '6 Iron',  brand: '', number: '6',  type: ClubType.iron,   loft: 30)),
  ('7i',  Club(name: '7 Iron',  brand: '', number: '7',  type: ClubType.iron,   loft: 34)),
  ('8i',  Club(name: '8 Iron',  brand: '', number: '8',  type: ClubType.iron,   loft: 38)),
  ('9i',  Club(name: '9 Iron',  brand: '', number: '9',  type: ClubType.iron,   loft: 42)),
  ('PW',  Club(name: 'PW',      brand: '', number: 'P',  type: ClubType.iron,   loft: 46)),
  ('GW',  Club(name: 'GW',      brand: '', number: 'G',  type: ClubType.iron,   loft: 50)),
  ('SW',  Club(name: 'SW',      brand: '', number: 'S',  type: ClubType.iron,   loft: 54)),
  ('LW',  Club(name: 'LW',      brand: '', number: 'L',  type: ClubType.iron,   loft: 58)),
  ('P',   Club(name: 'Putter',  brand: '', number: 'P',  type: ClubType.putter, loft: 4)),
];

class _ShotEditorSheet extends StatelessWidget {
  final Shot shot;
  const _ShotEditorSheet({required this.shot});

  void _pop(BuildContext context, Shot updated) =>
      Navigator.pop(context, updated);

  @override
  Widget build(BuildContext context) {
    final club = shot.club;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'Edit stroke',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // flags row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _FlagChip(
                  label: 'Penalty',
                  color: Colors.redAccent,
                  selected: shot.penalty,
                  onTap: () => _pop(context,
                      Shot(
                        startLocation: shot.startLocation,
                        endLocation: shot.endLocation,
                        club: shot.penalty ? shot.club : null,
                        lieType: shot.lieType,
                        penalty: !shot.penalty,
                        isTeeShot: shot.isTeeShot,
                        isRecovery: shot.isRecovery,
                      )),
                ),
                const SizedBox(width: 8),
                _FlagChip(
                  label: 'Tee shot',
                  color: Colors.lightBlueAccent,
                  selected: shot.isTeeShot,
                  onTap: () => _pop(context,
                      Shot(
                        startLocation: shot.startLocation,
                        endLocation: shot.endLocation,
                        club: shot.club,
                        lieType: shot.lieType,
                        penalty: shot.penalty,
                        isTeeShot: !shot.isTeeShot,
                        isRecovery: shot.isRecovery,
                      )),
                ),
                const SizedBox(width: 8),
                _FlagChip(
                  label: 'Recovery',
                  color: Colors.orangeAccent,
                  selected: shot.isRecovery,
                  onTap: () => _pop(context,
                      Shot(
                        startLocation: shot.startLocation,
                        endLocation: shot.endLocation,
                        club: shot.club,
                        lieType: shot.lieType,
                        penalty: shot.penalty,
                        isTeeShot: shot.isTeeShot,
                        isRecovery: !shot.isRecovery,
                      )),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // club grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (label, c) in _kBagClubs)
                  GestureDetector(
                    onTap: () => _pop(context,
                        Shot(
                          startLocation: shot.startLocation,
                          endLocation: shot.endLocation,
                          club: c,
                          lieType: shot.lieType,
                          penalty: false,
                          isTeeShot: shot.isTeeShot,
                          isRecovery: shot.isRecovery,
                        )),
                    child: Container(
                      width: 44,
                      height: 36,
                      decoration: BoxDecoration(
                        color: club?.name == c.name
                            ? Colors.yellow
                            : const Color(0xFF2C2C2C),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: club?.name == c.name
                              ? Colors.yellow
                              : Colors.white24,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: club?.name == c.name
                                ? Colors.black
                                : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _FlagChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FlagChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.white24,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : Colors.white54,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _HitMarker extends StatelessWidget {
  const _HitMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.cyanAccent, width: 1.5),
      ),
      child: const Center(
        child: Text(
          '+',
          style: TextStyle(
            color: Colors.cyanAccent,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _DistanceLabel extends StatelessWidget {
  final int yards;

  const _DistanceLabel({required this.yards});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$yards y',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
