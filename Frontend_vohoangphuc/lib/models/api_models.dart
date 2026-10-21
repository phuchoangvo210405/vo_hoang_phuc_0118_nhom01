import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class RoleHelper {
  static const String admin = 'Admin';
  static const String teacher = 'GiangVien';
  static const String student = 'SinhVien';

  static String normalize(dynamic raw) {
    if (raw == null) return student;
    final s = raw.toString().trim();
    if (s == '0' || s.toLowerCase() == 'admin') return admin;
    if (s == '1' || s.toLowerCase() == 'giangvien') return teacher;
    return student;
  }

  static String label(String role) {
    switch (normalize(role)) {
      case admin:
        return 'Quản trị viên (Admin)';
      case teacher:
        return 'Giảng viên (Nhân viên)';
      default:
        return 'Sinh viên';
    }
  }

  static String shortLabel(String role) {
    switch (normalize(role)) {
      case admin:
        return 'Admin';
      case teacher:
        return 'Giảng viên';
      default:
        return 'Sinh viên';
    }
  }

  static Color color(String role) {
    switch (normalize(role)) {
      case admin:
        return const Color(0xFF7C3AED);
      case teacher:
        return const Color(0xFF0284C7);
      default:
        return const Color(0xFF059669);
    }
  }

  static IconData icon(String role) {
    switch (normalize(role)) {
      case admin:
        return Icons.admin_panel_settings_rounded;
      case teacher:
        return Icons.co_present_rounded;
      default:
        return Icons.school_rounded;
    }
  }
}

class LeaveStatusHelper {
  static const String pending = 'Pending';
  static const String approved = 'Approved';
  static const String rejected = 'Rejected';

  static String normalize(dynamic raw) {
    if (raw == null) return pending;
    final s = raw.toString().trim();
    if (s == '1' || s.toLowerCase() == 'approved') return approved;
    if (s == '2' || s.toLowerCase() == 'rejected') return rejected;
    return pending;
  }

  static String label(String status) {
    switch (normalize(status)) {
      case approved:
        return 'Đã duyệt';
      case rejected:
        return 'Từ chối';
      default:
        return 'Chờ duyệt';
    }
  }

  static Color color(String status) {
    switch (normalize(status)) {
      case approved:
        return const Color(0xFF059669);
      case rejected:
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFD97706);
    }
  }
}

class AuthSession {
  final String token;
  final String username;
  final String fullName;
  final String role;
  final int? userId;
  final DateTime? expiresAt;

  const AuthSession({
    required this.token,
    required this.username,
    required this.fullName,
    required this.role,
    this.userId,
    this.expiresAt,
  });

  bool get isAdmin => RoleHelper.normalize(role) == RoleHelper.admin;
  bool get isTeacher => RoleHelper.normalize(role) == RoleHelper.teacher;
  bool get isStudent => RoleHelper.normalize(role) == RoleHelper.student;

  bool get isExpired {
    try {
      return JwtDecoder.isExpired(token);
    } catch (_) {
      return false;
    }
  }

  factory AuthSession.fromLoginResponse(
    Map<String, dynamic> json,
    String fallbackUsername,
  ) {
    final token = (json['token'] ?? json['Token'] ?? '').toString();
    Map<String, dynamic> decoded = {};
    DateTime? expDate;
    try {
      if (token.isNotEmpty) {
        decoded = JwtDecoder.decode(token);
        expDate = JwtDecoder.getExpirationDate(token);
      }
    } catch (_) {}

    final jwtRole =
        decoded['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'] ??
        decoded['role'];
    final jwtName =
        decoded['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name'] ??
        decoded['unique_name'] ??
        decoded['name'];
    final jwtId =
        decoded['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'] ??
        decoded['nameid'] ??
        decoded['sub'];

    final role = RoleHelper.normalize(json['role'] ?? json['Role'] ?? jwtRole);
    final username = (jwtName ?? fallbackUsername).toString();
    final fullName =
        (json['fullName'] ?? json['FullName'] ?? username).toString();

    return AuthSession(
      token: token,
      username: username,
      fullName: fullName,
      role: role,
      userId: jwtId != null ? int.tryParse(jwtId.toString()) : null,
      expiresAt: expDate,
    );
  }
}

