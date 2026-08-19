import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:swf_core/swf_core.dart';

/// 1px = 20twips。
const int _twipsPerPixel = 20;

/// テスト用の合成SWFフィクスチャビルダー。
///
/// [SwfParser]が読める最小限の形式でタグを組み立てる。実SWF（著作物）に
/// 依存するテストを、このビルダーが生成する合成SWFへ置き換えるための基盤。
class SwfBuilder {
  /// [version]・ステージサイズ（[widthPx] x [heightPx]）・[frameRate]を指定して
  /// ビルダーを生成する。既定値はテストで一般的に使う最小構成。
  SwfBuilder({
    this.version = 4,
    this.widthPx = 240,
    this.heightPx = 240,
    this.frameRate = 12,
  });

  /// ネストしたタイムライン（DefineSprite内）用。
  SwfBuilder._nested()
      : version = 4,
        widthPx = 0,
        heightPx = 0,
        frameRate = 12;

  /// SWFファイルバージョン（ヘッダの版数バイトに書き込まれる）。
  /// [buildCompressed]はこれが6未満の場合に組み立てを拒否する。
  final int version;

  /// ステージ幅（px単位）。[build]でtwipsへ換算しヘッダのRECT（フレームサイズ）に書き込む。
  final int widthPx;

  /// ステージ高さ（px単位）。[build]でtwipsへ換算しヘッダのRECT（フレームサイズ）に書き込む。
  final int heightPx;

  /// フレームレート（fps）。[build]で8.8固定小数点（値×256をUI16化）としてヘッダに書き込む。
  final double frameRate;

  final List<int> _tagBytes = [];
  int _frameCount = 0;

  static const List<int> _endTagBytes = [0, 0];

  /// SetBackgroundColor(タグ9)。背景色を[r]・[g]・[b]（各0-255）の順にUI8 3byteとして
  /// タグボディへそのまま書き込む。
  void setBackgroundColor(int r, int g, int b) {
    _writeTag(TagCode.setBackgroundColor, [r, g, b]);
  }

  /// 単色塗りの矩形シェイプをDefineShape(タグ2/バージョン1)として定義する。
  void defineShapeRect(
    int id, {
    required int widthPx,
    required int heightPx,
    int fillRgb = 0x000000,
  }) {
    final widthTwips = widthPx * _twipsPerPixel;
    final heightTwips = heightPx * _twipsPerPixel;

    final bw = BitWriter();
    bw.writeUI16(id);
    _writeRect(bw, 0, widthTwips, 0, heightTwips);

    // fill styles: solid 1個
    bw.writeUI8(1);
    bw.writeUI8(0x00); // solid fill
    bw.writeUI8((fillRgb >> 16) & 0xFF);
    bw.writeUI8((fillRgb >> 8) & 0xFF);
    bw.writeUI8(fillRgb & 0xFF);

    // line styles: なし
    bw.writeUI8(0);

    // shape records: MoveTo省略（原点0,0開始）→ 矩形の辺4本 → End
    final edgeBits =
        _neededSignedBits([widthTwips, heightTwips, -widthTwips, -heightTwips])
            .clamp(2, 17);
    bw.writeUB(4, 1); // numFillBits=1（fillStyle index 1が入る）
    bw.writeUB(4, 0); // numLineBits=0

    // StyleChangeRecord: fillStyle1=1を選択
    bw.writeUB(1, 0); // isEdge=false
    bw.writeUB(5, 0x04); // flags: fillStyle1あり
    bw.writeUB(1, 1); // fillStyle1 = 1 (numFillBits=1bit)

    void edge(int dx, int dy) {
      bw.writeUB(1, 1); // isEdge
      bw.writeUB(1, 1); // isStraight
      bw.writeUB(4, edgeBits - 2);
      bw.writeUB(1, 1); // isGeneral
      bw.writeSB(edgeBits, dx);
      bw.writeSB(edgeBits, dy);
    }

    edge(widthTwips, 0);
    edge(0, heightTwips);
    edge(-widthTwips, 0);
    edge(0, -heightTwips);

    // EndShapeRecord
    bw.writeUB(1, 0);
    bw.writeUB(5, 0);
    bw.align();

    _writeTag(TagCode.defineShape, bw.toBytes());
  }

