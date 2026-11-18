import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/audit/audit_repository.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/auth_repository.dart';
import '../features/dictionaries/dictionaries_repository.dart';
import '../features/operators/operators_repository.dart';
import '../features/permits/permits_repository.dart';
import '../features/trucks/trucks_repository.dart';
import '../features/users/users_repository.dart';
import 'api_client.dart';
import 'token_store.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(tokenStoreProvider)));

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider)),
);

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) =>
      AuthController(ref.watch(authRepositoryProvider), ref.watch(apiClientProvider), ref.watch(tokenStoreProvider)),
);

final usersRepositoryProvider = Provider<UsersRepository>((ref) => UsersRepository(ref.watch(apiClientProvider)));

final dictionariesRepositoryProvider = Provider<DictionariesRepository>(
  (ref) => DictionariesRepository(ref.watch(apiClientProvider)),
);

final trucksRepositoryProvider = Provider<TrucksRepository>((ref) => TrucksRepository(ref.watch(apiClientProvider)));

final operatorsRepositoryProvider = Provider<OperatorsRepository>(
  (ref) => OperatorsRepository(ref.watch(apiClientProvider)),
);

final permitsRepositoryProvider = Provider<PermitsRepository>((ref) => PermitsRepository(ref.watch(apiClientProvider)));

final auditRepositoryProvider = Provider<AuditRepository>((ref) => AuditRepository(ref.watch(apiClientProvider)));
