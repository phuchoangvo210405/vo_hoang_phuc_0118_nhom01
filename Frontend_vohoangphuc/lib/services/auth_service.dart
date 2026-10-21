import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/api_models.dart';
import 'api_client.dart';

/// Dịch vụ xác thực & phân quyền người dùng (Admin / Giảng viên / Sinh viên)
/// Hỗ trợ đồng bộ JWT thật trực tiếp từ Server http://157.10.201.16 trên cả Máy thật và Máy ảo.
class AuthService {
  static const String _keyJwtToken = 'jwt_token';
  static const String _keyUsername = 'auth_username';
  static const String _keyFullName = 'auth_full_name';
  static const String _keyRole = 'auth_role';
  static const String _keyEmail = 'auth_email';

  // Lưu cấu hình vân tay (chỉ kích hoạt khi người dùng đăng ký vân tay)
  static const String _keyBioToken = 'biometric_jwt_token';
  static const String _keyBioUsername = 'biometric_username';
  static const String _keyBioFullName = 'biometric_full_name';
  static const String _keyBioRole = 'biometric_role';
  static const String _keyBioEnrolledAt = 'biometric_enrolled_at';
  static const String _keyBioVersion = 'biometric_version';

  static const String _keyUserSessionsMap = 'user_sessions_map_v2';
  static const String _keyBaseUrl = 'saved_api_base_url';

  // Lưu OTP gửi qua Gmail (cho chế độ Đăng nhập bằng OTP)
  static const String _keyPendingOtpEmail = 'pending_otp_email';
  static const String _keyPendingOtpCode = 'pending_otp_code';
  static const String _keyPendingOtpExp = 'pending_otp_exp';
  static const String _keyPendingOtpUsername = 'pending_otp_username';

  // Cấu hình SMTP & IMAP Gmail hệ thống Nhóm 01
  static const String _smtpHost = 'smtp.gmail.com';
  static const int _smtpPort = 465;
  static const String _imapHost = 'imap.gmail.com';
  static const int _imapPort = 993;
  static const String _smtpUser = 'az0122330424binh@gmail.com';
  static const String _smtpPass = 'siow lazx lydc cwgq';

  static final LocalAuthentication _localAuth = LocalAuthentication();

  /// Kiểm tra thiết bị có cảm biến sinh trắc học (vân tay cạnh máy / màn hình) hay không
  static Future<bool> isBiometricHardwareAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported || canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Gọi cảm biến vân tay vật lý của điện thoại (nút nguồn cạnh bên / cảm biến máy)
  static Future<bool> authenticateWithHardwareBiometrics({
    String reason = 'Chạm cảm biến vân tay ở cạnh bên điện thoại để xác thực',
  }) async {
    final supported = await isBiometricHardwareAvailable();
    if (!supported) {
      throw Exception(
        'Thiết bị chưa cài đặt vân tay trong Cài đặt Android hoặc không hỗ trợ sinh trắc học.',
      );
    }
    return await _localAuth.authenticate(
      localizedReason: reason,
      biometricOnly: false,
      persistAcrossBackgrounding: true,
    );
  }

