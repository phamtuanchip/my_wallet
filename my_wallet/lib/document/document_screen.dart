
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../nfc/emrtd/bac.dart';
import '../nfc/emrtd/mrz.dart';
import 'chip_read_sheet.dart';
import 'document_capture.dart';
import 'document_ocr.dart';
import 'document_store.dart';
import 'id_document.dart';

/// Add / edit one document. Saves through [store] and pops `true` when the
/// vault changed (saved or deleted).
class DocumentScreen extends StatefulWidget {
  const DocumentScreen({
    super.key,
    required this.store,
    required this.initial,
    this.existing,
    this.capture,
    this.chipDetected = false,
  });

  final DocumentStore store;
  final DocumentContent initial;
  final IdDocument? existing;
  final DocumentCapture? capture;

  /// Opened because a chip document was just tapped: explain the next step.
  final bool chipDetected;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  late final DocumentContent _c = widget.initial;
  late final DocumentCapture _capture = widget.capture ?? DocumentCapture();
  final Map<String, TextEditingController> _ctrl = {};
  late final TextEditingController _title = TextEditingController(text: _c.title);
  bool _dirty = false;
  bool _saving = false;
  String? _busySide; // 'front' | 'back' while a photo is being taken / read

  DocumentKind get _kind => _c.kind;

  @override
  void initState() {
    super.initState();
    for (final key in _fieldKeys()) {
      _controller(key);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    _title.dispose();
    super.dispose();
  }

  TextEditingController _controller(String key) => _ctrl.putIfAbsent(key, () {
        final c = TextEditingController(text: _c.fields[key] ?? '');
        c.addListener(() {
          if (_c.fields[key] != c.text) {
            _c.fields[key] = c.text;
            _dirty = true;
          }
        });
        return c;
      });

  /// Form fields for the kind, then extra values (e.g. read from the chip), then notes.
  List<String> _fieldKeys() {
    final base = _kind.fields.map((f) => f.key).toList();
    final extra = _c.fields.keys.where((k) => !base.contains(k) && k != 'notes' && (_c.fields[k] ?? '').isNotEmpty);
    return [...base, ...extra, 'notes'];
  }

  void _applyFields(Map<String, String> values, {bool overwrite = false}) {
    setState(() {
      values.forEach((k, v) {
        if (v.isEmpty) return;
        final ctrl = _controller(k);
        if (overwrite || ctrl.text.trim().isEmpty) ctrl.text = v;
      });
      _dirty = true;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), showCloseIcon: true));
  }

  // ── Photos ────────────────────────────────────────────────────────────

  Future<void> _takePhoto(String side, {required bool fromGallery}) async {
    setState(() => _busySide = side);
    try {
      final shot = await _capture.capture(fromGallery: fromGallery);
      if (shot == null || !mounted) return;
      final found = parseDocumentText(_kind, shot.lines);
      setState(() {
        if (side == 'front') {
          _c.front = shot.jpeg;
        } else {
          _c.back = shot.jpeg;
        }
        _dirty = true;
      });
      _applyFields(found);
      final mrz = _kind.hasChip ? findMrz(shot.lines) : null;
      if (mrz != null && mrz.checksOk) {
        _applyFields(fieldsFromMrz(mrz, _kind), overwrite: true);
        _snack('MRZ read: the chip key is ready. Tap "Read chip".');
      } else if (found.isNotEmpty) {
        _snack('Filled ${found.length} field${found.length == 1 ? '' : 's'} from the photo. Please check them.');
      }
    } catch (e) {
      _snack('Could not take the photo (${e.runtimeType}).');
    } finally {
      if (mounted) setState(() => _busySide = null);
    }
  }

  Future<void> _photoActions(String side) async {
    final has = (side == 'front' ? _c.front : _c.back) != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (has)
            ListTile(leading: const Icon(LucideIcons.maximize2), title: const Text('View'), onTap: () => Navigator.pop(ctx, 'view')),
          ListTile(
              leading: const Icon(LucideIcons.scanLine),
              title: Text(has ? 'Retake with camera' : 'Take photo'),
              subtitle: const Text('Auto-crops the document'),
              onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(leading: const Icon(LucideIcons.image), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, 'gallery')),
          if (has)
            ListTile(
                leading: Icon(LucideIcons.trash2, color: Theme.of(ctx).colorScheme.error),
                title: Text('Remove', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                onTap: () => Navigator.pop(ctx, 'remove')),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'view':
        _viewImage(side == 'front' ? _c.front! : _c.back!, side == 'front' ? 'Front' : 'Back');
      case 'camera':
        await _takePhoto(side, fromGallery: false);
      case 'gallery':
        await _takePhoto(side, fromGallery: true);
      case 'remove':
        setState(() {
          if (side == 'front') {
            _c.front = null;
          } else {
            _c.back = null;
          }
          _dirty = true;
        });
    }
  }

