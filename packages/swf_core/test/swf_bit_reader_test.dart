import 'dart:typed_data';

import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

void main() {
  group('SwfBitReader 基本読取', () {
    test('readUI8/UI16/UI32 はリトルエンディアンで読む', () {
      final r = SwfBitReader(
          Uint8List.fromList([0x2A, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12]));
      expect(r.readUI8(), 0x2A);
      expect(r.readUI16(), 0x1234);
      expect(r.readUI32(), 0x12345678);
    });

    test('readUB はMSBから順にビットを読む', () {
      // 0b1011_0110 → UB(3)=0b101=5, UB(5)=0b10110=22
      final r = SwfBitReader(Uint8List.fromList([0xB6]));
      expect(r.readUB(3), 5);
      expect(r.readUB(5), 22);
    });

    test('readUB はバイト境界をまたげる', () {
      // 0b11111111 0b00000001 → UB(9) = 0b111111110 = 510
      final r = SwfBitReader(Uint8List.fromList([0xFF, 0x01]));
      expect(r.readUB(9), 510);
    });

    test('readSB は符号拡張する', () {
      // 0b111_00000: SB(3) = -1
      final r = SwfBitReader(Uint8List.fromList([0xE0]));
      expect(r.readSB(3), -1);
    });

    test('readSB 正の値はそのまま', () {
      // 0b011_00000: SB(3) = 3
      final r = SwfBitReader(Uint8List.fromList([0x60]));
      expect(r.readSB(3), 3);
    });

    test('readUB(0) は 0 を返しビット位置を進めない', () {
      final r = SwfBitReader(Uint8List.fromList([0xFF]));
      expect(r.readUB(0), 0);
      expect(r.readUB(8), 0xFF);
    });

    test('align 後のバイト読みはビット読みの次のバイト境界から', () {
      final r = SwfBitReader(Uint8List.fromList([0x80, 0x42]));
      r.readUB(1);
      r.align();
      expect(r.readUI8(), 0x42);
    });

    test('バイト読みはビット位置を自動的にalignする', () {
      final r = SwfBitReader(Uint8List.fromList([0x80, 0x42]));
      r.readUB(1);
      expect(r.readUI8(), 0x42);
    });
  });

  group('SwfBitReader 固定小数', () {
    test('readFB は16.16固定小数（符号付き）', () {
      // +1.0 = 0x10000 は符号ビット込みで18bit必要:
      // 0b01_0000000000000000 → MSB firstで 0x40 0x00 0x00
      final r = SwfBitReader(Uint8List.fromList([0x40, 0x00, 0x00]));
      expect(r.readFB(18), closeTo(1.0, 1e-9));
    });

    test('readFB 負値: FB(17)でMSBが立つと負', () {
      // 0b1_0000000000000000 (17bit) = -0x10000 → -1.0
      final r = SwfBitReader(Uint8List.fromList([0x80, 0x00, 0x00]));
      expect(r.readFB(17), closeTo(-1.0, 1e-9));
    });

    test('readFixed8 は8.8固定小数（フレームレート用）', () {
      // 12.0fps = 0x0C00 (LE: 00 0C)
      final r = SwfBitReader(Uint8List.fromList([0x00, 0x0C]));
      expect(r.readFixed8(), closeTo(12.0, 1e-9));
    });

    test('readFixed8 小数部あり', () {
      // 12.5 = 0x0C80 (LE: 80 0C)
      final r = SwfBitReader(Uint8List.fromList([0x80, 0x0C]));
      expect(r.readFixed8(), closeTo(12.5, 1e-9));
    });
  });

  group('SwfBitReader 複合構造', () {
    test('readRect: 240x240px ステージ (twips)', () {
      // nbits=14（符号付き4800には14bit必要）, xmin=0, xmax=4800, ymin=0, ymax=4800
      final bits = BitWriter();
      bits.writeUB(5, 14);
      bits.writeSB(14, 0);
      bits.writeSB(14, 4800);
      bits.writeSB(14, 0);
      bits.writeSB(14, 4800);
      final r = SwfBitReader(bits.toBytes());
      final rect = r.readRect();
      expect(rect.xMin, 0);
      expect(rect.xMax, 4800);
      expect(rect.yMin, 0);
      expect(rect.yMax, 4800);
    });

    test('readMatrix: 恒等行列（scale/rotateなし、translate 0,0）', () {
      final bits = BitWriter();
      bits.writeUB(1, 0); // hasScale = false
      bits.writeUB(1, 0); // hasRotate = false
      bits.writeUB(5, 0); // nTranslateBits = 0
      final r = SwfBitReader(bits.toBytes());
      final m = r.readMatrix();
      expect(m.scaleX, 1.0);
      expect(m.scaleY, 1.0);
      expect(m.rotateSkew0, 0.0);
      expect(m.rotateSkew1, 0.0);
      expect(m.translateX, 0);
      expect(m.translateY, 0);
    });

    test('readMatrix: 平行移動あり', () {
      final bits = BitWriter();
      bits.writeUB(1, 0); // hasScale
      bits.writeUB(1, 0); // hasRotate
      bits.writeUB(5, 10); // nTranslateBits
      bits.writeSB(10, 100); // tx (twips)
      bits.writeSB(10, -200); // ty
      final r = SwfBitReader(bits.toBytes());
      final m = r.readMatrix();
      expect(m.translateX, 100);
      expect(m.translateY, -200);
    });

    test('readCxform: 乗算+加算あり (withAlpha=false)', () {
      final bits = BitWriter();
      bits.writeUB(1, 1); // hasAdd
      bits.writeUB(1, 1); // hasMult
      bits.writeUB(4, 10); // nbits（符号付き256には10bit必要）
      bits.writeSB(10, 128); // rMult (0.5)
      bits.writeSB(10, 256); // gMult (1.0)
      bits.writeSB(10, 0); // bMult
      bits.writeSB(10, 10); // rAdd
      bits.writeSB(10, -10); // gAdd
      bits.writeSB(10, 0); // bAdd
      final r = SwfBitReader(bits.toBytes());
      final cx = r.readCxform(withAlpha: false);
      expect(cx.rMult, 128);
      expect(cx.gMult, 256);
      expect(cx.bMult, 0);
      expect(cx.rAdd, 10);
      expect(cx.gAdd, -10);
      expect(cx.aMult, 256); // alpha無し時は恒等
      expect(cx.aAdd, 0);
    });
  });

  group('SwfBitReader 文字列', () {
    test('readString: null終端Shift-JIS文字列', () {
      // "あ" = SJIS 0x82 0xA0
      final r = SwfBitReader(Uint8List.fromList([0x82, 0xA0, 0x00, 0xFF]));
      expect(r.readString(), 'あ');
      expect(r.readUI8(), 0xFF); // null終端の次から読める
    });

    test('readString: ASCII', () {
      final r = SwfBitReader(Uint8List.fromList([0x61, 0x62, 0x63, 0x00]));
      expect(r.readString(), 'abc');
    });
  });
}
