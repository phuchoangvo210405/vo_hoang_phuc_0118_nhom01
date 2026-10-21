import 'package:flutter_dotenv/flutter_dotenv.dart';

// Class quản lý đường dẫn API theo chuẩn bài học Tuần 7 (LTDD Tuan7 V2.docx)
// ignore: camel_case_types
class Config_URL {
  static const String deployedServerUrl = 'http://157.10.201.16';

  static String get baseUrl {
    if (dotenv.isInitialized) {
      final url = dotenv.env['BASE_URL']?.trim();
      if (url != null && url.isNotEmpty) {
        var cleaned = url;
        while (cleaned.endsWith('/')) {
          cleaned = cleaned.substring(0, cleaned.length - 1);
        }
        if (cleaned.endsWith('/api')) {
          cleaned = cleaned.substring(0, cleaned.length - 4);
        }
        return cleaned;
      }
    }
    return deployedServerUrl;
  }
}
