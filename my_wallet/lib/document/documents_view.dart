import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'id_document.dart';

IconData documentIcon(DocumentKind kind) => switch (kind) {
      DocumentKind.cccd => LucideIcons.idCard,
      DocumentKind.passport => LucideIcons.bookUser,
      DocumentKind.carLicense => LucideIcons.car,
      DocumentKind.motoLicense => LucideIcons.bike,
      DocumentKind.vehicleRegistration => LucideIcons.fileText,
      DocumentKind.insurance => LucideIcons.shieldCheck,
      DocumentKind.other => LucideIcons.file,
    };

/// Bottom sheet to choose what to add. [onNfcScan] adds a first row that
/// starts the auto-detecting NFC scan (bank card, chip ID, passport, badge).
Future<DocumentKind?> showDocumentKindPicker(
  BuildContext context, {
  String title = 'Add a document',
  List<DocumentKind> kinds = DocumentKind.values,
  String? message,
  VoidCallback? onNfcScan,
}) {
  return showModalBottomSheet<DocumentKind>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(message, style: Theme.of(ctx).textTheme.bodyMedium),
                ),
              if (onNfcScan != null) ...[
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    child: const Icon(LucideIcons.nfc, size: 20),
                  ),
                  title: const Text('Scan with NFC'),
                  subtitle: const Text('Bank card, chip CCCD, passport or access card: detected automatically'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onNfcScan();
                  },
                ),
                const Divider(indent: 24, endIndent: 24),
              ],
              for (final k in kinds)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: k.color.withValues(alpha: 0.15),
                    foregroundColor: k.color,
                    child: Icon(documentIcon(k), size: 20),
                  ),
                  title: Text(k.vnLabel),
                  subtitle: Text(k.hasChip ? '${k.label} · read the chip over NFC' : '${k.label} · photos of front and back'),
                  onTap: () => Navigator.pop(ctx, k),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// The Documents tab: one row per document, newest first. Only clear-text
/// metadata is shown here; opening a document asks for fingerprint/passcode.
class DocumentsView extends StatelessWidget {
  const DocumentsView({
    super.key,
    required this.documents,
    required this.loading,
    required this.onAdd,
    required this.onOpen,
  });

  final List<IdDocument> documents;
  final bool loading;
  final VoidCallback onAdd;
  final ValueChanged<IdDocument> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
          child: Row(children: [
            Expanded(
              child: Text('Documents',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
            ),
            IconButton.filled(tooltip: 'Add a document', onPressed: onAdd, icon: const Icon(LucideIcons.plus)),
          ]),
        ),
      ),
      if (loading)
        const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
      else if (documents.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(LucideIcons.idCard, size: 72, color: scheme.outlineVariant),
              const SizedBox(height: 16),
              Text('No documents yet', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Keep your CCCD, passport, driving licences and vehicle papers here. '
                'Chip documents are read over NFC; others are saved as photos of both sides, encrypted on this phone.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: onAdd, icon: const Icon(LucideIcons.plus), label: const Text('Add a document')),
            ]),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverList.separated(
            itemCount: documents.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _DocumentTile(doc: documents[i], onTap: () => onOpen(documents[i])),
          ),
        ),
    ]);
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.doc, required this.onTap});

  final IdDocument doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = doc.kind;
    final parts = [
      k.vnLabel,
      if (doc.numberLast4 != null) '•••• ${doc.numberLast4}',
      if (doc.frontFile != null || doc.backFile != null)
        doc.frontFile != null && doc.backFile != null ? '2 photos' : '1 photo',
    ];
    return Semantics(
      button: true,
      label: '${doc.title}, ${k.label}${doc.numberLast4 == null ? '' : ', ending ${doc.numberLast4}'}',
      excludeSemantics: true,
      child: Material(
        color: k.color,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(documentIcon(k), color: Colors.white, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(parts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                ]),
              ),
              if (doc.hasChipData) ...[
                const SizedBox(width: 8),
                const Tooltip(message: 'Read from the chip', child: Icon(LucideIcons.nfc, color: Colors.white, size: 20)),
              ],
              const SizedBox(width: 4),
              const Icon(LucideIcons.chevronRight, color: Colors.white70),
            ]),
          ),
        ),
      ),
    );
  }
}
