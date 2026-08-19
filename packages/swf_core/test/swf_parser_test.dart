import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

/// 合成SWF: FWSヘッダ + SetBackgroundColor + ShowFrame + End
Uint8List buildMinimalSwf() {
  final body = BitWriter();
  // RECT 240x240px (4800twips), nbits=14
  body.writeUB(5, 14);
  body.writeSB(14, 0);
  body.writeSB(14, 4800);
  body.writeSB(14, 0);
  body.writeSB(14, 4800);
  body.align();
  body.writeUI16(12 << 8); // フレームレート 12.0 (8.8固定小数)
  body.writeUI16(1); // フレーム数
  // SetBackgroundColor (tag 9, len 3): RGB(255, 128, 0)
  body.writeUI16((9 << 6) | 3);
  body.writeBytes([255, 128, 0]);
  // ShowFrame (tag 1, len 0)
  body.writeUI16(1 << 6);
  // End (tag 0, len 0)
  body.writeUI16(0);
  final bodyBytes = body.toBytes();

  final header = BitWriter();
  header.writeBytes('FWS'.codeUnits);
  header.writeUI8(4); // version
  header.writeUI32(8 + bodyBytes.length); // ファイル全長
  header.writeBytes(bodyBytes);
  return header.toBytes();
}

/// [buildMinimalSwf]のCWS（zlib圧縮）版を組み立てる。
Uint8List buildMinimalCompressedSwf() {
  final plain = buildMinimalSwf();
  final body = plain.sublist(8);
  final compressed = const ZLibEncoder().encode(body);

  final header = BitWriter();
  header.writeBytes('CWS'.codeUnits);
  header.writeUI8(6); // version（CWSはSWF 6以降の仕様）
  header.writeUI32(plain.length); // 展開後のファイル全長
  header.writeBytes(compressed);
  return header.toBytes();
}

void main() {
  group('SwfParser CWS（zlib圧縮SWF）', () {
    test('圧縮SWFを展開してFWSと同じ結果にパースできる', () {
      final movie = SwfParser.parse(buildMinimalCompressedSwf());
      expect(movie.version, 6);
      expect(movie.stageRect.widthTwips, 4800);
      expect(movie.frameRate, closeTo(12.0, 1e-9));
      expect(movie.frameCount, 1);
      expect(movie.backgroundColor, isNotNull);
    });

    test('FWS/CWS以外のシグネチャは拒否する', () {
      final bogus = buildMinimalSwf();
      bogus[0] = 0x58; // 'X'
      expect(() => SwfParser.parse(bogus), throwsA(isA<SwfParseException>()));
    });
  });

  group('SwfParser 合成SWF', () {
    test('ヘッダを読める（240x240 / 12fps / 1フレーム）', () {
      final movie = SwfParser.parse(buildMinimalSwf());
      expect(movie.version, 4);
      expect(movie.stageRect.widthTwips, 4800);
      expect(movie.stageRect.heightTwips, 4800);
      expect(movie.frameRate, closeTo(12.0, 1e-9));
      expect(movie.frameCount, 1);
    });

    test('タグを分割できる（SetBackgroundColor + ShowFrame + End）', () {
      final movie = SwfParser.parse(buildMinimalSwf());
      expect(movie.backgroundColor, isNotNull);
      expect(movie.backgroundColor!.r, 255);
      expect(movie.backgroundColor!.g, 128);
      expect(movie.backgroundColor!.b, 0);
      expect(movie.mainTimeline.frames, hasLength(1));
    });

    test('CWSヘッダだが本体が壊れている場合はSwfParseException', () {
      final bad = Uint8List.fromList([0x43, 0x57, 0x53, 4, 0, 0, 0, 0]);
      expect(() => SwfParser.parse(bad), throwsA(isA<SwfParseException>()));
    });
  });
}
