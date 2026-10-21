import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../config/config_url.dart';
import '../models/api_models.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  String _baseUrl;
  String? token;

  ApiClient({String? baseUrl, this.token})
    : _baseUrl = baseUrl ?? defaultBaseUrl();

  static const String deployedServerUrl = 'http://157.10.201.16';
  static const String conveyorInternetUrl =
      'https://smallgolddog75.conveyor.cloud';
  static const String conveyorLanUrl = 'https://192.168.0.131:45455';

  static String defaultBaseUrl() {
    return Config_URL.baseUrl;
  }

  static List<String> presetUrls() {
    return const [
      deployedServerUrl,
      conveyorInternetUrl,
      conveyorLanUrl,
      'https://10.0.2.2:7087',
      'http://10.0.2.2:5069',
      'https://localhost:7087',
      'http://localhost:5069',
    ];
  }

  String get baseUrl => _baseUrl;

  void setBaseUrl(String url) {
    var cleaned = url.trim();
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    if (cleaned.isNotEmpty) {
      _baseUrl = cleaned;
    }
  }

  void setToken(String? newToken) {
    token = newToken;
  }

  HttpClient _createHttpClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    return client;
  }

  String? _fallbackBaseUrlFor(String current) {
    if (current == deployedServerUrl) return conveyorInternetUrl;
    if (current == conveyorInternetUrl) return conveyorLanUrl;
    if (current == conveyorLanUrl) return deployedServerUrl;
    if (current == 'https://10.0.2.2:7087') return 'http://10.0.2.2:5069';
    if (current == 'http://10.0.2.2:5069') return deployedServerUrl;
    if (current == 'https://localhost:7087') return 'http://localhost:5069';
    if (current == 'http://localhost:5069') return deployedServerUrl;
    return null;
  }

  Future<dynamic> _requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      return await _requestJsonWithBase(_baseUrl, method, path, body: body);
    } on SocketException catch (_) {
      final alt = _fallbackBaseUrlFor(_baseUrl);
      if (alt != null) {
        try {
          final res = await _requestJsonWithBase(
            alt,
            method,
            path,
            body: body,
          );
          _baseUrl = alt;
          return res;
        } catch (_) {
          // Fall through to throw friendly error below
        }
      }
      throw ApiException(
        0,
        'Không kết nối được tới API ($_baseUrl). Hãy kiểm tra Backend Visual Studio đã chạy chưa hoặc đổi địa chỉ máy chủ.',
      );
    } on TimeoutException catch (_) {
      throw ApiException(
        0,
        'Hết thời gian kết nối tới máy chủ ($_baseUrl). Vui lòng kiểm tra lại mạng hoặc cổng API.',
      );
    } on HandshakeException catch (_) {
      final alt = _fallbackBaseUrlFor(_baseUrl);
      if (alt != null) {
        final res = await _requestJsonWithBase(alt, method, path, body: body);
        _baseUrl = alt;
        return res;
      }
      rethrow;
    }
  }

  Future<dynamic> _requestJsonWithBase(
    String base,
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final client = _createHttpClient();
    try {
      final uri = Uri.parse('$base$path');
      final req = await client.openUrl(method, uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null && token!.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        req.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json; charset=utf-8',
        );
        req.contentLength = bytes.length;
        req.add(bytes);
      }

      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (text.trim().isEmpty) return null;
        try {
          return jsonDecode(text);
        } catch (_) {
          return text;
        }
      }

      throw ApiException(resp.statusCode, _extractErrorMessage(resp.statusCode, text));
    } finally {
      client.close(force: false);
    }
  }

  Future<dynamic> _sendMultipart(
    String path, {
    required Map<String, String> fields,
    String? fileField,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    final client = _createHttpClient();
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final req = await client.postUrl(uri);
      if (token != null && token!.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }

      final boundary =
          '----FlutterFormBoundary${DateTime.now().microsecondsSinceEpoch}';
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );

      final builder = BytesBuilder();
      void writeStr(String s) => builder.add(utf8.encode(s));

      fields.forEach((key, value) {
        writeStr('--$boundary\r\n');
        writeStr('Content-Disposition: form-data; name="$key"\r\n\r\n');
        writeStr('$value\r\n');
      });

      if (fileField != null &&
          fileBytes != null &&
          fileBytes.isNotEmpty &&
          fileName != null) {
        writeStr('--$boundary\r\n');
        writeStr(
          'Content-Disposition: form-data; name="$fileField"; filename="$fileName"\r\n',
        );
        writeStr('Content-Type: image/png\r\n\r\n');
        builder.add(fileBytes);
        writeStr('\r\n');
      }

      writeStr('--$boundary--\r\n');
      final payload = builder.takeBytes();
      req.contentLength = payload.length;
      req.add(payload);

      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (text.trim().isEmpty) return null;
        try {
          return jsonDecode(text);
        } catch (_) {
          return text;
        }
      }

      throw ApiException(resp.statusCode, _extractErrorMessage(resp.statusCode, text));
    } on SocketException catch (_) {
      throw ApiException(
        0,
        'Không kết nối được tới API ($_baseUrl). Vui lòng kiểm tra máy chủ.',
      );
    } finally {
      client.close(force: false);
    }
  }

  Future<Uint8List> getBytes(String path) async {
    final client = _createHttpClient();
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final req = await client.getUrl(uri);
      if (token != null && token!.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final resp = await req.close();
      final builder = BytesBuilder();
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return bytes;
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      throw ApiException(resp.statusCode, _extractErrorMessage(resp.statusCode, text));
    } finally {
      client.close(force: false);
    }
  }

  String _extractErrorMessage(int statusCode, String raw) {
    final trimmed = raw.trim();
    if (statusCode == 503 ||
        statusCode == 502 ||
        trimmed.contains("Can't connect to your local application") ||
        trimmed.contains('<!DOCTYPE html>')) {
      return 'Conveyor ($statusCode): Không kết nối được tới Web API. Hãy đảm bảo bạn đã bấm Chạy (F5 / Start Debugging) project Backend_nhom01 trong Visual Studio!';
    }
    if (trimmed.isNotEmpty) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is String && decoded.trim().isNotEmpty) {
          return decoded.trim();
        }
        if (decoded is Map<String, dynamic>) {
          final msg = decoded['message'] ?? decoded['Message'];
          final dist = decoded['distanceMeters'] ?? decoded['DistanceMeters'];
          if (msg != null) {
            if (dist != null) {
              return '$msg (Khoảng cách hiện tại: ${dist}m)';
            }
            return msg.toString();
          }
          if (decoded['errors'] is Map) {
            final errs = decoded['errors'] as Map;
            final firstList = errs.values.firstWhere(
              (v) => v is List && v.isNotEmpty,
              orElse: () => null,
            );
            if (firstList is List && firstList.isNotEmpty) {
              return firstList.first.toString();
            }
          }
          if (decoded['title'] != null) {
            return decoded['title'].toString();
          }
        }
      } catch (_) {
        // Plain text string from ASP.NET Core BadRequest / Conflict / Unauthorized
        var clean = trimmed;
        if (clean.startsWith('"') && clean.endsWith('"') && clean.length >= 2) {
          clean = clean.substring(1, clean.length - 1);
        }
        return clean;
      }
    }
    switch (statusCode) {
      case 400:
        return 'Dữ liệu gửi lên không hợp lệ (400).';
      case 401:
        return 'Chưa đăng nhập hoặc phiên đăng nhập đã hết hạn (401).';
      case 403:
        return 'Bạn không có quyền thực hiện thao tác này (403).';
      case 404:
        return 'Không tìm thấy dữ liệu yêu cầu (404).';
      case 409:
        return 'Dữ liệu bị trùng hoặc đang có ràng buộc (409).';
      default:
        return 'Lỗi máy chủ (Mã lỗi: $statusCode).';
    }
  }

  // ===========================================================================
  // CÂU 1 & CÂU 2: AUTHENTICATION (ĐĂNG KÝ EMAIL + ĐĂNG NHẬP MẬT KHẨU & OTP)
  // ===========================================================================

  Future<String> register({
    required String username,
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    final res = await _requestJson(
      'POST',
      '/api/auth/register',
      body: {
        'username': username.trim(),
        'email': email.trim(),
        'password': password,
        'fullName': fullName.trim(),
        'role': role,
      },
    );
    if (res is Map) {
      return (res['message'] ?? 'Đã gửi mã OTP xác nhận tới email.').toString();
    }
    return 'Đã gửi mã OTP xác nhận tới email.';
  }

  Future<String> verifyRegister({
    required String username,
    required String code,
  }) async {
    final res = await _requestJson(
      'POST',
      '/api/auth/register/verify',
      body: {'username': username.trim(), 'code': code.trim()},
    );
    if (res is Map) {
      return (res['message'] ?? 'Đăng ký thành công. Hãy đăng nhập.')
          .toString();
    }
    return 'Đăng ký thành công. Hãy đăng nhập.';
  }

  Future<String> loginStep1({
    required String username,
    required String password,
  }) async {
    final res = await _requestJson(
      'POST',
      '/api/auth/login',
      body: {'username': username.trim(), 'password': password},
    );
    if (res is Map) {
      return (res['message'] ?? 'Đã gửi mã OTP đăng nhập tới email.')
          .toString();
    }
    return 'Đã gửi mã OTP đăng nhập tới email.';
  }

  Future<AuthSession> verifyLogin({
    required String username,
    required String code,
  }) async {
    final res = await _requestJson(
      'POST',
      '/api/auth/login/verify',
      body: {'username': username.trim(), 'code': code.trim()},
    );
    final map = (res as Map).cast<String, dynamic>();
    final session = AuthSession.fromLoginResponse(map, username.trim());
    token = session.token;
    return session;
  }

  // ===========================================================================
  // CÂU 4A: QUẢN LÝ NGƯỜI DÙNG CRUD (/api/users - Admin)
  // ===========================================================================

  Future<List<AppUserModel>> getUsers() async {
    final res = await _requestJson('GET', '/api/users') as List;
    return res
        .map((e) => AppUserModel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<AppUserModel> createUser({
    required String username,
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    final res = await _requestJson(
      'POST',
      '/api/users',
      body: {
        'username': username.trim(),
        'email': email.trim(),
        'password': password,
        'fullName': fullName.trim(),
        'role': role,
      },
    );
    return AppUserModel.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<AppUserModel> updateUser(
    int id, {
    required String email,
    required String fullName,
    required String role,
    required bool isActive,
  }) async {
    final res = await _requestJson(
      'PUT',
      '/api/users/$id',
      body: {
        'email': email.trim(),
        'fullName': fullName.trim(),
        'role': role,
        'isActive': isActive,
      },
    );
    return AppUserModel.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<void> deleteUser(int id) async {
    await _requestJson('DELETE', '/api/users/$id');
  }

  // ===========================================================================
  // CÂU 4B: QUẢN LÝ MÔN HỌC CRUD (/api/subjects)
  // ===========================================================================

  Future<List<SubjectModel>> getSubjects() async {
    final res = await _requestJson('GET', '/api/subjects') as List;
    return res
        .map((e) => SubjectModel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<SubjectModel> createSubject({
    required String code,
    required String name,
  }) async {
    final res = await _requestJson(
      'POST',
      '/api/subjects',
      body: {'code': code.trim(), 'name': name.trim()},
    );
    return SubjectModel.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<SubjectModel> updateSubject(
    int id, {
    required String code,
    required String name,
  }) async {
    final res = await _requestJson(
      'PUT',
      '/api/subjects/$id',
      body: {'code': code.trim(), 'name': name.trim()},
    );
    return SubjectModel.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<void> deleteSubject(int id) async {
    await _requestJson('DELETE', '/api/subjects/$id');
  }

  // ===========================================================================
  // CÂU 4C: QUẢN LÝ LỚP HỌC, SINH VIÊN TRONG LỚP & BÁO CÁO VẮNG (/api/classes)
  // ===========================================================================

  Future<List<ClassRoomModel>> getClasses() async {
    final res = await _requestJson('GET', '/api/classes') as List;
    return res
        .map((e) => ClassRoomModel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<ClassRoomModel> getClassDetail(int id) async {
    final res = await _requestJson('GET', '/api/classes/$id');
    return ClassRoomModel.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<void> createClass({
    required String name,
    required int subjectId,
    required int teacherId,
  }) async {
    await _requestJson(
      'POST',
      '/api/classes',
      body: {
        'name': name.trim(),
        'subjectId': subjectId,
        'teacherId': teacherId,
      },
    );
  }

  Future<void> updateClass(
    int id, {
    required String name,
    required int subjectId,
    required int teacherId,
  }) async {
    await _requestJson(
      'PUT',
      '/api/classes/$id',
      body: {
        'name': name.trim(),
        'subjectId': subjectId,
        'teacherId': teacherId,
      },
    );
  }

  Future<void> deleteClass(int id) async {
    await _requestJson('DELETE', '/api/classes/$id');
  }

  Future<List<EnrolledStudentModel>> getClassStudents(int classId) async {
    final res =
        await _requestJson('GET', '/api/classes/$classId/students') as List;
    return res
        .map(
          (e) => EnrolledStudentModel.fromJson(
            (e as Map).cast<String, dynamic>(),
          ),
        )
        .toList();
  }

  Future<void> enrollStudent(int classId, int studentId) async {
    await _requestJson(
      'POST',
      '/api/classes/$classId/students',
      body: {'studentId': studentId},
    );
  }

  Future<void> unenrollStudent(int classId, int studentId) async {
    await _requestJson('DELETE', '/api/classes/$classId/students/$studentId');
  }

  Future<List<AbsenceRowModel>> getAbsenceReport(int classId) async {
    final res =
        await _requestJson('GET', '/api/classes/$classId/absence-report')
            as List;
    return res
        .map(
          (e) => AbsenceRowModel.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<int> sendAbsenceWarnings(int classId) async {
    final res = await _requestJson(
      'POST',
      '/api/classes/$classId/send-warnings',
    );
    if (res is Map) {
      return (res['sent'] ?? res['Sent'] ?? 0) as int;
    }
    return 0;
  }

  // ===========================================================================
  // CÂU 4D: QUẢN LÝ BUỔI HỌC & ĐIỂM DANH (/api/sessions)
  // ===========================================================================

  Future<List<ClassSessionModel>> getClassSessions(int classId) async {
    final res =
        await _requestJson('GET', '/api/classes/$classId/sessions') as List;
    return res
        .map(
          (e) => ClassSessionModel.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<void> createSession(
    int classId, {
    required String title,
    required DateTime startsAt,
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    await _requestJson(
      'POST',
      '/api/classes/$classId/sessions',
      body: {
        'title': title.trim(),
        'startsAt': startsAt.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
      },
    );
  }

  Future<void> updateSession(
    int sessionId, {
    required String title,
    required DateTime startsAt,
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    await _requestJson(
      'PUT',
      '/api/sessions/$sessionId',
      body: {
        'title': title.trim(),
        'startsAt': startsAt.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
      },
    );
  }

  Future<void> deleteSession(int sessionId) async {
    await _requestJson('DELETE', '/api/sessions/$sessionId');
  }

  Future<void> closeSession(int sessionId) async {
    await _requestJson('POST', '/api/sessions/$sessionId/close');
  }

  Future<String> checkInSession(
    int sessionId, {
    required String qrToken,
    required double latitude,
    required double longitude,
    Uint8List? photoBytes,
    String? photoFileName,
  }) async {
    final res = await _sendMultipart(
      '/api/sessions/$sessionId/check-in',
      fields: {
        'QrToken': qrToken.trim(),
        'Latitude': latitude.toString(),
        'Longitude': longitude.toString(),
      },
      fileField: photoBytes != null ? 'Photo' : null,
      fileBytes: photoBytes,
      fileName: photoFileName ?? 'checkin.png',
    );
    if (res is Map) {
      final msg = (res['message'] ?? 'Điểm danh thành công.').toString();
      final dist = res['distanceMeters'] ?? res['DistanceMeters'];
      return dist != null ? '$msg (Khoảng cách: ${dist}m)' : msg;
    }
    return 'Điểm danh thành công.';
  }

  Future<List<AttendanceModel>> getSessionAttendances(int sessionId) async {
    final res =
        await _requestJson('GET', '/api/sessions/$sessionId/attendances')
            as List;
    return res
        .map(
          (e) => AttendanceModel.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<Uint8List> getAttendancePhoto(int attendanceId) {
    return getBytes('/api/attendances/$attendanceId/photo');
  }

  // ===========================================================================
  // CÂU 4E: ĐƠN XIN NGHỈ HỌC (/api/leave-requests)
  // ===========================================================================

  Future<String> submitLeaveRequest({
    required int sessionId,
    required String reason,
    Uint8List? evidenceBytes,
    String? evidenceFileName,
  }) async {
    final res = await _sendMultipart(
      '/api/leave-requests',
      fields: {'SessionId': sessionId.toString(), 'Reason': reason.trim()},
      fileField: evidenceBytes != null ? 'Evidence' : null,
      fileBytes: evidenceBytes,
      fileName: evidenceFileName ?? 'evidence.png',
    );
    if (res is Map) {
      return (res['message'] ?? 'Đã gửi đơn xin nghỉ.').toString();
    }
    return 'Đã gửi đơn xin nghỉ.';
  }

  Future<List<LeaveRequestModel>> getMyLeaveRequests() async {
    final res = await _requestJson('GET', '/api/leave-requests/mine') as List;
    return res
        .map(
          (e) => LeaveRequestModel.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<List<LeaveRequestModel>> getClassLeaveRequests(int classId) async {
    final res =
        await _requestJson('GET', '/api/classes/$classId/leave-requests')
            as List;
    return res
        .map(
          (e) => LeaveRequestModel.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<void> reviewLeaveRequest(int leaveId, {required bool approve}) async {
    await _requestJson(
      'PUT',
      '/api/leave-requests/$leaveId/review',
      body: {'approve': approve},
    );
  }

  Future<Uint8List> getLeaveEvidence(int leaveId) {
    return getBytes('/api/leave-requests/$leaveId/evidence');
  }
}
