# VYOM Intelligent 2

VYOM is an offline-first Flutter application for local business operators who deliver products to customers on a recurring basis. It records customers, products, customer defaults, daily deliveries, historical prices, payments, and customer ledger balances without requiring an online service.

Repository: [Anmol-dev21/vyom](https://github.com/Anmol-dev21/vyom)

Detailed handover: [PROJECT_HANDOVER.md](PROJECT_HANDOVER.md)

## Current State

The checked-out source supports:

- first-run language selection and business-profile setup
- product and customer workflows, with soft deactivation
- customer-product default quantities
- daily distribution drafts, atomic batch save, confirmation, and read-only confirmed days
- integer quantity conversion for litre/kg/piece-style units
- effective-dated product pricing in paise
- confirmed-distribution price and line-amount snapshots
- RECEIVED and GIVEN customer transactions
- customer ledger summaries and chronological customer ledger detail with DR/CR and running balance

The repository is a development codebase, not a production release. The dashboard contains action cards for areas whose routes exist, but not every card has fully verified end-to-end behavior. Monthly billing, invoices, export/printing, messaging, synchronization, licensing, backup, and other product-scope integrations remain unimplemented or unverified; see [PROJECT_HANDOVER.md](PROJECT_HANDOVER.md).

## Technology and Architecture

- Flutter 3.47.1 and Dart 3.13.1 were verified locally on 2026-10-28.
- Material 3 UI with `go_router` navigation.
- Riverpod providers for database, repositories, and asynchronous screen data.
- Drift over SQLite for local persistence and migrations.
- `path_provider` chooses the application documents directory; a system-temp fallback is used when the path provider is unavailable.
- `sqlite3_flutter_libs` supplies SQLite runtime support.
- Money is stored as integer paise. Quantities are stored as integer base units.

The main flow is:

`main.dart` -> `ProviderScope` -> `VyomApp` -> `GoRouter` -> feature screens -> Riverpod providers -> repositories/services -> `AppDatabase`.

## Repository Layout

```text
lib/
  main.dart                         Application entry point
  app/                              App widget, routes, theme
  core/                             Shared application state types
  database/                         Drift schema, repositories, ledger service
  features/                         Onboarding and business workflows/screens
  utils/                            Quantity conversion helpers
test/                               Repository, service, widget, and regression tests
android/, ios/, web/, linux/,       Flutter platform projects
macos/, windows/                    Flutter platform projects
```

Important database modules include `app_database.dart`, generated `app_database.g.dart`, repositories for products/customers/distributions/transactions/pricing, and `customer_ledger_service.dart`.

## Prerequisites

Install Flutter with Dart, then run `flutter doctor -v`. The verified local toolchain is Flutter 3.47.1, Dart 3.13.1, and SDK constraint `^3.13.1`.

For Android development, install Android Studio and an Android SDK, then make sure `flutter doctor -v` reports a usable Android toolchain. The checked environment does not have an Android SDK, so Android builds were not verified.

For Windows desktop development, install Visual Studio with the Desktop development with C++ workload. The checked environment does not have Visual Studio, so Windows builds were not verified. Chrome is available for web execution, but web behavior is not covered by the repository test suite.

## Setup and Run

From the repository root:

```powershell
flutter pub get
flutter run
```

Choose an available device with `flutter devices`, or specify one:

```powershell
flutter run -d chrome
```

The app starts at `/splash`. New installations proceed through language selection and business-profile setup before reaching the dashboard.

## Development Commands

```powershell
dart format lib test
dart run build_runner build
flutter analyze
flutter test
```

`build_runner` regenerates Drift code from `lib/database/app_database.dart`. Do not hand-edit `lib/database/app_database.g.dart`. Run the generator after schema changes and review the generated diff.

The previous documentation validation recorded a passing formatting, code-generation, analysis, and 172-test run on 2026-10-28. During this documentation audit, a fresh `flutter analyze` and `flutter test` also passed with 172 tests. The test run prints existing Drift warnings about multiple in-memory `AppDatabase` instances in migration/widget tests; these warnings do not fail the suite.

## Database Notes

`AppDatabase` currently declares schema version 5. It stores app settings, business profiles, products, customers, customer-product assignments, daily distributions, distribution items, transactions, and product-price periods. Foreign keys are enabled in `beforeOpen`. Important uniqueness constraints include one customer/product assignment, one customer/date distribution, one product/distribution item, and one product/effective-from price period.

Migrations add products/customers/assignments at version 2, distributions at version 3, transactions and transaction indexes at version 4, and price snapshot columns/product prices at version 5. Existing migration tests cover preserving data through the v2-to-v3 path; version 4 and 5 migration coverage should remain a release requirement.

Confirmed distribution items retain `unitPricePaise` and `lineAmountPaise`. Ledger calculations use those stored values instead of current product prices. Draft distributions do not affect the ledger.

## Supported Routes and Workflows

The router defines `/splash`, `/language`, `/business-setup`, `/dashboard`, `/products`, `/customers`, `/daily-update`, `/transactions`, `/reports`, and `/reports/customer/:customerId`. The dashboard exposes navigation for customer management and daily updates, plus action cards for transactions and reports.

The reports flow supports selecting a date range, viewing customer totals, and opening a customer detail statement. The detail statement shows distribution charges, received payments, given payments, notes, DR/CR, and a running balance.

## Limitations and Unverified Areas

- No backend, API endpoints, authentication, synchronization, or conflict handling exists.
- No monthly billing or invoice model/generator exists.
- No PDF, spreadsheet, Bluetooth, or general printing integration exists.
- No WhatsApp integration or delivery-status reporting exists.
- Hindi is selectable and persisted, but the UI is not fully localized; most strings are English.
- Voice commands, suppliers/purchases, Excel import, licensing, backup/restore, and production telemetry are absent.
- Android APK installation/release signing and platform builds need verification in a configured environment.

See [PROJECT_HANDOVER.md](PROJECT_HANDOVER.md) for the evidence-based status matrix, business rules, risks, and proposed next work.
