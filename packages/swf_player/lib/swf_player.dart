/// SWF4 / Flash Lite 1.x コンテンツを再生するFlutterウィジェット群。
///
/// 描画（[StagePainter]）・ビットマップ管理（[BitmapRegistry]）・
/// テキスト描画（[EditTextRenderer]）などのレンダリング層を提供する。
///
/// swf_coreの公開APIも便宜上すべて再exportする（本パッケージはcoreと
/// 同一リポジトリで同期リリースされ、利用時はSwfStage等のcore型を
/// 直接扱うため）。coreだけ使う場合はswf_coreを直接importすればよい。
library;

export 'package:swf_core/swf_core.dart';

export 'src/controller/swf_player_controller.dart';
export 'src/keyboard/swf_key_mapping.dart';
export 'src/widgets/keypad_widget.dart';
export 'src/widgets/swf_player_view.dart';
export 'src/render/bitmap_registry.dart';
export 'src/render/fill_paint_factory.dart';
export 'src/render/shape_path_builder.dart';
export 'src/render/stage_painter.dart';
export 'src/render/text_renderer.dart';
