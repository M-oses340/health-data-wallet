# Requirements Document

## Introduction

This document defines UI/UX improvement requirements for the Health Data Wallet Flutter app. The app already has working implementations of all five feature areas. The goal is to improve visual quality, interaction polish, accessibility, and user feedback across: the patient dashboard, researcher marketplace, data upload flow, consent management, and payments/dividends display. All improvements must remain consistent with the existing Material 3 design system and BLoC architecture.

## Glossary

- **Dashboard**: The `PatientShell` screen containing the bottom navigation bar and three tabs (Payments, Audit Trail, Upload).
- **Marketplace**: The researcher-facing `MarketplacePage` for discovering and selecting datasets.
- **Upload_Flow**: The `UploadDataPage` with Manual Entry and From File tabs.
- **Consent_Card**: A `_PaymentCard` widget that displays a payment and its associated "Revoke consent" action.
- **Payments_Page**: The `PaymentsPage` widget showing the earnings summary and individual payment cards.
- **Audit_Trail**: The `AuditTrailPage` showing a chronological timeline of data access events.
- **Skeleton_Loader**: An animated placeholder shown while data is loading.
- **Empty_State**: A widget shown when a list or page has no data to display.
- **Error_State**: A widget shown when a data fetch or action fails.
- **DID**: Decentralized Identifier — the unique identifier for a patient or researcher.
- **CID**: Content Identifier — the IPFS hash returned after a successful data upload.
- **ETH**: Ether — the cryptocurrency unit used for dividend payments.

---

## Requirements

### Requirement 1: Patient Dashboard Header and Navigation

**User Story:** As a patient, I want a clear, informative dashboard header and smooth navigation, so that I can quickly understand my account status and move between sections without confusion.

#### Acceptance Criteria

1. WHEN the Dashboard loads, THE Dashboard SHALL display the patient's name, truncated DID, and avatar (initials fallback) in the header.
2. WHEN the patient taps the truncated DID in the header, THE Dashboard SHALL copy the full DID to the clipboard and display a snackbar confirmation within 300ms.
3. WHEN the Payments tab has unread payments and the selected tab is not Payments, THE Dashboard SHALL display a numeric badge on the Payments navigation icon showing the payment count.
4. WHEN the patient taps the refresh icon in the header, THE Dashboard SHALL trigger a data reload and display a loading indicator on the active tab within 200ms.
5. WHEN the patient taps the logout icon, THE Dashboard SHALL display a confirmation dialog before signing out.
6. WHEN the Dashboard header is in its collapsed (pinned) state, THE Dashboard SHALL display the patient's name in the AppBar title area so the user always knows whose account is shown.
7. WHEN the avatar image fails to load, THE Dashboard SHALL display the patient's initials in the avatar container without layout shift.

---

### Requirement 2: Payments and Dividends Display

**User Story:** As a patient, I want a clear, readable payments screen with meaningful financial information, so that I can understand my earnings at a glance and manage individual payment records.

#### Acceptance Criteria

1. WHEN the Payments_Page is loading, THE Payments_Page SHALL display a Skeleton_Loader that matches the layout of the summary card and payment list items.
2. WHEN the Payments_Page has no payments, THE Payments_Page SHALL display an Empty_State with an icon, a primary message "No payments yet", and a secondary message explaining that earnings will appear here.
3. WHEN the Payments_Page encounters a fetch error, THE Payments_Page SHALL display an Error_State with a retry button that re-triggers the data load.
4. WHEN the Payments_Page is loaded with payments, THE Payments_Page SHALL display a summary card showing total ETH earned (formatted to 4 decimal places) and the total payment count.
5. WHEN a payment amount is displayed, THE Payments_Page SHALL show the ETH amount in a visually distinct color (green) with bold weight to indicate income.
6. WHEN a patient taps the contract ID on a Consent_Card, THE Consent_Card SHALL copy the full contract ID to the clipboard and display a snackbar confirmation.
7. WHEN a payment timestamp is displayed, THE Payments_Page SHALL format it as a human-readable local date and time string (e.g. "15 Jan 2025, 14:32").
8. WHEN the patient pulls down on the Payments_Page, THE Payments_Page SHALL trigger a refresh and show a RefreshIndicator.

---

### Requirement 3: Consent Management UI

**User Story:** As a patient, I want clear, safe controls for revoking consent, so that I can manage researcher access to my data with confidence and without accidental actions.

#### Acceptance Criteria

1. WHEN a patient taps "Revoke consent" on a Consent_Card, THE Consent_Card SHALL display a confirmation dialog with a clear description of the consequence before proceeding.
2. WHEN the patient confirms revocation, THE Consent_Card SHALL replace the "Revoke consent" button with a circular progress indicator for the duration of the API call.
3. WHEN consent revocation succeeds, THE Consent_Card SHALL display a success snackbar with a green background and reload the payments list.
4. WHEN consent revocation fails, THE Consent_Card SHALL display an error snackbar with a red background and re-enable the "Revoke consent" button.
5. WHEN a Consent_Card is in the revoking state, THE Consent_Card SHALL disable all interactive elements on that card to prevent duplicate requests.
6. WHEN a payment has no associated contract ID, THE Consent_Card SHALL hide the "Revoke consent" button entirely rather than showing a disabled state.

---

### Requirement 4: Data Upload Flow

**User Story:** As a patient, I want a guided, feedback-rich upload experience, so that I can confidently submit health data and know whether it succeeded or failed.

#### Acceptance Criteria

