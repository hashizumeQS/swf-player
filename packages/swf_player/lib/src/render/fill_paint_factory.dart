import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:swf_core/swf_core.dart';

/// CXFORM適用済みの色を返す。
ui.Color transformColor(RgbaColor c, SwfCxform cx) {
  if (cx.isIdentity) {
    return ui.Color.fromARGB(c.a, c.r, c.g, c.b);
  }
  int apply(int v, int mult, int add) =>
      ((v * mult) ~/ 256 + add).clamp(0, 255);
  return ui.Color.fromARGB(
    apply(c.a, cx.aMult, cx.aAdd),
    apply(c.r, cx.rMult, cx.rAdd),
    apply(c.g, cx.gMult, cx.gAdd),
    apply(c.b, cx.bMult, cx.bAdd),
  );
}

/// SWFのグラデーション正方形の半径（twips）。
/// グラデーションは(-16384,-16384)-(16384,16384)の正方形に定義され、
/// スタイルのMATRIXでシェイプ座標系へ変換される。
const _gradientRadiusTwips = 16384.0;

/// 塗りスタイル → Paint（bitmapはStagePainter側でImageShader化される）。
ui.Paint paintForFill(FillStyle style, SwfCxform cxform) {
  final paint = ui.Paint()..isAntiAlias = true;
  switch (style) {
    case SolidFill():
      paint.color = transformColor(style.color, cxform);
    case GradientFill():
      if (style.stops.isEmpty) {
        paint.color = transformColor(const RgbaColor(0, 0, 0), cxform);
        break;
      }
      final colors =
          style.stops.map((s) => transformColor(s.color, cxform)).toList();
      final ratios = style.stops.map((s) => s.ratio / 255.0).toList();
      // 単一ストップはグラデーションにできないためソリッド扱い
      if (colors.length == 1) {
        paint.color = colors.single;
        break;
      }
      final m = style.matrix;
      final matrix4 = Float64List(16)
        ..[0] = m.scaleX
        ..[1] = m.rotateSkew0
        ..[4] = m.rotateSkew1
        ..[5] = m.scaleY
        ..[10] = 1
        ..[12] = m.translateX.toDouble()
        ..[13] = m.translateY.toDouble()
        ..[15] = 1;
      paint.shader = style.isRadial
          ? ui.Gradient.radial(
              ui.Offset.zero,
              _gradientRadiusTwips,
              colors,
              ratios,
              ui.TileMode.clamp,
              matrix4,
            )
          : ui.Gradient.linear(
              const ui.Offset(-_gradientRadiusTwips, 0),
              const ui.Offset(_gradientRadiusTwips, 0),
              colors,
              ratios,
              ui.TileMode.clamp,
              matrix4,
            );
    case BitmapFill():
      // 画像未ロード時のフォールバック（未実装が視認できる色）
      paint.color = const ui.Color(0xFFFF00FF);
  }
  return paint;
}

ui.Paint paintForLine(LineStyle style, SwfCxform cxform) {
  return ui.Paint()
    ..isAntiAlias = true
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = style.widthTwips.toDouble()
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round
    ..color = transformColor(style.color, cxform);
}
