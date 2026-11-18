/// DTOs mirroring the backend schemas (app/schemas/*.py in GARAZ).
library;

enum Role {
  superAdmin('SUPER_ADMIN', 'Super administrator'),
  admin('ADMIN', 'Administrator'),
  manager('MANAGER', 'Kierownik / Lider');

  const Role(this.api, this.label);

  final String api;
  final String label;

  static Role fromApi(String value) => Role.values.firstWhere((r) => r.api == value);

  bool get isAdmin => this == Role.superAdmin || this == Role.admin;

  /// Which roles this role may create or edit — same table as the backend's
  /// MANAGEABLE_ROLES, so the UI never offers what the server would refuse.
  List<Role> get manageable => switch (this) {
    Role.superAdmin => Role.values,
    Role.admin => const [Role.manager],
    Role.manager => const [],
  };
}

enum UserStatus {
  active('ACTIVE', 'Aktywne'),
  disabled('DISABLED', 'Wyłączone');

  const UserStatus(this.api, this.label);

  final String api;
  final String label;

  static UserStatus fromApi(String value) => UserStatus.values.firstWhere((s) => s.api == value);
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

class User {
  const User({
    required this.id,
    required this.login,
    required this.email,
    required this.fullName,
    required this.role,
    required this.status,
    required this.mustChangePassword,
    required this.lastLoginAt,
    required this.createdAt,
  });

  final int id;
  final String login;
  final String? email;
  final String? fullName;
  final Role role;
  final UserStatus status;

  /// Set by an administrator; the app shows only the new-password screen
  /// until the user picks their own.
  final bool mustChangePassword;
  final DateTime? lastLoginAt;
  final DateTime createdAt;

  String get displayName => (fullName?.isNotEmpty ?? false) ? fullName! : login;

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: j['id'] as int,
    login: j['login'] as String,
    email: j['email'] as String?,
    fullName: j['full_name'] as String?,
    role: Role.fromApi(j['role'] as String),
    status: UserStatus.fromApi(j['status'] as String),
    mustChangePassword: j['must_change_password'] as bool? ?? false,
    lastLoginAt: _date(j['last_login_at']),
    createdAt: _date(j['created_at'])!,
  );
}

class AuditEntry {
  const AuditEntry({
    required this.action,
    required this.userId,
    required this.resourceType,
    required this.resourceId,
    required this.ipAddress,
    required this.payload,
    required this.createdAt,
  });

  final String action;
  final int? userId;
  final String? resourceType;
  final String? resourceId;
  final String? ipAddress;
  final Map<String, dynamic>? payload;
  final DateTime createdAt;

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
    action: j['action'] as String,
    userId: j['user_id'] as int?,
    resourceType: j['resource_type'] as String?,
    resourceId: j['resource_id'] as String?,
    ipAddress: j['ip_address'] as String?,
    payload: (j['payload'] as Map?)?.cast<String, dynamic>(),
    createdAt: _date(j['created_at'])!,
  );

  /// Polish name of the action; unknown ones show as sent.
  String get label => switch (action) {
    'auth.login' => 'Logowanie',
    'auth.logout_all' => 'Wylogowanie ze wszystkich urządzeń',
    'auth.password_changed' => 'Zmiana hasła',
    'auth.token_reuse' => 'Podejrzenie przejęcia sesji',
    'user.created' => 'Utworzenie konta',
    'user.updated' => 'Zmiana konta',
    'dictionary.created' => 'Dodanie pozycji słownika',
    'dictionary.updated' => 'Zmiana pozycji słownika',
    'truck.created' => 'Dodanie wózka',
    'truck.updated' => 'Zmiana wózka',
    'truck.qr_reissued' => 'Nowy kod QR wózka',
    _ => action,
  };
}

class PageOf<T> {
  const PageOf({required this.items, required this.total, required this.page, required this.limit});

  final List<T> items;
  final int total;
  final int page;
  final int limit;

  factory PageOf.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) item) => PageOf(
    items: (j['items'] as List).map((e) => item((e as Map).cast<String, dynamic>())).toList(),
    total: j['total'] as int,
    page: j['page'] as int,
    limit: j['limit'] as int,
  );
}

