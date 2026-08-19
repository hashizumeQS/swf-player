import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../io/swf_bit_reader.dart';
import '../model/character.dart';
import '../model/swf_movie.dart';
import '../model/timeline.dart';
import 'button_parser.dart';
import 'shape_parser.dart';
import 'tag_codes.dart';
import 'text_parser.dart';

export 'shape_parser.dart' show SwfParseException;

/// SWF4（Flash Lite 1.x）バイナリのパーサ。
class SwfParser {
  SwfParser._(this._data);

  final Uint8List _data;
  final Map<int, Character> _dictionary = {};
  RgbaColor? _backgroundColor;

  static SwfMovie parse(Uint8List data) =>
      SwfParser._(_decompressIfNeeded(data))._parse();

  /// CWS（zlib圧縮SWF）なら展開してFWS相当のバイト列に正規化する。
  ///
  /// 圧縮対象はファイル先頭8バイト（シグネチャ+バージョン+全長）を除く残り全体。
  static Uint8List _decompressIfNeeded(Uint8List data) {
    final isCws = data.length >= 8 &&
        data[0] == 0x43 &&
        data[1] == 0x57 &&
        data[2] == 0x53;
    if (!isCws) return data;

    final List<int> inflated;
    try {
      inflated = const ZLibDecoder().decodeBytes(data.sublist(8));
    } on Object catch (e) {
      throw SwfParseException('CWS本体のzlib展開に失敗しました: $e');
    }
    if (inflated.isEmpty) {
      throw SwfParseException('CWS本体のzlib展開結果が空です');
    }
    final out = Uint8List(8 + inflated.length);
    out.setRange(0, 8, data);
    out[0] = 0x46; // 'F': 以降はFWSとして扱う
    out.setRange(8, out.length, inflated);
    return out;
  }

  SwfMovie _parse() {
    if (_data.length < 8 ||
        _data[0] != 0x46 ||
        _data[1] != 0x57 ||
        _data[2] != 0x53) {
      throw SwfParseException('FWS/CWSシグネチャではありません');
    }
    final version = _data[3];
    final r = SwfBitReader(_data, 8);
    final stageRect = r.readRect();
    final frameRate = r.readFixed8();
    final frameCount = r.readUI16();

    final timeline = _parseTags(r, endPos: _data.length);

    return SwfMovie(
      version: version,
      stageRect: stageRect,
      frameRate: frameRate,
      frameCount: frameCount,
      backgroundColor: _backgroundColor,
      dictionary: _dictionary,
      mainTimeline: timeline,
    );
  }

  /// タグ列を読み、タイムライン（フレーム列）を構築する。
  /// DefineXxxは辞書へ、制御タグは現在フレームへ積む。
  Timeline _parseTags(SwfBitReader r, {required int endPos}) {
    final frames = <SwfFrame>[];
    final labels = <String, int>{};
    var current = SwfFrame();

    while (r.bytePosition < endPos) {
      final tagCodeAndLength = r.readUI16();
      final tagCode = tagCodeAndLength >> 6;
      var length = tagCodeAndLength & 0x3F;
      if (length == 0x3F) length = r.readUI32();
      final body = r.readBytes(length);
      final tr = SwfBitReader(body);

      switch (tagCode) {
        case TagCode.end:
          if (current.ops.isNotEmpty || current.actions.isNotEmpty) {
            frames.add(current);
          }
          return Timeline(frames, labels);

        case TagCode.showFrame:
          frames.add(current);
          current = SwfFrame();

        case TagCode.setBackgroundColor:
          _backgroundColor =
              RgbaColor(tr.readUI8(), tr.readUI8(), tr.readUI8());

        case TagCode.frameLabel:
          final label = tr.readString();
          labels[label] = frames.length;
          current = SwfFrame(
              ops: current.ops, actions: current.actions, label: label);

        case TagCode.doAction:
          current.actions.add(body);

        case TagCode.placeObject2:
          current.ops.add(_parsePlaceObject2(tr));

        case TagCode.removeObject2:
          current.ops.add(RemoveOp(tr.readUI16()));

        case TagCode.defineShape:
          _defineShape(tr, 1);
        case TagCode.defineShape2:
          _defineShape(tr, 2);
        case TagCode.defineShape3:
          _defineShape(tr, 3);

        case TagCode.defineSprite:
          final id = tr.readUI16();
          tr.readUI16(); // sprite frameCount
          final spriteTimeline = _parseTags(tr, endPos: body.length);
          _dictionary[id] = SpriteCharacter(id, spriteTimeline);

        case TagCode.defineBitsLossless:
          _defineBitmap(tr, body, BitmapFormat.lossless1);
        case TagCode.defineBitsLossless2:
          _defineBitmap(tr, body, BitmapFormat.lossless2);
        case TagCode.defineBitsJpeg3:
          _defineBitmap(tr, body, BitmapFormat.jpeg3);

        case TagCode.defineEditText:
          final c = parseDefineEditText(tr);
          _dictionary[c.id] = c;

        case TagCode.defineButton2:
          final c = parseDefineButton2(tr, body);
          _dictionary[c.id] = c;

        case TagCode.defineFont2:
          final c = parseDefineFont2(tr);
          _dictionary[c.id] = c;

        case TagCode.defineText:
          final c = parseDefineText(tr);
          _dictionary[c.id] = c;

        case TagCode.soundStreamHead2 || TagCode.protect:
          break; // 対象外（音声データなし・保護フラグ）

        default:
          // 未知タグは警告せず保持のみ（M1では出現しない想定）
          break;
      }
    }
    // Endタグなしで終端に達した場合
    if (current.ops.isNotEmpty || current.actions.isNotEmpty) {
      frames.add(current);
    }
    return Timeline(frames, labels);
  }

  void _defineShape(SwfBitReader tr, int version) {
    final id = tr.readUI16();
    final bounds = tr.readRect();
    final shape = ShapeParser(tr, version).readShapeWithStyle();
    _dictionary[id] = ShapeCharacter(id, bounds, shape, version);
  }

  void _defineBitmap(SwfBitReader tr, Uint8List body, BitmapFormat format) {
    final id = tr.readUI16();
    _dictionary[id] =
        BitmapCharacter(id, format, Uint8List.sublistView(body, 2));
  }

  PlaceOp _parsePlaceObject2(SwfBitReader tr) {
    final flags = tr.readUI8();
    final depth = tr.readUI16();
    final hasClipActions = flags & 0x80 != 0;
    if (hasClipActions) {
      throw SwfParseException('ClipActionsは未対応（対象SWFでは出現しない想定）');
    }
    return PlaceOp(
      depth: depth,
      move: flags & 0x01 != 0,
      characterId: flags & 0x02 != 0 ? tr.readUI16() : null,
      matrix: flags & 0x04 != 0 ? tr.readMatrix() : null,
      cxform: flags & 0x08 != 0 ? tr.readCxform(withAlpha: true) : null,
      ratio: flags & 0x10 != 0 ? tr.readUI16() : null,
      name: flags & 0x20 != 0 ? tr.readString() : null,
      clipDepth: flags & 0x40 != 0 ? tr.readUI16() : null,
    );
  }
}
