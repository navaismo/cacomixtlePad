import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'responsive_layout.dart';

Color meshColor(double value, double extent) => value < 0
    ? Color.lerp(const Color(0xff293d46), const Color(0xff69c8ef),
        (-value / extent).clamp(0.0, 1.0))!
    : Color.lerp(const Color(0xff293d46), const Color(0xffffa18b),
        (value / extent).clamp(0.0, 1.0))!;

String meshHeight(double z) => '${z > 0 ? '+' : ''}${z.toStringAsFixed(3)} mm';

class BedMesh extends StatefulWidget {
  final List<List<double>> grid;
  final math.Point<int>? selected;
  final ValueChanged<math.Point<int>>? onSelected;
  const BedMesh(
      {super.key, required this.grid, this.selected, this.onSelected});
  @override
  State<BedMesh> createState() => _BedMeshState();
}

class _BedMeshState extends State<BedMesh> {
  bool _surface = false;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grid = widget.grid;
    final values = grid.expand((row) => row);
    final low = values.reduce(math.min), high = values.reduce(math.max);
    final extent = math.max(0.05, math.max(low.abs(), high.abs()));
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
                showCheckmark: false,
                label: Text('Mesh_heatmap'.tr()),
                avatar: const Icon(Icons.grid_view_rounded, size: 18),
                selected: !_surface,
                onSelected: (_) => setState(() => _surface = false)),
            ChoiceChip(
                showCheckmark: false,
                label: Text('Mesh_surface'.tr()),
                avatar: const Icon(Icons.landscape_outlined, size: 18),
                selected: _surface,
                onSelected: (_) => setState(() => _surface = true)),
          ]),
          const SizedBox(height: 16),
          if (_surface)
            AspectRatio(
                aspectRatio: 1.35,
                child: ClipRect(
                    child: CustomPaint(painter: _SurfacePainter(grid))))
          else ...[
            Text('Mesh_rear'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, constraints) {
              final width = math.max(
                  constraints.maxWidth, (grid.first.length * 78 + 36) * scale);
              return Scrollbar(
                controller: _scroll,
                thumbVisibility: width > constraints.maxWidth,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                      width: width,
                      child: Column(children: [
                        Row(children: [
                          SizedBox(width: 36 * scale),
                          for (var x = 0; x < grid.first.length; x++)
                            Expanded(
                                child:
                                    Text('X$x', textAlign: TextAlign.center)),
                        ]),
                        const SizedBox(height: 6),
                        for (var y = grid.length - 1; y >= 0; y--)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(children: [
                                SizedBox(width: 36 * scale, child: Text('Y$y')),
                                for (var x = 0; x < grid[y].length; x++)
                                  Expanded(
                                      child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 3),
                                    child: Semantics(
                                      label:
                                          'X$x, Y$y, ${meshHeight(grid[y][x])}',
                                      selected:
                                          widget.selected == math.Point(x, y),
                                      button: true,
                                      child: Material(
                                        color: meshColor(grid[y][x], extent),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            side: BorderSide(
                                                width: widget.selected ==
                                                        math.Point(x, y)
                                                    ? 2
                                                    : 1,
                                                color: widget.selected ==
                                                        math.Point(x, y)
                                                    ? Colors.white
                                                    : Colors.white12)),
                                        child: InkWell(
                                          key: ValueKey('mesh-$x-$y'),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          onTap: widget.onSelected == null
                                              ? null
                                              : () => widget.onSelected!(
                                                  math.Point(x, y)),
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                minHeight: 56),
                                            child: Padding(
                                                padding: const EdgeInsets.symmetric(
                                                    vertical: 18,
                                                    horizontal: 4),
                                                child: Text(
                                                    grid[y][x]
                                                        .toStringAsFixed(3),
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: ThemeData.estimateBrightnessForColor(
                                                                    meshColor(
                                                                        grid[y]
                                                                            [x],
                                                                        extent)) ==
                                                                Brightness.light
                                                            ? const Color(
                                                                0xff10242f)
                                                            : Colors.white))),
                                          ),
                                        ),
                                      ),
                                    ),
                                  )),
                              ])),
                      ])),
                ),
              );
            }),
            const SizedBox(height: 4),
            Text('Mesh_front'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium),
          ],
          const SizedBox(height: 16),
          Container(
              height: 8,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(colors: [
                    meshColor(-extent, extent),
                    meshColor(0, extent),
                    meshColor(extent, extent)
                  ]))),
          const SizedBox(height: 8),
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(meshHeight(-extent)),
                const Text('0 mm'),
                Text(meshHeight(extent))
              ]),
        ]),
      ),
    );
  }
}

class BedMeshInfo extends StatelessWidget {
  final List<List<double>> grid;
  final math.Point<int>? selected;
  const BedMeshInfo({super.key, required this.grid, this.selected});

  @override
  Widget build(BuildContext context) {
    final values = grid.expand((row) => row);
    final low = values.reduce(math.min), high = values.reduce(math.max);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            selected == null
                ? 'Mesh_select'.tr()
                : 'X${selected!.x} · Y${selected!.y} · ${meshHeight(grid[selected!.y][selected!.x])}',
            key: const ValueKey('mesh-selection'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ControlWrap(minWidth: 100, maxColumns: 3, children: [
            _MeshStat(label: 'Mesh_min'.tr(), value: meshHeight(low)),
            _MeshStat(label: 'Mesh_max'.tr(), value: meshHeight(high)),
            _MeshStat(label: 'Mesh_range'.tr(), value: meshHeight(high - low)),
          ]),
        ]),
      ),
    );
  }
}

class _MeshStat extends StatelessWidget {
  final String label, value;
  const _MeshStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

class _SurfacePainter extends CustomPainter {
  final List<List<double>> grid;

  _SurfacePainter(this.grid);

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

        final col = meshColor(grid[iy][ix],
            math.max(0.05, math.max(minZval.abs(), maxZval.abs())));
        colors.add(col);
      }
    }

    // Fit the projected mesh below the statistics instead of using a fixed zoom.
    final left = positions.map((p) => p.dx).reduce(math.min);
    final right = positions.map((p) => p.dx).reduce(math.max);
    final top = positions.map((p) => p.dy).reduce(math.min);
    final bottom = positions.map((p) => p.dy).reduce(math.max);
    const padding = 24.0;
    const statsHeight = 0.0;
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
      ..color = Colors.white.withValues(alpha: 0.18);

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
  }

  @override
  bool shouldRepaint(covariant _SurfacePainter old) =>
      !listEquals(old.grid, grid);
}
