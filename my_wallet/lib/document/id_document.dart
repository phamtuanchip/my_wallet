import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// Kinds of personal documents kept in the vault. [hasChip] kinds can be read
/// over NFC (ICAO eMRTD); the others are stored as front/back photos + fields.
enum DocumentKind {
  cccd('CCCD (chip ID card)', 'Căn cước công dân', Color(0xFF2B5DA8), hasChip: true),
  passport('Passport', 'Hộ chiếu', Color(0xFF1F5E46), hasChip: true),
  carLicense('Car driving licence', 'Bằng lái ô tô', Color(0xFFB0476B)),
  motoLicense('Motorbike licence', 'Bằng lái xe máy', Color(0xFFC0702E)),
  vehicleRegistration('Vehicle registration', 'Giấy đăng ký xe', Color(0xFF5A5FB5)),
  insurance('Vehicle insurance', 'Bảo hiểm xe', Color(0xFF2E8C8C)),
  other('Other document', 'Giấy tờ khác', Color(0xFF5B5B60));

  const DocumentKind(this.label, this.vnLabel, this.color, {this.hasChip = false});

  final String label;
  final String vnLabel;
  final Color color;
  final bool hasChip;

  static DocumentKind fromName(String? name) =>
      DocumentKind.values.where((k) => k.name == name).firstOrNull ?? DocumentKind.other;

  /// Fields shown in the form, in order. Extra keys read from a chip that are
  /// not listed here (e.g. parents' names) are still saved and shown when set.
  List<DocumentField> get fields => switch (this) {
        DocumentKind.cccd => const [
            DocumentField.number,
            DocumentField.holder,
            DocumentField.dob,
            DocumentField.sex,
            DocumentField.nationality,
            DocumentField.hometown,
            DocumentField.residence,
            DocumentField.issueDate,
            DocumentField.expiry,
          ],
        DocumentKind.passport => const [
            DocumentField.passportNumber,
            DocumentField.holder,
            DocumentField.dob,
            DocumentField.sex,
            DocumentField.nationality,
            DocumentField.issueDate,
            DocumentField.expiry,
            DocumentField.issuePlace,
          ],
        DocumentKind.carLicense || DocumentKind.motoLicense => const [
            DocumentField.number,
            DocumentField.holder,
            DocumentField.dob,
            DocumentField.licenseClass,
            DocumentField.issueDate,
            DocumentField.expiry,
            DocumentField.issuePlace,
          ],
        DocumentKind.vehicleRegistration => const [
            DocumentField.plate,
            DocumentField.owner,
            DocumentField.brand,
            DocumentField.model,
            DocumentField.vehicleColor,
            DocumentField.chassisNumber,
            DocumentField.engineNumber,
            DocumentField.issueDate,
          ],
        DocumentKind.insurance => const [
            DocumentField.number,
            DocumentField.plate,
            DocumentField.owner,
            DocumentField.issueDate,
            DocumentField.expiry,
          ],
        DocumentKind.other => const [
            DocumentField.number,
            DocumentField.holder,
            DocumentField.issueDate,
            DocumentField.expiry,
          ],
      };

  /// Field holding the document's main number (used for the masked list label).
  DocumentField get numberField => switch (this) {
        DocumentKind.passport => DocumentField.passportNumber,
        DocumentKind.vehicleRegistration => DocumentField.plate,
        _ => DocumentField.number,
      };
}

enum FieldType { text, date, number, multiline }

