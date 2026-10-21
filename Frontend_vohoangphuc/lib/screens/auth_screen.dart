import 'package:flutter/material.dart';
import '../models/api_models.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/common_widgets.dart';

class AuthScreen extends StatefulWidget {
  final ApiClient api;
  final ValueChanged<AuthSession> onAuthenticated;

  const AuthScreen({
    super.key,
    required this.api,
    required this.onAuthenticated,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Chế độ đăng nhập: 0 = Đăng nhập bằng Mật khẩu, 1 = Đăng nhập bằng OTP qua Gmail
  int _loginMode = 0;

  // Controllers cho Đăng nhập bằng Mật khẩu
  final _loginUsernameCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool _loginObscure = true;

  // Controllers cho Đăng nhập bằng OTP (Chỉ cần nhập Gmail + OTP, không cần mật khẩu)
  final _loginGmailCtrl = TextEditingController();
  final _loginOtpCtrl = TextEditingController();
  bool _loginOtpSent = false;
  bool _loginLoading = false;

  // Controllers cho Đăng ký qua Email
  final _regFullNameCtrl = TextEditingController();
  final _regUsernameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();
  final _regOtpCtrl = TextEditingController();
  String _regRole = RoleHelper.student;
  bool _regObscure = true;
  bool _regOtpStep = false;
  bool _regLoading = false;

  String? _biometricUsername;
  String? _biometricRole;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkBiometricSession();
  }

  Future<void> _checkBiometricSession() async {
    final s = await AuthService.restoreBiometricSession();
    if (!mounted) return;
    setState(() {
      _biometricUsername = s?.username;
      _biometricRole = s?.role;
      if (s != null && _loginUsernameCtrl.text.isEmpty) {
        _loginUsernameCtrl.text = s.username;
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginUsernameCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _loginGmailCtrl.dispose();
    _loginOtpCtrl.dispose();
    _regFullNameCtrl.dispose();
    _regUsernameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPasswordCtrl.dispose();
    _regOtpCtrl.dispose();
    super.dispose();
  }

  /// Lựa chọn 1: Đăng nhập bằng Tên đăng nhập + Mật khẩu (KHÔNG gửi OTP về Gmail)
  Future<void> _handlePasswordLogin() async {
    final username = _loginUsernameCtrl.text.trim();
    final password = _loginPasswordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      showAppSnackBar(
        context,
        'Vui lòng nhập đầy đủ Tên đăng nhập và Mật khẩu.',
        isError: true,
      );
      return;
    }

    setState(() => _loginLoading = true);
    try {
      final session = await AuthService.loginWithPassword(
        username: username,
        password: password,
        api: widget.api,
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Đăng nhập thành công! Xin chào ${session.fullName} (${RoleHelper.shortLabel(session.role)}).',
      );
      widget.onAuthenticated(session);
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  /// Lựa chọn 2 (Bước 1): Chỉ nhập Gmail -> Bấm nhận OTP (Không cần mật khẩu)
  Future<void> _handleRequestGmailOtp() async {
    final gmail = _loginGmailCtrl.text.trim();
    if (gmail.isEmpty || !gmail.contains('@')) {
      showAppSnackBar(
        context,
        'Vui lòng nhập địa chỉ Gmail của bạn để nhận mã OTP.',
        isError: true,
      );
      return;
    }

    setState(() => _loginLoading = true);
    try {
      final msg = await AuthService.sendLoginOtpToGmail(
        gmailInput: gmail,
        api: widget.api,
      );
      if (!mounted) return;
      setState(() {
        _loginOtpSent = true;
        _loginOtpCtrl.clear();
      });
      showAppSnackBar(context, msg);
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  /// Lựa chọn 2 (Bước 2): Nhập mã OTP nhận từ Gmail -> Đăng nhập vào trong
  Future<void> _handleVerifyGmailOtp() async {
    final gmail = _loginGmailCtrl.text.trim();
    final code = _loginOtpCtrl.text.trim();
    if (gmail.isEmpty || code.length < 4) {
      showAppSnackBar(
        context,
        'Vui lòng nhập mã OTP 6 chữ số đã gửi về Gmail.',
        isError: true,
      );
      return;
    }

    setState(() => _loginLoading = true);
    try {
      final session = await AuthService.verifyLoginOtpFromGmail(
        gmailInput: gmail,
        otpCode: code,
        api: widget.api,
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Xác thực OTP thành công! Xin chào ${session.fullName}.',
      );
      widget.onAuthenticated(session);
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  /// Đăng nhập bằng cảm biến vân tay vật lý trên điện thoại (nút nguồn cạnh bên)
  Future<void> _handleFingerprintLogin() async {
    final savedSession = await AuthService.restoreBiometricSession();
    if (!mounted) return;
    if (savedSession == null) {
      showAppSnackBar(
        context,
        'Bạn chưa đăng ký vân tay. Hãy đăng nhập vào ứng dụng rồi vào tab "Tiện ích -> Vân tay" để đăng ký vân tay lần đầu!',
        isError: true,
      );
      return;
    }

    try {
      final authenticated = await AuthService.authenticateWithHardwareBiometrics(
        reason:
            'Chạm cảm biến vân tay của điện thoại để đăng nhập tài khoản @${savedSession.username}',
      );
      if (!mounted) return;
      if (authenticated) {
        showAppSnackBar(
          context,
          'Xác thực vân tay thành công! Chào mừng ${savedSession.fullName}.',
        );
        widget.onAuthenticated(savedSession);
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Không thể xác thực vân tay: ${e.toString().replaceFirst("Exception: ", "")}',
        isError: true,
      );
    }
  }

  Future<void> _handleRegisterStep1() async {
    final fullName = _regFullNameCtrl.text.trim();
    final username = _regUsernameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final password = _regPasswordCtrl.text;

    if (fullName.isEmpty ||
        username.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      showAppSnackBar(
        context,
        'Vui lòng điền đầy đủ thông tin đăng ký.',
        isError: true,
      );
      return;
    }
    if (!email.contains('@')) {
      showAppSnackBar(context, 'Địa chỉ email không hợp lệ.', isError: true);
      return;
    }
    if (password.length < 6) {
      showAppSnackBar(
        context,
        'Mật khẩu phải có tối thiểu 6 ký tự.',
        isError: true,
      );
      return;
    }

    setState(() => _regLoading = true);
    try {
      final msg = await widget.api.register(
        username: username,
        email: email,
        password: password,
        fullName: fullName,
        role: _regRole,
      );
      await AuthService.saveRegisteredAccountInfo(
        username: username,
        email: email,
        password: password,
        fullName: fullName,
        role: _regRole,
      );
      if (!mounted) return;
      setState(() {
        _regOtpStep = true;
        _regOtpCtrl.clear();
      });
      showAppSnackBar(context, msg);
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _regLoading = false);
    }
  }

  Future<void> _handleRegisterVerifyOtp() async {
    final username = _regUsernameCtrl.text.trim();
    final code = _regOtpCtrl.text.trim();
    if (username.isEmpty || code.length < 4) {
      showAppSnackBar(
        context,
        'Vui lòng nhập Tên đăng nhập và Mã OTP xác nhận.',
        isError: true,
      );
      return;
    }

    setState(() => _regLoading = true);
    try {
      final msg = await widget.api.verifyRegister(
        username: username,
        code: code,
      );
      if (!mounted) return;
      showAppSnackBar(context, msg);
      setState(() {
        _regOtpStep = false;
        _loginUsernameCtrl.text = username;
        _loginPasswordCtrl.text = _regPasswordCtrl.text;
        _loginGmailCtrl.text = _regEmailCtrl.text.trim();
        _loginMode = 0;
      });
      _tabController.animateTo(0);
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _regLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E1B4B),
              Color(0xFF312E81),
              Color(0xFF4F46E5),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  children: [
                    // Top Server Config Chip
                    Align(
                      alignment: Alignment.centerRight,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap:
                            () => showServerConfigDialog(
                              context,
                              widget.api,
                              onUpdated: () => setState(() {}),
                            ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.dns_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  widget.api.baseUrl,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.edit_outlined,
                                size: 14,
                                color: Colors.white70,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // App Hero Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'HỆ THỐNG ĐIỂM DANH & QUẢN LÝ LỚP',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Võ Hoàng Phúc - 0118 - Nhóm 01',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Main White Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Tab Bar: Đăng nhập vs Đăng ký Email
                          Container(
                            margin: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              indicatorSize: TabBarIndicatorSize.tab,
                              dividerColor: Colors.transparent,
                              indicator: BoxDecoration(
                                color: const Color(0xFF4F46E5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              labelColor: Colors.white,
                              unselectedLabelColor: const Color(0xFF475569),
                              labelStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                              tabs: const [
                                Tab(text: 'Đăng nhập'),
                                Tab(text: 'Đăng ký Email'),
                              ],
                            ),
                          ),

                          // Tab Content
                          AnimatedBuilder(
                            animation: _tabController,
                            builder: (context, _) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  4,
                                  20,
                                  22,
                                ),
                                child:
                                    _tabController.index == 0
                                        ? _buildLoginView()
                                        : _buildRegisterView(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hai lựa chọn đăng nhập: Bằng mật khẩu hoặc Bằng OTP (Gmail)
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _loginMode = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color:
                          _loginMode == 0
                              ? Colors.white
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow:
                          _loginMode == 0
                              ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 6,
                                ),
                              ]
                              : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 16,
                          color:
                              _loginMode == 0
                                  ? const Color(0xFF4F46E5)
                                  : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Bằng Mật khẩu',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color:
                                  _loginMode == 0
                                      ? const Color(0xFF312E81)
                                      : const Color(0xFF64748B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _loginMode = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color:
                          _loginMode == 1
                              ? Colors.white
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow:
                          _loginMode == 1
                              ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 6,
                                ),
                              ]
                              : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mark_email_read_outlined,
                          size: 16,
                          color:
                              _loginMode == 1
                                  ? const Color(0xFF4F46E5)
                                  : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Bằng mã OTP',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color:
                                  _loginMode == 1
                                      ? const Color(0xFF312E81)
                                      : const Color(0xFF64748B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_loginMode == 0)
          _buildPasswordLoginSection()
        else
          _buildGmailOtpLoginSection(),

        const SizedBox(height: 12),
        // Nút đăng nhập nhanh bằng cảm biến vân tay vật lý trên điện thoại
        OutlinedButton.icon(
          onPressed: _handleFingerprintLogin,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF059669),
            side: const BorderSide(color: Color(0xFF10B981)),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          ),
          icon: const Icon(Icons.fingerprint_rounded, size: 22),
          label: Text(
            _biometricUsername != null
                ? 'Đăng nhập vân tay (@$_biometricUsername - $_biometricRole)'
                : 'Đăng nhập bằng cảm biến vân tay',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ],
    );
  }

  /// Giao diện Lựa chọn 1: Đăng nhập bằng Mật khẩu
  Widget _buildPasswordLoginSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _loginUsernameCtrl,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Tên đăng nhập (Username)',
            hintText: 'VD: admin, gv01, phuchoangvo...',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _loginPasswordCtrl,
          obscureText: _loginObscure,
          onSubmitted: (_) => _handlePasswordLogin(),
          decoration: InputDecoration(
            labelText: 'Mật khẩu',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _loginObscure = !_loginObscure),
              icon: Icon(
                _loginObscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loginLoading ? null : _handlePasswordLogin,
          icon:
              _loginLoading
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : const Icon(Icons.login_rounded),
          label: Text(
            _loginLoading ? 'Đang đăng nhập...' : 'Đăng nhập bằng Mật khẩu',
          ),
        ),
      ],
    );
  }

  /// Giao diện Lựa chọn 2: Đăng nhập bằng OTP qua Gmail (Chỉ nhập Gmail -> Nhận OTP -> Nhập OTP)
  Widget _buildGmailOtpLoginSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _loginGmailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_loginOtpSent) _handleRequestGmailOtp();
          },
          decoration: const InputDecoration(
            labelText: 'Địa chỉ Gmail nhận mã OTP',
            hintText: 'VD: tenban@gmail.com',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 14),
        if (!_loginOtpSent) ...[
          FilledButton.icon(
            onPressed: _loginLoading ? null : _handleRequestGmailOtp,
            icon:
                _loginLoading
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Icon(Icons.send_rounded),
            label: Text(
              _loginLoading
                  ? 'Đang gửi mã OTP tới Gmail...'
                  : 'Nhận mã OTP qua Gmail',
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _loginOtpSent = true),
              icon: const Icon(Icons.dialpad_rounded, size: 16),
              label: const Text(
                'Đã có mã OTP? Nhập mã ngay',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Mã OTP 6 chữ số đã được gửi tới Gmail "${_loginGmailCtrl.text.trim()}". Vui lòng nhập mã bên dưới để đăng nhập:',
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF312E81),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _loginOtpCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            onSubmitted: (_) => _handleVerifyGmailOtp(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
            decoration: const InputDecoration(
              labelText: 'Mã xác thực OTP (6 số)',
              hintText: '123456',
              counterText: '',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _loginLoading ? null : _handleVerifyGmailOtp,
            icon:
                _loginLoading
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Icon(Icons.verified_rounded),
            label: Text(
              _loginLoading
                  ? 'Đang xác thực OTP...'
                  : 'Xác nhận OTP & Đăng nhập',
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed:
                    _loginLoading
                        ? null
                        : () => setState(() => _loginOtpSent = false),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Đổi địa chỉ Gmail'),
              ),
              TextButton.icon(
                onPressed: _loginLoading ? null : _handleRequestGmailOtp,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Gửi lại OTP'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildRegisterView() {
    if (_regOtpStep) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_outlined,
                  color: Color(0xFF059669),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bước 2/2: Nhập mã OTP đã gửi tới email "${_regEmailCtrl.text.trim()}" để kích hoạt tài khoản.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF065F46),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _regUsernameCtrl,
            decoration: const InputDecoration(
              labelText: 'Tên đăng nhập cần kích hoạt',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regOtpCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
            decoration: const InputDecoration(
              labelText: 'Mã OTP kích hoạt (6 số)',
              hintText: '123456',
              counterText: '',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _regLoading ? null : _handleRegisterVerifyOtp,
            icon:
                _regLoading
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Icon(Icons.check_circle_outline_rounded),
            label: Text(
              _regLoading
                  ? 'Đang xác nhận...'
                  : 'Xác nhận OTP & Kích hoạt tài khoản',
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed:
                _regLoading
                    ? null
                    : () => setState(() => _regOtpStep = false),
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Quay lại biểu mẫu đăng ký'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Đăng ký tài khoản qua Email',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Hệ thống sẽ gửi mã OTP tới email để xác thực tài khoản mới',
          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _regFullNameCtrl,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Họ và tên đầy đủ',
            hintText: 'VD: Võ Hoàng Phúc',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regUsernameCtrl,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Tên đăng nhập (Username)',
            hintText: 'VD: phuc0118',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Địa chỉ Email nhận OTP',
            hintText: 'VD: phuc@gmail.com',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _regRole,
          decoration: const InputDecoration(
            labelText: 'Vai trò tài khoản',
            prefixIcon: Icon(Icons.assignment_ind_outlined),
          ),
          items: const [
            DropdownMenuItem(
              value: RoleHelper.student,
              child: Text('Sinh viên (Người học)'),
            ),
            DropdownMenuItem(
              value: RoleHelper.teacher,
              child: Text('Giảng viên (Phụ trách lớp)'),
            ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _regRole = v);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regPasswordCtrl,
          obscureText: _regObscure,
          decoration: InputDecoration(
            labelText: 'Mật khẩu (tối thiểu 6 ký tự)',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _regObscure = !_regObscure),
              icon: Icon(
                _regObscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _regLoading ? null : _handleRegisterStep1,
          icon:
              _regLoading
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : const Icon(Icons.mark_email_unread_outlined),
          label: Text(
            _regLoading
                ? 'Đang tạo tài khoản & gửi OTP...'
                : 'Đăng ký & Nhận OTP qua Email',
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _regOtpStep = true),
            icon: const Icon(Icons.verified_user_outlined, size: 16),
            label: const Text(
              'Đã nhận mã OTP kích hoạt? Nhập tại đây',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
        ),
      ],
    );
  }
}
