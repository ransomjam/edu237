// =============================================================================
// Fapshi sandbox connectivity check
// =============================================================================
//
// A small, dependency-free script that talks to the Fapshi SANDBOX with your
// own test credentials, so you can confirm the integration end to end before
// anything is deployed — and long before any real money is involved.
//
// It never touches live: the base URL is hard-wired to the sandbox host.
//
// Run:
//   dart run tool/fapshi_sandbox_check.dart \
//     --apiuser=YOUR_SANDBOX_APIUSER \
//     --apikey=YOUR_SANDBOX_APIKEY \
//     [--phone=670000000]   # also exercises Direct Pay
//
// Credentials are passed on the command line (or FAPSHI_COLLECTION_API_USER /
// FAPSHI_COLLECTION_API_KEY in the environment) and are never written to a file
// or logged back out.
//
// What it does:
//   1. POST /initiate-pay      → a hosted checkout link
//   2. GET  /payment-status/id → the transaction's real state
//   3. POST /direct-pay        → optional, only with --phone
//
// What it deliberately does NOT do: mark anything in Camiva as paid. Only the
// webhook and the server-side verification may do that.
// =============================================================================

import 'dart:convert';
import 'dart:io';

const String sandboxBaseUrl = 'https://sandbox.fapshi.com';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);

  final apiUser = options['apiuser'] ??
      Platform.environment['FAPSHI_COLLECTION_API_USER'] ??
      '';
  final apiKey = options['apikey'] ??
      Platform.environment['FAPSHI_COLLECTION_API_KEY'] ??
      '';

  if (apiUser.isEmpty || apiKey.isEmpty) {
    stderr.writeln(
      'Missing sandbox credentials.\n'
      'Pass --apiuser=... --apikey=..., or set '
      'FAPSHI_COLLECTION_API_USER / FAPSHI_COLLECTION_API_KEY.',
    );
    exitCode = 2;
    return;
  }

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  try {
    stdout.writeln('Fapshi sandbox: $sandboxBaseUrl');

    // ---- 1. Initiate Pay ---------------------------------------------------
    final initiate = await _post(client, apiUser, apiKey, '/initiate-pay', {
      'amount': 100, // the documented minimum
      'externalId': 'camiva-sandbox-check',
      'message': 'Camiva sandbox check',
    });
    stdout.writeln('\n[1] POST /initiate-pay → ${initiate.status}');
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(initiate.body));

    final transId = (initiate.body as Map?)?['transId'] as String?;
    if (transId == null) {
      stderr.writeln('No transId returned — check the credentials and service.');
      exitCode = 1;
      return;
    }

    // ---- 2. Payment status -------------------------------------------------
    final status = await _get(
      client,
      apiUser,
      apiKey,
      '/payment-status/${Uri.encodeComponent(transId)}',
    );
    stdout.writeln('\n[2] GET /payment-status/$transId → ${status.status}');
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(status.body));

    // ---- 3. Direct Pay (optional) -----------------------------------------
    final phone = options['phone'];
    if (phone != null && phone.isNotEmpty) {
      final direct = await _post(client, apiUser, apiKey, '/direct-pay', {
        'amount': 100,
        'phone': phone,
        'externalId': 'edu237-sandbox-direct',
        'message': 'Camiva sandbox direct pay',
      });
      stdout.writeln('\n[3] POST /direct-pay → ${direct.status}');
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(direct.body));
      if (direct.status == 403) {
        stdout.writeln(
          '\nDirect Pay is not enabled for this service. That is expected '
          'until Fapshi activates it — Camiva falls back to the hosted '
          'checkout link in the meantime.',
        );
      }
    } else {
      stdout.writeln('\n[3] POST /direct-pay — skipped (pass --phone=6XXXXXXXX)');
    }

    stdout.writeln(
      '\nDone. Nothing in Camiva was marked as paid: only the webhook and the '
      'server-side verification can do that.',
    );
  } on SocketException catch (e) {
    // Never report a connectivity failure as a credential failure: the two
    // have completely different fixes. Exit code 3 means "could not reach
    // Fapshi at all", so callers can tell them apart.
    stderr.writeln(
      '\nCould not reach $sandboxBaseUrl.\n'
      'This is a network problem, NOT a credential problem — nothing was sent, '
      'so nothing was rejected.\n'
      '  ${e.osError?.message ?? e.message}\n\n'
      'Check a VPN/proxy, try another network, and confirm the host resolves:\n'
      '  nslookup sandbox.fapshi.com',
    );
    exitCode = 3;
  } on HandshakeException catch (e) {
    stderr.writeln(
      '\nTLS handshake with $sandboxBaseUrl failed — often a proxy or security '
      'product intercepting HTTPS. This is not a credential problem.\n  ${e.message}',
    );
    exitCode = 3;
  } finally {
    client.close(force: true);
  }
}

class _Response {
  _Response(this.status, this.body);
  final int status;
  final Object? body;
}

Future<_Response> _post(
  HttpClient client,
  String apiUser,
  String apiKey,
  String path,
  Map<String, Object?> payload,
) async {
  final request = await client.postUrl(Uri.parse('$sandboxBaseUrl$path'));
  request.headers.set('Content-Type', 'application/json');
  request.headers.set('apiuser', apiUser);
  request.headers.set('apikey', apiKey);
  request.write(jsonEncode(payload));
  return _read(await request.close());
}

Future<_Response> _get(
  HttpClient client,
  String apiUser,
  String apiKey,
  String path,
) async {
  final request = await client.getUrl(Uri.parse('$sandboxBaseUrl$path'));
  // The documentation is explicit that GET requests carry no body.
  request.headers.set('apiuser', apiUser);
  request.headers.set('apikey', apiKey);
  return _read(await request.close());
}

Future<_Response> _read(HttpClientResponse response) async {
  final text = await response.transform(utf8.decoder).join();
  Object? body;
  try {
    body = text.isEmpty ? null : jsonDecode(text);
  } catch (_) {
    body = text;
  }
  return _Response(response.statusCode, body);
}

Map<String, String> _parseArgs(List<String> args) {
  final options = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--')) continue;
    final separator = arg.indexOf('=');
    if (separator == -1) continue;
    options[arg.substring(2, separator)] = arg.substring(separator + 1);
  }
  return options;
}
