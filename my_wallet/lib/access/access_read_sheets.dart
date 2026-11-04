import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nfc_manager/nfc_manager.dart';

import 'lf_card_id.dart';
import 'nfc_tag_info.dart';

/// Waits for a 13.56 MHz card on the phone and reads its UID / type / key check.
Future<NfcTagInfo?> showNfcTagSheet(BuildContext context) => showModalBottomSheet<NfcTagInfo>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _NfcTagSheet(),
    );

class _NfcTagSheet extends StatefulWidget {
  const _NfcTagSheet();

  @override
  State<_NfcTagSheet> createState() => _NfcTagSheetState();
}

class _NfcTagSheetState extends State<_NfcTagSheet> {
  String? _error;
  bool _reading = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _closed = true;
    NfcManager.instance.stopSession().catchError((_) {});
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      if (!await NfcManager.instance.isAvailable()) {
        setState(() => _error = 'NFC is off. Turn it on in Android settings and try again.');
        return;
      }
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693, NfcPollingOption.iso18092},
        onDiscovered: _onTag,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start NFC (${e.runtimeType}).');
    }
  }

  Future<void> _onTag(NfcTag tag) async {
    if (_reading || _closed) return;
    setState(() => _reading = true);
    try {
      final info = await readNfcTagInfo(tag);
      await NfcManager.instance.stopSession();
      if (info == null) {
        if (mounted) setState(() => _error = 'The card answered, but it is not a type this phone can read.');
        return;
      }
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(info);
    } catch (e) {
      try {
        await NfcManager.instance.stopSession(errorMessage: 'Read failed');
      } catch (_) {}
      if (mounted) setState(() => _error = 'The card moved away. Hold it still on the phone and try again.');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = _error;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(error == null ? LucideIcons.nfc : LucideIcons.circleAlert,
              size: 56, color: error == null ? scheme.primary : scheme.error),
          const SizedBox(height: 16),
          Text(error == null ? 'Hold the card on the phone' : 'Could not read', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            error ??
                (_reading
                    ? 'Reading… keep the card still.'
                    : 'Works with 13.56 MHz cards (MIFARE, NTAG, DESFire…). If nothing happens after a few seconds, '
                        'the card is probably 125 kHz: use a USB reader or the printed number instead.'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (error == null)
            LinearProgressIndicator(value: _reading ? null : 0, borderRadius: BorderRadius.circular(4))
          else
            FilledButton.icon(onPressed: _start, icon: const Icon(LucideIcons.refreshCw, size: 18), label: const Text('Try again')),
        ]),
      ),
    );
  }
}

/// A USB/OTG 125 kHz reader acts as a keyboard: it "types" the card number and
/// presses Enter. This dialog keeps a field focused to catch that input; the
/// number can also be typed by hand.
Future<LfCardId?> showUsbReaderDialog(BuildContext context) => showDialog<LfCardId>(
      context: context,
      builder: (_) => const _UsbReaderDialog(),
    );

class _UsbReaderDialog extends StatefulWidget {
  const _UsbReaderDialog();

  @override
  State<_UsbReaderDialog> createState() => _UsbReaderDialogState();
}

class _UsbReaderDialogState extends State<_UsbReaderDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final id = parseLfCardId(_ctrl.text);
    if (id == null) {
      setState(() => _error = 'Not a card number. Expected 10 digits, 8/10 hex digits or "fff,ccccc".');
      _ctrl.clear();
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(LucideIcons.usb),
      title: const Text('USB card reader (125 kHz)'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Plug the reader in with an OTG adapter, then hold the card on it. '
            'The number appears below, or type the number printed on the card.'),
        const SizedBox(height: 16),
        TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Card number',
            hintText: '0004335038 or 066,09662',
            errorText: _error,
            errorMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Use')),
      ],
    );
  }
}
