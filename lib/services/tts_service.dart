import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 聽聖經：用系統／瀏覽器 TTS 逐節朗讀整章（白板「四、聽聖經」）。
///
/// 逐節朗讀（不是整章一次唸），這樣可以：
/// 1. 隨時停；2. 標出目前唸到哪一節（讀經頁高亮）。
/// 網頁走瀏覽器 SpeechSynthesis、手機走系統 TTS，皆由 flutter_tts 封裝。
class TtsState {
  /// 是否正在朗讀。
  final bool playing;

  /// 目前朗讀到的節號（1-based；null 表示沒在讀）。
  final int? verse;

  const TtsState({this.playing = false, this.verse});
}

class TtsController extends Notifier<TtsState> {
  FlutterTts? _tts;
  List<String> _verses = const [];
  int _index = 0;
  bool _active = false;

  @override
  TtsState build() {
    ref.onDispose(() {
      _active = false;
      _tts?.stop();
    });
    return const TtsState();
  }

  Future<void> _ensure() async {
    if (_tts != null) return;
    final t = FlutterTts();
    await t.setLanguage('zh-TW');
    await t.setSpeechRate(0.5); // 太快聽不清，取適中偏慢
    t.setCompletionHandler(() {
      if (!_active) return;
      _index++;
      _speakCurrent();
    });
    t.setCancelHandler(() {}); // 停止由 stop() 自己收尾
    _tts = t;
  }

  /// 從第 [from] 節（1-based）開始朗讀整章。
  Future<void> playChapter(List<String> verses, {int from = 1}) async {
    await _ensure();
    _verses = verses;
    _index = (from - 1).clamp(0, verses.isEmpty ? 0 : verses.length - 1);
    _active = true;
    _speakCurrent();
  }

  void _speakCurrent() {
    if (!_active || _index >= _verses.length) {
      stop();
      return;
    }
    state = TtsState(playing: true, verse: _index + 1);
    _tts!.speak(_verses[_index]);
  }

  Future<void> stop() async {
    _active = false;
    state = const TtsState();
    await _tts?.stop();
  }

  /// 播放中→停止；停止中→從頭播放。
  Future<void> toggle(List<String> verses) async {
    if (state.playing) {
      await stop();
    } else {
      await playChapter(verses);
    }
  }
}

final ttsProvider =
    NotifierProvider<TtsController, TtsState>(TtsController.new);
