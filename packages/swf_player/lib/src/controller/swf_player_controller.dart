import 'package:flutter/foundation.dart';
import 'package:swf_core/swf_core.dart';

import '../render/bitmap_registry.dart';

/// SWF再生の状態を所有するコントローラ。
///
/// [load]でSWFバイト列をパースしてステージを構築し、フレーム進行・
/// キー/タップ入力・変数読み出し・描画オプションを提供する。
/// フレームのスケジューリング（Ticker）は`SwfPlayerView`側の責務で、
/// 本クラスは1フレーム進める操作（[advanceFrame]）のみを公開する。
class SwfPlayerController extends ChangeNotifier {
  SwfPlayerController({
    SwfHost? host,
    this.movieTransformer,
    @visibleForTesting BitmapRegistry Function()? bitmapRegistryFactory,
  })  : _host = host,
        _bitmapRegistryFactory = bitmapRegistryFactory ?? BitmapRegistry.new;

  final SwfHost? _host;
  final BitmapRegistry Function() _bitmapRegistryFactory;

  /// パース直後のムービーに適用する変換フック。
  ///
  /// ホストアプリ固有の互換パッチ（特定キャラクタの差し替え等）を
  /// 注入するために使う。
  final void Function(SwfMovie movie)? movieTransformer;

  SwfStage? _stage;
  BitmapRegistry? _bitmaps;
  Object? _loadError;
  bool _disposed = false;

  /// 並行load対策の世代番号。最新のload呼び出しだけが状態を採用できる。
  int _loadGeneration = 0;

  /// ロード済みステージ（未ロード・失敗・dispose後はnull）。
  SwfStage? get stage => _stage;

  /// ロード済みビットマップレジストリ（未ロード・dispose後はnull）。
  BitmapRegistry? get bitmaps => _bitmaps;

  /// ロードに成功して再生可能な状態か。
  bool get isLoaded => _stage != null;

  /// 直近の[load]で発生したエラー（成功時はnull）。
  Object? get loadError => _loadError;

  /// 一時停止フラグ。trueの間はキー・タップ配送を止める。
  /// フレーム進行の停止は`SwfPlayerView`がこのフラグを見て行う。
  bool paused = false;

  /// キーコードの再マップ表（物理キー割当が特殊なコンテンツ向け）。
  Map<int, int> keyMap = const {};

  Set<int> _hiddenCharacterIds = const {};

  /// 描画から除外するcharacterId。ステージの入力無効IDにも同期される。
  Set<int> get hiddenCharacterIds => _hiddenCharacterIds;
  set hiddenCharacterIds(Set<int> value) {
    _hiddenCharacterIds = value;
    _stage?.inputDisabledCharacterIds = value;
    _repaint.value++;
  }

  Map<int, ({double x, double y})> _overridePositionsPx = const {};

  /// characterId別の表示位置上書き（px単位、`StagePainter`と同じレコード型）。
  Map<int, ({double x, double y})> get overridePositionsPx =>
      _overridePositionsPx;
  set overridePositionsPx(Map<int, ({double x, double y})> value) {
    _overridePositionsPx = value;
    _repaint.value++;
  }

  void Function(String label)? _onRootLabel;

  /// ルートタイムラインのラベル到達通知。load前に設定してもよい。
  void Function(String label)? get onRootLabel => _onRootLabel;
  set onRootLabel(void Function(String label)? callback) {
    _onRootLabel = callback;
    _stage?.onRootLabel = callback;
  }

  final ValueNotifier<int> _repaint = ValueNotifier(0);

  /// 再描画通知。`StagePainter`の`repaint`にそのまま渡せる。
  ValueListenable<int> get repaint => _repaint;

  /// SWFバイト列（FWS/CWS）をロードしてステージを構築する。
  ///
  /// 失敗時は例外を投げず[loadError]に保持する。ロードが採用された時点で
  /// 前のステージ・ビットマップを破棄する。並行して複数回呼ばれた場合は
  /// 完了順によらず最後の呼び出しだけが採用される（先行分は破棄）。
  Future<void> load(Uint8List swfBytes) async {
    final generation = ++_loadGeneration;
    _loadError = null;
    BitmapRegistry? pendingBitmaps;
    try {
      final movie = SwfParser.parse(swfBytes);
      movieTransformer?.call(movie);
      final bitmaps = pendingBitmaps = _bitmapRegistryFactory();
      await bitmaps.prime(movie);
      if (_disposed || generation != _loadGeneration) return;
      final stage = SwfStage(movie, host: _host)
        ..inputDisabledCharacterIds = _hiddenCharacterIds
        ..onRootLabel = _onRootLabel;
      _releasePlayback();
      _stage = stage;
      _bitmaps = bitmaps;
      pendingBitmaps = null; // 採用済み（finallyで破棄しない）
    } on Object catch (e) {
      if (_disposed || generation != _loadGeneration) return;
      _loadError = e;
    } finally {
      // 非採用（世代落ち・dispose済み・途中失敗）のレジストリを解放する
      pendingBitmaps?.dispose();
    }
    if (!_disposed) notifyListeners();
  }

  /// ステージを1フレーム進める。呼び出し頻度の制御は呼び出し側の責務。
  void advanceFrame() {
    final stage = _stage;
    if (stage == null) return;
    stage.advanceFrame();
    _repaint.value++;
  }

  /// SWF CondKeyPressコードのキー押下を配送する（[keyMap]適用後）。
  /// [paused]中は何もしない。
  void dispatchKey(int swfKeyCode) {
    final stage = _stage;
    if (stage == null || paused) return;
    stage.dispatchKey(keyMap[swfKeyCode] ?? swfKeyCode);
    _repaint.value++;
  }

  /// ステージ座標（px単位、等倍基準）のタップを配送する。
  /// [paused]中は何もしない。
  void dispatchTap(double stageXPx, double stageYPx) {
    final stage = _stage;
    if (stage == null || paused) return;
    stage.dispatchTap(stageXPx, stageYPx);
    _repaint.value++;
  }

  /// ルートタイムラインの変数を読み出す（未ロード・未定義はnull）。
  FlashValue? getVariable(String path) => _stage?.root.getVariable(path);

  void _releasePlayback() {
    _stage?.onRootLabel = null;
    _stage = null;
    _bitmaps?.dispose();
    _bitmaps = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _releasePlayback();
    _repaint.dispose();
    super.dispose();
  }
}
