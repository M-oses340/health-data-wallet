# Design Document: UI Improvements

## Overview

This document describes the technical design for UI/UX improvements across five areas of the Health Data Wallet Flutter app. All changes are additive refinements to existing widgets — no BLoC logic, API contracts, or routing changes are required. The improvements target visual hierarchy, interaction polish, loading/empty/error states, and accessibility.

The app uses Flutter with Material 3, BLoC for state management, and Dart. All new widgets follow the existing patterns: stateless where possible, stateful only when local animation or form state is needed.

---

## Architecture

The improvements are purely in the presentation layer. The BLoC states (`PatientLoaded`, `PatientLoading`, `PatientError`, `DatasetsLoaded`, etc.) are already well-structured and require no changes. Each improvement maps to one or more widget files:

```
packages/app/lib/features/
├── patient/
│   └── pages/
│       ├── patient_shell.dart       ← Req 1: Dashboard header + nav
│       ├── payments_page.dart       ← Req 2, 3: Payments + consent
│       ├── audit_trail_page.dart    ← Req 6: Audit trail
│       └── upload_data_page.dart   ← Req 4: Upload flow
└── researcher/
    └── pages/
        └── marketplace_page.dart   ← Req 5: Marketplace
```

Shared accessibility helpers (haptic feedback, semantic labels) are applied inline at the call site — no new shared library file is needed given the small scope.

---

## Components and Interfaces

### 1. Patient Dashboard Header (`patient_shell.dart`)

**Changes:**
- Add `Semantics` wrappers with labels to the refresh and logout `IconButton`s.
- Add a logout confirmation `AlertDialog` before calling `SignOut`.
- In the collapsed AppBar state, show `auth.name` as the `title` of `SliverAppBar` (currently absent).
- Wrap the DID copy `GestureDetector` with `HapticFeedback.lightImpact()`.

**Collapsed title approach:**
```dart
SliverAppBar(
  title: Text(auth.name ?? 'Patient Wallet'), // shown when collapsed
  expandedHeight: 120,
  pinned: true,
  flexibleSpace: FlexibleSpaceBar(...), // existing gradient header
)
```

### 2. Payments Page (`payments_page.dart`)

**Changes:**
- Improve `_errorView` to include a retry `FilledButton` that dispatches `LoadPatientData`.
- Improve timestamp formatting: replace raw `.toString().substring(0,16)` with `DateFormat('d MMM yyyy, HH:mm')` from `intl` package (already a transitive dependency via Flutter).
- Wrap contract ID copy tap with `HapticFeedback.lightImpact()`.
- Ensure snackbar duration is capped at 4 seconds.

**Timestamp formatting:**
```dart
import 'package:intl/intl.dart';
final _dateFmt = DateFormat('d MMM yyyy, HH:mm');
// usage:
final dateStr = ts != null
    ? _dateFmt.format(DateTime.fromMillisecondsSinceEpoch((ts as int) * 1000).toLocal())
    : '—';
```

### 3. Consent Management (`payments_page.dart` — `_PaymentCard`)

**Changes:**
- Hide "Revoke consent" button entirely when `contractId` is null (currently shows a disabled state implicitly).
- Add `Semantics` label to the revoke button.
- Disable all card interactions during `_revoking` state (wrap card content in `AbsorbPointer` when `_revoking`).
- Snackbar duration capped at `Duration(seconds: 4)`.

### 4. Upload Flow (`upload_data_page.dart`)

**Changes:**
- Add cross-field validation: if all three metric fields are empty on submit, show a banner error "Please enter at least one metric value."
- Wrap upload button `Semantics` with label.
- Ensure error banner persists when file remains selected after a failed upload (already partially correct — verify `_pickedFile` is not cleared on error).
- Add `HapticFeedback.lightImpact()` on successful upload.

**Cross-field validation in `_ManualEntryTabState._upload()`:**
```dart
final allEmpty = _heartRateCtrl.text.isEmpty &&
    _spo2Ctrl.text.isEmpty &&
    _tempCtrl.text.isEmpty;
if (allEmpty) {
  setState(() => _error = 'Please enter at least one metric value.');
  return;
}
```

