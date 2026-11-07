import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:CacomixtlePad/services/usb_connection_service.dart';
import 'package:easy_localization/easy_localization.dart';
import '../widgets/responsive_layout.dart';

class BedLevelPage extends StatefulWidget {
  const BedLevelPage({super.key});
  @override
  State<BedLevelPage> createState() => _BedLevelPageState();
}

class _BedLevelPageState extends State<BedLevelPage> {
  List<List<double>>? _grid2D;
  String? _error;
  bool _levelling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGrid());
  }

  Future<void> _loadGrid() async {
    final usbService =
        Provider.of<UsbConnectionService>(context, listen: false);
    final map = await usbService.getBLGrid(context);
    if (map.isEmpty) {
      if (mounted) setState(() => _error = 'BL_failed');
      return;
    }

    final xs = map.keys.map((p) => p.x).toSet().toList()..sort();
    final ys = map.keys.map((p) => p.y).toSet().toList()..sort();
    final nx = xs.length, ny = ys.length;

    final grid2D = List<List<double>>.generate(
      ny,
      (_) => List<double>.filled(nx, 0.0),
    );

    for (final entry in map.entries) {
      final x = entry.key.x;
      final y = entry.key.y;
      final z = entry.value;
      final i = ys.indexOf(y);
      final j = xs.indexOf(x);
      if (i >= 0 && j >= 0) {
        grid2D[i][j] = z;
      }
    }

    if (mounted) setState(() => _grid2D = grid2D);
  }

  void refreshGrid() async {
    setState(() {
      _grid2D = null;
      _error = null;
    });
    await _loadGrid();
    // refresh the heatmap in the UI
  }

  void newBedLevel(BuildContext context) async {
    final usbService =
        Provider.of<UsbConnectionService>(context, listen: false);
    if (_levelling) return;
    setState(() => _levelling = true);
    final success = await usbService.startBL(context);
    if (!mounted) return;
    setState(() => _levelling = false);
    if (success) {
      refreshGrid();
    } else {
      dialogShow(this.context, 'BL_failed'.tr());
    }
  }

  void dialogShow(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.all(12),
          title: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'.tr()),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double? minZ, maxZ, zRange;
    if (_grid2D != null) {
      minZ = _grid2D![0][0];
      maxZ = _grid2D![0][0];
      for (var row in _grid2D!) {
        for (var z in row) {
          if (z < minZ!) minZ = z;
          if (z > maxZ!) maxZ = z;
        }
      }
      zRange = (maxZ! - minZ!).clamp(1e-6, double.infinity);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Bed_Level_Visualizer'.tr()),
      ),
      body: PageScrollView(
        child: _error != null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!.tr()),
                TextButton(onPressed: refreshGrid, child: Text('Retry'.tr())),
              ])
            : _grid2D == null
                ? const Center(child: CircularProgressIndicator())
                : AdaptiveColumns(
                    leading: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: ClipRect(
                              child: CustomPaint(
                            painter: _HeatmapMeshPainter(_grid2D!,
                                minZ: minZ, maxZ: maxZ, zRange: zRange),
                          )),
                        ),
                      ),
                    ),
                    trailing:
                        ControlWrap(minWidth: 160, maxColumns: 2, children: [
                      ControlCard(
                          icon:
                              const Icon(Icons.border_clear_rounded, size: 40),
                          label: 'Get_Grid'.tr(),
                          onTap: refreshGrid),
                      ControlCard(
                          icon: Image.asset('assets/icons/bedlevel4.png',
                              height: 48),
                          label: 'Start_New_Level'.tr(),
                          enabled: !_levelling,
                          onTap: () => newBedLevel(context)),
                    ]),
                  ),
      ),
    );
  }
}

class _HeatmapMeshPainter extends CustomPainter {
  final List<List<double>> grid;
  final double? minZ, maxZ, zRange;

  _HeatmapMeshPainter(this.grid, {this.minZ, this.maxZ, this.zRange});

