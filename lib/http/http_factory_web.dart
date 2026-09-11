import 'package:http/http.dart' as http;

Future<void> initPlatformClient() async {}
http.Client getPlatformClient() => http.Client(); // Im Web nutzen wir den Standard-Client