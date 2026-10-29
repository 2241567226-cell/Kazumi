import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/dandan_credentials.dart';

/// 弹弹play开放平台凭证（AppId / AppSecret）设置项。
class DanmakuCredentialsTile extends StatefulWidget {
  const DanmakuCredentialsTile({super.key});

  @override
  State<DanmakuCredentialsTile> createState() => _DanmakuCredentialsTileState();
}

class _DanmakuCredentialsTileState extends State<DanmakuCredentialsTile> {
  late final _changes = GStorage.watchSettings([
    SettingsKeys.dandanAppId,
    SettingsKeys.dandanAppSecret,
  ]);

  String _status() {
    final custom = GStorage.getSetting<String>(SettingsKeys.dandanAppId)
            .trim()
            .isNotEmpty &&
        GStorage.getSetting<String>(SettingsKeys.dandanAppSecret)
            .trim()
            .isNotEmpty;
    if (custom) return '已使用你填写的凭证';
    if (hasDandanCredentials()) return '使用打包时内置的凭证';
    return '未配置，弹幕无法加载。点击填写 AppId 和 AppSecret';
  }

  Future<void> _edit() async {
    final idController = TextEditingController(
        text: GStorage.getSetting<String>(SettingsKeys.dandanAppId));
    final secretController = TextEditingController(
        text: GStorage.getSetting<String>(SettingsKeys.dandanAppSecret));
    bool obscure = true;

    final saved = await KazumiDialog.show<bool>(
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('弹弹play 开放平台凭证'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('在弹弹play开放平台创建应用并审核通过后，'
                    '把应用的 AppId 和 AppSecret 填在这里，保存后无需重新打包即可加载弹幕。'),
                const SizedBox(height: 12),
                TextField(
                  controller: idController,
                  decoration: const InputDecoration(
                    labelText: 'AppId',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: secretController,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'AppSecret',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded),
                      onPressed: () =>
                          setDialogState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('AppSecret 相当于密码，请勿泄露给他人。留空并保存可清除。',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(popWith: false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => KazumiDialog.dismiss(popWith: true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    final id = idController.text.trim();
    final secret = secretController.text.trim();
    idController.dispose();
    secretController.dispose();

    if (saved != true) return;
    await GStorage.putSetting<String>(SettingsKeys.dandanAppId, id);
    await GStorage.putSetting<String>(SettingsKeys.dandanAppSecret, secret);
    KazumiDialog.showToast(message: '已保存，重新进入播放页后生效');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: _changes,
      builder: (context, _) => SettingsTile(
        leading: Icons.key_rounded,
        title: const Text('弹弹play 凭证'),
        description: Text(_status()),
        onPressed: (_) => _edit(),
      ),
    );
  }
}
