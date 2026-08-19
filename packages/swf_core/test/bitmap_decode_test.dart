import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

/// DefineBitsLossless/2のタグ本体（characterId除く）を組み立てる。
Uint8List _buildLosslessData({
  required int formatCode,
  required int width,
  required int height,
  int? colorTableSize,
  required List<int> uncompressedBody,
}) {
  final header = <int>[
    formatCode,
    width & 0xFF,
    (width >> 8) & 0xFF,
    height & 0xFF,
    (height >> 8) & 0xFF,
    if (colorTableSize != null) colorTableSize,
  ];
  final compressed = const ZLibEncoder().encodeBytes(uncompressedBody);
  return Uint8List.fromList([...header, ...compressed]);
}

void main() {
  group('decodeLossless: 合成データ', () {
    test('format3(lossless1) 2x2パレット2色、行パディングあり(stride=4)', () {
      // パレット: index0=赤(255,0,0), index1=緑(0,255,0)
      const palette = [255, 0, 0, 0, 255, 0];
      // width=2 → stride=(2+3)&~3=4。各行2ピクセル+2バイトパディング。
      const row0 = [0, 1, 0, 0]; // 赤,緑
      const row1 = [1, 0, 0, 0]; // 緑,赤
      final data = _buildLosslessData(
        formatCode: 3,
        width: 2,
        height: 2,
        colorTableSize: 1, // 色数2-1
        uncompressedBody: [...palette, ...row0, ...row1],
      );
      final character = BitmapCharacter(1, BitmapFormat.lossless1, data);

      final decoded = decodeLossless(character);

      expect(decoded.width, 2);
      expect(decoded.height, 2);
      expect(decoded.rgba.length, 2 * 2 * 4);
      expect(
        decoded.rgba.sublist(0, 4),
        [255, 0, 0, 255],
        reason: '(0,0) = 赤',
      );
      expect(
        decoded.rgba.sublist(4, 8),
        [0, 255, 0, 255],
        reason: '(1,0) = 緑',
      );
      expect(
        decoded.rgba.sublist(8, 12),
        [0, 255, 0, 255],
        reason: '(0,1) = 緑',
      );
      expect(
        decoded.rgba.sublist(12, 16),
        [255, 0, 0, 255],
        reason: '(1,1) = 赤',
      );
    });

    test('format5(lossless2) 1x2 事前乗算ARGBの逆変換', () {
      // pixel0: A=128,R=128,G=0,B=0(事前乗算) → straight R=255,G=0,B=0,A=128
      // pixel1: A=0,R=50,G=50,B=50(事前乗算) → straight は全て0
      const pixel0 = [128, 128, 0, 0];
      const pixel1 = [0, 50, 50, 50];
      final data = _buildLosslessData(
        formatCode: 5,
        width: 1,
        height: 2,
        uncompressedBody: [...pixel0, ...pixel1],
      );
      final character = BitmapCharacter(2, BitmapFormat.lossless2, data);

      final decoded = decodeLossless(character);

      expect(decoded.width, 1);
      expect(decoded.height, 2);
      expect(decoded.rgba.length, 1 * 2 * 4);
      expect(
        decoded.rgba.sublist(0, 4),
        [255, 0, 0, 128],
        reason: 'a=128,premultiplied r=128 → straight r=255',
      );
      expect(
        decoded.rgba.sublist(4, 8),
        [0, 0, 0, 0],
        reason: 'a=0 → 全チャンネル0',
      );
    });
  });
}
