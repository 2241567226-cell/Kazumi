import 'dart:convert';

/// A free-form note ("追番记忆") attached to one anime, comment style.
class AnimeMemo {
  AnimeMemo({
    required this.id,
    required this.bangumiId,
    required this.text,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.deleted = false,
  });

  final String id;
  final int bangumiId;
  final String text;
  final int createdAtMs;
  final int updatedAtMs;

  /// Tombstone so deletions propagate through WebDAV.
  final bool deleted;

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  bool get edited => updatedAtMs > createdAtMs;

  AnimeMemo copyWith({String? text, int? updatedAtMs, bool? deleted}) =>
      AnimeMemo(
        id: id,
        bangumiId: bangumiId,
        text: text ?? this.text,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bangumiId': bangumiId,
        'text': text,
        'createdAt': createdAtMs,
        'updatedAt': updatedAtMs,
        if (deleted) 'deleted': true,
      };

  static AnimeMemo? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final bangumiId = json['bangumiId'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    if (id is! String ||
        id.isEmpty ||
        bangumiId is! int ||
        createdAt is! int ||
        updatedAt is! int) {
      return null;
    }
    return AnimeMemo(
      id: id,
      bangumiId: bangumiId,
      text: json['text'] as String? ?? '',
      createdAtMs: createdAt,
      updatedAtMs: updatedAt,
      deleted: json['deleted'] == true,
    );
  }

  String encode() => jsonEncode(toJson());

  static AnimeMemo? decode(String source) {
    try {
      return tryFromJson(jsonDecode(source));
    } catch (_) {
      return null;
    }
  }

  /// Newest edit wins; ties favour the tombstone.
  static AnimeMemo newer(AnimeMemo a, AnimeMemo b) {
    if (a.updatedAtMs != b.updatedAtMs) {
      return a.updatedAtMs > b.updatedAtMs ? a : b;
    }
    return a.deleted ? a : b;
  }

  /// A sync file is `{"version":1,"memos":[...]}`; malformed entries are skipped.
  static List<AnimeMemo> decodeFile(String source) {
    try {
      final json = jsonDecode(source);
      final list = json is Map ? json['memos'] : null;
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (tryFromJson(item) case final memo?) memo,
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encodeFile(Iterable<AnimeMemo> memos) => jsonEncode({
        'version': 1,
        'memos': [for (final memo in memos) memo.toJson()],
      });
}
