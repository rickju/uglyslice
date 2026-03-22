import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'models/round.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'models/course.dart';
import 'services/course_repository.dart';
import 'main.dart' show db;

// page widget
class RoundPage extends StatefulWidget {
  final String courseId;
  final String courseName;

  const RoundPage({super.key, required this.courseId, required this.courseName});

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

    final player = Player(name: 'Rick');
    setState(() {
      _round = Round(player: player, course: golfCourse, date: DateTime.now());
      _isLoading = false;
    });
    debugPrint('Holes loaded for ${widget.courseName}: ${_round!.course.holes.length}');
    _determinePosition();
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

    int distanceInYards = 0;
    LatLng? targetGreen;
    if (_round!.course.holes.isNotEmpty) {
      targetGreen = _round!.course.holes[_currentHoleIndex].pin;
    }

    if (_currentPlayerPos != null && targetGreen != null) {
      double meters = const Distance().as(
        LengthUnit.Meter,
        _currentPlayerPos!,
        targetGreen,
      );
      distanceInYards = (meters * 1.09361).round();
    }

    return Scaffold(
      // toolbar
      appBar: AppBar(
        title: Text(
          _round!.course.holes.isNotEmpty
              ? 'Hole ${_round!.course.holes[_currentHoleIndex].holeNumber}'
              : 'Golf App',
        ),
        actions: [
          IconButton(
            icon: Icon(_isSatellite ? Icons.map : Icons.satellite),
            onPressed: () {
              setState(() {
                _isSatellite = !_isSatellite;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            // ---- MAP ---
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(-41.2895, 174.6938),
              initialZoom: 16.0,
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
                      if (tp.boundingRect.isNotEmpty)
                        Polygon(
                          points: tp.boundingRect,
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
                            child: Icon(
                              Icons.location_on,
                              color: _selectedTee == pos ? Colors.purple : Colors.orange,
                              size: 30,
                            ),
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
            ],
          ),
          // --- distance badge: top-right ---
          Positioned(
            top: 10,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _currentPlayerPos == null
                    ? 'Locating...'
                    : '$distanceInYards YDS',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
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
                        if (_currentHoleIndex > 0) {
                          setState(() {
                            _currentHoleIndex--;
                            _selectedTee = null;
                          });
                          _fitMapToHoleView(_currentHoleIndex);
                        }
                      },
                    ),
                    Text(
                      'Hole ${_round!.course.holes[_currentHoleIndex].holeNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward, color: Colors.white),
                      onPressed: () {
                        if (_currentHoleIndex <
                            _round!.course.holes.length - 1) {
                          setState(() {
                            _currentHoleIndex++;
                            _selectedTee = null;
                          });
                          _fitMapToHoleView(_currentHoleIndex);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
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
