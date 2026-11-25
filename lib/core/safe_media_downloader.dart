// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:io';
import 'dart:typed_data';

/// Rejects private/loopback targets before every redirect and verifies the
/// connected peer afterwards. This prevents ordinary SSRF including DNS names
/// resolving to a private address; callers never receive partial files.
class SafeMediaDownloader {
  static const maxBytes = 8 * 1024 * 1024;
  Future<Uint8List> download(String value) => _read(value);

  Future<Uint8List> readPrefix(String value) => _read(value, prefixLength: 64);

  Future<Uint8List> _read(String value, {int? prefixLength}) async {
    var uri = Uri.parse(value);
    if (uri.userInfo.isNotEmpty)
      throw const HttpException('URL userinfo is not allowed');
    final pins = <String, InternetAddress>{};
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    client.autoUncompress = false;
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (target, proxyHost, proxyPort) {
      final address = pins[target.host];
      if (address == null) throw const HttpException('Unpinned host');
      if (address.host != target.host)
        throw const HttpException('Pinned hostname mismatch');
      final port = target.hasPort
          ? target.port
          : (target.scheme == 'https' ? 443 : 80);
      if (target.scheme == 'https')
        return SecureSocket.startConnect(address, port);
      return Socket.startConnect(address, port);
    };
    try {
      for (var redirects = 0; redirects < 5; redirects++) {
        if (uri.scheme != 'https' && uri.scheme != 'http' ||
            uri.userInfo.isNotEmpty)
          throw const HttpException('Unsupported media URL');
        pins[uri.host] = await _resolvePublic(uri.host)
            .timeout(const Duration(seconds: 12));
        final request = await client.getUrl(uri)
          ..followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'image/*');
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        if (prefixLength != null) {
          request.headers.set(
            HttpHeaders.rangeHeader,
            'bytes=0-${prefixLength - 1}',
          );
        }
        if (_isDcconOriginal(uri)) {
          request.headers.set(
            HttpHeaders.refererHeader,
            'https://dccon.dcinside.com/',
          );
          request.headers.set(
            HttpHeaders.userAgentHeader,
            'Mozilla/5.0 (MemeSearcher/1.0)',
          );
        }
        final response = await request.close().timeout(
          const Duration(seconds: 20),
        );
        final peer = response.connectionInfo?.remoteAddress;
        if (peer == null || !_public(peer))
          throw const HttpException('Non-public peer rejected');
        if (response.isRedirect) {
          final target = response.headers.value(HttpHeaders.locationHeader);
          if (target == null)
            throw const HttpException('Missing redirect target');
          uri = uri.resolve(target);
          await response.drain<void>().timeout(const Duration(seconds: 12));
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300)
          throw HttpException('Media HTTP ${response.statusCode}');
        final length = response.contentLength;
        if (prefixLength == null && length > maxBytes)
          throw const HttpException('Media too large');
        final data = BytesBuilder(copy: false);
        await for (final chunk in response.timeout(
          const Duration(seconds: 20),
        )) {
          if (prefixLength != null &&
              chunk.length >= prefixLength - data.length) {
            data.add(chunk.sublist(0, prefixLength - data.length));
            break;
          }
          if (data.length + chunk.length > maxBytes)
            throw const HttpException('Media too large');
          data.add(chunk);
        }
        return data.takeBytes();
      }
      throw const HttpException('Too many redirects');
    } finally {
      client.close(force: true);
    }
  }

  Future<InternetAddress> _resolvePublic(String host) async {
    final resolved = await InternetAddress.lookup(host);
    if (resolved.isEmpty || resolved.any((ip) => !_public(ip)))
      throw const HttpException('Host resolves to non-public address');
    return resolved.first;
  }

  bool _public(InternetAddress ip) {
    if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return false;
    final raw = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      final a = raw[0], b = raw[1];
      return !(a == 0 ||
          a == 10 ||
          a == 127 ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 100 && b >= 64 && b <= 127));
    }
    final uniqueLocal = (raw[0] & 0xfe) == 0xfc;
    final linkLocal = raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80;
    final unspecified = raw.every((byte) => byte == 0);
    final mappedV4 =
        raw.sublist(0, 10).every((byte) => byte == 0) &&
        raw[10] == 0xff &&
        raw[11] == 0xff;
    if (mappedV4)
      return _public(InternetAddress.fromRawAddress(raw.sublist(12)));
    return !uniqueLocal && !linkLocal && !unspecified;
  }

  bool _isDcconOriginal(Uri uri) =>
      RegExp(
        r'^dcimg\d+\.dcinside\.com$',
        caseSensitive: false,
      ).hasMatch(uri.host) &&
      uri.path == '/dccon.php';
}
