/// DTOs mirroring the backend schemas (app/schemas/*.py in GARAZ).
library;

import 'i18n.dart';

enum Role {
  superAdmin('SUPER_ADMIN', 'Super administrator'),
  admin('ADMIN', 'Administrator'),
  manager('MANAGER', 'Kierownik / Lider');

  const Role(this.api, this._label);

  final String api;
  final String _label;

  String get label => tr(_label);

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

  const UserStatus(this.api, this._label);

  final String api;
  final String _label;

  String get label => tr(_label);

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
    'auth.login' => tr('Logowanie'),
    'auth.logout_all' => tr('Wylogowanie ze wszystkich urządzeń'),
    'auth.password_changed' => tr('Zmiana hasła'),
    'auth.token_reuse' => tr('Podejrzenie przejęcia sesji'),
    'user.created' => tr('Utworzenie konta'),
    'user.updated' => tr('Zmiana konta'),
    'dictionary.created' => tr('Dodanie pozycji słownika'),
    'dictionary.updated' => tr('Zmiana pozycji słownika'),
    'truck.created' => tr('Dodanie wózka'),
    'truck.updated' => tr('Zmiana wózka'),
    'truck.qr_reissued' => tr('Nowy kod QR wózka'),
    'truck.deleted' => tr('Usunięcie wózka'),
    'truck_manufacturer.created' => tr('Dodanie producenta wózków'),
    'truck_manufacturer.updated' => tr('Zmiana producenta wózków'),
    'truck_manufacturer.deleted' => tr('Usunięcie producenta wózków'),
    'truck_model.created' => tr('Dodanie modelu wózka'),
    'truck_model.updated' => tr('Zmiana modelu wózka'),
    'truck_model.deleted' => tr('Usunięcie modelu wózka'),
    'incident.created' => tr('Zgłoszenie zdarzenia'),
    'incident.updated' => tr('Zmiana zgłoszenia'),
    'operator.created' => tr('Dodanie operatora'),
    'operator.updated' => tr('Zmiana operatora'),
    'operator.qr_reissued' => tr('Nowy kod QR operatora'),
    'permit.created' => tr('Dodanie uprawnienia'),
    'permit.updated' => tr('Zmiana uprawnienia'),
    'permit.expired' => tr('Uprawnienie wygasło'),
    'permit.renewed' => tr('Uprawnienie odnowione (nowy numer)'),
    'permit.document_attached' => tr('Dołączenie skanu dokumentu'),
    'permit.document_removed' => tr('Usunięcie skanu dokumentu'),
    'report.exported' => tr('Eksport do Excel'),
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
  return tr('{year}-{month}-{day} {hour}:{minute}', {
    'year': d.year,
    'month': two(d.month),
    'day': two(d.day),
    'hour': two(d.hour),
    'minute': two(d.minute),
  });
}

/// The panel's lists; [api] is the URL segment under /dictionaries.
enum DictionaryKind {
  truckTypes('truck-types', 'Typy wózków'),
  permitCategories('permit-categories', 'Kategorie uprawnień'),
  employers('employers', 'Pracodawcy'),
  incidentCategories('incident-categories', 'Kategorie zdarzeń'),
  sites('sites', 'Lokalizacje');

  const DictionaryKind(this.api, this._label);

  final String api;
  final String _label;

  String get label => tr(_label);
}

enum IncidentType {
  awaria('AWARIA', 'Awaria'),
  uszkodzenie('USZKODZENIE', 'Uszkodzenie'),
  kolizja('KOLIZJA', 'Kolizja');

  const IncidentType(this.api, this._label);

  final String api;
  final String _label;

  String get label => tr(_label);

