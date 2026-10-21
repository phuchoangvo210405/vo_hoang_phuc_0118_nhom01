import 'package:flutter_test/flutter_test.dart';
import 'package:vo_hoang_phuc_0118_nhom01/main.dart';

void main() {
  testWidgets('Render AuthScreen by default', (WidgetTester tester) async {
    await tester.pumpWidget(const DiemDanhSvApp());
    expect(find.text('HỆ THỐNG ĐIỂM DANH & QUẢN LÝ LỚP'), findsOneWidget);
    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(find.text('Bằng Mật khẩu'), findsOneWidget);
    expect(find.text('Bằng mã OTP'), findsOneWidget);
    expect(find.text('Đăng ký Email'), findsOneWidget);
  });
}
