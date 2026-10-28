import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:kazumi/modules/history/history_sync.dart';
import 'package:kazumi/modules/memo/anime_memo.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/webdav.dart';

/// Local store and WebDAV sync for per-anime notes (追番记忆).
class AnimeMemoService {
  AnimeMemoService._();
  static final AnimeMemoService instance = AnimeMemoService._();

  /// Bumped after every local or synced change so views can rebuild.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  Timer? _timer;

  bool get syncEnabled =>
      GStorage.getSetting(SettingsKeys.webDavEnable) &&
      GStorage.getSetting(SettingsKeys.webDavEnableCollect);

  List<AnimeMemo> _all() => [
        for (final raw in GStorage.animeMemos.values)
          if (AnimeMemo.decode(raw) case final memo?) memo,
      ];

  /// Live notes for one anime, newest first.
  List<AnimeMemo> memosOf(int bangumiId) {
    final list = _all()
        .where((memo) => memo.bangumiId == bangumiId && !memo.deleted)
        .toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return list;
  }

  Future<void> _put(AnimeMemo memo) async {
    await GStorage.animeMemos.put(memo.id, memo.encode());
    await GStorage.animeMemos.flush();
    revision.value++;
    _scheduleSync();
  }

  Future<void> add(int bangumiId, String text) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final suffix = (now ^ identityHashCode(text)).toRadixString(36);
    return _put(AnimeMemo(
      id: '${now.toRadixString(36)}-$suffix',
      bangumiId: bangumiId,
      text: text.trim(),
      createdAtMs: now,
      updatedAtMs: now,
    ));
  }

  Future<void> edit(AnimeMemo memo, String text) => _put(memo.copyWith(
        text: text.trim(),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));

  Future<void> remove(AnimeMemo memo) => _put(memo.copyWith(
        text: '',
        deleted: true,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));

  void _scheduleSync() {
    _timer?.cancel();
    if (!syncEnabled) return;
    _timer = Timer(const Duration(milliseconds: 800), () {
      unawaited(syncIfEnabled());
    });
  }

  Future<String> _deviceId() async {
    final existing = GStorage.getSetting(SettingsKeys.historySyncDeviceId);
    if (existing.isNotEmpty) return existing;
    final id = HistorySyncDevice.generateDeviceId();
    await GStorage.putSetting(SettingsKeys.historySyncDeviceId, id);
    return id;
  }

  /// Merge remote files into the local box, return the file to upload.
  Future<String> _merge(List<String> remoteFiles) async {
    final merged = {for (final memo in _all()) memo.id: memo};
    for (final source in remoteFiles) {
      for (final remote in AnimeMemo.decodeFile(source)) {
        final local = merged[remote.id];
        merged[remote.id] =
            local == null ? remote : AnimeMemo.newer(local, remote);
      }
    }
    await GStorage.animeMemos.putAll({
      for (final memo in merged.values) memo.id: memo.encode(),
    });
    await GStorage.animeMemos.flush();
    revision.value++;
    return AnimeMemo.encodeFile(merged.values);
  }

  Future<void> sync() async {
    _timer?.cancel();
    if (!syncEnabled) return;
    await WebDav().syncAnimeMemos(
      deviceId: await _deviceId(),
      merge: _merge,
    );
  }

  Future<void> syncIfEnabled() async {
    try {
      await sync();
    } catch (e, stackTrace) {
      KazumiLogger().w(
        'WebDav: anime memo sync failed; keeping local notes',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
