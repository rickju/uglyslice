import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:golf_track_app/models/golf_course.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';

void main() => runApp(const MaterialApp(home: GolfPhaseOne()));

class GolfPhaseOne extends StatefulWidget {
  const GolfPhaseOne({super.key});

  @override
  State<GolfPhaseOne> createState() => _GolfPhaseOneState();
}

class _GolfPhaseOneState extends State<GolfPhaseOne> {
  LatLng? _currentPalyerPos;
  GolfCourse? _golfCourse;
  int _currentHoleIndex = 0;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _loadGolfCourse();
  }

  Future<void> _loadGolfCourse() async {
    final String data = await rootBundle.loadString('karori_golf.json');
    setState(() {
      _golfCourse = GolfCourse.fromJson(data);
      print('Golf course loaded with ${_golfCourse!.holes.length} holes.');
    });
  }

  /// 获取并监听用户实时位置
  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    // 持续监听位置变化
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).listen((Position position) {
      setState(() {
        _currentPalyerPos = LatLng(position.latitude, position.longitude);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // 计算距离（米转码）
    int distanceInYards = 0;
    LatLng? targetGreen;
    if (_golfCourse != null && _golfCourse!.holes.isNotEmpty) {
      targetGreen = _golfCourse!.holes[_currentHoleIndex].pin;
    }
    
    if (_currentPalyerPos != null && targetGreen != null) {
      double meters = const Distance().as(LengthUnit.Meter, _currentPalyerPos!, targetGreen);
      distanceInYards = (meters * 1.09361).round();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Four Celsius')),
      body: Stack(
        children: [
          // 1. 地图视图
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _golfCourse != null && _golfCourse!.holes.isNotEmpty ? _golfCourse!.holes[0].pin : const LatLng(-41.2895, 174.6938),
              initialZoom: 16.0,
            ),
            children: [
              // 使用 OpenStreetMap 数据源
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.golfapp',
              ),
              if (_golfCourse != null)
                PolygonLayer(polygons: [
                  for (var feature in _golfCourse!.features)
                    Polygon(
                      points: feature.points,
                      color: _getColorForFeature(feature.tags['golf']),
                      borderColor: Colors.white,
                      borderStrokeWidth: 1,
                    ),
                ]),
              // 玩家位置标记
              if (_currentPalyerPos != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _currentPalyerPos!,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
                  ),
                ]),

              // 梯台位置标记
              if (_golfCourse != null && _golfCourse!.holes.isNotEmpty)
                MarkerLayer(markers: [
                  for (var tee in _golfCourse!.holes[_currentHoleIndex].tees)
                    Marker(
                      point: tee,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 30),
                    ),
                ]),
            ],
          ),
          // Hole selection UI
          if (_golfCourse != null && _golfCourse!.holes.isNotEmpty)
            Positioned(
              top: 10,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
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
                        setState(() {
                          if (_currentHoleIndex > 0) {
                            _currentHoleIndex--;
                            _mapController.move(_golfCourse!.holes[_currentHoleIndex].pin, 16.0);
                          }
                        });
                      },
                    ),
                    Text(
                                            'Hole ${_golfCourse!.holes[_currentHoleIndex].holeNumber}',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          if (_currentHoleIndex < _golfCourse!.holes.length - 1) {
                            _currentHoleIndex++;
                            _mapController.move(_golfCourse!.holes[_currentHoleIndex].pin, 16.0);
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

          // 2. 距离显示面板
          Positioned(
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
                      const Text('Distance to green center', style: TextStyle(color: Colors.white70, fontSize: 16)),
                      Text(
                        _currentPalyerPos == null ? "Locating..." : '$distanceInYards YDS',
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 36, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Distance to nearest tee', style: TextStyle(color: Colors.white70, fontSize: 16)),
                      Text(
                        _getDistanceToNearestTee(),
                        style: const TextStyle(color: Colors.redAccent, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      // 快速回到自己位置的按钮
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_currentPalyerPos != null) {
            _mapController.move(_currentPalyerPos!, 16.0);
          }
        },
        child: const Icon(Icons.gps_fixed),
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

  String _getDistanceToNearestTee() {
    if (_currentPalyerPos == null || _golfCourse == null || _golfCourse!.holes.isEmpty) {
      return "N/A";
    }

    final tees = _golfCourse!.holes[_currentHoleIndex].tees;
    if (tees.isEmpty) {
      return "N/A";
    }

    double minDistance = double.infinity;
    for (var tee in tees) {
      double meters = const Distance().as(LengthUnit.Meter, _currentPalyerPos!, tee);
      if (meters < minDistance) {
        minDistance = meters;
      }
    }

    int distanceInYards = (minDistance * 1.09361).round();
    return '$distanceInYards YDS';
  }
}

