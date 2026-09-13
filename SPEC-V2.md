# BookScanner Version 2.0 Feature Specification

**Document status:** Draft v2.0  
**Platforms:** iOS and Android  
**Product type:** Specialized scanning expansion  
**Depends on:** [BookScanner Version 1 specification](./SPEC-V1.md)

## 1. Research input and product direction

This section translates a stakeholder-provided AI opportunity analysis into a Version 2.0 feature delta. The analysis advises against competing only as another general-purpose scanner and identifies stronger specialized opportunities: receipt/expense automation, invoice extraction, school-assignment study tools, automatic ID redaction, verifiable offline privacy, table-to-spreadsheet conversion, support for African documents, and target-size WhatsApp sharing.

Version 2.0 will position BookScanner primarily as a **receipt and invoice scanner for freelancers and small businesses**, with automatic expense extraction and spreadsheet export. The other specialized modes reuse the same capture, OCR, provider, review, privacy, and export foundations.

## 2. Delta boundary

Version 2.0 must not rebuild or duplicate capabilities already specified for Version 1. The following are existing foundations rather than new Version 2.0 features:

- General document, book, receipt, and ID image capture.
- Edge detection, crop, perspective correction, enhancement, OCR, and searchable PDF.
- Generic table/layout detection.
- Generic annotations and manual redaction.
- Generic PDF compression, sharing, local storage, and offline scanning.
- Markdown and Word export.

Version 2.0 adds domain understanding, specialized review experiences, structured exports, automatic protection, and enforceable privacy controls on top of those foundations.

## 3. Version 2.0 goals

1. Turn receipts into reviewed, structured expenses and complete expense reports.
2. Turn invoices into reviewed business records with reliable totals, taxes, dates, parties, and line items.
3. Export structured data to valid Excel workbooks and CSV without manual retyping.
4. Work accurately with supported African currencies, taxes, identifiers, payment methods, languages, and document layouts.
5. Compress a scan to a user-selected file-size budget for WhatsApp or another share destination.
6. Automatically find sensitive fields in IDs/passports and produce irreversibly redacted copies.
7. Convert school assignments into cleaned, searchable material and grounded study aids.
8. Offer a verifiable local-only mode in which document content cannot be uploaded.

## 4. Receipt-to-expense workflow

### User journey

1. The user chooses **Receipt / Expense**, captures or imports one or many receipts, and optionally assigns a business, client, project, or trip.
2. The app enhances each receipt, runs OCR, classifies the document, and extracts expense fields.
3. The review screen displays the original receipt beside editable structured fields. Selecting a field highlights its source region.
4. Low-confidence, missing, inconsistent, or arithmetic-invalid fields are flagged. The user confirms or corrects them.
5. The user categorizes expenses, marks business/personal and reimbursable/non-reimbursable status, adds notes/tags, and attaches multiple pages to one expense when needed.
6. The user generates an expense report and exports XLSX, CSV, PDF summary, and an optional ZIP containing source receipts.

### Extracted expense fields

- Merchant legal/display name, branch, address, phone, tax identifier, and country when present.
- Transaction date and time with explicit timezone/locale handling where known.
- Currency, subtotal, discount, taxes/levies by label and amount, service charge, tip, rounding, and grand total.
- Payment method, masked card details, cash, bank transfer, mobile-money provider/reference, and transaction reference when present.
- Line items: description, quantity, unit, unit price, discount, tax, and line total.
- Suggested expense category, project/client, reimbursable status, and business-use percentage; suggestions require user confirmation.
- Source page and bounding region, OCR confidence, extraction confidence, and user-correction history for every extracted value.

### Expense rules

- Validate that line totals, subtotal, taxes, adjustments, and grand total reconcile within a configurable rounding tolerance.
- Preserve the printed value when arithmetic is inconsistent and warn instead of silently “correcting” the receipt.
- Detect probable duplicate expenses using merchant, date/time, amount, currency, reference, OCR text, and image similarity. Users can keep both.
- Support split expenses across categories/projects and partial business-use allocation.
- Never infer a currency from a symbol alone when multiple currencies share that symbol without showing the assumption for confirmation.
- Store monetary values as decimal minor-unit-safe values, never binary floating point.

## 5. Invoice extraction and tracking

### User journey

1. The user chooses **Invoice**, scans/imports an invoice, and selects **Received** or **Issued**.
2. The app extracts parties, identifiers, dates, totals, taxes, payment instructions, and line items.
3. The user reviews the source-linked fields and resolves warnings.
4. The invoice becomes a searchable record that can be exported individually or included in a business spreadsheet/report.

