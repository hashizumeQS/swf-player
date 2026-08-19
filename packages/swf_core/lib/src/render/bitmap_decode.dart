import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../model/character.dart';

const _alphaOpaque = 255;

/// DefineBitsLossless/2のBitmapFormatコード（タグ本体先頭のUI8）。
const _formatCodePalette = 3; // 8bit パレットindex
const _formatCodePix15 = 4; // 15bit RGB（lossless1のみ）
const _formatCodePix24Or32 = 5; // PIX24（lossless1）/ ARGB32（lossless2）

/// デコード済みビットマップ。
///
/// [rgba]は幅×高さ×4バイトで、各ピクセルがR,G,B,Aの順（straightアルファ、
/// 事前乗算なし）に並ぶ。
class DecodedBitmap {
  const DecodedBitmap(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;
}

/// DefineBitsLossless/DefineBitsLossless2のビットマップをRGBAピクセル列へ
/// デコードする。DefineBitsJPEG3（[BitmapFormat.jpeg3]）は非対応。
DecodedBitmap decodeLossless(BitmapCharacter c) {
  if (c.format == BitmapFormat.jpeg3) {
    throw UnsupportedError('DefineBitsJPEG3のデコードは未対応です (id=${c.id})');
  }

  final data = c.data;
  final formatCode = data[0];
  final width = data[1] | (data[2] << 8);
  final height = data[3] | (data[4] << 8);

  var paletteColorCount = 0;
  var compressedOffset = 5;
  if (formatCode == _formatCodePalette) {
    paletteColorCount = data[5] + 1; // BitmapColorTableSize = 色数-1
    compressedOffset = 6;
  }

  final compressed = Uint8List.sublistView(data, compressedOffset);
  final decompressed = const ZLibDecoder().decodeBytes(compressed);

  final isLossless2 = c.format == BitmapFormat.lossless2;

  switch (formatCode) {
    case _formatCodePalette:
      return _decodePalette(
        decompressed,
        width: width,
        height: height,
        paletteColorCount: paletteColorCount,
        paletteEntrySize: isLossless2 ? 4 : 3,
      );
    case _formatCodePix15:
      return _decodePix15(decompressed, width: width, height: height);
    case _formatCodePix24Or32:
      return isLossless2
          ? _decodeArgb32(decompressed, width: width, height: height)
          : _decodePix24(decompressed, width: width, height: height);
    default:
      throw FormatException(
        'Unknown BitmapFormat code $formatCode (id=${c.id})',
      );
  }
}

/// format=3: パレットindex行列。行はstride=(width+3)&~3で4バイト境界へ
/// パディングされる。パレットはlossless1=RGB(3バイト/色)、
/// lossless2=RGBA(4バイト/色)。
DecodedBitmap _decodePalette(
  Uint8List src, {
  required int width,
  required int height,
  required int paletteColorCount,
  required int paletteEntrySize,
}) {
  final paletteBytes = paletteColorCount * paletteEntrySize;
  final stride = (width + 3) & ~3;
  final rgba = Uint8List(width * height * 4);

  for (var y = 0; y < height; y++) {
    final rowStart = paletteBytes + y * stride;
    for (var x = 0; x < width; x++) {
      final paletteOffset = src[rowStart + x] * paletteEntrySize;
      final outOffset = (y * width + x) * 4;
      rgba[outOffset] = src[paletteOffset];
      rgba[outOffset + 1] = src[paletteOffset + 1];
      rgba[outOffset + 2] = src[paletteOffset + 2];
      rgba[outOffset + 3] =
          paletteEntrySize == 4 ? src[paletteOffset + 3] : _alphaOpaque;
    }
  }
  return DecodedBitmap(width, height, rgba);
}

/// format=4 (PIX15, lossless1のみ): 1ピクセル=UI16(ビッグエンディアン)。
/// 上位bitから予約1bit+R5bit+G5bit+B5bit。行はstride=(width*2+3)&~3で
/// 4バイト境界へパディングされる。
DecodedBitmap _decodePix15(
  Uint8List src, {
  required int width,
  required int height,
}) {
  final stride = (width * 2 + 3) & ~3;
  final rgba = Uint8List(width * height * 4);

  for (var y = 0; y < height; y++) {
    final rowStart = y * stride;
    for (var x = 0; x < width; x++) {
      final byteOffset = rowStart + x * 2;
      final pixel = (src[byteOffset] << 8) | src[byteOffset + 1];
      final outOffset = (y * width + x) * 4;
      rgba[outOffset] = _expand5to8((pixel >> 10) & 0x1F);
      rgba[outOffset + 1] = _expand5to8((pixel >> 5) & 0x1F);
      rgba[outOffset + 2] = _expand5to8(pixel & 0x1F);
      rgba[outOffset + 3] = _alphaOpaque;
    }
  }
  return DecodedBitmap(width, height, rgba);
}

int _expand5to8(int v5) => (v5 << 3) | (v5 >> 2);

/// format=5, lossless1 (PIX24): 1ピクセル=4バイト（Reserved,R,G,B）。
/// 常に4バイト境界なので行パディングは発生しない。
DecodedBitmap _decodePix24(
  Uint8List src, {
  required int width,
  required int height,
}) {
  final pixelCount = width * height;
  final rgba = Uint8List(pixelCount * 4);
  for (var i = 0; i < pixelCount; i++) {
    final srcOffset = i * 4;
    final outOffset = i * 4;
    rgba[outOffset] = src[srcOffset + 1];
    rgba[outOffset + 1] = src[srcOffset + 2];
    rgba[outOffset + 2] = src[srcOffset + 3];
    rgba[outOffset + 3] = _alphaOpaque;
  }
  return DecodedBitmap(width, height, rgba);
}

/// format=5, lossless2 (ARGB32): 1ピクセル=4バイト（A,R,G,B、事前乗算済み）。
/// straightアルファへ逆変換する。
DecodedBitmap _decodeArgb32(
  Uint8List src, {
  required int width,
  required int height,
}) {
  final pixelCount = width * height;
  final rgba = Uint8List(pixelCount * 4);
  for (var i = 0; i < pixelCount; i++) {
    final srcOffset = i * 4;
    final outOffset = i * 4;
    final a = src[srcOffset];
    if (a == 0) {
      rgba[outOffset] = 0;
      rgba[outOffset + 1] = 0;
      rgba[outOffset + 2] = 0;
      rgba[outOffset + 3] = 0;
    } else {
      rgba[outOffset] = _unpremultiply(src[srcOffset + 1], a);
      rgba[outOffset + 1] = _unpremultiply(src[srcOffset + 2], a);
      rgba[outOffset + 2] = _unpremultiply(src[srcOffset + 3], a);
      rgba[outOffset + 3] = a;
    }
  }
  return DecodedBitmap(width, height, rgba);
}

int _unpremultiply(int channel, int alpha) =>
    ((channel * _alphaOpaque) ~/ alpha).clamp(0, _alphaOpaque);
