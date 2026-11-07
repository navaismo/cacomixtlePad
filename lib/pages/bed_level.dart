import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:CacomixtlePad/services/usb_connection_service.dart';
import 'package:easy_localization/easy_localization.dart';
import '../widgets/bed_mesh.dart';
import '../widgets/responsive_layout.dart';

class BedLevelPage extends StatefulWidget {
  const BedLevelPage({super.key});
  @override
  State<BedLevelPage> createState() => _BedLevelPageState();
}

class _BedLevelPageState extends State<BedLevelPage> {
  List<List<double>>? _grid;
  String? _error;
  bool _busy = false;
  bool _probing = false;
  math.Point<int>? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGrid());
  }

  Future<void> _loadGrid({bool probe = false}) async {
    if (_busy || !mounted) return;
    final usb = context.read<UsbConnectionService>();
    setState(() {
      _busy = true;
      _probing = probe;
      _error = null;
    });
    try {
      if (probe && !await usb.startBL(context)) {
        if (mounted) {
          setState(() => _error = 'BL_failed');
        }
        return;
      }
      if (!mounted) return;
      final map = await usb.getBLGrid(context);
      if (!mounted) return;
      final xs = map.keys.map((p) => p.x).toSet().toList()..sort();
      final ys = map.keys.map((p) => p.y).toSet().toList()..sort();
      if (xs.length < 2 ||
          ys.length < 2 ||
          map.length != xs.length * ys.length ||
          map.values.any((z) => !z.isFinite)) {
        setState(() => _error = 'BL_failed');
        return;
      }
      setState(() {
        _grid = [
          for (final y in ys) [for (final x in xs) map[GridPoint(x, y)]!]
        ];
        _selected = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'BL_failed');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _probing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usb = context.watch<UsbConnectionService>();
    final enabled = !_busy && !usb.printActive && usb.isConnected;
    return Scaffold(
      appBar: AppBar(title: Text('Bed_Level_Visualizer'.tr())),
      body: PageScrollView(
          child: AdaptiveColumns(
        leadingFlex: 2,
        leading: _grid == null
            ? Card(
                child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.grid_on_rounded,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text((_error ?? 'Mesh_loading').tr(),
                          textAlign: TextAlign.center),
                    ])))
            : BedMesh(
                grid: _grid!,
                selected: _selected,
                onSelected: (point) => setState(() => _selected = point),
              ),
        trailing:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text((_probing ? 'Mesh_probing' : 'Mesh_loading').tr()),
            const SizedBox(height: 16),
          ],
          if (_error != null && _grid != null) ...[
            Text(_error!.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
          ],
          ControlWrap(minWidth: 140, maxColumns: 2, children: [
            ControlCard(
                icon: const Icon(Icons.refresh_rounded, size: 32),
                label: (_error != null ? 'Retry' : 'Get_Grid').tr(),
                enabled: enabled,
                onTap: () => _loadGrid()),
            ControlCard(
                icon: const Icon(Icons.auto_fix_high_rounded, size: 32),
                label: 'Start_New_Level'.tr(),
                enabled: enabled,
                onTap: () => _loadGrid(probe: true)),
          ]),
          if (_grid != null) ...[
            const SizedBox(height: 12),
            BedMeshInfo(grid: _grid!, selected: _selected),
          ],
        ]),
      )),
    );
  }
}
