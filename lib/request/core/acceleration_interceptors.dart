import 'package:dio/dio.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/clients/bangumi_client.dart';
import 'package:kazumi/request/core/ech_adapter.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/services/network/rules_mirror.dart';

/// RequestOptions.extra 中的标记：本次请求跳过镜像，直接访问官方接口。
const String kBypassBangumiMirror = 'bypassBangumiMirror';

class BangumiAccelerationInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final uri = options.uri;
    if (ApiEndpoints.bangumiPublicApiHosts.contains(uri.host)) {
      var mode = BangumiAcceleration.current;
      final bypass = options.extra[kBypassBangumiMirror] == true;
      final path = uri.path;
      // 镜像上需要签名的接口：搜索、各类评论。
      final isMirrorSearch =
          (options.method == 'POST' && path == '/v0/search/subjects') ||
              (options.method == 'GET' &&
                  path.endsWith('/comments') &&
                  (path.startsWith('/p1/subjects/') ||
                      path.startsWith('/p1/episodes/') ||
                      path.startsWith('/p1/characters/')));
      // 镜像的搜索接口需要签名；没有签名密钥(自行打包)或显式要求绕过时直连官方。
      if (mode == BangumiAcceleration.mirror &&
          (bypass ||
              (isMirrorSearch && !BangumiClient.hasMirrorCredentials))) {
        mode = BangumiAcceleration.direct;
      }
      switch (mode) {
        case BangumiAcceleration.direct:
          break;
        case BangumiAcceleration.ech:
          options.path = uri.replace(scheme: 'https').toString();
          options.queryParameters = {};
          options.requireEch();
        case BangumiAcceleration.mirror:
          options.path =
              ApiEndpoints.bangumiMirrorDomain +
              uri.path +
              (uri.hasQuery ? '?${uri.query}' : '');
          options.queryParameters = {};
      }
    }
    handler.next(options);
  }
}

class RulesMirrorInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final url = options.uri.toString();
    if (url.startsWith(ApiEndpoints.pluginShop)) {
      switch (RulesMirror.current) {
        case RulesMirror.direct:
          break;
        case RulesMirror.ghProxy:
          options.path = ApiEndpoints.ghProxyMirror + url;
          options.requireEch();
        case RulesMirror.ghfast:
          options.path = ApiEndpoints.ghfastMirror + url;
        case RulesMirror.gitcode:
          options.path =
              ApiEndpoints.gitcodeMirror +
              url.substring(ApiEndpoints.pluginShop.length);
      }
    }
    handler.next(options);
  }
}
