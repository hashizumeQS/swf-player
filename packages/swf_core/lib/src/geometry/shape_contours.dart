import '../model/shape_records.dart';

/// シェイプの1セグメント（絶対twips座標）。controlがnullなら直線。
class ContourSegment {
  const ContourSegment(this.anchorX, this.anchorY,
      [this.controlX, this.controlY]);

  final int anchorX;
  final int anchorY;
  final int? controlX;
  final int? controlY;

  bool get isCurve => controlX != null;

  /// 逆向きセグメント用: 新しいアンカーを与えて反転（2次ベジェは制御点共有）。
  ContourSegment reversed(int newAnchorX, int newAnchorY) =>
      ContourSegment(newAnchorX, newAnchorY, controlX, controlY);
}

/// 連結済みの輪郭（塗りなら閉、線なら開もあり）。
class Contour {
  const Contour(this.startX, this.startY, this.segments,
      {required this.isClosed});

  final int startX;
  final int startY;
  final List<ContourSegment> segments;
  final bool isClosed;
}

/// 1つの塗りスタイルに属する閉輪郭群。
class FillContours {
  const FillContours(this.style, this.contours);
  final FillStyle style;
  final List<Contour> contours;
}

/// 1つの線スタイルに属するポリライン（輪郭）群。
class LineContours {
  const LineContours(this.style, this.contours);
  final LineStyle style;
  final List<Contour> contours;
}

/// シェイプ全体の再構成結果。描画は fills を定義順に塗り、その後 lines。
class ShapeContours {
  const ShapeContours(this.fills, this.lines);
  final List<FillContours> fills;
  final List<LineContours> lines;
}

/// SWFシェイプレコード列から、塗りスタイル別の閉輪郭と線ポリラインを再構成する。
///
/// SWFのエッジは「左側=fillStyle0 / 右側=fillStyle1」の両側塗りモデル。
/// fillStyle1のエッジは順方向、fillStyle0のエッジは逆方向でバケツに集め、
/// 端点一致（twips整数の完全一致）で連結して閉輪郭を得る。
ShapeContours buildShapeContours(ShapeWithStyle shape) {
  final builder = _ContourBuilder();
  builder.setStyles(shape.fillStyles, shape.lineStyles);

  var x = 0, y = 0;
  for (final record in shape.records) {
    switch (record) {
      case StyleChangeRecord():
        if (record.newFillStyles != null) {
          builder.setStyles(
              record.newFillStyles!, record.newLineStyles ?? const []);
        }
        if (record.moveDeltaX != null) {
          x = record.moveDeltaX!;
          y = record.moveDeltaY!;
          builder.breakLine();
        }
        if (record.fillStyle0 != null) builder.fill0 = record.fillStyle0!;
        if (record.fillStyle1 != null) builder.fill1 = record.fillStyle1!;
        if (record.lineStyle != null) {
          builder.line = record.lineStyle!;
          builder.breakLine();
        }
      case StraightEdgeRecord():
        final nx = x + record.deltaX;
        final ny = y + record.deltaY;
        builder.addEdge(x, y, ContourSegment(nx, ny));
        x = nx;
        y = ny;
      case CurvedEdgeRecord():
        final cx = x + record.controlDeltaX;
        final cy = y + record.controlDeltaY;
        final nx = cx + record.anchorDeltaX;
        final ny = cy + record.anchorDeltaY;
        builder.addEdge(x, y, ContourSegment(nx, ny, cx, cy));
        x = nx;
        y = ny;
    }
  }
  return builder.build();
}

/// 方向付きエッジ（連結前の素材）。segmentは連結済みマーカーに書き換わる。
class _DirectedEdge {
  _DirectedEdge(this.startX, this.startY, this.segment);
  final int startX;
  final int startY;
  ContourSegment segment;
}

/// スタイル1つ分の方向付きエッジ集合（連結前の作業領域）。
class _FillBucket {
  _FillBucket(this.style);
  final FillStyle style;
  final List<_DirectedEdge> edges = [];
}

/// スタイル1つ分の線ポリライン構築用の作業領域。
class _LineBucket {
  _LineBucket(this.style);
  final LineStyle style;
  final List<Contour> contours = [];
  List<ContourSegment>? current;
  int curStartX = 0, curStartY = 0;
  int curX = 0, curY = 0;
}