  /// PlaceObject2(タグ26)。指定[depth]にキャラクターを配置または既存インスタンスを更新する。
  ///
  /// [characterId]を渡すとPlaceFlagHasCharacter(0x02)を立てUI16のcharacterIdを書き込み、
  /// キャラクターを新規配置する。[characterId]を省略した場合はPlaceFlagMove(0x01)を立て、
  /// 同depthの既存インスタンスを移動する呼び出しとして扱う。
  /// [translateXPx]・[translateYPx]のいずれかを渡すとPlaceFlagHasMatrix(0x04)を立て、
  /// px→twips換算した平行移動のみの行列（拡大縮小・回転なし）を書き込む。
  /// [name]を渡すとPlaceFlagHasName(0x20)を立て、SJISのnull終端文字列としてインスタンス名を
  /// 書き込む。ボディの並びはflags(UI8) → depth(UI16) → [characterId(UI16)] →
  /// [行列] → [name(STRING)]。
  void placeObject2({
    required int depth,
    int? characterId,
    int? translateXPx,
    int? translateYPx,
    String? name,
  }) {
    final hasCharacter = characterId != null;
    final hasMatrix = translateXPx != null || translateYPx != null;
    final hasName = name != null;
    final move = !hasCharacter;

    var flags = 0;
    if (move) flags |= 0x01;
    if (hasCharacter) flags |= 0x02;
    if (hasMatrix) flags |= 0x04;
    if (hasName) flags |= 0x20;

    final bw = BitWriter();
    bw.writeUI8(flags);
    bw.writeUI16(depth);
    if (hasCharacter) bw.writeUI16(characterId);
    if (hasMatrix) {
      _writeMatrixTranslateOnly(
        bw,
        (translateXPx ?? 0) * _twipsPerPixel,
        (translateYPx ?? 0) * _twipsPerPixel,
      );
    }
    if (hasName) _writeSjisString(bw, name);

    _writeTag(TagCode.placeObject2, bw.toBytes());
  }

  /// RemoveObject2(タグ28)。指定[depth]に配置中のインスタンスを取り除く。
  /// ボディはDepth(UI16)のみ。
  void removeObject2({required int depth}) {
    final bw = BitWriter();
    bw.writeUI16(depth);
    _writeTag(TagCode.removeObject2, bw.toBytes());
  }

  /// DefineButton2(タグ34)。CondKeyPress=[keyPress]のButtonCondAction 1個と、
  /// [shapeId]指定時はヒット/アップ兼用のButtonRecordを持つボタンを定義する。
  void defineButton(
    int id, {
    required int keyPress,
    required Uint8List actions,
    int? shapeId,
  }) {
    final recordBytes = <int>[];
    if (shapeId != null) {
      final rec = BitWriter();
      rec.writeUI8(0x01 | 0x08); // stateUp | stateHitTest
      rec.writeUI16(shapeId);
      rec.writeUI16(1); // depth
      _writeMatrixTranslateOnly(rec, 0, 0);
      _writeIdentityCxform(rec);
      recordBytes.addAll(rec.toBytes());
    }
    recordBytes.add(0); // ButtonRecord terminator

    final header = BitWriter();
    header.writeUI16(id);
    header.writeUI8(0); // flags (trackAsMenu)
    // actionOffset: offsetフィールド自身の位置からCondActionRecord先頭までの距離
    final offsetValue = 2 + recordBytes.length;
    header.writeUI16(offsetValue);

    final cond = (keyPress & 0x7F) << 9;
    final condBytes = <int>[
      0, 0, // size=0 → タグ末尾までを最終レコードとして扱う
      cond & 0xFF, (cond >> 8) & 0xFF,
      ...actions,
    ];

    final body = <int>[
      ...header.toBytes(),
      ...recordBytes,
      ...condBytes,
    ];
    _writeTag(TagCode.defineButton2, Uint8List.fromList(body));
  }

  /// DoAction(タグ12)。[bytecode]（[Asm]等で組み立てたActionRecord列。末尾にオペコード
  /// 0x00の終端バイトを含む想定）をそのままタグボディとして書き込む。
  void doAction(Uint8List bytecode) {
    _writeTag(TagCode.doAction, bytecode);
  }

  /// FrameLabel(タグ43)。現在フレームに付ける[label]をSJISのnull終端文字列としてボディに
  /// 書き込む。
  void frameLabel(String label) {
    final bw = BitWriter();
    _writeSjisString(bw, label);
    _writeTag(TagCode.frameLabel, bw.toBytes());
  }

  /// ShowFrame(タグ1)。ボディなし（0byte）のタグを書き込み現在のフレームを確定させ、
  /// 内部フレームカウントを1つ進める。
  void showFrame() {
    _frameCount++;
    _writeTag(TagCode.showFrame, const []);
  }

