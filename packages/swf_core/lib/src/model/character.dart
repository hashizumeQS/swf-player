import 'dart:typed_data';

import 'basic_types.dart';
import 'shape_records.dart';
import 'swf_movie.dart' show RgbaColor;
import 'timeline.dart';

/// SWF辞書に登録されるキャラクタ（DefineXxxタグの成果物）。
sealed class Character {
  const Character(this.id);
  final int id;
}

/// ベクタシェイプ（DefineShape/DefineShape2/DefineShape3）から生成されたキャラクタ。
class ShapeCharacter extends Character {
  const ShapeCharacter(super.id, this.bounds, this.shape, this.shapeVersion);

  /// シェイプの境界矩形（twips座標系）。
  final SwfRect bounds;

  /// 塗り・線スタイルとシェイプレコード列。
  final ShapeWithStyle shape;

  /// 1=DefineShape, 2=DefineShape2, 3=DefineShape3(RGBA)
  final int shapeVersion;
}

/// 入れ子のタイムラインを持つキャラクタ（MovieClip相当、DefineSprite由来）。
class SpriteCharacter extends Character {
  const SpriteCharacter(super.id, this.timeline);

  /// このスプライトが持つ独立したフレーム・タイムライン。
  final Timeline timeline;
}

/// ビットマップ（デコードはレンダリング層で遅延実行）。
class BitmapCharacter extends Character {
  const BitmapCharacter(super.id, this.format, this.data);

  final BitmapFormat format;

  /// タグ本体のうちcharacterId以降の生バイト列。
  final Uint8List data;
}

/// [BitmapCharacter.format]が示すビットマップの格納形式。
///
/// lossless1/lossless2はDefineBitsLossless(2)由来のzlib圧縮可逆画像、
/// jpeg3はDefineBitsJPEG3由来のJPEG本体（+ 任意のアルファ面）。
enum BitmapFormat { lossless1, lossless2, jpeg3 }

/// 編集可能／動的テキストフィールド（DefineEditText由来）。
///
/// ActionScriptの変数バインディング（[variableName]）や入力欄としても使われる。
class EditTextCharacter extends Character {
  const EditTextCharacter(
    super.id, {
    required this.bounds,
    required this.variableName,
    required this.initialText,
    required this.fontId,
    required this.fontHeightTwips,
    required this.textColor,
    required this.align,
    required this.leftMarginTwips,
    required this.rightMarginTwips,
    required this.hasBorder,
    required this.isMultiline,
    required this.useOutlines,
  });

  /// テキストフィールドの境界矩形（twips座標系）。
  final SwfRect bounds;

  /// ActionScript側からこのテキストフィールドを参照するための変数名。
  final String variableName;

  /// 初期表示テキスト。タグにテキスト本体が含まれない場合はnull。
  final String? initialText;

  /// 使用フォントのキャラクタID。nullの場合は端末のデバイスフォントを使う。
  final int? fontId;
  final int fontHeightTwips;
  final RgbaColor? textColor;

  /// 0=left, 1=right, 2=center, 3=justify
  final int align;
  final int leftMarginTwips;
  final int rightMarginTwips;
  final bool hasBorder;
  final bool isMultiline;

  /// trueならフォントのアウトライン（埋め込みグリフ）を使用、falseならデバイスフォント任せ。
  final bool useOutlines;
}

/// ボタン（DefineButton/DefineButton2由来）。表示状態ごとのキャラクタ配置と、
/// クリック等の操作に応じて発火するアクションを保持する。
class ButtonCharacter extends Character {
  const ButtonCharacter(super.id, this.records, this.condActions);

  /// 各状態（up/over/down/hitTest）でのキャラクタ配置一覧。
  final List<ButtonRecord> records;

  /// 状態遷移に応じて実行される条件付きアクション一覧。
  final List<ButtonCondAction> condActions;
}

/// 埋め込みフォント（DefineFont2由来）。グリフ形状と文字コード対応表を持つ。
class FontCharacter extends Character {
  const FontCharacter(
    super.id, {
    required this.name,
    required this.glyphs,
    required this.codeTable,
    required this.advances,
  });

  /// フォント名。
  final String name;

  /// グリフindexに対応するシェイプ形状の一覧。
  final List<GlyphShape> glyphs;

  /// グリフindex → 文字コード（Unicode変換済み）。
  final List<int> codeTable;

  /// EM square(1024)単位のグリフ送り幅。レイアウト情報が無い場合は空。
  final List<int> advances;

  bool get hasGlyphs => glyphs.isNotEmpty;
}

/// 静的テキスト（DefineText由来）。編集不可で、グリフをテキストレコード単位で
/// 直接配置する。
class StaticTextCharacter extends Character {
  const StaticTextCharacter(super.id, this.bounds, this.matrix, this.records);

  /// テキストの境界矩形（twips座標系）。
  final SwfRect bounds;

  /// テキスト全体に適用される変換行列。
  final SwfMatrix matrix;

  /// 描画順のテキストレコード列。
  final List<TextRecord> records;
}

/// DefineTextのTEXTRECORD。フォント・色・オフセットは省略可能で、
/// nullの場合は直前のレコードの値を引き継ぐ。
class TextRecord {
  const TextRecord({
    required this.fontId,
    required this.color,
    required this.xOffsetTwips,
    required this.yOffsetTwips,
    required this.textHeightTwips,
    required this.glyphs,
  });

  /// フォント切り替え時のみ設定。nullなら直前のレコードのフォントを継続。
  final int? fontId;

  /// 色変更時のみ設定。nullなら直前のレコードの色を継続。
  final RgbaColor? color;

  /// 水平オフセット（twips）。nullなら現在位置からの継続。
  final int? xOffsetTwips;

  /// 垂直オフセット（twips）。nullなら現在位置からの継続。
  final int? yOffsetTwips;

  /// フォントサイズ（twips）。fontIdと同時に設定される。
  final int? textHeightTwips;

  /// このレコードで描画するグリフ列。
  final List<GlyphEntry> glyphs;
}

/// TEXTRECORD内の1グリフ配置。
class GlyphEntry {
  const GlyphEntry(this.glyphIndex, this.advanceTwips);

  /// フォントのグリフ配列（[FontCharacter.glyphs]）へのindex。
  final int glyphIndex;

  /// 次のグリフまでの送り幅（twips）。
  final int advanceTwips;
}

/// 解釈対象外のタグ（情報保持のみ）。
class UnknownCharacter extends Character {
  const UnknownCharacter(super.id, this.tagCode);
  final int tagCode;
}
