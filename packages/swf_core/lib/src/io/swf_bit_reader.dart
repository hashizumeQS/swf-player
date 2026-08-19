import 'dart:typed_data';

import '../model/basic_types.dart';
import 'sjis.dart';

/// SWFバイナリのビット単位リーダー。
///
/// SWFのビットフィールドはMSBファーストで詰められ、バイト単位の値は
/// リトルエンディアン。バイト読み系のメソッドは暗黙にバイト境界へ整列する。
class SwfBitReader {
  SwfBitReader(this._data, [this._bytePos = 0]);

  final Uint8List _data;
  int _bytePos;
  int _bitPos = 0;

  static const _fixed8Scale = 256.0; // 8.8固定小数
  static const _fixed16Scale = 65536.0; // 16.16固定小数

  int get bytePosition => _bytePos;
  bool get isAtEnd => _bytePos >= _data.length;
  int get remainingBytes => _data.length - _bytePos;

  /// 次のバイト境界まで進める（ビット読みの途中なら切り上げ）。
  void align() {
    if (_bitPos != 0) {
      _bitPos = 0;
      _bytePos++;
    }
  }

  /// 符号なしビット列（MSBファースト）。
  int readUB(int nBits) {
    var value = 0;
    for (var i = 0; i < nBits; i++) {
      final bit = (_data[_bytePos] >> (7 - _bitPos)) & 1;
      value = (value << 1) | bit;
      _bitPos++;
      if (_bitPos == 8) {
        _bitPos = 0;
        _bytePos++;
      }
    }
    return value;
  }

  /// 符号付きビット列（2の補数）。
  int readSB(int nBits) {
    if (nBits == 0) return 0;
    final value = readUB(nBits);
    final signBit = 1 << (nBits - 1);
    return (value & signBit) != 0 ? value - (1 << nBits) : value;
  }

  /// 16.16固定小数のビット列。
  double readFB(int nBits) => readSB(nBits) / _fixed16Scale;

  int readUI8() {
    align();
    return _data[_bytePos++];
  }

  int readUI16() {
    align();
    final v = _data[_bytePos] | (_data[_bytePos + 1] << 8);
    _bytePos += 2;
    return v;
  }

  int readSI16() {
    final v = readUI16();
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  int readUI32() {
    align();
    final v = _data[_bytePos] |
        (_data[_bytePos + 1] << 8) |
        (_data[_bytePos + 2] << 16) |
        (_data[_bytePos + 3] << 24);
    _bytePos += 4;
    return v;
  }

  /// 8.8固定小数（フレームレート等）。
  double readFixed8() => readSI16() / _fixed8Scale;

  Uint8List readBytes(int length) {
    align();
    final v = Uint8List.sublistView(_data, _bytePos, _bytePos + length);
    _bytePos += length;
    return v;
  }

  /// 残り全バイト。
  Uint8List readRemaining() => readBytes(remainingBytes);

  /// null終端のShift-JIS文字列。
  String readString() {
    align();
    final start = _bytePos;
    while (_data[_bytePos] != 0) {
      _bytePos++;
    }
    final s = decodeSjis(Uint8List.sublistView(_data, start, _bytePos));
    _bytePos++; // null終端をスキップ
    return s;
  }

  SwfRect readRect() {
    align();
    final nBits = readUB(5);
    final rect = SwfRect(
      readSB(nBits),
      readSB(nBits),
      readSB(nBits),
      readSB(nBits),
    );
    align();
    return rect;
  }

  SwfMatrix readMatrix() {
    align();
    var scaleX = 1.0;
    var scaleY = 1.0;
    if (readUB(1) == 1) {
      final nBits = readUB(5);
      scaleX = readFB(nBits);
      scaleY = readFB(nBits);
    }
    var rotateSkew0 = 0.0;
    var rotateSkew1 = 0.0;
    if (readUB(1) == 1) {
      final nBits = readUB(5);
      rotateSkew0 = readFB(nBits);
      rotateSkew1 = readFB(nBits);
    }
    final nTranslateBits = readUB(5);
    final matrix = SwfMatrix(
      scaleX: scaleX,
      scaleY: scaleY,
      rotateSkew0: rotateSkew0,
      rotateSkew1: rotateSkew1,
      translateX: readSB(nTranslateBits),
      translateY: readSB(nTranslateBits),
    );
    align();
    return matrix;
  }

  SwfCxform readCxform({required bool withAlpha}) {
    align();
    final hasAdd = readUB(1) == 1;
    final hasMult = readUB(1) == 1;
    final nBits = readUB(4);
    var rMult = 256, gMult = 256, bMult = 256, aMult = 256;
    var rAdd = 0, gAdd = 0, bAdd = 0, aAdd = 0;
    if (hasMult) {
      rMult = readSB(nBits);
      gMult = readSB(nBits);
      bMult = readSB(nBits);
      if (withAlpha) aMult = readSB(nBits);
    }
    if (hasAdd) {
      rAdd = readSB(nBits);
      gAdd = readSB(nBits);
      bAdd = readSB(nBits);
      if (withAlpha) aAdd = readSB(nBits);
    }
    align();
    return SwfCxform(
      rMult: rMult,
      gMult: gMult,
      bMult: bMult,
      aMult: aMult,
      rAdd: rAdd,
      gAdd: gAdd,
      bAdd: bAdd,
      aAdd: aAdd,
    );
  }
}

/// テスト・合成フィクスチャ用のビットライター（MSBファースト）。
class BitWriter {
  final List<int> _bytes = [];
  int _bitPos = 0;

  void writeUB(int nBits, int value) {
    for (var i = nBits - 1; i >= 0; i--) {
      if (_bitPos == 0) _bytes.add(0);
      final bit = (value >> i) & 1;
      _bytes[_bytes.length - 1] |= bit << (7 - _bitPos);
      _bitPos = (_bitPos + 1) % 8;
    }
  }

  void writeSB(int nBits, int value) {
    writeUB(nBits, value & ((1 << nBits) - 1));
  }

  void align() {
    _bitPos = 0;
  }

  void writeUI8(int value) {
    align();
    _bytes.add(value & 0xFF);
  }

  void writeUI16(int value) {
    align();
    _bytes.add(value & 0xFF);
    _bytes.add((value >> 8) & 0xFF);
  }

  void writeUI32(int value) {
    align();
    for (var i = 0; i < 4; i++) {
      _bytes.add((value >> (8 * i)) & 0xFF);
    }
  }

  void writeBytes(List<int> bytes) {
    align();
    _bytes.addAll(bytes);
  }

  Uint8List toBytes() => Uint8List.fromList(_bytes);
}