/// One form field. [key] is what is stored in the encrypted JSON.
enum DocumentField {
  number('number', 'Number', 'Số', FieldType.number),
  passportNumber('passportNumber', 'Passport number', 'Số hộ chiếu', FieldType.text),
  holder('holder', 'Full name', 'Họ và tên', FieldType.text),
  dob('dob', 'Date of birth', 'Ngày sinh', FieldType.date),
  sex('sex', 'Sex', 'Giới tính', FieldType.text),
  nationality('nationality', 'Nationality', 'Quốc tịch', FieldType.text),
  hometown('hometown', 'Place of origin', 'Quê quán', FieldType.multiline),
  residence('residence', 'Place of residence', 'Nơi thường trú', FieldType.multiline),
  issueDate('issueDate', 'Issue date', 'Ngày cấp', FieldType.date),
  expiry('expiry', 'Valid until', 'Có giá trị đến', FieldType.date),
  issuePlace('issuePlace', 'Issued by / at', 'Nơi cấp', FieldType.text),
  licenseClass('licenseClass', 'Class', 'Hạng', FieldType.text),
  plate('plate', 'Plate number', 'Biển số', FieldType.text),
  owner('owner', 'Owner', 'Chủ xe', FieldType.text),
  brand('brand', 'Brand', 'Nhãn hiệu', FieldType.text),
  model('model', 'Model', 'Số loại', FieldType.text),
  vehicleColor('vehicleColor', 'Colour', 'Màu sơn', FieldType.text),
  chassisNumber('chassisNumber', 'Chassis number', 'Số khung', FieldType.text),
  engineNumber('engineNumber', 'Engine number', 'Số máy', FieldType.text),
  ethnicity('ethnicity', 'Ethnicity', 'Dân tộc', FieldType.text),
  religion('religion', 'Religion', 'Tôn giáo', FieldType.text),
  features('features', 'Identifying features', 'Đặc điểm nhận dạng', FieldType.multiline),
  father('father', "Father's name", 'Họ tên cha', FieldType.text),
  mother('mother', "Mother's name", 'Họ tên mẹ', FieldType.text),
  spouse('spouse', 'Spouse', 'Vợ/chồng', FieldType.text),
  oldIdNumber('oldIdNumber', 'Old ID (CMND)', 'Số CMND cũ', FieldType.number),
  notes('notes', 'Notes', 'Ghi chú', FieldType.multiline);

  const DocumentField(this.key, this.label, this.vnLabel, this.type);

  final String key;
  final String label;
  final String vnLabel;
  final FieldType type;

  static DocumentField? fromKey(String key) => DocumentField.values.where((f) => f.key == key).firstOrNull;
}

/// List row: only non-secret metadata is stored in clear.
class IdDocument {
  const IdDocument({
    required this.id,
    required this.kind,
    required this.title,
    this.numberLast4,
    required this.hasChipData,
    this.frontFile,
    this.backFile,
    this.faceFile,
    this.dataEnc,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final DocumentKind kind;
  final String title;
  final String? numberLast4;
  final bool hasChipData;
  final String? frontFile; // encrypted file names inside the documents folder
  final String? backFile;
  final String? faceFile;
  final String? dataEnc; // AES-GCM token of the JSON fields
  final DateTime createdAt;
  final DateTime updatedAt;

  factory IdDocument.fromMap(Map<String, Object?> m) => IdDocument(
        id: m['id'] as String,
        kind: DocumentKind.fromName(m['kind'] as String?),
        title: m['title'] as String? ?? '',
        numberLast4: m['number_last4'] as String?,
        hasChipData: (m['has_chip_data'] as int? ?? 0) == 1,
        frontFile: m['front_file'] as String?,
        backFile: m['back_file'] as String?,
        faceFile: m['face_file'] as String?,
        dataEnc: m['data_enc'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int? ?? 0),
      );
}

/// Decrypted contents edited on the document screen.
class DocumentContent {
  DocumentContent({
    required this.kind,
    this.title = '',
    Map<String, String>? fields,
    this.front,
    this.back,
    this.face,
    this.hasChipData = false,
  }) : fields = fields ?? {};

  final DocumentKind kind;
  String title;
  final Map<String, String> fields;
  Uint8List? front;
  Uint8List? back;
  Uint8List? face; // photo from the chip (JPEG, or JPEG 2000 that Flutter can't show)
  bool hasChipData;

  String get number => fields[kind.numberField.key] ?? '';

  String get defaultTitle {
    final name = fields['holder'] ?? fields['owner'] ?? '';
    return name.isEmpty ? kind.label : '${kind.vnLabel} · $name';
  }
}

/// Last 4 characters of a number, for the list (never the whole number).
String? maskedTail(String number) {
  final clean = number.replaceAll(RegExp(r'[\s.\-]'), '');
  if (clean.length < 4) return null;
  return clean.substring(clean.length - 4);
}
