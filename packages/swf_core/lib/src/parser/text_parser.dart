import '../io/sjis.dart';
import '../io/swf_bit_reader.dart';
import '../model/character.dart';
import '../model/shape_records.dart';
import '../model/swf_movie.dart';
import 'shape_parser.dart';

EditTextCharacter parseDefineEditText(SwfBitReader r) {
  final id = r.readUI16();
  final bounds = r.readRect();
  final flags1 = r.readUI8();
  final flags2 = r.readUI8();

  final hasText = flags1 & 0x80 != 0;
  final isMultiline = flags1 & 0x20 != 0;
  final hasTextColor = flags1 & 0x04 != 0;
  final hasMaxLength = flags1 & 0x02 != 0;
  final hasFont = flags1 & 0x01 != 0;
  final hasLayout = flags2 & 0x20 != 0;
  final hasBorder = flags2 & 0x08 != 0;
  final useOutlines = flags2 & 0x01 != 0;

  int? fontId;
  var fontHeight = 240; // デフォルト12pt相当
  if (hasFont) {
    fontId = r.readUI16();
    fontHeight = r.readUI16();
  }
  RgbaColor? textColor;
  if (hasTextColor) {
    textColor = RgbaColor(r.readUI8(), r.readUI8(), r.readUI8(), r.readUI8());
  }
  if (hasMaxLength) r.readUI16();

  var align = 0;
  var leftMargin = 0;
  var rightMargin = 0;
  if (hasLayout) {
    align = r.readUI8();
    leftMargin = r.readUI16();
    rightMargin = r.readUI16();
    r.readUI16(); // indent
    r.readSI16(); // leading
  }
  final variableName = r.readString();
  final initialText = hasText ? r.readString() : null;

  return EditTextCharacter(
    id,
    bounds: bounds,
    variableName: variableName,
    initialText: initialText,
    fontId: fontId,
    fontHeightTwips: fontHeight,
    textColor: textColor,
    align: align,
    leftMarginTwips: leftMargin,
    rightMarginTwips: rightMargin,
    hasBorder: hasBorder,
    isMultiline: isMultiline,
    useOutlines: useOutlines,
  );
}

FontCharacter parseDefineFont2(SwfBitReader r) {
  final id = r.readUI16();
  final flags = r.readUI8();
  final hasLayout = flags & 0x80 != 0;
  final isShiftJis = flags & 0x40 != 0;
  final hasWideOffsets = flags & 0x08 != 0;
  final hasWideCodes = flags & 0x04 != 0;
  r.readUI8(); // langCode
  final nameLen = r.readUI8();
  final nameBytes = r.readBytes(nameLen);
  // フォント名はnull終端を含むことがある
  final name = decodeSjis(nameBytes.takeWhile((b) => b != 0).toList());

  final numGlyphs = r.readUI16();
  final offsetTableStart = r.bytePosition;
  final offsets = List.generate(
      numGlyphs, (_) => hasWideOffsets ? r.readUI32() : r.readUI16());
  // codeTableOffset（グリフ0個の場合は存在しない）
  if (numGlyphs > 0) {
    if (hasWideOffsets) {
      r.readUI32();
    } else {
      r.readUI16();
    }
  }

  final glyphs = <GlyphShape>[];
  for (var i = 0; i < numGlyphs; i++) {
    // オフセットはオフセットテーブル先頭基準。ビットずれ防止に明示シーク相当
    final expected = offsetTableStart + offsets[i];
    if (r.bytePosition != expected) {
      r.readBytes(expected - r.bytePosition);
    }
    glyphs.add(ShapeParser(r, 1).readGlyphShape());
  }

  final codeTable = List.generate(
      numGlyphs, (_) => hasWideCodes ? r.readUI16() : r.readUI8());
  // ShiftJISコードテーブルはUnicodeへ正規化（非SJISはUCS-2のまま）
  final normalizedCodes = !isShiftJis
      ? codeTable
      : codeTable.map((c) {
          final bytes = c > 0xFF ? [c >> 8, c & 0xFF] : [c];
          final s = decodeSjis(bytes);
          return s.isEmpty ? c : s.codeUnitAt(0);
        }).toList();

  var advances = <int>[];
  if (hasLayout) {
    r.readUI16(); // ascent
    r.readUI16(); // descent
    r.readSI16(); // leading
    advances = List.generate(numGlyphs, (_) => r.readSI16());
    // boundsTable以降（kerning等）はレイアウトに未使用のため読み捨て
  }

  return FontCharacter(
    id,
    name: name,
    glyphs: glyphs,
    codeTable: normalizedCodes,
    advances: advances,
  );
}

StaticTextCharacter parseDefineText(SwfBitReader r) {
  final id = r.readUI16();
  final bounds = r.readRect();
  final matrix = r.readMatrix();
  final glyphBits = r.readUI8();
  final advanceBits = r.readUI8();

  final records = <TextRecord>[];
  while (true) {
    final flags = r.readUI8();
    if (flags == 0) break;
    final hasFont = flags & 0x08 != 0;
    final hasColor = flags & 0x04 != 0;
    final hasYOffset = flags & 0x02 != 0;
    final hasXOffset = flags & 0x01 != 0;

    final fontId = hasFont ? r.readUI16() : null;
    RgbaColor? color;
    if (hasColor) {
      color = RgbaColor(r.readUI8(), r.readUI8(), r.readUI8());
    }
    final xOffset = hasXOffset ? r.readSI16() : null;
    final yOffset = hasYOffset ? r.readSI16() : null;
    final textHeight = hasFont ? r.readUI16() : null;

    final glyphCount = r.readUI8();
    final glyphs = <GlyphEntry>[];
    for (var i = 0; i < glyphCount; i++) {
      glyphs.add(GlyphEntry(r.readUB(glyphBits), r.readSB(advanceBits)));
    }
    r.align();
    records.add(TextRecord(
      fontId: fontId,
      color: color,
      xOffsetTwips: xOffset,
      yOffsetTwips: yOffset,
      textHeightTwips: textHeight,
      glyphs: glyphs,
    ));
  }
  return StaticTextCharacter(id, bounds, matrix, records);
}
