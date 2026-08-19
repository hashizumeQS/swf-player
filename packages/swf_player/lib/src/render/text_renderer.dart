import 'package:flutter/painting.dart';
import 'package:swf_core/swf_core.dart';

import 'fill_paint_factory.dart';

/// DefineEditTextをデバイスフォント近似で描画する。
/// 変数バインドがあれば配置先クリップのスコープから値を取得する。
class EditTextRenderer {
  /// 表示テキストを解決（変数値 > 初期テキスト > 空）。
  static String resolveText(EditTextCharacter text, MovieClip? owner) {
    if (text.variableName.isNotEmpty && owner != null) {
      final value = owner.getVariable(text.variableName);
      if (value != null) return value.toFlashString();
    }
    return text.initialText ?? '';
  }

  static void paint(
    Canvas canvas,
    EditTextCharacter text,
    MovieClip? owner,
    SwfCxform cx,
  ) {
    final content = resolveText(text, owner);
    if (content.isEmpty) return;

    final color = text.textColor ?? const RgbaColor(0, 0, 0);
    final style = TextStyle(
      color: transformColor(color, cx),
      // canvasはtwips座標系なのでフォントサイズもtwips単位
      fontSize: text.fontHeightTwips.toDouble(),
      height: 1.1,
    );
    final align = switch (text.align) {
      1 => TextAlign.right,
      2 => TextAlign.center,
      3 => TextAlign.justify,
      _ => TextAlign.left,
    };
    final bounds = text.bounds;
    final maxWidth =
        (bounds.widthTwips - text.leftMarginTwips - text.rightMarginTwips)
            .toDouble()
            .clamp(0.0, double.infinity);

    final painter = TextPainter(
      text: TextSpan(text: content, style: style),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: text.isMultiline ? null : 1,
      ellipsis: text.isMultiline ? null : '',
    )..layout(minWidth: maxWidth, maxWidth: maxWidth);

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(
      bounds.xMin.toDouble(),
      bounds.yMin.toDouble(),
      bounds.xMax.toDouble(),
      bounds.yMax.toDouble(),
    ));
    painter.paint(
      canvas,
      Offset(
        (bounds.xMin + text.leftMarginTwips).toDouble(),
        bounds.yMin.toDouble(),
      ),
    );
    canvas.restore();
    painter.dispose();
  }
}
