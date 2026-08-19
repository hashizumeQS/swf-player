import 'dart:typed_data';

import 'package:swf_core/swf_core.dart';

/// テスト用バイトコードアセンブラ。
class Asm {
  final List<int> _bytes = [];

  Asm pushString(String s) {
    final data = encodeSjis(s);
    _op(0x96, [0, ...data, 0]);
    return this;
  }

  Asm pushFloat(double v) {
    final bd = ByteData(4)..setFloat32(0, v, Endian.little);
    _op(0x96, [1, ...bd.buffer.asUint8List()]);
    return this;
  }

  Asm op(int code) {
    _bytes.add(code);
    return this;
  }

  Asm jump(int offset) {
    _op(0x99, [offset & 0xFF, (offset >> 8) & 0xFF]);
    return this;
  }

  Asm iff(int offset) {
    _op(0x9D, [offset & 0xFF, (offset >> 8) & 0xFF]);
    return this;
  }

  Asm setTarget(String path) {
    _op(0x8B, [...encodeSjis(path), 0]);
    return this;
  }

  Asm gotoLabel(String label) {
    _op(0x8C, [...encodeSjis(label), 0]);
    return this;
  }

  Asm gotoFrame(int frame0) {
    _op(0x81, [frame0 & 0xFF, (frame0 >> 8) & 0xFF]);
    return this;
  }

  Asm getUrl2({int flags = 0}) {
    _op(0x9A, [flags]);
    return this;
  }

  /// 現在のバイト位置（後方ジャンプのオフセット計算用）。
  int get length => _bytes.length;

  void _op(int code, List<int> operand) {
    _bytes.add(code);
    _bytes.add(operand.length & 0xFF);
    _bytes.add((operand.length >> 8) & 0xFF);
    _bytes.addAll(operand);
  }

  Uint8List build() => Uint8List.fromList([..._bytes, 0]);
}
