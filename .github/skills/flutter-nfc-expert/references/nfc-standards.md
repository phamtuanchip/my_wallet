# NFC Standards: Mifare & NDEF

## Mifare Card Types

### Mifare Classic
- **Capacity**: 1K (13 sectors × 16 blocks) or 4K (40 sectors × 16 blocks)
- **Block Size**: 16 bytes
- **Authentication**: Proprietary 6-byte key (Key A / Key B)
- **Sector Trailer**: Last block of each sector contains keys and access bits
- **Reading**: Requires authentication per sector
- **Common Use**: Parking, transit cards, access badges

**UID Access:**
```
Block 0 contains manufacturer data and UID (bytes 0-3)
```

**Sector Structure (1K example):**
```
Sector 0: Blocks 0-3 (Block 3 = sector trailer with keys)
Sector 1: Blocks 4-7 (Block 7 = sector trailer)
...
Sector 15: Blocks 60-63 (Block 63 = sector trailer)
```

### Mifare Ultralight
- **Capacity**: 64 bytes (all readable without authentication)
- **Block Size**: 4 bytes (16 blocks total)
- **Authentication**: None (open read)
- **UID**: Bytes 0-2 + byte 3 (7-byte total)
- **Use**: Lightweight applications, URLs, simple data

**Block Layout:**
```
Blocks 0-2: Header, manufacturer data
Blocks 3-14: User writable
Block 15: One-time programmable lock
```

### Mifare Plus
- **Enhanced security** over Classic
- **Supports NDEF** natively
- **Backward compatible** with some Classic commands

## NDEF (NFC Data Exchange Format)

NDEF is a standardized message format for encoding data on NFC tags.

### Key Concepts

**Record Structure:**
```
[Header] [Type Length] [Payload Length] [ID Length] [Type] [ID] [Payload]
```

**Header Fields:**
- **MB (Message Begin)**: 1 = first record
- **ME (Message End)**: 1 = last record
- **CF (Chunk Flag)**: Split across multiple records
- **SR (Short Record)**: Payload < 256 bytes
- **IL (ID Length)**: ID field present

### Record Types

**1. URI Record**
```
Type: "U" (0x55)
Payload: Prefix byte + URI string
Prefixes:
  0x00 = "http://www." 
  0x01 = "https://www."
  0x02 = "http://"
  0x03 = "https://"
  etc.

Example: Store "https://example.com"
Type: 0x55
Payload: 0x03 + "example.com"
```

**2. Text Record**
```
Type: "T" (0x54)
Payload: Status byte (language encoding) + text
Status byte format:
  Bit 7: Reserved (0)
  Bits 6-4: Encoding (000=UTF-8, 001=UTF-16)
  Bits 3-0: Language code length

Example: Store "Hello" in English (UTF-8)
Payload: 0x02 + "en" + "Hello"
```

**3. Mime Type Record**
```
Type: Custom MIME type (e.g., "application/octet-stream")
Payload: Raw binary data
Use: Structured data, JSON, protobuf

Example: Store JSON on card
Type: "application/json"
Payload: {"cardId": "12", "balance": 450}
```

**4. Smart Poster Record**
```
Type: "Sp" 
Contains nested records: Title + URI + optional icon
Use: Contextual information with URL
```

### NDEF Parsing Flow

```
1. Read raw bytes from card
2. Parse message header (MB, ME, CF, SR, IL, TNF bits)
3. Extract record type, length, payload length
4. For each record:
   a. Identify type (URI, Text, Mime, etc.)
   b. Parse payload according to type rules
   c. Handle special encoding (UTF-8, UTF-16)
5. Validate structure (checksum if applicable)
6. Return structured data
```

### TNF (Type Name Format) Values

```
0: Empty (no type/payload)
1: NFC Well-Known Type (T, U, Sp, etc.)
2: MIME type media-type
3: Absolute-URI
4: External type (domain-specific)
5: Unknown
6: Unchanged (chunked record)
7: Reserved
```

## UID Structure & Collision Detection

### Unique Identifier (UID)

**Mifare Classic/Plus:**
- 4-byte or 7-byte UID
- Byte 0-2: Manufacturer code
- Byte 3 (4-byte): Check digit (BCC = ISO/IEC 14443-3)
- Bytes 4-7 (7-byte): Extended UID

**BCC Calculation (4-byte):**
```
BCC = Byte0 XOR Byte1 XOR Byte2 XOR Byte3
If BCC is valid: BCC = 0x00 (XOR of all 4 bytes)
```

### Duplicate Detection

In SQLite, detect repeated scans of same physical card:
```sql
SELECT uid, COUNT(*) as scan_count 
FROM cards 
GROUP BY uid 
HAVING count(*) > 1
ORDER BY discoveredAt DESC
```

## Common Issues with NDEF

| Issue | Cause | Solution |
|-------|-------|----------|
| Parse fails on legacy tags | Card uses non-standard format | Try raw hex dump first |
| UTF-16 text corrupted | Encoding mismatch | Check status byte encoding bits |
| Payload truncated | SR (Short Record) flag misread | Validate record header parsing |
| MIME type not recognized | Case sensitivity | Normalize to lowercase |

## References

- NFC Forum Type 1-4 specifications
- NDEF RFC (NFCpy library documentation)
- Mifare Classic datasheet
- Android NFC stack source code
