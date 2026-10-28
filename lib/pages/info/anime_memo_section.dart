import 'package:flutter/material.dart';

import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/memo/anime_memo.dart';
import 'package:kazumi/services/sync/anime_memo_service.dart';

/// 追番记忆: comment-style personal notes for one anime, synced via WebDAV.
class AnimeMemoSection extends StatefulWidget {
  const AnimeMemoSection({super.key, required this.bangumiId});

  final int bangumiId;

  @override
  State<AnimeMemoSection> createState() => _AnimeMemoSectionState();
}

class _AnimeMemoSectionState extends State<AnimeMemoSection> {
  final AnimeMemoService _service = AnimeMemoService.instance;
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pull notes written on other devices; the list refreshes via revision.
    _service.syncIfEnabled();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await _service.add(widget.bangumiId, text);
      _controller.clear();
    } catch (_) {
      KazumiDialog.showToast(message: '保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(AnimeMemo memo) async {
    final controller = TextEditingController(text: memo.text);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑追番记忆'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty || text.trim() == memo.text) return;
    try {
      await _service.edit(memo, text);
    } catch (_) {
      KazumiDialog.showToast(message: '保存失败，请稍后重试');
    }
  }

  Future<void> _delete(AnimeMemo memo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记忆？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.remove(memo);
    } catch (_) {
      KazumiDialog.showToast(message: '删除失败，请稍后重试');
    }
  }

  String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('追番记忆', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 6,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: '写下追这部番的感受、进度或想法…',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: '发布',
              onPressed: _saving ? null : _submit,
              icon: const Icon(Icons.send_rounded),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<int>(
          valueListenable: _service.revision,
          builder: (context, _, __) {
            final memos = _service.memosOf(widget.bangumiId);
            if (memos.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '还没有记忆，写下第一条吧',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              );
            }
            return Column(
              children: [
                for (final memo in memos)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    color: colors.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(memo.text),
                                const SizedBox(height: 6),
                                Text(
                                  memo.edited
                                      ? '${_time(memo.createdAt)} · 已编辑'
                                      : _time(memo.createdAt),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: '更多',
                            onSelected: (value) =>
                                value == 'edit' ? _edit(memo) : _delete(memo),
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('编辑')),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
