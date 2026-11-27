import 'package:flutter/material.dart';
import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'championship_prize_format.dart';

class DriverChampionshipPage extends StatefulWidget {
  const DriverChampionshipPage({super.key});
  @override
  State<DriverChampionshipPage> createState() => _DriverChampionshipPageState();
}

class _DriverChampionshipPageState extends State<DriverChampionshipPage> {
  // Share the same inherited app theme as the driver profile.
  // No route-level forced dark mode: colors update when the app switches theme.
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get bg => _dark ? const Color(0xFF0F1115) : const Color(0xFFF6F7F9);
  Color get surface => _dark ? const Color(0xFF22252B) : const Color(0xFFFFFFFF);
  Color get stroke => _dark ? const Color(0xFF343840) : const Color(0xFFE8EBF0);
  Color get gold => _dark ? const Color(0xFFFFD33B) : const Color(0xFF996600);
  Color get muted => _dark ? const Color(0xFFB3BBC8) : const Color(0xFF667085);
  Color get ink => _dark ? const Color(0xFFF5F7FA) : const Color(0xFF101828);
  Color get statSurface => _dark ? const Color(0xFF303540) : const Color(0xFFF3F5F9);
  Color get podiumSurface => _dark ? const Color(0xFF514222) : const Color(0xFFFFF6DE);
  Color get firstRankSurface => _dark ? const Color(0xFF76591B) : const Color(0xFFF3E1B1);
  Color get rankSurface => _dark ? const Color(0xFF404859) : const Color(0xFFE6EAF0);
  late Future<Map<String,dynamic>> _future;
  int _tab=0;
  Map<String,dynamic> _last=const {};
  bool _gateShown=false;
  Widget _ruleRow(String icon,String title,String body)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:7),
    child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(icon,style:const TextStyle(fontSize:20)),
      const SizedBox(width:10),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:TextStyle(color:ink,fontWeight:FontWeight.w800,fontSize:13)),
        const SizedBox(height:2),
        Text(body,style:TextStyle(color:muted,fontSize:12)),
      ])),
    ]));
  Future<void> _showRules(Map<String,dynamic> d,{bool mustAccept=false}) async {
    var checked=false,busy=false;
    String? error;
    final goals=d['goals'] is Map?Map<String,dynamic>.from(d['goals'] as Map):
      const {'first':50,'second':30,'third':10};
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,
      isDismissible:!mustAccept,enableDrag:!mustAccept,backgroundColor:bg,
      shape:const RoundedRectangleBorder(
        borderRadius:BorderRadius.vertical(top:Radius.circular(22))),
      builder:(sheetContext)=>StatefulBuilder(builder:(context,setSheet)=>
        SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(18,16,18,14),
          child:Column(mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Reglas del campeonato',style:TextStyle(color:ink,
              fontSize:18,fontWeight:FontWeight.w900)),
            const SizedBox(height:2),
            Text(mustAccept?'Léelas y acéptalas para participar.':
              'Léelas antes de participar.',
              style:TextStyle(color:muted,fontSize:12)),
            const SizedBox(height:8),
            Flexible(child:SingleChildScrollView(child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
              _ruleRow('🥇','1.er lugar','Al menos ${goals['first']} viajes válidos en el mes.'),
              _ruleRow('🥈','2.º lugar','Al menos ${goals['second']} viajes válidos en el mes.'),
              _ruleRow('🥉','3.er lugar','Al menos ${goals['third']} viajes válidos en el mes.'),
              _ruleRow('⚠️','Si no llegas a la meta','Quedas descartado del premio.'),
              _ruleRow('✅','Qué cuenta','Viajes completados en la zona, el servicio y las fechas del campeonato.'),
              _ruleRow('🚫','Qué no cuenta','Viajes cancelados o con irregularidades.'),
              _ruleRow('🔎','Viajes sospechosos',
                'Se descartan 3 o más viajes con el mismo pasajero en una semana, '
                'viajes repetidos con el mismo pasajero, tramo y hora, y los días '
                'en que solo llevas a pasajeros habituales mientras ignoras otras '
                'solicitudes. Trabaja con pasajeros distintos y atiende las solicitudes.'),
              _ruleRow('💰','Premios','No se pagan automáticamente. Se confirman al terminar, después de validar resultados.'),
              _ruleRow('🔄','Cada mes empieza de cero','Los viajes del mes anterior no se acumulan.'),
            ]))),
            if(mustAccept)...[
              CheckboxListTile(contentPadding:EdgeInsets.zero,
                controlAffinity:ListTileControlAffinity.leading,
                value:checked,onChanged:busy?null:(v)=>setSheet(()=>checked=v==true),
                title:Text('He leído y acepto las reglas del campeonato.',
                  style:TextStyle(color:ink,fontSize:13))),
              if(error!=null)
                Text(error!,style:const TextStyle(color:Colors.redAccent,fontSize:12)),
            ],
            const SizedBox(height:8),
            SizedBox(width:double.infinity,child:FilledButton(
              onPressed:mustAccept&&(!checked||busy)?null:()async{
                if(!mustAccept){ Navigator.of(sheetContext).pop(); return; }
                setSheet((){busy=true;error=null;});
                try {
                  await supabase.rpc('driver_championship_accept_rules_v1',
                    params:{'p_championship_id':d['id']});
                  if(sheetContext.mounted) Navigator.of(sheetContext).pop();
                  if(mounted) _refresh();
                } catch (_) {
                  setSheet((){busy=false;error='No se pudo guardar. Intenta de nuevo.';});
                }
              },
              child:Text(mustAccept?'Aceptar y participar':'Entendido'))),
          ])))));
  }
  Widget _myMonth(Map<String,dynamic> data){
    final goals=data['goals'];
    if(goals is! Map) return const SizedBox.shrink();
    final rides=_integer(data['my_rides']);
    final first=_integer(goals['first']),second=_integer(goals['second']),
      third=_integer(goals['third']);
    final notices=_integer(data['my_notices']),viewed=_integer(data['my_viewed']);
    final target=rides>=second?first:rides>=third?second:third;
    final left=target-rides;
    return Padding(padding:const EdgeInsets.only(bottom:16),
      child:_card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        _heading('Tu mes'),
        Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
          Text('$rides',style:TextStyle(color:gold,fontSize:27,fontWeight:FontWeight.w900)),
          const SizedBox(width:6),
          Text('viajes válidos',style:TextStyle(color:muted,fontSize:12)),
        ]),
        const SizedBox(height:8),
        ClipRRect(borderRadius:BorderRadius.circular(5),
          child:LinearProgressIndicator(minHeight:8,
            value:(rides/first).clamp(0.0,1.0).toDouble(),
            backgroundColor:statSurface,color:gold)),
        const SizedBox(height:8),
        Text('Metas del mes: 🥇 $first · 🥈 $second · 🥉 $third',
          style:TextStyle(color:ink,fontSize:12)),
        Text(left>0?'Te faltan $left viajes para la siguiente meta.':
          '¡Ya alcanzaste la meta del 1.er lugar!',
          style:TextStyle(color:muted,fontSize:12)),
        Text('Si no llegas a la meta de tu puesto, quedas descartado del premio.',
          style:TextStyle(color:muted,fontSize:11)),
        const Divider(height:22),
        Text('Solicitudes que te llegaron',style:TextStyle(color:ink,
          fontWeight:FontWeight.w800,fontSize:13)),
        const SizedBox(height:6),
        Text('Avisos recibidos: $notices · Abiertas: $viewed · Completadas: $rides',
          style:TextStyle(color:muted,fontSize:12)),
        if(notices>rides)Padding(padding:const EdgeInsets.only(top:6),
          child:Text('Te llegaron ${notices-rides} solicitudes que no terminaste. '
            'Aceptar más te acerca a los premios.',
            style:TextStyle(color:gold,fontSize:12))),
      ])));
  }
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
  Widget _card(Widget child,{Color? background}) => Container(
    width:double.infinity,padding:const EdgeInsets.all(16),
    decoration:BoxDecoration(color:background ?? surface,borderRadius:BorderRadius.circular(20),
      border:Border.all(color:stroke)),child:child);
  Widget _heading(String title)=>Padding(padding:const EdgeInsets.only(bottom:12),
    child:Text(title,style:TextStyle(color:ink,
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
              color:rank==0?podiumSurface:surface,
              borderRadius:BorderRadius.circular(16),
              border:Border.all(color:rank==0?gold:stroke)),
            child:Column(children:[
              Text(rank==0?'🥇':rank==1?'🥈':'🥉',
                style:TextStyle(fontSize:27)),
              const SizedBox(height:6),
              Text(rows.length>rank?rows[rank]['name'].toString():'—',
                maxLines:2,textAlign:TextAlign.center,
                overflow:TextOverflow.ellipsis,
                style:TextStyle(color:ink,fontSize:12,
                  fontWeight:FontWeight.w800)),
              const SizedBox(height:6),
              Text(rows.length>rank
                ?rows[rank]['rides'].toString()+' viajes':'Sin participantes',
                textAlign:TextAlign.center,
                style:TextStyle(color:gold,fontSize:11)),
            ])),
          )),
    ]);
  Widget _myStats(Map<String,dynamic> data,List<Map<String,dynamic>> rows) {
    final rank=_integer(data['my_position']),rides=_integer(data['my_rides']);
    final tenth=rows.length==10?_integer(rows.last['rides']):0;
    final needed=rank>10&&rows.length==10?tenth-rides+1:0;
    Widget stat(String label,String value,Color color)=>Expanded(
      child:Container(padding:const EdgeInsets.all(13),
      decoration:BoxDecoration(color:statSurface,
        borderRadius:BorderRadius.circular(13)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(label,style:TextStyle(color:muted,fontSize:12)),
        const SizedBox(height:5),
        Text(value,style:TextStyle(color:color,fontSize:25,
          fontWeight:FontWeight.w900))
      ])));
    return _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      _heading('Tu participación'),
      Row(children:[
        stat('Tu posición',rank>0?'#'+rank.toString():'—',gold),
        const SizedBox(width:9),
        stat('Mis viajes',rides.toString(),ink)]),
      const SizedBox(height:11),
      Text(rank<=3&&rank>0?'¡Estás en el podio!':
        needed>0?'Te faltan '+needed.toString()+' viajes para entrar al Top 10.':
        'Sigue sumando viajes para subir de posición.',
        style:TextStyle(color:ink,fontSize:13)),
      const SizedBox(height:12),
      SizedBox(width:double.infinity,child:FilledButton.icon(
        onPressed:()=>setState(()=>_tab=1),
        icon:Icon(Icons.leaderboard_outlined),
        label:Text('Ver clasificación'))),
    ]));
  }
  Widget _ranking(List<Map<String,dynamic>> rows)=>Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[
      _heading('Podio actual'),_podium(rows),const SizedBox(height:15),
      _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        _heading('Clasificación · Top 10'),
        if(rows.isEmpty)
          Text('Aún no hay participantes.',
            style:TextStyle(color:muted))
        else for(final row in rows)...[
          Row(children:[
            Container(height:30,width:30,
              alignment:Alignment.center,
              decoration:BoxDecoration(
                color:_integer(row['position'])==1
                  ?firstRankSurface:rankSurface,
                borderRadius:BorderRadius.circular(9)),
              child:Text(row['position'].toString(),
                style:TextStyle(color:ink,
                  fontWeight:FontWeight.w900))),
            const SizedBox(width:10),
            Expanded(child:Text(row['name'].toString(),
              style:TextStyle(color:row['is_me']==true?gold:ink,
                fontWeight:FontWeight.w700))),
            Text(row['rides'].toString(),style:TextStyle(
              color:ink,fontWeight:FontWeight.w900)),
            const SizedBox(width:5),
            Text('viajes',style:TextStyle(color:muted,fontSize:11)),
          ]),
          Divider(height:17,color:stroke),
        ],
        Text('Solo se muestran los 10 primeros. Tu puesto aparece por separado.',
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
            Text(prize[0].toString(),style:TextStyle(fontSize:27)),
            const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
              children:[
              Text(prize[1].toString(),style:TextStyle(
                color:ink,fontWeight:FontWeight.w800,fontSize:14)),
              const SizedBox(height:4),
              Text(prize[2]?.toString().isNotEmpty==true
                ?championshipPrizeLabel(prize[2],d['currency']):'Premio por anunciar',
                style:TextStyle(color:gold,fontSize:13))
            ]))
          ]))),
      _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        _heading('Reglas'),
        Text(d['rules']?.toString()??'Solo viajes válidos completados.',
          style:TextStyle(color:muted,fontSize:13)),
        const SizedBox(height:12),
        Text('Los premios no se pagan automáticamente. '
          'La entrega de premios se confirma al finalizar el campeonato.',
          style:TextStyle(color:muted,fontSize:12)),
      ]))
    ]);
  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:bg,
    appBar:AppBar(backgroundColor:bg,foregroundColor:ink,
      title:Text('Campeonato Express',
        style:TextStyle(fontWeight:FontWeight.w900)),
      actions:[
        IconButton(tooltip:'Reglas del campeonato',
          icon:Icon(Icons.info_outline,color:gold),
          onPressed:_last['available']==true?()=>_showRules(_last):null),
        IconButton(tooltip:'Actualizar',icon:Icon(Icons.refresh),
          onPressed:_refresh)]),
    body:FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,snapshot){
      if(snapshot.connectionState!=ConnectionState.done)
        return const Center(child:CircularProgressIndicator());
      if(snapshot.hasError)
        return Center(child:Padding(padding:const EdgeInsets.all(20),
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            Icon(Icons.error_outline,color:gold,size:40),
            const SizedBox(height:12),
            Text('No se pudo cargar el campeonato',
              style:TextStyle(color:ink,fontSize:17)),
            const SizedBox(height:9),
            Text(snapshot.error.toString(),textAlign:TextAlign.center,
              style:TextStyle(color:muted,fontSize:12)),
            TextButton.icon(onPressed:_refresh,icon:Icon(Icons.refresh),
              label:Text('Reintentar')),
          ])));
      final d=snapshot.data??<String,dynamic>{};
      final rows=_leaders(d);
      if(!identical(_last,d)){
        _last=d;
        WidgetsBinding.instance.addPostFrameCallback((_){
          if(mounted) setState((){});
        });
      }
      if(d['available']==true&&d['rules_accepted']==false&&!_gateShown){
        _gateShown=true;
        WidgetsBinding.instance.addPostFrameCallback((_){
          if(mounted) _showRules(d,mustAccept:true).whenComplete((){
            if(mounted) _gateShown=false;
          });
        });
      }
      if(d['available']!=true)
        return RefreshIndicator(onRefresh:_refresh,child:ListView(
          padding:const EdgeInsets.all(24),children:[
            const SizedBox(height:100),
            Icon(Icons.emoji_events_outlined,color:gold,size:64),
            const SizedBox(height:17),
            Text('Próximamente: Campeonato Express',
              textAlign:TextAlign.center,style:TextStyle(
                color:ink,fontSize:19,fontWeight:FontWeight.w900)),
            const SizedBox(height:10),
            Text(d['message']?.toString()??
              'Aún no hay un campeonato activo en tu ciudad.',
              textAlign:TextAlign.center,
              style:TextStyle(color:muted,fontSize:14))
          ]));
      final end=DateTime.tryParse(d['ends_at']?.toString()??'');
      final hours=end==null?0:end.toLocal().difference(DateTime.now()).inHours;
      final days=hours<=0?0:(hours+23)~/24;
      return RefreshIndicator(onRefresh:_refresh,child:ListView(
        padding:const EdgeInsets.fromLTRB(14,14,14,28),children:[
          _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              Icon(Icons.emoji_events_rounded,color:gold,size:31),
              const SizedBox(width:9),
              Expanded(child:Text(d['title']?.toString()??'Campeonato Express',
                style:TextStyle(color:ink,fontSize:20,
                  fontWeight:FontWeight.w900))),
              const Chip(label:Text('Activo',style:TextStyle(color:Colors.white,fontSize:11)),
                backgroundColor:Color(0xFF1BAA72)),
            ]),
            const SizedBox(height:9),
            Text((d['zone_name']?.toString()??'')+' · '+
              _service(d['service_key']?.toString()??'*'),
              style:TextStyle(color:muted,fontSize:12)),
            const SizedBox(height:6),
            Text('⏱ '+days.toString()+' días restantes',
              style:TextStyle(color:gold,fontSize:12)),
            const SizedBox(height:8),
            Text('Solo cuentan los viajes completados durante el campeonato.',
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
            _myMonth(d),
            _heading('Líderes del campeonato'),
            _podium(rows),const SizedBox(height:16),
            _card(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              _heading('¿Cómo participar?'),
              Text('Cada viaje que completes en la zona y servicio '
                'del campeonato suma un punto.',
                style:TextStyle(color:muted,fontSize:13)),
              const SizedBox(height:10),
              SizedBox(width:double.infinity,child:OutlinedButton.icon(
                onPressed:()=>setState(()=>_tab=2),
                icon:Icon(Icons.card_giftcard),
                label:Text('Ver premios')))
            ]))
          ]else if(_tab==1)...[
            _ranking(rows),const SizedBox(height:12),_myStats(d,rows)
          ]else _prizes(d),
        ]));
    }),
  );
}
