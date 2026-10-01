import 'package:flutter/material.dart';

import '../../../../domain/models/export_job.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../core/theme/app_theme.dart';

/// What Review asked the export screen to run after the format sheet closes.
class ExportLaunch {
  const ExportLaunch({
    required this.format,
    this.pdfOptions,
    this.markdownOptions,
    this.epubOptions,
  });

  final ExportFormat format;
  final PdfExportOptions? pdfOptions;
  final MarkdownExportOptions? markdownOptions;
  final EpubExportOptions? epubOptions;
}

enum _SheetFormat { pdf, markdown, epub }

enum _PdfQuality { high, medium, low }

extension on _PdfQuality {
  double get quality => switch (this) {
    _PdfQuality.high => 0.92,
    _PdfQuality.medium => 0.72,
    _PdfQuality.low => 0.45,
  };
}

/// Polished format picker. Choosing a format reveals only that format's
/// settings, then a single confirm button.
class ExportConvertSheet extends StatefulWidget {
  const ExportConvertSheet({super.key});

  @override
  State<ExportConvertSheet> createState() => _ExportConvertSheetState();
}

class _ExportConvertSheetState extends State<ExportConvertSheet> {
  _SheetFormat _format = _SheetFormat.pdf;
  bool _searchable = true;
  PdfPageSize _pageSize = PdfPageSize.a4;
  _PdfQuality _quality = _PdfQuality.high;
  bool _pageMarkers = true;
  bool _includeImages = true;

