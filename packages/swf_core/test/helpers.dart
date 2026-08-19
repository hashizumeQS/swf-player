import 'dart:typed_data';

import 'package:swf_core/swf_core.dart';

/// 最小バイトコード: var = value
Uint8List setVarBytecode(String name, String value) {
  final nameBytes = encodeSjis(name);
  final valueBytes = encodeSjis(value);
  return Uint8List.fromList([
    0x96,
    nameBytes.length + 2,
    0x00,
    0x00,
    ...nameBytes,
    0x00,
    0x96,
    valueBytes.length + 2,
    0x00,
    0x00,
    ...valueBytes,
    0x00,
    0x1D,
    0x00,
  ]);
}

/// 決定的・無音のテスト用ホスト。
class TestHost implements SwfHost {
  final List<String> traces = [];
  final List<(String, String)> urls = [];
  final List<(String, List<FlashValue>)> fsCommands = [];
  int nextRandom = 0;
  int? lastRandomMax;
  double time = 0;

  /// FSCommand2日付系の固定日時: 2026-08-15(土) 12:30:45
  final DateTime fixedNow = DateTime(2026, 8, 15, 12, 30, 45);

  @override
  void trace(String message) => traces.add(message);

  @override
  void getUrl(String url, String target) => urls.add((url, target));

  @override
  FlashValue fsCommand2(String command, List<FlashValue> args) {
    fsCommands.add((command, args));
    return DefaultSwfHost(now: () => fixedNow).fsCommand2(command, args);
  }

  @override
  double get timeMs => time;

  @override
  int random(int max) {
    lastRandomMax = max;
    return nextRandom;
  }
}