  void _viewImage(Uint8List bytes, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)),
        body: Center(
          child: InteractiveViewer(maxScale: 6, child: Image.memory(bytes, gaplessPlayback: true)),
        ),
      ),
    ));
  }

  // ── Chip ──────────────────────────────────────────────────────────────

  /// The BAC key from the form, or a message saying what's missing.
  (BacKey?, String?) _bacKey() {
    final rawNumber = (_c.fields[_kind.numberField.key] ?? '').replaceAll(RegExp(r'\s'), '').toUpperCase();
    final dob = toMrzDate(_c.fields['dob'] ?? '');
    final exp = toMrzDate(_c.fields['expiry'] ?? '');
    final missing = [
      if (rawNumber.isEmpty) _kind == DocumentKind.passport ? 'passport number' : 'ID number',
      if (dob == null) 'date of birth (dd/mm/yyyy)',
      if (exp == null) 'expiry date (dd/mm/yyyy)',
    ];
    if (missing.isNotEmpty) return (null, 'Enter the ${missing.join(', ')} first, or photograph the back so the MRZ is read.');
    var docNumber = rawNumber;
    if (_kind == DocumentKind.cccd) {
      if (!RegExp(r'^\d{9}$|^\d{12}$').hasMatch(rawNumber)) {
        return (null, 'The CCCD number must have 12 digits.');
      }
      // The chip's document number is the last 9 digits of the 12-digit number.
      docNumber = rawNumber.substring(rawNumber.length - 9);
    }
    return (BacKey(docNumber, dob!, exp!), null);
  }

  Future<void> _readChip() async {
    final (key, problem) = _bacKey();
    if (key == null) {
      _snack(problem!);
      return;
    }
    final data = await showChipReadSheet(context, key: key, readVnPersonal: _kind == DocumentKind.cccd);
    if (data == null || !mounted) return;
    final values = {
      ...fieldsFromMrz(data.mrz, _kind),
      ...data.vnPersonal, // Vietnamese name with diacritics, address, parents…
    };
    _applyFields(values, overwrite: true);
    setState(() {
      if (data.faceImage != null) _c.face = data.faceImage;
      _c.hasChipData = true;
      _dirty = true;
    });
    _snack('Chip read. ${values.length} fields updated${data.faceImage != null ? ' + photo' : ''}.');
  }

  // ── Save / delete ─────────────────────────────────────────────────────

  Future<void> _save() async {
    for (final f in _kind.fields.where((f) => f.type == FieldType.date)) {
      final v = (_c.fields[f.key] ?? '').trim();
      if (v.isNotEmpty && toMrzDate(v) == null) {
        _snack('${f.label}: use dd/mm/yyyy.');
        return;
      }
    }
    final hasAnything = _c.front != null ||
        _c.back != null ||
        _c.face != null ||
        _c.fields.values.any((v) => v.trim().isNotEmpty);
    if (!hasAnything) {
      _snack('Add a photo or fill in at least one field.');
      return;
    }
    setState(() => _saving = true);
    try {
      _c.title = _title.text;
      await widget.store.save(_c, existing: widget.existing);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Could not save (${e.runtimeType}).');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: const Text('Its photos and details are removed from this phone. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.store.delete(widget.existing!);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return ok == true;
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _dirty = false;
          Navigator.of(context).pop(false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.existing == null ? 'Add ${_kind.label.toLowerCase()}' : _kind.label),
          actions: [
            if (widget.existing != null)
              IconButton(tooltip: 'Delete', icon: const Icon(LucideIcons.trash2), onPressed: _saving ? null : _delete),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.viewInsetsOf(context).bottom),
          children: [
            Text(_kind.vnLabel, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: _kind.color)),
            const SizedBox(height: 12),
            if (_kind.hasChip) ...[_chipCard(scheme), const SizedBox(height: 16)],
            Row(children: [
              Expanded(child: _photoTile('front', 'Front', 'Mặt trước', _c.front)),
              const SizedBox(width: 12),
              Expanded(child: _photoTile('back', 'Back', 'Mặt sau', _c.back)),
            ]),
            const SizedBox(height: 20),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: 'Title (optional)',
                hintText: _c.defaultTitle,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _dirty = true,
            ),
            const SizedBox(height: 12),
            for (final key in _fieldKeys()) ...[_field(key), const SizedBox(height: 12)],
          ],
        ),
      ),
    );
  }

  Widget _chipCard(ColorScheme scheme) {
    final face = _c.face;
    final read = _c.hasChipData;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (face != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  height: 96,
                  child: Image.memory(
                    face,
                    fit: BoxFit.cover,
                    semanticLabel: 'Photo from the chip',
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: scheme.surfaceContainer,
                      child: const Center(
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('Photo saved (JPEG 2000)', textAlign: TextAlign.center, style: TextStyle(fontSize: 10)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(read ? LucideIcons.badgeCheck : LucideIcons.nfc, size: 20, color: read ? Colors.green : scheme.primary),
                  const SizedBox(width: 8),
                  Text(read ? 'Read from the chip' : 'NFC chip', style: Theme.of(context).textTheme.titleSmall),
                ]),
                const SizedBox(height: 6),
                Text(
                  widget.chipDetected && !read
                      ? 'Chip detected. Photograph the back (or type the number, date of birth and expiry), then tap "Read chip" and hold the document on the phone again.'
                      : read
                          ? 'Name, dates and photo come from the chip. Tap again to refresh.'
                          : 'The chip is unlocked with the ${_kind == DocumentKind.passport ? 'passport number' : 'ID number'}, date of birth and expiry date. Photograph the back to fill them from the MRZ.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: _readChip,
              icon: const Icon(LucideIcons.nfc, size: 18),
              label: Text(read ? 'Read chip again' : 'Read chip'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _photoTile(String side, String label, String vnLabel, Uint8List? bytes) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _busySide == side;
    return Semantics(
      button: true,
      label: bytes == null ? 'Add $label photo' : '$label photo, tap for options',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busySide != null ? null : () => bytes == null ? _takePhoto(side, fromGallery: false) : _photoActions(side),
        onLongPress: _busySide != null ? null : () => _photoActions(side),
        child: AspectRatio(
          aspectRatio: 1.586, // ID-1 card
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: scheme.surfaceContainerHighest,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: busy
                ? const Center(child: CircularProgressIndicator())
                : bytes != null
                    ? Stack(fit: StackFit.expand, children: [
                        Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                      ])
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(LucideIcons.camera, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 4),
                        Text('$label · $vnLabel', style: Theme.of(context).textTheme.bodySmall),
                      ]),
          ),
        ),
      ),
    );
  }

  Widget _field(String key) {
    final f = DocumentField.fromKey(key);
    final type = f?.type ?? FieldType.text;
    final ctrl = _controller(key);
    return TextField(
      controller: ctrl,
      keyboardType: switch (type) {
        FieldType.number => TextInputType.number,
        FieldType.date => TextInputType.datetime,
        FieldType.multiline => TextInputType.multiline,
        FieldType.text => TextInputType.text,
      },
      textCapitalization: type == FieldType.text ? TextCapitalization.words : TextCapitalization.sentences,
      minLines: type == FieldType.multiline ? 1 : null,
      maxLines: type == FieldType.multiline ? 4 : 1,
      inputFormatters: type == FieldType.date ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9/.\-]'))] : null,
      decoration: InputDecoration(
        labelText: f == null ? key : '${f.label} · ${f.vnLabel}',
        hintText: type == FieldType.date ? 'dd/mm/yyyy' : null,
        border: const OutlineInputBorder(),
        suffixIcon: type == FieldType.date
            ? IconButton(
                tooltip: 'Pick a date',
                icon: const Icon(LucideIcons.calendar, size: 20),
                onPressed: () => _pickDate(ctrl, key),
              )
            : null,
      ),
    );
  }

  Future<void> _pickDate(TextEditingController ctrl, String key) async {
    final now = DateTime.now();
    final current = toMrzDate(ctrl.text);
    DateTime initial = key == 'dob' ? DateTime(now.year - 30) : now;
    if (current != null) {
      final s = fromMrzDate(current, isExpiry: key == 'expiry')!.split('/');
      initial = DateTime(int.parse(s[2]), int.parse(s[1]), int.parse(s[0]));
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 100),
    );
    if (picked == null) return;
    ctrl.text = '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
  }
}
