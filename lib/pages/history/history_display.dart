import 'package:kazumi/modules/history/history_module.dart';

/// Display helpers shared by the history page and the collect (追番) page.
extension HistoryDisplay on History {
  /// "看到 22:44" for the last watched episode; empty when there is no progress.
  String get positionLabel {
    final progress = progresses[lastWatchEpisode]?.progress;
    if (progress == null || progress.inSeconds <= 0) return '';
    final seconds = (progress.inSeconds % 60).toString().padLeft(2, '0');
    final minutes = (progress.inMinutes % 60).toString().padLeft(2, '0');
    final position = progress.inHours > 0
        ? '${progress.inHours}:$minutes:$seconds'
        : '${progress.inMinutes}:$seconds';
    return '看到 $position';
  }

  String get episodeLabel =>
      lastWatchEpisodeName.isEmpty ? '第 $lastWatchEpisode 话' : lastWatchEpisodeName;

  /// "在线 · 源名" / "缓存 · 源名".
  String get sourceLabel {
    final kind =
        HistoryEntryKind.normalize(entryKind) == HistoryEntryKind.offline
            ? '缓存'
            : '在线';
    return [kind, if (adapterName.isNotEmpty) adapterName].join(' · ');
  }
}
