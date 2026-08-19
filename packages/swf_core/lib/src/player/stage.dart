import '../model/basic_types.dart';
import '../model/character.dart';
import '../model/shape_records.dart';
import '../model/swf_movie.dart';
import '../vm/action_interpreter.dart';
import 'movie_clip.dart';
import 'swf_host.dart';

/// 描画層へ渡すツリーノード。
class RenderNode {
  const RenderNode({
    required this.character,
    required this.matrix,
    required this.cxform,
    required this.depth,
    this.clipDepth,
    this.clip,
    this.owner,
    this.children = const [],
  });

  /// 描画対象のキャラクタ（シェイプ・スプライト・ボタン・テキスト等）。
  final Character character;

  /// このノード単独の変換行列（twips単位、親からの累積は含まない）。
  final SwfMatrix matrix;

  /// このノード単独の色変換（親からの累積は含まない）。
  final SwfCxform cxform;

  /// 描画順に使う深度値（昇順で手前に描画）。
  final int depth;

  /// マスクとしてのクリップ深度上限。nullなら通常ノード。
  /// 非nullの場合、このノード自身は描画されず、depthより大きく
  /// clipDepth以下の兄弟ノードをクリップするマスクとして扱われる。
  final int? clipDepth;

  /// characterがSpriteCharacterの場合の対応クリップ。
  final MovieClip? clip;

  /// このノードを表示リストに持つクリップ（EditTextの変数解決用）。
  final MovieClip? owner;

  /// characterがSpriteCharacterの場合の子ノード（深度昇順）。
  final List<RenderNode> children;
}

/// ステージ: ルートタイムライン・VM・フレーム進行の入口。
class SwfStage {
  /// [movie]からルートタイムライン（`_root`）を構築し、VMを初期化した上で
  /// frame1のDoActionまで実行済みの状態でステージを生成する。
  /// [host]省略時は[DefaultSwfHost]を使う。
  SwfStage(this.movie, {SwfHost? host})
      : host = host ?? DefaultSwfHost(),
        root = MovieClip(movie.mainTimeline, movie.dictionary, name: '_root') {
    interpreter = ActionInterpreter(this.host);
    _runPendingActions(); // frame1のDoAction
  }

  /// パース済みSWFムービー（ステージ矩形・辞書・メインタイムライン等）。
  final SwfMovie movie;

  /// VMからホスト環境への出口（通信・端末機能・時刻・乱数）。
  final SwfHost host;

  /// ルートのムービークリップ（`_root`）。
  final MovieClip root;

  /// ActionScriptバイトコードの実行エンジン。
  late final ActionInterpreter interpreter;

  /// ルートタイムラインのラベル到達通知（特定ラベル到達の検知に使う）。
  set onRootLabel(void Function(String label)? callback) {
    root.onLabelEnter = callback;
  }

  /// 入力無効にするcharacterId（子孫も含めて除外）。
  /// ホスト側で非表示化したキャラクタがキー・タップ・フォーカスに
  /// 反応してしまうのを防ぐ。
  Set<int> inputDisabledCharacterIds = const {};

  /// goto連鎖の暴走防止（1回のポンプで処理するパス数上限）。
  static const _maxActionPasses = 32;

  /// 全タイムラインを1フレーム進め、各フレームのDoActionを実行する。
  /// ラベル到達通知はアクション消化後に排出する（goto連鎖時は最終フレームのみ）。
  void advanceFrame() {
    root.enterFrame();
    _runPendingActions();
    flushLabelEvents();
  }

  /// 未排出のラベル到達イベントを排出する。
  /// VM経由のgotoはadvanceFrame/dispatchKeyが自動排出する。
  /// テストやツールから直接root.gotoFrame()した場合はこれを呼ぶこと。
  void flushLabelEvents() {
    if (!root.labelEventPending) return;
    root.labelEventPending = false;
    final label = root.currentFrameLabel;
    if (label != null) root.onLabelEnter?.call(label);
  }

  /// アクション保留中のクリップを親→子の順で消化する。
  /// アクション実行中のgotoで新たに保留が生じたら追加パスで処理。
  void _runPendingActions() {
    for (var pass = 0; pass < _maxActionPasses; pass++) {
      final pending = <MovieClip>[];
      _collectPending(root, pending);
      if (pending.isEmpty) return;
      for (final clip in pending) {
        clip.actionsPending = false;
        for (final actions in clip.currentFrameActions) {
          interpreter.run(actions, clip);
        }
      }
    }
  }

