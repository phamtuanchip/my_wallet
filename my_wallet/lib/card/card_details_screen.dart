import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/wallet_card_face.dart';
import 'card_info.dart';
import 'card_ocr_parser.dart';
import 'card_scanner.dart';

/// Plain (decrypted) card details edited on [CardDetailsScreen].
class CardDetails {
  const CardDetails({
    this.number = '',
    this.holder = '',
    this.scheme = CardScheme.unknown,
    this.product = CardProduct.unknown,
    this.issuer = '',
    this.expiry = '',
    this.cvv = '',
  });

  final String number; // digits only
  final String holder;
  final CardScheme scheme;
  final CardProduct product;
  final String issuer;
  final String expiry; // MM/YY
  final String cvv;
}

/// Edit form for the payment details of a saved card, with a camera scan that
/// pre-fills number, cardholder, expiry, bank and type. The caller decrypts
/// [initial] and encrypts the returned [CardDetails].
class CardDetailsScreen extends StatefulWidget {
  const CardDetailsScreen({
    super.key,
    required this.cardName,
    required this.color,
    required this.initial,
    this.scanner,
    this.scanOnOpen = false,
  });

  final String cardName;
  final Color color;
  final CardDetails initial;
  final CardScanner? scanner;
  final bool scanOnOpen;

  @override
  State<CardDetailsScreen> createState() => _CardDetailsScreenState();
}