  @override
  void paint(Canvas canvas, Size size) {
    final ny = grid.length;
    final nx = grid[0].length;
    double minZval = grid[0][0], maxZval = grid[0][0];
    for (var row in grid) {
      for (var z in row) {
        if (z < minZval) minZval = z;
        if (z > maxZval) maxZval = z;
      }
    }

    final zRangeVal = (maxZval - minZval).clamp(1e-6, double.infinity);
    const zScale = 8.0;

    final ax = -math.pi / 6;
    final ay = math.pi / 4;
    final cosA = math.cos(ax), sinA = math.sin(ax);
    final cosB = math.cos(ay), sinB = math.sin(ay);

    final positions = <Offset>[];
    final colors = <Color>[];

    for (int iy = 0; iy < ny; iy++) {
      for (int ix = 0; ix < nx; ix++) {
        final gx = ix - (nx - 1) / 2.0;
        final gz = iy - (ny - 1) / 2.0;
        final gy = (grid[iy][ix] - minZval) * zScale;

        final xt = gx * cosB + gz * sinB;
        final zt = -gx * sinB + gz * cosB;
        final yt = gy * cosA - zt * sinA;

        positions.add(Offset(xt, -yt));

        final t = ((grid[iy][ix] - minZval) / zRangeVal).clamp(0.0, 1.0);
        final col = t < 0.5
            ? Color.lerp(Colors.blue, Colors.green, t * 2)!
            : Color.lerp(Colors.green, Colors.red, (t - 0.5) * 2)!;
        colors.add(col);
      }
    }

    // Fit the projected mesh below the statistics instead of using a fixed zoom.
    final left = positions.map((p) => p.dx).reduce(math.min);
    final right = positions.map((p) => p.dx).reduce(math.max);
    final top = positions.map((p) => p.dy).reduce(math.min);
    final bottom = positions.map((p) => p.dy).reduce(math.max);
    const padding = 24.0;
    const statsHeight = 72.0;
    final availableWidth = math.max(1.0, size.width - padding * 2);
    final availableHeight =
        math.max(1.0, size.height - statsHeight - padding * 2);
    final scale = math.min(availableWidth / math.max(1e-6, right - left),
        availableHeight / math.max(1e-6, bottom - top));
    final center =
        Offset(size.width / 2, statsHeight + padding + availableHeight / 2);
    for (var i = 0; i < positions.length; i++) {
      positions[i] = center +
          Offset((positions[i].dx - (left + right) / 2) * scale,
              (positions[i].dy - (top + bottom) / 2) * scale);
    }

    final indices = <int>[];
    for (int y = 0; y < ny - 1; y++) {
      for (int x = 0; x < nx - 1; x++) {
        final i = y * nx + x;
        indices.addAll([i, i + 1, i + nx]);
        indices.addAll([i + 1, i + nx + 1, i + nx]);
      }
    }

    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      indices: indices,
      colors: colors,
    );
    canvas.drawVertices(vertices, BlendMode.modulate, Paint());

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.black.withValues(alpha: 0.1);

    for (int i = 0; i < indices.length; i += 3) {
      final p0 = positions[indices[i]];
      final p1 = positions[indices[i + 1]];
      final p2 = positions[indices[i + 2]];
      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();
      canvas.drawPath(path, stroke);
    }

    final textPainter = TextPainter(
      textAlign: TextAlign.right,
      textDirection: ui.TextDirection.ltr,
    );

    for (int iy = 0; iy < ny; iy++) {
      for (int ix = 0; ix < nx; ix++) {
        final idx = iy * nx + ix;
        final pos = positions[idx];
        final value = grid[iy][ix].toStringAsFixed(2);
        textPainter.text = TextSpan(
          text: value,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.black,
            backgroundColor: Color.fromARGB(140, 255, 255, 255),
          ),
        );
        textPainter.layout();
        canvas.save();
        canvas.translate(
            pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2);
        textPainter.paint(canvas, Offset.zero);
        canvas.restore();
      }
    }

    final stats = [
      'minZ: ${minZ?.toStringAsFixed(3) ?? minZval.toStringAsFixed(3)}',
      'maxZ: ${maxZ?.toStringAsFixed(3) ?? maxZval.toStringAsFixed(3)}',
      'zRange: ${zRange?.toStringAsFixed(3) ?? zRangeVal.toStringAsFixed(3)}',
    ];

    final statStyle = [
      const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 12, color: Colors.cyan),
      const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red),
      const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green),
    ];

    for (int i = 0; i < stats.length; i++) {
      textPainter.text = TextSpan(text: stats[i], style: statStyle[i]);
      textPainter.layout(maxWidth: size.width);
      textPainter.paint(
          canvas, Offset((size.width - textPainter.width) / 2, i * 22));
    }
    textPainter.dispose();
  }

  @override
  bool shouldRepaint(covariant _HeatmapMeshPainter old) =>
      !listEquals(old.grid, grid) ||
      old.minZ != minZ ||
      old.maxZ != maxZ ||
      old.zRange != zRange;
}
