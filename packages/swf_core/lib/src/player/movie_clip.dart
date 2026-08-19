import 'dart:collection';
import 'dart:typed_data';

import '../model/basic_types.dart';
import '../model/character.dart';
import '../model/timeline.dart';
import '../vm/flash_value.dart';

/// 表示リスト上の配置済みオブジェクト。
class PlacedObject {
  PlacedObject({
    required this.depth,
    required this.character,
    required this.matrix,
    required this.cxform,
    this.name,
    this.clipDepth,
    this.ratio,
    this.clip,
  });

  final int depth;
  Character character;
  SwfMatrix matrix;
  SwfCxform cxform;
  String? name;
  int? clipDepth;
  int? ratio;
  bool visible = true;

  /// ActionScriptで行列(_x/_y/_xscale/_yscale/_rotation)を変更済み。
  /// trueの間はタイムラインのMOVEタグ・後方goto再構築が行列を
  /// 上書きしない（Ruffleのtransformed_by_scriptと同等）。
  bool matrixTransformedByScript = false;

  /// ActionScriptでcxform(_alpha)を変更済み。行列とは独立に保護する
  /// （_x変更でタイムラインのフェード等を止めないため）。
  bool cxformTransformedByScript = false;

  /// characterがSpriteCharacterの場合の入れ子タイムライン。
  MovieClip? clip;

  /// このインスタンスのライフタイムが始まったフレームindex（0-based）。
  /// 配置・差し替えで更新され、後方goto再構築の存続判定に使う
  /// （remove/差し替えを挟んだ別ライフタイムへAS変形を引き継がないため）。
  int lifetimeStartFrame = 0;
}

/// タイムラインを持つムービークリップ（ルートまたはスプライトインスタンス）。
class MovieClip {
  MovieClip(this.timeline, this.dictionary,
      {this.name = '',
      this.parent,
      this.placement,
      bool holdFirstFrame = false})
      : _holdFrame = holdFirstFrame {
    if (timeline.frames.isNotEmpty) {
      _applyFrameOps(0);
      actionsPending = true;
    }
  }

  /// Flash仕様: フレーム途中で配置されたクリップは、そのフレームの間
  /// frame1のまま表示され、次のフレームから進行する。
  /// （配置直後の親のenterFrame走査で1コマ進んでしまうのを防ぐ）
  bool _holdFrame;

  final Timeline timeline;
  final Map<int, Character> dictionary;
  final MovieClip? parent;
  String name;

  /// このクリップを表示リストに配置しているオブジェクト（rootはnull）。
  /// _x/_y/_visible等のプロパティ操作の対象。
  PlacedObject? placement;

  /// 1-based カレントフレーム。
  int get currentFrame => _frameIndex + 1;
  int _frameIndex = 0;

  bool isPlaying = true;

  /// カレントフレームのDoActionが未実行であることを示す（Stageが消化）。
  bool actionsPending = false;

  /// ラベル付きフレームへ到達したときの通知（Stageが設定・排出する）。
  /// 再生ヘッドが実際に移動したときのみ発火する（stop中は発火しない、
  /// ループ再入は同一フレーム番号でも新しい到達として扱う）。
  /// 排出はStageがそのフレームのDoAction消化後に行うため、
  /// コールバック時点でスコア等の変数は確定済み。
  void Function(String label)? onLabelEnter;

  /// 再生ヘッド移動によりラベルイベントが未排出であることを示す。
  bool labelEventPending = false;

  /// カレントフレームのラベル（なければnull）。
  String? get currentFrameLabel =>
      timeline.frames.isEmpty ? null : timeline.frames[_frameIndex].label;

  /// Flash4変数スコープ（内部キーは小文字正規化。Flash4は大小文字非区別）。
  final Map<String, FlashValue> _variables = {};

  FlashValue? getVariable(String name) => _variables[name.toLowerCase()];

  void setVariable(String name, FlashValue value) {
    _variables[name.toLowerCase()] = value;
  }

  /// デバッグ・テスト用の変数ビュー（キーは小文字正規化済み）。
  Map<String, FlashValue> get variables => _variables;

  final SplayTreeMap<int, PlacedObject> displayList = SplayTreeMap();

  int get totalFrames => timeline.frameCount;

  MovieClip get root => parent?.root ?? this;

