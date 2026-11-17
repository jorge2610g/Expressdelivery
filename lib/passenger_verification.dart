import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Pasos que el pasajero puede tener pendientes. El orden es el de la pantalla.
enum PassengerVerificationStep { profilePhoto, identityFront, identityBack, faceSelfie }

/// Estado leído de `passenger_verification_state()`. Sin datos personales.
class PassengerVerificationState {
  const PassengerVerificationState({
    required this.profilePhotoRequired,
    required this.identityDocumentRequired,
    required this.faceSelfieRequired,
    required this.hasProfilePhoto,
    required this.submittedDocuments,
  });

  final bool profilePhotoRequired;
  final bool identityDocumentRequired;
  final bool faceSelfieRequired;
  final bool hasProfilePhoto;
  final List<String> submittedDocuments;

  factory PassengerVerificationState.fromJson(Map<dynamic, dynamic> json) {
    final submitted = json['submitted_documents'];
    return PassengerVerificationState(
      profilePhotoRequired: json['profile_photo_required'] == true,
      identityDocumentRequired: json['identity_document_required'] == true,
      faceSelfieRequired: json['face_selfie_required'] == true,
      hasProfilePhoto: json['has_profile_photo'] == true,
      submittedDocuments: submitted is List
          ? submitted.map((item) => item.toString()).toList()
          : const <String>[],
    );
  }

  /// Pasos que faltan según lo que el administrador activó.
  List<PassengerVerificationStep> get pendingSteps {
    final pending = <PassengerVerificationStep>[];
    if (profilePhotoRequired && !hasProfilePhoto) {
      pending.add(PassengerVerificationStep.profilePhoto);
    }
    if (identityDocumentRequired) {
      if (!submittedDocuments.contains('identity_front')) {
        pending.add(PassengerVerificationStep.identityFront);
      }
      if (!submittedDocuments.contains('identity_back')) {
        pending.add(PassengerVerificationStep.identityBack);
      }
    }
    if (faceSelfieRequired && !submittedDocuments.contains('face_selfie')) {
      pending.add(PassengerVerificationStep.faceSelfie);
    }
    return pending;
  }

  bool get isComplete => pendingSteps.isEmpty;
}

/// Tipo de documento que guarda la base para cada paso de carnet o selfie.
String? passengerDocumentTypeFor(PassengerVerificationStep step) {
  return switch (step) {
    PassengerVerificationStep.identityFront => 'identity_front',
    PassengerVerificationStep.identityBack => 'identity_back',
    PassengerVerificationStep.faceSelfie => 'face_selfie',
    PassengerVerificationStep.profilePhoto => null,
  };
}

/// Extensión permitida por el bucket (jpg, png o webp), o null si no sirve.
String? passengerImageExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = fileName.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'jpg',
    'png' => 'png',
    'webp' => 'webp',
    _ => null,
  };
}

String passengerContentType(String extension) {
  return switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

/// Ruta de la foto de perfil: siempre dentro de la carpeta del propio pasajero.
String passengerProfilePhotoPath({
  required String userId,
  required String extension,
}) {
  return '$userId/profile.$extension';
}

/// Ruta de carnet o selfie: carpeta del pasajero, tipo y marca de tiempo.
String passengerVerificationObjectPath({
  required String userId,
  required String documentType,
  required String extension,
  required int timestampMs,
}) {
  return '$userId/$documentType-$timestampMs.$extension';
}

/// Acceso a las RPC y al almacenamiento de verificación del pasajero.
class PassengerVerificationService {
  PassengerVerificationService(this.client);

  final SupabaseClient client;

  Future<PassengerVerificationState> fetchState() async {
    final raw = await client.rpc('passenger_verification_state');
    if (raw is! Map) {
      throw StateError('Respuesta inesperada de passenger_verification_state');
    }
    return PassengerVerificationState.fromJson(raw);
  }

  Future<void> uploadProfilePhoto({
    required String userId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final path = passengerProfilePhotoPath(userId: userId, extension: extension);
    await client.storage.from('passenger-profile').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: passengerContentType(extension),
            cacheControl: '3600',
          ),
        );
    await client.rpc(
      'passenger_set_profile_photo',
      params: {'p_object_path': path},
    );
  }

  Future<void> submitDocument({
    required String userId,
    required PassengerVerificationStep step,
    required Uint8List bytes,
    required String extension,
    required int timestampMs,
  }) async {
    final type = passengerDocumentTypeFor(step);
    if (type == null) {
      throw ArgumentError('El paso $step no es un documento');
    }
    final path = passengerVerificationObjectPath(
      userId: userId,
      documentType: type,
      extension: extension,
      timestampMs: timestampMs,
    );
    await client.storage.from('passenger-verification').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: passengerContentType(extension),
          ),
        );
    await client.rpc(
      'passenger_submit_verification_document',
      params: {'p_document_type': type, 'p_object_path': path},
    );
  }
}
