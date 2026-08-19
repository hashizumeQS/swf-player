import 'basic_types.dart';
import 'character.dart';
import 'timeline.dart';

/// RGBA色（各要素0〜255）。アルファ省略時は不透明（0xFF）。
class RgbaColor {
  const RgbaColor(this.r, this.g, this.b, [this.a = 0xFF]);

  /// 赤成分（0〜255）。
  final int r;

  /// 緑成分（0〜255）。
  final int g;

  /// 青成分（0〜255）。
  final int b;

  /// アルファ成分（0〜255）。省略時は不透明（0xFF）。
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

  /// SWFファイルフォーマットバージョン（ヘッダの3バイト目）。
  final int version;

  /// ステージの境界矩形（twips座標系）。
  final SwfRect stageRect;

  /// 1秒あたりのフレーム数（8.8固定小数点由来のdouble）。
  final double frameRate;

  /// メインタイムラインのフレーム総数（ヘッダ由来の宣言値）。
  final int frameCount;

  /// ステージの背景色。SetBackgroundColorタグが無い場合はnull。
  final RgbaColor? backgroundColor;

  /// characterId → Character
  final Map<int, Character> dictionary;

  /// メインのフレーム・タイムライン。
  final Timeline mainTimeline;
}