### 5. Marketplace (`marketplace_page.dart`)

**Changes:**
- Replace `CircularProgressIndicator` loading state with a `_SkeletonList` (3 placeholder cards) matching the `_DatasetCard` layout.
- Improve `_EmptySearch` to include a suggestion subtitle: "Try a different category or data type filter."
- Improve `_errorView` to include a retry button that re-dispatches the last search.
- Auto-search when a filter chip is tapped (already partially done — verify `_search()` is called in `onTap`).
- Add `Semantics` labels to filter chips.

**Skeleton card for marketplace:**
```dart
class _MarketplaceSkeletonCard extends StatelessWidget {
  // Matches _DatasetCard layout: 44px circle + two lines + two badges + method chips row
}
```

### 6. Audit Trail (`audit_trail_page.dart`)

**Changes:**
- Improve `_errorView` (currently inline) to include a retry button.
- Wrap contract ID copy tap with `HapticFeedback.lightImpact()`.
- Improve timestamp formatting using `DateFormat('d MMM yyyy, HH:mm')`.
- Ensure snackbar duration is 4 seconds.

---

## Data Models

No new data models are introduced. All improvements operate on the existing dynamic maps returned by `ApiClient` and the existing BLoC states. The only data-adjacent change is timestamp formatting, which is a pure presentation transformation:

```
int (Unix seconds) → DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal() → DateFormat string
```

The `intl` package's `DateFormat` is used for locale-aware formatting. It is already available as a transitive dependency of Flutter's `flutter_localizations`.

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*


### Property 1: Payment badge count reflects payment list size

*For any* `PatientLoaded` state with a non-empty payments list, when the active tab is not the Payments tab, the badge label on the Payments navigation icon should display the exact count of payments in the list.

**Validates: Requirements 1.3**

---

### Property 2: ETH total formatting is sum-accurate

*For any* list of payment maps each containing a numeric `amount` field, the total displayed in the summary card should equal the arithmetic sum of all amounts formatted to exactly 4 decimal places.

**Validates: Requirements 2.4**

---

### Property 3: Timestamp formatting produces valid date strings

*For any* valid Unix timestamp integer (seconds since epoch), the formatted output should be a non-empty string matching the pattern `d MMM yyyy, HH:mm` (e.g. "15 Jan 2025, 14:32") and should not be the fallback "—".

**Validates: Requirements 2.7**

---

### Property 4: Revoke button is hidden when contractId is absent

*For any* payment map that does not contain a `contractId` key (or where `contractId` is null), the rendered `_PaymentCard` widget tree should not contain a "Revoke consent" button.

**Validates: Requirements 3.6**

---

### Property 5: Empty form submission is always rejected

*For any* manual entry form state where all three metric fields (heart rate, SpO₂, temperature) are empty strings, attempting to submit should not invoke the API and should set an error message in the widget state.

**Validates: Requirements 4.2**

---

### Property 6: Non-numeric metric input always produces a field error

*For any* string that cannot be parsed by `double.tryParse` (i.e. returns null), the metric field validator should return a non-null, non-empty error string.

**Validates: Requirements 4.3**

---

### Property 7: Dataset card renders all required fields

*For any* dataset map containing `category`, `dataType`, `recordCount`, `minQualityScore`, and `availableMethods` fields, the rendered `_DatasetCard` widget tree should contain text nodes for each of those values, and each method string should appear as a separate chip widget.

**Validates: Requirements 5.6, 5.9, 5.10** (edge case: zero record count must still render)

---

### Property 8: Audit entry renders event chip, contract ID, and timestamp

*For any* audit entry map containing `eventType`, `contractId`, and `timestamp` fields, the rendered `_TimelineEntry` widget tree should contain the event type text (formatted), the truncated contract ID text, and the formatted timestamp text.

**Validates: Requirements 6.4**

---

### Property 9: Event type color mapping is exhaustive for known types