  void _confirm() {
    final launch = switch (_format) {
      _SheetFormat.pdf => ExportLaunch(
        format: _searchable ? ExportFormat.searchablePdf : ExportFormat.imagePdf,
        pdfOptions: PdfExportOptions(
          pageSize: _pageSize,
          imageQuality: _quality.quality,
          searchable: _searchable,
        ),
      ),
      _SheetFormat.markdown => ExportLaunch(
        format: ExportFormat.markdown,
        markdownOptions: MarkdownExportOptions(
          includePageBoundaryComments: _pageMarkers,
        ),
      ),
      _SheetFormat.epub => ExportLaunch(
        format: ExportFormat.epub,
        epubOptions: EpubExportOptions(includePageImages: _includeImages),
      ),
    };
    Navigator.of(context).pop(launch);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final confirmLabel = switch (_format) {
      _SheetFormat.pdf => l10n.reviewExportToPdf,
      _SheetFormat.markdown => l10n.reviewExportToMarkdown,
      _SheetFormat.epub => l10n.reviewExportToEpub,
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.homeHairline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.reviewExportConvert,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                color: AppTheme.homeText,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.reviewExportSheetSubtitle,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                color: AppTheme.homeMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            _FormatCard(
              key: const ValueKey('reviewExportPdf'),
              selected: _format == _SheetFormat.pdf,
              color: const Color(0xFFE25B5B),
              icon: Icons.picture_as_pdf_outlined,
              title: l10n.reviewExportPdf,
              subtitle: l10n.reviewExportPdfHint,
              onTap: () => setState(() => _format = _SheetFormat.pdf),
            ),
            const SizedBox(height: 10),
            _FormatCard(
              key: const ValueKey('reviewExportMarkdown'),
              selected: _format == _SheetFormat.markdown,
              color: const Color(0xFF3DFF8A),
              icon: Icons.description_outlined,
              title: l10n.reviewExportMarkdown,
              subtitle: l10n.reviewExportMarkdownHint,
              onTap: () => setState(() => _format = _SheetFormat.markdown),
            ),
            const SizedBox(height: 10),
            _FormatCard(
              key: const ValueKey('reviewExportEpub'),
              selected: _format == _SheetFormat.epub,
              color: const Color(0xFF8B7CFF),
              icon: Icons.menu_book_outlined,
              title: l10n.reviewExportEpub,
              subtitle: l10n.reviewExportEpubHint,
              onTap: () => setState(() => _format = _SheetFormat.epub),
            ),
            const SizedBox(height: 18),
            if (_format == _SheetFormat.pdf)
              _OptionsPanel(
                key: const ValueKey('reviewPdfOptions'),
                title: l10n.reviewExportPdfOptions,
                children: [
                  _SwitchRow(
                    key: const ValueKey('reviewExportOcrSwitch'),
                    icon: Icons.text_fields,
                    label: l10n.reviewExportOcr,
                    value: _searchable,
                    onChanged: (value) => setState(() => _searchable = value),
                  ),
                  _DropdownRow<PdfPageSize>(
                    key: const ValueKey('reviewExportPageSize'),
                    icon: Icons.crop_free,
                    label: l10n.pdfPageSize,
                    value: _pageSize,
                    items: {
                      PdfPageSize.a4: l10n.pdfPageSizeA4,
                      PdfPageSize.letter: l10n.pdfPageSizeLetter,
                      PdfPageSize.legal: l10n.pdfPageSizeLegal,
                      PdfPageSize.matchSource: l10n.pdfPageSizeMatchSource,
                    },
                    onChanged: (value) => setState(() => _pageSize = value),
                  ),
                  _DropdownRow<_PdfQuality>(
                    key: const ValueKey('reviewExportQuality'),
                    icon: Icons.photo_outlined,
                    label: l10n.reviewExportImageQuality,
                    value: _quality,
                    items: {
                      _PdfQuality.high: l10n.reviewExportQualityHigh,
                      _PdfQuality.medium: l10n.reviewExportQualityMedium,
                      _PdfQuality.low: l10n.reviewExportQualityLow,
                    },
                    onChanged: (value) => setState(() => _quality = value),
                  ),
                ],
              ),
            if (_format == _SheetFormat.markdown)
              _OptionsPanel(
                key: const ValueKey('reviewMarkdownOptions'),
                title: l10n.reviewExportMarkdownOptions,
                children: [
                  _SwitchRow(
                    key: const ValueKey('reviewPageMarkersSwitch'),
                    icon: Icons.bookmark_border,
                    label: l10n.reviewIncludePageMarkers,
                    value: _pageMarkers,
                    onChanged: (value) => setState(() => _pageMarkers = value),
                  ),
                ],
              ),
            if (_format == _SheetFormat.epub)
              _OptionsPanel(
                key: const ValueKey('reviewEpubOptions'),
                title: l10n.reviewExportEpubOptions,
                children: [
                  _SwitchRow(
                    key: const ValueKey('reviewIncludeImagesSwitch'),
                    icon: Icons.image_outlined,
                    label: l10n.reviewIncludePageImages,
                    value: _includeImages,
                    onChanged: (value) => setState(() => _includeImages = value),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [AppTheme.accent, AppTheme.accentDeep],
                ),
              ),
              child: FilledButton.icon(
                key: const ValueKey('reviewExportConfirm'),
                onPressed: _confirm,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: const Color(0xFF04140C),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                icon: Icon(
                  _format == _SheetFormat.pdf
                      ? Icons.picture_as_pdf_outlined
                      : Icons.ios_share_outlined,
                ),
                label: Text(
                  confirmLabel,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({
    super.key,
    required this.selected,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.homeCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.homeHairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        color: AppTheme.homeText,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        color: AppTheme.homeMuted,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.homeMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionsPanel extends StatelessWidget {
  const _OptionsPanel({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: AppTheme.homeCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.homeHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: AppTheme.homeMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.homeMuted, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: AppTheme.homeText,
              fontSize: 13,
            ),
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: const Color(0xFF04140C),
          activeTrackColor: AppTheme.accent,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.homeMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                color: AppTheme.homeText,
                fontSize: 13,
              ),
            ),
          ),
          DropdownButton<T>(
            value: value,
            dropdownColor: const Color(0xFF163026),
            underline: const SizedBox.shrink(),
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: AppTheme.homeText,
              fontSize: 13,
            ),
            items: [
              for (final entry in items.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (next) {
              if (next != null) onChanged(next);
            },
          ),
        ],
      ),
    );
  }
}
