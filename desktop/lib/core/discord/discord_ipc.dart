import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Minimal Discord local-RPC client — just enough to set and clear Rich
/// Presence. Talks to the running Discord desktop app over its IPC endpoint:
/// a Unix domain socket on Linux, a named pipe on Windows.
///
/// Wire format: every frame is `[int32 LE opcode][int32 LE length][JSON]`.
/// Request/response only — each write is followed by reading until the
/// matching reply, so no background read loop is needed (which keeps the
/// Windows pipe single-threaded).
class DiscordIpcClient {
  DiscordIpcClient(this.clientId);

  final String clientId;
  _Transport? _transport;

  static const _opHandshake = 0;
  static const _opFrame = 1;
  static const _opClose = 2;
  static const _opPing = 3;
  static const _opPong = 4;

  static const _replyTimeout = Duration(seconds: 5);

  bool get isConnected => _transport != null;

  static bool get isSupported => Platform.isLinux || Platform.isWindows;

  /// Connects to the first reachable `discord-ipc-{0..9}` endpoint and performs
  /// the handshake. Throws if Discord isn't running or rejects the client ID.
  Future<void> connect() async {
    if (_transport != null) return;
    final transport = await _openTransport();
    try {
      await _writeFrame(transport, _opHandshake, {'v': 1, 'client_id': clientId});
      final reply = await _readReply(transport, nonce: null);
      if (reply['evt'] != 'READY') {
        throw DiscordIpcException('Handshake rejected: ${reply['data']}');
      }
      _transport = transport;
    } catch (_) {
      await transport.close();
      rethrow;
    }
  }

  /// Sets the activity, or clears it when [activity] is null.
  Future<void> setActivity(Map<String, dynamic>? activity) async {
    final transport = _transport;
    if (transport == null) throw const DiscordIpcException('Not connected');
    final nonce = _nonce();
    try {
      await _writeFrame(transport, _opFrame, {
        'cmd': 'SET_ACTIVITY',
        'args': {'pid': pid, 'activity': activity},
        'nonce': nonce,
      });
      final reply = await _readReply(transport, nonce: nonce);
      if (reply['evt'] == 'ERROR') {
        // Discord answered, so the connection is still healthy — only the
        // payload was refused.
        throw DiscordIpcException('SET_ACTIVITY rejected: ${reply['data']}',
            rejected: true);
      }
    } on DiscordIpcException {
      rethrow;
    } catch (e) {
      await close();
      throw DiscordIpcException('Connection lost: $e');
    }
  }

  Future<void> close() async {
    final transport = _transport;
    _transport = null;
    if (transport == null) return;
    try {
      await _writeFrame(transport, _opClose, const {});
    } catch (_) {}
    await transport.close();
  }

  // ── Framing ───────────────────────────────────────────────────────────────

  Future<void> _writeFrame(
      _Transport transport, int op, Map<String, dynamic> payload) {
    final body = utf8.encode(jsonEncode(payload));
    final header = ByteData(8)
      ..setInt32(0, op, Endian.little)
      ..setInt32(4, body.length, Endian.little);
    final frame = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(body);
    return transport.write(frame.takeBytes());
  }

  /// Reads frames until a reply arrives: the handshake's READY dispatch when
  /// [nonce] is null, otherwise the response carrying [nonce]. Answers pings
  /// along the way.
  Future<Map<String, dynamic>> _readReply(_Transport transport,
      {required String? nonce}) async {
    final deadline = DateTime.now().add(_replyTimeout);
    while (true) {
      final header = ByteData.sublistView(await transport.read(8, deadline));
      final op = header.getInt32(0, Endian.little);
      final length = header.getInt32(4, Endian.little);
      final body = await transport.read(length, deadline);
      final payload = length == 0
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(body)) as Map<String, dynamic>;

      switch (op) {
        case _opPing:
          await _writeFrame(transport, _opPong, payload);
        case _opClose:
          throw DiscordIpcException(
              'Discord closed the connection: ${payload['message']}');
        case _opFrame:
          if (nonce == null || payload['nonce'] == nonce) return payload;
      }
    }
  }

  static String _nonce() {
    final rng = Random();
    return List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  // ── Endpoint discovery ────────────────────────────────────────────────────

  static Future<_Transport> _openTransport() async {
    if (Platform.isWindows) {
      for (var i = 0; i < 10; i++) {
        final pipe = _PipeTransport.open(r'\\.\pipe\discord-ipc-' '$i');
        if (pipe != null) return pipe;
      }
    } else if (Platform.isLinux) {
      for (final dir in _unixSocketDirs()) {
        for (var i = 0; i < 10; i++) {
          final path = p.join(dir, 'discord-ipc-$i');
          if (FileSystemEntity.typeSync(path) ==
              FileSystemEntityType.notFound) {
            continue;
          }
          try {
            return await _SocketTransport.connect(path);
          } catch (_) {
            // Stale socket from a crashed client — try the next one.
          }
        }
      }
    }
    throw const DiscordIpcException('Discord is not running');
  }

  /// Discord places its socket in the runtime dir; Flatpak and Snap builds nest
  /// it one level deeper.
  static List<String> _unixSocketDirs() {
    final env = Platform.environment;
    final base = env['XDG_RUNTIME_DIR'] ??
        env['TMPDIR'] ??
        env['TMP'] ??
        env['TEMP'] ??
        '/tmp';
    return [
      base,
      p.join(base, 'app', 'com.discordapp.Discord'),
      p.join(base, 'app', 'com.discordapp.DiscordCanary'),
      p.join(base, '.flatpak', 'dev.vencord.Vesktop', 'xdg-run'),
      p.join(base, 'snap.discord'),
      p.join(base, 'snap.discord-canary'),
    ];
  }
}

