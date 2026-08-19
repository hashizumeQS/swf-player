import 'package:swf_core/swf_core.dart';
import 'package:test/test.dart';

void main() {
  group('SwfKeyCode', () {
    test('方向・決定キーはSWF仕様のCondKeyPressコードと一致する', () {
      expect(SwfKeyCode.left, 1);
      expect(SwfKeyCode.right, 2);
      expect(SwfKeyCode.enter, 13);
      expect(SwfKeyCode.up, 14);
      expect(SwfKeyCode.down, 15);
    });

    test('テンキー・記号キーはASCIIコードと一致する', () {
      expect(SwfKeyCode.asterisk, 42);
      expect(SwfKeyCode.hash, 35);
      expect(SwfKeyCode.digit0, 48);
      expect(SwfKeyCode.digit9, 57);
      // digit0..digit9 が連番であること
      const digits = [
        SwfKeyCode.digit0,
        SwfKeyCode.digit1,
        SwfKeyCode.digit2,
        SwfKeyCode.digit3,
        SwfKeyCode.digit4,
        SwfKeyCode.digit5,
        SwfKeyCode.digit6,
        SwfKeyCode.digit7,
        SwfKeyCode.digit8,
        SwfKeyCode.digit9,
      ];
      for (var i = 0; i < digits.length; i++) {
        expect(digits[i], SwfKeyCode.digit0 + i);
      }
    });
  });
}
