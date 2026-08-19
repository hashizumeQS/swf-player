import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:swf_core/swf_core.dart';

/// ムービー内の全ビットマップを ui.Image 化して保持する。
/// 描画前に prime() を await すること。
class BitmapRegistry {
  final Map<int, ui.Image> _images = {};

  /// [movie]の辞書内にある全ビットマップキャラクタをデコードし、
  /// `ui.Image`としてキャッシュする。描画前に一度だけawaitすること。
  /// フォーマットが[BitmapFormat.jpeg3]ならJPEG本体をデコードしzlib圧縮
  /// アルファ面を合成し、それ以外（lossless1/lossless2）はzlib展開の
  /// 可逆ビットマップとしてデコードする。
  Future<void> prime(SwfMovie movie) async {
    for (final c in movie.dictionary.values.whereType<BitmapCharacter>()) {
      if (c.format == BitmapFormat.jpeg3) {
        _images[c.id] = await _decodeJpeg3(c);
        continue;
      }
      final decoded = decodeLossless(c);
      _images[c.id] = await _toImage(decoded);
    }
  }

  /// characterId（[id]）に対応するデコード済み画像を返す。
  /// [prime]未実行、または該当IDのビットマップキャラクタが存在しない場合は
  /// null。
  ui.Image? imageFor(int id) => _images[id];

  /// キャッシュ済みの全`ui.Image`を解放し、キャッシュを空にする。
  void dispose() {
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
  }

  static Future<ui.Image> _toImage(DecodedBitmap d) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _premultiply(d.rgba),
      d.width,
      d.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// straightアルファ→事前乗算済みへ変換（in place）。
  /// decodeImageFromPixels(rgba8888)はpremultiplied解釈のため、
  /// straightのまま渡すと半透明ピクセルが本来より明るく合成される。
  static Uint8List _premultiply(Uint8List rgba) {
    for (var i = 0; i < rgba.length; i += 4) {
      final a = rgba[i + 3];
      if (a == 255) continue;
      if (a == 0) {
        rgba[i] = 0;
        rgba[i + 1] = 0;
        rgba[i + 2] = 0;
        continue;
      }
      // 最近傍丸め（切り捨てだと半透明色が最大1階調暗くなる）
      rgba[i] = (rgba[i] * a + 127) ~/ 255;
      rgba[i + 1] = (rgba[i + 1] * a + 127) ~/ 255;
      rgba[i + 2] = (rgba[i + 2] * a + 127) ~/ 255;
    }
    return rgba;
  }

  /// DefineBitsJPEG3をデコードする。
  ///
  /// dataレイアウト: UI32(LE) alphaDataOffset + JPEGデータ(alphaDataOffset
  /// バイト) + zlib圧縮アルファ（幅×高さ×1バイト）。JPEG部はdart:uiでデコード
  /// し、そのRGB出力（JPEGにアルファは無いため全ピクセル不透明）へzlib展開
  /// したアルファチャンネルを上書き合成する。
  static Future<ui.Image> _decodeJpeg3(BitmapCharacter c) async {
    final data = c.data;
    final alphaDataOffset =
        data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24);
    final jpegEnd = (4 + alphaDataOffset).clamp(4, data.length);
    final jpegBytes =
        _mergeLeadingTablesSegment(Uint8List.sublistView(data, 4, jpegEnd));
    final alphaCompressed = Uint8List.sublistView(data, jpegEnd);

    final codec = await ui.instantiateImageCodec(jpegBytes);
    final int width;
    final int height;
    final ByteData? byteData;
    try {
      final frame = await codec.getNextFrame();
      final rgbImage = frame.image;
      width = rgbImage.width;
      height = rgbImage.height;
      byteData = await rgbImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      rgbImage.dispose();
    } finally {
      codec.dispose();
    }

    final rgba = byteData!.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );

    if (alphaCompressed.isNotEmpty) {
      final expectedAlphaLength = width * height;
      try {
        final alpha = const ZLibDecoder().decodeBytes(alphaCompressed);
        if (alpha.length == expectedAlphaLength) {
          for (var i = 0; i < expectedAlphaLength; i++) {
            rgba[i * 4 + 3] = alpha[i];
          }
        }
      } catch (_) {
        // 展開失敗（サイズ不一致・破損）時は不透明のまま使う。
      }
    }

    return _toImage(DecodedBitmap(width, height, rgba));
  }

  /// 古いSWFのJPEGデータは、量子化/ハフマン表（DQT/DHT）だけを定義しSOF/SOS
  /// を持たないテーブル専用セグメントが先頭に付き、それを閉じるEOIの直後に
  /// 本来の画像のSOIが続く（バイト列としては FF D9 FF D8 が連続する）ことが
  /// ある。本来の画像側はこの共有テーブルを前提にSOF/SOSのみを持つため、
  /// 単純に後半（2番目のSOI以降）だけを取り出すとテーブル欠落で壊れる。
  /// EOI+SOIの4バイトだけを取り除いて両セグメントを1本のJPEGへ結合する
  /// （先頭セグメントのSOIをそのまま画像全体のSOIとして使う）。
  /// マーカー列が見つからなければそのまま返す。
  static Uint8List _mergeLeadingTablesSegment(Uint8List jpeg) {
    for (var i = 0; i <= jpeg.length - 4; i++) {
      if (jpeg[i] == 0xFF &&
          jpeg[i + 1] == 0xD9 &&
          jpeg[i + 2] == 0xFF &&
          jpeg[i + 3] == 0xD8) {
        final merged = Uint8List(jpeg.length - 4);
        merged.setRange(0, i, jpeg, 0);
        merged.setRange(i, merged.length, jpeg, i + 4);
        return merged;
      }
    }
    return jpeg;
  }
}