  static void _collectPending(MovieClip clip, List<MovieClip> out) {
    if (clip.actionsPending) out.add(clip);
    for (final obj in clip.displayList.values) {
      final child = obj.clip;
      if (child != null) _collectPending(child, out);
    }
  }

  /// キー入力のディスパッチ。処理したらtrue。
  /// まずボタンのCondKeyPressへ配送し、未処理の方向キーは
  /// フォーカスナビゲーション（Flash Lite実機の4方向キー移動）、
  /// 未処理の決定キーはフォーカス中ボタンの押下として扱う。
  bool dispatchKey(int swfKeyCode) {
    if (_dispatchKeyTo(root, swfKeyCode)) return true;
    return switch (swfKeyCode) {
      _NavKey.left => _moveFocus(-1, 0),
      _NavKey.right => _moveFocus(1, 0),
      _NavKey.up => _moveFocus(0, -1),
      _NavKey.down => _moveFocus(0, 1),
      _NavKey.enter => _activateFocusedButton(),
      _ => false,
    };
  }

  bool _dispatchKeyTo(MovieClip clip, int swfKeyCode) {
    var handled = false;
    for (final obj in List.of(clip.displayList.values)) {
      if (inputDisabledCharacterIds.contains(obj.character.id)) continue;
      final character = obj.character;
      if (character is ButtonCharacter) {
        for (final cond in character.condActions) {
          if (cond.keyPress == swfKeyCode) {
            interpreter.run(cond.actions, clip);
            handled = true;
          }
        }
      }
      final child = obj.clip;
      if (child != null) {
        handled = _dispatchKeyTo(child, swfKeyCode) || handled;
      }
    }
    if (handled) {
      _runPendingActions();
      flushLabelEvents();
    }
    return handled;
  }

  /// ステージ座標（px）へのタップをボタンへディスパッチ。処理したらtrue。
  /// ヒット判定はボタンのHitTestステートが参照するキャラクタの
  /// 外接矩形（変換済みAABB）による近似。
  bool dispatchTap(double xPx, double yPx) {
    final handled =
        _dispatchTapTo(root, SwfMatrix.identity, xPx * 20, yPx * 20);
    if (handled) {
      _runPendingActions();
      flushLabelEvents();
    }
    return handled;
  }

  bool _dispatchTapTo(
      MovieClip clip, SwfMatrix parentMatrix, double xt, double yt) {
    // 上に描画されるもの（深度大）を優先
    for (final obj in clip.displayList.values.toList().reversed) {
      if (inputDisabledCharacterIds.contains(obj.character.id)) continue;
      final matrix = parentMatrix.multiply(obj.matrix);
      final character = obj.character;
      if (character is ButtonCharacter) {
        if (_hitButton(character, matrix, xt, yt)) {
          var fired = false;
          for (final cond in character.condActions) {
            if (cond.keyPress == 0 &&
                (cond.overUpToOverDown ||
                    cond.overDownToOverUp ||
                    cond.idleToOverUp)) {
              interpreter.run(cond.actions, clip);
              fired = true;
            }
          }
          if (fired) return true;
        }
      }
      final child = obj.clip;
      if (child != null && _dispatchTapTo(child, matrix, xt, yt)) {
        return true;
      }
    }
    return false;
  }

  bool _hitButton(
      ButtonCharacter button, SwfMatrix matrix, double xt, double yt) {
    for (final record in button.records) {
      if (!record.stateHitTest) continue;
      final aabb = _recordAabb(record, matrix);
      if (aabb != null && aabb.contains(xt, yt)) return true;
    }
    return false;
  }

  // --- キーフォーカスナビゲーション（Flash Lite実機セマンティクス） ---
  //
  // 方向キーはステージ内のボタン間でフォーカスを移動させ、フォーカスイン
  // したボタンのrollover(IdleToOverUp)アクションを発火する。端まで来たら
  // 反対側へラップする。決定キーはフォーカス中ボタンの押下として扱う。
  // （rolloverボタンを縦に並べたカルーセル型メニューが典型的な利用例）
  //
  // 既知の非互換: フォーカスアウト時のrollout(OverUpToIdle)は発火しない
  // （パーサがOverUpToIdleフラグを保持していないため）。rolloverで立てた
  // 状態をrolloutで戻すSWFでは状態が残る。

  PlacedObject? _focusedButton;
  MovieClip? _focusedOwner;

  /// フォーカス時点のキャラクタ。同一depthの差し替えではPlacedObjectが
  /// 再利用されるため、identityだけでは生存確認にならない。
  Character? _focusedCharacter;

