import 'dart:typed_data';

import 'basic_types.dart';
import 'swf_movie.dart' show RgbaColor;

/// 塗りスタイル。DefineShape/2は RGB、DefineShape3 は RGBA。
sealed class FillStyle {
  const FillStyle();
}

/// 単色塗り。
class SolidFill extends FillStyle {
  const SolidFill(this.color);

  /// 塗りの色。
  final RgbaColor color;
}

/// グラデーション塗り（線形または放射状）。
class GradientFill extends FillStyle {
  const GradientFill({
    required this.isRadial,
    required this.matrix,
    required this.stops,
  });

  /// trueなら放射状（RADIAL）、falseなら線形（LINEAR）グラデーション。
  final bool isRadial;

  /// 単位グラデーション空間（-1〜1）をシェイプのtwips座標へ写す変換行列。
  final SwfMatrix matrix;

  /// 色停止点。ratio昇順で並ぶ。
  final List<GradientStop> stops;
}

/// グラデーションの色停止点（GRADRECORD）。
class GradientStop {
  const GradientStop(this.ratio, this.color);

  /// グラデーション上の位置（0〜255）。
  final int ratio; // 0-255

  /// この停止点の色。
  final RgbaColor color;
}

/// ビットマップ塗り（塗りつぶしにビットマップキャラクタを用いる）。
class BitmapFill extends FillStyle {
  const BitmapFill({
    required this.bitmapId,
    required this.matrix,
    required this.repeating,
    required this.smoothed,
  });

  /// 塗りに使う[BitmapCharacter]のキャラクタID。
  final int bitmapId;

  /// ビットマップ空間をシェイプのtwips座標へ写す変換行列。
  final SwfMatrix matrix;

  /// trueなら塗り範囲全体にビットマップを繰り返し敷き詰める（タイリング）。
  final bool repeating;

  /// trueならビットマップの拡大縮小時にスムージングを適用する。
  final bool smoothed;
}

/// 線（ストローク）スタイル。
class LineStyle {
  const LineStyle(this.widthTwips, this.color);

  /// 線幅（twips）。
  final int widthTwips;

  /// 線の色。
  final RgbaColor color;
}

/// シェイプレコード。座標は twips、カレントポイントからの相対。
sealed class ShapeRecord {
  const ShapeRecord();
}

/// スタイル変更（moveTo / スタイル選択 / 新スタイル定義）。
class StyleChangeRecord extends ShapeRecord {
  const StyleChangeRecord({
    this.moveDeltaX,
    this.moveDeltaY,
    this.fillStyle0,
    this.fillStyle1,
    this.lineStyle,
    this.newFillStyles,
    this.newLineStyles,
  });

  /// moveTo（絶対座標）。nullなら移動なし。
  final int? moveDeltaX;
  final int? moveDeltaY;

  /// 選択するスタイルindex（1-based、0=塗りなし）。nullなら変更なし。
  final int? fillStyle0;
  final int? fillStyle1;
  final int? lineStyle;

  /// 新スタイル配列（DefineShape2以降）。非nullならスタイル配列を差し替え。
  final List<FillStyle>? newFillStyles;
  final List<LineStyle>? newLineStyles;
}

/// 直線エッジ（カレントポイントからの相対移動）。
class StraightEdgeRecord extends ShapeRecord {
  const StraightEdgeRecord(this.deltaX, this.deltaY);

  /// カレントポイントからのX方向相対移動（twips）。
  final int deltaX;

  /// カレントポイントからのY方向相対移動（twips）。
  final int deltaY;
}

/// 2次ベジェ曲線エッジ。
///
/// SWF仕様どおり、制御点はカレントポイントからの相対移動
/// （controlDeltaX/Y）、終点は制御点からの相対移動（anchorDeltaX/Y）。
class CurvedEdgeRecord extends ShapeRecord {
  const CurvedEdgeRecord(this.controlDeltaX, this.controlDeltaY,
      this.anchorDeltaX, this.anchorDeltaY);

  /// カレントポイントから制御点までのX方向相対移動（twips）。
  final int controlDeltaX;

  /// カレントポイントから制御点までのY方向相対移動（twips）。
  final int controlDeltaY;

  /// 制御点から終点（アンカー）までのX方向相対移動（twips）。
  final int anchorDeltaX;

  /// 制御点から終点（アンカー）までのY方向相対移動（twips）。
  final int anchorDeltaY;
}

/// DefineShapeのSHAPEWITHSTYLE全体。
class ShapeWithStyle {
  const ShapeWithStyle({
    required this.fillStyles,
    required this.lineStyles,
    required this.records,
  });

  /// 塗りスタイル配列（0-based）。StyleChangeRecordのfillStyle0/1は
  /// 1-based indexでこの配列を参照する（0=塗りなし）。
  final List<FillStyle> fillStyles;

  /// 線スタイル配列（0-based）。StyleChangeRecordのlineStyleは
  /// 1-based indexでこの配列を参照する（0=線なし）。
  final List<LineStyle> lineStyles;

  /// 描画順のシェイプレコード列。
  final List<ShapeRecord> records;
}

/// DefineFont2のグリフ用SHAPE（スタイル配列なし、fill 0/1のみ）。
class GlyphShape {
  const GlyphShape(this.records);

  /// グリフの輪郭を構成するシェイプレコード列（スタイル配列は持たず、
  /// fill 0/1のみを使用する）。
  final List<ShapeRecord> records;
}

/// ボタンの表示レコード。
class ButtonRecord {
  const ButtonRecord({
    required this.stateUp,
    required this.stateOver,
    required this.stateDown,
    required this.stateHitTest,
    required this.characterId,
    required this.depth,
    required this.matrix,
    required this.cxform,
  });

  /// trueなら「UP」状態でこのキャラクタを表示する。
  final bool stateUp;

  /// trueなら「OVER（ロールオーバー）」状態でこのキャラクタを表示する。
  final bool stateOver;

  /// trueなら「DOWN（押下）」状態でこのキャラクタを表示する。
  final bool stateDown;

  /// trueならヒットテスト（当たり判定）の形状としてこのキャラクタを使う。
  final bool stateHitTest;

  /// 配置するキャラクタのID。
  final int characterId;

  /// 表示リストにおける深度（重なり順）。
  final int depth;

  /// このキャラクタに適用する変換行列。
  final SwfMatrix matrix;

  /// このキャラクタに適用するカラー変換。
  final SwfCxform cxform;
}

/// ボタンの条件付きアクション（キー条件を含む）。
class ButtonCondAction {
  const ButtonCondAction({
    required this.keyPress,
    required this.overDownToOverUp,
    required this.overUpToOverDown,
    required this.idleToOverUp,
    required this.actions,
  });

  /// SWF CondKeyPressコード（0=キー条件なし）。
  final int keyPress;

  /// 「ボタンを離した（クリック確定）」遷移。
  final bool overDownToOverUp;

  /// 「押下開始」遷移。
  final bool overUpToOverDown;

  /// 「ロールオーバー」遷移。
  final bool idleToOverUp;

  /// この条件を満たしたときに実行するDoActionバイトコード列。
  final Uint8List actions;
}
