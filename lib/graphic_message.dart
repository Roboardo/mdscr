import 'dart:math' as math;

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
                CustomPaint(
                  painter: _GraphicScenePainter(spheres),
                  child: const SizedBox.expand(),
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
          child: CustomPaint(
            painter: _GraphicScenePainter(
              widget.spheres,
              yaw: _yaw,
              pitch: _pitch,
              zoom: _zoom,
              drawGrid: false,
            ),
            child: const SizedBox.expand(),
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

    final ordered = [...spheres]
      ..sort(
        (a, b) => _cameraCoordinates(a).depth.compareTo(
          _cameraCoordinates(b).depth,
        ),
      );
    for (final sphere in ordered) {
      final projection = _project(sphere, size);
        final sceneScale = _sceneScale(size);
      final radius = math.max(
        2.0,
          sphere.radius * projection.scale * sceneScale * 36 / 42,
      );
      final color = _colorFor(sphere.color);
      canvas.drawCircle(
        projection.point,
        radius,
          Paint()..color = color,
      );
    }
  }

  ({Offset point, double scale}) _project(GraphicSphere sphere, Size size) {
    const cameraDistance = 18.5;
    final coordinates = _cameraCoordinates(sphere);
    final depth = math.max(2.0, cameraDistance - coordinates.depth);
    final scale = cameraDistance / depth * zoom;
      final sceneScale = _sceneScale(size);
    return (
      point: Offset(
          size.width / 2 + coordinates.x * scale * sceneScale,
          size.height / 2 - coordinates.z * scale * sceneScale,
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
