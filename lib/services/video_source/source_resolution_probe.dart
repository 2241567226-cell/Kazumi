import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/video_source/webview_video_source_service.dart';
import 'package:media_kit/media_kit.dart';

enum SourceResolutionStatus { queued, probing, done, unknown }

class SourceResolutionState {
  const SourceResolutionState(this.status, [this.label]);

  final SourceResolutionStatus status;

  /// 例如 "1080P"、"4K"、"1920×1080"
  final String? label;

  bool get isBusy =>
      status == SourceResolutionStatus.queued ||
      status == SourceResolutionStatus.probing;
}

/// 探测"播放来源"中各条目的分辨率。
///
/// 1. 先从条目标题里匹配（如 "1080P"、"4K"），不需要网络；
/// 2. 匹配不到时，取该条目第一集 -> 用 WebView 解析出真实视频地址 ->
///    HLS 读取 master playlist 的 RESOLUTION；否则用 media_kit 读取视频宽高。
///
/// 探测为串行执行（共用一个 WebView），结果按 "插件名|条目地址" 缓存。
class SourceResolutionProbe extends ChangeNotifier {
  static final Map<String, SourceResolutionState> _cache = {};

  final Queue<_ProbeJob> _queue = Queue<_ProbeJob>();
  final Set<String> _enqueued = <String>{};
  WebViewVideoSourceService? _service;
  bool _running = false;
  bool _disposed = false;

  static String keyOf(String pluginName, SearchItem item) =>
      '$pluginName|${item.src}';

  SourceResolutionState? stateOf(String pluginName, SearchItem item) =>
      _cache[keyOf(pluginName, item)];

  /// 将条目加入探测队列（重复调用安全）。
  void request(Plugin plugin, SearchItem item) {
    if (_disposed) return;
    final key = keyOf(plugin.name, item);
    final cached = _cache[key];
    if (cached != null && !cached.isBusy) return;
    if (!_enqueued.add(key)) return;

    final fromTitle = parseResolution(item.name);
    if (fromTitle != null) {
      _set(key, SourceResolutionState(SourceResolutionStatus.done, fromTitle));
      return;
    }
    _cache[key] = const SourceResolutionState(SourceResolutionStatus.queued);
    _queue.add(_ProbeJob(key, plugin, item));
    _pump();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final job = _queue.removeFirst();
        _set(job.key, const SourceResolutionState(SourceResolutionStatus.probing));
        String? label;
        try {
          label = await _probe(job.plugin, job.item);
        } catch (e) {
          KazumiLogger().w('SourceResolutionProbe: probe failed', error: e);
        }
        if (_disposed) return;
        _set(
          job.key,
          label == null
              ? const SourceResolutionState(SourceResolutionStatus.unknown)
              : SourceResolutionState(SourceResolutionStatus.done, label),
        );
      }
    } finally {
      _running = false;
    }
  }

  void _set(String key, SourceResolutionState state) {
    _cache[key] = state;
    if (!_disposed) notifyListeners();
  }

  Future<String?> _probe(Plugin plugin, SearchItem item) async {
    final roads = await plugin.queryChapterRoads(item.src);
    String? episode;
    for (final road in roads) {
      if (road.data.isNotEmpty) {
        episode = road.data.first;
        break;
      }
    }
    if (episode == null || _disposed) return null;

    _service ??= WebViewVideoSourceService();
    final source = await _service!.resolve(
      plugin.buildFullUrl(episode),
      useLegacyParser: plugin.useLegacyParser,
      timeout: const Duration(seconds: 12),
    );
    if (_disposed) return null;

    final headers = plugin.buildHttpHeaders();
    final url = source.url;
    final looksLikeHls = url.toLowerCase().contains('.m3u8');
    if (looksLikeHls) {
      final fromPlaylist = await _resolutionFromHls(url, headers);
      if (fromPlaylist != null) return fromPlaylist;
    }
    return _resolutionFromPlayer(url, headers);
  }

  Future<String?> _resolutionFromHls(
      String url, Map<String, String> headers) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: headers,
        responseType: ResponseType.plain,
      ));
      final response = await dio.get<String>(url);
      final text = response.data ?? '';
      final matches =
          RegExp(r'RESOLUTION=(\d+)x(\d+)', caseSensitive: false)
              .allMatches(text);
      int bestW = 0, bestH = 0;
      for (final m in matches) {
        final w = int.parse(m.group(1)!);
        final h = int.parse(m.group(2)!);
        if (h > bestH) {
          bestW = w;
          bestH = h;
        }
      }
      if (bestH > 0) return formatResolution(bestW, bestH);
    } catch (e) {
      KazumiLogger().w('SourceResolutionProbe: hls parse failed', error: e);
    }
    return null;
  }

  Future<String?> _resolutionFromPlayer(
      String url, Map<String, String> headers) async {
    Player? player;
    StreamSubscription? widthSub;
    StreamSubscription? heightSub;
    try {
      player = Player();
      int w = 0, h = 0;
      final done = Completer<void>();
      void check() {
        if (w > 0 && h > 0 && !done.isCompleted) done.complete();
      }

      widthSub = player.stream.width.listen((v) {
        w = v ?? 0;
        check();
      });
      heightSub = player.stream.height.listen((v) {
        h = v ?? 0;
        check();
      });
      await player.open(Media(url, httpHeaders: headers), play: false);
      await done.future.timeout(const Duration(seconds: 10));
      return formatResolution(w, h);
    } catch (_) {
      return null;
    } finally {
      await widthSub?.cancel();
      await heightSub?.cancel();
      try {
        await player?.dispose();
      } catch (_) {}
    }
  }

  /// 从文本中匹配分辨率标记。
  static String? parseResolution(String text) {
    final lower = text.toLowerCase();
    final dims = RegExp(r'(\d{3,4})\s*[x×*]\s*(\d{3,4})').firstMatch(lower);
    if (dims != null) {
      final w = int.parse(dims.group(1)!);
      final h = int.parse(dims.group(2)!);
      if (w >= 320 && h >= 240) return formatResolution(w, h);
    }
    if (RegExp(r'(^|[^a-z0-9])(4k|2160\s*p?)([^a-z0-9]|$)').hasMatch(lower)) {
      return '4K';
    }
    if (RegExp(r'(^|[^a-z0-9])(2k|1440\s*p)([^a-z0-9]|$)').hasMatch(lower)) {
      return '2K';
    }
    final p = RegExp(r'(^|[^0-9])(1080|720|576|540|480|360)\s*p').firstMatch(lower);
    if (p != null) return '${p.group(2)}P';
    if (RegExp(r'(^|[^a-z0-9])(fhd|蓝光|超清)([^a-z0-9]|$)').hasMatch(lower)) {
      return '1080P';
    }
    return null;
  }

  /// 把宽高格式化为常见清晰度标签，并附带实际宽高。
  static String formatResolution(int width, int height) {
    final base = width >= 3200 || height >= 2000
        ? '4K'
        : height >= 1400
            ? '2K'
            : height >= 1000 || width >= 1800
                ? '1080P'
                : height >= 680 || width >= 1200
                    ? '720P'
                    : height >= 500
                        ? '576P'
                        : height >= 400
                            ? '480P'
                            : '${height}P';
    return '$base · ${width}×$height';
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    _service?.cancel();
    final service = _service;
    _service = null;
    if (service != null) {
      unawaited(service.dispose());
    }
    super.dispose();
  }
}

class _ProbeJob {
  _ProbeJob(this.key, this.plugin, this.item);

  final String key;
  final Plugin plugin;
  final SearchItem item;
}
