# swf_player

Flutter widgets for playing SWF4 / **Flash Lite 1.x** content — the format
used by Japanese feature-phone era games and animations. Built on the
pure-Dart [`swf_core`](https://pub.dev/packages/swf_core) runtime.

## Features

- **`SwfPlayerView`** — drop-in playback widget: frame-rate-accurate
  ticker, physical keyboard input, tap dispatch, and stage rendering.
- **`SwfPlayerController`** — owns the playback state: `load()` SWF bytes,
  pause/resume, key/tap dispatch with optional remapping, ActionScript
  variable access, and root-timeline label notifications (e.g. detecting
  a "game over" frame).
- **`KeypadWidget`** — a feature-phone style virtual keypad (D-pad ring +
  numeric keys with long-press auto-repeat) that pairs naturally with
  `CondKeyPress`-driven Flash Lite content.
- Renders shapes (with gradients and bitmap fills), lossless/JPEG/JPEG3
  bitmaps, static and dynamic texts, buttons, color transforms, and
  clip-depth masks.

Out of scope: ActionScript 2/3, video, sound, and SWF5+ tags.

## Usage

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

`SwfPlayerView` handles physical keyboards automatically
(arrows / Enter / Space / digits / `*` / `#`). Route on-screen input
through `controller.dispatchKey` with the `SwfKeyCode` constants.

See `example/` for a complete app that generates a demo SWF at runtime
with `package:swf_core/testing.dart` — no copyrighted content required.

## License

MIT
