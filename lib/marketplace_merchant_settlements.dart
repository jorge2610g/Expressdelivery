import 'package:flutter/material.dart';
import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'marketplace_chat_attachments.dart';
import 'money_format.dart';

class MarketplaceMerchantSettlementsPage extends StatefulWidget {
  const MarketplaceMerchantSettlementsPage({
    super.key,required this.merchantId,required this.merchantName});
  final String merchantId,merchantName;
  @override
  State<MarketplaceMerchantSettlementsPage> createState() =>
    _MarketplaceMerchantSettlementsPageState();
}
class _MarketplaceMerchantSettlementsPageState
    extends State<MarketplaceMerchantSettlementsPage> {
  late Future<List<Map<String,dynamic>>> future;
  bool busy=false;
  @override
  void initState(){super.initState();_refresh();}
  void _refresh(){
    future=()async{
      final data=await supabase.rpc('marketplace_merchant_weekly_cuts',
        params:{'p_merchant_id':widget.merchantId,
          'p_channel':ExpressRuntimeChannel.name});
      return data is List?data.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList()
        :<Map<String,dynamic>>[];
    }();
  }
  String _money(Object? amount,Object? currency)=>expressMoney(amount,currency);
  String _status(String raw)=>switch(raw){
    'paid'=>'Pagado','under_review'=>'En revisión',
    'rejected'=>'Rechazado',_=>'Pendiente'
  };
  Future<void> _report(Map<String,dynamic> cut)async {
    if(busy)return;
    final reference=TextEditingController();
    var method='transfer';
    String? receiptPath;
    final confirmed=await showDialog<bool>(context:context,
      builder:(context)=>StatefulBuilder(builder:(context,setLocal)=>AlertDialog(
        title:const Text('Informar pago a Express'),
        content:ConstrainedBox(constraints:const BoxConstraints(maxWidth:460),
          child:SingleChildScrollView(child:Column(
            mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              Text('Servicio Express · cobrado por adelantado',
                style:Theme.of(context).textTheme.titleMedium),
              const SizedBox(height:8),
              Text(_money(cut['amount'],cut['currency_code']),
                style:Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height:12),
              DropdownButtonFormField<String>(
                initialValue:method,
                decoration:const InputDecoration(labelText:'Método del pago'),
                items:const [
                  DropdownMenuItem(value:'transfer',child:Text('Transferencia')),
                  DropdownMenuItem(value:'deposit',child:Text('Depósito bancario')),
                ],
                onChanged:(v)=>setLocal(()=>method=v??'transfer')),
              const SizedBox(height:12),
              TextField(controller:reference,
                decoration:const InputDecoration(
                  labelText:'Número de operación o referencia')),
              const SizedBox(height:10),
              OutlinedButton.icon(
                onPressed:()async{
                  try{
                    final path=await marketplacePickAndUploadChatImage(
                      cut['id'].toString(),bucket:'marketplace-weekly-receipts');
                    if(context.mounted && path!=null)setLocal(()=>receiptPath=path);
                  }catch(e){
                    if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content:Text('Imagen no enviada: $e')));
                  }
                },
                icon:Icon(receiptPath==null?Icons.add_photo_alternate_outlined:
                  Icons.check_circle_outline),
                label:Text(receiptPath==null?'Adjuntar comprobante':
                  'Comprobante adjuntado')),
              const SizedBox(height:8),
              const Text('Informar este pago no elimina la deuda. '
                'Express revisará el comprobante antes de marcarlo como pagado.',
                style:TextStyle(fontSize:12)),
            ]))),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(context,false),
            child:const Text('Cancelar')),
          FilledButton(onPressed:()=>Navigator.pop(context,true),
            child:const Text('Enviar aviso')),
        ],
      )));
    final ref=reference.text.trim();reference.dispose();
    if(confirmed!=true||!mounted)return;
    if(ref.length<4){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('Indica una referencia de al menos 4 caracteres.')));
      return;
    }
    setState(()=>busy=true);
    try{
      await supabase.rpc('marketplace_report_weekly_cut',params:{
        'p_cut_id':cut['id'],'p_reference':ref,
        'p_method':method,'p_receipt_path':receiptPath
      });
      if(mounted){
        setState(_refresh);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:Text('Pago informado; esperando confirmación de Express.')));
      }
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('No se pudo informar: $e')));
    }finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Liquidaciones Express'),
      actions:[IconButton(onPressed:()=>setState(_refresh),
        icon:const Icon(Icons.refresh))]),
    body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:940),
      child:FutureBuilder<List<Map<String,dynamic>>>(future:future,
        builder:(context,snapshot){
          if(snapshot.connectionState!=ConnectionState.done){
            return const Center(child:CircularProgressIndicator());}
          if(snapshot.hasError)return Center(child:Text(
            'No se pudieron cargar los cortes: ${snapshot.error}'));
          final cuts=snapshot.data??<Map<String,dynamic>>[];
          if(cuts.isEmpty)return const Center(child:Padding(
            padding:EdgeInsets.all(24),child:Text(
              'Todavía no hay cortes semanales cerrados. '
              'Se generan después de finalizar las entregas y la semana correspondiente.',
              textAlign:TextAlign.center)));
          return ListView(padding:const EdgeInsets.all(17),children:[
            Text(widget.merchantName,style:Theme.of(context).textTheme.titleLarge),
            const SizedBox(height:5),
            const Text('Solo ves el importe de Servicio Express a liquidar. '
              'La entrega de efectivo al repartidor se controla por pedido.'),
            const SizedBox(height:14),
            for(final cut in cuts)Padding(padding:const EdgeInsets.only(bottom:12),
              child:Card(child:Padding(padding:const EdgeInsets.all(16),
                child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Row(children:[
                    Expanded(child:Text('${cut['week_start']} → ${cut['week_end']}',
                      style:const TextStyle(fontWeight:FontWeight.w700))),
                    Chip(label:Text(_status(cut['status']?.toString()??''))),
                  ]),
                  const SizedBox(height:8),
                  const Text('Servicio Express · cobrado por adelantado'),
                  Text(_money(cut['amount'],cut['currency_code']),
                    style:Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height:6),
                  Text('${cut['orders']} pedidos entregados'),
                  if(cut['status']=='under_review')
                    const Text('Comprobante enviado. Express está verificando el pago.'),
                  if(cut['status']=='paid')
                    const Text('Pago verificado por administración.'),
                  if(cut['status']=='rejected')
                    const Text('Aviso rechazado. Revisa y vuelve a informar el pago.'),
                  if(cut['status']=='pending'||cut['status']=='rejected')...[
                    const SizedBox(height:10),
                    FilledButton.icon(onPressed:busy?null:()=>_report(cut),
                      icon:const Icon(Icons.send_outlined),
                      label:const Text('Informar pago a Express')),
                  ],
                ]))))
          ]);
        }))),
  );
}
