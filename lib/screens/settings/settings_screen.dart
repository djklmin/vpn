import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/ai_service.dart';
import '../../services/contact_sync.dart';
import '../../services/app_sync.dart';
import '../../services/webdav_service.dart';
import '../../utils/storage.dart';
import '../../utils/theme.dart';
import '../login_screen.dart';
import '../update/update_screen.dart';

/// 应用当前版本（运行时从 package_info_plus 动态读取，与 pubspec.yaml 自动同步）
// 实例字段在 _SettingsScreenState 里维护，这里仅作默认值占位
class SettingsScreen extends StatefulWidget {
  final CloudMailApi api;

  const SettingsScreen({super.key, required this.api});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showAvatar = true;
  bool _autoLoadImages = true;
  bool _swipeActionsEnabled = true;

  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  List<String> _models = [];
  String? _selectedModel;
  bool _loadingModels = false;
  // 应用当前版本（运行时从 package_info_plus 动态读取）
  String _appVersion = '4.2.0';

  // WebDAV 配置
  final _davUrlController = TextEditingController();
  final _davUserController = TextEditingController();
  final _davPassController = TextEditingController();
  final _davDirController = TextEditingController(text: '/CloudMail');
  bool _testingDav = false;
  bool _syncing = false;

  // 主题色预设
  static const _presetColors = <Color>[
    Color(0xFF1A73E8), // Google 蓝
    Color(0xFFEA4335), // 红
    Color(0xFF34C759), // 绿
    Color(0xFFFF9500), // 橙
    Color(0xFF5856D6), // 靛
    Color(0xFFAF52DE), // 紫
    Color(0xFFFF2D55), // 粉
    Color(0xFF00C7BE), // 青
    Color(0xFF8E8E93), // 灰
  ];

  // 字体预设（系统字体）
  static const _presetFonts = <String>['系统默认', 'serif', 'monospace'];

  @override
  void initState() {
    super.initState();
    _showAvatar = StorageService.showSenderAvatar;
    _autoLoadImages = StorageService.autoLoadImages;
    _swipeActionsEnabled = StorageService.swipeActionsEnabled;

    _apiKeyController.text = StorageService.openaiApiKey ?? '';
    _baseUrlController.text = StorageService.openaiBaseUrl ?? '';
    _selectedModel = StorageService.openaiModel;
    _loadAppVersion();
    _loadWebDavConfig();
  }

  void _loadWebDavConfig() {
    final cfg = ContactSync.loadConfig();
    if (cfg != null) {
      _davUrlController.text = cfg.url;
      _davUserController.text = cfg.username;
      _davPassController.text = cfg.password;
      _davDirController.text = cfg.remoteDir;
    }
  }

