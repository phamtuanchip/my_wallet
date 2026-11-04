import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';

import '../nfc/emrtd/bac.dart';
import '../nfc/emrtd/emrtd_reader.dart';

/// Bottom sheet that waits for the document on the back of the phone and
/// reads its chip. Pops with the [EmrtdData], or null when closed.
Future<EmrtdData?> showChipReadSheet(BuildContext context, {required BacKey key, required bool readVnPersonal}) {
  return showModalBottomSheet<EmrtdData>(
    context: context,
    isDismissible: true,
    showDragHandle: true,
    builder: (_) => _ChipReadSheet(bacKey: key, readVnPersonal: readVnPersonal),
  );
}

class _ChipReadSheet extends StatefulWidget {
  const _ChipReadSheet({required this.bacKey, required this.readVnPersonal});

  final BacKey bacKey;
  final bool readVnPersonal;

  @override
  State<_ChipReadSheet> createState() => _ChipReadSheetState();
}

class _ChipReadSheetState extends State<_ChipReadSheet> {
  String _status = 'Place the document on the back of the phone and keep it still.';
  String? _error;
  double? _progress;
  bool _busy = false;
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
    setState(() {
      _error = null;
      _progress = null;
      _status = 'Place the document on the back of the phone and keep it still.';
    });
    try {
      if (!await NfcManager.instance.isAvailable()) {
        setState(() => _error = 'NFC is off. Turn it on in Android settings and try again.');
        return;
      }
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        onDiscovered: _onTag,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start NFC (${e.runtimeType}).');
    }
  }

  Future<void> _onTag(NfcTag tag) async {
    if (_busy || _closed) return;
    final isoDep = IsoDep.from(tag);
    if (isoDep == null) {
      await _fail('This is not a chip ID card or passport.');
      return;
    }
    _busy = true;
    try {
      final data = await EmrtdReader((apdu) => isoDep.transceive(data: apdu))
          .read(
            widget.bacKey,
            readVnPersonal: widget.readVnPersonal,
            onProgress: (step, p) {
              if (!mounted) return;
              setState(() {
                _progress = p;
                _status = switch (step) {
                  EmrtdStep.connecting => 'Connecting to the chip…',
                  EmrtdStep.authenticating => 'Unlocking the chip with the document number and dates…',
                  EmrtdStep.readingData => 'Reading personal data…',
                  EmrtdStep.readingPhoto => 'Reading the photo… keep it still',
                  EmrtdStep.readingPersonal => 'Reading address and family details…',
                  EmrtdStep.done => 'Done',
                };
              });
            },
          )
          .timeout(const Duration(seconds: 60));
      await NfcManager.instance.stopSession();
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(data);
    } on EmrtdAccessDenied {
      await _fail('The chip refused the key. Check the document number, date of birth and expiry date.');
    } on TimeoutException {
      await _fail('Reading took too long. Hold the document still on the phone and try again.');
    } on PlatformException {
      await _fail('The document moved away from the phone. Keep it still until reading finishes.');
    } on SecureMessagingException {
      await _fail('The connection to the chip was interrupted. Try again.');
    } on BacException {
      await _fail('The chip did not answer as expected. Try again.');
    } catch (e) {
      await _fail('Could not read the chip (${e.runtimeType}).');
    } finally {
      _busy = false;
    }
  }

  Future<void> _fail(String message) async {
    HapticFeedback.heavyImpact();
    try {
      await NfcManager.instance.stopSession(errorMessage: message);
    } catch (_) {}
    if (mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = _error;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(error == null ? LucideIcons.nfc : LucideIcons.circleAlert,
                size: 56, color: error == null ? scheme.primary : scheme.error),
            const SizedBox(height: 16),
            Text(error == null ? 'Read the chip' : 'Could not read',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(error ?? _status, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (error == null)
              LinearProgressIndicator(value: _progress, borderRadius: BorderRadius.circular(4))
            else
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('Try again'),
              ),
            const SizedBox(height: 12),
            Text(
              'The chip antenna is usually in the middle of the card. On most phones the NFC reader is '
              'near the camera.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