### Extracted invoice fields

- Supplier and customer names, addresses, email/phone, tax identifiers, and registration identifiers.
- Invoice number, purchase-order/reference number, issue date, due date, payment terms, and service/delivery period.
- Currency, subtotal, discounts, taxes/levies/withholding by label/rate/amount, shipping/fees, amount paid, balance due, and total.
- Line-item description, SKU/code, quantity, unit, unit price, discount, tax rate, and amount.
- Bank or mobile-money payment instructions and references. Sensitive account data must receive the same protection as ID data.
- Extraction confidence, source coordinates, validation state, and correction history per field.

### Invoice rules

- Reconcile line items and summary totals using locale/country-specific rounding rules.
- Detect likely duplicates by supplier/customer, invoice number, date, currency, amount, text, and image similarity.
- Support statuses: draft extraction, needs review, approved, unpaid, partially paid, paid, overdue, void, and archived.
- Calculate overdue state locally from the confirmed due date; do not send reminders or contact another person without a separate user-authorized feature.
- Version 2.0 tracks invoice state but is not an accounting ledger, tax-filing service, or payment processor.

## 6. Expense reports and business summaries

- Filter by date range, business, client, project, category, currency, payment method, tax type, reimbursement status, and review state.
- Generate totals by category, project/client, merchant, currency, tax/levy label, and month.
- Never add unlike currencies into one total without a user-selected conversion method and recorded exchange rate/source/date. Default to separate currency totals.
- Include report title, owner/business metadata, reporting period, notes, expense rows, subtotals, tax summaries, and receipt references.
- Allow the user to choose whether receipt thumbnails/full pages are embedded in the PDF report or supplied in a separate ZIP.
- Reports remain editable until explicitly finalized; regeneration must use confirmed structured values and retain source links.

## 7. Scan-to-Excel and CSV

### Workbook exports

- Produce standards-compliant `.xlsx` files that open without repair warnings in current Microsoft Excel, Apple Numbers, Google Sheets import, and LibreOffice.
- Expense workbook sheets: `Expenses`, `Line Items`, `Tax Summary`, `Categories`, and `Report Metadata`.
- Invoice workbook sheets: `Invoices`, `Invoice Line Items`, `Tax Summary`, `Parties`, and `Export Metadata`.
- General table/inventory mode exports each detected table to a separate worksheet and supports combining compatible tables across pages.
- Inventory/price-list fields may include item/SKU, barcode, description, quantity, unit, unit price, tax, total, and source page.
- Use true numeric/date cell types, preserve leading-zero identifiers as text, include ISO currency codes, freeze headers, enable filters, and provide stable record IDs.
- Formula cells may be included for summaries, but confirmed extracted values remain available and formulas must not overwrite source data.

### Review and fallback

- Provide a grid review for column names, row/column boundaries, merged cells, data types, and OCR warnings before export.
- Allow adding/removing rows and columns, moving split values, and combining tables.
- If a table cannot be reconstructed reliably, export the uncertain cells with warnings and source coordinates rather than inventing values.
- CSV export supports a selected table or normalized record type and uses UTF-8 with configurable delimiter. Multi-table exports use a ZIP of clearly named CSV files.

## 8. African document and commerce profiles

- Implement country profiles instead of a single hard-coded “African” parser. Ghana is the required first profile; additional launch countries must be selected and tested with representative, lawfully sourced data before release.
- A profile defines currencies and symbols, number/date formats, common receipt/invoice terminology, tax/levy labels, business/tax identifier formats, mobile-money providers, ID types, languages, and validation rules.
- Ghana support includes GHS/GH₵ handling, Ghana Card and passport-aware redaction templates, mobile-money references, and configurable recognition of current Ghanaian tax/levy labels. Tax rules must be data-driven and versioned because legislation changes.
- Recognize mixed local/English terminology and common thermal, handwritten-added, stamped, carbon-copy, and low-contrast receipts without claiming unsupported handwriting accuracy.
- Country/profile selection is visible and correctable. Auto-detection may suggest a profile but must not silently apply tax or identity assumptions.
- Profile/model updates are signed, versioned, rollback-capable, and compatible with strict local-only mode after the user explicitly downloads them.
- Dataset collection, labeling, evaluation, and release reporting must measure per-country performance and avoid treating one country's formats as representative of the continent.

## 9. Target-size WhatsApp sharing

This feature uses the platform share sheet and does not require access to a user's WhatsApp account or contacts.

