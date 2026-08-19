/// SWFの座標・変換の基本型。座標は twips（1px = 20twips）。
library;

/// SWF RECT。twips単位の境界矩形。
class SwfRect {
  const SwfRect(this.xMin, this.xMax, this.yMin, this.yMax);

  /// 左端のX座標（twips）。
  final int xMin;

  /// 右端のX座標（twips）。
  final int xMax;

  /// 上端のY座標（twips）。
  final int yMin;

  /// 下端のY座標（twips）。
  final int yMax;

  /// 矩形の幅（twips）。
  int get widthTwips => xMax - xMin;

  /// 矩形の高さ（twips）。
  int get heightTwips => yMax - yMin;

  @override
  String toString() => 'SwfRect($xMin, $xMax, $yMin, $yMax)';
}

/// SWF MATRIX。scale/rotateは16.16固定小数由来のdouble、translateはtwips整数。
class SwfMatrix {
  const SwfMatrix({
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.rotateSkew0 = 0.0,
    this.rotateSkew1 = 0.0,
    this.translateX = 0,
    this.translateY = 0,
  });

  /// 恒等変換（拡大縮小・回転・平行移動なし）。
  static const identity = SwfMatrix();

  /// 水平方向のスケール係数（1.0が等倍）。
  final double scaleX;

  /// 垂直方向のスケール係数（1.0が等倍）。
  final double scaleY;

  /// [apply]におけるY成分へのX寄与係数（回転・スキュー項）。
  final double rotateSkew0;

  /// [apply]におけるX成分へのY寄与係数（回転・スキュー項）。
  final double rotateSkew1;

  /// 水平方向の平行移動量（twips）。
  final int translateX;

  /// 垂直方向の平行移動量（twips）。
  final int translateY;

  @override
  String toString() =>
      'SwfMatrix(sx=$scaleX, sy=$scaleY, r0=$rotateSkew0, r1=$rotateSkew1, '
      'tx=$translateX, ty=$translateY)';

  /// 行列の合成: this（親）の後にchild（子）を適用する変換。
  SwfMatrix multiply(SwfMatrix child) => SwfMatrix(
        scaleX: scaleX * child.scaleX + rotateSkew1 * child.rotateSkew0,
        rotateSkew0: rotateSkew0 * child.scaleX + scaleY * child.rotateSkew0,
        rotateSkew1: scaleX * child.rotateSkew1 + rotateSkew1 * child.scaleY,
        scaleY: rotateSkew0 * child.rotateSkew1 + scaleY * child.scaleY,
        translateX: (scaleX * child.translateX + rotateSkew1 * child.translateY)
                .round() +
            translateX,
        translateY: (rotateSkew0 * child.translateX + scaleY * child.translateY)
                .round() +
            translateY,
      );

  /// 点(twips)を変換する。
  (double, double) apply(double x, double y) => (
        scaleX * x + rotateSkew1 * y + translateX,
        rotateSkew0 * x + scaleY * y + translateY,
      );
}

/// SWF CXFORM / CXFORMWITHALPHA。乗算項は8.8固定小数の生値（256 = 1.0）。
class SwfCxform {
  const SwfCxform({
    this.rMult = _identityMult,
    this.gMult = _identityMult,
    this.bMult = _identityMult,
    this.aMult = _identityMult,
    this.rAdd = 0,
    this.gAdd = 0,
    this.bAdd = 0,
    this.aAdd = 0,
  });

  static const _identityMult = 256;

  /// 恒等変換（乗算項=256すなわち1.0、加算項=0）。
  static const identity = SwfCxform();

  /// 赤成分の乗算係数（8.8固定小数の生値、256 = 1.0）。
  final int rMult;

  /// 緑成分の乗算係数（8.8固定小数の生値、256 = 1.0）。
  final int gMult;

  /// 青成分の乗算係数（8.8固定小数の生値、256 = 1.0）。
  final int bMult;

  /// アルファ成分の乗算係数（8.8固定小数の生値、256 = 1.0）。
  final int aMult;

  /// 赤成分への加算値。`clamp((v * rMult) ~/ 256 + rAdd, 0, 255)`の形で
  /// 乗算後に適用される。
  final int rAdd;

  /// 緑成分への加算値。適用方法は[rAdd]と同様。
  final int gAdd;

  /// 青成分への加算値。適用方法は[rAdd]と同様。
  final int bAdd;

  /// アルファ成分への加算値。適用方法は[rAdd]と同様。
  final int aAdd;

  /// 乗算項が全て1.0（256）、加算項が全て0の恒等変換かどうか。
  bool get isIdentity =>
      rMult == _identityMult &&
      gMult == _identityMult &&
      bMult == _identityMult &&
      aMult == _identityMult &&
      rAdd == 0 &&
      gAdd == 0 &&
      bAdd == 0 &&
      aAdd == 0;
}
