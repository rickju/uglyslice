import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:golf_track_app/models/round.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

class RoundPage extends StatefulWidget {
  final Round round;

  const RoundPage({super.key, required this.round});

  @override
  State<RoundPage> createState() => _RoundPageState();
}

class _RoundPageState extends State<RoundPage> {
  LatLng? _currentPalyerPos;
  int _currentHoleIndex = 0;
  LatLng? _selectedTee;
  LatLng? _rulerTarget;
  bool _isSatellite = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _determinePosition();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.round.course.holes.isNotEmpty) {
        _fitMapToHoleView(0);
      }
    });
  }

  Future<void> _determinePosition() async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).listen((Position position) {
        final newPos = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPalyerPos = newPos;
        });

        if (widget.round.course.holes.isNotEmpty) {
          final targetGreen = widget.round.course.holes[_currentHoleIndex].pin;
          final bearing = const Distance().bearing(newPos, targetGreen);
          _mapController.rotate(-bearing);
        }
      });
    } else {
      setState(() {
        _currentPalyerPos = const LatLng(-41.2866, 174.7772); // Wellington, NZ
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    int distanceInYards = 0;
    LatLng? targetGreen;
    if (widget.round.course.holes.isNotEmpty) {
      targetGreen = widget.round.course.holes[_currentHoleIndex].pin;
    }
    
    if (_currentPalyerPos != null && targetGreen != null) {
      double meters = const Distance().as(LengthUnit.Meter, _currentPalyerPos!, targetGreen);
      distanceInYards = (meters * 1.09361).round();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.round.course.holes.isNotEmpty
            ? 'Hole ${widget.round.course.holes[_currentHoleIndex].holeNumber}'
            : 'Golf App'),
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
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(-41.2895, 174.6938),
              initialZoom: 16.0,
              onTap: (tapPosition, point) => setState(() {
                _rulerTarget = point;
              }),
            ),
            children: [
              TileLayer(
                urlTemplate: _isSatellite
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.golfapp',
              ),
              PolygonLayer(polygons: [
                for (var feature in widget.round.course.features)
                  Polygon(
                    points: feature.points,
                    color: _getColorForFeature(feature.tags['golf']),
                    borderColor: Colors.white,
                    borderStrokeWidth: 1,
                  ),
              ]),
              if (_currentPalyerPos != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _currentPalyerPos!,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
                  ),
                ]),
              if (widget.round.course.holes.isNotEmpty)
                MarkerLayer(markers: [
                  for (var tee in widget.round.course.holes[_currentHoleIndex].tees)
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
                          color: _selectedTee == tee.position ? Colors.purple : Colors.red,
                          size: 30,
                        ),
                      ),
                    ),
                ]),
              if (_rulerTarget != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _rulerTarget!,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_pin, color: Colors.orange, size: 30),
                  ),
                ]),
            ],
          ),
          if (widget.round.course.holes.isNotEmpty)
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
                            _selectedTee = null;
                            _fitMapToHoleView(_currentHoleIndex);
                          }
                        });
                      },
                    ),
                    Text(
                      'Hole ${widget.round.course.holes[_currentHoleIndex].holeNumber}',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          if (_currentHoleIndex < widget.round.course.holes.length - 1) {
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
                      const Expanded(child: Text('Distance to green center', style: TextStyle(color: Colors.white70, fontSize: 16))),
                      Text(
                        _currentPalyerPos == null ? "Locating..." : '$distanceInYards YDS',
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 36, fontWeight: FontWeight.bold),
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
              if (_currentPalyerPos != null && widget.round.course.holes.isNotEmpty) {
                final targetGreen = widget.round.course.holes[_currentHoleIndex].pin;
                final bearing = const Distance().bearing(_currentPalyerPos!, targetGreen);
                _mapController.moveAndRotate(_currentPalyerPos!, 16.0, -bearing);
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
              if (_currentPalyerPos != null) {
                print('Recording shot at: $_currentPalyerPos');
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
    if (_selectedTee == null || widget.round.course.holes.isEmpty) {
      return;
    }

    final pin = widget.round.course.holes[_currentHoleIndex].pin;
    final bounds = LatLngBounds.fromPoints([_selectedTee!, pin]);
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)));
  }

  void _fitMapToHoleView(int holeIndex) {
    if (widget.round.course.holes.isEmpty) return;

    final hole = widget.round.course.holes[holeIndex];
    final points = [hole.pin, ...hole.tees.map((t) => t.position)];

    if (points.isEmpty) {
      _mapController.move(hole.pin, 16);
      return;
    }

    final bounds = LatLngBounds.fromPoints(points);

    LatLng centerOfTees;
    if (hole.tees.isNotEmpty) {
      double totalLat = 0;
      double totalLng = 0;
      for (var tee in hole.tees) {
        totalLat += tee.position.latitude;
        totalLng += tee.position.longitude;
      }
      centerOfTees = LatLng(totalLat / hole.tees.length, totalLng / hole.tees.length);
    } else {
      _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)));
      return;
    }
    
    final bearing = const Distance().bearing(centerOfTees, hole.pin);

    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
    );
    _mapController.rotate(-bearing);
  }
}
