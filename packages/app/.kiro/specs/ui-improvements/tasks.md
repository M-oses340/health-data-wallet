# Implementation Plan: UI Improvements

## Overview

Incremental UI/UX improvements across five areas of the Health Data Wallet Flutter app. All changes are in the presentation layer — no BLoC, API, or routing changes required. Tasks are ordered so each builds on the previous, with property and unit tests placed close to the implementation they validate.

## Tasks

- [x] 1. Improve Patient Dashboard header and navigation (`patient_shell.dart`)
  - [x] 1.1 Add collapsed AppBar title and logout confirmation dialog
    - Set `title: Text(auth.name ?? 'Patient Wallet')` on `SliverAppBar` so the name is visible when collapsed
    - Wrap the logout `IconButton` `onPressed` to show an `AlertDialog` confirmation before dispatching `SignOut`
    - _Requirements: 1.5, 1.6_
  - [x] 1.2 Add Semantics labels to header icon buttons and haptic feedback to DID copy
    - Wrap refresh `IconButton` with `Semantics(label: 'Refresh data')`
    - Wrap logout `IconButton` with `Semantics(label: 'Sign out')`
    - Add `HapticFeedback.lightImpact()` inside the DID copy `GestureDetector.onTap`
    - _Requirements: 1.2, 7.1, 7.2_
  - [ ]* 1.3 Write widget tests for dashboard header
    - Test collapsed title shows patient name
    - Test logout tap shows confirmation dialog before sign-out
    - Test DID copy tap triggers clipboard write
    - _Requirements: 1.1, 1.5, 1.6_

- [x] 2. Improve Payments page states and formatting (`payments_page.dart`)
  - [x] 2.1 Add retry button to error state and improve timestamp formatting
    - Replace `_errorView` with a version that includes a `FilledButton('Retry')` dispatching `LoadPatientData(auth.did)`
    - Import `package:intl/intl.dart` and replace raw `.toString().substring(0,16)` timestamp formatting with `DateFormat('d MMM yyyy, HH:mm').format(...)`
    - Cap all snackbar `duration` to `Duration(seconds: 4)`
    - _Requirements: 2.3, 2.7, 7.5_
  - [ ]* 2.2 Write property test for ETH total formatting (Property 2)
    - **Property 2: ETH total formatting is sum-accurate**
    - **Validates: Requirements 2.4**
    - Generate random lists of payment maps with numeric amounts; assert displayed total equals sum formatted to 4 decimal places
    - `// Feature: ui-improvements, Property 2: ETH total formatting is sum-accurate`
  - [ ]* 2.3 Write property test for timestamp formatting (Property 3)
    - **Property 3: Timestamp formatting produces valid date strings**
    - **Validates: Requirements 2.7**
    - Generate random Unix timestamps; assert formatted string matches `d MMM yyyy, HH:mm` pattern and is not "—"
    - `// Feature: ui-improvements, Property 3: Timestamp formatting produces valid date strings`
  - [ ]* 2.4 Write widget tests for payments page states
    - Test `PatientLoading` renders skeleton loader
    - Test `PatientLoaded` with empty list renders empty state with correct messages
    - Test `PatientError` renders error state with retry button
    - _Requirements: 2.1, 2.2, 2.3_

