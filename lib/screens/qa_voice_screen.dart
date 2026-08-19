import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../providers/providers.dart';
import '../services/qa_service.dart';
import 'qa_screen.dart';

/// 語音提問（白板新想法）：
/// 按住麥克風說出問題 → 轉成文字 → 先列出「現有解答」（**純關鍵字比對**
/// 既有已公開 Q&A，無 AI）→ 不滿意就一鍵送到後台問答區等教會（管理者）回答。
class QaVoiceScreen extends ConsumerStatefulWidget {
  const QaVoiceScreen({super.key});

  @override
  ConsumerState<QaVoiceScreen> createState() => _QaVoiceScreenState();
}

class _QaVoiceScreenState extends ConsumerState<QaVoiceScreen> {
  final SpeechToText _speech = SpeechToText();
  final TextEditingController _text = TextEditingController();
  bool _available = false;
  bool _listening = false;
  String _category = kQaCategories.last; // 預設「其他」
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _available = await _speech.initialize(
        onStatus: (s) {
          if (mounted && (s == 'done' || s == 'notListening')) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    } catch (_) {
      _available = false;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _speech.stop();
    _text.dispose();
    super.dispose();
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions:
          SpeechListenOptions(partialResults: true, localeId: 'zh_TW'),
      onResult: (r) {
        if (!mounted) return;
        setState(() => _text.text = r.recognizedWords);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = _text.text.trim();
    // 只比對「已發布」的解答（approved≠published）；沒有已發布資料就不回答，
    // 絕不以未發布內容或任何 AI／網路來源代替。
    final published =
        ref.watch(publishedQuestionsProvider('')).value ?? const [];
    // 純關鍵字比對現有解答（無 AI）：問題/回答/標籤 含任一字詞就列出
    final matches = query.isEmpty
        ? const <Question>[]
        : published.where((q) {
            final hay =
                '${q.title} ${q.body} ${q.answer?.content ?? ''} ${(q.answer?.tags ?? []).join(' ')}';
            return query
                .split(RegExp(r'[\s，。？!?、]+'))
                .where((w) => w.length >= 2)
                .any(hay.contains);
          }).take(5).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('語音提問')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _available ? _toggleListen : null,
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor:
                        _listening ? scheme.error : scheme.primary,
                    child: Icon(_listening ? Icons.stop : Icons.mic,
                        size: 40, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  !_available
                      ? '此裝置／瀏覽器不支援語音辨識，請直接打字'
                      : (_listening ? '聆聽中…再按一下結束' : '按一下開始說出你的問題'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            maxLines: 4,
            minLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '你的問題（語音轉出來的文字可以再修改）',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          if (matches.isNotEmpty) ...[
            Text('先看看教會已發布的解答（關鍵字比對，非 AI）',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: scheme.primary)),
            const SizedBox(height: 4),
            for (final q in matches)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: Text(q.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(q.isAnswered ? '已回答' : '待回答'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => QuestionDetailScreen(id: q.id)),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ] else if (query.isNotEmpty) ...[
            Text('目前沒有教會已發布的相符解答。可送出問題，等教會親自回答。',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
          ],
          Text('分類', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final c in kQaCategories)
                ChoiceChip(
                  label: Text(c),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // 「不滿意」按鈕：把問題送到後台問答區（pending，等管理者人工回答）
          FilledButton.icon(
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(_submitting
                ? '送出中…'
                : (matches.isEmpty ? '送出問題，等教會回答' : '不滿意這些解答？送出等教會回答')),
            onPressed: _submitting || query.isEmpty ? null : _submit,
          ),
          const SizedBox(height: 8),
          Text('送出後進入待審佇列，由管理者親自回答（全人工，無 AI）。',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final user = ref.read(authUserProvider).value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('請先到「設定」用 Google 登入，才能提問')));
      return;
    }
    final body = _text.text.trim();
    // 標題取第一句（或前 30 字），全文放內文
    final firstSentence =
        body.split(RegExp(r'[。？！?\n]')).first.trim();
    final title = firstSentence.isEmpty
        ? body.substring(0, body.length.clamp(0, 30))
        : (firstSentence.length > 40
            ? firstSentence.substring(0, 40)
            : firstSentence);
    setState(() => _submitting = true);
    final m = ScaffoldMessenger.of(context);
    try {
      await ref.read(qaServiceProvider).submitQuestion(
            uid: user.uid,
            authorName: user.displayName ?? '',
            title: title,
            body: body,
            category: _category,
          );
      ref.invalidate(myQuestionsProvider);
      m.showSnackBar(const SnackBar(content: Text('已送出，等教會（管理者）回答')));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('送出失敗：$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
