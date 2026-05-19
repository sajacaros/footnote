import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/walk_models.dart';

class LocationTracker {
  static const trackingInterval = Duration(seconds: 2);

  StreamSubscription<Position>? _subscription;

  Future<bool> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<TrackPoint?> currentPoint() async {
    if (!await ensurePermission()) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
      ),
    );
    return _pointFromPosition(position);
  }

  Future<bool> start({
    required void Function(TrackPoint point) onPoint,
  }) async {
    if (!await ensurePermission()) {
      return false;
    }

    _subscription = Geolocator.getPositionStream(
      locationSettings: _trackingSettings(),
    ).listen((position) {
      onPoint(_pointFromPosition(position));
    });

    return true;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  TrackPoint _pointFromPosition(Position position) {
    return TrackPoint(
      position: LatLng(position.latitude, position.longitude),
      recordedAt: position.timestamp,
      elevation: position.altitude,
      accuracy: position.accuracy,
      speed: position.speed,
    );
  }

  LocationSettings _trackingSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: trackingInterval,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
  }
}
