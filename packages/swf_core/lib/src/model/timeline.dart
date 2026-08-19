import 'dart:typed_data';

import 'basic_types.dart';

/// 1フレーム分の表示リスト操作とアクション。
class SwfFrame {
  SwfFrame({
    List<FrameOp>? ops,
    List<Uint8List>? actions,
    this.label,
  })  : ops = ops ?? [],
        actions = actions ?? [];

  final List<FrameOp> ops;

  /// このフレームのDoActionバイト列（タグ出現順）。
  final List<Uint8List> actions;

  final String? label;
}

/// フレーム内の表示リスト操作。
sealed class FrameOp {
  const FrameOp();
}

/// PlaceObject2。move=trueなら同depthの既存オブジェクトを更新、
/// characterId非nullなら新規配置または差し替え。
class PlaceOp extends FrameOp {
  const PlaceOp({
    required this.depth,
    required this.move,
    this.characterId,
    this.matrix,
    this.cxform,
    this.ratio,
    this.name,
    this.clipDepth,
  });

  final int depth;
  final bool move;
  final int? characterId;
  final SwfMatrix? matrix;
  final SwfCxform? cxform;
  final int? ratio;
  final String? name;
  final int? clipDepth;
}

class RemoveOp extends FrameOp {
  const RemoveOp(this.depth);
  final int depth;
}

/// メインタイムラインまたはスプライトのタイムライン。
class Timeline {
  const Timeline(this.frames, this.labelToFrame);

  final List<SwfFrame> frames;

  /// フレームラベル → 0-based フレームindex。
  final Map<String, int> labelToFrame;

  int get frameCount => frames.length;
}
