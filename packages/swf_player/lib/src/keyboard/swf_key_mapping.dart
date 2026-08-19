import 'package:flutter/services.dart';
import 'package:swf_core/swf_core.dart';

/// 物理キーボード → SWF CondKeyPressコード変換表。
final _physicalKeyToSwf = <LogicalKeyboardKey, int>{
  LogicalKeyboardKey.arrowLeft: SwfKeyCode.left,
  LogicalKeyboardKey.arrowRight: SwfKeyCode.right,
  LogicalKeyboardKey.arrowUp: SwfKeyCode.up,
  LogicalKeyboardKey.arrowDown: SwfKeyCode.down,
  LogicalKeyboardKey.enter: SwfKeyCode.enter,
  LogicalKeyboardKey.space: SwfKeyCode.enter,
  LogicalKeyboardKey.numpadEnter: SwfKeyCode.enter,
  LogicalKeyboardKey.asterisk: SwfKeyCode.asterisk,
  LogicalKeyboardKey.numpadMultiply: SwfKeyCode.asterisk,
  LogicalKeyboardKey.numberSign: SwfKeyCode.hash,
};

/// 物理キーボードのキーをSWF CondKeyPressコードへ変換する。
///
/// 方向キー・Enter/Space・テンキー記号は個別対応表で、数字はメイン列・
/// テンキーの両方をdigit0..9へ写像する。対象外のキーはnull。
int? swfKeyCodeForLogicalKey(LogicalKeyboardKey key) {
  final mapped = _physicalKeyToSwf[key];
  if (mapped != null) return mapped;
  final id = key.keyId;
  if (id >= LogicalKeyboardKey.digit0.keyId &&
      id <= LogicalKeyboardKey.digit9.keyId) {
    return SwfKeyCode.digit0 + (id - LogicalKeyboardKey.digit0.keyId);
  }
  if (id >= LogicalKeyboardKey.numpad0.keyId &&
      id <= LogicalKeyboardKey.numpad9.keyId) {
    return SwfKeyCode.digit0 + (id - LogicalKeyboardKey.numpad0.keyId);
  }
  return null;
}