- [x] 3. Improve Consent Management card (`payments_page.dart` — `_PaymentCard`)
  - [x] 3.1 Hide revoke button when contractId is null and add AbsorbPointer during revoking
    - In `_PaymentCard.build`, wrap the revoke button section in `if (contractId != '—' && widget.payment['contractId'] != null)`
    - Wrap the entire card `Padding` content in `AbsorbPointer(absorbing: _revoking, child: ...)` to disable all interactions during revoke
    - Add `Semantics(label: 'Revoke consent for contract $shortId')` to the revoke `OutlinedButton`
    - _Requirements: 3.5, 3.6, 7.1_
  - [ ]* 3.2 Write property test for revoke button visibility (Property 4)
    - **Property 4: Revoke button is hidden when contractId is absent**
    - **Validates: Requirements 3.6**
    - Generate payment maps with and without `contractId`; assert button absent when null, present when non-null
    - `// Feature: ui-improvements, Property 4: Revoke button is hidden when contractId is absent`
  - [ ]* 3.3 Write widget tests for consent revoke flow
    - Test tap shows confirmation dialog
    - Test confirm shows progress indicator
    - Test success shows green snackbar and reloads
    - Test failure shows red snackbar and re-enables button
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [ ] 4. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Improve Data Upload flow (`upload_data_page.dart`)
  - [x] 5.1 Add cross-field empty validation and fix error state persistence
    - In `_ManualEntryTabState._upload()`, add a check before `_formKey.currentState!.validate()`: if all three controllers are empty, set `_error = 'Please enter at least one metric value.'` and return early without calling the API
    - Verify `_pickedFile` is NOT cleared in the error path of `_FilePickerTabState._upload()` (it should remain set)
    - Add `HapticFeedback.lightImpact()` on successful upload in both tabs
    - _Requirements: 4.2, 4.5, 7.2_
  - [ ]* 5.2 Write property test for empty form validation (Property 5)
    - **Property 5: Empty form submission is always rejected**
    - **Validates: Requirements 4.2**
    - For all combinations of empty/non-empty fields where all are empty, assert no API call is made and error state is set
    - `// Feature: ui-improvements, Property 5: Empty form submission is always rejected`
  - [ ]* 5.3 Write property test for non-numeric field validator (Property 6)
    - **Property 6: Non-numeric metric input always produces a field error**
    - **Validates: Requirements 4.3**
    - Generate random non-numeric strings; assert the validator function returns a non-null, non-empty string
    - `// Feature: ui-improvements, Property 6: Non-numeric metric input always produces a field error`
  - [ ]* 5.4 Write widget tests for upload flow states
    - Test upload button disabled when no file selected
    - Test button shows progress indicator during upload
    - Test success banner shows CID prefix and clears fields
    - Test error banner shows message and file remains selected
    - _Requirements: 4.4, 4.5, 4.7, 4.8, 4.9_