  /// 从 package_info_plus 动态读取版本号，与 pubspec.yaml 自动同步
  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      // version 形如 "4.1.0"，buildNumber 形如 "15"
      final ver = info.version;
      if (ver.isNotEmpty && mounted) {
        setState(() => _appVersion = ver);
      }
    } catch (_) {
      // 读取失败时保留默认值
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _davUrlController.dispose();
    _davUserController.dispose();
    _davPassController.dispose();
    _davDirController.dispose();
    super.dispose();
  }

  // ===== WebDAV 同步 =====

  void _saveWebDavConfig() {
    final cfg = WebDavConfig(
      url: _davUrlController.text.trim(),
      username: _davUserController.text.trim(),
      password: _davPassController.text,
      remoteDir: _davDirController.text.trim().isEmpty
          ? '/CloudMail'
          : _davDirController.text.trim(),
    );
    ContactSync.saveConfig(cfg);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebDAV 配置已保存')),
      );
    }
  }

  Future<void> _testWebDav() async {
    final cfg = WebDavConfig(
      url: _davUrlController.text.trim(),
      username: _davUserController.text.trim(),
      password: _davPassController.text,
      remoteDir: _davDirController.text.trim().isEmpty
          ? '/CloudMail'
          : _davDirController.text.trim(),
    );
    if (!cfg.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写完整的服务器地址、用户名和密码')),
      );
      return;
    }
    setState(() => _testingDav = true);
    final ok = await ContactSync.testConnection(cfg);
    if (mounted) {
      setState(() => _testingDav = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '连接成功' : '连接失败，请检查配置')),
      );
    }
  }

  /// 上传全部配置到云端（应用设置 + 联系人）
  Future<void> _uploadToCloud() async {
    setState(() => _syncing = true);
    final messages = <String>[];

    // 1. 上传应用设置
    final settingsResult = await AppSync.uploadSettings();
    messages.add(settingsResult.message);

    // 2. 上传联系人
    final contactResult = await ContactSync.upload();
    messages.add(contactResult.message);

    if (mounted) {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messages.join('；'))),
      );
    }
  }

  /// 从云端拉取全部配置并应用（应用设置 + 联系人）
  Future<void> _pullFromCloud() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从云端拉取配置？'),
        content: const Text('云端的应用设置和联系人将覆盖本地数据，确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('拉取'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _syncing = true);
    final messages = <String>[];

    // 1. 下载应用设置
    final settingsResult = await AppSync.downloadSettings();
    messages.add(settingsResult.message);

    // 2. 下载联系人
    final contactResult = await ContactSync.download();
    messages.add(contactResult.message);

    if (mounted) {
      setState(() {
        _syncing = false;
        // 刷新本地设置状态
        _showAvatar = StorageService.showSenderAvatar;
        _autoLoadImages = StorageService.autoLoadImages;
        _swipeActionsEnabled = StorageService.swipeActionsEnabled;
        _apiKeyController.text = StorageService.openaiApiKey ?? '';
        _baseUrlController.text = StorageService.openaiBaseUrl ?? '';
        _selectedModel = StorageService.openaiModel;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messages.join('；'))),
      );
    }
  }

  // ===== 个性化 =====

  Future<void> _pickBackgroundImage() async {
    final picker = ImagePicker();
    try {
      final xfile = await picker.pickImage(source: ImageSource.gallery);
      if (xfile == null) return;
      final path = xfile.path;
      if (mounted) {
        context.read<ThemeProvider>().setCustomBackgroundImage(path);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('背景图已设置')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
      }
    }
  }

  Future<void> _fetchModels() async {
    // 先保存当前配置，再用最新配置请求
    StorageService.openaiApiKey = _apiKeyController.text.trim().isEmpty
        ? null
        : _apiKeyController.text.trim();
    StorageService.openaiBaseUrl = _baseUrlController.text.trim().isEmpty
        ? null
        : _baseUrlController.text.trim();

    setState(() => _loadingModels = true);
    try {
      final service = AiService();
      final models = await service.fetchModels();
      setState(() {
        _models = models;
        // 如果当前选中的模型不在列表里，清空选择
        if (_selectedModel != null && !models.contains(_selectedModel)) {
          _selectedModel = null;
        }
      });
      if (models.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('上游没有返回可用模型')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取模型失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  void _showModelPicker() async {
    if (_models.isEmpty) {
      await _fetchModels();
    }
    if (!mounted || _models.isEmpty) return;

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择模型'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _models.length,
            itemBuilder: (c, i) {
              final m = _models[i];
              return ListTile(
                title: Text(m),
                trailing: _selectedModel == m
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, m),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (picked != null) {
      setState(() => _selectedModel = picked);
      StorageService.openaiModel = picked;
    }
  }

  /// 保存 AI 配置（API Key + 地址 + 模型）
  void _saveOpenAIConfig() {
    StorageService.openaiApiKey = _apiKeyController.text.trim().isEmpty
        ? null
        : _apiKeyController.text.trim();
    StorageService.openaiBaseUrl = _baseUrlController.text.trim().isEmpty
        ? null
        : _baseUrlController.text.trim();
    if (_selectedModel != null) {
      StorageService.openaiModel = _selectedModel;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 配置已保存')),
      );
    }
  }

  void _openUpdateScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => UpdateScreen(currentVersion: _appVersion),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('确定要退出当前账号吗？下次得重新登录哦~'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.api.logout();
    } catch (_) {}

    if (mounted) {
      StorageService.clear();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (ctx) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle('外观'),
          _buildCard([
            _buildTile(
              icon: Icons.style_outlined,
              title: '界面风格',
              subtitle: _uiStyleText(themeProvider.uiStyle),
              onTap: () => _showUiStyleDialog(themeProvider),
            ),
            const Divider(height: 1, indent: 56),
            _buildTile(
              icon: Icons.dark_mode_outlined,
              title: '深色模式',
              subtitle: isDark ? '当前是深色模式' : '当前是浅色模式',
              trailing: Switch(
                value: isDark,
                onChanged: (val) {
                  themeProvider.setThemeMode(
                    val ? ThemeMode.dark : ThemeMode.light,
                  );
                },
              ),
            ),
            const Divider(height: 1, indent: 56),
            _buildTile(
              icon: Icons.palette_outlined,
              title: '主题模式',
              subtitle: _themeModeText(themeProvider.themeMode),
              onTap: () => _showThemeDialog(themeProvider),
            ),
            const Divider(height: 1, indent: 56),
            _buildTile(
              icon: Icons.account_circle_outlined,
              title: '显示发件人头像',
              trailing: Switch(
                value: _showAvatar,
                onChanged: (val) {
                  setState(() => _showAvatar = val);
                  StorageService.showSenderAvatar = val;
                },
              ),
            ),
          ]),
          const SizedBox(height: 24),

          _buildSectionTitle('个性化'),
          _buildCard([
            // 主题色选择
            InkWell(
              onTap: () => _showColorPicker(themeProvider),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.palette,
                        color: Theme.of(context).colorScheme.primary, size: 22),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('主题色',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface)),
                          Text(
                              themeProvider.customPrimaryColor == null
                                  ? '默认'
                                  : '自定义',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: themeProvider.customPrimaryColor ??
                            Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant,
                            width: 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, indent: 56),
            // 字体选择
            _buildTile(
              icon: Icons.text_fields_outlined,
              title: '字体',
              subtitle: _fontLabel(themeProvider.customFontFamily),
              onTap: () => _showFontPicker(themeProvider),
            ),
            const Divider(height: 1, indent: 56),
            // 背景图
            _buildTile(
              icon: Icons.wallpaper_outlined,
              title: '背景图',
              subtitle: themeProvider.hasCustomBackground ? '已设置' : '默认',
              onTap: _pickBackgroundImage,
            ),
            if (themeProvider.hasCustomBackground) ...[
              const Divider(height: 1, indent: 56),
              _buildTile(
                icon: Icons.close,
                title: '移除背景图',
                onTap: () {
                  themeProvider.setCustomBackgroundImage(null);
                },
              ),
            ],
          ]),
          const SizedBox(height: 24),

          _buildSectionTitle('邮件'),
          _buildCard([
            _buildTile(
              icon: Icons.swipe_right_alt_outlined,
              title: '邮件滑动操作',
              subtitle: '左滑删除、右滑星标',
              trailing: Switch(
                value: _swipeActionsEnabled,
                onChanged: (val) {
                  setState(() => _swipeActionsEnabled = val);
                  StorageService.swipeActionsEnabled = val;
                },
              ),
            ),
            const Divider(height: 1, indent: 56),
            _buildTile(
              icon: Icons.image_outlined,
              title: '自动加载图片',
              subtitle: '邮件中的图片是否自动显示',
              trailing: Switch(
                value: _autoLoadImages,
                onChanged: (val) {
                  setState(() => _autoLoadImages = val);
                  StorageService.autoLoadImages = val;
                },
              ),
            ),
          ]),
          const SizedBox(height: 24),

          _buildSectionTitle('更新'),
          _buildCard([
            _buildTile(
              icon: Icons.system_update_alt_outlined,
              title: '检查更新',
              subtitle: '当前版本: $_appVersion',
              onTap: _openUpdateScreen,
            ),
          ]),
          const SizedBox(height: 24),

          // ===== AI 助手板块 =====
          // 设计目标：
          //  - 三个字段（API Key / API 地址 / 模型）紧凑相连，无大块留白
          //  - "保存模型"按钮放在最底部，使用主色蓝色填充
          _buildSectionTitle('AI 助手'),
          _buildCard([
            // 三个紧密相连的输入字段，仅用细分割线分隔
            _buildAiField(
              label: 'API Key',
              hint: 'sk-xxxxxxxxxxxxxxxxxx',
              controller: _apiKeyController,
              obscure: true,
              isDark: isDark,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _buildAiField(
              label: 'API 地址',
              hint: 'https://api.openai.com/v1',
              controller: _baseUrlController,
              isDark: isDark,
              trailing: TextButton.icon(
                onPressed: _loadingModels ? null : _fetchModels,
                icon: _loadingModels
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('拉取模型', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            // 模型选择行：点击弹出选择
            InkWell(
              onTap: _showModelPicker,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '模型',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedModel ?? '点击选择模型',
                          style: TextStyle(
                            fontSize: 13,
                            color: _selectedModel == null
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right,
                        size: 20, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            // 底部：保存按钮（主色蓝色，铺满宽度）
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _saveOpenAIConfig,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '保存模型',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 24),

          _buildSectionTitle('账户'),
          _buildCard([
            _buildTile(
              icon: Icons.email_outlined,
              title: '当前登录',
              subtitle: StorageService.email ?? '未知',
            ),
            const Divider(height: 1, indent: 56),
            _buildTile(
              icon: Icons.language_outlined,
              title: '服务器地址',
              subtitle: StorageService.baseUrl ?? '未知',
            ),
          ]),
          const SizedBox(height: 24),

          // ===== WebDAV 云同步 =====
          _buildSectionTitle('云同步'),
          _buildCard([
            _buildAiField(
              label: '服务器地址',
              hint: 'https://dav.example.com/remote.php/dav/files/user',
              controller: _davUrlController,
              isDark: isDark,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _buildAiField(
              label: '用户名',
              hint: '用户名',
              controller: _davUserController,
              isDark: isDark,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _buildAiField(
              label: '密码',
              hint: '应用密码',
              controller: _davPassController,
              obscure: true,
              isDark: isDark,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _buildAiField(
              label: '远程目录',
              hint: '/CloudMail',
              controller: _davDirController,
              isDark: isDark,
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testingDav ? null : _testWebDav,
                      icon: _testingDav
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_protected_setup, size: 18),
                      label: const Text('测试连接'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _syncing ? null : _uploadToCloud,
                      icon: _syncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.cloud_upload, size: 18),
                      label: const Text('上传配置'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _syncing ? null : _pullFromCloud,
                      icon: _syncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.cloud_download, size: 18),
                      label: const Text('拉取配置'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.tonal(
                onPressed: _saveWebDavConfig,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('保存配置'),
              ),
            ),
          ]),
          const SizedBox(height: 24),

          _buildSectionTitle('关于'),
          _buildCard([
            _buildTile(
              icon: Icons.info_outline,
              title: '版本',
              subtitle: _appVersion,
              onTap: _openUpdateScreen,
            ),
            const Divider(height: 1, indent: 56),
            _buildTile(
              icon: Icons.cleaning_services_outlined,
              title: '清空 AI 对话历史',
              subtitle: '删除所有 AI 助手的对话记录',
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清空对话历史？'),
                    content: const Text('确定要删除所有 AI 对话记录吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  AiService.clearAllConversations();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('AI 对话历史已清空')),
                    );
                  }
                }
              },
            ),
            const Divider(height: 1, indent: 56),
            _buildTile(
              icon: Icons.code_outlined,
              title: '项目地址',
              subtitle: 'github.com/cheymin/Cloud-Mail-For-Android',
              onTap: () async {
                const url =
                    'https://github.com/cheymin/Cloud-Mail-For-Android';
                try {
                  await launchUrl(Uri.parse(url),
                      mode: LaunchMode.externalApplication);
                } catch (_) {}
              },
            ),
          ]),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _logout,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('退出登录'),
            ),
          ),
          const SizedBox(height: 32),
          // 作者署名
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.favorite,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cloud Mail',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Made with ❤ by Cheymin',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// AI 板块用：标签 + 输入框（紧凑布局，左右两端各 16 padding）
  Widget _buildAiField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool obscure = false,
    required bool isDark,
    Widget? trailing,
  }) {
    final fillColor =
        isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: obscure,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: fillColor,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).textTheme.bodyMedium?.color,
        ),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 13))
          : null,
      trailing: trailing ??
          (onTap != null ? const Icon(Icons.chevron_right, size: 20) : null),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  String _themeModeText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色模式';
      case ThemeMode.dark:
        return '深色模式';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  String _uiStyleText(UiStyle style) {
    switch (style) {
      case UiStyle.google:
        return 'Google 风（Material You）';
      case UiStyle.apple:
        return 'Apple 风（Mimestream）';
    }
  }

  void _showUiStyleDialog(ThemeProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择界面风格'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              provider.setUiStyle(UiStyle.google);
              Navigator.pop(ctx);
            },
            child: ListTile(
              leading: Icon(
                provider.uiStyle == UiStyle.google
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Google 风'),
              subtitle: const Text('Material You · 密集列表 · pill 按钮'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              provider.setUiStyle(UiStyle.apple);
              Navigator.pop(ctx);
            },
            child: ListTile(
              leading: Icon(
                provider.uiStyle == UiStyle.apple
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Apple 风'),
              subtitle: const Text('Mimestream · 留白 · 圆形头像'),
            ),
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(ThemeProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择主题'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              provider.setThemeMode(ThemeMode.system);
              Navigator.pop(ctx);
            },
            child: const Text('跟随系统'),
          ),
          SimpleDialogOption(
            onPressed: () {
              provider.setThemeMode(ThemeMode.light);
              Navigator.pop(ctx);
            },
            child: const Text('浅色模式'),
          ),
          SimpleDialogOption(
            onPressed: () {
              provider.setThemeMode(ThemeMode.dark);
              Navigator.pop(ctx);
            },
            child: const Text('深色模式'),
          ),
        ],
      ),
    );
  }

  /// 主题色选择弹窗
  void _showColorPicker(ThemeProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择主题色'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            // 恢复默认
            GestureDetector(
              onTap: () {
                provider.setCustomPrimaryColor(null);
                Navigator.pop(ctx);
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(ctx).colorScheme.outline, width: 1.5),
                ),
                child: Icon(Icons.refresh,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
            ),
            ..._presetColors.map((c) {
              final selected =
                  provider.customPrimaryColor?.value == c.value;
              return GestureDetector(
                onTap: () {
                  provider.setCustomPrimaryColor(c);
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? Theme.of(ctx).colorScheme.onSurface
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 字体选择弹窗（含导入自定义字体入口）
  void _showFontPicker(ThemeProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择字体'),
        children: [
          // 内置字体
          ..._presetFonts.map((f) {
            final actual = f == '系统默认' ? null : f;
            // 已导入的自定义字体不在这里显示（避免与内置字体名冲突）
            final selected = provider.customFontPath == null &&
                provider.customFontFamily == actual;
            return SimpleDialogOption(
              onPressed: () {
                provider.setCustomFontFamily(actual);
                Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      f,
                      style: TextStyle(
                        fontFamily: actual,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary),
                ],
              ),
            );
          }),
          // 已导入的自定义字体（如果有）
          if (provider.customFontPath != null &&
              provider.customFontFamily != null) ...[
            const Divider(height: 1),
            SimpleDialogOption(
              onPressed: () {
                provider.setCustomFontFamily(provider.customFontFamily);
                Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.customFontFamily!,
                          style: TextStyle(
                            fontFamily: provider.customFontFamily,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '已导入的自定义字体',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 当前正在使用导入的字体时显示 check
                  //（排除内置字体：null / serif / monospace）
                  if (provider.customFontFamily != null &&
                      !const {'serif', 'monospace'}
                          .contains(provider.customFontFamily))
                    Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary),
                ],
              ),
            ),
          ],
          const Divider(height: 1),
          // 导入自定义字体入口
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _importCustomFont(provider);
            },
            child: Row(
              children: [
                Icon(Icons.file_upload_outlined,
                    size: 20, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '导入自定义字体…',
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(ctx).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 导入自定义字体文件（.ttf / .otf）
  Future<void> _importCustomFont(ThemeProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
        withData: false,
      );
      if (result == null || result.files.single.path == null) return;

      final file = result.files.single;
      final sourcePath = file.path!;
      // 用文件名（去扩展名）作为字体家族名
      final displayName = file.name.contains('.')
          ? file.name.substring(0, file.name.lastIndexOf('.'))
          : file.name;

      await provider.importCustomFont(sourcePath, displayName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('字体「$displayName」已导入并应用')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入字体失败: $e')),
        );
      }
    }
  }

  /// 字体显示文字
  String _fontLabel(String? family) {
    if (family == null) return '系统默认';
    switch (family) {
      case 'serif':
        return '衬线字体';
      case 'monospace':
        return '等宽字体';
      default:
        return family;
    }
  }
}
