import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/api_models.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/common_widgets.dart';

class SmartFeaturesScreen extends StatefulWidget {
  final ApiClient api;
  final AuthSession? session;
  final bool showAppBar;
  final int initialTab;

  const SmartFeaturesScreen({
    super.key,
    required this.api,
    this.session,
    this.showAppBar = false,
    this.initialTab = 0,
  });

  static final ValueNotifier<int> sessionChangeNotifier = ValueNotifier<int>(0);
  static int? preferredSessionId;
  static final Map<String, String> _placeLabelsByCoord = {
    '10.7769,106.7009': 'Cơ sở Quận 1 - TP.HCM',
    '10.8506,106.7719': 'Cơ sở Khu Công Nghệ Cao (TP. Thủ Đức)',
    '10.8018,106.7145': 'Cơ sở Bình Thạnh - Điện Biên Phủ',
    '10.7324,106.6992': 'Cơ sở Quận 7 - Nguyễn Hữu Thọ',
    '10.4594,105.6326': 'Cơ sở Đồng Tháp - TP. Cao Lãnh',
    '10.0302,105.7721': 'Cơ sở Cần Thơ - Ninh Kiều',
    '21.0368,105.7829': 'Cơ sở Hà Nội - Cầu Giấy',
  };

  static String _coordKey(double lat, double lon) =>
      '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';

  static void registerPlaceLabel(double lat, double lon, String label) {
    if (label.trim().isEmpty) return;
    _placeLabelsByCoord[_coordKey(lat, lon)] = label.trim();
  }

  static String describeCoordinates(double lat, double lon) {
    if (lat == 0.0 && lon == 0.0) return 'Chưa đặt vị trí cố định';
    final exact = _placeLabelsByCoord[_coordKey(lat, lon)];
    if (exact != null) return exact;
    for (final entry in _placeLabelsByCoord.entries) {
      final parts = entry.key.split(',');
      if (parts.length == 2) {
        final kLat = double.tryParse(parts[0]) ?? 0;
        final kLon = double.tryParse(parts[1]) ?? 0;
        if ((kLat - lat).abs() < 0.002 && (kLon - lon).abs() < 0.002) {
          return entry.value;
        }
      }
    }
    return 'Vị trí (${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)})';
  }

  static void notifySessionsChanged({
    int? preferredId,
    double? lat,
    double? lon,
    String? placeName,
  }) {
    if (preferredId != null) {
      preferredSessionId = preferredId;
    }
    if (lat != null &&
        lon != null &&
        placeName != null &&
        placeName.isNotEmpty) {
      registerPlaceLabel(lat, lon, placeName);
    }
    sessionChangeNotifier.value++;
  }

  @override
  State<SmartFeaturesScreen> createState() => _SmartFeaturesScreenState();
}

class _UpcomingClassSessionInfo {
  final ClassRoomModel classRoom;
  final ClassSessionModel session;
  final DateTime targetStartTime;

  const _UpcomingClassSessionInfo({
    required this.classRoom,
    required this.session,
    required this.targetStartTime,
  });
}

