import 'package:flutter/material.dart';
import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'money_format.dart';

class MarketplaceMerchantCataloguePage extends StatefulWidget {
 const MarketplaceMerchantCataloguePage({super.key,required this.merchantId,
 required this.merchantName});
 final String merchantId,merchantName;
 @override State<MarketplaceMerchantCataloguePage> createState()=>
 _MarketplaceMerchantCataloguePageState();
}
class _MarketplaceMerchantCataloguePageState
 extends State<MarketplaceMerchantCataloguePage> {
 late Future<Map<String,dynamic>> future;
 bool saving=false;
 @override void initState(){super.initState();_refresh();}
 void _refresh(){
   future=()async{
     final raw=await supabase.rpc('marketplace_merchant_manage_state',params:{
       'p_merchant_id':widget.merchantId,
       'p_channel':ExpressRuntimeChannel.name,
     });
     return raw is Map?Map<String,dynamic>.from(raw):<String,dynamic>{};
   }();
 }
 Future<void> _setOpen(bool open)async{
   if(saving)return;setState(()=>saving=true);
   try{
     await supabase.rpc('marketplace_merchant_set_open',params:{
       'p_merchant_id':widget.merchantId,'p_open':open,
       'p_channel':ExpressRuntimeChannel.name,
     });
     if(mounted)setState(_refresh);
   }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(
     SnackBar(content:Text('No se pudo cambiar el estado: $e')));}
   finally{if(mounted)setState(()=>saving=false);}
 }
 Future<void> _edit(Map<String,dynamic>? item,String currency)async{
   final name=TextEditingController(text:item?['name']?.toString()??'');
   final description=TextEditingController(text:item?['description']?.toString()??'');
   final price=TextEditingController(text:item?['price']?.toString()??'');
   final image=TextEditingController(text:item?['image_url']?.toString()??'');
   var active=item?['active']!=false;
   final ok=await showDialog<bool>(context:context,builder:(context)=>
     StatefulBuilder(builder:(context,setLocal)=>AlertDialog(
       title:Text(item==null?'Nuevo producto':'Editar producto'),
       content:ConstrainedBox(constraints:const BoxConstraints(maxWidth:550),
         child:SingleChildScrollView(child:Column(
           mainAxisSize:MainAxisSize.min,children:[
             TextField(controller:name,
               decoration:const InputDecoration(labelText:'Nombre del producto')),
             const SizedBox(height:10),
             TextField(controller:description,maxLines:2,
               decoration:const InputDecoration(labelText:'Descripción')),
             const SizedBox(height:10),
             TextField(controller:price,keyboardType:TextInputType.number,
               decoration:InputDecoration(labelText:'Precio $currency')),
             const SizedBox(height:10),
             TextField(controller:image,
               decoration:const InputDecoration(labelText:'URL de la fotografía (opcional)')),
             SwitchListTile(value:active,onChanged:(v)=>setLocal(()=>active=v),
               title:const Text('Producto disponible')),
           ]))),
       actions:[
         TextButton(onPressed:()=>Navigator.pop(context,false),
           child:const Text('Cancelar')),
         FilledButton(onPressed:()=>Navigator.pop(context,true),
           child:const Text('Guardar')),
       ],
     )));
   if(ok==true&&mounted){
     final amount=num.tryParse(price.text.trim());
     if(amount==null||amount<0||name.text.trim().length<2){
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
         content:Text('Completa el nombre y un precio válido.')));
     }else{
       setState(()=>saving=true);
       try{
         await supabase.rpc('marketplace_merchant_upsert_product',params:{
           'p_merchant_id':widget.merchantId,
           'p_product_id':item?['id'],
           'p_name':name.text.trim(),
           'p_description':description.text.trim(),
           'p_price':amount,
           'p_active':active,
           'p_image_url':image.text.trim(),
           'p_channel':ExpressRuntimeChannel.name,
         });
         if(mounted)setState(_refresh);
       }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content:Text('No se pudo guardar el producto: $e')));}
       finally{if(mounted)setState(()=>saving=false);}
     }
   }
   name.dispose();description.dispose();price.dispose();image.dispose();
 }
 @override Widget build(BuildContext context)=>Scaffold(
   appBar:AppBar(title:const Text('Mi restaurante y productos'),
     actions:[IconButton(onPressed:()=>setState(_refresh),
       icon:const Icon(Icons.refresh))]),
   body:FutureBuilder<Map<String,dynamic>>(future:future,
     builder:(context,snapshot){
       if(snapshot.connectionState!=ConnectionState.done)
         return const Center(child:CircularProgressIndicator());
       if(snapshot.hasError)return Center(child:Text(
         'No se pudo cargar el restaurante: ${snapshot.error}'));
       final data=snapshot.data??<String,dynamic>{};
       final merchant=data['merchant'] is Map?Map<String,dynamic>.from(data['merchant']):{};
       final stats=data['stats'] is Map?Map<String,dynamic>.from(data['stats']):{};
       final role=data['role']?.toString()??'staff';
       final canEdit=role=='owner'||role=='manager';
       final products=(data['products'] is List ? data['products'] as List:[])
         .whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
       final currency=data['currency']?.toString()??'CLP';
       final open=merchant['open_override']!=false;
       return Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:950),
         child:ListView(padding:const EdgeInsets.all(18),children:[
           Text(widget.merchantName,
             style:Theme.of(context).textTheme.headlineSmall),
           const SizedBox(height:12),
           Card(child:Padding(padding:const EdgeInsets.all(15),
             child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
               Row(children:[
                 Expanded(child:Text('Estado del restaurante',
                   style:Theme.of(context).textTheme.titleMedium)),
                 Chip(label:Text(open?'Abierto':'Cerrado')),
               ]),
               if(canEdit)SwitchListTile(
                 value:open,onChanged:saving?null:_setOpen,
                 title:const Text('Recibir nuevos pedidos'),
                 subtitle:const Text('Recibirás nuevos pedidos cuando el servicio esté disponible.')),
               const Divider(),
               Wrap(spacing:16,runSpacing:10,children:[
                 Text('Pedidos (30 días): ${stats['orders']??0}'),
                 Text('Entregados: ${stats['delivered']??0}'),
                 Text('Pendientes: ${stats['pending']??0}'),
                 Text('Ventas de productos: ${expressMoney(stats['sales_products']??0,currency)}'),
               ]),
             ]))),
           const SizedBox(height:16),
           Row(children:[
             Expanded(child:Text('Productos',
               style:Theme.of(context).textTheme.titleLarge)),
             if(canEdit)FilledButton.icon(onPressed:saving?null:()=>_edit(null,currency),
               icon:const Icon(Icons.add),label:const Text('Crear producto')),
           ]),
           const SizedBox(height:8),
           if(products.isEmpty)const Card(child:Padding(
             padding:EdgeInsets.all(20),child:Text('Aún no hay productos.'))),
           for(final item in products)Card(child:ListTile(
             leading:const CircleAvatar(child:Icon(Icons.fastfood_outlined)),
             title:Text(item['name']?.toString()??'Producto'),
             subtitle:Text('${expressMoney(item['price']??0,currency)} · '
               '${item['active']==false?'Oculto':'Disponible'} · '
               'Vendidos ${item['sold_count']??0}'),
             trailing:canEdit?IconButton(
               onPressed:()=>_edit(item,currency),
               icon:const Icon(Icons.edit_outlined)):null,
           )),
           const SizedBox(height:12),
           const Text('Desactivar un producto lo retira del catálogo sin '
             'borrar sus ventas ni el historial de pedidos.',
             style:TextStyle(fontSize:12)),
         ])));
     }),
 );
}
