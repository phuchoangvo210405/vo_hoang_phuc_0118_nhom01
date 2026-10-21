import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/config_url.dart';
import 'models/api_models.dart';
import 'screens/admin_dashboard.dart';
import 'screens/auth_screen.dart';
import 'screens/student_dashboard.dart';
import 'screens/teacher_dashboard.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';

class _DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Fallback to Config_URL.defaultServerUrl (http://157.10.201.16)
  }
  HttpOverrides.global = _DevHttpOverrides();
  runApp(const DiemDanhSvApp());
}

class DiemDanhSvApp extends StatefulWidget {
  const DiemDanhSvApp({super.key});

  @override
  State<DiemDanhSvApp> createState() => _DiemDanhSvAppState();
}

class _DiemDanhSvAppState extends State<DiemDanhSvApp> {
  late final ApiClient _api = ApiClient(baseUrl: Config_URL.baseUrl);
  AuthSession? _session;

  @override
  void initState() {
    super.initState();
    _restorePersistedState();
  }

  /// Theo tài liệu LTDD Tuần 7:
  /// Kiểm tra `jwt_token` trong SharedPreferences + giải mã role bằng JwtDecoder
  /// để tự động đăng nhập đúng trang phân quyền (Admin / Giảng viên / Sinh viên).
  Future<void> _restorePersistedState() async {
    final savedUrl = await AuthService.loadSavedBaseUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _api.setBaseUrl(savedUrl);
    }
    final restored = await AuthService.restoreSession();
    if (!mounted || restored == null) return;
    final validated = await AuthService.validateOrRefreshSession(
      restored,
      _api,
    );
    if (!mounted) return;
    setState(() {
      _session = validated;
      _api.setToken(validated?.token);
    });
  }

  void _handleAuthenticated(AuthSession session) {
    AuthService.saveSession(session);
    setState(() {
      _session = session;
      _api.setToken(session.token);
    });
  }

  void _handleLogout() {
    AuthService.clearActiveSession();
    setState(() {
      _session = null;
      _api.setToken(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF4F46E5);

    return MaterialApp(
      title: 'Điểm Danh SV - Nhóm 01',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF312E81),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primaryColor, width: 1.8),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: _buildHomeByRole(),
    );
  }

  /// Câu 3: Phân quyền người dùng sau khi xác thực OTP thành công
  Widget _buildHomeByRole() {
    final s = _session;
    if (s == null) {
      return AuthScreen(api: _api, onAuthenticated: _handleAuthenticated);
    }
    if (s.isAdmin) {
      return AdminDashboard(
        api: _api,
        session: s,
        onLogout: _handleLogout,
      );
    }
    if (s.isTeacher) {
      return TeacherDashboard(
        api: _api,
        session: s,
        onLogout: _handleLogout,
      );
    }
    return StudentDashboard(
      api: _api,
      session: s,
      onLogout: _handleLogout,
    );
  }
}