1. WHEN the Upload_Flow is displayed, THE Upload_Flow SHALL show two clearly labelled tabs: "Manual entry" and "From file", each with a descriptive icon.
2. WHEN the patient submits the manual entry form with all fields empty, THE Upload_Flow SHALL prevent submission and display an inline validation message indicating at least one metric must be provided.
3. WHEN the patient enters a non-numeric value in a metric field, THE Upload_Flow SHALL display an inline field-level error message immediately on form submission attempt.
4. WHEN a file upload succeeds, THE Upload_Flow SHALL display a success banner showing the first 20 characters of the CID followed by an ellipsis, with a green background.
5. WHEN a file upload fails, THE Upload_Flow SHALL display an error banner with the error message and a red background, and the previously selected file SHALL remain selected.
6. WHEN the patient picks a file in the From File tab, THE Upload_Flow SHALL display the file name, file size in KB, and a "Change file" option within the drop zone.
7. WHEN no file is selected in the From File tab, THE Upload_Flow SHALL disable the "Upload to Vault" button.
8. WHEN an upload is in progress, THE Upload_Flow SHALL replace the button icon with a circular progress indicator and disable the button to prevent duplicate submissions.
9. WHEN a manual entry upload succeeds, THE Upload_Flow SHALL clear all metric input fields and display the success banner.
10. WHEN the patient selects a category using the SegmentedButton, THE Upload_Flow SHALL visually highlight the selected segment and update the data type sent to the API accordingly.

---

### Requirement 5: Researcher Marketplace UI

**User Story:** As a researcher, I want a polished, efficient marketplace interface, so that I can discover relevant datasets quickly and understand their quality and coverage before requesting access.

#### Acceptance Criteria

1. WHEN the Marketplace loads for the first time, THE Marketplace SHALL display a search prompt state with an icon and instructional text guiding the researcher to search.
2. WHEN the Marketplace is loading search results, THE Marketplace SHALL display a Skeleton_Loader with placeholder cards instead of a spinner to maintain layout stability.
3. WHEN a search returns no results, THE Marketplace SHALL display an Empty_State with an icon, a "No datasets found" message, and a suggestion to try different search terms or filters.
4. WHEN the Marketplace encounters a search error, THE Marketplace SHALL display an Error_State with the error message and a retry button.
5. WHEN a researcher selects a data type filter chip, THE Marketplace SHALL visually highlight the selected chip and immediately trigger a new search with the updated filter.
6. WHEN a dataset card is displayed, THE Marketplace SHALL show the category, data type, record count, minimum quality score, and available computation methods.
7. WHEN a researcher taps "Use dataset" on a dataset card, THE Marketplace SHALL navigate to the Submit Request page with the dataset fields pre-filled.
8. WHEN the search text field is submitted via keyboard, THE Marketplace SHALL trigger the search without requiring the researcher to tap the Search button.
9. WHEN available computation methods are displayed on a dataset card, THE Marketplace SHALL render each method as a distinct pill/chip with a secondary container color.
10. WHEN the record count on a dataset card is zero, THE Marketplace SHALL display "0 records" without hiding or omitting the stat badge.

---

### Requirement 6: Audit Trail UI

**User Story:** As a patient, I want a clear, readable audit trail, so that I can understand what has happened to my data over time and identify any unexpected access.

#### Acceptance Criteria

1. WHEN the Audit_Trail is loading, THE Audit_Trail SHALL display a Skeleton_Loader with timeline-shaped placeholders (circle + card) matching the real layout.
2. WHEN the Audit_Trail has no entries, THE Audit_Trail SHALL display an Empty_State with an icon, a "No audit entries yet" message, and a secondary message explaining that data activity will appear here.
3. WHEN the Audit_Trail encounters a fetch error, THE Audit_Trail SHALL display an Error_State with a retry button.
4. WHEN an audit entry is displayed, THE Audit_Trail SHALL show the event type as a color-coded chip, the contract ID (truncated, copyable), and the formatted local timestamp.
5. WHEN a patient taps a contract ID in an audit entry, THE Audit_Trail SHALL copy the full contract ID to the clipboard and display a snackbar confirmation.
6. WHEN the event type is CONSENT_GRANTED, THE Audit_Trail SHALL render the event chip in green; CONSENT_REVOKED in red; DIVIDEND_PAID in blue; DATA_ACCESSED in purple; DATA_UPLOADED in indigo; and unknown types in grey.
7. WHEN the patient pulls down on the Audit_Trail, THE Audit_Trail SHALL trigger a refresh and show a RefreshIndicator.
8. WHEN the Audit_Trail has entries, THE Audit_Trail SHALL render a vertical connecting line between consecutive timeline entries to visually indicate chronological order.

---

### Requirement 7: Accessibility and Interaction Polish

**User Story:** As any user of the app, I want all interactive elements to be accessible and provide clear feedback, so that the app is usable regardless of ability or device.

#### Acceptance Criteria

1. THE App SHALL ensure all interactive icon buttons include a Semantics label or tooltip describing their action (e.g. "Refresh data", "Sign out", "Copy DID").
2. WHEN a copyable text element is tapped, THE App SHALL provide haptic feedback in addition to the snackbar confirmation.
3. THE App SHALL ensure all text meets a minimum contrast ratio of 4.5:1 against its background as defined by WCAG 2.1 AA for normal text.
4. WHEN a destructive action button (e.g. "Revoke consent") is displayed, THE App SHALL use a visually distinct color (red) and include a warning icon to signal the destructive nature.
5. WHEN any snackbar is displayed, THE App SHALL ensure it is dismissed automatically after no more than 4 seconds.
6. WHEN the app is in a loading state on any page, THE App SHALL prevent user interaction with data-dependent controls until loading completes.
