import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'signal_dictionary.dart';

class GraphicMessage extends StatelessWidget {
  const GraphicMessage({super.key, required this.spheres, this.onTap});

  final List<GraphicSphere> spheres;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: onTap == null ? null : 'OPEN 3D VIEWER',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: const Color(0xff020704),
              border: Border.all(color: const Color(0xff246e1a)),
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _GraphicScenePainter(spheres),
                    isComplex: true,
                    child: const SizedBox.expand(),
                  ),
                ),
                if (onTap != null)
                  const Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.open_in_full, size: 18),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GraphicViewerScreen extends StatefulWidget {
  const GraphicViewerScreen({super.key, required this.spheres});

  final List<GraphicSphere> spheres;

  @override
  State<GraphicViewerScreen> createState() => _GraphicViewerScreenState();
}

class _GraphicViewerScreenState extends State<GraphicViewerScreen> {
  double _yaw = 0;
  double _pitch = 0;
  double _zoom = 1;
  double _gestureYaw = 0;
  double _gesturePitch = 0;
  double _gestureZoom = 1;
  Offset _gestureStart = Offset.zero;

  void _resetView() {
    setState(() {
      _yaw = 0;
      _pitch = 0;
      _zoom = 1;
    });
  }

  void _startGesture(ScaleStartDetails details) {
    _gestureYaw = _yaw;
    _gesturePitch = _pitch;
    _gestureZoom = _zoom;
    _gestureStart = details.focalPoint;
  }

