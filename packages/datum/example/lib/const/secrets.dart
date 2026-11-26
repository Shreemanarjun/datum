// ignore_for_file: constant_identifier_names

/// Defaults target the hosted demo project; point at a local stack with
/// `--dart-define=SUPABASE_URL=http://127.0.0.1:54321
///  --dart-define=SUPABASE_ANON_KEY=$PUBLISHABLE_KEY` (from `supabase status`).
class Secrets {
  Secrets._();
  static const String SUPABASE_URL = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://zmozkivkhopoeutpnnum.supabase.co');
  static const String SUPABASE_ANON_KEY = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_Bvov34wsvt0zEON48tQzag_kQAPcPAp');
}
