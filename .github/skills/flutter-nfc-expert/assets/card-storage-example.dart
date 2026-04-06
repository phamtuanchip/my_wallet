import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

/// SQLite database layer for persisting NFC card data
class CardStorageService {
  static final CardStorageService _instance = CardStorageService._internal();
  static Database? _database;
  
  factory CardStorageService() {
    return _instance;
  }
  
  CardStorageService._internal();
  
  // Table names
  static const String cardsTable = 'cards';
  static const String transactionsTable = 'transactions';
  static const String cardMetadataTable = 'card_metadata';
  
  /// Initialize database connection
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  /// Create and open database
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'nfc_cards.db');
    
    // Check if database exists, else create from scratch
    final exists = await databaseExists(path);
    if (!exists) {
      // Create tables using SQL script
      final db = await openDatabase(
        path,
        version: 1,
        onCreate: _createTables,
      );
      return db;
    } else {
      return await openDatabase(path);
    }
  }
  
  /// Create all required tables
  Future<void> _createTables(Database db, int version) async {
    // Main cards table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $cardsTable (
        id TEXT PRIMARY KEY,                      -- UUID
        uid TEXT NOT NULL,                        -- NFC hardware UID
        card_type TEXT,                           -- Mifare Classic/Ultralight/NDEF
        content TEXT,                             -- Raw NDEF payload (JSON)
        formatted_content TEXT,                   -- Human-readable parsed content
        tags TEXT,                                -- JSON array of tags (wallet, payment, etc.)
        balance REAL,                             -- Card balance if applicable
        discovered_at INTEGER NOT NULL,           -- Epoch timestamp
        last_scanned INTEGER,                     -- Last scan timestamp
        scan_count INTEGER DEFAULT 1,             -- Number of times this card was scanned
        notes TEXT,                               -- User notes
        is_favorite BOOLEAN DEFAULT 0,            -- User marked as favorite
        UNIQUE(uid)                               -- Prevent duplicate UIDs
      )
    ''');
    
    // Transactions table (for card emulation/payments)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $transactionsTable (
        id TEXT PRIMARY KEY,
        card_id TEXT NOT NULL,
        transaction_type TEXT,                    -- 'read', 'write', 'payment', 'emulation'
        amount REAL,
        description TEXT,
        status TEXT,                              -- 'pending', 'success', 'failed'
        timestamp INTEGER NOT NULL,
        reader_id TEXT,                           -- External POS/terminal ID
        FOREIGN KEY (card_id) REFERENCES $cardsTable(id)
      )
    ''');
    
    // Card metadata for custom fields
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $cardMetadataTable (
        id TEXT PRIMARY KEY,
        card_id TEXT NOT NULL,
        key TEXT NOT NULL,                        -- Metadata key
        value TEXT,                               -- Metadata value
        FOREIGN KEY (card_id) REFERENCES $cardsTable(id),
        UNIQUE(card_id, key)
      )
    ''');
    
    // Create indexes for faster queries
    await db.execute('CREATE INDEX idx_uid ON $cardsTable(uid)');
    await db.execute('CREATE INDEX idx_discovered_at ON $cardsTable(discovered_at)');
    await db.execute('CREATE INDEX idx_card_id_transaction ON $transactionsTable(card_id)');
  }
  
  /// Store a scanned NFC card
  Future<String> saveCard({
    required String uid,
    required String cardType,
    required Map<String, dynamic> ndefContent,
    required String formattedContent,
    List<String> tags = const [],
    double? balance,
    String? notes,
  }) async {
    final db = await database;
    final cardId = const Uuid().v4();
    
    // Check if card with this UID already exists
    final existingCard = await db.query(
      cardsTable,
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    
    if (existingCard.isNotEmpty) {
      // Update existing card
      final oldId = existingCard.first['id'];
      await db.update(
        cardsTable,
        {
          'last_scanned': DateTime.now().millisecondsSinceEpoch,
          'scan_count': (existingCard.first['scan_count'] as int) + 1,
        },
        where: 'id = ?',
        whereArgs: [oldId],
      );
      return oldId as String;
    }
    
    // Insert new card
    await db.insert(
      cardsTable,
      {
        'id': cardId,
        'uid': uid,
        'card_type': cardType,
        'content': jsonEncode(ndefContent),
        'formatted_content': formattedContent,
        'tags': jsonEncode(tags),
        'balance': balance,
        'discovered_at': DateTime.now().millisecondsSinceEpoch,
        'last_scanned': DateTime.now().millisecondsSinceEpoch,
        'scan_count': 1,
        'notes': notes,
      },
    );
    
    return cardId;
  }
  
  /// Retrieve all stored cards with pagination
  Future<List<ScannedCard>> getAllCards({
    int limit = 50,
    int offset = 0,
    String orderBy = 'discovered_at DESC',
  }) async {
    final db = await database;
    
    final results = await db.query(
      cardsTable,
      limit: limit,
      offset: offset,
      orderBy: orderBy,
    );
    
    return results.map((row) => ScannedCard.fromMap(row)).toList();
  }
  
  /// Find duplicate cards (same UID scanned multiple times)
  Future<List<DuplicateCardGroup>> findDuplicateCards() async {
    final db = await database;
    
    // Group by UID and count occurrences
    final results = await db.rawQuery('''
      SELECT uid, COUNT(*) as scan_count
      FROM $cardsTable
      GROUP BY uid
      HAVING COUNT(*) > 1
      ORDER BY scan_count DESC
    ''');
    
    List<DuplicateCardGroup> duplicates = [];
    for (final row in results) {
      final uid = row['uid'] as String;
      final count = row['scan_count'] as int;
      
      // Get all scans for this UID
      final cards = await db.query(
        cardsTable,
        where: 'uid = ?',
        whereArgs: [uid],
        orderBy: 'discovered_at DESC',
      );
      
      duplicates.add(DuplicateCardGroup(
        uid: uid,
        scanCount: count,
        cards: cards.map((c) => ScannedCard.fromMap(c)).toList(),
      ));
    }
    
    return duplicates;
  }
  
  /// Get a card by ID
  Future<ScannedCard?> getCardById(String cardId) async {
    final db = await database;
    
    final results = await db.query(
      cardsTable,
      where: 'id = ?',
      whereArgs: [cardId],
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    return ScannedCard.fromMap(results.first);
  }
  
  /// Get a card by UID
  Future<ScannedCard?> getCardByUid(String uid) async {
    final db = await database;
    
    final results = await db.query(
      cardsTable,
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    return ScannedCard.fromMap(results.first);
  }
  
  /// Search cards by tag
  Future<List<ScannedCard>> getCardsByTag(String tag) async {
    final db = await database;
    
    // LIKE search for tag in JSON array
    final results = await db.query(
      cardsTable,
      where: "tags LIKE ?",
      whereArgs: ['%$tag%'],
    );
    
    return results.map((row) => ScannedCard.fromMap(row)).toList();
  }
  
  /// Update card metadata
  Future<void> updateCard({
    required String cardId,
    String? notes,
    double? balance,
    bool? isFavorite,
    List<String>? tags,
  }) async {
    final db = await database;
    
    final updates = <String, dynamic>{};
    if (notes != null) updates['notes'] = notes;
    if (balance != null) updates['balance'] = balance;
    if (isFavorite != null) updates['is_favorite'] = isFavorite ? 1 : 0;
    if (tags != null) updates['tags'] = jsonEncode(tags);
    updates['last_scanned'] = DateTime.now().millisecondsSinceEpoch;
    
    await db.update(
      cardsTable,
      updates,
      where: 'id = ?',
      whereArgs: [cardId],
    );
  }
  
  /// Delete a card by ID
  Future<void> deleteCard(String cardId) async {
    final db = await database;
    
    // Delete associated transactions
    await db.delete(
      transactionsTable,
      where: 'card_id = ?',
      whereArgs: [cardId],
    );
    
    // Delete associated metadata
    await db.delete(
      cardMetadataTable,
      where: 'card_id = ?',
      whereArgs: [cardId],
    );
    
    // Delete card
    await db.delete(
      cardsTable,
      where: 'id = ?',
      whereArgs: [cardId],
    );
  }
  
  /// Record a transaction (payment, emulation event, etc.)
  Future<void> recordTransaction({
    required String cardId,
    required String transactionType,
    required String status,
    String? description,
    double? amount,
    String? readerId,
  }) async {
    final db = await database;
    
    await db.insert(
      transactionsTable,
      {
        'id': const Uuid().v4(),
        'card_id': cardId,
        'transaction_type': transactionType,
        'amount': amount,
        'description': description,
        'status': status,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'reader_id': readerId,
      },
    );
  }
  
  /// Get transaction history for a card
  Future<List<Transaction>> getTransactions(String cardId) async {
    final db = await database;
    
    final results = await db.query(
      transactionsTable,
      where: 'card_id = ?',
      whereArgs: [cardId],
      orderBy: 'timestamp DESC',
    );
    
    return results.map((row) => Transaction.fromMap(row)).toList();
  }
  
  /// Export all cards to JSON
  Future<String> exportCardsAsJson() async {
    final db = await database;
    
    final results = await db.query(cardsTable);
    final cards = results.map((row) => ScannedCard.fromMap(row)).toList();
    
    return jsonEncode(cards.map((c) => c.toMap()).toList());
  }
  
  /// Clear all data (use with caution)
  Future<void> clearAllData() async {
    final db = await database;
    
    await db.delete(transactionsTable);
    await db.delete(cardMetadataTable);
    await db.delete(cardsTable);
  }
  
  /// Get database statistics
  Future<Map<String, dynamic>> getStats() async {
    final db = await database;
    
    final cardCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) as count FROM $cardsTable'),
    ) ?? 0;
    
    final totalScans = Sqflite.firstIntValue(
      await db.rawQuery('SELECT SUM(scan_count) as total FROM $cardsTable'),
    ) ?? 0;
    
    final transactionCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) as count FROM $transactionsTable'),
    ) ?? 0;
    
    return {
      'total_cards': cardCount,
      'total_scans': totalScans,
      'total_transactions': transactionCount,
    };
  }
}

// ============== Data Models ==============

class ScannedCard {
  final String id;
  final String uid;
  final String cardType;
  final Map<String, dynamic> content;
  final String formattedContent;
  final List<String> tags;
  final double? balance;
  final DateTime discoveredAt;
  final DateTime? lastScanned;
  final int scanCount;
  final String? notes;
  final bool isFavorite;
  
  ScannedCard({
    required this.id,
    required this.uid,
    required this.cardType,
    required this.content,
    required this.formattedContent,
    this.tags = const [],
    this.balance,
    required this.discoveredAt,
    this.lastScanned,
    this.scanCount = 1,
    this.notes,
    this.isFavorite = false,
  });
  
  factory ScannedCard.fromMap(Map<dynamic, dynamic> map) {
    return ScannedCard(
      id: map['id'] as String,
      uid: map['uid'] as String,
      cardType: map['card_type'] as String? ?? 'Unknown',
      content: jsonDecode(map['content'] as String? ?? '{}'),
      formattedContent: map['formatted_content'] as String? ?? '',
      tags: (jsonDecode(map['tags'] as String? ?? '[]') as List).cast<String>(),
      balance: (map['balance'] as num?)?.toDouble(),
      discoveredAt: DateTime.fromMillisecondsSinceEpoch(map['discovered_at'] as int),
      lastScanned: map['last_scanned'] != null 
        ? DateTime.fromMillisecondsSinceEpoch(map['last_scanned'] as int)
        : null,
      scanCount: map['scan_count'] as int? ?? 1,
      notes: map['notes'] as String?,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
    );
  }
  
  Map<String, dynamic> toMap() => {
    'id': id,
    'uid': uid,
    'cardType': cardType,
    'content': content,
    'formattedContent': formattedContent,
    'tags': tags,
    'balance': balance,
    'discoveredAt': discoveredAt.toIso8601String(),
    'lastScanned': lastScanned?.toIso8601String(),
    'scanCount': scanCount,
    'notes': notes,
    'isFavorite': isFavorite,
  };
}

class Transaction {
  final String id;
  final String cardId;
  final String transactionType;
  final double? amount;
  final String? description;
  final String status;
  final DateTime timestamp;
  final String? readerId;
  
  Transaction({
    required this.id,
    required this.cardId,
    required this.transactionType,
    this.amount,
    this.description,
    required this.status,
    required this.timestamp,
    this.readerId,
  });
  
  factory Transaction.fromMap(Map<dynamic, dynamic> map) {
    return Transaction(
      id: map['id'] as String,
      cardId: map['card_id'] as String,
      transactionType: map['transaction_type'] as String,
      amount: (map['amount'] as num?)?.toDouble(),
      description: map['description'] as String?,
      status: map['status'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      readerId: map['reader_id'] as String?,
    );
  }
}

class DuplicateCardGroup {
  final String uid;
  final int scanCount;
  final List<ScannedCard> cards;
  
  DuplicateCardGroup({
    required this.uid,
    required this.scanCount,
    required this.cards,
  });
}