  /// What the type means — shown next to the choice, the line between them is not obvious.
  String get hint => switch (this) {
    IncidentType.awaria => tr('Wózek przestał działać prawidłowo — usterka techniczna (bateria, hydraulika, maszt…).'),
    IncidentType.uszkodzenie => tr(
      'Fizyczne uszkodzenie bez zderzenia (pęknięta osłona, wygięte widły, zużyta opona).',
    ),
    IncidentType.kolizja => tr('Wózek w coś uderzył: regał, ścianę lub bramę, inny wózek.'),
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

  const TruckStatus(this.api, this._label);

  final String api;
  final String _label;

  String get label => tr(_label);

  /// For a status label in a list row.
  String get shortLabel => switch (this) {
    TruckStatus.outOfService => tr('Wyłączony'),
    _ => label,
  };

  /// For a filter: the trucks in this status.
  String get filterLabel => switch (this) {
    TruckStatus.active => tr('Aktywne'),
    TruckStatus.outOfService => tr('Wyłączone'),
    TruckStatus.inactive => tr('Nieaktywne'),
  };

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
  final EntryRef? manufacturer;
  final EntryRef? model;
  final TruckStatus status;
  final EntryRef site;
  final EntryRef truckType;

  /// What the sticker encodes.
  final String qrUrl;
  final DateTime qrIssuedAt;

  String get makeAndModel => [manufacturer?.name, model?.name].whereType<String>().join(' ');

  factory Truck.fromJson(Map<String, dynamic> j) => Truck(
    id: j['id'] as int,
    number: j['number'] as String,
    manufacturer: _ref(j['manufacturer']),
    model: _ref(j['model']),
    status: TruckStatus.fromApi(j['status'] as String),
    site: EntryRef.fromJson((j['site'] as Map).cast<String, dynamic>()),
    truckType: EntryRef.fromJson((j['truck_type'] as Map).cast<String, dynamic>()),
    qrUrl: j['qr_url'] as String,
    qrIssuedAt: _date(j['qr_issued_at'])!,
  );
}

EntryRef? _ref(Object? v) => v == null ? null : EntryRef.fromJson((v as Map).cast<String, dynamic>());

/// A truck model in the manufacturers list, with how many trucks are it.
class TruckModelEntry {
  const TruckModelEntry({required this.id, required this.name, required this.truckCount});

  final int id;
  final String name;
  final int truckCount;

  factory TruckModelEntry.fromJson(Map<String, dynamic> j) =>
      TruckModelEntry(id: j['id'] as int, name: j['name'] as String, truckCount: j['truck_count'] as int? ?? 0);
}

/// A truck manufacturer with its models; [truckCount] counts its trucks of any model.
class TruckManufacturer {
  const TruckManufacturer({required this.id, required this.name, required this.models, required this.truckCount});

  final int id;
  final String name;
  final List<TruckModelEntry> models;
  final int truckCount;

