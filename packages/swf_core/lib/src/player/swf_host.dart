import 'dart:math';

import '../vm/flash_value.dart';

/// VMからホスト環境への出口（通信・端末機能・時刻・乱数）。
/// テストではモックを注入して決定的に実行できる。
abstract class SwfHost {
  void trace(String message);

  /// GetURL/GetURL2。実通信は行わず、ホスト実装がログ出力や
  /// アプリ固有の処理に差し替える。
  void getUrl(String url, String target);

  /// Flash Lite固有のFSCommand2。戻り値はスタックに積まれる。
  FlashValue fsCommand2(String command, List<FlashValue> args);

  /// GetTime用: 起動からの経過ミリ秒。
  double get timeMs;

  /// RandomNumber用: 0以上max未満の整数。
  int random(int max);
}

/// 既定実装: 日付・時刻系FSCommand2は実値を返し、その他は-1(no-op)。
///
/// trace/getUrlは[log]コールバックへ出力する（未指定ならno-op）。
class DefaultSwfHost implements SwfHost {
  DefaultSwfHost({Random? random, DateTime Function()? now, this.log})
      : _random = random ?? Random(),
        _now = now ?? DateTime.now;

  final Random _random;
  final DateTime Function() _now;
  final Stopwatch _stopwatch = Stopwatch()..start();

  /// trace/getUrlの出力先（nullならno-op）。
  final void Function(String message)? log;

  @override
  void trace(String message) {
    log?.call('[trace] $message');
  }

  @override
  void getUrl(String url, String target) {
    log?.call('[getUrl(stub)] $url (target: $target)');
  }

  @override
  FlashValue fsCommand2(String command, List<FlashValue> args) {
    final now = _now();
    switch (command) {
      case 'GetDateYear':
        return FlashNumber(now.year.toDouble());
      case 'GetDateMonth':
        return FlashNumber(now.month.toDouble());
      case 'GetDateDay':
        return FlashNumber(now.day.toDouble());
      case 'GetDateWeekday':
        // Flash Lite: 0=日曜。DartのweekdayはMon=1..Sun=7
        return FlashNumber((now.weekday % 7).toDouble());
      case 'GetTimeHours':
        return FlashNumber(now.hour.toDouble());
      case 'GetTimeMinutes':
        return FlashNumber(now.minute.toDouble());
      case 'GetTimeSeconds':
        return FlashNumber(now.second.toDouble());
      case 'GetTimeZoneOffset':
        return FlashNumber(now.timeZoneOffset.inMinutes.toDouble());
      default:
        // SetQuality/FullScreen/Vibrate等はno-op
        return const FlashNumber(-1);
    }
  }

  @override
  double get timeMs => _stopwatch.elapsedMilliseconds.toDouble();

  @override
  int random(int max) => max <= 0 ? 0 : _random.nextInt(max);
}