  /// DefineSprite(タグ39)。[build]でスプライト内タイムラインをネストビルドする。
  void defineSprite(int id, void Function(SwfBuilder sprite) build) {
    final sprite = SwfBuilder._nested();
    build(sprite);

    final headerBw = BitWriter();
    headerBw.writeUI16(id);
    headerBw.writeUI16(sprite._frameCount);

    final body = <int>[
      ...headerBw.toBytes(),
      ...sprite._tagBytes,
      ..._endTagBytes,
    ];
    _writeTag(TagCode.defineSprite, Uint8List.fromList(body));
  }

  /// FWSヘッダ + 蓄積したタグ列 + Endタグ。
  Uint8List build() {
    final widthTwips = widthPx * _twipsPerPixel;
    final heightTwips = heightPx * _twipsPerPixel;

    final headerBw = BitWriter();
    _writeRect(headerBw, 0, widthTwips, 0, heightTwips);
    headerBw.writeUI16((frameRate * 256).round());
    headerBw.writeUI16(_frameCount);

    final body = <int>[
      ...headerBw.toBytes(),
      ..._tagBytes,
      ..._endTagBytes,
    ];

    final fileBw = BitWriter();
    fileBw.writeBytes('FWS'.codeUnits);
    fileBw.writeUI8(version);
    fileBw.writeUI32(8 + body.length);
    fileBw.writeBytes(body);
    return fileBw.toBytes();
  }

  /// [build]のCWS（zlib圧縮SWF）版。
  ///
  /// CWSはSWF仕様上version 6以降でのみ有効なため、それ未満では組み立てを
  /// 拒否する（仕様上不正なフィクスチャの生成を防ぐ）。
  Uint8List buildCompressed() {
    if (version < 6) {
      throw ArgumentError.value(version, 'version', 'CWS（zlib圧縮）はSWF 6以降のみ');
    }
    final plain = build();
    final bodyBytes = plain.sublist(8);
    final compressed = const ZLibEncoder().encode(bodyBytes);

    final header = BitWriter();
    header.writeBytes('CWS'.codeUnits);
    header.writeUI8(version);
    header.writeUI32(plain.length);
    header.writeBytes(compressed);
    return header.toBytes();
  }

  // --- 内部ヘルパー ---

  void _writeTag(int tagCode, List<int> body) {
    final length = body.length;
    if (length < 0x3F) {
      _tagBytes.add((((tagCode << 6) | length)) & 0xFF);
      _tagBytes.add((((tagCode << 6) | length) >> 8) & 0xFF);
    } else {
      final short = (tagCode << 6) | 0x3F;
      _tagBytes.add(short & 0xFF);
      _tagBytes.add((short >> 8) & 0xFF);
      _tagBytes.add(length & 0xFF);
      _tagBytes.add((length >> 8) & 0xFF);
      _tagBytes.add((length >> 16) & 0xFF);
      _tagBytes.add((length >> 24) & 0xFF);
    }
    _tagBytes.addAll(body);
  }

  static void _writeRect(BitWriter bw, int xMin, int xMax, int yMin, int yMax) {
    final nBits = _neededSignedBits([xMin, xMax, yMin, yMax]).clamp(1, 31);
    bw.writeUB(5, nBits);
    bw.writeSB(nBits, xMin);
    bw.writeSB(nBits, xMax);
    bw.writeSB(nBits, yMin);
    bw.writeSB(nBits, yMax);
    bw.align();
  }

  static void _writeMatrixTranslateOnly(BitWriter bw, int tx, int ty) {
    bw.writeUB(1, 0); // hasScale
    bw.writeUB(1, 0); // hasRotate
    final nBits = _neededSignedBits([tx, ty]).clamp(1, 31);
    bw.writeUB(5, nBits);
    bw.writeSB(nBits, tx);
    bw.writeSB(nBits, ty);
    bw.align();
  }

  static void _writeIdentityCxform(BitWriter bw) {
    bw.writeUB(1, 0); // hasAdd
    bw.writeUB(1, 0); // hasMult
    bw.writeUB(4, 0); // nBits
    bw.align();
  }

  static void _writeSjisString(BitWriter bw, String s) {
    bw.writeBytes(encodeSjis(s));
    bw.writeUI8(0);
  }

  /// 値の集合すべてを符号付きnBitsで表現できる最小ビット数。
  static int _neededSignedBits(List<int> values) {
    var bits = 1;
    while (true) {
      final min = -(1 << (bits - 1));
      final max = (1 << (bits - 1)) - 1;
      if (values.every((v) => v >= min && v <= max)) return bits;
      bits++;
    }
  }
}
