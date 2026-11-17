# GARAZ app

Flutter (web + Android) dla systemu GARAZ — rejestr uprawnień operatorów i zdarzeń wózków widłowych.
Backend: repozytorium `GARAZ` (FastAPI), które serwuje build web pod `/app/`.

Na razie minimalny panel do testowania backendu: logowanie loginem (np. z WMS), użytkownicy panelu,
dziennik zmian, moje konto (zmiana hasła, wylogowanie).

## Struktura

- `lib/core/` — konfiguracja, klient API (Dio, odświeżanie tokenów single-flight), tokeny, modele, router, motyw.
- `lib/features/<obszar>/` — repozytorium (wywołania API) + ekrany.

## Uruchomienie lokalne (z backendem w Dockerze)

1. W `../GARAZ`: skopiuj `.env.sample` → `.env`, ustaw `ADMIN_BOOTSTRAP_PASSWORD`, potem `docker compose up -d --build`.
2. Tutaj zbuduj web i wrzuć go do backendu (restartuje `garaz-api`):

```bash
./scripts/build_web_local.sh
```

3. Otwórz http://localhost:8000/app/ i zaloguj się jako `admin` z hasłem z `.env`.

Szybsza pętla podczas pracy nad UI (hot reload; backend musi mieć `http://localhost:<port>` w `ALLOWED_ORIGINS`):

```bash
flutter run -d edge --web-port 5000 --dart-define=API_BASE_URL=http://localhost:8000/api
```

Android (emulator widzi hosta jako `10.0.2.2`, to domyślny adres):

```bash
flutter run -d emulator-5554
```

## Sprawdzenia

```bash
flutter analyze
```

```bash
flutter test
```