  /// カレントフレームのDoActionバイト列（タグ出現順）。
  List<Uint8List> get currentFrameActions =>
      timeline.frames.isEmpty ? const [] : timeline.frames[_frameIndex].actions;

  /// スラッシュ構文のターゲットパス（"/a/b"）。
  String get targetPath {
    final p = parent;
    if (p == null) return '/';
    final base = p.targetPath;
    return base == '/' ? '/$name' : '$base/$name';
  }

  /// 再生ヘッドを1フレーム進める（末尾ならframe1へループ）。
  /// isPlaying=falseなら何もしない。子クリップは常に進む。
  void enterFrame() {
    if (_holdFrame) {
      _holdFrame = false;
    } else if (isPlaying && timeline.frameCount > 0) {
      if (_frameIndex + 1 >= timeline.frameCount) {
        _rewindTo(0);
      } else {
        _frameIndex++;
        _applyFrameOps(_frameIndex);
      }
      actionsPending = true;
      labelEventPending = true;
    }
    for (final obj in List.of(displayList.values)) {
      obj.clip?.enterFrame();
    }
  }

  void play() => isPlaying = true;
  void stop() => isPlaying = false;

  /// 指定フレーム（1-based）へ移動。後方なら表示リストを巻き戻して再構築。
  /// 移動先フレームのアクションは保留され、Stageのポンプが実行する。
  void gotoFrame(int frame) {
    final target = (frame - 1).clamp(0, timeline.frameCount - 1);
    if (target == _frameIndex) return;
    if (target > _frameIndex) {
      while (_frameIndex < target) {
        _frameIndex++;
        _applyFrameOps(_frameIndex);
      }
    } else {
      _rewindTo(target);
    }
    actionsPending = true;
    labelEventPending = true;
  }

  bool gotoLabel(String label) {
    final index = _labelIndex(label);
    if (index == null) return false;
    gotoFrame(index + 1);
    return true;
  }

