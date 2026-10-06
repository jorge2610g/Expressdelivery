import 'runtime_channel.dart';
import 'supabase_client.dart';

/// Resolves the runtime channel for the current authenticated account.
///
/// Preview APKs remain strict: they always request Preview and keep the
/// historical package-level isolation. Production candidates can resolve an
/// already-authorized QA account to Preview while normal accounts stay in
/// Production. The server is authoritative; the client never self-elects QA.
Future<Map<String, dynamic>> resolveExpressRuntimeAccess() async {
  ExpressRuntimeChannel.resetToCompiledMode();

  Map<String, dynamic>? resolution;
  if (!ExpressRuntimeChannel.compiledPreviewMode) {
    final rawResolution = await supabase.rpc(
      'resolve_current_runtime_environment',
    );
    resolution = Map<String, dynamic>.from(rawResolution as Map);
    if (resolution['allowed'] != true) {
      return <String, dynamic>{
        ...resolution,
        'bound_environment': resolution['environment'],
      };
    }

    final environment = resolution['environment']?.toString();
    if (environment == null) {
      throw StateError('Runtime environment resolution returned no environment');
    }
    ExpressRuntimeChannel.applyResolvedEnvironment(environment);
  }

  final rawAccess = await supabase.rpc(
    'ensure_current_runtime_access',
    params: {'p_channel': ExpressRuntimeChannel.name},
  );
  final access = Map<String, dynamic>.from(rawAccess as Map);

  return <String, dynamic>{
    ...access,
    'resolved_environment': ExpressRuntimeChannel.name,
    if (resolution?['source'] != null) 'runtime_source': resolution!['source'],
  };
}