- [x] 6. Improve Researcher Marketplace (`marketplace_page.dart`)
  - [x] 6.1 Replace loading spinner with skeleton cards and improve empty/error states
    - Replace `CircularProgressIndicator` in the `ResearcherLoading` branch with a `_MarketplaceSkeletonList` widget (3 placeholder cards matching `_DatasetCard` layout: 44px circle + two text lines + two badge rows)
    - Update `_EmptySearch` to add a subtitle: `'Try a different category or data type filter.'`
    - Add a retry `FilledButton` to the `ResearcherError` branch that re-dispatches `SearchDatasets` with the current `_categoryCtrl.text` and `_selectedType`
    - _Requirements: 5.2, 5.3, 5.4_
  - [x] 6.2 Auto-search on filter chip tap and add Semantics to chips
    - In `_TypeChip.onTap` callbacks, call `_search()` after `setState` so selecting a chip immediately triggers a search
    - Wrap each `_TypeChip` `GestureDetector` with `Semantics(label: 'Filter by $label', button: true)`
    - _Requirements: 5.5, 7.1_
  - [ ]* 6.3 Write property test for dataset card rendering (Property 7)
    - **Property 7: Dataset card renders all required fields**
    - **Validates: Requirements 5.6, 5.9, 5.10**
    - Generate random dataset maps; assert rendered card contains category, dataType, recordCount, quality score, and each method as a chip; include zero-record-count edge case
    - `// Feature: ui-improvements, Property 7: Dataset card renders all required fields`
  - [ ]* 6.4 Write widget tests for marketplace states
    - Test initial state shows search prompt
    - Test `ResearcherLoading` shows skeleton (not spinner)
    - Test `DatasetsLoaded` with empty list shows empty state with suggestion text
    - Test `ResearcherError` shows error state with retry button
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [x] 7. Improve Audit Trail page (`audit_trail_page.dart`)
  - [x] 7.1 Add retry button to error state and improve timestamp formatting
    - Replace the inline error `Column` with a version that includes a `FilledButton('Retry')` dispatching `LoadPatientData(auth.did)`
    - Apply `DateFormat('d MMM yyyy, HH:mm')` to audit entry timestamps (same as payments)
    - Add `HapticFeedback.lightImpact()` to the contract ID copy `GestureDetector`
    - Cap snackbar duration to `Duration(seconds: 4)`
    - _Requirements: 6.3, 6.4, 6.5, 7.2, 7.5_
  - [ ]* 7.2 Write property test for audit entry rendering (Property 8)
    - **Property 8: Audit entry renders event chip, contract ID, and timestamp**
    - **Validates: Requirements 6.4**
    - Generate random audit entry maps; assert rendered `_TimelineEntry` contains event type text, truncated contract ID, and formatted timestamp
    - `// Feature: ui-improvements, Property 8: Audit entry renders event chip, contract ID, and timestamp`
  - [ ]* 7.3 Write property test for event type color mapping (Property 9)
    - **Property 9: Event type color mapping is exhaustive for known types**
    - **Validates: Requirements 6.6**
    - Test all 7 known event type strings return the specified colors; test random unknown strings return grey
    - `// Feature: ui-improvements, Property 9: Event type color mapping is exhaustive for known types`
  - [ ]* 7.4 Write property test for timeline connecting lines (Property 10)
    - **Property 10: Timeline connecting lines equal entries minus one**
    - **Validates: Requirements 6.8**
    - Generate lists of N entries (N: 2–50); assert the rendered timeline contains exactly N-1 connecting line widgets
    - `// Feature: ui-improvements, Property 10: Timeline connecting lines equal entries minus one`
  - [ ]* 7.5 Write widget tests for audit trail states
    - Test `PatientLoading` renders skeleton timeline
    - Test `PatientLoaded` with empty list renders empty state with both messages
    - Test `PatientError` renders error state with retry button
    - _Requirements: 6.1, 6.2, 6.3_

- [ ] 8. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Accessibility and interaction polish pass
  - [x] 9.1 Add remaining Semantics labels and verify snackbar durations
    - Audit all `IconButton` usages across all five pages and add `tooltip` or `Semantics(label: ...)` where missing
    - Search all `SnackBar(` usages and ensure every one has `duration: const Duration(seconds: 4)` or less
    - Add `Semantics(label: 'Revoke consent')` to the destructive button in `_PaymentCard` if not already done in task 3.1
    - _Requirements: 7.1, 7.4, 7.5_
  - [ ]* 9.2 Write property test for snackbar duration (Property 11)
    - **Property 11: Snackbar duration never exceeds 4 seconds**
    - **Validates: Requirements 7.5**
    - For each snackbar creation site in the codebase, assert `duration <= Duration(seconds: 4)` via static inspection or parameterized test
    - `// Feature: ui-improvements, Property 11: Snackbar duration never exceeds 4 seconds`
  - [ ]* 9.3 Write property test for badge count (Property 1)
    - **Property 1: Payment badge count reflects payment list size**
    - **Validates: Requirements 1.3**
    - Generate random payment lists of size 1–999; render `PatientShell` with active tab != Payments; assert badge label equals list length
    - `// Feature: ui-improvements, Property 1: Payment badge count reflects payment list size`

- [ ] 10. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- The `intl` package is already available as a transitive Flutter dependency — no `pubspec.yaml` changes needed
- All property tests should run a minimum of 100 generated input combinations
- Each property test comment references the design document property number for traceability
- Unit tests use `flutter_test` and `bloc_test` packages already present in `dev_dependencies`
