import 'dart:ui' as ui;

import 'package:swf_core/swf_core.dart';

/// シェイプ1個分の描画データ（twips座標のPath）。
class ShapeRenderData {
  const ShapeRenderData(this.fills, this.lines);

  /// 塗りスタイルと、それに対応する閉輪郭を結合したtwips座標のPathの組。
  /// 定義順＝描画順（後の要素が上に重なる）。
  final List<(FillStyle, ui.Path)> fills;

  /// 線スタイルと、それに対応するポリラインを結合したtwips座標のPathの組。
  /// 定義順＝描画順。
  final List<(LineStyle, ui.Path)> lines;
}

/// ShapeCharacter → ui.Path 変換（characterごとにキャッシュ）。
class ShapePathBuilder {
  final Map<int, ShapeRenderData> _cache = {};
  final Map<int, ui.Path> _glyphCache = {};

  /// フォントグリフのPath（EM=1024単位座標）。
  ui.Path forGlyph(FontCharacter font, int glyphIndex) {
    final key = (font.id << 16) | glyphIndex;
    return _glyphCache.putIfAbsent(key, () {
      if (glyphIndex < 0 || glyphIndex >= font.glyphs.length) {
        return ui.Path();
      }
      // グリフSHAPEは単一の暗黙塗り。輪郭再構成を流用するため
      // ダミーのソリッド塗り1つを持つShapeWithStyleに包む
      final pseudo = ShapeWithStyle(
        fillStyles: const [SolidFill(RgbaColor(0, 0, 0))],
        lineStyles: const [],
        records: font.glyphs[glyphIndex].records,
      );
      final contours = buildShapeContours(pseudo);
      final path = ui.Path()..fillType = ui.PathFillType.nonZero;
      for (final fc in contours.fills) {
        path.addPath(_toPath(fc.contours, forceClose: true), ui.Offset.zero);
      }
      return path;
    });
  }

  /// [character]の塗り・線をtwips座標のPathへ変換する（characterIdでキャッシュ、
  /// 同じcharacterに対する2回目以降の呼び出しは再構成しない）。
  ShapeRenderData forShape(ShapeCharacter character) {
    return _cache.putIfAbsent(character.id, () {
      final contours = buildShapeContours(character.shape);
      final fills = <(FillStyle, ui.Path)>[];
      for (final fc in contours.fills) {
        fills.add((fc.style, _toPath(fc.contours, forceClose: true)));
      }
      final lines = <(LineStyle, ui.Path)>[];
      for (final lc in contours.lines) {
        lines.add((lc.style, _toPath(lc.contours, forceClose: false)));
      }
      return ShapeRenderData(fills, lines);
    });
  }

  static ui.Path _toPath(List<Contour> contours, {required bool forceClose}) {
    final path = ui.Path()..fillType = ui.PathFillType.nonZero;
    for (final c in contours) {
      path.moveTo(c.startX.toDouble(), c.startY.toDouble());
      for (final s in c.segments) {
        if (s.isCurve) {
          path.quadraticBezierTo(
            s.controlX!.toDouble(),
            s.controlY!.toDouble(),
            s.anchorX.toDouble(),
            s.anchorY.toDouble(),
          );
        } else {
          path.lineTo(s.anchorX.toDouble(), s.anchorY.toDouble());
        }
      }
      if (c.isClosed || forceClose) path.close();
    }
    return path;
  }
}