  factory TruckManufacturer.fromJson(Map<String, dynamic> j) => TruckManufacturer(
    id: j['id'] as int,
    name: j['name'] as String,
    truckCount: j['truck_count'] as int? ?? 0,
    models: [for (final m in j['models'] as List) TruckModelEntry.fromJson((m as Map).cast<String, dynamic>())],
  );
}

DateTime _day(Object v) => DateTime.parse(v as String);

/// "2026-11-17", a calendar day (no zone).
String formatDay(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

enum PermitStatus {
  active('ACTIVE', 'Aktywne'),
  suspended('SUSPENDED', 'Zawieszone'),
  expired('EXPIRED', 'Wygasłe'),
  // Replaced by a renewal (new number); kept read-only.
  archived('ARCHIVED', 'Zarchiwizowane');

  const PermitStatus(this.api, this._label);

  final String api;
  final String _label;

  String get label => tr(_label);

  static PermitStatus fromApi(String value) => PermitStatus.values.firstWhere((s) => s.api == value);
}

/// A permit as its operator's record lists it.
class PermitBrief {
  const PermitBrief({
    required this.id,
    required this.number,
    required this.status,
    required this.category,
    required this.validUntil,
    required this.truckTypes,
    required this.daysLeft,
  });

  final int id;
  final String number;
  final PermitStatus status;
  final EntryRef category;
  final DateTime validUntil;
  final List<EntryRef> truckTypes;

  /// 0 on the last valid day, negative once past.
  final int daysLeft;

  factory PermitBrief.fromJson(Map<String, dynamic> j) => PermitBrief(
    id: j['id'] as int,
    number: j['number'] as String,
    status: PermitStatus.fromApi(j['status'] as String),
    category: EntryRef.fromJson((j['category'] as Map).cast<String, dynamic>()),
    validUntil: _day(j['valid_until']),
    truckTypes: [for (final t in j['truck_types'] as List) EntryRef.fromJson((t as Map).cast<String, dynamic>())],
    daysLeft: j['days_left'] as int,
  );
}

class PermitDocument {
  const PermitDocument(this.filename, this.contentType, this.size);

  final String filename;
  final String contentType;
  final int size;
}

class Permit extends PermitBrief {
  const Permit({
    required super.id,
    required super.number,
    required super.status,
    required super.category,
    required super.validUntil,
    required super.truckTypes,
    required super.daysLeft,
    required this.operatorId,
    required this.operatorName,
    required this.operatorEmployer,
    required this.issuedOn,
    required this.udtNumber,
    required this.replacedById,
    required this.basisName,
    required this.basisNumber,
    required this.basisDate,
    required this.document,
  });

  final int operatorId;
  final String operatorName;
  final String? operatorEmployer;
  final DateTime issuedOn;
  final String? udtNumber;
  final int? replacedById;
  final String? basisName;
  final String? basisNumber;
  final DateTime? basisDate;
  final PermitDocument? document;

  factory Permit.fromJson(Map<String, dynamic> j) {
    final brief = PermitBrief.fromJson(j);
    final op = (j['operator'] as Map).cast<String, dynamic>();
    final doc = (j['document'] as Map?)?.cast<String, dynamic>();
    return Permit(
      id: brief.id,
      number: brief.number,
      status: brief.status,
      category: brief.category,
      validUntil: brief.validUntil,
      truckTypes: brief.truckTypes,
      daysLeft: brief.daysLeft,
      operatorId: op['id'] as int,
      operatorName: op['full_name'] as String,
      operatorEmployer: (op['employer'] as Map?)?['name'] as String?,
      issuedOn: _day(j['issued_on']),
      udtNumber: j['udt_number'] as String?,
      replacedById: j['replaced_by_id'] as int?,
      basisName: j['basis_name'] as String?,
      basisNumber: j['basis_number'] as String?,
      basisDate: j['basis_date'] == null ? null : _day(j['basis_date']),
      document: doc == null
          ? null
          : PermitDocument(doc['filename'] as String, doc['content_type'] as String, doc['size'] as int),
    );
  }
}

class Operator {
  const Operator({
    required this.id,
    required this.fullName,
    required this.employer,
    required this.hysterCardNumber,
    required this.isActive,
    required this.site,
    required this.qrIssuedAt,
    required this.permits,
    required this.permitStatus,
  });

  final int id;
  final String fullName;
  final EntryRef? employer;
  final String? hysterCardNumber;
  final bool isActive;
  final EntryRef site;
  final DateTime qrIssuedAt;

  /// Newest first.
  final List<PermitBrief> permits;

  /// The best of their permits; null with none.
  final PermitStatus? permitStatus;

  factory Operator.fromJson(Map<String, dynamic> j) => Operator(
    id: j['id'] as int,
    fullName: j['full_name'] as String,
    employer: j['employer'] == null ? null : EntryRef.fromJson((j['employer'] as Map).cast<String, dynamic>()),
    hysterCardNumber: j['hyster_card_number'] as String?,
    isActive: j['is_active'] as bool,
    site: EntryRef.fromJson((j['site'] as Map).cast<String, dynamic>()),
    qrIssuedAt: _date(j['qr_issued_at'])!,
    permits: [for (final p in j['permits'] as List) PermitBrief.fromJson((p as Map).cast<String, dynamic>())],
    permitStatus: j['permit_status'] == null ? null : PermitStatus.fromApi(j['permit_status'] as String),
  );
}

enum IncidentStatus {
  newReport('NEW', 'Nowe'),
  inProgress('IN_PROGRESS', 'W trakcie'),
  closed('CLOSED', 'Zamknięte');

  const IncidentStatus(this.api, this._label);

  final String api;
  final String _label;

  String get label => tr(_label);

  static IncidentStatus fromApi(String value) => IncidentStatus.values.firstWhere((s) => s.api == value);
}

/// A mark the server puts on a report for the administrator to look at.
String incidentFlagLabel(String flag) => switch (flag) {
  'OPERATOR_INACTIVE' => tr('Operator nieaktywny'),
  'NO_ACTIVE_PERMIT' => tr('Brak ważnego uprawnienia'),
  'TRUCK_TYPE_NOT_PERMITTED' => tr('Brak uprawnienia na ten typ wózka'),
  'MTH_LOWER_THAN_LAST' => tr('MTH niższe niż ostatnio'),
  'UNREGISTERED_OPERATOR' => tr('Osoba spoza rejestru operatorów'),
  _ => flag,
};

class IncidentPhotoRef {
  const IncidentPhotoRef({required this.id, required this.width, required this.height});

  final int id;
  final int width;
  final int height;

  factory IncidentPhotoRef.fromJson(Map<String, dynamic> j) =>
      IncidentPhotoRef(id: j['id'] as int, width: j['width'] as int, height: j['height'] as int);
}

class IncidentEvent {
  const IncidentEvent({
    required this.createdAt,
    required this.userName,
    required this.fromStatus,
    required this.toStatus,
    required this.comment,
  });

  final DateTime createdAt;

  /// Null for a report sent from an operator's phone.
  final String? userName;
  final IncidentStatus? fromStatus;
  final IncidentStatus toStatus;
  final String? comment;

  factory IncidentEvent.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map?;
    return IncidentEvent(
      createdAt: _date(j['created_at'])!,
      userName: user == null ? null : (user['full_name'] as String? ?? user['login'] as String),
      fromStatus: j['from_status'] == null ? null : IncidentStatus.fromApi(j['from_status'] as String),
      toStatus: IncidentStatus.fromApi(j['to_status'] as String),
      comment: j['comment'] as String?,
    );
  }
}

/// A report as lists and its page show it; [description] and [events] only on the page.
class Incident {
  const Incident({
    required this.id,
    required this.occurredAt,
    required this.type,
    required this.category,
    required this.truck,
    required this.truckStatus,
    required this.operator,
    required this.operatorName,
    required this.createdBy,
    required this.status,
    required this.flags,
    required this.outOfService,
    required this.mth,
    required this.photos,
    this.description,
    this.events = const [],
  });

