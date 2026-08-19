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

  /// このフレームで実行する表示リスト操作（配置・更新・削除）の列。
  final List<FrameOp> ops;

  /// このフレームのDoActionバイト列（タグ出現順）。
  final List<Uint8List> actions;

  /// FrameLabelタグで指定されたフレームラベル。無ければnull。
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

  /// 表示リストにおける深度（重なり順）。
  final int depth;

  /// trueなら同depthの既存オブジェクトを更新、falseなら新規配置。
  final bool move;

  /// 配置・差し替えるキャラクタのID。nullなら変更なし（move時の属性更新のみ）。
  final int? characterId;

  /// 配置変換行列。nullなら変更なし。
  final SwfMatrix? matrix;

  /// カラー変換。nullなら変更なし。
  final SwfCxform? cxform;

  /// PlaceObject2のRatio値（0〜65535）。DefineMorphShapeの補間比率として
  /// 使われる値だが、本ライブラリはモーフシェイプ未対応のため実質未使用。
  /// nullなら変更なし。
  final int? ratio;

  /// ActionScriptからこのインスタンスを参照するための名前。nullなら変更なし。
  final String? name;

  /// マスクとして使う場合のクリップ深度上限。指定時は(depth, clipDepth]の
  /// 範囲のオブジェクトがこのキャラクタでクリップされる。nullなら変更なし。
  final int? clipDepth;
}

/// RemoveObject2。指定depthの表示オブジェクトを表示リストから削除する。
class RemoveOp extends FrameOp {
  const RemoveOp(this.depth);

  /// 削除対象の深度。
  final int depth;
}

/// メインタイムラインまたはスプライトのタイムライン。
class Timeline {
  const Timeline(this.frames, this.labelToFrame);

  /// 0-based フレームindexで並んだフレーム列。
  final List<SwfFrame> frames;

  /// フレームラベル → 0-based フレームindex。
  final Map<String, int> labelToFrame;

  /// このタイムラインの総フレーム数。
  int get frameCount => frames.length;
}
