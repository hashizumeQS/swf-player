/// 純Dart実装の Shift-JIS (CP932) デコーダ／エンコーダ。
///
/// `dart:convert` の他コーデックには依存せず、Flutter非依存の純Dartパッケージ
/// として利用できる。変換テーブルは [sjis_table.dart] に分離されており、
/// Python の `cp932` コーデックから機械生成されたものを用いる。
library;

import 'sjis_table.dart';

/// デコード時に未定義のバイト列を表すために使う置換文字 (U+FFFD)。
const int _replacementCharCodePoint = 0xFFFD;

/// エンコード不能な文字を表すために使う ASCII '?' (0x3F)。
const int _questionMarkByte = 0x3F;

/// 半角カナの SJIS 開始バイト (0xA1) と対応する Unicode 開始コードポイント (U+FF61)。
const int _halfwidthKanaSjisStart = 0xA1;
const int _halfwidthKanaSjisEnd = 0xDF;
const int _halfwidthKanaUnicodeStart = 0xFF61;

/// ASCII 域の上限 (0x7F)。
const int _asciiMax = 0x7F;

/// SJIS 2バイト文字の第1バイト (リードバイト) として有効な範囲。
const int _leadByteRange1Start = 0x81;
const int _leadByteRange1End = 0x9F;
const int _leadByteRange2Start = 0xE0;
const int _leadByteRange2End = 0xFC;

bool _isLeadByte(int byte) {
  return (byte >= _leadByteRange1Start && byte <= _leadByteRange1End) ||
      (byte >= _leadByteRange2Start && byte <= _leadByteRange2End);
}

/// CP932 (Shift-JIS) バイト列を Dart の [String] にデコードする。
///
/// - 0x00〜0x7F は ASCII としてそのままデコードする。
/// - 0xA1〜0xDF は半角カナ (U+FF61〜U+FF9F) としてデコードする。
/// - 有効なリードバイトに後続バイトが無い、またはテーブルに存在しない
///   組み合わせは未定義バイトとして U+FFFD に置換する。
String decodeSjis(List<int> bytes) {
  final buffer = StringBuffer();
  var i = 0;
  final length = bytes.length;

  while (i < length) {
    final byte = bytes[i];

    if (byte <= _asciiMax) {
      buffer.writeCharCode(byte);
      i += 1;
      continue;
    }

    if (byte >= _halfwidthKanaSjisStart && byte <= _halfwidthKanaSjisEnd) {
      buffer.writeCharCode(
        _halfwidthKanaUnicodeStart + (byte - _halfwidthKanaSjisStart),
      );
      i += 1;
      continue;
    }

    if (_isLeadByte(byte)) {
      final hasTrailByte = i + 1 < length;
      if (!hasTrailByte) {
        buffer.writeCharCode(_replacementCharCodePoint);
        i += 1;
        continue;
      }

      final trailByte = bytes[i + 1];
      final code = (byte << 8) | trailByte;
      final unicode = sjisTwoByteToUnicode[code];
      if (unicode == null) {
        buffer.writeCharCode(_replacementCharCodePoint);
      } else {
        buffer.writeCharCode(unicode);
      }
      i += 2;
      continue;
    }

    // 0x80, 0xA0, 0xFD-0xFF などリードバイトとして未定義のバイト。
    buffer.writeCharCode(_replacementCharCodePoint);
    i += 1;
  }

  return buffer.toString();
}

/// Unicode コードポイントから SJIS 2バイトコードへの逆引きテーブル。
/// 遅延構築し、初回アクセス時のみ生成する。
Map<int, int>? _unicodeToSjisTwoByte;

Map<int, int> _buildReverseTable() {
  final reverse = <int, int>{};
  for (final entry in sjisTwoByteToUnicode.entries) {
    // 同じ Unicode コードポイントに複数の SJIS コードが対応する場合は、
    // 先に登録された (SJISコードが小さい) ものを正とする。
    reverse.putIfAbsent(entry.value, () => entry.key);
  }
  return reverse;
}

Map<int, int> get _reverseTable =>
    _unicodeToSjisTwoByte ??= _buildReverseTable();

/// Dart の [String] を CP932 (Shift-JIS) バイト列にエンコードする。
///
/// - U+0000〜U+007F は ASCII としてそのままエンコードする。
/// - U+FF61〜U+FF9F は半角カナとして 1 バイトにエンコードする。
/// - それ以外はテーブルの逆引きで 2 バイトにエンコードする。
/// - エンコード不能な文字は '?' (0x3F) に置換する。
List<int> encodeSjis(String s) {
  final bytes = <int>[];

  for (final rune in s.runes) {
    if (rune <= _asciiMax) {
      bytes.add(rune);
      continue;
    }

    if (rune >= _halfwidthKanaUnicodeStart &&
        rune <=
            _halfwidthKanaUnicodeStart +
                (_halfwidthKanaSjisEnd - _halfwidthKanaSjisStart)) {
      bytes.add(_halfwidthKanaSjisStart + (rune - _halfwidthKanaUnicodeStart));
      continue;
    }

    final sjisCode = _reverseTable[rune];
    if (sjisCode == null) {
      bytes.add(_questionMarkByte);
      continue;
    }

    bytes.add((sjisCode >> 8) & 0xFF);
    bytes.add(sjisCode & 0xFF);
  }

  return bytes;
}