*For any* known event type string from the set {CONSENT_GRANTED, CONSENT_REVOKED, DIVIDEND_PAID, DATA_ANONYMIZED, DATA_ACCESSED, COMPUTATION_COMPLETED, DATA_UPLOADED}, the `_eventConfig` function should return a color that matches the specified mapping (green, red, blue, orange, purple, teal, indigo respectively). For any unknown string, it should return grey.

**Validates: Requirements 6.6**

---

### Property 10: Timeline connecting lines equal entries minus one

*For any* audit trail with N entries where N > 1, the rendered timeline should contain exactly N-1 connecting line container widgets between entries.

**Validates: Requirements 6.8**

---

### Property 11: Snackbar duration never exceeds 4 seconds

*For any* snackbar created in the app (copy confirmations, upload success/error, revoke success/error), the `duration` parameter should be less than or equal to `Duration(seconds: 4)`.

**Validates: Requirements 7.5**

---

## Error Handling

| Scenario | Current behavior | Improved behavior |
|---|---|---|
| `PatientError` on Payments/Audit | Shows icon + message, no retry | Add `FilledButton('Retry')` that dispatches `LoadPatientData` |
| `ResearcherError` on Marketplace | Shows icon + message, no retry | Add `FilledButton('Retry')` that re-dispatches last `SearchDatasets` |
| Revoke consent API failure | Red snackbar, button re-enabled | Same, plus `AbsorbPointer` lifted so card is interactive again |
| Upload API failure | Red banner shown | Banner shown, file selection preserved (already correct) |
| Avatar image load failure | Initials shown | Same — already handled via `errorBuilder` |
| All-empty manual entry form | No validation, API called with empty payload | Inline error banner, API call blocked |

All error states include a retry mechanism. Error messages are surfaced from the exception's `toString()` — no changes to the API error contract are needed.

---

## Testing Strategy

### Dual Testing Approach

Both unit tests and property-based tests are used. Unit tests cover specific examples, state transitions, and interaction flows. Property-based tests verify universal correctness rules across generated inputs.

### Unit Tests (widget tests)

Located in `packages/app/test/widgets/`. Each page gets a test file:

- `patient_shell_test.dart` — header rendering, logout dialog, badge visibility
- `payments_page_test.dart` — loading/empty/error states, summary card, timestamp display
- `payment_card_test.dart` — revoke flow (confirm → loading → success/error), hide button when no contractId
- `upload_data_page_test.dart` — tab structure, file picker state, upload button disabled state, success/error banners
- `marketplace_page_test.dart` — initial state, loading skeleton, empty/error states, chip selection
- `audit_trail_page_test.dart` — loading/empty/error states, timeline entry rendering, connecting lines

### Property-Based Tests

Located in `packages/app/test/properties/`. Use the `dart_test` framework with manual property runners (Flutter does not have a mature PBT library; properties are implemented as parameterized tests with generated inputs using `dart:math` Random and lists of representative values).

For each property, run a minimum of 100 generated input combinations.

Tag format in test comments: `// Feature: ui-improvements, Property N: <property_text>`

| Property | Test file | Generator |
|---|---|---|
| P1: Badge count | `patient_shell_property_test.dart` | Random int 1–999 |
| P2: ETH sum formatting | `payments_property_test.dart` | Random list of double amounts |
| P3: Timestamp formatting | `payments_property_test.dart` | Random Unix timestamps |
| P4: Revoke button hidden | `payment_card_property_test.dart` | Payment maps with/without contractId |
| P5: Empty form rejection | `upload_property_test.dart` | Always-empty field combinations |
| P6: Non-numeric validator | `upload_property_test.dart` | Random non-numeric strings |
| P7: Dataset card fields | `marketplace_property_test.dart` | Random dataset maps |
| P8: Audit entry rendering | `audit_trail_property_test.dart` | Random audit entry maps |
| P9: Event type color mapping | `audit_trail_property_test.dart` | All 7 known types + random unknown strings |
| P10: Timeline line count | `audit_trail_property_test.dart` | Random lists of N entries (N: 2–50) |
| P11: Snackbar duration | `snackbar_property_test.dart` | All snackbar call sites (static analysis) |
