import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/utils/app_exception.dart';

/// Where the private key lives. On phones: Keychain (iOS) / Keystore-backed
/// storage (Android). It never leaves the device and is never uploaded.
abstract class KeyVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureKeyVault implements KeyVault {
  const SecureKeyVault();
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}

class MemoryKeyVault implements KeyVault {
  final _data = <String, String>{};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

/// Encrypted media plus the one-time key needed to open it.
class EncryptedMedia {
  const EncryptedMedia(this.bytes, this.key);
  final Uint8List bytes;
  final String key;
}

/// End-to-end encryption for chats, in the spirit of WhatsApp:
///
///  * every phone has an X25519 key pair; only the public key is shared
///    (through the server, with your matches only);
///  * both phones derive the same conversation key from their own private key
///    and the other's public key (ECDH) + HKDF-SHA256 bound to the conversation;
///  * text is sealed with AES-256-GCM, so the server only relays ciphertext;
///  * photos are sealed with a fresh random AES-256-GCM key each, and that key
///    travels inside an encrypted message.
///
/// Unlike WhatsApp's Signal protocol there is no per-message key ratchet, so a
/// stolen private key could open old ciphertext; history itself is never kept
/// on the server, which limits that risk.
class ChatCrypto {
  ChatCrypto({
    required KeyVault vault,
    required String userId,
    required Future<String?> Function(String userId) fetchPublicKey,
  }) : _vault = vault,
       _userId = userId,
       _fetchPublicKey = fetchPublicKey;

  final KeyVault _vault;
  final String _userId;
  final Future<String?> Function(String userId) _fetchPublicKey;

  static final _x25519 = X25519();
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  Future<SimpleKeyPair>? _keyPair;
  final _publicKeys = <String, String>{};
  final _sharedKeys = <String, SecretKey>{};

  String get _vaultKey => 'woops_chat_key_$_userId';

  /// Loads (or creates once) this phone's key pair. Concurrent callers share
  /// one attempt, so two keys are never generated.
  Future<SimpleKeyPair> _myKeyPair() => _keyPair ??= _loadOrCreate().catchError((Object e) {
    _keyPair = null;
    throw e;
  });

  Future<SimpleKeyPair> _loadOrCreate() async {
    final stored = await _vault.read(_vaultKey);
    if (stored != null) return _x25519.newKeyPairFromSeed(base64Decode(stored));
    final pair = await _x25519.newKeyPair();
    await _vault.write(_vaultKey, base64Encode(await pair.extractPrivateKeyBytes()));
    return pair;
  }

  /// This phone's public key (base64), to publish with `set_my_chat_key`.
  Future<String> myPublicKey() async => base64Encode((await (await _myKeyPair()).extractPublicKey()).bytes);

  Future<String?> _theirKey(String userId) async {
    final cached = _publicKeys[userId];
    if (cached != null) return cached;
    final key = await _fetchPublicKey(userId);
    if (key != null) _publicKeys[userId] = key;
    return key;
  }

  /// Forget a cached key (e.g. after a "couldn't decrypt", they may have a new phone).
  void forget(String userId) => _publicKeys.remove(userId);

  /// True if the other person's app can receive encrypted messages.
  Future<bool> canEncryptTo(String userId) async => await _theirKey(userId) != null;

  Future<SecretKey> _conversationKey(String theirPublicKey, String conversationId) async {
    final cacheKey = '$conversationId|$theirPublicKey';
    final cached = _sharedKeys[cacheKey];
    if (cached != null) return cached;
    final shared = await _x25519.sharedSecretKey(
      keyPair: await _myKeyPair(),
      remotePublicKey: SimplePublicKey(base64Decode(theirPublicKey), type: KeyPairType.x25519),
    );
    final key = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('woops-chat-v1'),
      info: utf8.encode(conversationId),
    );
    return _sharedKeys[cacheKey] = key;
  }

  /// Seals [plaintext] for [otherUserId]. The envelope names both public keys,
  /// so the receiver can always derive the same key.
  Future<String> encrypt(String plaintext, {required String conversationId, required String otherUserId}) async {
    final theirs = await _theirKey(otherUserId);
    if (theirs == null) {
      throw const AppException('Ask your match to update Woops so you can chat securely.', code: 'no_chat_key');
    }
    final mine = await myPublicKey();
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: await _conversationKey(theirs, conversationId),
      aad: utf8.encode(conversationId),
    );
    return jsonEncode({
      'v': 1,
      's': mine,
      'r': theirs,
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    });
  }

  /// Opens an envelope sealed by either side of the conversation.
  Future<String> decrypt(String envelope, {required String conversationId}) async {
    final j = jsonDecode(envelope) as Map<String, dynamic>;
    final mine = await myPublicKey();
    // If I sent it, the other key is the recipient's; otherwise the sender's.
    final other = j['s'] == mine ? j['r'] as String : j['s'] as String;
    final clear = await _aes.decrypt(
      SecretBox(
        base64Decode(j['c'] as String),
        nonce: base64Decode(j['n'] as String),
        mac: Mac(base64Decode(j['m'] as String)),
      ),
      secretKey: await _conversationKey(other, conversationId),
      aad: utf8.encode(conversationId),
    );
    return utf8.decode(clear);
  }

  /// Seals a photo with a fresh random key (returned base64).
  Future<EncryptedMedia> encryptBytes(Uint8List bytes) async {
    final key = await _aes.newSecretKey();
    final box = await _aes.encrypt(bytes, secretKey: key);
    return EncryptedMedia(box.concatenation(), base64Encode(await key.extractBytes()));
  }

  Future<Uint8List> decryptBytes(Uint8List sealed, String key) async {
    final box = SecretBox.fromConcatenation(sealed, nonceLength: 12, macLength: 16);
    return Uint8List.fromList(await _aes.decrypt(box, secretKey: SecretKey(base64Decode(key))));
  }
}
