import 'package:flutter_test/flutter_test.dart';
import 'package:garaz_app/core/api_client.dart';
import 'package:garaz_app/core/models.dart';

void main() {
  test('role table mirrors the backend MANAGEABLE_ROLES', () {
    expect(Role.superAdmin.manageable, Role.values);
    expect(Role.admin.manageable, [Role.manager]);
    expect(Role.manager.manageable, isEmpty);
  });

  test('user parses the API shape with login and optional email', () {
    final u = User.fromJson({
      'id': 1,
      'login': 'jkowalski',
      'email': null,
      'full_name': null,
      'role': 'ADMIN',
      'status': 'ACTIVE',
      'must_change_password': true,
      'last_login_at': null,
      'created_at': '2026-11-17T10:00:00Z',
    });
    expect(u.displayName, 'jkowalski');
    expect(u.role.isAdmin, isTrue);
    expect(u.mustChangePassword, isTrue);
  });

  test('422 detail is shown as field — message', () {
    final msg = ApiClient.messageFor(422, [
      {'loc': ['body', 'login'], 'msg': 'Value error, too short'},
    ]);
    expect(msg, contains('login — too short'));
  });
}
