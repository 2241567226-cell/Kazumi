import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 自绘标题栏使用的窗口控制按钮：最小化(-)、最大化/还原(□)、关闭(X)。
///
/// 仅在桌面端且使用自绘窗口按钮时展示（调用方负责判断）。
class WindowControlButtons extends StatefulWidget {
  const WindowControlButtons({super.key});

  @override
  State<WindowControlButtons> createState() => _WindowControlButtonsState();
}

class _WindowControlButtonsState extends State<WindowControlButtons>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncState() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted && maximized != _maximized) {
        setState(() => _maximized = maximized);
      }
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
        return;
      }
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '最小化',
          onPressed: () => windowManager.minimize(),
          icon: const _MinimizeGlyph(),
        ),
        IconButton(
          tooltip: _maximized ? '还原' : '最大化',
          onPressed: _toggleMaximize,
          icon: Icon(_maximized
              ? Icons.filter_none_rounded
              : Icons.crop_square_rounded),
          iconSize: _maximized ? 18 : 24,
        ),
        IconButton(
          tooltip: '关闭',
          onPressed: () => windowManager.close(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

/// 自绘的“最小化”横线。
///
/// Material 的 `minimize_rounded` 图标横线贴在图标框底部，和 □ / × 并排时
/// 视觉上偏下。这里用一条垂直居中的横线代替，颜色跟随 IconButton。
class _MinimizeGlyph extends StatelessWidget {
  const _MinimizeGlyph();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: Container(
          width: 14,
          height: 2,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}