class AppUserModel {
  final int id;
  final String username;
  final String email;
  final String fullName;
  final String role;
  final bool isActive;

  const AppUserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
  });

  factory AppUserModel.fromJson(Map<String, dynamic> json) {
    return AppUserModel(
      id: (json['id'] ?? json['Id'] ?? 0) as int,
      username: (json['username'] ?? json['Username'] ?? '').toString(),
      email: (json['email'] ?? json['Email'] ?? '').toString(),
      fullName: (json['fullName'] ?? json['FullName'] ?? '').toString(),
      role: RoleHelper.normalize(json['role'] ?? json['Role']),
      isActive: (json['isActive'] ?? json['IsActive'] ?? true) == true,
    );
  }
}

class SubjectModel {
  final int id;
  final String code;
  final String name;

  const SubjectModel({
    required this.id,
    required this.code,
    required this.name,
  });

  factory SubjectModel.fromJson(Map<String, dynamic> json) {
    return SubjectModel(
      id: (json['id'] ?? json['Id'] ?? 0) as int,
      code: (json['code'] ?? json['Code'] ?? '').toString(),
      name: (json['name'] ?? json['Name'] ?? '').toString(),
    );
  }
}

class ClassRoomModel {
  final int id;
  final String name;
  final int subjectId;
  final String subjectName;
  final int teacherId;
  final String teacherName;

  const ClassRoomModel({
    required this.id,
    required this.name,
    required this.subjectId,
    required this.subjectName,
    required this.teacherId,
    required this.teacherName,
  });

  factory ClassRoomModel.fromJson(Map<String, dynamic> json) {
    return ClassRoomModel(
      id: (json['id'] ?? json['Id'] ?? 0) as int,
      name: (json['name'] ?? json['Name'] ?? '').toString(),
      subjectId: (json['subjectId'] ?? json['SubjectId'] ?? 0) as int,
      subjectName: (json['subject'] ?? json['Subject'] ?? '').toString(),
      teacherId: (json['teacherId'] ?? json['TeacherId'] ?? 0) as int,
      teacherName: (json['teacher'] ?? json['Teacher'] ?? '').toString(),
    );
  }
}

class EnrolledStudentModel {
  final int studentId;
  final String username;
  final String fullName;
  final String email;

  const EnrolledStudentModel({
    required this.studentId,
    required this.username,
    required this.fullName,
    required this.email,
  });

  factory EnrolledStudentModel.fromJson(Map<String, dynamic> json) {
    return EnrolledStudentModel(
      studentId: (json['studentId'] ?? json['StudentId'] ?? 0) as int,
      username: (json['username'] ?? json['Username'] ?? '').toString(),
      fullName: (json['fullName'] ?? json['FullName'] ?? '').toString(),
      email: (json['email'] ?? json['Email'] ?? '').toString(),
    );
  }
}

class AbsenceRowModel {
  final int studentId;
  final String username;
  final String fullName;
  final String email;
  final int totalSessions;
  final int absentSessions;
  final double absentRate;
  final bool isWarned;

  const AbsenceRowModel({
    required this.studentId,
    required this.username,
    required this.fullName,
    required this.email,
    required this.totalSessions,
    required this.absentSessions,
    required this.absentRate,
    required this.isWarned,
  });

  factory AbsenceRowModel.fromJson(Map<String, dynamic> json) {
    return AbsenceRowModel(
      studentId: (json['studentId'] ?? json['StudentId'] ?? 0) as int,
      username: (json['username'] ?? json['Username'] ?? '').toString(),
      fullName: (json['fullName'] ?? json['FullName'] ?? '').toString(),
      email: (json['email'] ?? json['Email'] ?? '').toString(),
      totalSessions:
          (json['totalSessions'] ?? json['TotalSessions'] ?? 0) as int,
      absentSessions:
          (json['absentSessions'] ?? json['AbsentSessions'] ?? 0) as int,
      absentRate:
          ((json['absentRate'] ?? json['AbsentRate'] ?? 0) as num).toDouble(),
      isWarned: (json['isWarned'] ?? json['IsWarned'] ?? false) == true,
    );
  }
}