/// [buildShapeContours]の内部実装。シェイプレコード列を走査しながら
/// スタイル別バケツにエッジ／線分を振り分け、最後に端点連結で輪郭化する。
class _ContourBuilder {
  // スタイル配列の世代（レイヤー）を通算したバケツ列。定義順=描画順。
  final List<_FillBucket> _allFillBuckets = [];
  final List<_LineBucket> _allLineBuckets = [];

  // 現世代のスタイル配列（1-based indexでアクセス）。
  List<_FillBucket> _activeFills = [];
  List<_LineBucket> _activeLines = [];

  int fill0 = 0;
  int fill1 = 0;
  int line = 0;

  void setStyles(List<FillStyle> fills, List<LineStyle> lines) {
    _activeFills = [for (final s in fills) _FillBucket(s)];
    _activeLines = [for (final s in lines) _LineBucket(s)];
    _allFillBuckets.addAll(_activeFills);
    _allLineBuckets.addAll(_activeLines);
    fill0 = 0;
    fill1 = 0;
    line = 0;
  }

  /// 線ポリラインを（moveTo/スタイル変更で）打ち切る。
  void breakLine() {
    for (final b in _activeLines) {
      _flushLine(b);
    }
  }

  void _flushLine(_LineBucket b) {
    final cur = b.current;
    if (cur != null && cur.isNotEmpty) {
      final closed = b.curX == b.curStartX && b.curY == b.curStartY;
      b.contours.add(Contour(b.curStartX, b.curStartY, cur, isClosed: closed));
    }
    b.current = null;
  }

  void addEdge(int fromX, int fromY, ContourSegment seg) {
    if (fill1 > 0 && fill1 <= _activeFills.length) {
      _activeFills[fill1 - 1].edges.add(_DirectedEdge(fromX, fromY, seg));
    }
    if (fill0 > 0 && fill0 <= _activeFills.length) {
      _activeFills[fill0 - 1].edges.add(
          _DirectedEdge(seg.anchorX, seg.anchorY, seg.reversed(fromX, fromY)));
    }
    if (line > 0 && line <= _activeLines.length) {
      final b = _activeLines[line - 1];
      if (b.current == null || b.curX != fromX || b.curY != fromY) {
        _flushLine(b);
        b.current = [];
        b.curStartX = fromX;
        b.curStartY = fromY;
      }
      b.current!.add(seg);
      b.curX = seg.anchorX;
      b.curY = seg.anchorY;
    }
  }

  ShapeContours build() {
    breakLine();
    final fills = <FillContours>[];
    for (final bucket in _allFillBuckets) {
      if (bucket.edges.isEmpty) continue;
      fills.add(FillContours(bucket.style, _joinEdges(bucket.edges)));
    }
    final lines = <LineContours>[];
    for (final bucket in _allLineBuckets) {
      if (bucket.contours.isEmpty) continue;
      lines.add(LineContours(bucket.style, bucket.contours));
    }
    return ShapeContours(fills, lines);
  }

  /// 方向付きエッジ群を端点一致で連結し輪郭列にする。
  static List<Contour> _joinEdges(List<_DirectedEdge> edges) {
    // 始点座標 → エッジ列（同一始点の複数エッジに対応）
    final byStart = <int, List<_DirectedEdge>>{};
    int key(int x, int y) => (x << 20) ^ (y & 0xFFFFF);
    for (final e in edges) {
      byStart.putIfAbsent(key(e.startX, e.startY), () => []).add(e);
    }

    final contours = <Contour>[];
    for (final e in edges) {
      if (e.segment == _consumed) continue;
      // このエッジを起点に連結をたどる
      var cur = e;
      final segs = <ContourSegment>[];
      final startX = cur.startX, startY = cur.startY;
      var cx = startX, cy = startY;
      while (true) {
        segs.add(cur.segment);
        cx = cur.segment.anchorX;
        cy = cur.segment.anchorY;
        _markConsumed(cur);
        if (cx == startX && cy == startY) {
          contours.add(Contour(startX, startY, segs, isClosed: true));
          break;
        }
        final candidates = byStart[key(cx, cy)];
        _DirectedEdge? next;
        if (candidates != null) {
          for (final c in candidates) {
            if (c.segment != _consumed) {
              next = c;
              break;
            }
          }
        }
        if (next == null) {
          // 連結先なし: 開いた輪郭として確定（描画時はcloseで補完）
          contours.add(Contour(startX, startY, segs, isClosed: false));
          break;
        }
        cur = next;
      }
    }
    return contours;
  }

  static const _consumed = ContourSegment(-1 << 30, -1 << 30);

  static void _markConsumed(_DirectedEdge e) {
    e.segment = _consumed;
  }
}
