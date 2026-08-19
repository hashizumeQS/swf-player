import '../io/swf_bit_reader.dart';
import '../model/shape_records.dart';
import '../model/swf_movie.dart';

/// DefineShape/2/3 のSHAPEWITHSTYLE、およびグリフSHAPEのパース。
class ShapeParser {
  ShapeParser(this._r, this.shapeVersion);

  final SwfBitReader _r;

  /// 1=DefineShape, 2=DefineShape2, 3=DefineShape3(RGBA・拡張カウント)
  final int shapeVersion;

  bool get _hasAlpha => shapeVersion >= 3;
  bool get _hasExtendedCount => shapeVersion >= 2;

  RgbaColor _readColor() {
    final r = _r.readUI8();
    final g = _r.readUI8();
    final b = _r.readUI8();
    final a = _hasAlpha ? _r.readUI8() : 0xFF;
    return RgbaColor(r, g, b, a);
  }

  List<FillStyle> _readFillStyles() {
    var count = _r.readUI8();
    if (count == 0xFF && _hasExtendedCount) count = _r.readUI16();
    return List.generate(count, (_) => _readFillStyle());
  }

  FillStyle _readFillStyle() {
    final type = _r.readUI8();
    switch (type) {
      case 0x00:
        return SolidFill(_readColor());
      case 0x10 || 0x12:
        final matrix = _r.readMatrix();
        final numStops = _r.readUI8() & 0x0F;
        final stops = List.generate(
          numStops,
          (_) => GradientStop(_r.readUI8(), _readColor()),
        );
        return GradientFill(
            isRadial: type == 0x12, matrix: matrix, stops: stops);
      case 0x40 || 0x41 || 0x42 || 0x43:
        final bitmapId = _r.readUI16();
        final matrix = _r.readMatrix();
        return BitmapFill(
          bitmapId: bitmapId,
          matrix: matrix,
          repeating: type == 0x40 || type == 0x42,
          smoothed: type == 0x40 || type == 0x41,
        );
      default:
        throw SwfParseException('未対応の塗りスタイル: 0x${type.toRadixString(16)}');
    }
  }

  List<LineStyle> _readLineStyles() {
    var count = _r.readUI8();
    if (count == 0xFF && _hasExtendedCount) count = _r.readUI16();
    return List.generate(
      count,
      (_) => LineStyle(_r.readUI16(), _readColor()),
    );
  }

  ShapeWithStyle readShapeWithStyle() {
    final fillStyles = _readFillStyles();
    final lineStyles = _readLineStyles();
    final records = _readShapeRecords(allowNewStyles: true);
    return ShapeWithStyle(
      fillStyles: fillStyles,
      lineStyles: lineStyles,
      records: records,
    );
  }

  /// グリフ用SHAPE（スタイル配列なし）。
  GlyphShape readGlyphShape() {
    return GlyphShape(_readShapeRecords(allowNewStyles: false));
  }

  List<ShapeRecord> _readShapeRecords({required bool allowNewStyles}) {
    _r.align();
    var numFillBits = _r.readUB(4);
    var numLineBits = _r.readUB(4);
    final records = <ShapeRecord>[];

    while (true) {
      final isEdge = _r.readUB(1) == 1;
      if (!isEdge) {
        final flags = _r.readUB(5);
        if (flags == 0) break; // EndShapeRecord

        int? moveX, moveY;
        if (flags & 0x01 != 0) {
          final moveBits = _r.readUB(5);
          moveX = _r.readSB(moveBits);
          moveY = _r.readSB(moveBits);
        }
        final fillStyle0 = (flags & 0x02 != 0) ? _r.readUB(numFillBits) : null;
        final fillStyle1 = (flags & 0x04 != 0) ? _r.readUB(numFillBits) : null;
        final lineStyle = (flags & 0x08 != 0) ? _r.readUB(numLineBits) : null;

        List<FillStyle>? newFills;
        List<LineStyle>? newLines;
        if (flags & 0x10 != 0) {
          if (!allowNewStyles) {
            throw SwfParseException('グリフSHAPE内でスタイル再定義は不正');
          }
          _r.align();
          newFills = _readFillStyles();
          newLines = _readLineStyles();
          numFillBits = _r.readUB(4);
          numLineBits = _r.readUB(4);
        }
        records.add(StyleChangeRecord(
          moveDeltaX: moveX,
          moveDeltaY: moveY,
          fillStyle0: fillStyle0,
          fillStyle1: fillStyle1,
          lineStyle: lineStyle,
          newFillStyles: newFills,
          newLineStyles: newLines,
        ));
      } else {
        final isStraight = _r.readUB(1) == 1;
        final numBits = _r.readUB(4) + 2;
        if (isStraight) {
          final isGeneral = _r.readUB(1) == 1;
          if (isGeneral) {
            records.add(
                StraightEdgeRecord(_r.readSB(numBits), _r.readSB(numBits)));
          } else {
            final isVertical = _r.readUB(1) == 1;
            final delta = _r.readSB(numBits);
            records.add(isVertical
                ? StraightEdgeRecord(0, delta)
                : StraightEdgeRecord(delta, 0));
          }
        } else {
          records.add(CurvedEdgeRecord(
            _r.readSB(numBits),
            _r.readSB(numBits),
            _r.readSB(numBits),
            _r.readSB(numBits),
          ));
        }
      }
    }
    _r.align();
    return records;
  }
}

class SwfParseException implements Exception {
  SwfParseException(this.message);
  final String message;

  @override
  String toString() => 'SwfParseException: $message';
}
