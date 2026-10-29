import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:kazumi/services/logging/logger.dart';

/// 通过 HTTP Range 只读取视频文件头部，解析出分辨率（宽, 高）。
///
/// 支持 MP4 / MOV（moov → tkhd）和 MKV / WebM（Tracks → Video）。
/// 通常只需要 1～2 个很小的请求，比启动播放器快得多。
/// 无法识别或服务器不支持 Range 时返回 null，由调用方走兜底方案。
class VideoHeaderProbe {
  VideoHeaderProbe(this.headers);

  final Map<String, String> headers;

  late final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    followRedirects: true,
    maxRedirects: 5,
    headers: headers,
    responseType: ResponseType.stream,
    validateStatus: (s) => s != null && s >= 200 && s < 300,
  ));

  Future<(int, int)?> probe(String url) async {
    try {
      final head = await _read(url, 0, 256 * 1024);
      if (head == null || head.length < 12) return null;
      // MKV / WebM：EBML 头 1A 45 DF A3
      if (head[0] == 0x1A &&
          head[1] == 0x45 &&
          head[2] == 0xDF &&
          head[3] == 0xA3) {
        return _parseMkv(head);
      }
      // MP4 / MOV：偏移 4 处为 'ftyp'（或 moov/free/mdat 等）
      return await _parseMp4(url, head);
    } catch (e) {
      KazumiLogger().w('VideoHeaderProbe failed', error: e);
      return null;
    }
  }

  /// 读取 [start, start+length) 的字节。服务器不支持 Range 且 start>0 时返回 null。
  Future<Uint8List?> _read(String url, int start, int length) async {
    final cancel = CancelToken();
    try {
      final resp = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancel,
        options: Options(headers: {
          ...headers,
          'range': 'bytes=$start-${start + length - 1}',
        }),
      );
      // 200 表示服务器忽略了 Range，从头开始发送
      if (resp.statusCode == 200 && start > 0) {
        cancel.cancel();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp.data!.stream) {
        builder.add(chunk);
        if (builder.length >= length) break;
      }
      cancel.cancel(); // 够用了，立刻断开，避免继续下载
      final all = builder.takeBytes();
      return all.length > length ? Uint8List.sublistView(all, 0, length) : all;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return null;
      rethrow;
    }
  }

  // ---------------------------------------------------------------- MP4

  Future<(int, int)?> _parseMp4(String url, Uint8List head) async {
    var offset = 0;
    Uint8List buf = head;
    var bufStart = 0;
    for (var i = 0; i < 64; i++) {
      // 确保缓冲里有当前 box 的头部（16 字节）
      if (offset < bufStart || offset + 16 > bufStart + buf.length) {
        final next = await _read(url, offset, 64 * 1024);
        if (next == null || next.length < 8) return null;
        buf = next;
        bufStart = offset;
      }
      final bd = ByteData.sublistView(buf);
      final rel = offset - bufStart;
      var size = bd.getUint32(rel);
      final type = String.fromCharCodes(buf.sublist(rel + 4, rel + 8));
      var headerLen = 8;
      if (size == 1) {
        if (rel + 16 > buf.length) return null;
        size = bd.getUint64(rel + 8);
        headerLen = 16;
      } else if (size == 0) {
        return null; // 延伸到文件末尾，后面不会再有 moov
      }
      if (size < headerLen) return null;

      if (type == 'moov') {
        const maxMoov = 12 * 1024 * 1024;
        if (size > maxMoov) return null;
        final end = bufStart + buf.length;
        Uint8List moov;
        if (offset + size <= end) {
          moov = Uint8List.sublistView(buf, rel, rel + size);
        } else {
          final data = await _read(url, offset, size);
          if (data == null || data.length < size) return null;
          moov = data;
        }
        return _findTkhd(moov, headerLen);
      }
      offset += size; // 跳过 ftyp / free / mdat 等
    }
    return null;
  }

  (int, int)? _findTkhd(Uint8List moov, int moovHeaderLen) {
    final bd = ByteData.sublistView(moov);
    var p = moovHeaderLen;
    while (p + 8 <= moov.length) {
      final size = bd.getUint32(p);
      final type = String.fromCharCodes(moov.sublist(p + 4, p + 8));
      if (size < 8 || p + size > moov.length) break;
      if (type == 'trak') {
        final r = _tkhdInTrak(moov, p + 8, p + size);
        if (r != null) return r;
      }
      p += size;
    }
    return null;
  }

  (int, int)? _tkhdInTrak(Uint8List data, int start, int end) {
    final bd = ByteData.sublistView(data);
    var p = start;
    while (p + 8 <= end) {
      final size = bd.getUint32(p);
      final type = String.fromCharCodes(data.sublist(p + 4, p + 8));
      if (size < 8 || p + size > end) break;
      if (type == 'tkhd') {
        // tkhd 末尾 8 字节为 16.16 定点数的 宽、高；音频轨为 0
        final w = bd.getUint32(p + size - 8) >> 16;
        final h = bd.getUint32(p + size - 4) >> 16;
        if (w > 0 && h > 0) return (w, h);
        return null;
      }
      p += size;
    }
    return null;
  }

  // ---------------------------------------------------------------- MKV

  static const _idSegment = 0x18538067;
  static const _idTracks = 0x1654AE6B;
  static const _idTrackEntry = 0xAE;
  static const _idVideo = 0xE0;
  static const _idPixelW = 0xB0;
  static const _idPixelH = 0xBA;
  static const _idCluster = 0x1F43B675;

  (int, int)? _parseMkv(Uint8List d) {
    int pos = 0;
    // 跳过 EBML 头
    final headId = _readId(d, pos);
    if (headId == null) return null;
    pos += headId.$2;
    final headSize = _readSize(d, pos);
    if (headSize == null) return null;
    pos += headSize.$2 + headSize.$1;
    return _scanMkv(d, pos, d.length, 0);
  }

  (int, int)? _scanMkv(Uint8List d, int start, int end, int depth) {
    var pos = start;
    int? w, h;
    while (pos < end) {
      final id = _readId(d, pos);
      if (id == null) return null;
      final sz = _readSize(d, pos + id.$2);
      if (sz == null) return null;
      final bodyStart = pos + id.$2 + sz.$2;
      final unknown = sz.$1 < 0;
      final bodyEnd = unknown ? end : bodyStart + sz.$1;
      switch (id.$1) {
        case _idCluster:
          return null; // 已到数据区，Tracks 不会再出现
        case _idSegment:
        case _idTracks:
        case _idTrackEntry:
          final r = _scanMkv(d, bodyStart, bodyEnd > end ? end : bodyEnd, depth + 1);
          if (r != null) return r;
        case _idVideo:
          final r = _scanMkv(d, bodyStart, bodyEnd > end ? end : bodyEnd, depth + 1);
          if (r != null) return r;
        case _idPixelW:
          w = _readUInt(d, bodyStart, sz.$1);
        case _idPixelH:
          h = _readUInt(d, bodyStart, sz.$1);
      }
      if (w != null && h != null && w > 0 && h > 0) return (w, h);
      if (unknown) return null;
      if (bodyEnd > end) return null;
      pos = bodyEnd;
    }
    return null;
  }

  /// 返回 (id, 字节数)
  (int, int)? _readId(Uint8List d, int pos) {
    if (pos >= d.length) return null;
    final first = d[pos];
    var len = 1;
    var mask = 0x80;
    while (len <= 4 && (first & mask) == 0) {
      len++;
      mask >>= 1;
    }
    if (len > 4 || pos + len > d.length) return null;
    var v = 0;
    for (var i = 0; i < len; i++) {
      v = (v << 8) | d[pos + i];
    }
    return (v, len);
  }

  /// 返回 (值, 字节数)；值 -1 表示未知长度
  (int, int)? _readSize(Uint8List d, int pos) {
    if (pos >= d.length) return null;
    final first = d[pos];
    var len = 1;
    var mask = 0x80;
    while (len <= 8 && (first & mask) == 0) {
      len++;
      mask >>= 1;
    }
    if (len > 8 || pos + len > d.length) return null;
    var v = first & (mask - 1);
    var allOnes = v == (mask - 1);
    for (var i = 1; i < len; i++) {
      v = (v << 8) | d[pos + i];
      if (d[pos + i] != 0xFF) allOnes = false;
    }
    return (allOnes ? -1 : v, len);
  }

  int? _readUInt(Uint8List d, int pos, int len) {
    if (len <= 0 || len > 8 || pos + len > d.length) return null;
    var v = 0;
    for (var i = 0; i < len; i++) {
      v = (v << 8) | d[pos + i];
    }
    return v;
  }
}
