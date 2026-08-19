import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

/// 輪郭のアンカー点による符号付き面積（y下向き座標系、正=時計回り）。
double signedArea(Contour c) {
  var area = 0.0;
  var px = c.startX, py = c.startY;
  for (final s in c.segments) {
    area += (px * s.anchorY - s.anchorX * py) / 2;
    px = s.anchorX;
    py = s.anchorY;
  }
  return area;
}

void main() {
  group('buildShapeContours 基本', () {
    test('fillStyle1のみの正方形が1つの閉輪郭になる', () {
      // (0,0)→(100,0)→(100,100)→(0,100)→(0,0) を右塗り(fillStyle1=1)
      final shape = ShapeWithStyle(
        fillStyles: const [SolidFill(RgbaColor(255, 0, 0))],
        lineStyles: const [],
        records: const [
          StyleChangeRecord(moveDeltaX: 0, moveDeltaY: 0, fillStyle1: 1),
          StraightEdgeRecord(100, 0),
          StraightEdgeRecord(0, 100),
          StraightEdgeRecord(-100, 0),
          StraightEdgeRecord(0, -100),
        ],
      );
      final result = buildShapeContours(shape);
      expect(result.fills, hasLength(1));
      final fill = result.fills.single;
      expect(fill.style, isA<SolidFill>());
      expect(fill.contours, hasLength(1));
      final contour = fill.contours.single;
      expect(contour.isClosed, isTrue);
      // 4本の直線セグメント
      expect(contour.segments, hasLength(4));
      expect(contour.startX, 0);
      expect(contour.startY, 0);
    });

    test('fillStyle0（左塗り）はエッジが逆向きに再構成される', () {
      // 同じ正方形を左塗り(fillStyle0=1)で定義 → 逆順の閉輪郭になる
      final shape = ShapeWithStyle(
        fillStyles: const [SolidFill(RgbaColor(0, 255, 0))],
        lineStyles: const [],
        records: const [
          StyleChangeRecord(moveDeltaX: 0, moveDeltaY: 0, fillStyle0: 1),
          StraightEdgeRecord(100, 0),
          StraightEdgeRecord(0, 100),
          StraightEdgeRecord(-100, 0),
          StraightEdgeRecord(0, -100),
        ],
      );
      final result = buildShapeContours(shape);
      final contour = result.fills.single.contours.single;
      expect(contour.isClosed, isTrue);
      expect(contour.segments, hasLength(4));
      // 巻き方向が反転していること（符号付き面積が正逆になる）
      expect(signedArea(contour), lessThan(0));
    });

    test('fillStyle1の正方形は符号付き面積が正（基準）', () {
      final shape = ShapeWithStyle(
        fillStyles: const [SolidFill(RgbaColor(255, 0, 0))],
        lineStyles: const [],
        records: const [
          StyleChangeRecord(moveDeltaX: 0, moveDeltaY: 0, fillStyle1: 1),
          StraightEdgeRecord(100, 0),
          StraightEdgeRecord(0, 100),
          StraightEdgeRecord(-100, 0),
          StraightEdgeRecord(0, -100),
        ],
      );
      final contour = buildShapeContours(shape).fills.single.contours.single;
      expect(signedArea(contour), greaterThan(0));
    });

    test('両側塗り: 中央線を共有する2つの矩形', () {
      // 左右2色: 中央の縦線はfillStyle0=左の色, fillStyle1=右の色
      // 左矩形(0,0)-(100,100)=style1, 右矩形(100,0)-(200,100)=style2
      final shape = ShapeWithStyle(
        fillStyles: const [
          SolidFill(RgbaColor(255, 0, 0)),
          SolidFill(RgbaColor(0, 0, 255)),
        ],
        lineStyles: const [],
        records: const [
          // 中央線(100,0)→(100,100)下向き: 進行右側(x-側=左矩形)=style1,
          // 左側(x+側=右矩形)=style0=2
          StyleChangeRecord(
              moveDeltaX: 100, moveDeltaY: 0, fillStyle0: 2, fillStyle1: 1),
          StraightEdgeRecord(0, 100),
          // 左矩形の残り3辺（内側を右に見て周回: 下→左→上）
          StyleChangeRecord(
              moveDeltaX: 100, moveDeltaY: 100, fillStyle0: 0, fillStyle1: 1),
          StraightEdgeRecord(-100, 0),
          StraightEdgeRecord(0, -100),
          StraightEdgeRecord(100, 0),
          // 右矩形の残り3辺（内側を右に見て周回: 上→右→下）
          StyleChangeRecord(
              moveDeltaX: 100, moveDeltaY: 0, fillStyle0: 0, fillStyle1: 2),
          StraightEdgeRecord(100, 0),
          StraightEdgeRecord(0, 100),
          StraightEdgeRecord(-100, 0),
        ],
      );
      final result = buildShapeContours(shape);
      expect(result.fills, hasLength(2));
      for (final fill in result.fills) {
        expect(fill.contours, hasLength(1), reason: '各色1閉輪郭');
        expect(fill.contours.single.isClosed, isTrue);
      }
    });

    test('曲線エッジが輪郭に保存される', () {
      final shape = ShapeWithStyle(
        fillStyles: const [SolidFill(RgbaColor(0, 0, 0))],
        lineStyles: const [],
        records: const [
          StyleChangeRecord(moveDeltaX: 0, moveDeltaY: 0, fillStyle1: 1),
          CurvedEdgeRecord(50, 0, 50, 50), // 制御点(50,0), アンカー(100,50)
          StraightEdgeRecord(-100, -50),
        ],
      );
      final result = buildShapeContours(shape);
      final contour = result.fills.single.contours.single;
      expect(contour.segments, hasLength(2));
      final curve = contour.segments.first;
      expect(curve.controlX, 50);
      expect(curve.controlY, 0);
      expect(curve.anchorX, 100);
      expect(curve.anchorY, 50);
    });

    test('線スタイルはポリラインとして収集される', () {
      final shape = ShapeWithStyle(
        fillStyles: const [],
        lineStyles: const [LineStyle(20, RgbaColor(0, 0, 0))],
        records: const [
          StyleChangeRecord(moveDeltaX: 0, moveDeltaY: 0, lineStyle: 1),
          StraightEdgeRecord(100, 0),
          StraightEdgeRecord(0, 100),
        ],
      );
      final result = buildShapeContours(shape);
      expect(result.fills, isEmpty);
      expect(result.lines, hasLength(1));
      expect(result.lines.single.style.widthTwips, 20);
      expect(result.lines.single.contours.single.segments, hasLength(2));
    });

    test('moveToで分断された同一スタイルの2輪郭', () {
      final shape = ShapeWithStyle(
        fillStyles: const [SolidFill(RgbaColor(1, 2, 3))],
        lineStyles: const [],
        records: const [
          StyleChangeRecord(moveDeltaX: 0, moveDeltaY: 0, fillStyle1: 1),
          StraightEdgeRecord(10, 0),
          StraightEdgeRecord(0, 10),
          StraightEdgeRecord(-10, -10),
          StyleChangeRecord(moveDeltaX: 100, moveDeltaY: 100),
          StraightEdgeRecord(10, 0),
          StraightEdgeRecord(0, 10),
          StraightEdgeRecord(-10, -10),
        ],
      );
      final result = buildShapeContours(shape);
      expect(result.fills.single.contours, hasLength(2));
      expect(result.fills.single.contours.every((c) => c.isClosed), isTrue);
    });
  });
}
