import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../models/course.dart';
import '../models/jts.dart';

class CourseRepository {
  final _db = FirebaseFirestore.instance;

  CollectionReference get _courses => _db.collection('courses');

  Future<bool> courseExists(String courseId) async {
    final doc = await _courses.doc(courseId).get();
    return doc.exists;
  }

  /// Load course root doc + holes sub-collection from Firestore.
  /// Returns null if not found.
  Future<Course?> fetchCourse(String courseId) async {
    final doc = await _courses.doc(courseId).get();
    if (!doc.exists) return null;

    final holeDocs = await _courses
        .doc(courseId)
        .collection('holes')
        .orderBy('holeNumber')
        .get();

    final courseData = doc.data() as Map<String, dynamic>;
    final holeMaps = holeDocs.docs
        .map((d) => d.data())
        .toList();

    return Course.fromFirestore(courseData, holeMaps);
  }

  /// Save course to Firestore. Uses a batch write so root doc + all hole
  /// documents are committed atomically.
  Future<void> saveCourse(Course course) async {
    // Extract boundary points from the JTS polygon for storage.
    final boundaryPts = _extractBoundaryPoints(course);

    final batch = _db.batch();

    // Root document
    final courseRef = _courses.doc(course.id);
    batch.set(courseRef, course.toFirestoreMap(boundaryPts));

    // Hole sub-documents
    for (final hole in course.holes) {
      final holeRef = courseRef.collection('holes').doc('${hole.holeNumber}');
      batch.set(holeRef, hole.toMap());
    }

    await batch.commit();
  }

  List<LatLng> _extractBoundaryPoints(Course course) {
    try {
      final coords = course.boundary.getExteriorRing()?.getCoordinates();
      if (coords == null) return [];
      return coords
          .map((c) => LatLng(c.y, c.x))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