- Add **Compress for sharing** with presets and a custom target size in MB. Presets must be remotely/configurably labeled rather than assuming a permanent WhatsApp file limit.
- Estimate achievable size, then iteratively adjust image resolution, JPEG quality, color mode, metadata, and PDF object compression while preserving page order and OCR text where supported.
- Show the estimated/actual output size and a representative quality preview before sharing.
- Never overwrite the archival/source scan. Save the compressed output as a derived artifact with its settings.
- If the target cannot be reached above the minimum readability threshold, explain the trade-off and offer: raise target size, grayscale/black-and-white, split into volumes, or continue with a larger file.
- Support deterministic splitting by page ranges into sequentially named files, each within the selected budget where technically possible.
- Record no contacts or destination metadata. The operating system controls the final share destination.

## 10. Automatic ID and passport redaction

- Detect the document type and locate sensitive fields such as national ID/passport number, document number, date of birth, address, signature, machine-readable zone, barcode/QR payload, portrait, and other profile-defined identifiers.
- Display proposed redactions as editable overlays. Users can add, resize, remove, and label redaction regions before export.
- Provide purpose presets such as **Proof of identity**, **Proof of age**, and **Custom**, but always show exactly what will remain visible.
- Export must burn redactions irreversibly into a rasterized derivative and remove corresponding OCR text, annotations, metadata, thumbnails, and hidden layers.
- Verify the exported derivative by re-rendering it and checking that redacted strings are absent from OCR/searchable content and document metadata.
- Preserve the original only in the user's protected local library unless the user explicitly deletes it. Never include the original in a redacted share package.
- Sensitive detected values must not appear in logs, analytics, crash reports, filenames, notifications, or unencrypted indexes.
- Automatic redaction is assistive: require visual confirmation and warn that detection can miss fields.

## 11. School-assignment and study mode

- Provide a capture profile optimized for worksheets, ruled paper, handwritten answers, teacher markings, diagrams, and mixed printed/handwritten pages.
- Clean background/shadows and improve legibility while retaining an untouched original and avoiding removal of faint pencil marks or teacher annotations.
- Separate printed prompts, handwritten responses, marks/comments, diagrams, and page structure when supported. Each extracted item retains a source-page region and confidence.
- Export cleaned assignment PDF plus editable recognized text where confidence permits.
- Generate optional study outputs: concise notes, topic outline, glossary, practice questions, and flashcards grounded only in the scanned assignment.
- Every generated study item links back to its source page/region. Unsupported or uncertain claims must be labeled; the system must not fabricate an answer to illegible content.
- Let the learner edit, delete, and regenerate individual study items and export them to Markdown or Word.
- Clearly separate transcription from AI-generated study material and label generated content.
- Cloud AI processing requires explicit per-job consent. Strict local-only mode disables providers that cannot run on-device and explains the unavailable feature.
- Include age-appropriate privacy controls and avoid collecting student identity or school information unless required and explicitly entered.

## 12. Strict local-only privacy mode

Version 1 already works offline for core scanning. Version 2 adds an enforceable **Local-only mode**:

- When enabled, no document image, OCR text, extracted field, metadata, derived report, or document-derived telemetry may leave the device.
- Network-backed processing providers become unavailable and cannot be selected through fallback logic.
- Cloud backup/sync, remote OCR/AI, remote profile lookup, and document-derived crash attachments are disabled. The UI displays a persistent local-only indicator during processing.
- Required models/profile packs are downloaded only through an explicit, separate user action that explains the network request; document content is never attached to that request.
- Provide a local privacy activity screen showing processing providers used, model versions, and whether any job used a network-capable provider.
- Automated network-denial tests must demonstrate that supported local-only workflows complete while all document-content upload attempts are blocked.
- Changing out of local-only mode requires explicit confirmation and does not upload existing documents automatically.

## 13. Version 2.0 architecture additions

Add replaceable provider contracts without exposing vendor types to Flutter:

- `DocumentClassifierProvider`
- `ReceiptExtractionProvider`
- `InvoiceExtractionProvider`
- `TableExtractionProvider`
- `HandwritingRecognitionProvider`
- `StudyMaterialProvider`
- `SensitiveFieldDetectionProvider`
- `SpreadsheetExportProvider`
- `TargetSizeCompressionProvider`
- `CountryProfileProvider`

All extraction results use canonical, versioned domain models containing value, normalized value, source page/region, confidence, validation messages, provider/model versions, and correction state. Provider replacement must satisfy the adapter and contract-test requirements in Section 9.7 of the Version 1 specification.

New core entities include:

