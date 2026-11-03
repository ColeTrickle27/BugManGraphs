// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Returns a disposer. Only the verified embedding parent can request pixels.
void Function() listenForPresentationExport({
  required String graphKey,
  required Future<Uint8List> Function() capture,
}) {
  final origin =
      _verifiedReturnOrigin(Uri.base.queryParameters['returnOrigin']);
  final parent = html.window.parent;
  if (origin == null || parent == html.window || graphKey.isEmpty) return () {};
  var disposed = false;
  var busy = false;
  String? completedId;
  Map<String, String>? completedResponse;
  final subscription = html.window.onMessage.listen((event) async {
    final data = event.data;
    if (disposed ||
        event.origin != origin ||
        !(event as JSObject)
            .getProperty<JSAny?>('source'.toJS)
            .strictEquals(globalContext.getProperty<JSAny?>('parent'.toJS))
            .toDart ||
        data is! Map ||
        data['type'] != 'bugman-graph:export-presentation' ||
        data['graphKey'] != graphKey) {
      return;
    }
    final requestId = data['requestId'];
    if (requestId is! String || requestId.isEmpty || requestId.length > 200) {
      return;
    }
    if (completedId == requestId && completedResponse != null) {
      parent?.postMessage(completedResponse, origin);
      return;
    }
    if (busy) return;
    busy = true;
    final response = <String, String>{
      'requestId': requestId,
      'graphKey': graphKey
    };
    try {
      final encoded = base64Encode(await capture());
      if (encoded.length > 14 * 1024 * 1024) throw StateError('Too large');
      response.addAll(
          {'type': 'bugman-graph:presentation-png', 'pngBase64': encoded});
    } catch (_) {
      response.addAll({
        'type': 'bugman-graph:presentation-error',
        'error': 'The customer graph image could not be prepared.'
      });
    }
    busy = false;
    if (disposed) return;
    completedId = requestId;
    completedResponse = response;
    parent?.postMessage(response, origin);
  });
  return () {
    disposed = true;
    subscription.cancel();
  };
}

const Set<String> _allowedReturnOrigins = <String>{
  'https://ops.holloman-ext.com',
  'https://sales.holloman-ext.com',
  'http://localhost:8443',
  'http://127.0.0.1:8443',
};

/// Sends only the real R2 graph key back to an allowlisted SalesBrain host.
/// Supports the standalone editor in either an iframe or a controlled new tab.
void notifySalesBrainGraphSaved(String graphKey) {
  final String safeKey = graphKey.trim();
  if (safeKey.isEmpty) return;
  final String? returnOrigin =
      _verifiedReturnOrigin(Uri.base.queryParameters['returnOrigin']);
  if (returnOrigin == null) return;
  final html.WindowBase? target = html.window.parent != html.window
      ? html.window.parent
      : html.window.opener;
  if (target == null) return;
  final String billToNumber = (Uri.base.queryParameters['billTo'] ?? '').trim();
  final String locationNumber =
      (Uri.base.queryParameters['location'] ?? '').trim();
  if (billToNumber.isEmpty || locationNumber.isEmpty) return;
  target.postMessage(
    <String, String>{
      'type': 'bugman-graph:saved',
      'graphKey': safeKey,
      'billToNumber': billToNumber,
      'locationNumber': locationNumber,
    },
    returnOrigin,
  );
}

String? _verifiedReturnOrigin(String? value) {
  if (value == null || value.isEmpty) return null;
  final Uri? uri = Uri.tryParse(value);
  if (uri == null || uri.origin != value) return null;
  if (_allowedReturnOrigins.contains(uri.origin)) return uri.origin;
  // Cloudflare Pages previews stay scoped to Holloman's trusted Pages host.
  if (uri.scheme == 'https' &&
      uri.host.endsWith('.holloman-ops-brain.pages.dev')) {
    return uri.origin;
  }
  return null;
}
