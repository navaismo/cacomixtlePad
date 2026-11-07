import 'dart:math' as math;

/// Modal state is updated only after a command is acknowledged by the printer.
class PrinterModalState {
  bool? millimeters;
  bool? absoluteAxes;
  bool? relativeExtrusion;
  double? stepperIdleSeconds;
  final homed = <String>{};

  void reset() {
    millimeters = absoluteAxes = relativeExtrusion = null;
    stepperIdleSeconds = null;
    homed.clear();
  }

  void acknowledge(String command) {
    final text = command
        .split(';')
        .first
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .trim()
        .toUpperCase();
    final code = RegExp(r'^([GMT]\d+)(?=[^\d.]|$)').firstMatch(text)?.group(1);
    switch (code) {
      case 'G20':
        millimeters = false;
        break;
      case 'G21':
        millimeters = true;
        break;
      case 'G90':
        absoluteAxes = true;
        relativeExtrusion = false;
        break;
      case 'G91':
        absoluteAxes = false;
        relativeExtrusion = true;
        break;
      case 'M82':
        relativeExtrusion = false;
        break;
      case 'M83':
        relativeExtrusion = true;
        break;
      case 'G28':
        final axes = RegExp('[XYZ]')
            .allMatches(text.substring(3))
            .map((m) => m.group(0)!)
            .toSet();
        homed.addAll(axes.isEmpty ? ['X', 'Y', 'Z'] : axes);
        break;
      case 'M18':
      case 'M84':
        final timeout = RegExp('S\\s*$_number').firstMatch(text);
        if (timeout != null) {
          final seconds = double.tryParse(timeout.group(1)!);
          stepperIdleSeconds =
              seconds != null && seconds.isFinite && seconds >= 0
                  ? seconds
                  : null;
        } else {
          homed.clear();
        }
        break;
      case 'M112':
      case 'M999':
        homed.clear();
        break;
    }
  }

  bool get canPark =>
      millimeters != null &&
      absoluteAxes != null &&
      relativeExtrusion != null &&
      homed.containsAll(['X', 'Y', 'Z']);
}

const _number = r'([+-]?(?:\d+(?:\.\d*)?|\.\d+))';

class FirmwarePosition {
  final double x, y, z, e;
  const FirmwarePosition(this.x, this.y, this.z, this.e);

  static FirmwarePosition? parse(String report) {
    final match = RegExp(
            '(?:^|\\s)X:\\s*$_number\\s+Y:\\s*$_number\\s+Z:\\s*$_number(?:\\s+E:\\s*$_number)?',
            multiLine: true,
            caseSensitive: false)
        .firstMatch(report);
    if (match == null) return null;
    final values = [
      for (var i = 1; i <= 4; i++) double.tryParse(match.group(i) ?? '0')
    ];
    if (values.any((v) => v == null || !v.isFinite)) return null;
    return FirmwarePosition(values[0]!, values[1]!, values[2]!, values[3]!);
  }

  bool closeTo(FirmwarePosition other) =>
      (x - other.x).abs() <= 0.05 &&
      (y - other.y).abs() <= 0.05 &&
      (z - other.z).abs() <= 0.05 &&
      (e - other.e).abs() <= 0.05;
}

class TravelLimits {
  final FirmwarePosition minimum, maximum;
  const TravelLimits(this.minimum, this.maximum);

  static TravelLimits? parse(String report) {
    final on =
        RegExp(r'(?:Soft endstops:\s*On\b|\bM211\s+S1\b)', caseSensitive: false)
            .hasMatch(report);
    final min = RegExp(r'\bMin:\s*(.*?)(?=\bMax:|$)',
            caseSensitive: false, dotAll: true)
        .firstMatch(report);
    final max = RegExp(r'\bMax:\s*(.*)', caseSensitive: false, dotAll: true)
        .firstMatch(report);
    if (!on || min == null || max == null) return null;
    final low = FirmwarePosition.parse(min.group(1)!);
    final high = FirmwarePosition.parse(max.group(1)!);
    if (low == null ||
        high == null ||
        low.x >= high.x ||
        low.y >= high.y ||
        low.z >= high.z) {
      return null;
    }
    return TravelLimits(low, high);
  }

  bool contains(FirmwarePosition p) =>
      p.x >= minimum.x &&
      p.x <= maximum.x &&
      p.y >= minimum.y &&
      p.y <= maximum.y &&
      p.z >= minimum.z &&
      p.z <= maximum.z;
}

class ParkSnapshot {
  final FirmwarePosition original, parked;
  final bool millimeters, absoluteAxes, relativeExtrusion;
  final bool limitedLift;
  const ParkSnapshot(
      {required this.original,
      required this.parked,
      required this.millimeters,
      required this.absoluteAxes,
      required this.relativeExtrusion,
      required this.limitedLift});

  static ParkSnapshot? create(
      PrinterModalState mode, FirmwarePosition position, TravelLimits limits) {
    if (!mode.canPark || !limits.contains(position)) return null;
    final z = math.min(position.z + 30, limits.maximum.z);
    // Do not traverse the print with less than 5 mm of vertical clearance.
    if (z - position.z < 5) return null;
    final y = math.max(position.y, limits.maximum.y - 5);
    return ParkSnapshot(
        original: position,
        parked: FirmwarePosition(position.x, y, z, position.e),
        millimeters: mode.millimeters!,
        absoluteAxes: mode.absoluteAxes!,
        relativeExtrusion: mode.relativeExtrusion!,
        limitedLift: z - position.z < 29.99);
  }

  // No E or F parameters: keep the extruder coordinate and modal feedrate intact.
  List<String> get parkCommands => [
        'G21',
        'G90',
        'G0 Z${parked.z.toStringAsFixed(3)}',
        'G0 Y${parked.y.toStringAsFixed(3)}',
        'M400'
      ];
  List<String> get restoreCommands => [
        'G0 X${original.x.toStringAsFixed(3)} Y${original.y.toStringAsFixed(3)}',
        'G0 Z${original.z.toStringAsFixed(3)}',
        'M400',
      ];
  List<String> get restoreModes => [
        millimeters ? 'G21' : 'G20',
        absoluteAxes ? 'G90' : 'G91',
        relativeExtrusion ? 'M83' : 'M82'
      ];
}
