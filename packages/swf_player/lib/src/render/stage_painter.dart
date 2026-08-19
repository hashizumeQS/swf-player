import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:swf_core/swf_core.dart';

import 'bitmap_registry.dart';
import 'fill_paint_factory.dart';
import 'shape_path_builder.dart';
import 'text_renderer.dart';

const _twipsPerPixel = 20.0;

/// SwfStageの現在状態を描画するCustomPainter。
/// repaint通知はListenable（PlayerControllerのnotifier）経由。
class StagePainter extends CustomPainter {
  StagePainter({
    required this.stage,
    required this.pathBuilder,
    required this.bitmaps,
    this.hiddenCharacterIds = const {},
    this.overridePositionsPx = const {},
    super.repaint,
  });

  final SwfStage stage;
  final ShapePathBuilder pathBuilder;
  final BitmapRegistry bitmaps;

  /// 描画から除外するcharacterId（ホスト側で不要になった旧UI等）。
  final Set<int> hiddenCharacterIds;

  /// characterId → 表示位置の上書き（px単位）。レイアウト調整用。
  final Map<int, ({double x, double y})> overridePositionsPx;

  @override
  void paint(Canvas canvas, Size size) {
    final stageWidthTwips = stage.movie.stageRect.widthTwips.toDouble();
    final scale = size.width / stageWidthTwips;
    canvas.save();
    canvas.scale(scale);

    final bg = stage.movie.backgroundColor;
    canvas.drawRect(
      Rect.fromLTWH(
          0, 0, stageWidthTwips, stage.movie.stageRect.heightTwips.toDouble()),
      Paint()
        ..color = bg != null
            ? ui.Color.fromARGB(255, bg.r, bg.g, bg.b)
            : const ui.Color(0xFFFFFFFF),
    );

    _paintNodes(canvas, stage.buildRenderTree(), SwfCxform.identity);
    canvas.restore();
  }

  /// 兄弟ノード列を深度順に描画する。clipDepth付きノードはマスクとして扱い、
  /// そのノード自身は描かず、(depth, clipDepth] の範囲のノードをクリップする。
  void _paintNodes(Canvas canvas, List<RenderNode> nodes, SwfCxform cx) {
    var clipUntil = -1;
    var clipActive = false;
    for (final node in nodes) {
      if (clipActive && node.depth > clipUntil) {
        canvas.restore();
        clipActive = false;
      }
      final clipDepth = node.clipDepth;
      if (clipDepth != null && clipDepth > 0) {
        final maskPath = _maskPathOf(node);
        if (maskPath != null) {
          canvas.save();
          canvas.clipPath(maskPath);
          clipActive = true;
          clipUntil = clipDepth;
        }
        continue; // マスクノード自身は描画しない
      }
      _paintNode(canvas, node, cx);
    }
    if (clipActive) canvas.restore();
  }

  /// マスクノードのクリップパス（ノードの行列適用済み）。
  ui.Path? _maskPathOf(RenderNode node) {
    final character = node.character;
    if (character is! ShapeCharacter) return null;
    final data = pathBuilder.forShape(character);
    final combined = ui.Path();
    for (final (_, path) in data.fills) {
      combined.addPath(path, ui.Offset.zero);
    }
    return combined.transform(_toMatrix4(node.matrix));
  }

  void _paintNode(Canvas canvas, RenderNode node, SwfCxform parentCx) {
    if (hiddenCharacterIds.contains(node.character.id)) return;
    final cx = _composeCxform(parentCx, node.cxform);
    var matrix = node.matrix;
    final override = overridePositionsPx[node.character.id];
    if (override != null) {
      matrix = SwfMatrix(
        scaleX: matrix.scaleX,
        scaleY: matrix.scaleY,
        rotateSkew0: matrix.rotateSkew0,
        rotateSkew1: matrix.rotateSkew1,
        translateX: (override.x * 20).round(),
        translateY: (override.y * 20).round(),
      );
    }
    canvas.save();
    canvas.transform(_toMatrix4(matrix));
    switch (node.character) {
      case final ShapeCharacter shape:
        _paintShape(canvas, shape, cx);
      case SpriteCharacter():
        _paintNodes(canvas, node.children, cx);
      case final EditTextCharacter text:
        EditTextRenderer.paint(canvas, text, node.owner, cx);
      case final ButtonCharacter button:
        _paintButton(canvas, button, cx);
      case final StaticTextCharacter text:
        _paintStaticText(canvas, text, cx);
      default:
        break;
    }
    canvas.restore();
  }