/// "2026-11-17 14:05" in the device's zone (the warehouse's, in practice).
String formatDateTime(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// The panel's lists; [api] is the URL segment under /dictionaries.
enum DictionaryKind {
  truckTypes('truck-types', 'Typy wózków'),
  permitCategories('permit-categories', 'Kategorie uprawnień'),
  employers('employers', 'Pracodawcy'),
  incidentCategories('incident-categories', 'Kategorie zdarzeń'),
  sites('sites', 'Lokalizacje');

  const DictionaryKind(this.api, this.label);

  final String api;
  final String label;
}

enum IncidentType {
  awaria('AWARIA', 'Awaria'),
  uszkodzenie('USZKODZENIE', 'Uszkodzenie'),
  kolizja('KOLIZJA', 'Kolizja');

  const IncidentType(this.api, this.label);

  final String api;
  final String label;

  /// What the type means — shown next to the choice, the line between them is not obvious.
  String get hint => switch (this) {
    IncidentType.awaria => 'Wózek przestał działać prawidłowo — usterka techniczna (bateria, hydraulika, maszt…).',
    IncidentType.uszkodzenie => 'Fizyczne uszkodzenie bez zderzenia (pęknięta osłona, wygięte widły, zużyta opona).',
    IncidentType.kolizja => 'Wózek w coś uderzył: regał, ścianę lub bramę, inny wózek.',
  };

  static IncidentType fromApi(String value) => IncidentType.values.firstWhere((t) => t.api == value);
}

class DictionaryEntry {
  const DictionaryEntry({
    required this.id,
    required this.name,
    required this.isActive,
    required this.sortOrder,
    required this.incidentTypes,
    required this.defaultOutOfService,
  });

  final int id;
  final String name;
  final bool isActive;
  final int sortOrder;

  /// Incident categories only; null elsewhere.
  final List<IncidentType>? incidentTypes;
  final bool? defaultOutOfService;

  factory DictionaryEntry.fromJson(Map<String, dynamic> j) => DictionaryEntry(
    id: j['id'] as int,
    name: j['name'] as String,
    isActive: j['is_active'] as bool,
    sortOrder: j['sort_order'] as int,
    incidentTypes: (j['incident_types'] as List?)?.map((e) => IncidentType.fromApi(e as String)).toList(),
    defaultOutOfService: j['default_out_of_service'] as bool?,
  );
}

enum TruckStatus {
  active('ACTIVE', 'Aktywny'),
  outOfService('OUT_OF_SERVICE', 'Wyłączony z eksploatacji'),
  inactive('INACTIVE', 'Nieaktywny');

  const TruckStatus(this.api, this.label);

  final String api;
  final String label;

  static TruckStatus fromApi(String value) => TruckStatus.values.firstWhere((s) => s.api == value);
}

/// A dictionary entry as another record shows it.
class EntryRef {
  const EntryRef(this.id, this.name);

  final int id;
  final String name;

  factory EntryRef.fromJson(Map<String, dynamic> j) => EntryRef(j['id'] as int, j['name'] as String);
}

class Truck {
  const Truck({
    required this.id,
    required this.number,
    required this.manufacturer,
    required this.model,
    required this.status,
    required this.site,
    required this.truckType,
    required this.qrUrl,
    required this.qrIssuedAt,
  });

  final int id;
  final String number;
  final String? manufacturer;
  final String? model;
  final TruckStatus status;
  final EntryRef site;
  final EntryRef truckType;

  /// What the sticker encodes.
  final String qrUrl;
  final DateTime qrIssuedAt;

  String get makeAndModel => [manufacturer, model].whereType<String>().join(' ');

  factory Truck.fromJson(Map<String, dynamic> j) => Truck(
    id: j['id'] as int,
    number: j['number'] as String,
    manufacturer: j['manufacturer'] as String?,
    model: j['model'] as String?,
    status: TruckStatus.fromApi(j['status'] as String),
    site: EntryRef.fromJson((j['site'] as Map).cast<String, dynamic>()),
    truckType: EntryRef.fromJson((j['truck_type'] as Map).cast<String, dynamic>()),
    qrUrl: j['qr_url'] as String,
    qrIssuedAt: _date(j['qr_issued_at'])!,
  );
}
