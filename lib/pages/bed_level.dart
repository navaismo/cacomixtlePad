import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:CacomixtlePad/services/usbConn_svc.dart';
import 'package:easy_localization/easy_localization.dart';

//! I dont undertand this class, but IA does so it helped to correct the code lol

class GridPoint {
  final int x, y;
  GridPoint(this.x, this.y);
  @override
  bool operator ==(Object o) => o is GridPoint && o.x == x && o.y == y;
  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}

class BedLevelPage extends StatefulWidget {
  const BedLevelPage({Key? key}) : super(key: key);
  @override
  _BedLevelPageState createState() => _BedLevelPageState();
}

class _BedLevelPageState extends State<BedLevelPage> {
  List<List<double>>? _grid2D;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGrid());
  }

  Future<void> _loadGrid() async {
    final usbService =
        Provider.of<UsbConnectionService>(context, listen: false);
    final map = await usbService.getBLGrid(context);
    if (map.isEmpty) return;

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

    setState(() => _grid2D = grid2D);
  }

  void refreshGrid() async {
    setState(() {
      _grid2D = null;
    });
    await _loadGrid();
    // refresh the heatmap in the UI
  }

  void newBedLevel(BuildContext context) async {
    final usbService =
        Provider.of<UsbConnectionService>(context, listen: false);
    dialogShow(context, 'New_BL'.tr());
    final r = await usbService.startBL(context);
    
    if (r){
 
      refreshGrid();
    }else{
      dialogShow(context, 'BL_failed'.tr());
    }
  }

  void dialogShow(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child:  Text('OK'.tr()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionCard(IconData icon, String label, VoidCallback onTap) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 50),
              const SizedBox(height: 10),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard2(String asset, String label, VoidCallback onTap) {
    final screen = MediaQuery.of(context).size;
    final isWide = screen.width > 1000;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                asset,
                width: isWide ? 60 : 50,
                height: isWide ? 60 : 50,
              ),
              const SizedBox(height: 10),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17)),
            ],
          ),
        ),
      ),
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
      body: Center(
        child: _grid2D == null
            ? const CircularProgressIndicator()
            : SizedBox(
                width: 1100, // Bigger cards
                height: 500,
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.3,
                  children: [
                    // Heatmap & stats card (left)
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Center(
                          child: CustomPaint(
                            size: const Size(420, 420),
                            painter: _HeatmapMeshPainter(
                              _grid2D!,
                              minZ: minZ,
                              maxZ: maxZ,
                              zRange: zRange,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Buttons card (right)
                    Card(
                      color: Colors.white.withAlpha((0.026 * 255).round()),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: GridView.count(
                          crossAxisCount: 2,
                          childAspectRatio: 1.5,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _buildActionCard(Icons.border_clear_rounded, 'Get_Grid'.tr(),
                                refreshGrid),
                            _buildActionCard2(
                                'assets/icons/bedlevel4.png',
                                'Start_New_Level'.tr(),
                                () => newBedLevel(context)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
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
    final cellSize = math.min(size.width / (nx + ny), size.height / (nx + ny)) *
        2; // Adjust the last number(2) to zoom in/out
    final zScale =
        8.0; // Adjust this value to change the height of Z scale mking deeper valleys and higher peaks

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

        final px = xt * cellSize + size.width / 2;
        final py = -yt * cellSize + size.height / 2;

        positions.add(Offset(px, py));

        final t = ((grid[iy][ix] - minZval) / zRangeVal).clamp(0.0, 1.0);
        final col = t < 0.5
            ? Color.lerp(Colors.blue, Colors.green, t * 2)!
            : Color.lerp(Colors.green, Colors.red, (t - 0.5) * 2)!;
        colors.add(col);
      }
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
      ..color = Colors.black.withOpacity(0.1);

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

    //final topOffset = Offset(size.width / 2, 20);
    for (int i = 0; i < stats.length; i++) {
      textPainter.text = TextSpan(text: stats[i], style: statStyle[i]);
      textPainter.layout();
      final paragraphBuilder =
          ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
            ..pushStyle(statStyle[i].getTextStyle())
            ..addText(stats[i]);
      final paragraph = paragraphBuilder.build();
      paragraph.layout(ui.ParagraphConstraints(width: size.width));
      canvas.drawParagraph(
        paragraph,
        Offset(size.width / 2 - textPainter.width / 2, i * 22),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapMeshPainter old) =>
      !listEquals(old.grid, grid) ||
      old.minZ != minZ ||
      old.maxZ != maxZ ||
      old.zRange != zRange;
}
