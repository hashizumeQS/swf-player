import 'dart:typed_data';

import '../io/swf_bit_reader.dart';
import '../model/character.dart';
import '../model/shape_records.dart';

ButtonCharacter parseDefineButton2(SwfBitReader r, Uint8List tagBody) {
  final id = r.readUI16();
  r.readUI8(); // flags (trackAsMenu)
  final actionOffsetPos = r.bytePosition;
  final actionOffset = r.readUI16();

  final records = <ButtonRecord>[];
  while (true) {
    final flags = r.readUI8();
    if (flags == 0) break;
    final characterId = r.readUI16();
    final depth = r.readUI16();
    final matrix = r.readMatrix();
    final cxform = r.readCxform(withAlpha: true);
    records.add(ButtonRecord(
      stateUp: flags & 0x01 != 0,
      stateOver: flags & 0x02 != 0,
      stateDown: flags & 0x04 != 0,
      stateHitTest: flags & 0x08 != 0,
      characterId: characterId,
      depth: depth,
      matrix: matrix,
      cxform: cxform,
    ));
  }

  final condActions = <ButtonCondAction>[];
  if (actionOffset != 0) {
    // actionOffsetはオフセットフィールド自身の位置基準
    var pos = actionOffsetPos + actionOffset;
    while (pos + 4 <= tagBody.length) {
      final size = tagBody[pos] | (tagBody[pos + 1] << 8);
      final cond = tagBody[pos + 2] | (tagBody[pos + 3] << 8);
      final end = size == 0 ? tagBody.length : pos + size;
      final actions = Uint8List.sublistView(tagBody, pos + 4, end);
      condActions.add(ButtonCondAction(
        keyPress: (cond >> 9) & 0x7F,
        overDownToOverUp: cond & 0x0008 != 0,
        overUpToOverDown: cond & 0x0004 != 0,
        idleToOverUp: cond & 0x0001 != 0,
        actions: actions,
      ));
      if (size == 0) break;
      pos += size;
    }
  }
  return ButtonCharacter(id, records, condActions);
}
