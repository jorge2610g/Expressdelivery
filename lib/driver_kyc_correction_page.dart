import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Replaces only rejected identity images in every country.
/// Previously approved evidence remains untouched.
class DriverKycCorrectionPage extends StatefulWidget {
  const DriverKycCorrectionPage({super.key,this.focusSlot});
  final String? focusSlot;

  @override
  State<DriverKycCorrectionPage> createState()=>_DriverKycCorrectionPageState();
}

class _DriverKycCorrectionPageState extends State<DriverKycCorrectionPage> {
  final _picker=ImagePicker();
  late Future<Map<String,dynamic>> _future;
  String? _busySlot;
  @override
  void initState(){super.initState();_reload();}
  Map<String,dynamic> _map(dynamic v)=>v is Map
      ? Map<String,dynamic>.from(v):<String,dynamic>{};
  String _text(dynamic v)=>v?.toString().trim()??'';
  String _label(String slot)=>switch(slot) {
    'front'=>'Frente del carné','back'=>'Reverso del carné',
    'selfie'=>'Fotografía facial',_=>'Foto de perfil',
  };
  Future<Map<String,dynamic>> _load() async {
    final raw=await Supabase.instance.client.rpc(
      'driver_kyc_bolivia_review_state');
    return _map(raw);
  }
  void _reload(){if(mounted) setState(()=>_future=_load());}

  Future<void> _retake(
    String slot,
    String documentId,
    int expectedVersion,
  ) async {
    if(_busySlot!=null) return;
    final image=await _picker.pickImage(
      source:ImageSource.camera,imageQuality:86,maxWidth:2200);
    if(image==null||!mounted) return;
    final bytes=await image.readAsBytes();
    if(bytes.isEmpty||bytes.length>15*1024*1024) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('La fotografía no es válida o supera 15 MB.')));
      return;
    }
    final userId=Supabase.instance.client.auth.currentUser?.id;
    if(userId==null) return;
    final path='$userId/${slot=='profile'?'profile':'documents/$documentId'}'
      '/$slot-${DateTime.now().microsecondsSinceEpoch}.jpg';
    setState(()=>_busySlot=slot);
    try {
      await Supabase.instance.client.storage.from('driver-onboarding')
        .uploadBinary(path,bytes,fileOptions:const FileOptions(
          contentType:'image/jpeg',upsert:false));
      await Supabase.instance.client.rpc('driver_kyc_bolivia_replace_part',
        params:{
          'p_document_id':documentId,'p_slot':slot,'p_path':path,
          'p_expected_version':expectedVersion,
        });
      if(!mounted) return;
      _reload();
      await showDialog<void>(
        context:context,
        builder:(dialogContext)=>AlertDialog(
          icon:const Icon(Icons.check_circle,color:Color(0xFF067647)),
          title:const Text('Tu documento ha sido cargado exitosamente'),
          content:const Text('Un administrador revisará tu fotografía. '
            'La revisión puede tardar 24 horas o más.'),
          actions:[
            FilledButton(onPressed:()=>Navigator.pop(dialogContext),
              child:const Text('Entendido')),
          ],
        ),
      );
    } catch (_) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:Text('No se pudo guardar la fotografía. Intenta nuevamente.')));
        _reload();
      }
    } finally {
      if(mounted) setState(()=>_busySlot=null);
    }
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar:AppBar(title:const Text('Corregir documentos')),
      body:FutureBuilder<Map<String,dynamic>>(
        future:_future,builder:(context,snapshot){
          if(!snapshot.hasData){
            if(snapshot.hasError)return Center(child:Column(
              mainAxisSize:MainAxisSize.min,
              children:[
                const Text('No pudimos consultar los documentos.'),
                TextButton(onPressed:_reload,child:const Text('Reintentar')),
              ],
            ));
            return const Center(child:CircularProgressIndicator());
          }
          final state=snapshot.data!;
          final docId=_text(state['document_id']);
          if(docId.isEmpty) return const Center(
            child:Text('Aún no tienes fotografías en revisión manual.'));
          final parts=_map(state['review_parts']);
          final slots=<String>['front','back','selfie']; // One selfie = identity + profile.
          slots.sort((a,b)=>a==widget.focusSlot?-1:b==widget.focusSlot?1:0);
          final rejected=slots.where((slot)=>
            _text(_map(parts[slot])['status'])=='rejected').length;
          return RefreshIndicator(
            onRefresh:() async{_reload();await _future;},
            child:ListView(
              padding:const EdgeInsets.all(18),
              children:[
                Text(rejected>0?'Corrección necesaria'
                    :'Estado de tus documentos',
                  style:Theme.of(context).textTheme.titleLarge),
                const SizedBox(height:8),
                Text(rejected>0?'Carga solamente las fotografías rechazadas.'
                    :'Tus fotografías están guardadas. '
                      'Un administrador revisará la información.'),
                const SizedBox(height:12),
                for(final slot in slots)
                  Builder(builder:(context){
                    final part=_map(parts[slot]);
                    final status=_text(part['status']);
                    final path=_text(part['path']);
                    final version=int.tryParse(_text(part['version']))??0;
                    final canReplace=status=='rejected';
                    if(path.isEmpty && status.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Card(
                      child:Padding(
                        padding:const EdgeInsets.all(14),
                        child:Column(
                          crossAxisAlignment:CrossAxisAlignment.stretch,
                          children:[
                            Text(_label(slot),
                              style:const TextStyle(
                                fontWeight:FontWeight.w800,fontSize:16)),
                            const SizedBox(height:7),
                            Text(switch(status){
                              'approved'=>'✅ Aprobado',
                              'rejected'=>'❌ Rechazado',
                              _=>'🟡 En revisión',
                            }),
                            if(status=='rejected' &&
                                _text(part['reason']).isNotEmpty)
                              Text('Motivo: ${_text(part['reason'])}'),
                            const SizedBox(height:10),
                            if(canReplace)
                              FilledButton.icon(
                                onPressed:_busySlot!=null?null:
                                    ()=>_retake(slot,docId,version),
                                icon:const Icon(Icons.photo_camera_outlined),
                                label:Text(_busySlot==slot
                                    ?'Guardando…':'Cargar ${_label(slot).toLowerCase()}'),
                              )
                            else const Text('Tu documento ha sido enviado.'),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(height:12),
                const Text('Un administrador revisará tu información. '
                  'El proceso puede tardar 24 horas o más.',
                  textAlign:TextAlign.center),
              ],
            ),
          );
        },
      ),
    );
  }
}
