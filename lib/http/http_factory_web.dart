import 'package:http/http.dart' as http;

/// Browser-spezifischer HTTP-Client.
///
/// SofaScore blockiert direkte Browser-Requests an api.sofascore.com teilweise
/// mit 403. Im Web verwenden wir deshalb den v1-Mirror api.sofascore.app.
/// Andere Hosts (z. B. Supabase) werden unverändert weitergereicht.
class _SofaScoreWebClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.host == 'api.sofascore.com') {
      final mirrorUri = request.url.replace(host: 'api.sofascore.app');
      final mirrorRequest = http.Request(request.method, mirrorUri);

      // Im Browser nur Header übernehmen, die keine unnötige CORS-Preflight-
      // Anfrage bzw. verbotene Browser-Header erzwingen.
      for (final entry in request.headers.entries) {
        final name = entry.key.toLowerCase();
        if (name == 'accept' ||
            name == 'accept-language' ||
            name == 'content-type') {
          mirrorRequest.headers[entry.key] = entry.value;
        }
      }

      if (request is http.Request && request.bodyBytes.isNotEmpty) {
        mirrorRequest.bodyBytes = request.bodyBytes;
      }

      return _inner.send(mirrorRequest);
    }

    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

Future<void> initPlatformClient() async {
  print('✅ HTTP-TRANSPORT: Browser + SofaScore-Mirror aktiv.');
}

http.Client getPlatformClient() => _SofaScoreWebClient();
