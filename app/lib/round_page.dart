import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'models/round.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'models/golf_course.dart';
import 'models/player.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

// page widget
class RoundPage extends StatefulWidget {
  final String courseName;

  const RoundPage({super.key, required this.courseName});

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
  bool _isSatellite = false;

  String? _errorMessage;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadCourse();
  }

  // XXX: hard code: Karori XXX
  Future<void> _apiQuery(File file) async {
    final query = """
[out:json][timeout:25];
// 1. 查找指定名称的球场主体（可以是 Way 或 Relation）
(
  // way["leisure"="golf_course"]["name"~"佘山国际高尔夫"];
  // relation["leisure"="golf_course"]["name"~"佘山国际高尔夫"];
  node["leisure"="golf_course"]["name"="Karori Golf Club"](-47.5, 166.0, -34.0, 179.0);
  way["leisure"="golf_course"]["name"="Karori Golf Club"](-47.5, 166.0, -34.0, 179.0);
  relation["leisure"="golf_course"]["name"="Karori Golf Club"](-47.5, 166.0, -34.0, 179.0);
)->.course;
// 2. 将球场主体放入输出
.course out geom;
// 3. 递归获取该球场区域内的所有高尔夫相关设施（果岭、沙坑等）
(
  node(area.course)["golf"];
  way(area.course)["golf"];
  relation(area.course)["golf"];
);
out geom;
""";

    try {
      debugPrint('api query: $query');
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
      );

      if (response.statusCode == 200) {
        final golfCourse = CourseParser.fromJson(
          response.body,
          widget.courseName,
        );

        // if (golfCourse.holes.isNotEmpty) {
        await file.writeAsString(response.body);
        // }

        final player = Player(name: 'Rick');
        setState(() {
          _round = Round(
            player: player,
            course: golfCourse,
            date: DateTime.now(),
          );
          _isLoading = false;
        });
        debugPrint(
          'Holes loaded for ${widget.courseName}: ${_round!.course.holes.length}',
        );
        _determinePosition();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_round!.course.holes.isNotEmpty) {
            _fitMapToHoleView(0);
          }
        });
      } else {
        throw Exception('Failed to query full course data');
      }
    } catch (e) {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${widget.courseName.replaceAll(' ', '_')}.json';
      final expectedPath = '${directory.path}/$fileName';

      setState(() {
        _isLoading = false;
        _errorMessage =
            'api query failed for ${widget.courseName}.\n\n'
            'To use a cached file, please place it at:\n$expectedPath';
      });
    }
  } // _apiQuery

  Future<void> _loadCourse() async {
    final directory = await getApplicationDocumentsDirectory();
    final fileName = '${widget.courseName.replaceAll(' ', '_')}.json';
    final file = File('${directory.path}/$fileName');

    debugPrint('Looking for local cached course file at: ${file.path}');
    if (await file.exists()) {
      try {
        final jsonString = await file.readAsString();
        final golfCourse = CourseParser.fromJson(jsonString, widget.courseName);
        final player = Player(name: 'Rick');
        setState(() {
          _round = Round(
            player: player,
            course: golfCourse,
            date: DateTime.now(),
          );
          _isLoading = false;
        });
        debugPrint(
          'Holes loaded for ${widget.courseName}: ${_round!.course.holes.length}',
        );
        _determinePosition();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_round!.course.holes.isNotEmpty) {
            _fitMapToHoleView(0);
          }
        });
        return;
      } catch (e) {
        debugPrint('failed to load local course json file, error: $e');
        // Fallback to network if cache is invalid
        // XXX await _apiQuery(file); XXX
      }
    }
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

        if (firstHole.tees.isNotEmpty) {
          fallbackPosition = firstHole.tees[0].position;
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
                // --- course border ---
                polygons: [
                  for (var feature in _round!.course.features)
                    Polygon(
                      points: feature.points,
                      color: _getColorForFeature(feature.tags['golf']),
                      borderColor: Colors.white,
                      borderStrokeWidth: 1,
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
              if (_round!.course.holes.isNotEmpty) // --- tee ----
                MarkerLayer(
                  markers: [
                    for (var tee
                        in _round!.course.holes[_currentHoleIndex].tees)
                      Marker(
                        point: tee.position,
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedTee = tee.position;
                            });
                            _fitMapToHole();
                          },
                          child: Icon(
                            Icons.location_on,
                            color: _selectedTee == tee.position
                                ? Colors.purple
                                : Colors.red,
                            size: 30,
                          ),
                        ),
                      ),
                  ],
                ),
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
          if (_round!.course.holes.isNotEmpty)
            Positioned(
              // --- top toolbar ---
              top: 10,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 15,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      // --- button: Previous Hole ---
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          if (_currentHoleIndex > 0) {
                            _currentHoleIndex--;
                            _selectedTee = null;
                            _fitMapToHoleView(_currentHoleIndex);
                          }
                        });
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
                      // --- button: Next Hole ----
                      icon: const Icon(
                        Icons.arrow_forward,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          if (_currentHoleIndex <
                              _round!.course.holes.length - 1) {
                            _currentHoleIndex++;
                            _selectedTee = null;
                            _fitMapToHoleView(_currentHoleIndex);
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            // --- bottom toolbar ---
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 25),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Distance to green center',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                      Text(
                        _currentPlayerPos == null
                            ? "Locating..."
                            : '$distanceInYards YDS',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'gps_button',
            onPressed: () {
              if (_currentPlayerPos != null &&
                  _round!.course.holes.isNotEmpty) {
                final targetGreen = _round!.course.holes[_currentHoleIndex].pin;
                final bearing = const Distance().bearing(
                  _currentPlayerPos!,
                  targetGreen,
                );
                _mapController.moveAndRotate(
                  _currentPlayerPos!,
                  16.0,
                  -bearing,
                );
              }
            },
            child: const Icon(Icons.gps_fixed),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'add_shot_button',
            onPressed: () {
              // This is where you would record a shot.
              // For now, it just prints the current location.
              if (_currentPlayerPos != null) {
                debugPrint('Recording shot at: $_currentPlayerPos');
              }
            },
            child: const Icon(Icons.add),
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
        return Colors.blue.withOpacity(0.5);
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
    debugPrint('round_page::_fitMapToHoleView: selected tee: $_selectedTee');
    if (_round == null || _round!.course.holes.isEmpty) {
      return;
    }

    // hole boundary
    final hole = _round!.course.holes[holeIndex];
    debugPrint('round_page::_fitMapToHoleView: hole #: ${hole.holeNumber}');
    debugPrint('pin: ${hole.pin}');
    debugPrint('tee num: ${hole.tees.length}');

    // ------------------------------
    final pin = hole.pin;
    if (hole.tees.isEmpty) {
      _mapController.move(pin, 16);
      return;
    }
    final LatLng teePosition = hole.tees[0].position;
    // 1. 基础点集：包含旗杆和发球台
    final List<LatLng> points = [
      hole.pin,
      ...hole.tees.map((Tee t) => t.position),
    ];
    debugPrint(
      'points: \n${points.map((p) => "(${p.latitude}, ${p.longitude})").join("\n")}',
    );

    // 2. 计算距离以确定动态 Padding (方案 3)
    const Distance distanceCalculator = Distance();
    final double meters = distanceCalculator.as(
      LengthUnit.Meter,
      pin,
      teePosition,
    );

    // 根据球洞长度决定边距
    double dynamicPadding = meters < 150 ? 100.0 : 60.0;

    // 3. 使用 v8.x 推荐的 fitCamera 方法
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: EdgeInsets.all(dynamicPadding),
        // 方案 2：限制最大缩放，防止只有一个 Tee 时缩放过深
        maxZoom: 18.0,
        // 方案 3：如果需要，可以设置 minZoom 防止缩放得太小看不了全景
        minZoom: 3.0,
      ),
    );

    debugPrint('fitCamera: Distance ${meters.toStringAsFixed(1)}m');
    // ------------------------------

    if (points.isEmpty) {
      _mapController.move(hole.pin, 16);
      return;
    }

    final bounds = LatLngBounds.fromPoints(points);
    debugPrint(bounds.toString());
    LatLng centerOfTees;
    if (hole.tees.isNotEmpty) {
      double totalLat = 0;
      double totalLng = 0;
      for (var tee in hole.tees) {
        totalLat += tee.position.latitude;
        totalLng += tee.position.longitude;
      }
      centerOfTees = LatLng(
        totalLat / hole.tees.length,
        totalLng / hole.tees.length,
      );
    } else {
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
      );
      return;
    }

    final bearing = const Distance().bearing(centerOfTees, hole.pin);

    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
    );
    _mapController.rotate(-bearing);
  }
}
