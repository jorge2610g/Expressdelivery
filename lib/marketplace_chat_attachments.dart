import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'core/supabase_client.dart';

const marketplaceChatBucket = 'marketplace-order-chat';

/// Returns only a private storage path, never a permanently public image URL.
Future<String?> marketplacePickAndUploadChatImage(String orderId) async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 72,
    maxWidth: 1600,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty || bytes.lengthInBytes > 5242880) {
    throw StateError('La imagen debe ser menor a 5 MB.');
  }
  final name = file.name.toLowerCase();
  final extension = name.endsWith('.png') ? 'png' :
      name.endsWith('.webp') ? 'webp' : 'jpg';
  final mime = extension == 'png' ? 'image/png' :
      extension == 'webp' ? 'image/webp' : 'image/jpeg';
  final path = '$orderId/${DateTime.now().microsecondsSinceEpoch}.$extension';
  await supabase.storage.from(marketplaceChatBucket).uploadBinary(
    path, bytes,
    fileOptions: FileOptions(contentType: mime,upsert: false),
  );
  return path;
}

class MarketplaceChatAttachment extends StatelessWidget {
  const MarketplaceChatAttachment({super.key,required this.objectPath});
  final String objectPath;

  @override
  Widget build(BuildContext context) {
    if (!RegExp(r'^[0-9a-f-]{36}/[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)$')
        .hasMatch(objectPath)) {
      return const Text('Imagen antigua. Contacta al restaurante para verla.');
    }
    return FutureBuilder<String>(
      future: supabase.storage.from(marketplaceChatBucket)
          .createSignedUrl(objectPath, 600),
      builder: (context,snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height:40,child:Center(
            child:CircularProgressIndicator(strokeWidth:2)));
        }
        if (!snapshot.hasData) return const Text('No se pudo abrir la imagen.');
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260,maxHeight: 240),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(snapshot.data!,
              fit: BoxFit.contain,
              errorBuilder: (_,__,___) =>
                const Text('Imagen no disponible.')),
          ),
        );
      },
    );
  }
}
