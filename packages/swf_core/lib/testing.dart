/// テスト・デモ用の合成SWF生成ユーティリティ。
///
/// [SwfBuilder]でタグ列からSWFバイナリを、[Asm]でSWF4バイトコードを
/// 組み立てられる。実SWFに依存しないテストフィクスチャや、権利的に
/// クリーンなサンプルコンテンツの生成に使う。
library;

export 'src/testing/asm.dart';
export 'src/testing/swf_builder.dart';
