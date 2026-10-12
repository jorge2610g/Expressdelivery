import 'package:flutter/material.dart';
import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';

class DriverChampionshipPage extends StatefulWidget {
  const DriverChampionshipPage({super.key});
  @override
  State<DriverChampionshipPage> createState() => _DriverChampionshipPageState();
}

class _DriverChampionshipPageState extends State<DriverChampionshipPage> {
  static const bg=Color(0xFF15171C),surface=Color(0xFF292D37),
    stroke=Color(0xFF434959),gold=Color(0xFFFFD33B),
    muted=Color(0xFFBAC2D1);
  late Future<Map<String,dynamic>> _future;
  int _tab=0;
  @override
  void initState() { super.initState(); _load(); }

  void _load() {
    _future=() async {
      final result=await supabase.rpc('driver_championships_for_driver',
        params:{'p_channel':ExpressRuntimeChannel.name});
      if(result is Map) return Map<String,dynamic>.from(result);
      throw StateError('Datos del campeonato no disponibles');
    }();
  }
  Future<void> _refresh() async {
    setState(_load);
    try { await _future; } catch (_) {}
  }
  int _integer(Object? v)=>v is num?v.toInt():int.tryParse(v.toString())??0;
  List<Map<String,dynamic>> _leaders(Map<String,dynamic> data) {
    final raw=data['top_ten'];
    return raw is List?raw.whereType<Map>()
      .map((e)=>Map<String,dynamic>.from(e)).toList():[];
  }
  String _service(String raw) {
    if(raw=='motorcycle') return 'Moto';
    if(raw=='economy') return 'Express';
    if(raw=='comfort') return 'Comfort';
    if(raw=='xl') return 'XL';
    return 'Todos los servicios';
  }
  Widget _card(Widget child,{Color background=surface}) => Container(
    width:double.infinity,padding:const EdgeInsets.all(16),
    decoration:BoxDecoration(color:background,borderRadius:BorderRadius.circular(20),
      border:Border.all(color:stroke)),child:child);
  Widget _heading(String title)=>Padding(padding:const EdgeInsets.only(bottom:12),
    child:Text(title,style:const TextStyle(color:Colors.white,
      fontSize:17,fontWeight:FontWeight.w900)));
  Widget _tabItem(String label,int value,IconData icon)=>Expanded(
    child:Padding(padding:const EdgeInsets.symmetric(horizontal:3),
      child:InkWell(
        onTap:()=>setState(()=>_tab=value),
        borderRadius:BorderRadius.circular(12),
        child:Container(padding:const EdgeInsets.symmetric(vertical:13),
          decoration:BoxDecoration(
            color:_tab==value?const Color(0xFF205FCB):surface,
            borderRadius:BorderRadius.circular(12)),
          child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
            Icon(icon,size:16,color:_tab==value?Colors.white:muted),
            const SizedBox(width:5),
            Flexible(child:Text(label,maxLines:1,overflow:TextOverflow.ellipsis,
              style:TextStyle(color:_tab==value?Colors.white:muted,
                fontSize:12,fontWeight:FontWeight.w800))),
          ])))));
  Widget _podium(List<Map<String,dynamic>> rows)=>Row(
    crossAxisAlignment:CrossAxisAlignment.end,children:[
      for(final rank in [1,0,2])
        Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:4),
          child:Container(padding:const EdgeInsets.symmetric(
            horizontal:5,vertical:15),
            decoration:BoxDecoration(
              color:rank==0?const Color(0xFF514222):surface,
              borderRadius:BorderRadius.circular(16),
              border:Border.all(color:rank==0?gold:stroke)),
            child:Column(children:[
              Text(rank==0?'🥇':rank==1?'🥈':'🥉',
                style:const TextStyle(fontSize:27)),
              const SizedBox(height:6),
              Text(rows.length>rank?rows[rank]['name'].toString():'—',
                maxLines:2,textAlign:TextAlign.center,
                overflow:TextOverflow.ellipsis,
                style:const TextStyle(color:Colors.white,fontSize:12,
                  fontWeight:FontWeight.w800)),
              const SizedBox(height:6),
              Text(rows.length>rank
                ?rows[rank]['rides'].toString()+' viajes':'Sin participantes',
                textAlign:TextAlign.center,
                style:const TextStyle(color:gold,fontSize:11)),
            ])),
          ))),
    ]);
  Widget _myStats(Map<String,dynamic> data,List<Map<String,dynamic>> rows) {
    final rank=_integer(data['my_position']),rides=_integer(data['my_rides']);
    final tenth=rows.length==10?_integer(rows.last['rides']):0;
    final needed=rank>10&&rows.length==10?tenth-rides+1:0;
    Widget stat(String label,String value,Color color)=>Expanded(
      child:Container(padding:const EdgeInsets.all(13),
      decoration:BoxDecoration(color:const Color(0xFF363D4D),
        borderRadius:BorderRadius.circular(13)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(label,style:const TextStyle(color:muted,fontSize:12)),
        const SizedBox(height:5),
        Text(value,style:TextStyle(color:color,fontSize:25,
          fontWeight:FontWeight.w900))
      ])));
    return _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      _heading('Tu participación'),
      Row(children:[
        stat('Tu posición',rank>0?'#'+rank.toString():'—',gold),
        const SizedBox(width:9),
        stat('Mis viajes',rides.toString(),Colors.white)]),
      const SizedBox(height:11),
      Text(rank<=3&&rank>0?'¡Estás en el podio!':
        needed>0?'Te faltan '+needed.toString()+' viajes para entrar al Top 10.':
        'Sigue sumando viajes para subir de posición.',
        style:const TextStyle(color:Colors.white,fontSize:13)),
      const SizedBox(height:12),
      SizedBox(width:double.infinity,child:FilledButton.icon(
        onPressed:()=>setState(()=>_tab=1),
        icon:const Icon(Icons.leaderboard_outlined),
        label:const Text('Ver clasificación'))),
    ]));
  }
  Widget _ranking(List<Map<String,dynamic>> rows)=>Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[
      _heading('Podio actual'),_podium(rows),const SizedBox(height:15),
      _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        _heading('Clasificación · Top 10'),
        if(rows.isEmpty)
          const Text('Aún no hay participantes.',
            style:TextStyle(color:muted))
        else for(final row in rows)...[
          Row(children:[
            Container(height:30,width:30,
              alignment:Alignment.center,
              decoration:BoxDecoration(
                color:_integer(row['position'])==1
                  ?const Color(0xFF76591B):const Color(0xFF404859),
                borderRadius:BorderRadius.circular(9)),
              child:Text(row['position'].toString(),
                style:const TextStyle(color:Colors.white,
                  fontWeight:FontWeight.w900))),
            const SizedBox(width:10),
            Expanded(child:Text(row['name'].toString(),
              style:TextStyle(color:row['is_me']==true?gold:Colors.white,
                fontWeight:FontWeight.w700))),
            Text(row['rides'].toString(),style:const TextStyle(
              color:Colors.white,fontWeight:FontWeight.w900)),
            const SizedBox(width:5),
            const Text('viajes',style:TextStyle(color:muted,fontSize:11)),
          ]),
          const Divider(height:17,color:stroke),
        ],
        const Text('Solo se muestran los 10 primeros. Tu puesto aparece por separado.',
          style:TextStyle(color:muted,fontSize:11))
      ]))
    ]);
  Widget _prizes(Map<String,dynamic> d)=>Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[
      _heading('Premios del campeonato'),
      for(final prize in [
        ['🥇','Primer lugar',d['first_prize']],
        ['🥈','Segundo lugar',d['second_prize']],
        ['🥉','Tercer lugar',d['third_prize']],
      ])
        Padding(padding:const EdgeInsets.only(bottom:11),
          child:_card(Row(children:[
            Text(prize[0].toString(),style:const TextStyle(fontSize:27)),
            const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
              children:[
              Text(prize[1].toString(),style:const TextStyle(
                color:Colors.white,fontWeight:FontWeight.w800,fontSize:14)),
              const SizedBox(height:4),
              Text(prize[2]?.toString().isNotEmpty==true
                ?prize[2].toString():'Premio por anunciar',
                style:const TextStyle(color:gold,fontSize:13))
            ]))
          ]))),
      _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        _heading('Reglas'),
        Text(d['rules']?.toString()??'Solo viajes válidos completados.',
          style:const TextStyle(color:muted,fontSize:13)),
        const SizedBox(height:12),
        const Text('Los premios no se pagan automáticamente. '
          'El administrador confirma su entrega tras el cierre.',
          style:TextStyle(color:muted,fontSize:12)),
      ]))
    ]);
  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:bg,
    appBar:AppBar(backgroundColor:bg,foregroundColor:Colors.white,
      title:const Text('Campeonato Express',
        style:TextStyle(fontWeight:FontWeight.w900)),
      actions:[IconButton(tooltip:'Actualizar',icon:const Icon(Icons.refresh),
        onPressed:_refresh)]),
    body:FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,snapshot){
      if(snapshot.connectionState!=ConnectionState.done)
        return const Center(child:CircularProgressIndicator());
      if(snapshot.hasError)
        return Center(child:Padding(padding:const EdgeInsets.all(20),
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.error_outline,color:gold,size:40),
            const SizedBox(height:12),
            const Text('No se pudo cargar el campeonato',
              style:TextStyle(color:Colors.white,fontSize:17)),
            const SizedBox(height:9),
            Text(snapshot.error.toString(),textAlign:TextAlign.center,
              style:const TextStyle(color:muted,fontSize:12)),
            TextButton.icon(onPressed:_refresh,icon:const Icon(Icons.refresh),
              label:const Text('Reintentar')),
          ])));
      final d=snapshot.data??<String,dynamic>{};
      final rows=_leaders(d);
      if(d['available']!=true)
        return RefreshIndicator(onRefresh:_refresh,child:ListView(
          padding:const EdgeInsets.all(24),children:[
            const SizedBox(height:100),
            const Icon(Icons.emoji_events_outlined,color:gold,size:64),
            const SizedBox(height:17),
            const Text('Próximamente: Campeonato Express',
              textAlign:TextAlign.center,style:TextStyle(
                color:Colors.white,fontSize:19,fontWeight:FontWeight.w900)),
            const SizedBox(height:10),
            Text(d['message']?.toString()??
              'Aún no hay un campeonato activo en tu ciudad.',
              textAlign:TextAlign.center,
              style:const TextStyle(color:muted,fontSize:14))
          ]));
      final end=DateTime.tryParse(d['ends_at']?.toString()??'');
      final hours=end==null?0:end.toLocal().difference(DateTime.now()).inHours;
      final days=hours<=0?0:(hours+23)~/24;
      return RefreshIndicator(onRefresh:_refresh,child:ListView(
        padding:const EdgeInsets.fromLTRB(14,14,14,28),children:[
          _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              const Icon(Icons.emoji_events_rounded,color:gold,size:31),
              const SizedBox(width:9),
              Expanded(child:Text(d['title']?.toString()??'Campeonato Express',
                style:const TextStyle(color:Colors.white,fontSize:20,
                  fontWeight:FontWeight.w900))),
              const Chip(label:Text('Activo',style:TextStyle(fontSize:11)),
                backgroundColor:Color(0xFF1BAA72)),
            ]),
            const SizedBox(height:9),
            Text((d['zone_name']?.toString()??'')+' · '+
              _service(d['service_key']?.toString()??'*'),
              style:const TextStyle(color:muted,fontSize:12)),
            const SizedBox(height:6),
            Text('⏱ '+days.toString()+' días restantes',
              style:const TextStyle(color:gold,fontSize:12)),
            const SizedBox(height:8),
            const Text('Solo cuentan los viajes completados durante el campeonato.',
              style:TextStyle(color:muted,fontSize:12)),
          ])),
          const SizedBox(height:12),
          Row(children:[
            _tabItem('Inicio',0,Icons.home_outlined),
            _tabItem('Top 10',1,Icons.leaderboard_outlined),
            _tabItem('Premios',2,Icons.card_giftcard_outlined),
          ]),
          const SizedBox(height:17),
          if(_tab==0)...[
            _myStats(d,rows),const SizedBox(height:16),
            _heading('Líderes del campeonato'),
            _podium(rows),const SizedBox(height:16),
            _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              _heading('¿Cómo participar?'),
              const Text('Cada viaje que completes en la zona y servicio '
                'del campeonato suma un punto.',
                style:TextStyle(color:muted,fontSize:13)),
              const SizedBox(height:10),
              SizedBox(width:double.infinity,child:OutlinedButton.icon(
                onPressed:()=>setState(()=>_tab=2),
                icon:const Icon(Icons.card_giftcard),
                label:const Text('Ver premios')))
            ]))
          ]else if(_tab==1)...[
            _ranking(rows),const SizedBox(height:12),_myStats(d,rows)
          ]else _prizes(d),
        ]));
    }),
  );
}
