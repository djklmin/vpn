import 'dart:convert';
import '../services/webdav_service.dart';
import '../utils/storage.dart';

/// 应用全量数据同步服务
/// 同步用户所有可修改的设置：界面风格、主题、OpenAI、WebDAV、个性化等
class AppSync {
  static const _filename = 'app_settings.json';

  /// 读取已保存的 WebDAV 配置
  static WebDavConfig? loadConfig() {
    final raw = StorageService.webdavConfig;
    if (raw == null || raw.isEmpty) return null;
    try {
      return WebDavConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 保存 WebDAV 配置
  static void saveConfig(WebDavConfig config) {
    StorageService.webdavConfig = jsonEncode(config.toJson());
  }

  /// 测试连接
  static Future<bool> testConnection(WebDavConfig config) async {
    final svc = WebDavService(config);
    return svc.testConnection();
  }

  /// 导出所有用户设置为 JSON
  static Map<String, dynamic> exportSettings() {
    return {
      'version': 2,
      'exportTime': DateTime.now().toIso8601String(),
      'uiStyle': StorageService.uiStyle,
      'themeMode': StorageService.themeMode,
      'showSenderAvatar': StorageService.showSenderAvatar,
      'autoLoadImages': StorageService.autoLoadImages,
      'swipeActionsEnabled': StorageService.swipeActionsEnabled,
      'openaiApiKey': StorageService.openaiApiKey ?? '',
      'openaiBaseUrl': StorageService.openaiBaseUrl ?? '',
      'openaiModel': StorageService.openaiModel ?? '',
      'customPrimaryColor': StorageService.customPrimaryColor,
      'customFontFamily': StorageService.customFontFamily,
      'customFontPath': StorageService.customFontPath,
      'customBackgroundImage': StorageService.customBackgroundImage,
      'rememberLogin': StorageService.rememberLogin,
      'chatHistory': StorageService.chatHistory ?? '',
    };
  }

  /// 从 JSON 导入用户设置
  static int importSettings(Map<String, dynamic> data) {
    int changed = 0;

    if (data['uiStyle'] != null) {
      StorageService.uiStyle = data['uiStyle'] as String;
      changed++;
    }
    if (data['themeMode'] != null) {
      StorageService.themeMode = data['themeMode'] as String;
      changed++;
    }
    if (data['showSenderAvatar'] != null) {
      StorageService.showSenderAvatar = data['showSenderAvatar'] as bool;
      changed++;
    }
    if (data['autoLoadImages'] != null) {
      StorageService.autoLoadImages = data['autoLoadImages'] as bool;
      changed++;
    }
    if (data['swipeActionsEnabled'] != null) {
      StorageService.swipeActionsEnabled = data['swipeActionsEnabled'] as bool;
      changed++;
    }
    if (data['openaiApiKey'] != null) {
      StorageService.openaiApiKey = data['openaiApiKey'] as String;
      changed++;
    }
    if (data['openaiBaseUrl'] != null) {
      StorageService.openaiBaseUrl = data['openaiBaseUrl'] as String;
      changed++;
    }
    if (data['openaiModel'] != null) {
      StorageService.openaiModel = data['openaiModel'] as String;
      changed++;
    }
    if (data['customPrimaryColor'] != null) {
      StorageService.customPrimaryColor = data['customPrimaryColor'] as int?;
      changed++;
    }
    if (data['customFontFamily'] != null) {
      StorageService.customFontFamily = data['customFontFamily'] as String?;
      changed++;
    }
    if (data['customFontPath'] != null) {
      StorageService.customFontPath = data['customFontPath'] as String?;
      changed++;
    }
    if (data['customBackgroundImage'] != null) {
      StorageService.customBackgroundImage = data['customBackgroundImage'] as String?;
      changed++;
    }
    if (data['rememberLogin'] != null) {
      StorageService.rememberLogin = data['rememberLogin'] as bool;
      changed++;
    }
    if (data['chatHistory'] != null &&
        (data['chatHistory'] as String).isNotEmpty) {
      StorageService.chatHistory = data['chatHistory'] as String;
      changed++;
    }

    return changed;
  }

  /// 上传所有用户设置到云端
  static Future<SyncResult> uploadSettings() async {
    final config = loadConfig();
    if (config == null || !config.isConfigured) {
      return const SyncResult(success: false, message: '请先配置 WebDAV');
    }
    final svc = WebDavService(config);
    final json = jsonEncode(exportSettings());
    final ok = await svc.uploadString(_filename, json);
    return SyncResult(
      success: ok,
      message: ok ? '应用设置已上传' : '上传失败，请检查配置',
      changed: ok ? 1 : 0,
    );
  }

  /// 从云端下载并应用用户设置
  static Future<SyncResult> downloadSettings() async {
    final config = loadConfig();
    if (config == null || !config.isConfigured) {
      return const SyncResult(success: false, message: '请先配置 WebDAV');
    }
    final svc = WebDavService(config);
    final raw = await svc.downloadString(_filename);
    if (raw == null) {
      return const SyncResult(success: false, message: '云端暂无设置数据');
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final changed = importSettings(data);
      return SyncResult(
        success: true,
        message: changed > 0
            ? '已恢复 $changed 项设置'
            : '云端设置与本地一致',
        changed: changed,
      );
    } catch (_) {
      return const SyncResult(success: false, message: '设置数据格式异常');
    }
  }
}
