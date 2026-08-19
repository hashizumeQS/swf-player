/// SWF CondKeyPressコードの定数群。
///
/// SWF仕様のButtonCondAction（CondKeyPress）で用いられるキーコード。
/// 方向・決定キーは特殊コード（1,2,13,14,15）、テンキー・記号キーは
/// ASCIIコードが割り当てられる。`SwfStage.dispatchKey` へそのまま渡せる値。
abstract final class SwfKeyCode {
  static const left = 1;
  static const right = 2;
  static const enter = 13;
  static const up = 14;
  static const down = 15;
  static const asterisk = 42;
  static const hash = 35;
  static const digit0 = 48;
  static const digit1 = 49;
  static const digit2 = 50;
  static const digit3 = 51;
  static const digit4 = 52;
  static const digit5 = 53;
  static const digit6 = 54;
  static const digit7 = 55;
  static const digit8 = 56;
  static const digit9 = 57;
}
