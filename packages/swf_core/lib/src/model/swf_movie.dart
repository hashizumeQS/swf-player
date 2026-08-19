import 'basic_types.dart';
import 'character.dart';
import 'timeline.dart';

/// RGBA色（各要素0〜255）。アルファ省略時は不透明（0xFF）。
class RgbaColor {
  const RgbaColor(this.r, this.g, this.b, [this.a = 0xFF]);

  final int r;
  final int g;
  final int b;
  final int a;

  @override
  String toString() => 'RgbaColor($r, $g, $b, $a)';
}

/// パース済みSWFムービー全体。
class SwfMovie {
  const SwfMovie({
    required this.version,
    required this.stageRect,
    required this.frameRate,
    required this.frameCount,
    required this.backgroundColor,
    required this.dictionary,
    required this.mainTimeline,
  });

  final int version;
  final SwfRect stageRect;
  final double frameRate;
  final int frameCount;
  final RgbaColor? backgroundColor;

  /// characterId → Character
  final Map<int, Character> dictionary;

  final Timeline mainTimeline;
}