- **Business profile:** name, country profile, identifiers, base currency, categories, and export preferences.
- **Expense:** source documents, merchant, date, monetary breakdown, currency, payment details, category/project/client allocations, review state, and duplicate group.
- **Invoice:** source documents, direction, parties, identifiers, dates, terms, line items, monetary breakdown, payment details, and status.
- **Extracted field:** typed value, display value, source polygon, OCR/extraction confidence, validation state, provenance, and correction history.
- **Country profile:** versioned locale, currency, terminology, identifiers, taxes/levies, payment methods, document templates, and parser rules.
- **Export artifact:** format, schema version, filters, selected records, compression/privacy options, provider versions, checksum, and creation timestamp.

## 14. Version 2.0 acceptance criteria

### Receipt and expenses

- Given a supported clear receipt, the review screen displays merchant, date, currency, subtotal/taxes/total, payment information, and available line items with source highlighting and confidence.
- Given totals that do not reconcile, the app warns and preserves printed values until the user resolves or accepts the discrepancy.
- Given two probable copies of one receipt, the app flags a duplicate and allows the user to keep, merge, or dismiss it without deleting source images silently.
- Given reviewed expenses in multiple currencies, a report keeps currency totals separate unless the user explicitly configures conversion.

### Invoices

- Given a supported invoice, the app extracts parties, invoice number, dates, currency, monetary breakdown, payment terms, and line items and allows correction before approval.
- Given a confirmed due date in the past and a non-paid status, the app marks the invoice overdue without contacting the customer or supplier.

### Spreadsheet export

- Reviewed expense and invoice workbooks open without repair warnings and contain typed dates/numbers, preserved text identifiers, source references, and the specified worksheets.
- A table scan can be corrected in grid review and exported to XLSX and UTF-8 CSV with matching row/column values.

### African profiles

- Ghana profile test fixtures correctly distinguish GHS values, supported identifier formats, configured tax/levy labels, date/number formats, and supported mobile-money references.
- Switching country profile reruns only profile-dependent stages and preserves original images and manual corrections where compatible.

### Target-size sharing

- Given a reachable target budget, the generated file is at or below the selected size, remains readable at the defined threshold, preserves page order, and retains searchable text where configured.
- Given an unreachable budget, the app does not silently produce unreadable pages and offers larger-size, monochrome, or split-file choices.

### ID/passport redaction

- The user can review and modify all proposed redactions before export.
- Re-render and text inspection of an exported redacted file cannot recover the redacted pixels or corresponding hidden/OCR text.

### Assignments

- The cleaned assignment retains faint handwriting/marks in the source truth and links extracted/generated content to page regions.
- Study material distinguishes transcription from generated content and does not present illegible source content as a confident fact.

### Local-only mode

- With local-only mode enabled and network access denied, supported capture, processing, review, search, and local export workflows complete successfully.
- Instrumented tests detect no document-content network request, and unavailable cloud-only functionality is disabled with a clear explanation.

## 15. Version 2.0 delivery order

1. **Foundation:** canonical business schemas, decimal money handling, extraction provenance, country-profile framework, provider contracts, privacy policy enforcement, and test corpus.
2. **Primary opportunity:** receipt/invoice classification, extraction, source-linked review, validation, duplicates, business organization, and expense reports.
3. **Structured export:** XLSX/CSV service, workbook validation, general table/inventory review, and exports.
4. **Local-market readiness:** Ghana profile, supported languages/formats, mobile-money fields, tax/levy configuration, and per-profile evaluation.
5. **Sharing:** target-size compression, readability guard, file splitting, and platform share-sheet flow.
6. **Sensitive documents:** ID/passport field detection, redaction review, irreversible export, and leakage verification.
7. **Education:** assignment cleanup, mixed-text extraction, grounded study outputs, and student privacy safeguards.
8. **Release hardening:** Android/iOS integration tests, strict local-only network tests, accessibility/localization, performance, migration, and all Version 2.0 acceptance criteria.

## 16. Version 2.0 product decisions required

1. Additional launch country profiles after Ghana and the lawful evaluation datasets available for each.
2. Supported UI/OCR/handwriting languages and required accuracy thresholds per profile.
3. On-device extraction/study models versus optional cloud providers and associated pricing.
4. Default business categories and whether users can import a chart of accounts.
5. Supported accounting/export schemas beyond generic XLSX/CSV.
6. Receipt/invoice retention, backup, and deletion defaults.
7. Minimum acceptable OCR, field extraction, table reconstruction, dewarping, and redaction recall/precision for release.
8. Whether school-assignment study generation ships in the initial 2.0 release or a 2.x update after the primary small-business workflow.
