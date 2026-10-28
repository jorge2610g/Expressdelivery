import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'video_style_home.dart';

void main(){
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _PresentationApp());
}

class _PresentationApp extends StatefulWidget {
  const _PresentationApp();
  @override
  State<_PresentationApp> createState()=>_PresentationAppState();
}

class _PresentationAppState extends State<_PresentationApp> {
  final String role=Uri.base.queryParameters['role']=='conductor'?'conductor':'pasajero';
  int step=0;
  double fare=18;
  String origin='Mi ubicación actual';
  String destination='Plaza Principal';

  @override
  void initState(){
    super.initState();
    html.window.onMessage.listen((event){
      if(event.origin!=html.window.location.origin)return;
      dynamic data;
      try { data = event.data is String ? jsonDecode(event.data as String) : event.data; } catch (_) { return; }
      if(data is! Map || data['source']!='express-moto-parent')return;
      final rawStep=data['step'];
      if(rawStep is num){
        setState((){
          step=rawStep.toInt().clamp(0,13);
          final v=data['fare'];if(v is num)fare=v.toDouble();
          final o=data['origin'];if(o is String)origin=o;
          final d=data['destination'];if(d is String)destination=d;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_){send('ready');});
  }

  void send(String action){
    html.window.parent?.postMessage(jsonEncode({'source':'express-moto-flutter','role':role,'action':action}),html.window.location.origin);
  }

  @override
  Widget build(BuildContext context){
    return MaterialApp(
      title:'Express Moto · Demostración',debugShowCheckedModeBanner:false,
      theme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF0B57D0)),
        scaffoldBackgroundColor:const Color(0xFFF5F7FB),fontFamily:'Roboto'),
      home:ExpressMotoPresentationPhone(role:role,step:step,fare:fare,origin:origin,destination:destination,onAction:send),
    );
  }
}