class _CardDetailsScreenState extends State<CardDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _number;
  late final TextEditingController _holder;
  late final TextEditingController _issuer;
  late final TextEditingController _expiry;
  late final TextEditingController _cvv;
  final _issuerFocus = FocusNode();
  late CardScheme _scheme;
  late CardProduct _product;
  bool _schemeTouched = false;
  bool _issuerTouched = false;
  bool _showCvv = false;
  bool _scanning = false; // camera or picker open, or OCR running
  bool _reading = false; // OCR running (shows the progress bar)
  bool _numberUnverified = false;
  late final CardScanner _scanner = widget.scanner ?? CardScanner();

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _number = TextEditingController(text: formatPan(d.number));
    _holder = TextEditingController(text: d.holder);
    _issuer = TextEditingController(text: d.issuer);
    _expiry = TextEditingController(text: d.expiry);
    _cvv = TextEditingController(text: d.cvv);
    _scheme = d.scheme;
    _product = d.product;
    _schemeTouched = d.scheme != CardScheme.unknown;
    _issuerTouched = d.issuer.isNotEmpty;
    for (final c in [_number, _holder, _expiry]) {
      c.addListener(() => setState(() {}));
    }
    if (widget.scanOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    }
  }

  @override
  void dispose() {
    for (final c in [_number, _holder, _issuer, _expiry, _cvv]) {
      c.dispose();
    }
    _issuerFocus.dispose();
    super.dispose();
  }

  void _onNumberChanged(String value) {
    final digits = digitsOnly(value);
    setState(() {
      _numberUnverified = false;
      if (!_schemeTouched) _scheme = detectScheme(digits);
      if (!_issuerTouched) {
        final issuer = issuerFromNumber(digits);
        if (issuer != null) _issuer.text = issuer;
      }
    });
  }

  Future<void> _scan({bool fromGallery = false}) async {
    if (_scanning) return;
    setState(() => _scanning = true);
    CardScanResult? r;
    String? error;
    try {
      r = await _scanner.scan(
        fromGallery: fromGallery,
        onPhotoReady: () {
          if (mounted) setState(() => _reading = true);
        },
      );
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _reading = false;
    });
    final messenger = ScaffoldMessenger.of(context);
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not read the photo: $error')),
      );
      return;
    }
    if (r == null) return; // cancelled
    if (r.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No card details found. Try again with the card filling the frame, flat, no glare.',
          ),
        ),
      );
      return;
    }
    setState(() {
      if (r!.number != null) {
        _number.text = formatPan(r.number!);
        _numberUnverified = !r.numberVerified;
      }
      if (r.holder != null) _holder.text = r.holder!;
      if (r.expiry != null) _expiry.text = r.expiry!;
      if (r.scheme != null && r.scheme != CardScheme.unknown) {
        _scheme = r.scheme!;
        _schemeTouched = true;
      }
      if (r.product != null) _product = r.product!;
      if (r.issuer != null) {
        _issuer.text = r.issuer!;
        _issuerTouched = true;
      }
    });
    HapticFeedback.mediumImpact();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Filled ${r.foundFields.join(', ')}. Check them, then add the CVV from the back.',
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      CardDetails(
        number: digitsOnly(_number.text),
        holder: _holder.text.trim().toUpperCase(),
        scheme: _scheme,
        product: _product,
        issuer: _issuer.text.trim(),
        expiry: _expiry.text.trim(),
        cvv: _cvv.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final digits = digitsOnly(_number.text);
    final luhnOk = digits.isEmpty || luhnValid(digits);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Card details'),
        actions: [
          TextButton(
            onPressed: _scanning ? null : _save,
            child: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              WalletCardFace(
                title: widget.cardName,
                subtitle: _issuer.text.isEmpty ? null : _issuer.text,
                color: widget.color,
                last4: digits.length >= 4 ? last4Of(digits) : null,
                holder: _holder.text,
                expiry: _expiry.text.length == 5 ? _expiry.text : null,
                scheme: _scheme,
                footnote: 'Fill in the details below or scan the card',
                elevated: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _scanning ? null : () => _scan(),
                      icon: const Icon(LucideIcons.scanLine, size: 18),
                      label: const Text('Scan card'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _scanning
                          ? null
                          : () => _scan(fromGallery: true),
                      icon: const Icon(LucideIcons.image, size: 18),
                      label: const Text('From photo'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                ],
              ),
              if (_reading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                Text(
                  'Reading card on this phone…',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'The photo is read on the phone and deleted right away. The card number and CVV are '
                'stored encrypted and need your fingerprint or passcode to view.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // ── Card number
              TextFormField(
                controller: _number,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.creditCardNumber],
                inputFormatters: [_PanFormatter()],
                onChanged: _onNumberChanged,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                  letterSpacing: 1,
                ),
                decoration: InputDecoration(
                  labelText: 'Card number',
                  prefixIcon: const Icon(LucideIcons.creditCard),
                  border: const OutlineInputBorder(),
                  helperText: _numberUnverified
                      ? 'Read from the photo but the check digit fails: compare with the card'
                      : (!luhnOk
                            ? 'Check digit does not match: please double-check'
                            : null),
                  helperStyle: TextStyle(
                    color: (_numberUnverified || !luhnOk) ? cs.error : null,
                  ),
                ),
                validator: (v) {
                  final d = digitsOnly(v ?? '');
                  if (d.isEmpty) return null; // details are optional
                  if (d.length < 12 || d.length > 19) {
                    return 'Card numbers have 12–19 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── Cardholder
              TextFormField(
                controller: _holder,
                textCapitalization: TextCapitalization.characters,
                autofillHints: const [AutofillHints.creditCardName],
                decoration: const InputDecoration(
                  labelText: 'Cardholder name',
                  prefixIcon: Icon(LucideIcons.user),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // ── Expiry + CVV
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _expiry,
                      keyboardType: TextInputType.number,
                      autofillHints: const [
                        AutofillHints.creditCardExpirationDate,
                      ],
                      inputFormatters: [_ExpiryFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Expiry',
                        hintText: 'MM/YY',
                        prefixIcon: Icon(LucideIcons.calendar),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        return parseExpiry(v) == null ? 'Use MM/YY' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _cvv,
                      keyboardType: TextInputType.number,
                      obscureText: !_showCvv,
                      autofillHints: const [
                        AutofillHints.creditCardSecurityCode,
                      ],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: InputDecoration(
                        labelText: 'CVV',
                        prefixIcon: const Icon(LucideIcons.lock),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _showCvv ? 'Hide CVV' : 'Show CVV',
                          icon: Icon(
                            _showCvv ? LucideIcons.eyeOff : LucideIcons.eye,
                          ),
                          onPressed: () => setState(() => _showCvv = !_showCvv),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        return (v.length < 3) ? '3–4 digits' : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Issuer (bank) with suggestions
              RawAutocomplete<String>(
                textEditingController: _issuer,
                focusNode: _issuerFocus,
                optionsBuilder: (value) {
                  final q = value.text.trim().toLowerCase();
                  if (q.isEmpty) return const Iterable<String>.empty();
                  return kIssuers
                      .map((i) => i.name)
                      .where((n) => n.toLowerCase().contains(q))
                      .take(6);
                },
                onSelected: (_) => setState(() => _issuerTouched = true),
                fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
                    TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() => _issuerTouched = true),
                      decoration: const InputDecoration(
                        labelText: 'Issuing bank',
                        prefixIcon: Icon(LucideIcons.landmark),
                        border: OutlineInputBorder(),
                      ),
                    ),
                optionsViewBuilder: (context, onSelected, options) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: 240,
                        maxWidth: MediaQuery.sizeOf(context).width - 32,
                      ),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: [
                          for (final o in options)
                            ListTile(
                              title: Text(o),
                              onTap: () => onSelected(o),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Scheme
              Text(
                'Card network',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in CardScheme.values)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: _scheme == s,
                      onSelected: (_) => setState(() {
                        _scheme = s;
                        _schemeTouched = true;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Product
              Text('Card type', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<CardProduct>(
                showSelectedIcon: false,
                segments: [
                  for (final p in CardProduct.values)
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {_product},
                onSelectionChanged: (s) => setState(() => _product = s.first),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _scanning ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Save card details'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps only digits (max 19) and groups them like the card prints them.
class _PanFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var d = digitsOnly(newValue.text);
    if (d.length > 19) d = d.substring(0, 19);
    final text = formatPan(d);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// `MMYY` → `MM/YY` while typing.
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var d = digitsOnly(newValue.text);
    if (d.length > 4) d = d.substring(0, 4);
    final deleting = newValue.text.length < oldValue.text.length;
    final text = d.length > 2 || (d.length == 2 && !deleting)
        ? '${d.substring(0, 2)}/${d.substring(2)}'
        : d;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
