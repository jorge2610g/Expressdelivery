import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';

class AuthService {
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) => supabase.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) => supabase.auth.signUp(
    email: email,
    password: password,
    emailRedirectTo: 'https://jorge2610g.github.io/Expressdelivery/',
    data: {'full_name': fullName, 'phone': phone},
  );

  Future<void> signOut() => supabase.auth.signOut();
}