class _SmartFeaturesScreenState extends State<SmartFeaturesScreen>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _launcherChannel = MethodChannel(
    'nhom01/launcher',
  );

  late final TabController _tabController;

  // Danh sách buổi học sắp tới & đồng hồ đếm ngược (Ngày / Giờ / Phút / Giây)
  List<_UpcomingClassSessionInfo> _upcomingSessions = [];
  _UpcomingClassSessionInfo? _selectedUpcoming;
  Timer? _countdownTimer;
  Duration _remainingTime = Duration.zero;

  // ===========================================================================
  // STATE 1: ĐĂNG KÝ VÂN TAY LẦN ĐẦU & THAY ĐỔI DẤU VÂN TAY
  // ===========================================================================
  Map<String, dynamic>? _bioRegInfo;
  bool _bioBusy = false;

  // ===========================================================================
  // STATE 2: VỊ TRÍ CỦA BẠN, BẢN ĐỒ ĐƯỜNG ĐI GOOGLE MAPS & LỚP HỌC SẮP TỚI
  // ===========================================================================
  double? _myLat;
  double? _myLon;
  double? _myAccuracy;
  bool _loadingGps = false;
  String _gpsStatusMessage = 'Đang xác định tọa độ GPS thực tế của bạn...';
  bool _isLiveSharing = false;
  StreamSubscription<Position>? _positionStreamSub;

  // Dữ liệu đường đi thực tế (OSRM Street Route)
  List<({double lat, double lon})> _routePolyline = [];
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;
  bool _loadingRoute = false;
  int _mapZoom = 15;
  int _mapFocusMode = 0; // 0: Toàn lộ trình, 1: Tâm lớp học, 2: Vị trí của bạn

  // ===========================================================================
  // STATE 3: DỊCH REALTIME & CHỤP ẢNH DỊCH VĂN BẢN / TÀI LIỆU (ML KIT OCR)
  // ===========================================================================
  int _translateSubMode = 0; // 0: Dịch văn bản Realtime, 1: Chụp ảnh dịch OCR
  String _sourceLang = 'vi';
  String _targetLang = 'en';
  final _translateInputCtrl = TextEditingController(
    text:
        'Em xin phép giảng viên nghỉ học buổi sáng nay vì lý do khám sức khỏe định kỳ tại bệnh viện.',
  );
  String _translatedOutput = '';
  bool _isTranslating = false;
  Timer? _translateDebounce;

  final ImagePicker _imagePicker = ImagePicker();
  String? _capturedImagePath;
  bool _ocrProcessing = false;
  final _ocrExtractedCtrl = TextEditingController();
  String _ocrTranslatedText = '';
  List<String> _ocrDetectedLines = [];

  static const Map<String, String> _langNames = {
    'vi': 'Tiếng Việt 🇻🇳',
    'en': 'Tiếng Anh 🇬🇧',
    'ja': 'Tiếng Nhật 🇯🇵',
    'ko': 'Tiếng Hàn 🇰🇷',
    'zh-CN': 'Tiếng Trung 🇨🇳',
    'fr': 'Tiếng Pháp 🇫🇷',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _tabController.addListener(_onInternalTabChanged);
    SmartFeaturesScreen.sessionChangeNotifier.addListener(
      _onExternalSessionsChanged,
    );
    _startCountdownTimer();
    _loadBioAndSessionInfo();
    _fetchRealGpsLocation(silent: true);
    _runRealtimeTranslation(_translateInputCtrl.text);
  }

  void _onInternalTabChanged() {
    if (!_tabController.indexIsChanging && _tabController.index == 1) {
      _loadBioAndSessionInfo();
    }
  }

  void _onExternalSessionsChanged() {
    if (mounted) {
      _loadBioAndSessionInfo();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onInternalTabChanged);
    SmartFeaturesScreen.sessionChangeNotifier.removeListener(
      _onExternalSessionsChanged,
    );
    _tabController.dispose();
    _translateInputCtrl.dispose();
    _ocrExtractedCtrl.dispose();
    _positionStreamSub?.cancel();
    _translateDebounce?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _selectedUpcoming == null) return;
      final now = DateTime.now();
      var target = _selectedUpcoming!.targetStartTime;
      if (target.isBefore(now)) {
        // Nếu đã qua mốc giờ, tính lịch buổi học kế tiếp cùng khung giờ
        final diffDays = now.difference(target).inDays + 1;
        target = target.add(Duration(days: diffDays));
      }
      setState(() {
        _remainingTime = target.difference(now);
      });
    });
  }

  DateTime _computeNextTargetTime(DateTime startsAt, DateTime now) {
    if (startsAt.isAfter(now)) return startsAt;
    var candidate = DateTime(
      now.year,
      now.month,
      now.day,
      startsAt.hour,
      startsAt.minute,
      startsAt.second,
    );
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  Future<void> _loadBioAndSessionInfo() async {
    final info = await AuthService.getBiometricRegistrationInfo();
    if (mounted) {
      setState(() => _bioRegInfo = info);
    }

    if (widget.session == null) return;
    try {
      final classes = await widget.api.getClasses();
      final now = DateTime.now();
      final items = <_UpcomingClassSessionInfo>[];

      for (final c in classes) {
        try {
          final sList = await widget.api.getClassSessions(c.id);
          for (final s in sList) {
            items.add(
              _UpcomingClassSessionInfo(
                classRoom: c,
                session: s,
                targetStartTime: _computeNextTargetTime(s.startsAt, now),
              ),
            );
          }
        } catch (_) {}
      }
      if (!mounted) return;

      // Sắp xếp ưu tiên:
      // 1. Buổi học có tọa độ thực tế (latitude != 0 || longitude != 0) lên trước buổi học (0,0)
      // 2. Buổi học mới tạo gần nhất (id lớn nhất) hoặc sắp diễn ra
      items.sort((a, b) {
        final aHasCoord =
            a.session.latitude != 0.0 || a.session.longitude != 0.0;
        final bHasCoord =
            b.session.latitude != 0.0 || b.session.longitude != 0.0;
        if (aHasCoord != bHasCoord) return aHasCoord ? -1 : 1;

        final aFuture = a.session.startsAt.isAfter(now);
        final bFuture = b.session.startsAt.isAfter(now);
        if (aFuture != bFuture) return aFuture ? -1 : 1;

        // Ưu tiên buổi học vừa mới tạo (ID lớn hơn) để khi tạo buổi học ở vị trí mới sẽ hiển thị ngay
        final idCmp = b.session.id.compareTo(a.session.id);
        if (idCmp != 0) return idCmp;

        return a.targetStartTime.compareTo(b.targetStartTime);
      });

      _UpcomingClassSessionInfo? chosen;
      final prefId = SmartFeaturesScreen.preferredSessionId;
      if (prefId != null) {
        for (final item in items) {
          if (item.session.id == prefId) {
            chosen = item;
            break;
          }
        }
      }
      chosen ??= items.isNotEmpty ? items.first : null;

      setState(() {
        _upcomingSessions = items;
        _selectedUpcoming = chosen;
        if (_selectedUpcoming != null) {
          _remainingTime = _selectedUpcoming!.targetStartTime.difference(now);
          final room = _getClassroomCoords(_selectedUpcoming);
          if (_myLat != null && _myLon != null) {
            final d = Geolocator.distanceBetween(
              _myLat!,
              _myLon!,
              room.lat,
              room.lon,
            );
            _mapFocusMode = d > 3000 ? 1 : 0;
          } else {
            _mapFocusMode = 1;
          }
        }
      });
      _fetchRoadRoute();
    } catch (_) {}
  }

  /// Lấy tọa độ phòng học của buổi học sắp tới (nếu DB đang để 0,0 thì dùng tọa độ cơ sở trường lân cận)
  ({double lat, double lon, bool isConfiguredInDb}) _getClassroomCoords(
    _UpcomingClassSessionInfo? info,
  ) {
    if (info != null &&
        (info.session.latitude != 0.0 || info.session.longitude != 0.0)) {
      return (
        lat: info.session.latitude,
        lon: info.session.longitude,
        isConfiguredInDb: true,
      );
    }
    // Nếu buổi học trong DB chưa nhập tọa độ (0.0, 0.0), hiển thị vị trí phòng học cơ sở gần vị trí hiện tại
    final baseLat = _myLat ?? 10.7769;
    final baseLon = _myLon ?? 106.7009;
    return (
      lat: baseLat + 0.0028,
      lon: baseLon + 0.0024,
      isConfiguredInDb: false,
    );
  }

  /// Tính toán đường đi thực tế trên bản đồ (OSRM Routing API như Google Maps)
  Future<void> _fetchRoadRoute() async {
    final room = _getClassroomCoords(_selectedUpcoming);
    if (_myLat == null || _myLon == null) {
      if (mounted) {
        setState(() {
          _routePolyline = [];
          _mapZoom = 16;
        });
      }
      return;
    }
    final startLat = _myLat!;
    final startLon = _myLon!;
    final endLat = room.lat;
    final endLon = room.lon;
    final directDist = Geolocator.distanceBetween(
      startLat,
      startLon,
      endLat,
      endLon,
    );

    setState(() => _loadingRoute = true);
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$startLon,$startLat;$endLon,$endLat'
        '?overview=full&geometries=geojson',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final routes = data['routes'];
        if (routes is List && routes.isNotEmpty) {
          final firstRoute = routes.first as Map<String, dynamic>;
          final dist = (firstRoute['distance'] as num?)?.toDouble();
          final dur = (firstRoute['duration'] as num?)?.toDouble();
          final geom = firstRoute['geometry'] as Map<String, dynamic>?;
          final coords = geom?['coordinates'] as List?;
          if (coords != null && coords.isNotEmpty) {
            final pts = <({double lat, double lon})>[];
            for (final c in coords) {
              if (c is List && c.length >= 2) {
                pts.add((
                  lat: (c[1] as num).toDouble(),
                  lon: (c[0] as num).toDouble(),
                ));
              }
            }
            if (mounted && pts.length >= 2) {
              setState(() {
                _routePolyline = pts;
                _routeDistanceMeters = dist;
                _routeDurationSeconds = dur;
                _mapZoom =
                    _mapFocusMode == 0
                        ? _suggestZoomForDistance(directDist)
                        : 16;
              });
              return;
            }
          }
        }
      }
    } catch (_) {
      // Fallback sang đường gấp khúc mô phỏng lộ trình phố nếu mạng chặn OSRM
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }

    if (!mounted) return;
    final midLat = (startLat + endLat) / 2;
    final midLon = (startLon + endLon) / 2;
    setState(() {
      _routePolyline = [
        (lat: startLat, lon: startLon),
        (lat: startLat, lon: midLon),
        (lat: midLat, lon: midLon),
        (lat: endLat, lon: midLon),
        (lat: endLat, lon: endLon),
      ];
      _routeDistanceMeters = directDist * 1.22;
      _routeDurationSeconds = (directDist * 1.22) / 8.3; // ~30km/h
      _mapZoom = _mapFocusMode == 0 ? _suggestZoomForDistance(directDist) : 16;
    });
  }

  int _suggestZoomForDistance(double meters) {
    if (meters < 200) return 17;
    if (meters < 550) return 16;
    if (meters < 1500) return 15;
    if (meters < 3500) return 14;
    if (meters < 8000) return 13;
    if (meters < 18000) return 12;
    if (meters < 38000) return 11;
    if (meters < 80000) return 10;
    if (meters < 170000) return 9;
    if (meters < 360000) return 8;
    if (meters < 750000) return 7;
    return 6;
  }

  Future<void> _openGoogleMapsDirections() async {
    if (_myLat == null || _myLon == null) {
      showAppSnackBar(
        context,
        'Đang lấy tọa độ GPS của bạn, vui lòng thử lại sau giây lát.',
        isError: true,
      );
      return;
    }
    final room = _getClassroomCoords(_selectedUpcoming);
    final url =
        'https://www.google.com/maps/dir/?api=1'
        '&origin=${_myLat!.toStringAsFixed(6)},${_myLon!.toStringAsFixed(6)}'
        '&destination=${room.lat.toStringAsFixed(6)},${room.lon.toStringAsFixed(6)}'
        '&travelmode=driving';
    try {
      await _launcherChannel.invokeMethod('openUrl', {'url': url});
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Đã sao chép liên kết chỉ đường Google Maps vào bộ nhớ tạm!',
      );
    }
  }

  // ===========================================================================
  // LOGIC 1: ĐĂNG KÝ VÂN TAY LẦN ĐẦU & ĐỔI DẤU VÂN TAY (MẬT KHẨU / VÂN TAY CŨ)
  // ===========================================================================

  Future<void> _handleFirstTimeBiometricRegistration() async {
    final session = widget.session;
    if (session == null) {
      showAppSnackBar(
        context,
        'Vui lòng đăng nhập tài khoản trước khi đăng ký vân tay.',
        isError: true,
      );
      return;
    }

    setState(() => _bioBusy = true);
    try {
      final ok = await AuthService.authenticateWithHardwareBiometrics(
        reason:
            'Chạm cảm biến vân tay ở cạnh bên điện thoại để ĐĂNG KÝ vân tay cho tài khoản @${session.username}',
      );
      if (!mounted) return;
      if (ok) {
        HapticFeedback.heavyImpact();
        await AuthService.registerBiometricForSession(session);
        final updated = await AuthService.getBiometricRegistrationInfo();
        if (!mounted) return;
        setState(() => _bioRegInfo = updated);
        showAppSnackBar(
          context,
          'Đăng ký vân tay thành công cho tài khoản @${session.username}!',
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _bioBusy = false);
    }
  }

  Future<void> _handleChangeBiometricByPassword() async {
    final session = widget.session;
    if (session == null) return;

    final passCtrl = TextEditingController();
    bool obscure = true;
    final confirmedPassword = await showDialog<String>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setModal) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: const Row(
                    children: [
                      Icon(Icons.lock_person_rounded, color: Color(0xFF4F46E5)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Xác nhận mật khẩu để đổi vân tay',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Nhập mật khẩu của tài khoản @${session.username} để đăng ký dấu vân tay mới:',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passCtrl,
                        obscureText: obscure,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu hiện tại',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setModal(() => obscure = !obscure),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Huỷ'),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, passCtrl.text),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Xác nhận & Quét vân tay mới'),
                    ),
                  ],
                ),
          ),
    );

    if (confirmedPassword == null || confirmedPassword.isEmpty) return;

    setState(() => _bioBusy = true);
    try {
      final validPass = await AuthService.verifyCurrentPassword(
        username: session.username,
        password: confirmedPassword,
        api: widget.api,
      );
      if (!mounted) return;
      if (!validPass) {
        showAppSnackBar(
          context,
          'Mật khẩu không chính xác. Không thể thay đổi dấu vân tay.',
          isError: true,
        );
        return;
      }

      final scannedNew = await AuthService.authenticateWithHardwareBiometrics(
        reason:
            'Mật khẩu hợp lệ! Hãy chạm DẤU VÂN TAY MỚI vào cảm biến cạnh máy để lưu',
      );
      if (!mounted) return;
      if (scannedNew) {
        HapticFeedback.heavyImpact();
        await AuthService.registerBiometricForSession(session);
        final updated = await AuthService.getBiometricRegistrationInfo();
        if (!mounted) return;
        setState(() => _bioRegInfo = updated);
        showAppSnackBar(
          context,
          'Đã cập nhật dấu vân tay mới thành công (Xác thực bằng mật khẩu)!',
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _bioBusy = false);
    }
  }

  Future<void> _handleChangeBiometricByOldFingerprint() async {
    final session = widget.session;
    if (session == null) return;

    setState(() => _bioBusy = true);
    try {
      final oldOk = await AuthService.authenticateWithHardwareBiometrics(
        reason:
            'Bước 1/2: Chạm DẤU VÂN TAY CŨ hiện tại vào cảm biến cạnh máy để xác nhận',
      );
      if (!mounted) return;
      if (!oldOk) {
        showAppSnackBar(
          context,
          'Chưa xác thực được dấu vân tay cũ.',
          isError: true,
        );
        return;
      }

      final proceedToNew = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.fingerprint_rounded, color: Color(0xFF059669)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đã xác nhận vân tay cũ!',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: const Text(
                'Bước 2/2: Nhấn nút bên dưới rồi đặt DẤU VÂN TAY MỚI lên cảm biến ở cạnh điện thoại để hoàn tất thay đổi.',
                style: TextStyle(fontSize: 13.5, height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Huỷ'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('Quét vân tay mới ngay'),
                ),
              ],
            ),
      );

      if (proceedToNew != true || !mounted) return;

      final newOk = await AuthService.authenticateWithHardwareBiometrics(
        reason:
            'Bước 2/2: Chạm DẤU VÂN TAY MỚI vào cảm biến cạnh máy để lưu đăng ký',
      );
      if (!mounted) return;
      if (newOk) {
        HapticFeedback.heavyImpact();
        await AuthService.registerBiometricForSession(session);
        final updated = await AuthService.getBiometricRegistrationInfo();
        if (!mounted) return;
        setState(() => _bioRegInfo = updated);
        showAppSnackBar(
          context,
          'Đã thay đổi sang dấu vân tay mới thành công!',
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _bioBusy = false);
    }
  }

  Future<void> _handleRemoveBiometric() async {
    await AuthService.clearBiometricRegistration();
    final updated = await AuthService.getBiometricRegistrationInfo();
    if (!mounted) return;
    setState(() => _bioRegInfo = updated);
    showAppSnackBar(context, 'Đã huỷ liên kết đăng nhập vân tay trên máy.');
  }

  // ===========================================================================
  // LOGIC 2: HIỂN THỊ & CHIA SẺ VỊ TRÍ GPS HIỆN TẠI CHO SINH VIÊN BIẾT
  // ===========================================================================

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _gpsStatusMessage =
              'Thiết bị đang tắt Định vị (GPS). Vui lòng bật GPS trên điện thoại.';
        });
        showAppSnackBar(
          context,
          'Vui lòng bật dịch vụ Vị trí (GPS) trên điện thoại.',
          isError: true,
        );
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _gpsStatusMessage =
              'Chưa cấp quyền truy cập Vị trí (GPS) cho ứng dụng.';
        });
        showAppSnackBar(
          context,
          'Vui lòng cấp quyền Vị trí (Location) cho ứng dụng.',
          isError: true,
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _fetchRealGpsLocation({bool silent = false}) async {
    if (_loadingGps) return;
    setState(() => _loadingGps = true);
    try {
      final hasPerm = await _ensureLocationPermission();
      if (!hasPerm) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _myLat = pos.latitude;
        _myLon = pos.longitude;
        _myAccuracy = pos.accuracy;
        _gpsStatusMessage =
            'Đã cập nhật vị trí thực tế (Độ chính xác ±${pos.accuracy.toStringAsFixed(1)}m)';
      });
      _fetchRoadRoute();
      if (!silent) {
        showAppSnackBar(
          context,
          'Vị trí hiện tại của bạn: (${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)})',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gpsStatusMessage = 'Không lấy được GPS: $e';
      });
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  Future<void> _toggleLiveSharing(bool value) async {
    await _positionStreamSub?.cancel();
    _positionStreamSub = null;

    if (!value) {
      setState(() => _isLiveSharing = false);
      return;
    }

    final hasPerm = await _ensureLocationPermission();
    if (!hasPerm) return;

    await _fetchRealGpsLocation(silent: true);
    if (!mounted) return;

    setState(() => _isLiveSharing = true);
    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position pos) {
      if (!mounted) return;
      setState(() {
        _myLat = pos.latitude;
        _myLon = pos.longitude;
        _myAccuracy = pos.accuracy;
        _gpsStatusMessage =
            'Đang theo dõi vị trí trực tiếp (Sai số ±${pos.accuracy.toStringAsFixed(1)}m)';
      });
      _fetchRoadRoute();
    });
  }

  void _copyShareableLocationLink() {
    if (_myLat == null || _myLon == null) {
      showAppSnackBar(
        context,
        'Vui lòng bấm "Cập nhật vị trí hiện tại" trước khi chia sẻ.',
        isError: true,
      );
      return;
    }
    final latStr = _myLat!.toStringAsFixed(6);
    final lonStr = _myLon!.toStringAsFixed(6);
    final mapsUrl = 'https://www.google.com/maps?q=$latStr,$lonStr';

    final shareText =
        '📍 Vị trí hiện tại của ${widget.session?.fullName ?? "Sinh viên"}:\n'
        '• Vĩ độ (Latitude): $latStr\n'
        '• Kinh độ (Longitude): $lonStr\n'
        '• Xem trên Google Maps: $mapsUrl';
    Clipboard.setData(ClipboardData(text: shareText));
    showAppSnackBar(
      context,
      'Đã sao chép tọa độ vị trí & link Google Maps!',
    );
  }

  // ===========================================================================
  // LOGIC 3: DỊCH REALTIME & CHỤP ẢNH OCR THỰC TẾ (CAMERA / GALLERY + ML KIT)
  // ===========================================================================

  void _onTranslateTextChanged(String text) {
    _translateDebounce?.cancel();
    _translateDebounce = Timer(const Duration(milliseconds: 420), () {
      _runRealtimeTranslation(text);
    });
  }

  Future<String> _translateTextViaApi(
    String text, {
    required String sl,
    required String tl,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return '';
    try {
      final uri = Uri.parse(
        'https://translate.googleapis.com/translate_a/single'
        '?client=gtx&sl=$sl&tl=$tl&dt=t&q=${Uri.encodeQueryComponent(clean)}',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        if (decoded is List && decoded.isNotEmpty && decoded[0] is List) {
          final segments = decoded[0] as List;
          final buffer = StringBuffer();
          for (final seg in segments) {
            if (seg is List && seg.isNotEmpty && seg[0] != null) {
              buffer.write(seg[0].toString());
            }
          }
          final result = buffer.toString().trim();
          if (result.isNotEmpty) return result;
        }
      }
    } catch (_) {}
    return '[Bản dịch $sl → $tl]: $clean';
  }

  Future<void> _runRealtimeTranslation(String input) async {
    final clean = input.trim();
    if (clean.isEmpty) {
      if (mounted) setState(() => _translatedOutput = '');
      return;
    }
    setState(() => _isTranslating = true);
    final res = await _translateTextViaApi(
      clean,
      sl: _sourceLang,
      tl: _targetLang,
    );
    if (!mounted) return;
    setState(() {
      _translatedOutput = res;
      _isTranslating = false;
    });
  }

  Future<void> _captureOrPickImageForOcr(ImageSource source) async {
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 92,
      );
      if (picked == null) return;

      setState(() {
        _capturedImagePath = picked.path;
        _ocrProcessing = true;
        _ocrDetectedLines = [];
        _ocrExtractedCtrl.clear();
        _ocrTranslatedText = '';
      });

      final inputImage = InputImage.fromFilePath(picked.path);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      RecognizedText recognizedText;
      try {
        recognizedText = await textRecognizer.processImage(inputImage);
      } finally {
        await textRecognizer.close();
      }

      final extracted = recognizedText.text.trim();
      final lines = <String>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          if (line.text.trim().isNotEmpty) {
            lines.add(line.text.trim());
          }
        }
      }

      if (!mounted) return;
      if (extracted.isEmpty) {
        setState(() => _ocrProcessing = false);
        showAppSnackBar(
          context,
          'Không phát hiện được chữ viết trong ảnh. Vui lòng chụp rõ nét hơn.',
          isError: true,
        );
        return;
      }

      setState(() {
        _ocrDetectedLines = lines;
        _ocrExtractedCtrl.text = extracted;
      });

      final translated = await _translateTextViaApi(
        extracted,
        sl: _sourceLang,
        tl: _targetLang,
      );
      if (!mounted) return;
      setState(() {
        _ocrTranslatedText = translated;
        _ocrProcessing = false;
      });
      showAppSnackBar(
        context,
        'Đã nhận diện ${lines.length} dòng văn bản từ ảnh và dịch hoàn tất!',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocrProcessing = false);
      showAppSnackBar(
        context,
        'Không thể chụp/đọc văn bản từ ảnh: $e',
        isError: true,
      );
    }
  }

  Future<void> _retranslateOcrExtractedText() async {
    final text = _ocrExtractedCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _ocrProcessing = true);
    final translated = await _translateTextViaApi(
      text,
      sl: _sourceLang,
      tl: _targetLang,
    );
    if (!mounted) return;
    setState(() {
      _ocrTranslatedText = translated;
      _ocrProcessing = false;
    });
  }

  void _swapLanguages() {
    setState(() {
      final tmp = _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = tmp;
    });
    if (_translateSubMode == 0) {
      if (_translatedOutput.isNotEmpty) {
        _translateInputCtrl.text = _translatedOutput;
      }
      _runRealtimeTranslation(_translateInputCtrl.text);
    } else {
      _retranslateOcrExtractedText();
    }
  }

  // ===========================================================================
  // GIAO DIỆN CHÍNH: 3 TAB (VÂN TAY | VỊ TRÍ | DỊCH & CHỤP ẢNH)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: TabBar(
            controller: _tabController,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFF475569),
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            tabs: const [
              Tab(
                icon: Icon(Icons.fingerprint_rounded, size: 19),
                text: 'Vân tay',
              ),
              Tab(
                icon: Icon(Icons.location_on_rounded, size: 19),
                text: 'Vị trí',
              ),
              Tab(
                icon: Icon(Icons.translate_rounded, size: 19),
                text: 'Dịch & Chụp ảnh',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildBiometricTab(),
              _buildStudentLocationInfoTab(),
              _buildTranslatorTab(),
            ],
          ),
        ),
      ],
    );

    if (!widget.showAppBar) return content;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TIỆN ÍCH THÔNG MINH',
          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
        ),
      ),
      body: content,
    );
  }

  // ===========================================================================
  // UI TAB 1: CHỈ ĐỂ ĐĂNG KÝ VÂN TAY LẦN ĐẦU & ĐỔI DẤU VÂN TAY (ĐÃ BỎ QR)
  // ===========================================================================

  Widget _buildBiometricTab() {
    final currentUsername = widget.session?.username ?? '';
    final registeredUser = _bioRegInfo?['username']?.toString() ?? '';
    final isCurrentAccountEnrolled =
        _bioRegInfo != null &&
        registeredUser.toLowerCase() == currentUsername.toLowerCase();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'Đăng ký & Thay đổi Dấu Vân Tay Đăng Nhập',
          subtitle:
              'Đăng ký vân tay khi lần đầu đăng nhập hoặc thay đổi dấu vân tay mới bằng mật khẩu / vân tay cũ',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      isCurrentAccountEnrolled
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        isCurrentAccountEnrolled
                            ? const Color(0xFF10B981)
                            : const Color(0xFFC7D2FE),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            isCurrentAccountEnrolled
                                ? const Color(0xFF059669)
                                : const Color(0xFF4F46E5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCurrentAccountEnrolled
                            ? Icons.verified_user_rounded
                            : Icons.fingerprint_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isCurrentAccountEnrolled
                                ? 'ĐÃ ĐĂNG KÝ VÂN TAY ĐĂNG NHẬP'
                                : 'CHƯA ĐĂNG KÝ VÂN TAY CHO TÀI KHOẢN NÀY',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color:
                                  isCurrentAccountEnrolled
                                      ? const Color(0xFF065F46)
                                      : const Color(0xFF312E81),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isCurrentAccountEnrolled
                                ? 'Tài khoản: @${_bioRegInfo!['username']} (${RoleHelper.shortLabel(_bioRegInfo!['role'].toString())})\n'
                                    'Phiên bản vân tay: #${_bioRegInfo!['version']} • Cập nhật: ${_bioRegInfo!['enrolledAt']}'
                                : 'Khi lần đầu đăng nhập, hãy bấm nút bên dưới và chạm cảm biến vân tay ở cạnh điện thoại để kích hoạt đăng nhập bằng vân tay.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF475569),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (!isCurrentAccountEnrolled) ...[
                FilledButton.icon(
                  onPressed:
                      _bioBusy ? null : _handleFirstTimeBiometricRegistration,
                  icon:
                      _bioBusy
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.fingerprint_rounded),
                  label: Text(
                    _bioBusy
                        ? 'Đang chờ chạm cảm biến vân tay cạnh máy...'
                        : 'Đăng ký vân tay lần đầu cho @${widget.session?.username ?? "tài khoản"}',
                  ),
                ),
              ] else ...[
                const Text(
                  'Thay đổi / Đăng ký lại dấu vân tay mới:',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _bioBusy ? null : _handleChangeBiometricByPassword,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                  ),
                  icon: const Icon(Icons.password_rounded, size: 19),
                  label: const Text('Đổi dấu vân tay mới bằng Mật khẩu'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed:
                      _bioBusy ? null : _handleChangeBiometricByOldFingerprint,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                  ),
                  icon: const Icon(Icons.fingerprint_rounded, size: 20),
                  label: const Text('Đổi dấu vân tay mới bằng Dấu vân tay cũ'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _bioBusy ? null : _handleRemoveBiometric,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                  ),
                  icon: const Icon(Icons.link_off_rounded, size: 18),
                  label: const Text('Huỷ đăng ký vân tay trên thiết bị'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // UI TAB 2: VỊ TRÍ CỦA BẠN, BẢN ĐỒ ĐƯỜNG ĐI GOOGLE MAPS & LỚP HỌC SẮP TỚI
  // ===========================================================================

  Widget _buildCountdownUnitBox(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentLocationInfoTab() {
    final hasMyGps = _myLat != null && _myLon != null;
    final upcoming = _selectedUpcoming;
    final roomCoords = _getClassroomCoords(upcoming);

    final double? straightDistMeters =
        hasMyGps
            ? Geolocator.distanceBetween(
              _myLat!,
              _myLon!,
              roomCoords.lat,
              roomCoords.lon,
            )
            : null;
    final double allowedRadius =
        (upcoming != null && upcoming.session.radiusMeters > 0)
            ? upcoming.session.radiusMeters
            : 100.0;
    final bool isInsideRange =
        straightDistMeters != null && straightDistMeters <= allowedRadius;

    final totalSecs =
        _remainingTime.inSeconds > 0 ? _remainingTime.inSeconds : 0;
    final days = (totalSecs ~/ 86400).toString().padLeft(2, '0');
    final hours = ((totalSecs % 86400) ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((totalSecs % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSecs % 60).toString().padLeft(2, '0');

    final roadDistStr =
        _routeDistanceMeters != null
            ? (_routeDistanceMeters! >= 1000
                ? '${(_routeDistanceMeters! / 1000).toStringAsFixed(2)} km'
                : '${_routeDistanceMeters!.round()} m')
            : (straightDistMeters != null
                ? '${straightDistMeters.round()} m'
                : '--');
    final roadTimeStr =
        _routeDurationSeconds != null
            ? '${math.max(1, (_routeDurationSeconds! / 60).round())} phút'
            : '--';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. THẺ LỚP HỌC SẮP HỌC GẦN NHẤT & ĐỒNG HỒ ĐẾM NGƯỢC (NGÀY / GIỜ / PHÚT / GIÂY)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF312E81).withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.timer_outlined,
                      color: Color(0xFF38BDF8),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LỚP HỌC SẮP HỌC GẦN NHẤT',
                          style: TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          upcoming != null
                              ? '${upcoming.classRoom.name} • ${upcoming.session.title}'
                              : 'Chưa có lịch buổi học sắp tới',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (upcoming != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            upcoming.session.isOpen
                                ? const Color(0xFF059669)
                                : const Color(0xFF0284C7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        upcoming.session.isOpen ? 'Đang mở' : 'Sắp diễn ra',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              if (upcoming != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Môn: ${upcoming.classRoom.subjectName} • GV: ${upcoming.classRoom.teacherName}\n'
                  'Thời gian học: ${formatDateTime(upcoming.targetStartTime)}\n'
                  'Địa điểm lớp: ${SmartFeaturesScreen.describeCoordinates(roomCoords.lat, roomCoords.lon)} (${roomCoords.lat.toStringAsFixed(4)}, ${roomCoords.lon.toStringAsFixed(4)})',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'THỜI GIAN ĐẾM NGƯỢC ĐẾN GIỜ VÀO LỚP:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildCountdownUnitBox(days, 'NGÀY'),
                  const SizedBox(width: 8),
                  _buildCountdownUnitBox(hours, 'GIỜ'),
                  const SizedBox(width: 8),
                  _buildCountdownUnitBox(minutes, 'PHÚT'),
                  const SizedBox(width: 8),
                  _buildCountdownUnitBox(seconds, 'GIÂY'),
                ],
              ),
              if (_upcomingSessions.length > 1) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<_UpcomingClassSessionInfo>(
                      value: _selectedUpcoming,
                      dropdownColor: const Color(0xFF1E1B4B),
                      isExpanded: true,
                      iconEnabledColor: Colors.white,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                      ),
                      items:
                          _upcomingSessions
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(
                                    'Đổi buổi xem: ${u.classRoom.name} - ${u.session.title} (${formatDateTime(u.targetStartTime)})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          SmartFeaturesScreen.preferredSessionId =
                              val.session.id;
                          final room = _getClassroomCoords(val);
                          int nextFocus = 1;
                          if (_myLat != null && _myLon != null) {
                            final d = Geolocator.distanceBetween(
                              _myLat!,
                              _myLon!,
                              room.lat,
                              room.lon,
                            );
                            nextFocus = d > 3000 ? 1 : 0;
                          }
                          setState(() {
                            _selectedUpcoming = val;
                            _mapFocusMode = nextFocus;
                            _remainingTime = val.targetStartTime.difference(
                              DateTime.now(),
                            );
                          });
                          _fetchRoadRoute();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. BẢN ĐỒ & ĐƯỜNG ĐI NHƯ GOOGLE MAPS (OPENSTREETMAP TILES + OSRM ROUTE)
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Thanh tiêu đề bản đồ đường đi
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                color: const Color(0xFF0F172A),
                child: Row(
                  children: [
                    const Icon(
                      Icons.directions_rounded,
                      color: Color(0xFF38BDF8),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasMyGps
                            ? (isInsideRange
                                ? 'Đang trong khu vực lớp học (Cách ${straightDistMeters.round()}m)'
                                : 'Lộ trình từ Vị trí của bạn → Lớp học ($roadDistStr • ~$roadTimeStr)')
                            : 'Đang lấy tọa độ GPS để vẽ đường đi tới lớp...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_loadingRoute)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                  ],
                ),
              ),

              // Thanh chọn góc nhìn bản đồ nhanh (Toàn lộ trình | Tâm Lớp học | Vị trí của bạn)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                color: const Color(0xFFF8FAFC),
                child: Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        selected: _mapFocusMode == 0,
                        visualDensity: VisualDensity.compact,
                        label: const Text(
                          '🛣️ Toàn lộ trình',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onSelected: (_) {
                          final dist =
                              hasMyGps
                                  ? Geolocator.distanceBetween(
                                    _myLat!,
                                    _myLon!,
                                    roomCoords.lat,
                                    roomCoords.lon,
                                  )
                                  : 500.0;
                          setState(() {
                            _mapFocusMode = 0;
                            _mapZoom = _suggestZoomForDistance(dist);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ChoiceChip(
                        selected: _mapFocusMode == 1,
                        visualDensity: VisualDensity.compact,
                        label: const Text(
                          '🏫 Tâm Lớp học',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onSelected: (_) {
                          setState(() {
                            _mapFocusMode = 1;
                            _mapZoom = 16;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ChoiceChip(
                        selected: _mapFocusMode == 2,
                        visualDensity: VisualDensity.compact,
                        label: const Text(
                          '📍 Vị trí của tôi',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onSelected: (_) {
                          setState(() {
                            _mapFocusMode = 2;
                            _mapZoom = 16;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Khung bản đồ đường phố thực tế + đường đi màu xanh kiểu Google Maps
              SizedBox(
                height: 280,
                width: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _GoogleStyleRouteMapWidget(
                        studentLat: _myLat ?? roomCoords.lat,
                        studentLon: _myLon ?? roomCoords.lon,
                        classroomLat: roomCoords.lat,
                        classroomLon: roomCoords.lon,
                        hasStudentGps: hasMyGps,
                        routePolyline: _routePolyline,
                        allowedRadiusMeters: allowedRadius,
                        zoom: _mapZoom,
                        focusMode: _mapFocusMode,
                        classroomLabel:
                            upcoming != null
                                ? upcoming.session.title
                                : 'Lớp học',
                      ),
                    ),

                    // Huy hiệu Quãng đường & Thời gian giống Google Maps
                    if (hasMyGps)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.two_wheeler_rounded,
                                size: 17,
                                color: Color(0xFF2563EB),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$roadDistStr ($roadTimeStr)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Nút phóng to / thu nhỏ bản đồ (+/-)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Column(
                        children: [
                          Material(
                            color: Colors.white.withValues(alpha: 0.92),
                            shape: const CircleBorder(),
                            elevation: 3,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap:
                                  () => setState(
                                    () =>
                                        _mapZoom = (_mapZoom + 1).clamp(5, 18),
                                  ),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.add_rounded, size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Material(
                            color: Colors.white.withValues(alpha: 0.92),
                            shape: const CircleBorder(),
                            elevation: 3,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap:
                                  () => setState(
                                    () =>
                                        _mapZoom = (_mapZoom - 1).clamp(5, 18),
                                  ),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.remove_rounded, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Chi tiết tọa độ Vị trí của bạn & Vị trí lớp học + Nút mở Google Maps
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 11,
                          height: 11,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2563EB),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hasMyGps
                                ? 'Vị trí của bạn: (${_myLat!.toStringAsFixed(6)}, ${_myLon!.toStringAsFixed(6)})'
                                    '${_myAccuracy != null ? " • ±${_myAccuracy!.toStringAsFixed(0)}m" : ""}'
                                : 'Đang xác định vị trí của bạn...',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 11,
                          height: 11,
                          decoration: const BoxDecoration(
                            color: Color(0xFFDC2626),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Vị trí lớp học: ${SmartFeaturesScreen.describeCoordinates(roomCoords.lat, roomCoords.lon)} (${roomCoords.lat.toStringAsFixed(5)}, ${roomCoords.lon.toStringAsFixed(5)})',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _openGoogleMapsDirections,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                      ),
                      icon: const Icon(Icons.map_rounded, size: 19),
                      label: const Text(
                        'Mở chỉ đường trực tiếp trên Google Maps',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. CẬP NHẬT & CHIA SẺ VỊ TRÍ CỦA BẠN
        SectionCard(
          title: 'Cập nhật & Chia sẻ Vị trí của bạn',
          subtitle: _gpsStatusMessage,
          trailing: Switch(
            value: _isLiveSharing,
            onChanged: _toggleLiveSharing,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _loadingGps
                              ? null
                              : () => _fetchRealGpsLocation(silent: false),
                      icon:
                          _loadingGps
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.my_location_rounded, size: 18),
                      label: Text(
                        _loadingGps
                            ? 'Đang lấy GPS...'
                            : 'Cập nhật vị trí hiện tại',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyShareableLocationLink,
                      icon: const Icon(Icons.share_location_rounded, size: 18),
                      label: const Text('Sao chép link vị trí'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // UI TAB 3: DỊCH REALTIME & CHỤP ẢNH DỊCH VĂN BẢN / TÀI LIỆU (ML KIT OCR)
  // ===========================================================================

  Widget _buildTranslatorTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sourceLang,
                    isExpanded: true,
                    items:
                        _langNames.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _sourceLang = v);
                        if (_translateSubMode == 0) {
                          _runRealtimeTranslation(_translateInputCtrl.text);
                        } else {
                          _retranslateOcrExtractedText();
                        }
                      }
                    },
                  ),
                ),
              ),
              IconButton(
                onPressed: _swapLanguages,
                tooltip: 'Đảo chiều ngôn ngữ',
                icon: const Icon(
                  Icons.swap_horiz_rounded,
                  color: Color(0xFF4F46E5),
                ),
              ),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _targetLang,
                    isExpanded: true,
                    items:
                        _langNames.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _targetLang = v);
                        if (_translateSubMode == 0) {
                          _runRealtimeTranslation(_translateInputCtrl.text);
                        } else {
                          _retranslateOcrExtractedText();
                        }
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                selected: _translateSubMode == 0,
                onSelected: (_) => setState(() => _translateSubMode = 0),
                avatar: const Icon(Icons.keyboard_alt_outlined, size: 18),
                label: const Text('Dịch văn bản Realtime'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                selected: _translateSubMode == 1,
                onSelected: (_) => setState(() => _translateSubMode = 1),
                avatar: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Chụp ảnh dịch tài liệu'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_translateSubMode == 0)
          _buildRealtimeTextTranslator()
        else
          _buildCameraPhotoOcrTranslator(),
      ],
    );
  }

  Widget _buildRealtimeTextTranslator() {
    return SectionCard(
      title: 'Dịch thuật văn bản Realtime',
      subtitle: 'Tự động dịch ngay khi bạn đang gõ phím',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _translateInputCtrl,
            maxLines: 3,
            onChanged: _onTranslateTextChanged,
            decoration: InputDecoration(
              labelText: 'Văn bản gốc (${_langNames[_sourceLang]})',
              hintText: 'Nhập nội dung cần dịch...',
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _translateInputCtrl.clear();
                  _runRealtimeTranslation('');
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFC7D2FE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: Color(0xFF4F46E5),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Bản dịch (${_langNames[_targetLang]})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                    if (_isTranslating)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _translatedOutput),
                          );
                          showAppSnackBar(context, 'Đã sao chép bản dịch!');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 17),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  _translatedOutput.isEmpty
                      ? 'Bản dịch sẽ hiển thị tức thì tại đây...'
                      : _translatedOutput,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E1B4B),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPhotoOcrTranslator() {
    return SectionCard(
      title: 'Chụp ảnh & Dịch văn bản / Tài liệu (OCR)',
      subtitle:
          'Chụp ảnh sách vở, tài liệu, bảng giảng đường hoặc chọn ảnh từ máy để tự động nhận diện chữ và dịch',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _ocrProcessing
                          ? null
                          : () =>
                              _captureOrPickImageForOcr(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('Chụp ảnh Camera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _ocrProcessing
                          ? null
                          : () =>
                              _captureOrPickImageForOcr(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('Chọn ảnh Thư viện'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_ocrProcessing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text(
                    'Đang nhận diện chữ viết (OCR) từ ảnh và dịch thuật...',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ],
              ),
            ),

          if (_capturedImagePath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: Image.file(
                  File(_capturedImagePath!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else if (!_ocrProcessing) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.document_scanner_rounded,
                    size: 42,
                    color: Color(0xFF4F46E5),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Nhấn "Chụp ảnh Camera" để chụp văn bản/tài liệu thực tế hoặc "Chọn ảnh Thư viện"',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          TextField(
            controller: _ocrExtractedCtrl,
            maxLines: 4,
            onChanged: (_) => _retranslateOcrExtractedText(),
            decoration: InputDecoration(
              labelText:
                  _ocrDetectedLines.isNotEmpty
                      ? 'Văn bản quét được từ ảnh (${_ocrDetectedLines.length} dòng)'
                      : 'Văn bản nhận diện từ ảnh (OCR)',
              hintText:
                  'Văn bản sau khi chụp ảnh sẽ tự động hiện tại đây...',
              suffixIcon: IconButton(
                tooltip: 'Dịch lại văn bản này',
                icon: const Icon(Icons.translate_rounded),
                onPressed: _retranslateOcrExtractedText,
              ),
            ),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF6EE7B7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 17,
                      color: Color(0xFF059669),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Bản dịch Tài liệu sang ${_langNames[_targetLang]}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: Color(0xFF065F46),
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Sao chép bản dịch',
                      onPressed: () {
                        if (_ocrTranslatedText.trim().isEmpty) return;
                        Clipboard.setData(
                          ClipboardData(text: _ocrTranslatedText),
                        );
                        showAppSnackBar(
                          context,
                          'Đã sao chép bản dịch tài liệu!',
                        );
                      },
                      icon: const Icon(
                        Icons.copy_rounded,
                        size: 17,
                        color: Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  _ocrTranslatedText.isEmpty
                      ? 'Chụp ảnh văn bản/tài liệu để xem bản dịch tại đây...'
                      : _ocrTranslatedText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF064E3B),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// WIDGET BẢN ĐỒ ĐƯỜNG ĐI KIỂU GOOGLE MAPS (OPENSTREETMAP TILES + OSRM ROUTE)
// =============================================================================

class _GoogleStyleRouteMapWidget extends StatelessWidget {
  final double studentLat;
  final double studentLon;
  final double classroomLat;
  final double classroomLon;
  final bool hasStudentGps;
  final List<({double lat, double lon})> routePolyline;
  final double allowedRadiusMeters;
  final int zoom;
  final int focusMode;
  final String classroomLabel;

  const _GoogleStyleRouteMapWidget({
    required this.studentLat,
    required this.studentLon,
    required this.classroomLat,
    required this.classroomLon,
    required this.hasStudentGps,
    required this.routePolyline,
    required this.allowedRadiusMeters,
    required this.zoom,
    this.focusMode = 0,
    required this.classroomLabel,
  });

  static double _lonToWorldX(double lon, int z) {
    final scale = 256.0 * (1 << z);
    return (lon + 180.0) / 360.0 * scale;
  }

  static double _latToWorldY(double lat, int z) {
    final scale = 256.0 * (1 << z);
    final sinLat = math.sin(lat * math.pi / 180.0).clamp(-0.9999, 0.9999);
    return (0.5 -
            math.log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * math.pi)) *
        scale;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final double centerLat;
        final double centerLon;
        if (focusMode == 1 || !hasStudentGps) {
          centerLat = classroomLat;
          centerLon = classroomLon;
        } else if (focusMode == 2) {
          centerLat = studentLat;
          centerLon = studentLon;
        } else {
          centerLat = (studentLat + classroomLat) / 2;
          centerLon = (studentLon + classroomLon) / 2;
        }

        final centerWorldX = _lonToWorldX(centerLon, zoom);
        final centerWorldY = _latToWorldY(centerLat, zoom);
        final viewLeft = centerWorldX - width / 2;
        final viewTop = centerWorldY - height / 2;

        final maxTileIndex = (1 << zoom) - 1;
        final minTx = (viewLeft / 256.0).floor();
        final maxTx = ((viewLeft + width) / 256.0).floor();
        final minTy = (viewTop / 256.0).floor();
        final maxTy = ((viewTop + height) / 256.0).floor();

        final tileWidgets = <Widget>[];
        for (int tx = minTx; tx <= maxTx; tx++) {
          for (int ty = minTy; ty <= maxTy; ty++) {
            if (ty < 0 || ty > maxTileIndex) continue;
            final wrappedTx =
                ((tx % (maxTileIndex + 1)) + (maxTileIndex + 1)) %
                (maxTileIndex + 1);
            final left = tx * 256.0 - viewLeft;
            final top = ty * 256.0 - viewTop;
            tileWidgets.add(
              Positioned(
                left: left,
                top: top,
                width: 256,
                height: 256,
                child: Image.network(
                  'https://tile.openstreetmap.org/$zoom/$wrappedTx/$ty.png',
                  headers: const {
                    'User-Agent': 'Nhom01StudentAttendanceApp/1.0',
                  },
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, _, _) => Container(color: const Color(0xFFE2E8F0)),
                ),
              ),
            );
          }
        }

        Offset toViewportOffset(double lat, double lon) {
          return Offset(
            _lonToWorldX(lon, zoom) - viewLeft,
            _latToWorldY(lat, zoom) - viewTop,
          );
        }

        final studentOffset = toViewportOffset(studentLat, studentLon);
        final classroomOffset = toViewportOffset(classroomLat, classroomLon);
        final routeOffsets =
            routePolyline
                .map((pt) => toViewportOffset(pt.lat, pt.lon))
                .toList();

        // Bán kính mét chuyển sang pixel theo vĩ độ hiện tại
        final metersPerPixel =
            156543.03392 *
            math.cos(centerLat * math.pi / 180.0) /
            (1 << zoom);
        final radiusPx =
            (allowedRadiusMeters /
                    (metersPerPixel <= 0.001 ? 1.0 : metersPerPixel))
                .clamp(16.0, 120.0);

        return Container(
          color: const Color(0xFFE5E7EB),
          child: Stack(
            children: [
              ...tileWidgets,
              Positioned.fill(
                child: CustomPaint(
                  painter: _GoogleRouteOverlayPainter(
                    studentOffset: studentOffset,
                    classroomOffset: classroomOffset,
                    hasStudentGps: hasStudentGps,
                    routeOffsets: routeOffsets,
                    classroomRadiusPx: radiusPx,
                    classroomLabel: classroomLabel,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GoogleRouteOverlayPainter extends CustomPainter {
  final Offset studentOffset;
  final Offset classroomOffset;
  final bool hasStudentGps;
  final List<Offset> routeOffsets;
  final double classroomRadiusPx;
  final String classroomLabel;

  _GoogleRouteOverlayPainter({
    required this.studentOffset,
    required this.classroomOffset,
    required this.hasStudentGps,
    required this.routeOffsets,
    required this.classroomRadiusPx,
    required this.classroomLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Vòng bán kính điểm danh quanh lớp học
    final geofenceFill =
        Paint()
          ..color = const Color(0xFF059669).withValues(alpha: 0.16)
          ..style = PaintingStyle.fill;
    final geofenceStroke =
        Paint()
          ..color = const Color(0xFF059669).withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
    canvas.drawCircle(classroomOffset, classroomRadiusPx, geofenceFill);
    canvas.drawCircle(classroomOffset, classroomRadiusPx, geofenceStroke);

    // 2. Đường đi màu xanh kiểu Google Maps nối từ vị trí của bạn tới Lớp học
    final pts =
        routeOffsets.length >= 2
            ? routeOffsets
            : (hasStudentGps
                ? <Offset>[studentOffset, classroomOffset]
                : <Offset>[]);

    if (pts.length >= 2) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }

      // Viền xanh đậm bên ngoài giống Google Maps
      final casingPaint =
          Paint()
            ..color = const Color(0xFF1E40AF)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 8.0;
      canvas.drawPath(path, casingPaint);

      // Lõi xanh sáng bên trong giống Google Maps
      final routePaint =
          Paint()
            ..color = const Color(0xFF3B82F6)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 5.0;
      canvas.drawPath(path, routePaint);
    }

    // 3. Vẽ ghim đỏ Lớp học
    canvas.drawCircle(
      classroomOffset,
      13,
      Paint()..color = const Color(0xFFDC2626).withValues(alpha: 0.25),
    );
    canvas.drawCircle(
      classroomOffset,
      8.5,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      classroomOffset,
      6.5,
      Paint()..color = const Color(0xFFDC2626),
    );
    _drawBadgeLabel(
      canvas,
      '🏫 $classroomLabel',
      Offset(classroomOffset.dx - 38, classroomOffset.dy - 30),
      const Color(0xFF991B1B),
    );

    // 4. Vẽ chấm xanh GPS "Vị trí của bạn" giống Google Maps
    if (hasStudentGps) {
      canvas.drawCircle(
        studentOffset,
        15,
        Paint()..color = const Color(0xFF2563EB).withValues(alpha: 0.25),
      );
      canvas.drawCircle(
        studentOffset,
        8.5,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        studentOffset,
        6.5,
        Paint()..color = const Color(0xFF2563EB),
      );
      _drawBadgeLabel(
        canvas,
        '📍 Vị trí của bạn',
        Offset(studentOffset.dx - 44, studentOffset.dy + 11),
        const Color(0xFF1E3A8A),
      );
    }
  }

  void _drawBadgeLabel(
    Canvas canvas,
    String text,
    Offset pos,
    Color textColor,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pos.dx - 6, pos.dy - 3, tp.width + 12, tp.height + 6),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = textColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _GoogleRouteOverlayPainter oldDelegate) => true;
}

class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
