import 'dart:convert';
import 'package:http/http.dart' as http;

/// 翻译服务 — 使用 uapis.cn 免费翻译 API
///
/// 免费、无需配置，支持 100+ 语言自动检测并翻译为目标语言。
class TranslateService {
  static const _endpoint = 'https://uapis.cn/api/v1/translate/text';

  /// 翻译文本为中文
  ///
  /// 返回翻译结果字符串；失败时返回 null，由调用方决定回退策略。
  static Future<String?> translateToChinese(String text) async {
    if (text.trim().isEmpty) return null;

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'to_lang': 'zh',
              'text': text.length > 3000 ? text.substring(0, 3000) : text,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final translated = data['translate'] as String?;
        if (translated != null && translated.isNotEmpty) {
          return translated;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
