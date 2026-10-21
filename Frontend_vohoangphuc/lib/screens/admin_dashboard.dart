import 'package:flutter/material.dart';
import '../models/api_models.dart';
import '../services/api_client.dart';
import '../widgets/common_widgets.dart';
import 'class_detail_screen.dart';
import 'smart_features_screen.dart';

class AdminDashboard extends StatefulWidget {
  final ApiClient api;
  final AuthSession session;
  final VoidCallback onLogout;

  const AdminDashboard({
    super.key,
    required this.api,
    required this.session,
    required this.onLogout,
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  bool _loading = true;

  List<AppUserModel> _users = [];
  List<SubjectModel> _subjects = [];
  List<ClassRoomModel> _classes = [];

  String _classSearch = '';
  String _subjectSearch = '';
  String _userSearch = '';
  String _userRoleFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.api.getUsers(),
        widget.api.getSubjects(),
        widget.api.getClasses(),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<AppUserModel>;
        _subjects = results[1] as List<SubjectModel>;
        _classes = results[2] as List<ClassRoomModel>;
      });
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AppUserModel> get _teachers =>
      _users
          .where((u) => RoleHelper.normalize(u.role) == RoleHelper.teacher)
          .toList();

  List<AppUserModel> get _students =>
      _users
          .where((u) => RoleHelper.normalize(u.role) == RoleHelper.student)
          .toList();

  // ===========================================================================
  // CRUD MÔN HỌC (/api/subjects)
  // ===========================================================================

  Future<void> _showSubjectDialog({SubjectModel? existing}) async {
    final isEdit = existing != null;
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final nameCtrl = TextEditingController(text: existing?.name ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              isEdit ? 'Cập nhật môn học' : 'Thêm môn học mới',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Mã môn học (Code)',
                    hintText: 'VD: COMP101, LTDDC4...',
                    prefixIcon: Icon(Icons.qr_code_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên môn học',
                    hintText: 'VD: Lập trình thiết bị di động',
                    prefixIcon: Icon(Icons.menu_book_rounded),
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
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text(isEdit ? 'Lưu thay đổi' : 'Thêm môn học'),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
    );

    if (ok != true) return;
    final code = codeCtrl.text.trim();
    final name = nameCtrl.text.trim();
    if (code.isEmpty || name.isEmpty) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Vui lòng nhập đầy đủ Mã môn học và Tên môn học.',
        isError: true,
      );
      return;
    }

    try {
      if (isEdit) {
        await widget.api.updateSubject(existing.id, code: code, name: name);
        if (!mounted) return;
        showAppSnackBar(context, 'Đã cập nhật môn học "$name".');
      } else {
        await widget.api.createSubject(code: code, name: name);
        if (!mounted) return;
        showAppSnackBar(context, 'Đã thêm môn học "$name" ($code).');
      }
      await _loadAllData();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  Future<void> _handleDeleteSubject(SubjectModel s) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Xoá môn học',
      message: 'Bạn có chắc muốn xoá môn học "${s.name}" (${s.code})?',
      confirmLabel: 'Xoá môn học',
    );
    if (!ok) return;
    try {
      await widget.api.deleteSubject(s.id);
      if (!mounted) return;
      showAppSnackBar(context, 'Đã xoá môn học "${s.name}".');
      await _loadAllData();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  // ===========================================================================
  // CRUD LỚP HỌC (/api/classes)
  // ===========================================================================

  Future<void> _showClassDialog({ClassRoomModel? existing}) async {
    if (_subjects.isEmpty) {
      showAppSnackBar(
        context,
        'Chưa có môn học nào! Hãy tạo ít nhất 1 Môn học trước khi mở lớp.',
        isError: true,
      );
      setState(() => _currentIndex = 2);
      return;
    }
    if (_teachers.isEmpty) {
      showAppSnackBar(
        context,
        'Chưa có tài khoản Giảng viên nào! Hãy tạo tài khoản Giảng viên trước.',
        isError: true,
      );
      setState(() => _currentIndex = 3);
      return;
    }

    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    int selectedSubjectId =
        existing != null && _subjects.any((s) => s.id == existing.subjectId)
            ? existing.subjectId
            : _subjects.first.id;
    int selectedTeacherId =
        existing != null && _teachers.any((t) => t.id == existing.teacherId)
            ? existing.teacherId
            : _teachers.first.id;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setModalState) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Text(
                    isEdit ? 'Cập nhật lớp học' : 'Tạo lớp học mới',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Tên lớp học',
                            hintText: 'VD: Lập trình Di động - Nhóm 01',
                            prefixIcon: Icon(Icons.class_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: selectedSubjectId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Thuộc môn học',
                            prefixIcon: Icon(Icons.menu_book_outlined),
                          ),
                          items:
                              _subjects
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s.id,
                                      child: Text(
                                        '${s.code} - ${s.name}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setModalState(() => selectedSubjectId = v);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: selectedTeacherId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Giảng viên phụ trách',
                            prefixIcon: Icon(Icons.co_present_outlined),
                          ),
                          items:
                              _teachers
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t.id,
                                      child: Text(
                                        '${t.fullName} (@${t.username})',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setModalState(() => selectedTeacherId = v);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Huỷ'),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: Text(isEdit ? 'Lưu thay đổi' : 'Tạo lớp học'),
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
          ),
    );

    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      showAppSnackBar(context, 'Vui lòng nhập tên lớp học.', isError: true);
      return;
    }

