// lib/auth_service.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data'; // WICHTIG für Uint8List
class AuthService with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  User? _user;

  AuthService() {
    // Dieser Teil bleibt unverändert
    _supabase.auth.onAuthStateChange.listen((data) {
      final Session? session = data.session;
      _user = session?.user;
      notifyListeners();
    });
  }

  User? get currentUser => _user;
  bool get isLoggedIn => _user != null;

  // --- ANPASSUNG HIER ---
  Future<void> signUp(BuildContext context, {required String email, required String password, required String username}) async {
    try {
      final AuthResponse res = await _supabase.auth.signUp(email: email, password: password);

      // Wenn die Registrierung erfolgreich war UND ein User-Objekt zurückgegeben wurde
      if (res.user != null) {
        // Erstelle ein Profil für den neuen Benutzer
        await _supabase.from('profiles').insert({
          'user_id': res.user!.id,
          'username': username,
        });
      } else if (res.session == null) {
        // Fall: E-Mail Bestätigung ist aktiv, aber der User hat sich noch nicht verifiziert
        _showErrorDialog(context, 'Registrierung erfolgreich! Bitte bestätige deine E-Mail-Adresse, um dich anzumelden.');
      }

    } on AuthException catch (e) {
      _showErrorDialog(context, 'Fehler bei der Authentifizierung: ${e.message}');
    } on PostgrestException catch (e) {
      // Spezifischer Fehler für Datenbank-Operationen (z.B. Profilerstellung)
      _showErrorDialog(context, 'Fehler bei der Profilerstellung: ${e.message}');
    } catch (e) {
      _showErrorDialog(context, 'Ein unerwarteter Fehler ist aufgetreten: $e');
    }
  }

  // signIn und signOut bleiben unverändert
  Future<void> signIn(BuildContext context, {required String email, required String password}) async {
    try {
      await _supabase.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      _showErrorDialog(context, e.message);
    } catch (e) {
      _showErrorDialog(context, 'Ein unerwarteter Fehler ist aufgetreten.');
    }
  }
  Future<String?> updateProfilePicture(Uint8List imageBytes) async {
    final userId = currentUser?.id;
    if (userId == null) {
      throw Exception('Nicht eingeloggt. Bitte melde dich erneut an.');
    }

    // Da der Bucket schon 'avatars' heißt, nennen wir die Datei einfach <user_id>.jpg
    final path = '$userId.jpg';

    try {
      // 1. Bild in den neuen Supabase Storage Bucket 'avatars' hochladen
      await _supabase.storage.from('avatars').uploadBinary(
        path,
        imageBytes,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: true, // WICHTIG: Überschreibt das alte Bild, falls vorhanden!
        ),
      );

      // 2. Die öffentliche URL des Bildes abrufen
      final publicUrl = _supabase.storage.from('avatars').getPublicUrl(path);

      // 3. Die URL in der 'profiles'-Tabelle aktualisieren
      await _supabase.from('profiles').update({
        'avatar_url': publicUrl
      }).eq('user_id', userId);

      // 4. Den neuen Link zurückgeben
      return publicUrl;

    } catch (e) {
      print('Fehler beim Profilbild-Upload: $e');
      throw Exception('Das Profilbild konnte nicht gespeichert werden.');
    }
  }
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hinweis'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}