class ClassSessionModel {
  final int id;
  final String title;
  final DateTime startsAt;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final bool isOpen;
  final String? qrToken;

  const ClassSessionModel({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.isOpen,
    this.qrToken,
  });

  factory ClassSessionModel.fromJson(Map<String, dynamic> json) {
    final rawDate = (json['startsAt'] ?? json['StartsAt'] ?? '').toString();
    return ClassSessionModel(
      id: (json['id'] ?? json['Id'] ?? 0) as int,
      title: (json['title'] ?? json['Title'] ?? '').toString(),
      startsAt: DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now(),
      latitude: ((json['latitude'] ?? json['Latitude'] ?? 0) as num).toDouble(),
      longitude:
          ((json['longitude'] ?? json['Longitude'] ?? 0) as num).toDouble(),
      radiusMeters:
          ((json['radiusMeters'] ?? json['RadiusMeters'] ?? 50) as num)
              .toDouble(),
      isOpen: (json['isOpen'] ?? json['IsOpen'] ?? false) == true,
      qrToken: (json['qrToken'] ?? json['QrToken'])?.toString(),
    );
  }
}

class AttendanceModel {
  final int id;
  final int studentId;
  final String username;
  final String fullName;
  final DateTime checkedInAt;
  final double distanceMeters;
  final bool hasPhoto;

  const AttendanceModel({
    required this.id,
    required this.studentId,
    required this.username,
    required this.fullName,
    required this.checkedInAt,
    required this.distanceMeters,
    required this.hasPhoto,
  });

  factory AttendanceModel.fromJson(Map<String, dynamic> json) {
    final rawDate =
        (json['checkedInAt'] ?? json['CheckedInAt'] ?? '').toString();
    return AttendanceModel(
      id: (json['id'] ?? json['Id'] ?? 0) as int,
      studentId: (json['studentId'] ?? json['StudentId'] ?? 0) as int,
      username: (json['username'] ?? json['Username'] ?? '').toString(),
      fullName: (json['fullName'] ?? json['FullName'] ?? '').toString(),
      checkedInAt: DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now(),
      distanceMeters:
          ((json['distanceMeters'] ?? json['DistanceMeters'] ?? 0) as num)
              .toDouble(),
      hasPhoto: (json['hasPhoto'] ?? json['HasPhoto'] ?? false) == true,
    );
  }
}

class LeaveRequestModel {
  final int id;
  final int classSessionId;
  final String sessionTitle;
  final int? studentId;
  final String? studentName;
  final String reason;
  final bool hasEvidence;
  final String status;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  const LeaveRequestModel({
    required this.id,
    required this.classSessionId,
    required this.sessionTitle,
    this.studentId,
    this.studentName,
    required this.reason,
    required this.hasEvidence,
    required this.status,
    required this.createdAt,
    this.reviewedAt,
  });

  factory LeaveRequestModel.fromJson(Map<String, dynamic> json) {
    final rawCreated =
        (json['createdAt'] ?? json['CreatedAt'] ?? '').toString();
    final rawReviewed = (json['reviewedAt'] ?? json['ReviewedAt'])?.toString();
    return LeaveRequestModel(
      id: (json['id'] ?? json['Id'] ?? 0) as int,
      classSessionId:
          (json['classSessionId'] ?? json['ClassSessionId'] ?? 0) as int,
      sessionTitle: (json['session'] ?? json['Session'] ?? '').toString(),
      studentId: (json['studentId'] ?? json['StudentId']) as int?,
      studentName: (json['student'] ?? json['Student'])?.toString(),
      reason: (json['reason'] ?? json['Reason'] ?? '').toString(),
      hasEvidence:
          (json['hasEvidence'] ?? json['HasEvidence'] ?? false) == true,
      status: LeaveStatusHelper.normalize(json['status'] ?? json['Status']),
      createdAt: DateTime.tryParse(rawCreated)?.toLocal() ?? DateTime.now(),
      reviewedAt:
          rawReviewed != null ? DateTime.tryParse(rawReviewed)?.toLocal() : null,
    );
  }
}

String formatDateTime(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final y = dt.year;
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$d/$m/$y $hh:$mm';
}
