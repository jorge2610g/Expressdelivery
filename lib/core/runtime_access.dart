import 'runtime_channel.dart';
import 'supabase_client.dart';

/// Resolves the runtime channel for the current authenticated account.
///
/// Preview and Production have fully separate Supabase projects. A build
/// can only access accounts in its own backend; former Production-binary QA
/// account switching is rejected instead of silently crossing data planes.
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
    if (environment.trim().toLowerCase() != ExpressRuntimeChannel.name) {
      return <String, dynamic>{
        ...resolution,
        'allowed': false,
        'bound_environment': environment,
        'reason': 'cross_project_account_not_allowed',
      };
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