  /// ラベル検索（Flash4準拠で大小文字非区別）。
  int? _labelIndex(String label) {
    final direct = timeline.labelToFrame[label];
    if (direct != null) return direct;
    final lower = label.toLowerCase();
    for (final e in timeline.labelToFrame.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return null;
  }

  /// 後方goto/ループ: frame1..targetのopsをシミュレートした目標状態と
  /// 現在の表示リストをリコンサイルする。同depth・同characterで存続する
  /// インスタンスは内部状態（子クリップの再生ヘッド・変数）を保持する。
  /// （Flash実機の挙動: 後方gotoで連続して存在するスプライトはリセットされない）
  void _rewindTo(int targetIndex) {
    final desired = <int, _SimPlacement>{};
    for (var i = 0; i <= targetIndex; i++) {
      for (final op in timeline.frames[i].ops) {
        switch (op) {
          case PlaceOp():
            final existing = desired[op.depth];
            if (op.move && op.characterId == null) {
              existing?.merge(op);
            } else if (op.characterId != null) {
              if (existing != null) {
                // 差し替え: 未指定属性は引き継ぐ（実行時パスと同一規則）
                existing.characterId = op.characterId!;
                existing.lifetimeStart = i;
                existing.merge(op);
              } else {
                desired[op.depth] = _SimPlacement(op, i);
              }
            }
          case RemoveOp():
            desired.remove(op.depth);
        }
      }
    }

    displayList.removeWhere((depth, _) => !desired.containsKey(depth));
    desired.forEach((depth, sim) {
      final existing = displayList[depth];
      if (existing != null &&
          existing.character.id == sim.characterId &&
          existing.lifetimeStartFrame == sim.lifetimeStart) {
        // インスタンス存続: タイムライン指定の属性のみ反映
        // （AS変更済みの行列・cxformはそれぞれ独立に維持する）
        if (!existing.matrixTransformedByScript && sim.matrix != null) {
          existing.matrix = sim.matrix!;
        }
        if (!existing.cxformTransformedByScript && sim.cxform != null) {
          existing.cxform = sim.cxform!;
        }
        if (sim.ratio != null) existing.ratio = sim.ratio;
        return;
      }
      final character = dictionary[sim.characterId];
      if (character == null) return;
      final placed = PlacedObject(
        depth: depth,
        character: character,
        matrix: sim.matrix ?? SwfMatrix.identity,
        cxform: sim.cxform ?? SwfCxform.identity,
        name: sim.name,
        clipDepth: sim.clipDepth,
        ratio: sim.ratio,
      );
      placed.lifetimeStartFrame = sim.lifetimeStart;
      placed.clip = _instantiate(character, sim.name, placed);
      displayList[depth] = placed;
    });
    _frameIndex = targetIndex;
  }

  void _applyFrameOps(int frameIndex) {
    for (final op in timeline.frames[frameIndex].ops) {
      switch (op) {
        case PlaceOp():
          _applyPlace(op);
        case RemoveOp():
          displayList.remove(op.depth);
      }
    }
  }

  void _applyPlace(PlaceOp op) {
    final existing = displayList[op.depth];
    if (op.move && op.characterId == null) {
      // 既存オブジェクトの属性更新（AS変更済みの行列・cxformは
      // それぞれ独立に維持する）
      if (existing == null) return;
      if (!existing.matrixTransformedByScript && op.matrix != null) {
        existing.matrix = op.matrix!;
      }
      if (!existing.cxformTransformedByScript && op.cxform != null) {
        existing.cxform = op.cxform!;
      }
      if (op.ratio != null) existing.ratio = op.ratio;
      if (op.name != null) existing.name = op.name;
      return;
    }
    final characterId = op.characterId;
    if (characterId == null) return;
    final character = dictionary[characterId];
    if (character == null) return;

    if (existing != null) {
      // キャラクタ差し替え（moveの有無に関わらず、未指定属性は既存から引き継ぐ。
      // SWF仕様: 同depthへの再配置で行列等を省略した場合は前の値を維持する）
      // 新インスタンスなのでAS変更履歴は無効、ライフタイムも新規
      existing.matrixTransformedByScript = false;
      existing.cxformTransformedByScript = false;
      existing.lifetimeStartFrame = _frameIndex;
      existing.character = character;
      existing.clip = _instantiate(character, op.name, existing);
      if (op.matrix != null) existing.matrix = op.matrix!;
      if (op.cxform != null) existing.cxform = op.cxform!;
      if (op.ratio != null) existing.ratio = op.ratio;
      if (op.name != null) existing.name = op.name;
      if (op.clipDepth != null) existing.clipDepth = op.clipDepth;
      return;
    }
    // 新規配置
    final placed = PlacedObject(
      depth: op.depth,
      character: character,
      matrix: op.matrix ?? SwfMatrix.identity,
      cxform: op.cxform ?? SwfCxform.identity,
      name: op.name,
      clipDepth: op.clipDepth,
      ratio: op.ratio,
    );
    placed.lifetimeStartFrame = _frameIndex;
    placed.clip = _instantiate(character, op.name, placed);
    displayList[op.depth] = placed;
  }

  MovieClip? _instantiate(
      Character character, String? name, PlacedObject placement) {
    if (character is! SpriteCharacter) return null;
    return MovieClip(character.timeline, dictionary,
        name: name ?? '',
        parent: this,
        placement: placement,
        holdFirstFrame: true);
  }

  /// 名前で子クリップを検索（Flash4準拠で大小文字非区別）。
  MovieClip? childByName(String name) {
    final lower = name.toLowerCase();
    for (final obj in displayList.values) {
      if (obj.clip != null && obj.name?.toLowerCase() == lower) {
        return obj.clip;
      }
    }
    return null;
  }
}

/// _rewindToのシミュレーション用の配置状態。
class _SimPlacement {
  _SimPlacement(PlaceOp op, this.lifetimeStart)
      : characterId = op.characterId!,
        matrix = op.matrix,
        cxform = op.cxform,
        ratio = op.ratio,
        name = op.name,
        clipDepth = op.clipDepth;

  int characterId;

  /// このライフタイムが始まるフレームindex（配置・差し替えで更新）。
  int lifetimeStart;
  SwfMatrix? matrix;
  SwfCxform? cxform;
  int? ratio;
  String? name;
  int? clipDepth;

  void merge(PlaceOp op) {
    if (op.matrix != null) matrix = op.matrix;
    if (op.cxform != null) cxform = op.cxform;
    if (op.ratio != null) ratio = op.ratio;
    if (op.name != null) name = op.name;
    if (op.clipDepth != null) clipDepth = op.clipDepth;
  }
}
