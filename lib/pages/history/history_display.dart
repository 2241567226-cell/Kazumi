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

  /// "22:44" without a prefix; empty when there is no progress.
  String get positionText {
    final label = positionLabel;
    return label.startsWith('看到 ') ? label.substring(3) : label;
  }

  /// "第12集---22:44" (the time part is omitted when there is no progress).
  String get watchedEpisodeLine {
    final time = positionText;
    return time.isEmpty
        ? '第$lastWatchEpisode集'
        : '第$lastWatchEpisode集---$time';
  }

  /// "在线---源名" / "本地---源名".
  String get watchModeLine {
    final kind =
        HistoryEntryKind.normalize(entryKind) == HistoryEntryKind.offline
            ? '本地'
            : '在线';
    return adapterName.isEmpty ? kind : '$kind---$adapterName';
  }
}

/// "2026年1月番" from an air date string; empty when the date is unknown.
String seasonLabelOf(String airDate) {
  final date = DateTime.tryParse(airDate);
  if (date == null) return '';
  final month = ((date.month - 1) ~/ 3) * 3 + 1;
  return '${date.year}年$month月番';
}