  void _updateGesture(ScaleUpdateDetails details) {
    setState(() {
      _yaw = _gestureYaw + (details.focalPoint.dx - _gestureStart.dx) * .01;
      _pitch = (_gesturePitch +
              (details.focalPoint.dy - _gestureStart.dy) * .01)
          .clamp(-math.pi / 2, math.pi / 2)
          .toDouble();
      _zoom = (_gestureZoom * details.scale).clamp(.5, 4).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D VIEWER'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'RESET VIEW',
            onPressed: _resetView,
          ),
        ],
      ),
      body: ColoredBox(
        color: const Color(0xff020704),
        child: GestureDetector(
          onScaleStart: _startGesture,
          onScaleUpdate: _updateGesture,
          onDoubleTap: _resetView,
          behavior: HitTestBehavior.opaque,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _GraphicScenePainter(
                widget.spheres,
                yaw: _yaw,
                pitch: _pitch,
                zoom: _zoom,
                drawGrid: false,
              ),
              isComplex: true,
              willChange: true,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _GraphicScenePainter extends CustomPainter {
  _GraphicScenePainter(
    this.spheres, {
    this.yaw = 0,
    this.pitch = 0,
    this.zoom = 1,
    this.drawGrid = true,
  });

  final List<GraphicSphere> spheres;
  final double yaw;
  final double pitch;
  final double zoom;
  final bool drawGrid;

  static const _gradient = <Color>[
    Color(0xffff5800),
    Color(0xffbbff00),
    Color(0xff00cdff),
    Color(0xff0084ff),
    Color(0xff4d00ff),
    Color(0xfffb39ff),
    Color(0xffff0fd7),
    Color(0xff484848),
    Color(0xff636363),
    Color(0xffffffff),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (drawGrid) {
      final gridPaint = Paint()
        ..color = const Color(0xff246e1a)
        ..strokeWidth = 1;
      for (final y in [size.height * .14, size.height * .86]) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
        for (var column = -2; column <= 6; column++) {
          final start = Offset(column * size.width / 4, y);
          final end = Offset(
            size.width / 2 + (column - 2) * size.width / 10,
            size.height / 2,
          );
          canvas.drawLine(start, end, gridPaint);
        }
      }
    }

    _paintRayTracedSpheres(canvas, size);
  }

  void _paintRayTracedSpheres(Canvas canvas, Size size) {
    const cameraDistance = 18.5;
    const maximumRayIntersections = 100000;
    final scale = _sceneScale(size) * zoom;
    final baseSampleSize = drawGrid ? 3.0 : 2.0;
    final sampleSize = math.max(
      baseSampleSize,
      math.sqrt(
        size.width * size.height * spheres.length / maximumRayIntersections,
      ),
    );
    final samplesByColor = <Color, List<Offset>>{};
    final cameraSpheres = spheres
        .map(
          (sphere) => (
            center: _cameraCoordinates(sphere),
            radius: sphere.radius,
            color: _colorFor(sphere.color),
          ),
        )
        .toList();

    for (var screenY = 0.0; screenY < size.height; screenY += sampleSize) {
      for (var screenX = 0.0; screenX < size.width; screenX += sampleSize) {
        final rayX = (screenX - size.width / 2) / scale;
        final rayZ = -(screenY - size.height / 2) / scale;
        final rayLength = math.sqrt(
          rayX * rayX + rayZ * rayZ + cameraDistance * cameraDistance,
        );
        final direction = (
          x: rayX / rayLength,
          z: rayZ / rayLength,
          depth: -cameraDistance / rayLength,
        );
        _RayHit? closestHit;
        for (final sphere in cameraSpheres) {
          final hit = _intersectRaySphere(direction, sphere.center, sphere.radius);
          if (hit != null && (closestHit == null || hit.distance < closestHit.distance)) {
            closestHit = _RayHit(
              distance: hit.distance,
              normal: hit.normal,
              color: sphere.color,
            );
          }
        }
        if (closestHit != null) {
          final color = _shadeSurface(closestHit.color, closestHit.normal);
          samplesByColor.putIfAbsent(color, () => []).add(
            Offset(screenX + sampleSize / 2, screenY + sampleSize / 2),
          );
        }
      }
    }
    for (final entry in samplesByColor.entries) {
      canvas.drawPoints(
        ui.PointMode.points,
        entry.value,
        Paint()
          ..color = entry.key
          ..strokeWidth = sampleSize + .5
          ..strokeCap = StrokeCap.square,
      );
    }
  }

  ({double distance, ({double x, double z, double depth}) normal})?
      _intersectRaySphere(
    ({double x, double z, double depth}) direction,
    ({double x, double z, double depth}) center,
    double radius,
  ) {
    final relativeDepth = center.depth - 18.5;
    final projection = center.x * direction.x +
      center.z * direction.z +
      relativeDepth * direction.depth;
    final centerDistanceSquared = center.x * center.x +
      center.z * center.z +
      relativeDepth * relativeDepth;
    final perpendicularDistanceSquared =
        centerDistanceSquared - projection * projection;
    final radiusSquared = radius * radius;
    if (perpendicularDistanceSquared > radiusSquared) {
      return null;
    }
    final distance = projection - math.sqrt(radiusSquared - perpendicularDistanceSquared);
    if (distance <= 0) {
      return null;
    }
    return (
      distance: distance,
      normal: (
        x: (direction.x * distance - center.x) / radius,
        z: (direction.z * distance - center.z) / radius,
        depth: (direction.depth * distance - relativeDepth) / radius,
      ),
    );
  }

  Color _shadeSurface(
    Color color,
    ({double x, double z, double depth}) normal,
  ) {
    const lightX = -.45;
    const lightZ = .55;
    const lightDepth = 1.0;
    const lightLength = 1.237;
    final diffuse = math.max(
      0.0,
      (normal.x * lightX + normal.z * lightZ + normal.depth * lightDepth) /
          lightLength,
    );
    final brightness = .16 + diffuse * .84;
    final quantizedBrightness = (brightness * 15).round() / 15;
    return Color.lerp(Colors.black, color, quantizedBrightness)!
      .withValues(alpha: 1);
  }

  ({Offset point, double scale}) _project(GraphicSphere sphere, Size size) {
    const cameraDistance = 18.5;
    final coordinates = _cameraCoordinates(sphere);
    final depth = math.max(2.0, cameraDistance - coordinates.depth);
    final scale = cameraDistance / depth * zoom;
    return (
      point: Offset(
        size.width / 2 + coordinates.x * scale * _sceneScale(size),
        size.height / 2 - coordinates.z * scale * _sceneScale(size),
      ),
      scale: scale,
    );
  }

  double _sceneScale(Size size) => math.min(size.width / 36, size.height / 28);

  ({double x, double z, double depth}) _cameraCoordinates(
    GraphicSphere sphere,
  ) {
    final yawCosine = math.cos(yaw);
    final yawSine = math.sin(yaw);
    final frontToBack = -sphere.y;
    final x = sphere.x * yawCosine + frontToBack * yawSine;
    final depth = -sphere.x * yawSine + frontToBack * yawCosine;
    final pitchCosine = math.cos(pitch);
    final pitchSine = math.sin(pitch);
    return (
      x: x,
      z: sphere.z * pitchCosine - depth * pitchSine,
      depth: depth * pitchCosine + sphere.z * pitchSine,
    );
  }

  Color _colorFor(int value) {
    final position = value / 64 * (_gradient.length - 1);
    final low = position.floor();
    final high = position.ceil();
    return Color.lerp(_gradient[low], _gradient[high], position - low)!;
  }

  @override
  bool shouldRepaint(_GraphicScenePainter oldDelegate) =>
      oldDelegate.spheres != spheres ||
      oldDelegate.yaw != yaw ||
      oldDelegate.pitch != pitch ||
      oldDelegate.zoom != zoom ||
      oldDelegate.drawGrid != drawGrid;
}

class _RayHit {
  const _RayHit({
    required this.distance,
    required this.normal,
    required this.color,
  });

  final double distance;
  final ({double x, double z, double depth}) normal;
  final Color color;
}