class DiscordIpcException implements Exception {
  const DiscordIpcException(this.message, {this.rejected = false});
  final String message;

  /// Discord refused the payload itself; resending it unchanged won't help.
  final bool rejected;
  @override
  String toString() => 'DiscordIpcException: $message';
}

// ── Transports ──────────────────────────────────────────────────────────────

abstract class _Transport {
  Future<void> write(Uint8List bytes);

  /// Reads exactly [count] bytes, failing once [deadline] passes.
  Future<Uint8List> read(int count, DateTime deadline);

  Future<void> close();
}

class _SocketTransport implements _Transport {
  _SocketTransport(this._socket) {
    _sub = _socket.listen(
      (chunk) {
        _buffer.add(chunk);
        _wake();
      },
      onError: (Object e) {
        _error = e;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
    );
  }

  static Future<_SocketTransport> connect(String path) async {
    final socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 2),
    );
    return _SocketTransport(socket);
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _sub;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  Completer<void>? _waiter;
  Object? _error;
  bool _done = false;

  void _wake() {
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  @override
  Future<void> write(Uint8List bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  @override
  Future<Uint8List> read(int count, DateTime deadline) async {
    while (_buffer.length < count) {
      if (_error != null) throw _error!;
      if (_done) throw const SocketException('Discord socket closed');
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) throw TimeoutException('Discord IPC read');
      _waiter = Completer<void>();
      await _waiter!.future.timeout(remaining, onTimeout: () {});
    }
    final all = _buffer.takeBytes();
    if (all.length > count) _buffer.add(Uint8List.sublistView(all, count));
    return Uint8List.sublistView(all, 0, count);
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    _socket.destroy();
  }
}

/// Windows named pipe via kernel32. Reads poll [_peekNamedPipe] so a stalled
/// Discord can never block the UI isolate inside a synchronous ReadFile.
class _PipeTransport implements _Transport {
  _PipeTransport._(this._handle);

  final int _handle;
  bool _closed = false;

  static const _genericRead = 0x80000000;
  static const _genericWrite = 0x40000000;
  static const _openExisting = 3;
  static const _invalidHandle = -1;

  static final _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final _createFile = _kernel32.lookupFunction<
      IntPtr Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Uint32,
          Uint32, IntPtr),
      int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int,
          int)>('CreateFileW');

  static final _writeFile = _kernel32.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>,
          Pointer<Void>),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>,
          Pointer<Void>)>('WriteFile');

  static final _readFile = _kernel32.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>,
          Pointer<Void>),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>,
          Pointer<Void>)>('ReadFile');

  static final _peekNamedPipe = _kernel32.lookupFunction<
      Int32 Function(IntPtr, Pointer<Void>, Uint32, Pointer<Uint32>,
          Pointer<Uint32>, Pointer<Uint32>),
      int Function(int, Pointer<Void>, int, Pointer<Uint32>, Pointer<Uint32>,
          Pointer<Uint32>)>('PeekNamedPipe');

  static final _closeHandle = _kernel32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  static _PipeTransport? open(String path) {
    final name = path.toNativeUtf16();
    try {
      final handle = _createFile(name, _genericRead | _genericWrite, 0,
          nullptr, _openExisting, 0, 0);
      return handle == _invalidHandle ? null : _PipeTransport._(handle);
    } finally {
      calloc.free(name);
    }
  }

  @override
  Future<void> write(Uint8List bytes) async {
    if (_closed) throw const FileSystemException('Discord pipe closed');
    final buf = calloc<Uint8>(bytes.length);
    final written = calloc<Uint32>();
    try {
      buf.asTypedList(bytes.length).setAll(0, bytes);
      if (_writeFile(_handle, buf, bytes.length, written, nullptr) == 0 ||
          written.value != bytes.length) {
        throw const FileSystemException('Discord pipe write failed');
      }
    } finally {
      calloc.free(buf);
      calloc.free(written);
    }
  }

  @override
  Future<Uint8List> read(int count, DateTime deadline) async {
    final out = BytesBuilder(copy: false);
    final avail = calloc<Uint32>();
    final got = calloc<Uint32>();
    try {
      while (out.length < count) {
        if (_closed) throw const FileSystemException('Discord pipe closed');
        if (_peekNamedPipe(_handle, nullptr, 0, nullptr, avail, nullptr) == 0) {
          throw const FileSystemException('Discord pipe broken');
        }
        final want = min(avail.value, count - out.length);
        if (want == 0) {
          if (DateTime.now().isAfter(deadline)) {
            throw TimeoutException('Discord IPC read');
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
          continue;
        }
        final buf = calloc<Uint8>(want);
        try {
          if (_readFile(_handle, buf, want, got, nullptr) == 0) {
            throw const FileSystemException('Discord pipe read failed');
          }
          out.add(Uint8List.fromList(buf.asTypedList(got.value)));
        } finally {
          calloc.free(buf);
        }
      }
      return out.takeBytes();
    } finally {
      calloc.free(avail);
      calloc.free(got);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _closeHandle(_handle);
  }
}
