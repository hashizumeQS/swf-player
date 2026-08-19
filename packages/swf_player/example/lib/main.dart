import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:swf_player/swf_player.dart';

import 'demo_swf.dart';

void main() {
  runApp(const SwfPlayerExampleApp());
}

/// swf_player公開API（SwfPlayerController/SwfPlayerView/KeypadWidget）の
/// 最小サンプルアプリ。デモコンテンツは著作物を使わず[buildDemoSwf]で
/// 実行時に自己完結生成する。
class SwfPlayerExampleApp extends StatelessWidget {
  const SwfPlayerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'swf_player example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const PlayerPage(),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _controller = SwfPlayerController();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _controller.onRootLabel = _handleRootLabel;
    unawaited(_controller.load(buildDemoSwf()));
  }

  void _handleRootLabel(String label) {
    if (label != 'over') return;
    _scaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('Reached the "over" label')),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('swf_player example')),
        body: SafeArea(
          // 画面高をステージ（正方形）とキーパッドで分け合い、キーパッドは
          // 残り領域へ等比縮小で収める（小型・横向きでもoverflowしない）
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stageSide = math.min(
                constraints.maxWidth - 32,
                constraints.maxHeight / 2,
              );
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: stageSide,
                      height: stageSide,
                      child: SwfPlayerView(controller: _controller),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: 320,
                          child: KeypadWidget(onKey: _controller.dispatchKey),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