  bool _isFocused(_FocusTarget t) =>
      identical(t.placed, _focusedButton) &&
      identical(t.placed.character, _focusedCharacter);

  /// 方向(dx,dy)へフォーカスを移動。ボタンが1つでもあればtrue。
  bool _moveFocus(int dx, int dy) {
    final targets = <_FocusTarget>[];
    _collectFocusable(root, SwfMatrix.identity, targets);
    if (targets.isEmpty) return false;

    _FocusTarget? current;
    for (final t in targets) {
      if (_isFocused(t)) {
        current = t;
        break;
      }
    }

    _FocusTarget next;
    if (current == null) {
      // フォーカス無し: 読み順（上→下、左→右）で先頭のボタンへ
      next = targets.reduce(
          (a, b) => a.cy < b.cy || (a.cy == b.cy && a.cx <= b.cx) ? a : b);
    } else {
      final cur = current;
      double forward(_FocusTarget t) =>
          dx != 0 ? (t.cx - cur.cx) * dx : (t.cy - cur.cy) * dy;
      double sideways(_FocusTarget t) =>
          dx != 0 ? (t.cy - cur.cy).abs() : (t.cx - cur.cx).abs();
      final others =
          targets.where((t) => !identical(t.placed, cur.placed)).toList();
      if (others.isEmpty) return true;
      final ahead = others.where((t) => forward(t) > 0).toList();
      if (ahead.isNotEmpty) {
        // 進行方向で最も近いボタン。横ずれ込みの距離（ユークリッド）で
        // 選ぶ（前方僅か・横に大きくずれたボタンを同列の近傍より
        // 優先しないため）。同距離なら横ずれが小さい方。
        double dist2(_FocusTarget t) {
          final f = forward(t);
          final s = sideways(t);
          return f * f + s * s;
        }

        next = ahead.reduce((a, b) {
          final da = dist2(a);
          final db = dist2(b);
          if (da != db) return da < db ? a : b;
          return sideways(a) <= sideways(b) ? a : b;
        });
      } else {
        // ラップ: 同じ列/行（横ずれ最小）を優先しつつ反対端
        // （forward最小=最も後方）のボタンへ
        next = others.reduce((a, b) {
          final sa = sideways(a);
          final sb = sideways(b);
          if (sa != sb) return sa < sb ? a : b;
          return forward(a) <= forward(b) ? a : b;
        });
      }
    }

    if (!identical(next.placed, _focusedButton) ||
        !identical(next.placed.character, _focusedCharacter)) {
      _focusedButton = next.placed;
      _focusedOwner = next.owner;
      _focusedCharacter = next.placed.character;
      _fireButtonConds(next.placed, next.owner,
          (cond) => cond.keyPress == 0 && cond.idleToOverUp);
    }
    return true;
  }

  /// 決定キー: フォーカス中ボタンの押下(press/release)アクションを発火。
  /// 単発イベントAPI（キー押下/解放を区別しない）のため、実機で別イベント
  /// になるpress→releaseを同一ディスパッチ内でこの順に連続実行する
  /// （既知の制約。press側で画面遷移してもrelease側まで実行される）。
  bool _activateFocusedButton() {
    final focused = _focusedButton;
    final owner = _focusedOwner;
    if (focused == null || owner == null) return false;
    final targets = <_FocusTarget>[];
    _collectFocusable(root, SwfMatrix.identity, targets);
    if (!targets.any(_isFocused)) {
      // 画面遷移・差し替え等でボタンが消えていたらフォーカス破棄
      _focusedButton = null;
      _focusedOwner = null;
      _focusedCharacter = null;
      return false;
    }
    final pressed = _fireButtonConds(
        focused, owner, (cond) => cond.keyPress == 0 && cond.overUpToOverDown);
    final released = _fireButtonConds(
        focused, owner, (cond) => cond.keyPress == 0 && cond.overDownToOverUp);
    return pressed || released;
  }

  /// 条件に合うボタンアクションを実行。発火したらポンプしてtrue。
  bool _fireButtonConds(PlacedObject placed, MovieClip owner,
      bool Function(ButtonCondAction) test) {
    final button = placed.character;
    if (button is! ButtonCharacter) return false;
    var fired = false;
    for (final cond in button.condActions) {
      if (test(cond)) {
        interpreter.run(cond.actions, owner);
        fired = true;
      }
    }
    if (fired) {
      _runPendingActions();
      flushLabelEvents();
    }
    return fired;
  }