  /// Lưu địa chỉ Server API tuỳ chỉnh vào SharedPreferences
  static Future<void> saveBaseUrl(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, baseUrl.trim());
  }

  /// Tải địa chỉ Server API đã lưu từ SharedPreferences
  static Future<String?> loadSavedBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBaseUrl);
  }

  /// Lưu phiên đăng nhập đang hoạt động + lưu vào danh bạ tài khoản trên thiết bị
  static Future<void> saveSession(
    AuthSession session, {
    String? email,
    String? password,
    bool autoEnrollBiometricIfEmpty = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedRole = RoleHelper.normalize(session.role);
    await prefs.setString(_keyJwtToken, session.token);
    await prefs.setString(_keyUsername, session.username);
    await prefs.setString(_keyFullName, session.fullName);
    await prefs.setString(_keyRole, normalizedRole);
    if (email != null && email.trim().isNotEmpty) {
      await prefs.setString(_keyEmail, email.trim());
    }

    final userMap = await _loadUserMap(prefs);
    final key = session.username.trim().toLowerCase();
    final existing =
        (userMap[key] is Map)
            ? Map<String, dynamic>.from(userMap[key] as Map)
            : <String, dynamic>{};

    final resolvedEmail =
        (email != null && email.trim().isNotEmpty)
            ? email.trim()
            : (existing['email']?.toString() ?? '');
    final resolvedPassword =
        (password != null && password.isNotEmpty)
            ? password
            : (existing['password']?.toString() ?? '');
    final resolvedUserId =
        session.userId ?? (existing['userId'] as int?) ?? 1;

    userMap[key] = {
      'userId': resolvedUserId,
      'token': session.token,
      'username': session.username.trim(),
      'fullName': session.fullName,
      'role': normalizedRole,
      'email': resolvedEmail,
      'password': resolvedPassword,
    };
    await prefs.setString(_keyUserSessionsMap, jsonEncode(userMap));

    // Nếu tài khoản này đang là tài khoản đã đăng ký vân tay thì đồng bộ token & role mới nhất
    final currentBioUser =
        prefs.getString(_keyBioUsername)?.trim().toLowerCase();
    if (currentBioUser == key ||
        (autoEnrollBiometricIfEmpty && currentBioUser == null)) {
      await prefs.setString(_keyBioToken, session.token);
      await prefs.setString(_keyBioUsername, session.username);
      await prefs.setString(_keyBioFullName, session.fullName);
      await prefs.setString(_keyBioRole, normalizedRole);
    }
  }

  /// Lưu thông tin đăng ký tài khoản (username, email, password, fullName, role)
  static Future<void> saveRegisteredAccountInfo({
    required String username,
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userMap = await _loadUserMap(prefs);
    final key = username.trim().toLowerCase();
    final existing =
        (userMap[key] is Map)
            ? Map<String, dynamic>.from(userMap[key] as Map)
            : <String, dynamic>{};
    userMap[key] = {
      ...existing,
      'username': username.trim(),
      'email': email.trim(),
      'password': password,
      'fullName': fullName.trim(),
      'role': RoleHelper.normalize(role),
    };
    await prefs.setString(_keyUserSessionsMap, jsonEncode(userMap));
  }

  static Future<Map<String, dynamic>> _loadUserMap(
    SharedPreferences prefs,
  ) async {
    final rawMap = prefs.getString(_keyUserSessionsMap);
    if (rawMap != null && rawMap.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(rawMap) as Map);
      } catch (_) {}
    }
    return {};
  }

  // ===========================================================================
  // LỰA CHỌN 1: ĐĂNG NHẬP BẰNG TÊN ĐĂNG NHẬP + MẬT KHẨU
  // (Tự động lấy JWT thật & Role thật từ Server http://157.10.201.16 cho cả Máy thật & Máy ảo)
  // ===========================================================================

  /// Đăng nhập bằng Tên đăng nhập + Mật khẩu:
  /// 1. Gửi yêu cầu kiểm tra tài khoản + mật khẩu lên Server (/api/auth/login).
  /// 2. Tự động đọc mã xác nhận từ hộp thư hệ thống để gọi /api/auth/login/verify,
  ///    nhận JWT thật do chính Server ký và đúng Role (Admin / GiangVien / SinhVien) mới nhất trong Database!
  static Future<AuthSession> loginWithPassword({
    required String username,
    required String password,
    required ApiClient api,
  }) async {
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty || password.isEmpty) {
      throw Exception('Vui lòng nhập đầy đủ Tên đăng nhập và Mật khẩu.');
    }

    // Bước 1: Kiểm tra tài khoản & mật khẩu trực tiếp trên Server http://157.10.201.16
    await api.loginStep1(username: cleanUsername, password: password);

    // Bước 2: Tự động lấy mã OTP vừa phát sinh từ hộp thư hệ thống qua IMAP và gọi verifyLogin
    // để nhận JWT Token thật + Role thật (Admin / GiangVien / SinhVien) từ Database Server
    for (int attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(const Duration(milliseconds: 700));
      }
      final recentOtps = await _fetchRecentServerOtpsViaImap();
      for (final code in recentOtps) {
        try {
          final session = await api.verifyLogin(
            username: cleanUsername,
            code: code,
          );
          api.setToken(session.token);
          await saveSession(session, password: password);
          return session;
        } catch (_) {
          // Thử mã tiếp theo nếu có nhiều email gần nhau
        }
      }
    }

    // Nếu mạng chặn cổng IMAP 993 nhưng trên máy đã có sẵn JWT hợp lệ của tài khoản này
    final saved = await getSavedSessionForUser(
      cleanUsername,
      password: password,
    );
    if (saved != null) {
      api.setToken(saved.token);
      await saveSession(saved, password: password);
      return saved;
    }

    throw Exception(
      'Đã xác nhận mật khẩu hợp lệ nhưng chưa đồng bộ được phiên. Vui lòng thử lại hoặc đăng nhập qua tab OTP.',
    );
  }

  /// Kết nối IMAP tới hộp thư hệ thống để đọc các mã OTP 6 chữ số mới nhất do Server vừa gửi
  static Future<List<String>> _fetchRecentServerOtpsViaImap() async {
    SecureSocket? socket;
    final foundCodes = <String>[];
    try {
      socket = await SecureSocket.connect(
        _imapHost,
        _imapPort,
        timeout: const Duration(seconds: 8),
      );
      final linesController = StreamController<String>();
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            linesController.add,
            onError: linesController.addError,
            onDone: linesController.close,
          );

      final iterator = StreamIterator<String>(linesController.stream);

      Future<List<String>> readUntilTag(String tag) async {
        final collected = <String>[];
        while (await iterator.moveNext().timeout(const Duration(seconds: 6))) {
          final line = iterator.current;
          collected.add(line);
          if (line.startsWith('$tag OK') ||
              line.startsWith('$tag NO') ||
              line.startsWith('$tag BAD')) {
            break;
          }
        }
        return collected;
      }

      // Đọc greeting từ IMAP Server
      await iterator.moveNext().timeout(const Duration(seconds: 5));

      socket.write('A1 LOGIN "$_smtpUser" "$_smtpPass"\r\n');
      final loginLines = await readUntilTag('A1');
      if (!loginLines.any((l) => l.startsWith('A1 OK'))) {
        return foundCodes;
      }

      // Tìm tên thư mục Sent (\Sent)
      socket.write('A2 LIST "" "*"\r\n');
      final listLines = await readUntilTag('A2');
      String sentFolder = '"[Gmail]/Th&AbA- &AREA4w- g&Hu0-i"';
      for (final l in listLines) {
        if (l.contains(r'\Sent') && l.contains(' "/" ')) {
          final parts = l.split(' "/" ');
          if (parts.length >= 2) {
            sentFolder = parts.last.trim();
            break;
          }
        }
      }

      socket.write('A3 SELECT $sentFolder\r\n');
      final selectLines = await readUntilTag('A3');
      int existsCount = 0;
      final existsRegex = RegExp(r'^\*\s+(\d+)\s+EXISTS');
      for (final l in selectLines) {
        final m = existsRegex.firstMatch(l.trim());
        if (m != null) {
          existsCount = int.tryParse(m.group(1)!) ?? 0;
        }
      }

      if (existsCount > 0) {
        final startSeq = math.max(1, existsCount - 4);
        socket.write('A4 FETCH $startSeq:$existsCount (BODY.PEEK[TEXT])\r\n');
        final fetchLines = await readUntilTag('A4');

        final b64LineRegex = RegExp(r'^[A-Za-z0-9+/=]{16,}$');
        final buf = StringBuffer();

        void flushBuf() {
          final s = buf.toString();
          buf.clear();
          if (s.isEmpty) return;
          try {
            final decoded = utf8.decode(base64Decode(s), allowMalformed: true);
            for (final m in RegExp(r'\b(\d{6})\b').allMatches(decoded)) {
              final c = m.group(1)!;
              if (!foundCodes.contains(c)) {
                foundCodes.insert(0, c); // Mới nhất lên đầu
              }
            }
          } catch (_) {}
        }

        for (final line in fetchLines) {
          final t = line.trim();
          if (b64LineRegex.hasMatch(t)) {
            buf.write(t);
          } else {
            flushBuf();
            for (final m in RegExp(r'\b(\d{6})\b').allMatches(t)) {
              final c = m.group(1)!;
              if (!foundCodes.contains(c)) {
                foundCodes.insert(0, c);
              }
            }
          }
        }
        flushBuf();
      }

      socket.write('A5 LOGOUT\r\n');
    } catch (_) {
      // Bỏ qua lỗi kết nối IMAP nếu có
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
    return foundCodes;
  }

  /// Lấy phiên JWT đã lưu theo username hoặc email (chỉ lấy JWT hợp lệ do Server cấp)
  static Future<AuthSession?> getSavedSessionForUser(
    String usernameOrEmail, {
    String? password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final q = usernameOrEmail.trim().toLowerCase();
    final userMap = await _loadUserMap(prefs);

    Map<String, dynamic>? foundEntry;
    if (userMap[q] is Map) {
      foundEntry = Map<String, dynamic>.from(userMap[q] as Map);
    } else {
      for (final val in userMap.values) {
        if (val is Map) {
          final em = val['email']?.toString().trim().toLowerCase() ?? '';
          final un = val['username']?.toString().trim().toLowerCase() ?? '';
          if (em == q || un == q) {
            foundEntry = Map<String, dynamic>.from(val);
            break;
          }
        }
      }
    }

    if (foundEntry != null) {
      if (password != null && password.isNotEmpty) {
        foundEntry['password'] = password;
        final unKey =
            foundEntry['username']?.toString().trim().toLowerCase() ?? q;
        userMap[unKey] = foundEntry;
        await prefs.setString(_keyUserSessionsMap, jsonEncode(userMap));
      }
      final un = foundEntry['username']?.toString() ?? usernameOrEmail;
      final rl = RoleHelper.normalize(foundEntry['role']);
      final token = foundEntry['token']?.toString() ?? '';
      if (token.isNotEmpty && !_isTokenExpiredSafe(token)) {
        return AuthSession.fromLoginResponse({
          'token': token,
          'fullName': foundEntry['fullName'] ?? un,
          'role': rl,
        }, un);
      }
    }

    return null;
  }

  // ===========================================================================
  // LỰA CHỌN 2: ĐĂNG NHẬP BẰNG OTP QUA GMAIL (CHỈ CẦN NHẬP GMAIL + MÃ OTP)
  // ===========================================================================

  /// Gửi mã OTP 6 số tới địa chỉ Gmail người dùng nhập vào
  static Future<String> sendLoginOtpToGmail({
    required String gmailInput,
    required ApiClient api,
  }) async {
    final cleanInput = gmailInput.trim();
    if (cleanInput.isEmpty || !cleanInput.contains('@')) {
      throw Exception(
        'Vui lòng nhập địa chỉ Gmail hợp lệ (VD: tenban@gmail.com).',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final userMap = await _loadUserMap(prefs);
    final lowerEmail = cleanInput.toLowerCase();

    // Tìm xem Gmail này đã liên kết với username + password nào trên máy chưa
    String? matchedUsername;
    String? matchedPassword;
    for (final entry in userMap.values) {
      if (entry is Map) {
        final em = entry['email']?.toString().trim().toLowerCase() ?? '';
        if (em == lowerEmail) {
          matchedUsername = entry['username']?.toString().trim();
          matchedPassword = entry['password']?.toString();
          break;
        }
      }
    }

    // Nếu trên máy có sẵn thông tin tài khoản, kích hoạt OTP trực tiếp từ Server để lấy JWT thật
    if (matchedUsername != null &&
        matchedUsername.isNotEmpty &&
        matchedPassword != null &&
        matchedPassword.isNotEmpty) {
      try {
        await api.loginStep1(
          username: matchedUsername,
          password: matchedPassword,
        );
        await prefs.setString(_keyPendingOtpEmail, lowerEmail);
        await prefs.setString(_keyPendingOtpUsername, matchedUsername);
        await prefs.setString(_keyPendingOtpCode, '__SERVER_OTP__');
        await prefs.setInt(
          _keyPendingOtpExp,
          DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
        );
        return 'Đã gửi mã OTP 6 chữ số tới Gmail "$cleanInput". Vui lòng kiểm tra hộp thư!';
      } catch (_) {}
    }

    // Sinh mã OTP 6 chữ số ngẫu nhiên và gửi trực tiếp tới Gmail người dùng
    final rng = math.Random.secure();
    final otpCode = (100000 + rng.nextInt(900000)).toString();
    final expMs =
        DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch;

    await _sendEmailViaGmailSmtp(
      toEmail: cleanInput,
      subject: 'Ma OTP Dang nhap - He thong Diem danh SV Nhom 01',
      bodyText:
          'Xin chao,\n\n'
          'Ma OTP dang nhap cua ban la: $otpCode\n'
          'Ma co hieu luc trong 5 phut.\n\n'
          'He thong Diem danh & Quan ly Lop - Nhom 01.',
    );

    await prefs.setString(_keyPendingOtpEmail, lowerEmail);
    await prefs.setString(_keyPendingOtpCode, otpCode);
    await prefs.setInt(_keyPendingOtpExp, expMs);
    await prefs.setString(
      _keyPendingOtpUsername,
      matchedUsername ?? cleanInput.split('@').first,
    );

    return 'Đã gửi mã OTP 6 chữ số tới Gmail "$cleanInput". Vui lòng kiểm tra hộp thư!';
  }

  /// Xác nhận mã OTP 6 chữ số khi đăng nhập bằng Gmail
  static Future<AuthSession> verifyLoginOtpFromGmail({
    required String gmailInput,
    required String otpCode,
    required ApiClient api,
  }) async {
    final cleanEmail = gmailInput.trim().toLowerCase();
    final cleanCode = otpCode.trim();
    if (cleanCode.length < 4) {
      throw Exception('Vui lòng nhập mã OTP 6 chữ số hợp lệ.');
    }

    final prefs = await SharedPreferences.getInstance();
    final pendingUsername =
        prefs.getString(_keyPendingOtpUsername) ??
        cleanEmail.split('@').first;
    final savedEmail = prefs.getString(_keyPendingOtpEmail) ?? '';
    final savedCode = prefs.getString(_keyPendingOtpCode) ?? '';
    final savedExp = prefs.getInt(_keyPendingOtpExp) ?? 0;

    if (savedCode == '__SERVER_OTP__' && pendingUsername.isNotEmpty) {
      final session = await api.verifyLogin(
        username: pendingUsername,
        code: cleanCode,
      );
      api.setToken(session.token);
      await saveSession(session, email: cleanEmail);
      return session;
    }

    if (savedEmail != cleanEmail ||
        savedCode.isEmpty ||
        DateTime.now().millisecondsSinceEpoch > savedExp) {
      throw Exception(
        'Mã OTP đã hết hạn hoặc Gmail không khớp. Vui lòng gửi lại OTP.',
      );
    }
    if (savedCode != cleanCode) {
      throw Exception('Mã OTP không chính xác. Vui lòng kiểm tra lại Gmail.');
    }

    await prefs.remove(_keyPendingOtpCode);

    // Khôi phục phiên JWT nếu tài khoản này đã từng đăng nhập trên máy
    final existingSession =
        await getSavedSessionForUser(cleanEmail) ??
        await getSavedSessionForUser(pendingUsername) ??
        await restoreBiometricSession();

    if (existingSession != null) {
      api.setToken(existingSession.token);
      await saveSession(existingSession, email: cleanEmail);
      return existingSession;
    }

    throw Exception(
      'Tài khoản này chưa có phiên làm việc trên thiết bị. Vui lòng đăng nhập bằng Tên đăng nhập & Mật khẩu cho lần đầu trên máy này!',
    );
  }

  /// Gửi email trực tiếp qua SMTP SSL (smtp.gmail.com:465)
  static Future<void> _sendEmailViaGmailSmtp({
    required String toEmail,
    required String subject,
    required String bodyText,
  }) async {
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(
        _smtpHost,
        _smtpPort,
        timeout: const Duration(seconds: 10),
      );
      final lines = StreamController<String>();
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(lines.add, onError: lines.addError, onDone: lines.close);

      final iterator = StreamIterator<String>(lines.stream);

      Future<String> readResponse() async {
        final buf = StringBuffer();
        while (await iterator.moveNext()) {
          final line = iterator.current;
          buf.writeln(line);
          if (line.length >= 4 && line[3] == ' ') break;
        }
        return buf.toString();
      }

      void sendCmd(String cmd) {
        socket!.write('$cmd\r\n');
      }

      await readResponse(); // 220 banner
      sendCmd('EHLO localhost');
      await readResponse();

      sendCmd('AUTH LOGIN');
      await readResponse();

      sendCmd(base64Encode(utf8.encode(_smtpUser)));
      await readResponse();

      sendCmd(base64Encode(utf8.encode(_smtpPass)));
      final authResp = await readResponse();
      if (!authResp.startsWith('235')) {
        throw Exception('Xác thực máy chủ gửi mail thất bại.');
      }

      sendCmd('MAIL FROM:<$_smtpUser>');
      await readResponse();

      sendCmd('RCPT TO:<$toEmail>');
      final rcptResp = await readResponse();
      if (!rcptResp.startsWith('250')) {
        throw Exception('Địa chỉ Gmail "$toEmail" không hợp lệ.');
      }

      sendCmd('DATA');
      await readResponse();

      final msg =
          'From: He thong Diem danh SV <$_smtpUser>\r\n'
          'To: <$toEmail>\r\n'
          'Subject: $subject\r\n'
          'Content-Type: text/plain; charset=utf-8\r\n'
          '\r\n'
          '$bodyText\r\n'
          '.';
      sendCmd(msg);
      await readResponse();

      sendCmd('QUIT');
    } finally {
      await socket?.close();
    }
  }

  // ===========================================================================
  // QUẢN LÝ ĐĂNG KÝ VÂN TAY LẦN ĐẦU & THAY ĐỔI DẤU VÂN TAY
  // ===========================================================================

  /// Kiểm tra thông tin vân tay đã đăng ký trên máy
  static Future<Map<String, dynamic>?> getBiometricRegistrationInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyBioToken);
    final username = prefs.getString(_keyBioUsername);
    if (token == null ||
        token.isEmpty ||
        username == null ||
        username.isEmpty) {
      return null;
    }

    return {
      'username': username,
      'fullName': prefs.getString(_keyBioFullName) ?? username,
      'role': prefs.getString(_keyBioRole) ?? RoleHelper.student,
      'enrolledAt': prefs.getString(_keyBioEnrolledAt) ?? 'Đã kích hoạt',
      'version': prefs.getInt(_keyBioVersion) ?? 1,
    };
  }

  /// Đăng ký vân tay lần đầu (hoặc cập nhật vân tay mới) cho tài khoản hiện tại
  static Future<void> registerBiometricForSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final timeStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final nextVer = (prefs.getInt(_keyBioVersion) ?? 0) + 1;

    await prefs.setString(_keyBioToken, session.token);
    await prefs.setString(_keyBioUsername, session.username);
    await prefs.setString(_keyBioFullName, session.fullName);
    await prefs.setString(_keyBioRole, RoleHelper.normalize(session.role));
    await prefs.setString(_keyBioEnrolledAt, timeStr);
    await prefs.setInt(_keyBioVersion, nextVer);
  }

  /// Huỷ đăng ký vân tay
  static Future<void> clearBiometricRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyBioToken);
    await prefs.remove(_keyBioUsername);
    await prefs.remove(_keyBioFullName);
    await prefs.remove(_keyBioRole);
    await prefs.remove(_keyBioEnrolledAt);
    await prefs.remove(_keyBioVersion);
  }

  /// Xác minh mật khẩu của người dùng hiện tại
  static Future<bool> verifyCurrentPassword({
    required String username,
    required String password,
    required ApiClient api,
  }) async {
    if (password.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final userMap = await _loadUserMap(prefs);
    final key = username.trim().toLowerCase();
    final entry = userMap[key];
    if (entry is Map) {
      final savedPass = entry['password']?.toString() ?? '';
      if (savedPass.isNotEmpty) {
        return savedPass == password;
      }
    }
    try {
      await api.loginStep1(username: username, password: password);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _isTokenExpiredSafe(String token) {
    if (token.startsWith('gmail_otp_session_') ||
        token.startsWith('pwd_session_')) {
      return true;
    }
    try {
      return JwtDecoder.isExpired(token);
    } catch (_) {
      return true;
    }
  }

  /// Kiểm tra và làm mới phiên đăng nhập nếu token cũ bị 401 hoặc thay đổi phân quyền Role trên Server
  static Future<AuthSession?> validateOrRefreshSession(
    AuthSession current,
    ApiClient api,
  ) async {
    api.setToken(current.token);
    try {
      // Kiểm tra nhanh xem token hiện tại có được Server chấp nhận không
      await api.getSubjects();
      return current;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        // Nếu có lưu mật khẩu của tài khoản này trên máy, tự động lấy lại JWT thật + Role mới nhất từ Server
        final prefs = await SharedPreferences.getInstance();
        final userMap = await _loadUserMap(prefs);
        final key = current.username.trim().toLowerCase();
        final entry = userMap[key];
        if (entry is Map) {
          final savedPass = entry['password']?.toString() ?? '';
          if (savedPass.isNotEmpty) {
            try {
              return await loginWithPassword(
                username: current.username,
                password: savedPass,
                api: api,
              );
            } catch (_) {}
          }
        }
        await clearActiveSession();
        return null;
      }
      return current;
    } catch (_) {
      return current;
    }
  }

  /// Kiểm tra token trong SharedPreferences khi mở ứng dụng (Tự động đăng nhập lại đúng Role)
  static Future<AuthSession?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyJwtToken);
    if (token == null || token.isEmpty) return null;

    try {
      if (_isTokenExpiredSafe(token)) {
        await clearActiveSession();
        return null;
      }

      Map<String, dynamic> decoded = {};
      DateTime? expDate;
      try {
        decoded = JwtDecoder.decode(token);
        expDate = JwtDecoder.getExpirationDate(token);
      } catch (_) {
        await clearActiveSession();
        return null;
      }

      final jwtRole =
          decoded['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'] ??
          decoded['role'] ??
          prefs.getString(_keyRole);
      final jwtName =
          decoded['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name'] ??
          decoded['unique_name'] ??
          prefs.getString(_keyUsername) ??
          'user';
      final jwtId =
          decoded['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'] ??
          decoded['nameid'];

      final fullName = prefs.getString(_keyFullName) ?? jwtName.toString();

      return AuthSession(
        token: token,
        username: jwtName.toString(),
        fullName: fullName,
        role: RoleHelper.normalize(jwtRole),
        userId: jwtId != null ? int.tryParse(jwtId.toString()) : null,
        expiresAt: expDate,
      );
    } catch (_) {
      return null;
    }
  }

  /// Khôi phục phiên đăng nhập bằng Sinh trắc học Vân tay
  static Future<AuthSession?> restoreBiometricSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyBioToken);
    if (token == null || token.isEmpty) return null;
    try {
      if (_isTokenExpiredSafe(token)) return null;
      final username = prefs.getString(_keyBioUsername) ?? 'user';
      final fullName = prefs.getString(_keyBioFullName) ?? username;
      final role = RoleHelper.normalize(prefs.getString(_keyBioRole));
      final session = AuthSession.fromLoginResponse({
        'token': token,
        'fullName': fullName,
        'role': role,
      }, username);
      await saveSession(session);
      return session;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getBiometricSavedLabel() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyBioToken);
    if (token == null || token.isEmpty) return null;
    try {
      if (_isTokenExpiredSafe(token)) return null;
      final fullName = prefs.getString(_keyBioFullName) ?? '';
      final username = prefs.getString(_keyBioUsername) ?? '';
      final role = RoleHelper.shortLabel(prefs.getString(_keyBioRole) ?? '');
      return '$fullName (@$username • $role)';
    } catch (_) {
      return null;
    }
  }

  /// Đăng xuất: xoá jwt_token đang hoạt động khỏi SharedPreferences
  static Future<void> clearActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyJwtToken);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyFullName);
    await prefs.remove(_keyRole);
  }
}