  final int id;
  final DateTime occurredAt;
  final IncidentType type;
  final EntryRef category;

  /// The truck's number as [EntryRef.name].
  final EntryRef truck;
  final TruckStatus truckStatus;

  /// Null for a driver outside the register: [operatorName] then.
  final EntryRef? operator;
  final String? operatorName;

  /// Who entered it in the panel; null for a report from an operator's phone.
  final String? createdBy;
  final IncidentStatus status;
  final List<String> flags;
  final bool outOfService;
  final double? mth;
  final List<IncidentPhotoRef> photos;
  final String? description;
  final List<IncidentEvent> events;

  /// Whoever drove: the operator, or the name entered for someone outside the register.
  String get driver => operator?.name ?? operatorName ?? '?';

  factory Incident.fromJson(Map<String, dynamic> j) {
    final truck = (j['truck'] as Map).cast<String, dynamic>();
    final op = (j['operator'] as Map?)?.cast<String, dynamic>();
    final by = j['created_by'] as Map?;
    return Incident(
      id: j['id'] as int,
      occurredAt: _date(j['occurred_at'])!,
      type: IncidentType.fromApi(j['incident_type'] as String),
      category: EntryRef.fromJson((j['category'] as Map).cast<String, dynamic>()),
      truck: EntryRef(truck['id'] as int, truck['number'] as String),
      truckStatus: TruckStatus.fromApi(truck['status'] as String),
      operator: op == null ? null : EntryRef(op['id'] as int, op['full_name'] as String),
      operatorName: j['operator_name'] as String?,
      createdBy: by == null ? null : (by['full_name'] as String? ?? by['login'] as String),
      status: IncidentStatus.fromApi(j['status'] as String),
      flags: [for (final f in j['flags'] as List) f as String],
      outOfService: j['out_of_service'] as bool,
      mth: (j['mth'] as num?)?.toDouble(),
      photos: [for (final p in j['photos'] as List) IncidentPhotoRef.fromJson((p as Map).cast<String, dynamic>())],
      description: j['description'] as String?,
      events: [
        for (final e in (j['events'] as List?) ?? const []) IncidentEvent.fromJson((e as Map).cast<String, dynamic>()),
      ],
    );
  }
}
