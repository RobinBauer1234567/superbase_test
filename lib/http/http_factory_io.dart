import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:cupertino_http/cupertino_http.dart';
import 'package:cronet_http/cronet_http.dart';

CronetEngine? _cronetEngine;

Future<void> initPlatformClient() async {
  if (Platform.isAndroid) {
    try {
      _cronetEngine = await CronetEngine.build();
      print('✅ HTTP-TRANSPORT: Cronet aktiv (Android).');
    } catch (e) {
      _cronetEngine = null;
      print('❌ HTTP-TRANSPORT: Cronet konnte nicht geladen werden: $e');
    }
  }
}

http.Client getPlatformClient() {
  if (Platform.isAndroid && _cronetEngine != null) {
    return CronetClient.fromCronetEngine(_cronetEngine!);
  } else if (Platform.isIOS || Platform.isMacOS) {
    print('✅ HTTP-TRANSPORT: Cupertino/URLSession aktiv.');
    return CupertinoClient.defaultSessionConfiguration();
  }

  print('⚠️ HTTP-TRANSPORT: Standard Dart HTTP aktiv (${Platform.operatingSystem}).');
  return http.Client();
}
