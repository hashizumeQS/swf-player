/// Flash 4（SWF4）の値。文字列と数値のみが存在し、型は暗黙変換される。
sealed class FlashValue {
  const FlashValue();

  static const zero = FlashNumber(0);
  static const one = FlashNumber(1);
  static const emptyString = FlashString('');

  factory FlashValue.fromBool(bool b) => b ? one : zero;

  double toNumber();

  String toFlashString();

  /// Flash4の真偽判定: 数値化して非ゼロなら真。
  bool get isTruthy => toNumber() != 0;
}

/// 数値。
class FlashNumber extends FlashValue {
  const FlashNumber(this.value);
  final double value;

  @override
  double toNumber() => value;

  @override
  String toFlashString() {
    if (value == value.truncateToDouble() && value.isFinite) {
      return value.truncate().toString();
    }
    return value.toString();
  }
}

/// 文字列。
class FlashString extends FlashValue {
  const FlashString(this.value);
  final String value;

  @override
  double toNumber() {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 0;
    return double.tryParse(trimmed) ?? 0;
  }

  @override
  String toFlashString() => value;
}
