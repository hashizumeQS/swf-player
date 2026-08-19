/// SWFの座標・変換の基本型。座標は twips（1px = 20twips）。
library;

/// SWF RECT。twips単位の境界矩形。
class SwfRect {
  const SwfRect(this.xMin, this.xMax, this.yMin, this.yMax);

  final int xMin;
  final int xMax;
  final int yMin;
  final int yMax;

  int get widthTwips => xMax - xMin;
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

  static const identity = SwfMatrix();

  final double scaleX;
  final double scaleY;
  final double rotateSkew0;
  final double rotateSkew1;
  final int translateX;
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
  static const identity = SwfCxform();

  final int rMult;
  final int gMult;
  final int bMult;
  final int aMult;
  final int rAdd;
  final int gAdd;
  final int bAdd;
  final int aAdd;

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