    try {
      if (isEdit) {
        await widget.api.updateClass(
          existing.id,
          name: name,
          subjectId: selectedSubjectId,
          teacherId: selectedTeacherId,
        );
        if (!mounted) return;
        showAppSnackBar(context, 'Đã cập nhật lớp "$name".');
      } else {
        await widget.api.createClass(
          name: name,
          subjectId: selectedSubjectId,
          teacherId: selectedTeacherId,
        );
        if (!mounted) return;
        showAppSnackBar(context, 'Đã tạo lớp học "$name".');
      }
      await _loadAllData();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  Future<void> _handleDeleteClass(ClassRoomModel c) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Xoá lớp học',
      message: 'Bạn có chắc chắn muốn xoá lớp "${c.name}"?',
      confirmLabel: 'Xoá lớp',
    );
    if (!ok) return;
    try {
      await widget.api.deleteClass(c.id);
      if (!mounted) return;
      showAppSnackBar(context, 'Đã xoá lớp học "${c.name}".');
      await _loadAllData();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  // ===========================================================================
  // CRUD NGƯỜI DÙNG (/api/users)
  // ===========================================================================

  Future<void> _showCreateUserDialog() async {
    final usernameCtrl = TextEditingController();
    final fullNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String role = RoleHelper.student;

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
                    'Thêm tài khoản người dùng mới',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: fullNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Họ và tên',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: usernameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Tên đăng nhập (Username)',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: role,
                          decoration: const InputDecoration(
                            labelText: 'Phân quyền vai trò',
                            prefixIcon: Icon(Icons.security_rounded),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: RoleHelper.student,
                              child: Text('Sinh viên (Khách hàng)'),
                            ),
                            DropdownMenuItem(
                              value: RoleHelper.teacher,
                              child: Text('Giảng viên (Nhân viên)'),
                            ),
                            DropdownMenuItem(
                              value: RoleHelper.admin,
                              child: Text('Quản trị viên (Admin)'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setModalState(() => role = v);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: passwordCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Mật khẩu khởi tạo (≥ 6 ký tự)',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Huỷ'),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Tạo tài khoản'),
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
          ),
    );

    if (ok != true) return;
    if (usernameCtrl.text.trim().isEmpty ||
        fullNameCtrl.text.trim().isEmpty ||
        emailCtrl.text.trim().isEmpty ||
        passwordCtrl.text.length < 6) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Vui lòng điền đủ thông tin và mật khẩu tối thiểu 6 ký tự.',
        isError: true,
      );
      return;
    }

    try {
      await widget.api.createUser(
        username: usernameCtrl.text,
        email: emailCtrl.text,
        password: passwordCtrl.text,
        fullName: fullNameCtrl.text,
        role: role,
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Đã tạo tài khoản "${usernameCtrl.text.trim()}" thành công.',
      );
      await _loadAllData();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  Future<void> _showUpdateUserDialog(AppUserModel u) async {
    final fullNameCtrl = TextEditingController(text: u.fullName);
    final emailCtrl = TextEditingController(text: u.email);
    String role = RoleHelper.normalize(u.role);
    bool isActive = u.isActive;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setModalState) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Text(
                    'Cập nhật tài khoản @${u.username}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: fullNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Họ và tên',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: role,
                          decoration: const InputDecoration(
                            labelText: 'Phân quyền vai trò',
                            prefixIcon: Icon(Icons.security_rounded),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: RoleHelper.student,
                              child: Text('Sinh viên (Khách hàng)'),
                            ),
                            DropdownMenuItem(
                              value: RoleHelper.teacher,
                              child: Text('Giảng viên (Nhân viên)'),
                            ),
                            DropdownMenuItem(
                              value: RoleHelper.admin,
                              child: Text('Quản trị viên (Admin)'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setModalState(() => role = v);
                          },
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Trạng thái kích hoạt',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            isActive
                                ? 'Đang hoạt động (Cho phép đăng nhập)'
                                : 'Đang khoá / Chưa xác thực OTP',
                            style: const TextStyle(fontSize: 12),
                          ),
                          value: isActive,
                          onChanged: (v) => setModalState(() => isActive = v),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Huỷ'),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Lưu cập nhật'),
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
          ),
    );

    if (ok != true) return;
    try {
      await widget.api.updateUser(
        u.id,
        email: emailCtrl.text,
        fullName: fullNameCtrl.text,
        role: role,
        isActive: isActive,
      );
      if (!mounted) return;
      showAppSnackBar(context, 'Đã cập nhật người dùng @${u.username}.');
      await _loadAllData();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  Future<void> _handleDeleteUser(AppUserModel u) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Xoá tài khoản',
      message:
          'Bạn có chắc muốn xoá tài khoản "${u.fullName}" (@${u.username})?',
      confirmLabel: 'Xoá tài khoản',
    );
    if (!ok) return;
    try {
      await widget.api.deleteUser(u.id);
      if (!mounted) return;
      showAppSnackBar(context, 'Đã xoá người dùng @${u.username}.');
      await _loadAllData();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    }
  }

  void _openClassDetail(ClassRoomModel c) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ClassDetailScreen(
              api: widget.api,
              classRoom: c,
              session: widget.session,
              allStudentsHint: _students,
            ),
      ),
    ).then((_) => _loadAllData());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TRANG QUẢN TRỊ (ADMIN)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              'Xin chào, ${widget.session.fullName} (@${widget.session.username})',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => showServerConfigDialog(context, widget.api),
            tooltip: 'Cấu hình máy chủ API',
            icon: const Icon(Icons.dns_rounded),
          ),
          IconButton(
            onPressed: _loadAllData,
            tooltip: 'Tải lại dữ liệu',
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: widget.onLogout,
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : IndexedStack(
                index: _currentIndex,
                children: [
                  _buildOverviewTab(),
                  _buildClassesTab(),
                  _buildSubjectsTab(),
                  _buildUsersTab(),
                  SmartFeaturesScreen(
                    api: widget.api,
                    session: widget.session,
                  ),
                ],
              ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) {
          setState(() => _currentIndex = idx);
          if (idx == 4) {
            SmartFeaturesScreen.notifySessionsChanged();
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Tổng quan',
          ),
          NavigationDestination(
            icon: Badge(
              label: Text('${_classes.length}'),
              child: const Icon(Icons.class_outlined),
            ),
            selectedIcon: Badge(
              label: Text('${_classes.length}'),
              child: const Icon(Icons.class_rounded),
            ),
            label: 'Lớp học',
          ),
          NavigationDestination(
            icon: Badge(
              label: Text('${_subjects.length}'),
              child: const Icon(Icons.menu_book_outlined),
            ),
            selectedIcon: Badge(
              label: Text('${_subjects.length}'),
              child: const Icon(Icons.menu_book_rounded),
            ),
            label: 'Môn học',
          ),
          NavigationDestination(
            icon: Badge(
              label: Text('${_users.length}'),
              child: const Icon(Icons.people_alt_outlined),
            ),
            selectedIcon: Badge(
              label: Text('${_users.length}'),
              child: const Icon(Icons.people_alt_rounded),
            ),
            label: 'Người dùng',
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'Tiện ích',
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Admin Hero Banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 38,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bảng điều khiển Quản trị viên',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Toàn quyền quản lý CRUD Người dùng, Môn học, Lớp học, Buổi điểm danh & Báo cáo học vụ.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Metrics Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.9,
            children: [
              StatMetricCard(
                label: 'Tổng tài khoản',
                value: '${_users.length}',
                icon: Icons.people_alt_rounded,
                color: const Color(0xFF4F46E5),
              ),
              StatMetricCard(
                label: 'Lớp học đang mở',
                value: '${_classes.length}',
                icon: Icons.class_rounded,
                color: const Color(0xFF0284C7),
              ),
              StatMetricCard(
                label: 'Môn học đào tạo',
                value: '${_subjects.length}',
                icon: Icons.menu_book_rounded,
                color: const Color(0xFF059669),
              ),
              StatMetricCard(
                label: 'GV / Sinh viên',
                value: '${_teachers.length} / ${_students.length}',
                icon: Icons.school_rounded,
                color: const Color(0xFFD97706),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Quick CRUD Actions
          const Text(
            'Thao tác CRUD nhanh',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _showSubjectDialog(),
                icon: const Icon(Icons.add_box_outlined, size: 18),
                label: const Text('Thêm Môn học'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _showClassDialog(),
                icon: const Icon(Icons.add_business_outlined, size: 18),
                label: const Text('Tạo Lớp học'),
              ),
              FilledButton.tonalIcon(
                onPressed: _showCreateUserDialog,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Tạo Người dùng'),
              ),
            ],
          ),
          const SizedBox(height: 22),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Danh sách Lớp học trên hệ thống',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentIndex = 1),
                child: const Text('Xem tất cả'),
              ),
            ],
          ),
          if (_classes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Chưa có lớp học nào. Hãy tạo Môn học và Lớp học mới.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            )
          else
            ..._classes
                .take(5)
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildClassCard(c),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildClassesTab() {
    final filtered =
        _classes.where((c) {
          final q = _classSearch.trim().toLowerCase();
          if (q.isEmpty) return true;
          return c.name.toLowerCase().contains(q) ||
              c.subjectName.toLowerCase().contains(q) ||
              c.teacherName.toLowerCase().contains(q);
        }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showClassDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Tạo lớp học'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _classSearch = v),
              decoration: const InputDecoration(
                hintText: 'Tìm lớp học theo tên lớp, môn học, giảng viên...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child:
                filtered.isEmpty
                    ? EmptyStateView(
                      icon: Icons.class_outlined,
                      title: 'Không tìm thấy lớp học',
                      subtitle:
                          'Nhấn "Tạo lớp học" để gán môn học và giảng viên phụ trách.',
                      action: FilledButton.icon(
                        onPressed: () => _showClassDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Tạo lớp học mới'),
                      ),
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder:
                          (context, idx) => _buildClassCard(filtered[idx]),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassCard(ClassRoomModel c) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openClassDetail(c),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Mã lớp #${c.id}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _showClassDialog(existing: c),
                  tooltip: 'Sửa lớp học',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
                IconButton(
                  onPressed: () => _handleDeleteClass(c),
                  tooltip: 'Xoá lớp học',
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              c.name,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.menu_book_outlined,
                  size: 15,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Môn học: ${c.subjectName}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.co_present_outlined,
                  size: 15,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Giảng viên: ${c.teacherName}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                const Text(
                  'Quản lý chi tiết →',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectsTab() {
    final filtered =
        _subjects.where((s) {
          final q = _subjectSearch.trim().toLowerCase();
          if (q.isEmpty) return true;
          return s.code.toLowerCase().contains(q) ||
              s.name.toLowerCase().contains(q);
        }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSubjectDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Thêm môn học'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _subjectSearch = v),
              decoration: const InputDecoration(
                hintText: 'Tìm theo mã môn học hoặc tên môn học...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child:
                filtered.isEmpty
                    ? EmptyStateView(
                      icon: Icons.menu_book_outlined,
                      title: 'Chưa có môn học nào',
                      subtitle:
                          'Hãy thêm danh mục môn học để mở các lớp học tương ứng.',
                      action: FilledButton.icon(
                        onPressed: () => _showSubjectDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm môn học đầu tiên'),
                      ),
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final s = filtered[idx];
                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                s.code,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF059669),
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            title: Text(
                              s.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text('ID môn học: #${s.id}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed:
                                      () => _showSubjectDialog(existing: s),
                                  tooltip: 'Sửa môn học',
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  onPressed: () => _handleDeleteSubject(s),
                                  tooltip: 'Xoá môn học',
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersTab() {
    final filtered =
        _users.where((u) {
          if (_userRoleFilter != 'ALL' &&
              RoleHelper.normalize(u.role) != _userRoleFilter) {
            return false;
          }
          final q = _userSearch.trim().toLowerCase();
          if (q.isEmpty) return true;
          return u.fullName.toLowerCase().contains(q) ||
              u.username.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q);
        }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateUserDialog,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Thêm người dùng'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _userSearch = v),
              decoration: const InputDecoration(
                hintText: 'Tìm theo họ tên, username hoặc email...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _buildRoleFilterChip('ALL', 'Tất cả (${_users.length})'),
                const SizedBox(width: 8),
                _buildRoleFilterChip(RoleHelper.admin, 'Admin'),
                const SizedBox(width: 8),
                _buildRoleFilterChip(
                  RoleHelper.teacher,
                  'Giảng viên (${_teachers.length})',
                ),
                const SizedBox(width: 8),
                _buildRoleFilterChip(
                  RoleHelper.student,
                  'Sinh viên (${_students.length})',
                ),
              ],
            ),
          ),
          Expanded(
            child:
                filtered.isEmpty
                    ? const EmptyStateView(
                      icon: Icons.person_search_outlined,
                      title: 'Không có người dùng phù hợp',
                      subtitle: 'Hãy thử đổi bộ lọc hoặc tạo tài khoản mới.',
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final u = filtered[idx];
                        final roleColor = RoleHelper.color(u.role);
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 21,
                                    backgroundColor: roleColor.withValues(
                                      alpha: 0.14,
                                    ),
                                    child: Icon(
                                      RoleHelper.icon(u.role),
                                      color: roleColor,
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          u.fullName.isNotEmpty
                                              ? u.fullName
                                              : u.username,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'ID: #${u.id} • @${u.username}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  RoleBadge(role: u.role),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.email_outlined,
                                      size: 15,
                                      color: Color(0xFF64748B),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        u.email,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: Color(0xFF334155),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          u.isActive
                                              ? const Color(0xFFECFDF5)
                                              : const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          u.isActive
                                              ? Icons.check_circle_rounded
                                              : Icons.lock_outline_rounded,
                                          size: 13,
                                          color:
                                              u.isActive
                                                  ? const Color(0xFF059669)
                                                  : const Color(0xFFDC2626),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          u.isActive
                                              ? 'Đang hoạt động'
                                              : 'Chưa kích hoạt / Khoá',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color:
                                                u.isActive
                                                    ? const Color(0xFF059669)
                                                    : const Color(0xFFDC2626),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: const Color(0xFF4F46E5),
                                    ),
                                    onPressed: () => _showUpdateUserDialog(u),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 17,
                                    ),
                                    label: const Text('Sửa'),
                                  ),
                                  const SizedBox(width: 4),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: const Color(0xFFDC2626),
                                    ),
                                    onPressed: () => _handleDeleteUser(u),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('Xoá'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleFilterChip(String value, String label) {
    final selected = _userRoleFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _userRoleFilter = value),
    );
  }
}