  /// フォーカス可能なボタン（ステージ内にhit領域の中心があるもの）を収集。
  /// ステージ外へ退避されたボタンは実機同様ナビゲーション対象外。
  void _collectFocusable(
      MovieClip clip, SwfMatrix parentMatrix, List<_FocusTarget> out) {
    for (final obj in clip.displayList.values) {
      if (!obj.visible) continue;
      if (inputDisabledCharacterIds.contains(obj.character.id)) continue;
      final matrix = parentMatrix.multiply(obj.matrix);
      final character = obj.character;
      if (character is ButtonCharacter) {
        final b = _buttonHitAabb(character, matrix);
        // 一部でもステージ内にあれば対象（AABB交差判定）。
        // 完全にステージ外へ退避されたボタンだけを除外する
        final onStage = b != null &&
            b.maxX >= movie.stageRect.xMin &&
            b.minX <= movie.stageRect.xMax &&
            b.maxY >= movie.stageRect.yMin &&
            b.minY <= movie.stageRect.yMax;
        if (onStage) {
          out.add(_FocusTarget(
              obj, clip, (b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2));
        }
      }
      final child = obj.clip;
      if (child != null) _collectFocusable(child, matrix, out);
    }
  }

  /// ボタンの全HitTestレコードを合成した外接矩形（変換済みAABB、twips）。
  _Aabb? _buttonHitAabb(ButtonCharacter button, SwfMatrix matrix) {
    _Aabb? merged;
    for (final record in button.records) {
      if (!record.stateHitTest) continue;
      final aabb = _recordAabb(record, matrix);
      if (aabb == null) continue;
      merged = merged == null ? aabb : merged.union(aabb);
    }
    return merged;
  }

  /// ボタンレコード参照キャラクタの変換済みAABB（twips）。
  _Aabb? _recordAabb(ButtonRecord record, SwfMatrix matrix) {
    final character = movie.dictionary[record.characterId];
    final bounds = switch (character) {
      final ShapeCharacter s => s.bounds,
      final EditTextCharacter t => t.bounds,
      final StaticTextCharacter t => t.bounds,
      _ => null,
    };
    if (bounds == null) return null;
    final m = matrix.multiply(record.matrix);
    _Aabb? aabb;
    for (final (px, py) in [
      (bounds.xMin.toDouble(), bounds.yMin.toDouble()),
      (bounds.xMax.toDouble(), bounds.yMin.toDouble()),
      (bounds.xMin.toDouble(), bounds.yMax.toDouble()),
      (bounds.xMax.toDouble(), bounds.yMax.toDouble()),
    ]) {
      final (tx, ty) = m.apply(px, py);
      final point = _Aabb(tx, tx, ty, ty);
      aabb = aabb == null ? point : aabb.union(point);
    }
    return aabb;
  }

  /// 現在の表示状態を深度昇順のツリーとして構築。
  List<RenderNode> buildRenderTree() => _buildNodes(root);

  static List<RenderNode> _buildNodes(MovieClip clip) {
    final nodes = <RenderNode>[];
    for (final obj in clip.displayList.values) {
      if (!obj.visible) continue;
      nodes.add(RenderNode(
        character: obj.character,
        matrix: obj.matrix,
        cxform: obj.cxform,
        depth: obj.depth,
        clipDepth: obj.clipDepth,
        clip: obj.clip,
        owner: clip,
        children: obj.clip != null ? _buildNodes(obj.clip!) : const [],
      ));
    }
    return nodes;
  }
}

/// SWF CondKeyPressコード（ナビゲーション関連）。
class _NavKey {
  static const left = 1;
  static const right = 2;
  static const enter = 13;
  static const up = 14;
  static const down = 15;
}

/// フォーカス候補: ボタンの配置と中心座標（twips）。
class _FocusTarget {
  const _FocusTarget(this.placed, this.owner, this.cx, this.cy);

  final PlacedObject placed;
  final MovieClip owner;
  final double cx;
  final double cy;
}

/// 変換済み外接矩形（twips）。
class _Aabb {
  const _Aabb(this.minX, this.maxX, this.minY, this.maxY);

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  _Aabb union(_Aabb other) => _Aabb(
        minX < other.minX ? minX : other.minX,
        maxX > other.maxX ? maxX : other.maxX,
        minY < other.minY ? minY : other.minY,
        maxY > other.maxY ? maxY : other.maxY,
      );

  bool contains(double x, double y) =>
      x >= minX && x <= maxX && y >= minY && y <= maxY;
}
