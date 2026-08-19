# swf_player

[![pub package](https://img.shields.io/pub/v/swf_player.svg)](https://pub.dev/packages/swf_player)
[![CI](https://github.com/hashizumeQS/swf-player/actions/workflows/ci.yaml/badge.svg)](https://github.com/hashizumeQS/swf-player/actions/workflows/ci.yaml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/hashizumeQS/swf-player/blob/main/packages/swf_player/LICENSE)

Flutter widgets for playing SWF4 / **Flash Lite 1.x** content — the format
used by Japanese feature-phone era games and animations. Built on the
pure-Dart [`swf_core`](https://pub.dev/packages/swf_core) runtime.
Works on all Flutter platforms, including Web.

*[日本語の説明は下にあります](#日本語)*

<img src="https://raw.githubusercontent.com/hashizumeQS/swf-player/main/doc/example_screenshot.png" alt="example app: SWF stage with a virtual feature-phone keypad" width="300">

## Features

- **`SwfPlayerView`** — drop-in playback widget: frame-rate-accurate
  ticker (with catch-up limiting), physical keyboard input, tap dispatch,
  and stage rendering via `CustomPainter`.
- **`SwfPlayerController`** — owns the playback state: `load()` SWF bytes
  (FWS/CWS), pause/resume, key/tap dispatch with optional remapping,
  ActionScript variable access, and root-timeline label notifications
  (e.g. detecting a "game over" frame to show your own UI).
- **`KeypadWidget`** — a feature-phone style virtual keypad (D-pad ring +
  numeric keys with long-press auto-repeat) that pairs naturally with
  `CondKeyPress`-driven Flash Lite content.
- Renders shapes (with gradients and bitmap fills), lossless/JPEG/JPEG3
  bitmaps, static and dynamic texts, buttons, color transforms, and
  clip-depth masks.

Out of scope: ActionScript 2/3, video, sound, and SWF5+ tags. See the
[`swf_core` README](https://pub.dev/packages/swf_core) for the detailed
supported tag/opcode set.

## Quick start

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:swf_player/swf_player.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.swfBytes});
  final Uint8List swfBytes;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final controller = SwfPlayerController();

  @override
  void initState() {
    super.initState();
    controller.onRootLabel = (label) {
      if (label == 'over') debugPrint('game over!');
    };
    controller.load(widget.swfBytes);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      AspectRatio(
        aspectRatio: 1,
        child: SwfPlayerView(controller: controller),
      ),
      Expanded(
        child: KeypadWidget(onKey: controller.dispatchKey),
      ),
    ]);
  }
}
```

Loading from a Flutter asset:

```dart
final data = await rootBundle.load('assets/movie.swf');
await controller.load(data.buffer.asUint8List());
```

## Input

`SwfPlayerView` maps physical keyboards automatically: arrow keys,
Enter/Space (decision key), digits `0`–`9` (main row and numpad), `*`, and
`#`. For on-screen input, route key codes through
`controller.dispatchKey` using the `SwfKeyCode` constants — `KeypadWidget`
does exactly that.

Per-title quirks are handled on the controller:

- `controller.keyMap = {SwfKeyCode.digit2: SwfKeyCode.up}` remaps keys
  (some PC-oriented content binds unusual keys).
- `controller.paused = true` freezes playback and blocks input — useful
  while your own overlay (menu, score dialog) is on top.

## Advanced hooks

- `movieTransformer` (constructor parameter): mutate the parsed
  `SwfMovie` before playback — e.g. patch a timeline or hide characters
  from legacy content.
- `hiddenCharacterIds` / `overridePositionsPx`: per-character render
  tweaks, also excluded from input hit-testing.
- `SwfHost` (constructor parameter): intercept `trace`, `GetURL`, and
  `FSCommand2` calls from the content.
- `getVariable('score')`: read ActionScript variables — combined with
  `onRootLabel`, this is enough to build score/ranking integrations.

## Example

The bundled [example](https://pub.dev/packages/swf_player/example)
generates its demo SWF **at runtime** with
[`package:swf_core/testing.dart`](https://pub.dev/documentation/swf_core/latest/testing/)
(`SwfBuilder` / `Asm`) — no copyrighted content is bundled anywhere in
this repository.

## 日本語

ガラケー（フィーチャーフォン）時代の **Flash Lite 1.x（SWF4）** ゲーム・
アニメをFlutterで再生するパッケージです。`SwfPlayerView` を置いて
`SwfPlayerController.load()` にバイト列を渡すだけで再生でき、物理キーボード・
タップ・バーチャルキーパッド（`KeypadWidget`、十字リング＋テンキー＋長押し
リピート）に対応します。`onRootLabel` と `getVariable()` でゲームオーバー
検知やスコア読み出しができ、独自のランキングUIと組み合わせられます。
Web含む全プラットフォームで動作します。音声・動画・ActionScript 2/3は
対象外です。

## License

MIT