  /// DefineText: 埋め込みグリフ（EM=1024単位のSWFシェイプ）を並べる。
  void _paintStaticText(Canvas canvas, StaticTextCharacter text, SwfCxform cx) {
    canvas.save();
    canvas.transform(_toMatrix4(text.matrix));
    FontCharacter? font;
    var color = const RgbaColor(0, 0, 0);
    var heightTwips = 240.0;
    var x = 0.0;
    var y = 0.0;
    for (final record in text.records) {
      if (record.fontId != null) {
        font = stage.movie.dictionary[record.fontId!] as FontCharacter?;
      }
      if (record.color != null) color = record.color!;
      if (record.xOffsetTwips != null) x = record.xOffsetTwips!.toDouble();
      if (record.yOffsetTwips != null) y = record.yOffsetTwips!.toDouble();
      if (record.textHeightTwips != null) {
        heightTwips = record.textHeightTwips!.toDouble();
      }
      if (font == null) continue;
      final paint = ui.Paint()
        ..isAntiAlias = true
        ..color = transformColor(color, cx);
      final glyphScale = heightTwips / 1024;
      for (final entry in record.glyphs) {
        canvas.save();
        canvas.translate(x, y);
        canvas.scale(glyphScale);
        canvas.drawPath(pathBuilder.forGlyph(font, entry.glyphIndex), paint);
        canvas.restore();
        x += entry.advanceTwips;
      }
    }
    canvas.restore();
  }

  /// ボタンのUpステートを描画（Over/Downはポインタ未対応のため未使用）。
  /// レコードは深度順に、シェイプ・テキストなど任意のキャラクタを描く。
  void _paintButton(Canvas canvas, ButtonCharacter button, SwfCxform cx) {
    final records = button.records.where((r) => r.stateUp).toList()
      ..sort((a, b) => a.depth.compareTo(b.depth));
    for (final record in records) {
      final character = stage.movie.dictionary[record.characterId];
      if (character == null) continue;
      final recordCx = _composeCxform(cx, record.cxform);
      canvas.save();
      canvas.transform(_toMatrix4(record.matrix));
      switch (character) {
        case final ShapeCharacter shape:
          _paintShape(canvas, shape, recordCx);
        case final StaticTextCharacter text:
          _paintStaticText(canvas, text, recordCx);
        case final EditTextCharacter text:
          EditTextRenderer.paint(canvas, text, null, recordCx);
        default:
          break;
      }
      canvas.restore();
    }
  }

  void _paintShape(Canvas canvas, ShapeCharacter shape, SwfCxform cx) {
    final data = pathBuilder.forShape(shape);
    for (final (style, path) in data.fills) {
      canvas.drawPath(path, _fillPaint(style, cx));
    }
    for (final (style, path) in data.lines) {
      canvas.drawPath(path, paintForLine(style, cx));
    }
  }

  ui.Paint _fillPaint(FillStyle style, SwfCxform cx) {
    if (style is BitmapFill) {
      final image = bitmaps.imageFor(style.bitmapId);
      if (image != null) {
        final tile = style.repeating ? ui.TileMode.repeated : ui.TileMode.clamp;
        final paint = ui.Paint()
          ..isAntiAlias = true
          ..filterQuality =
              style.smoothed ? FilterQuality.low : FilterQuality.none
          ..shader =
              ui.ImageShader(image, tile, tile, _toMatrix4(style.matrix));
        if (!cx.isIdentity) {
          paint.colorFilter = _cxformFilter(cx);
        }
        return paint;
      }
    }
    return paintForFill(style, cx);
  }

  static ui.ColorFilter _cxformFilter(SwfCxform cx) {
    return ui.ColorFilter.matrix([
      cx.rMult / 256,
      0,
      0,
      0,
      cx.rAdd.toDouble(),
      0,
      cx.gMult / 256,
      0,
      0,
      cx.gAdd.toDouble(),
      0,
      0,
      cx.bMult / 256,
      0,
      cx.bAdd.toDouble(),
      0,
      0,
      0,
      cx.aMult / 256,
      cx.aAdd.toDouble(),
    ]);
  }

  /// SWF MATRIX → Matrix4（列優先）。座標はtwipsのまま。
  static Float64List _toMatrix4(SwfMatrix m) {
    final out = Float64List(16);
    out[0] = m.scaleX;
    out[1] = m.rotateSkew0;
    out[4] = m.rotateSkew1;
    out[5] = m.scaleY;
    out[10] = 1;
    out[12] = m.translateX.toDouble();
    out[13] = m.translateY.toDouble();
    out[15] = 1;
    return out;
  }

  static SwfCxform _composeCxform(SwfCxform parent, SwfCxform child) {
    if (parent.isIdentity) return child;
    if (child.isIdentity) return parent;
    return SwfCxform(
      rMult: parent.rMult * child.rMult ~/ 256,
      gMult: parent.gMult * child.gMult ~/ 256,
      bMult: parent.bMult * child.bMult ~/ 256,
      aMult: parent.aMult * child.aMult ~/ 256,
      rAdd: parent.rAdd + parent.rMult * child.rAdd ~/ 256,
      gAdd: parent.gAdd + parent.gMult * child.gAdd ~/ 256,
      bAdd: parent.bAdd + parent.bMult * child.bAdd ~/ 256,
      aAdd: parent.aAdd + parent.aMult * child.aAdd ~/ 256,
    );
  }

  @override
  bool shouldRepaint(StagePainter oldDelegate) => oldDelegate.stage != stage;
}

/// px単位の論理ステージサイズ。
Size stageSizeOf(SwfMovie movie) => Size(
      movie.stageRect.widthTwips / _twipsPerPixel,
      movie.stageRect.heightTwips / _twipsPerPixel,
    );
