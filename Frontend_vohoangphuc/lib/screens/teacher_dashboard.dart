import 'package:flutter/material.dart';
import '../models/api_models.dart';
import '../services/api_client.dart';
import '../widgets/common_widgets.dart';
import 'class_detail_screen.dart';
import 'smart_features_screen.dart';

class TeacherDashboard extends StatefulWidget {
  final ApiClient api;
  final AuthSession session;
  final VoidCallback onLogout;

  const TeacherDashboard({
    super.key,
    required this.api,
    required this.session,
    required this.onLogout,
  });

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  int _currentIndex = 0;
  bool _loading = true;
  List<ClassRoomModel> _classes = [];
  List<SubjectModel> _subjects = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.api.getClasses(),
        widget.api.getSubjects(),
      ]);
      if (!mounted) return;
      setState(() {
        _classes = results[0] as List<ClassRoomModel>;
        _subjects = results[1] as List<SubjectModel>;
      });
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openClass(ClassRoomModel c) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ClassDetailScreen(
              api: widget.api,
              classRoom: c,
              session: widget.session,
            ),
      ),
    ).then((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0369A1),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DASHBOARD GIẢNG VIÊN (NHÂN VIÊN)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              'GV: ${widget.session.fullName} (@${widget.session.username})',
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
            onPressed: _loadData,
            tooltip: 'Làm mới',
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
                  _buildClassesView(),
                  _buildSubjectsView(),
                  SmartFeaturesScreen(
                    api: widget.api,
                    session: widget.session,
                  ),
                ],
              ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          if (i == 2) {
            SmartFeaturesScreen.notifySessionsChanged();
          }
        },
        destinations: [
          NavigationDestination(
            icon: Badge(
              label: Text('${_classes.length}'),
              child: const Icon(Icons.co_present_outlined),
            ),
            selectedIcon: Badge(
              label: Text('${_classes.length}'),
              child: const Icon(Icons.co_present_rounded),
            ),
            label: 'Lớp phụ trách',
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
            label: 'Danh mục Môn học',
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

  Widget _buildClassesView() {
    final filtered =
        _classes.where((c) {
          final q = _search.trim().toLowerCase();
          if (q.isEmpty) return true;
          return c.name.toLowerCase().contains(q) ||
              c.subjectName.toLowerCase().contains(q);
        }).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Teacher Hero Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0369A1), Color(0xFF0284C7)],
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
                    Icons.co_present_rounded,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Xin chào GV. ${widget.session.fullName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Chọn lớp học bên dưới để tạo buổi học (CRUD), mở mã QR điểm danh, quản lý sinh viên, duyệt đơn nghỉ và gửi cảnh báo học vụ.',
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
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: StatMetricCard(
                  label: 'Lớp đang phụ trách',
                  value: '${_classes.length}',
                  icon: Icons.class_rounded,
                  color: const Color(0xFF0284C7),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatMetricCard(
                  label: 'Tổng môn đào tạo',
                  value: '${_subjects.length}',
                  icon: Icons.menu_book_rounded,
                  color: const Color(0xFF059669),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: const InputDecoration(
              hintText: 'Tìm kiếm lớp học phụ trách...',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 14),

          if (filtered.isEmpty)
            const EmptyStateView(
              icon: Icons.school_outlined,
              title: 'Chưa có lớp học nào được phân công',
              subtitle:
                  'Quản trị viên (Admin) sẽ phân công lớp học cho tài khoản Giảng viên của bạn.',
            )
          else
            ...filtered.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _openClass(c),
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
                                color: const Color(0xFFE0F2FE),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Mã lớp #${c.id}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0369A1),
                                ),
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 16,
                              color: Color(0xFF64748B),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          c.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Môn học: ${c.subjectName}',
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () => _openClass(c),
                              icon: const Icon(
                                Icons.qr_code_2_rounded,
                                size: 18,
                              ),
                              label: const Text('Quản lý Buổi học & Điểm danh'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubjectsView() {
    if (_subjects.isEmpty) {
      return const EmptyStateView(
        icon: Icons.menu_book_outlined,
        title: 'Chưa có môn học nào',
        subtitle: 'Danh sách các môn học trên hệ thống sẽ hiển thị tại đây.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _subjects.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final s = _subjects[idx];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                s.code,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0369A1),
                ),
              ),
            ),
            title: Text(
              s.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Mã định danh môn học: #${s.id}'),
          ),
        );
      },
    );
  }
}
