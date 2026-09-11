import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:cupertino_http/cupertino_http.dart';
import 'package:cronet_http/cronet_http.dart';

CronetEngine? _cronetEngine;

Future<void> initPlatformClient() async {
  if (Platform.isAndroid) {
    try {
      _cronetEngine = await CronetEngine.build();
    } catch (e) {
      print('Cronet konnte nicht geladen werden: $e');
    }
  }
}

http.Client getPlatformClient() {
  if (Platform.isAndroid && _cronetEngine != null) {
    return CronetClient.fromCronetEngine(_cronetEngine!);
  } else if (Platform.isIOS || Platform.isMacOS) {
    return CupertinoClient.defaultSessionConfiguration();
  }
  return http.Client();
}