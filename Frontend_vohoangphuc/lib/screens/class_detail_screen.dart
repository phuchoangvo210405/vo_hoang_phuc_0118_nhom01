import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../models/api_models.dart';
import '../services/api_client.dart';
import '../utils/stamp_generator.dart';
import '../widgets/common_widgets.dart';
import 'smart_features_screen.dart';

class ClassDetailScreen extends StatefulWidget {
  final ApiClient api;
  final ClassRoomModel classRoom;
  final AuthSession session;
  final List<AppUserModel> allStudentsHint;

  const ClassDetailScreen({
    super.key,
    required this.api,
    required this.classRoom,
    required this.session,
    this.allStudentsHint = const [],
  });

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  List<ClassSessionModel> _sessions = [];
  List<EnrolledStudentModel> _students = [];
  List<LeaveRequestModel> _leaves = [];
  List<AbsenceRowModel> _absenceRows = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.api.getClassSessions(widget.classRoom.id),
        widget.api.getClassStudents(widget.classRoom.id),
        widget.api.getClassLeaveRequests(widget.classRoom.id),
        widget.api.getAbsenceReport(widget.classRoom.id),
      ]);
      if (!mounted) return;
      setState(() {
        _sessions = results[0] as List<ClassSessionModel>;
        _students = results[1] as List<EnrolledStudentModel>;
        _leaves = results[2] as List<LeaveRequestModel>;
        _absenceRows = results[3] as List<AbsenceRowModel>;
      });
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===========================================================================
  // 1. QUẢN LÝ BUỔI HỌC (CREATE / UPDATE / CLOSE / DELETE / QR / ATTENDANCES)
  // ===========================================================================

  static const List<({String id, String label, double lat, double lon})>
  _campusPresets = [
    (
      id: 'q1_hcm',
      label: '🏫 Cơ sở Quận 1 - TP.HCM',
      lat: 10.7769,
      lon: 106.7009,
    ),
    (
      id: 'thuduc_hcm',
      label: '🏢 Khu Công Nghệ Cao (TP. Thủ Đức)',
      lat: 10.8506,
      lon: 106.7719,
    ),
    (
      id: 'binhthanh_hcm',
      label: '🎓 Cơ sở Bình Thạnh - Điện Biên Phủ',
      lat: 10.8018,
      lon: 106.7145,
    ),
    (
      id: 'q7_hcm',
      label: '🏫 Cơ sở Quận 7 - Nguyễn Hữu Thọ',
      lat: 10.7324,
      lon: 106.6992,
    ),
    (
      id: 'caolanh_dt',
      label: '🏛️ Cơ sở Đồng Tháp - TP. Cao Lãnh',
      lat: 10.4594,
      lon: 105.6326,
    ),
    (
      id: 'ninhkieu_ct',
      label: '🏫 Cơ sở Cần Thơ - Ninh Kiều',
      lat: 10.0302,
      lon: 105.7721,
    ),
    (
      id: 'caugiay_hn',
      label: '🏛️ Cơ sở Hà Nội - Cầu Giấy',
      lat: 21.0368,
      lon: 105.7829,
    ),
  ];

  Future<void> _showSessionFormDialog({ClassSessionModel? existing}) async {
    final isEdit = existing != null;
    final isAdmin = widget.session.isAdmin;
    final titleCtrl = TextEditingController(
      text: existing?.title ?? 'Buổi học tuần ${_sessions.length + 1}',
    );
    double selectedLat =
        (existing != null &&
                (existing.latitude != 0 || existing.longitude != 0))
            ? existing.latitude
            : 10.7769;
    double selectedLon =
        (existing != null &&
                (existing.latitude != 0 || existing.longitude != 0))
            ? existing.longitude
            : 106.7009;
    double selectedRadius = existing?.radiusMeters ?? 150;
    DateTime startsAt =
        existing?.startsAt ?? DateTime.now().add(const Duration(hours: 1));

    String selectedPresetId = 'q1_hcm';
    for (final p in _campusPresets) {
      if ((p.lat - selectedLat).abs() < 0.002 &&
          (p.lon - selectedLon).abs() < 0.002) {
        selectedPresetId = p.id;
        break;
      }
    }
    String selectedPlaceLabel = SmartFeaturesScreen.describeCoordinates(
      selectedLat,
      selectedLon,
    );
    int miniMapZoom = 15;
    bool gettingGps = false;
    bool searchingPlace = false;
    final searchPlaceCtrl = TextEditingController();
    List<({String displayName, double lat, double lon})> searchResults = [];

    final saved = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setModalState) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Text(
                    isEdit
                        ? 'Cập nhật buổi học'
                        : (isAdmin
                            ? 'Tạo buổi học mới'
                            : 'Tạo buổi học & Mở điểm danh'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: SizedBox(
                    width: 400,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: titleCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Tiêu đề buổi học',
                              hintText: 'VD: Buổi 1 - Giới thiệu môn học',
                              prefixIcon: Icon(Icons.event_note_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final pickedDate = await showDatePicker(
                                context: ctx,
                                initialDate: startsAt,
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2030),
                              );
                              if (pickedDate == null || !ctx.mounted) return;
                              final pickedTime = await showTimePicker(
                                context: ctx,
                                initialTime: TimeOfDay.fromDateTime(startsAt),
                              );
                              if (pickedTime == null) return;
                              setModalState(() {
                                startsAt = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  pickedTime.hour,
                                  pickedTime.minute,
                                );
                              });
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Thời gian bắt đầu',
                                prefixIcon: Icon(Icons.schedule_rounded),
                              ),
                              child: Text(
                                formatDateTime(startsAt),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // CHỌN VỊ TRÍ ĐƠN GIẢN (KHÔNG CẦN NHẬP KINH ĐỘ / VĨ ĐỘ)
                          const Text(
                            'Chọn vị trí phòng học / địa điểm:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // 1. Dropdown chọn nhanh Cơ sở hoặc Vị trí hiện tại
                          DropdownButtonFormField<String>(
                            initialValue: selectedPresetId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Chọn nhanh Cơ sở / Địa điểm',
                              prefixIcon: Icon(Icons.location_city_rounded),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'gps_current',
                                child: Text(
                                  '📍 Vị trí hiện tại của tôi (GPS)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ..._campusPresets.map(
                                (p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(
                                    p.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const DropdownMenuItem(
                                value: 'custom_map',
                                child: Text(
                                  '🗺️ Điểm đã chọn trên bản đồ / tìm kiếm',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            onChanged: (val) async {
                              if (val == null) return;
                              if (val == 'gps_current') {
                                setModalState(() {
                                  selectedPresetId = val;
                                  gettingGps = true;
                                });
                                try {
                                  var perm = await Geolocator.checkPermission();
                                  if (perm == LocationPermission.denied) {
                                    perm = await Geolocator.requestPermission();
                                  }
                                  final pos =
                                      await Geolocator.getCurrentPosition(
                                        locationSettings:
                                            const LocationSettings(
                                              accuracy: LocationAccuracy.high,
                                            ),
                                      );
                                  setModalState(() {
                                    selectedLat = pos.latitude;
                                    selectedLon = pos.longitude;
                                    selectedPlaceLabel =
                                        'Vị trí GPS hiện tại của tôi';
                                    gettingGps = false;
                                  });
                                } catch (_) {
                                  setModalState(() => gettingGps = false);
                                }
                                return;
                              }
                              for (final p in _campusPresets) {
                                if (p.id == val) {
                                  setModalState(() {
                                    selectedPresetId = val;
                                    selectedLat = p.lat;
                                    selectedLon = p.lon;
                                    selectedPlaceLabel = p.label.replaceFirst(
                                      RegExp(r'^[^\s]+\s'),
                                      '',
                                    );
                                  });
                                  return;
                                }
                              }
                              setModalState(() => selectedPresetId = val);
                            },
                          ),
                          const SizedBox(height: 8),

                          // 2. Tìm kiếm theo tên đường / trường học / địa danh
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: searchPlaceCtrl,
                                  textInputAction: TextInputAction.search,
                                  decoration: const InputDecoration(
                                    hintText:
                                        'Tìm tên đường, trường, quận/huyện...',
                                    prefixIcon: Icon(
                                      Icons.search_rounded,
                                      size: 20,
                                    ),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                  ),
                                  onSubmitted: (_) async {
                                    final q = searchPlaceCtrl.text.trim();
                                    if (q.isEmpty) return;
                                    setModalState(() => searchingPlace = true);
                                    try {
                                      final uri = Uri.parse(
                                        'https://nominatim.openstreetmap.org/search'
                                        '?format=json&limit=4&accept-language=vi'
                                        '&q=${Uri.encodeQueryComponent(q)}',
                                      );
                                      final res = await http
                                          .get(
                                            uri,
                                            headers: const {
                                              'User-Agent':
                                                  'Nhom01AttendanceApp/1.0',
                                            },
                                          )
                                          .timeout(const Duration(seconds: 6));
                                      if (res.statusCode == 200) {
                                        final list = jsonDecode(res.body);
                                        if (list is List) {
                                          final found =
                                              <
                                                ({
                                                  String displayName,
                                                  double lat,
                                                  double lon,
                                                })
                                              >[];
                                          for (final item in list) {
                                            if (item is Map) {
                                              final la = double.tryParse(
                                                item['lat']?.toString() ?? '',
                                              );
                                              final lo = double.tryParse(
                                                item['lon']?.toString() ?? '',
                                              );
                                              final name =
                                                  item['display_name']
                                                      ?.toString() ??
                                                  '';
                                              if (la != null &&
                                                  lo != null &&
                                                  name.isNotEmpty) {
                                                found.add((
                                                  displayName: name,
                                                  lat: la,
                                                  lon: lo,
                                                ));
                                              }
                                            }
                                          }
                                          setModalState(() {
                                            searchResults = found;
                                            if (found.isNotEmpty) {
                                              selectedLat = found.first.lat;
                                              selectedLon = found.first.lon;
                                              selectedPresetId = 'custom_map';
                                              selectedPlaceLabel =
                                                  found.first.displayName
                                                      .split(',')
                                                      .take(2)
                                                      .join(',')
                                                      .trim();
                                            }
                                          });
                                        }
                                      }
                                    } catch (_) {}
                                    setModalState(() => searchingPlace = false);
                                  },
                                ),
                              ),
                              const SizedBox(width: 6),
                              FilledButton.tonal(
                                onPressed:
                                    searchingPlace
                                        ? null
                                        : () async {
                                          final q = searchPlaceCtrl.text.trim();
                                          if (q.isEmpty) return;
                                          setModalState(
                                            () => searchingPlace = true,
                                          );
                                          try {
                                            final uri = Uri.parse(
                                              'https://nominatim.openstreetmap.org/search'
                                              '?format=json&limit=4&accept-language=vi'
                                              '&q=${Uri.encodeQueryComponent(q)}',
                                            );
                                            final res = await http
                                                .get(
                                                  uri,
                                                  headers: const {
                                                    'User-Agent':
                                                        'Nhom01AttendanceApp/1.0',
                                                  },
                                                )
                                                .timeout(
                                                  const Duration(seconds: 6),
                                                );
                                            if (res.statusCode == 200) {
                                              final list = jsonDecode(res.body);
                                              if (list is List) {
                                                final found =
                                                    <
                                                      ({
                                                        String displayName,
                                                        double lat,
                                                        double lon,
                                                      })
                                                    >[];
                                                for (final item in list) {
                                                  if (item is Map) {
                                                    final la = double.tryParse(
                                                      item['lat']?.toString() ??
                                                          '',
                                                    );
                                                    final lo = double.tryParse(
                                                      item['lon']?.toString() ??
                                                          '',
                                                    );
                                                    final name =
                                                        item['display_name']
                                                            ?.toString() ??
                                                        '';
                                                    if (la != null &&
                                                        lo != null &&
                                                        name.isNotEmpty) {
                                                      found.add((
                                                        displayName: name,
                                                        lat: la,
                                                        lon: lo,
                                                      ));
                                                    }
                                                  }
                                                }
                                                setModalState(() {
                                                  searchResults = found;
                                                  if (found.isNotEmpty) {
                                                    selectedLat =
                                                        found.first.lat;
                                                    selectedLon =
                                                        found.first.lon;
                                                    selectedPresetId =
                                                        'custom_map';
                                                    selectedPlaceLabel =
                                                        found.first.displayName
                                                            .split(',')
                                                            .take(2)
                                                            .join(',')
                                                            .trim();
                                                  }
                                                });
                                              }
                                            }
                                          } catch (_) {}
                                          setModalState(
                                            () => searchingPlace = false,
                                          );
                                        },
                                child:
                                    searchingPlace
                                        ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : const Text('Tìm'),
                              ),
                            ],
                          ),
                          if (searchResults.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Column(
                                children:
                                    searchResults
                                        .map(
                                          (r) => InkWell(
                                            onTap: () {
                                              setModalState(() {
                                                selectedLat = r.lat;
                                                selectedLon = r.lon;
                                                selectedPresetId = 'custom_map';
                                                selectedPlaceLabel =
                                                    r.displayName
                                                        .split(',')
                                                        .take(2)
                                                        .join(',')
                                                        .trim();
                                                searchResults = [];
                                              });
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.place_rounded,
                                                    size: 16,
                                                    color: Color(0xFFDC2626),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      r.displayName,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 11.5,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),

                          // 3. Bản đồ nhỏ tương tác: Chạm trực tiếp lên bản đồ để chọn vị trí!
                          Container(
                            height: 165,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFCBD5E1),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: _InteractiveMiniMapPicker(
                                    lat: selectedLat,
                                    lon: selectedLon,
                                    zoom: miniMapZoom,
                                    onTapLocation: (newLat, newLon) {
                                      setModalState(() {
                                        selectedLat = newLat;
                                        selectedLon = newLon;
                                        selectedPresetId = 'custom_map';
                                        selectedPlaceLabel =
                                            'Điểm chọn trên bản đồ (${newLat.toStringAsFixed(4)}, ${newLon.toStringAsFixed(4)})';
                                      });
                                    },
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  right: 44,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF0F172A,
                                      ).withValues(alpha: 0.82),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      gettingGps
                                          ? 'Đang lấy GPS hiện tại...'
                                          : '👆 Chạm lên bản đồ để đổi vị trí: $selectedPlaceLabel',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 6,
                                  bottom: 6,
                                  child: Column(
                                    children: [
                                      Material(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap:
                                              () => setModalState(
                                                () =>
                                                    miniMapZoom =
                                                        (miniMapZoom + 1).clamp(
                                                          6,
                                                          18,
                                                        ),
                                              ),
                                          child: const Padding(
                                            padding: EdgeInsets.all(5),
                                            child: Icon(Icons.add, size: 16),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Material(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap:
                                              () => setModalState(
                                                () =>
                                                    miniMapZoom =
                                                        (miniMapZoom - 1).clamp(
                                                          6,
                                                          18,
                                                        ),
                                              ),
                                          child: const Padding(
                                            padding: EdgeInsets.all(5),
                                            child: Icon(Icons.remove, size: 16),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 4. Chọn nhanh bán kính cho phép điểm danh
                          const Text(
                            'Phạm vi bán kính lớp học:',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children:
                                [50.0, 100.0, 150.0, 200.0, 500.0].map((r) {
                                  final isSelected =
                                      (selectedRadius - r).abs() < 1;
                                  return ChoiceChip(
                                    label: Text('${r.toInt()}m'),
                                    selected: isSelected,
                                    visualDensity: VisualDensity.compact,
                                    onSelected:
                                        (_) => setModalState(
                                          () => selectedRadius = r,
                                        ),
                                  );
                                }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Huỷ'),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: Text(isEdit ? 'Cập nhật' : 'Tạo buổi học'),
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
          ),
    );

    if (saved != true) return;
    final title = titleCtrl.text.trim();
    final lat = double.parse(selectedLat.toStringAsFixed(6));
    final lon = double.parse(selectedLon.toStringAsFixed(6));
    final radius = selectedRadius;

    if (title.isEmpty || radius <= 0) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Vui lòng nhập tiêu đề buổi học hợp lệ.',
        isError: true,
      );
      return;
    }

    try {
      SmartFeaturesScreen.registerPlaceLabel(lat, lon, selectedPlaceLabel);
      if (isEdit) {
        await widget.api.updateSession(
          existing.id,
          title: title,
          startsAt: startsAt,
          latitude: lat,
          longitude: lon,
          radiusMeters: radius,
        );
        if (!mounted) return;
        showAppSnackBar(context, 'Đã cập nhật buổi học "$title".');
      } else {
        await widget.api.createSession(
          widget.classRoom.id,
          title: title,
          startsAt: startsAt,
          latitude: lat,
          longitude: lon,
          radiusMeters: radius,
        );
        if (!mounted) return;
        showAppSnackBar(
          context,
          isAdmin
              ? 'Đã tạo buổi học "$title" tại $selectedPlaceLabel!'
              : 'Đã tạo buổi học "$title" và sinh mã QR điểm danh!',
        );
      }
      await _loadAll();
      int? targetId = existing?.id;
      if (targetId == null && _sessions.isNotEmpty) {
        targetId =
            _sessions.map((e) => e.id).reduce((a, b) => a > b ? a : b);
      }
      SmartFeaturesScreen.notifySessionsChanged(
        preferredId: targetId,
        lat: lat,
        lon: lon,
        placeName: selectedPlaceLabel,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  Future<void> _handleCloseSession(ClassSessionModel s) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Đóng điểm danh buổi học',
      message:
          'Bạn có chắc muốn đóng điểm danh cho "${s.title}"? Sau khi đóng, các sinh viên vắng không phép sẽ được tính vào báo cáo chuyên cần.',
      confirmLabel: 'Đóng điểm danh',
      confirmColor: const Color(0xFFD97706),
    );
    if (!ok) return;
    try {
      await widget.api.closeSession(s.id);
      if (!mounted) return;
      showAppSnackBar(context, 'Đã đóng điểm danh buổi "${s.title}".');
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  Future<void> _handleDeleteSession(ClassSessionModel s) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Xoá buổi học',
      message: 'Bạn có chắc chắn muốn xoá buổi học "${s.title}"?',
      confirmLabel: 'Xoá buổi học',
    );
    if (!ok) return;
    try {
      await widget.api.deleteSession(s.id);
      if (SmartFeaturesScreen.preferredSessionId == s.id) {
        SmartFeaturesScreen.preferredSessionId = null;
      }
      if (!mounted) return;
      showAppSnackBar(context, 'Đã xoá buổi học "${s.title}".');
      await _loadAll();
      SmartFeaturesScreen.notifySessionsChanged();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  Future<void> _showQrDialog(ClassSessionModel s) async {
    final token = s.qrToken ?? '';
    await showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Column(
              children: [
                const Text(
                  'MÃ QR ĐIỂM DANH BUỔI HỌC',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrMatrixPreview(token: token, size: 180),
                const SizedBox(height: 16),
                const Text(
                  'Mã QR Token (Sinh viên dùng để Check-in):',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: SelectableText(
                    token,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Toạ độ tâm lớp: (${s.latitude}, ${s.longitude}) • Bán kính: ${s.radiusMeters.toStringAsFixed(0)}m',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: token));
                  showAppSnackBar(
                    context,
                    'Đã sao chép mã QR Token vào bộ nhớ tạm!',
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Sao chép mã'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
            ],
          ),
    );
  }

  Future<void> _showSessionAttendancesSheet(ClassSessionModel s) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          minChildSize: 0.45,
          builder: (context, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.how_to_reg_rounded,
                        color: Color(0xFF4F46E5),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Danh sách điểm danh: ${s.title}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: FutureBuilder<List<AttendanceModel>>(
                      future: widget.api.getSessionAttendances(s.id),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snap.hasError) {
                          return Center(
                            child: Text('Lỗi tải điểm danh: ${snap.error}'),
                          );
                        }
                        final list = snap.data ?? [];
                        if (list.isEmpty) {
                          return const EmptyStateView(
                            icon: Icons.person_off_outlined,
                            title: 'Chưa có sinh viên điểm danh',
                            subtitle:
                                'Hãy mở mã QR của buổi học để sinh viên quét và gửi điểm danh.',
                          );
                        }
                        return ListView.separated(
                          controller: scrollCtrl,
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final a = list[idx];
                            return Card(
                              elevation: 0,
                              color: const Color(0xFFF8FAFC),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(
                                    0xFF059669,
                                  ).withValues(alpha: 0.14),
                                  child: const Icon(
                                    Icons.check_rounded,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                                title: Text(
                                  '${a.fullName} (${a.username})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  'Lúc: ${formatDateTime(a.checkedInAt)} • Cách tâm lớp: ${a.distanceMeters.toStringAsFixed(1)}m',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                                trailing:
                                    a.hasPhoto
                                        ? OutlinedButton.icon(
                                          onPressed:
                                              () => showRemoteImageDialog(
                                                context,
                                                title:
                                                    'Ảnh điểm danh - ${a.fullName}',
                                                loader:
                                                    () => widget.api
                                                        .getAttendancePhoto(
                                                          a.id,
                                                        ),
                                              ),
                                          icon: const Icon(
                                            Icons.photo_camera_outlined,
                                            size: 16,
                                          ),
                                          label: const Text('Ảnh'),
                                        )
                                        : const Text(
                                          'Không đính kèm ảnh',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // 2. QUẢN LÝ SINH VIÊN TRONG LỚP (ENROLL / UNENROLL)
  // ===========================================================================

  Future<void> _showEnrollStudentDialog() async {
    final enrolledIds = _students.map((e) => e.studentId).toSet();
    final candidates =
        widget.allStudentsHint
            .where(
              (u) =>
                  RoleHelper.normalize(u.role) == RoleHelper.student &&
                  !enrolledIds.contains(u.id),
            )
            .toList();

    int? selectedId = candidates.isNotEmpty ? candidates.first.id : null;
    final manualIdCtrl = TextEditingController(
      text: selectedId != null ? selectedId.toString() : '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setModalState) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: const Text(
                    'Thêm Sinh viên vào lớp',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (candidates.isNotEmpty) ...[
                        DropdownButtonFormField<int>(
                          initialValue: selectedId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Chọn nhanh Sinh viên',
                            prefixIcon: Icon(Icons.school_outlined),
                          ),
                          items:
                              candidates
                                  .map(
                                    (u) => DropdownMenuItem(
                                      value: u.id,
                                      child: Text(
                                        '[ID: ${u.id}] ${u.fullName} (${u.username})',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) {
                            setModalState(() {
                              selectedId = v;
                              if (v != null) manualIdCtrl.text = v.toString();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: manualIdCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Mã ID Sinh viên (StudentId)',
                          hintText: 'Nhập ID tài khoản sinh viên (VD: 3)',
                          prefixIcon: Icon(Icons.numbers_rounded),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Huỷ'),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Thêm vào lớp'),
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
          ),
    );

    if (ok != true) return;
    final studentId = int.tryParse(manualIdCtrl.text.trim());
    if (studentId == null || studentId <= 0) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Vui lòng nhập ID sinh viên hợp lệ.',
        isError: true,
      );
      return;
    }

    try {
      await widget.api.enrollStudent(widget.classRoom.id, studentId);
      if (!mounted) return;
      showAppSnackBar(context, 'Đã thêm sinh viên (ID: $studentId) vào lớp.');
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  Future<void> _handleUnenrollStudent(EnrolledStudentModel st) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Xoá sinh viên khỏi lớp',
      message:
          'Bạn có chắc muốn xoá sinh viên "${st.fullName}" (${st.username}) khỏi lớp ${widget.classRoom.name}?',
      confirmLabel: 'Xoá khỏi lớp',
    );
    if (!ok) return;
    try {
      await widget.api.unenrollStudent(widget.classRoom.id, st.studentId);
      if (!mounted) return;
      showAppSnackBar(context, 'Đã xoá ${st.fullName} khỏi lớp.');
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  // ===========================================================================
  // 3. DUYỆT ĐƠN XIN NGHỈ (APPROVE / REJECT)
  // ===========================================================================

  Future<void> _handleReviewLeave(LeaveRequestModel leave, bool approve) async {
    try {
      await widget.api.reviewLeaveRequest(leave.id, approve: approve);
      if (!mounted) return;
      showAppSnackBar(
        context,
        approve
            ? 'Đã DUYỆT đơn xin nghỉ của ${leave.studentName ?? "sinh viên"}.'
            : 'Đã TỪ CHỐI đơn xin nghỉ của ${leave.studentName ?? "sinh viên"}.',
      );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  // ===========================================================================
  // 4. GỬI EMAIL CẢNH BÁO VẮNG HỌC
  // ===========================================================================

  Future<void> _handleSendWarnings() async {
    try {
      final sent = await widget.api.sendAbsenceWarnings(widget.classRoom.id);
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Đã gửi email cảnh báo học vụ cho $sent sinh viên vắng quá ngưỡng!',
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingLeavesCount =
        _leaves
            .where(
              (l) =>
                  LeaveStatusHelper.normalize(l.status) ==
                  LeaveStatusHelper.pending,
            )
            .length;
    final warnedCount = _absenceRows.where((r) => r.isWarned).length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.classRoom.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              'Môn: ${widget.classRoom.subjectName} • GV: ${widget.classRoom.teacherName}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadAll,
            tooltip: 'Làm mới dữ liệu',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amberAccent,
          indicatorWeight: 3,
          tabs: [
            Tab(
              icon: Icon(
                widget.session.isAdmin
                    ? Icons.event_note_rounded
                    : Icons.qr_code_2_rounded,
                size: 20,
              ),
              text: 'Buổi học (${_sessions.length})',
            ),
            Tab(
              icon: const Icon(Icons.groups_rounded, size: 20),
              text: 'Sinh viên (${_students.length})',
            ),
            Tab(
              icon: const Icon(Icons.fact_check_rounded, size: 20),
              text:
                  pendingLeavesCount > 0
                      ? 'Đơn nghỉ ($pendingLeavesCount chờ)'
                      : 'Đơn nghỉ (${_leaves.length})',
            ),
            Tab(
              icon: const Icon(Icons.warning_amber_rounded, size: 20),
              text:
                  warnedCount > 0
                      ? 'Báo cáo vắng ($warnedCount CB)'
                      : 'Báo cáo vắng',
            ),
          ],
        ),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                controller: _tabController,
                children: [
                  _buildSessionsTab(),
                  _buildStudentsTab(),
                  _buildLeaveRequestsTab(),
                  _buildAbsenceReportTab(),
                ],
              ),
    );
  }

  Widget _buildSessionsTab() {
    final isAdmin = widget.session.isAdmin;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSessionFormDialog(),
        icon: Icon(
          isAdmin ? Icons.add_circle_outline_rounded : Icons.add_task_rounded,
        ),
        label: Text(isAdmin ? 'Tạo buổi học' : 'Tạo buổi học & Mở QR'),
      ),
      body:
          _sessions.isEmpty
              ? EmptyStateView(
                icon:
                    isAdmin
                        ? Icons.event_note_rounded
                        : Icons.qr_code_scanner_rounded,
                title: 'Chưa có buổi học nào',
                subtitle:
                    isAdmin
                        ? 'Nhấn "Tạo buổi học" để lên lịch buổi học và chọn vị trí phòng học.'
                        : 'Nhấn "Tạo buổi học & Mở QR" để tạo phiên điểm danh GPS + QR cho lớp học.',
                action: FilledButton.icon(
                  onPressed: () => _showSessionFormDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Tạo buổi học đầu tiên'),
                ),
              )
              : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: _sessions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final s = _sessions[index];
                  final placeDesc = SmartFeaturesScreen.describeCoordinates(
                    s.latitude,
                    s.longitude,
                  );
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color:
                            (!isAdmin && s.isOpen)
                                ? const Color(0xFF059669).withValues(alpha: 0.4)
                                : const Color(0xFFE2E8F0),
                        width: (!isAdmin && s.isOpen) ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isAdmin)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.event_available_rounded,
                                      size: 14,
                                      color: Color(0xFF4F46E5),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Buổi học đã lên lịch',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF4F46E5),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      s.isOpen
                                          ? const Color(0xFFECFDF5)
                                          : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      s.isOpen
                                          ? Icons.radio_button_checked
                                          : Icons.lock_outline,
                                      size: 14,
                                      color:
                                          s.isOpen
                                              ? const Color(0xFF059669)
                                              : const Color(0xFF64748B),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      s.isOpen
                                          ? 'Đang mở điểm danh'
                                          : 'Đã đóng điểm danh',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            s.isOpen
                                                ? const Color(0xFF059669)
                                                : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const Spacer(),
                            IconButton(
                              onPressed:
                                  () => _showSessionFormDialog(existing: s),
                              tooltip: 'Sửa buổi học',
                              icon: const Icon(Icons.edit_outlined, size: 20),
                            ),
                            IconButton(
                              onPressed: () => _handleDeleteSession(s),
                              tooltip: 'Xoá buổi học',
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s.title,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 15,
                              color: Color(0xFF64748B),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Bắt đầu: ${formatDateTime(s.startsAt)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 15,
                              color: Color(0xFF64748B),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Địa điểm: $placeDesc • Bán kính: ${s.radiusMeters.toStringAsFixed(0)}m',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (!isAdmin &&
                                s.qrToken != null &&
                                s.qrToken!.isNotEmpty)
                              FilledButton.tonalIcon(
                                onPressed: () => _showQrDialog(s),
                                icon: const Icon(
                                  Icons.qr_code_rounded,
                                  size: 18,
                                ),
                                label: const Text('Mã QR Điểm danh'),
                              ),
                            OutlinedButton.icon(
                              onPressed: () => _showSessionAttendancesSheet(s),
                              icon: const Icon(
                                Icons.fact_check_outlined,
                                size: 18,
                              ),
                              label: const Text('DS đã điểm danh'),
                            ),
                            if (!isAdmin && s.isOpen)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFD97706),
                                ),
                                onPressed: () => _handleCloseSession(s),
                                icon: const Icon(
                                  Icons.lock_clock_outlined,
                                  size: 18,
                                ),
                                label: const Text('Đóng điểm danh'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
    );
  }

  Widget _buildStudentsTab() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showEnrollStudentDialog,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Thêm SV vào lớp'),
      ),
      body:
          _students.isEmpty
              ? EmptyStateView(
                icon: Icons.group_add_outlined,
                title: 'Chưa có sinh viên trong lớp',
                subtitle:
                    'Hãy thêm sinh viên vào lớp học để sinh viên có thể xem lịch học, điểm danh và gửi đơn xin nghỉ.',
                action: FilledButton.icon(
                  onPressed: _showEnrollStudentDialog,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Thêm sinh viên ngay'),
                ),
              )
              : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: _students.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final st = _students[index];
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFEEF2FF),
                        child: Text(
                          st.fullName.isNotEmpty
                              ? st.fullName[0].toUpperCase()
                              : 'S',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                      ),
                      title: Text(
                        st.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'ID: ${st.studentId} • @${st.username} • ${st.email}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      trailing: IconButton(
                        onPressed: () => _handleUnenrollStudent(st),
                        tooltip: 'Xoá khỏi lớp',
                        icon: const Icon(
                          Icons.person_remove_outlined,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  );
                },
              ),
    );
  }

  Widget _buildLeaveRequestsTab() {
    if (_leaves.isEmpty) {
      return const EmptyStateView(
        icon: Icons.inbox_outlined,
        title: 'Chưa có đơn xin nghỉ nào',
        subtitle: 'Các đơn xin phép nghỉ học của sinh viên sẽ hiển thị tại đây.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _leaves.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final l = _leaves[index];
        final statusColor = LeaveStatusHelper.color(l.status);
        final isPending =
            LeaveStatusHelper.normalize(l.status) == LeaveStatusHelper.pending;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.studentName ?? 'Sinh viên #${l.studentId}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      LeaveStatusHelper.label(l.status),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Buổi học: ${l.sessionTitle}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Lý do xin nghỉ: ${l.reason}',
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 4),
              Text(
                'Gửi lúc: ${formatDateTime(l.createdAt)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (l.hasEvidence)
                    OutlinedButton.icon(
                      onPressed:
                          () => showRemoteImageDialog(
                            context,
                            title:
                                'Minh chứng đơn nghỉ - ${l.studentName ?? ""}',
                            loader: () => widget.api.getLeaveEvidence(l.id),
                          ),
                      icon: const Icon(Icons.attachment_rounded, size: 18),
                      label: const Text('Xem minh chứng'),
                    ),
                  if (isPending) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                      ),
                      onPressed: () => _handleReviewLeave(l, true),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Duyệt đơn'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                      ),
                      onPressed: () => _handleReviewLeave(l, false),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Từ chối'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAbsenceReportTab() {
    final warnedCount = _absenceRows.where((r) => r.isWarned).length;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:
                warnedCount > 0
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  warnedCount > 0
                      ? const Color(0xFFFECACA)
                      : const Color(0xFFC7D2FE),
            ),
          ),
          child: Row(
            children: [
              Icon(
                warnedCount > 0
                    ? Icons.warning_amber_rounded
                    : Icons.verified_outlined,
                color:
                    warnedCount > 0
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF4F46E5),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  warnedCount > 0
                      ? 'Có $warnedCount sinh viên vắng vượt ngưỡng cảnh báo (≥ 20% số buổi đã đóng).'
                      : 'Tất cả sinh viên trong lớp hiện đều đảm bảo tỷ lệ chuyên cần.',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (warnedCount > 0)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                  ),
                  onPressed: _handleSendWarnings,
                  icon: const Icon(Icons.outgoing_mail, size: 18),
                  label: const Text('Gửi cảnh báo'),
                ),
            ],
          ),
        ),
        Expanded(
          child:
              _absenceRows.isEmpty
                  ? const EmptyStateView(
                    icon: Icons.analytics_outlined,
                    title: 'Chưa có dữ liệu báo cáo',
                    subtitle:
                        'Hãy thêm sinh viên vào lớp và đóng các buổi học để thống kê tỷ lệ chuyên cần.',
                  )
                  : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _absenceRows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final r = _absenceRows[index];
                      final pct = (r.absentRate * 100).toStringAsFixed(0);
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color:
                                r.isWarned
                                    ? const Color(0xFFFCA5A5)
                                    : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                r.isWarned
                                    ? const Color(0xFFFEE2E2)
                                    : const Color(0xFFECFDF5),
                            child: Text(
                              '$pct%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color:
                                    r.isWarned
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFF059669),
                              ),
                            ),
                          ),
                          title: Text(
                            '${r.fullName} (${r.username})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Email: ${r.email}\nSố buổi vắng không phép: ${r.absentSessions}/${r.totalSessions} buổi đã đóng',
                          ),
                          isThreeLine: true,
                          trailing:
                              r.isWarned
                                  ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Cảnh báo',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                  )
                                    : const Text(
                                      'Đạt',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF059669),
                                      ),
                                    ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      );
    }
}

class _InteractiveMiniMapPicker extends StatelessWidget {
  final double lat;
  final double lon;
  final int zoom;
  final void Function(double newLat, double newLon) onTapLocation;

  const _InteractiveMiniMapPicker({
    required this.lat,
    required this.lon,
    required this.zoom,
    required this.onTapLocation,
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

  static double _worldXToLon(double worldX, int z) {
    final scale = 256.0 * (1 << z);
    return (worldX / scale) * 360.0 - 180.0;
  }

  static double _worldYToLat(double worldY, int z) {
    final scale = 256.0 * (1 << z);
    final n = math.pi - 2.0 * math.pi * worldY / scale;
    final sinhN = 0.5 * (math.exp(n) - math.exp(-n));
    return 180.0 / math.pi * math.atan(sinhN);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final centerWorldX = _lonToWorldX(lon, zoom);
        final centerWorldY = _latToWorldY(lat, zoom);
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

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final local = details.localPosition;
            final tappedWorldX = viewLeft + local.dx;
            final tappedWorldY = viewTop + local.dy;
            final newLat = _worldYToLat(tappedWorldY, zoom).clamp(-85.0, 85.0);
            final newLon = _worldXToLon(
              tappedWorldX,
              zoom,
            ).clamp(-180.0, 180.0);
            onTapLocation(newLat, newLon);
          },
          child: Container(
            color: const Color(0xFFE2E8F0),
            child: Stack(
              children: [
                ...tileWidgets,
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '🏫 Vị trí lớp',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFFDC2626),
                        size: 30,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
