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
      // In a presentation phone iframe the CSS viewport can be only 250–300px
      // wide. Flutter's original mobile widgets are designed around a normal
      // phone width, so laying them out directly causes words to stack and
      // headers to wrap. Lay out at a stable phone width, then uniformly scale
      // the *whole* genuine Flutter interface into the visible phone viewport.
      // FittedBox also transforms pointer coordinates: buttons still work.
      home:LayoutBuilder(builder:(context,constraints){
        final viewportWidth=constraints.maxWidth;
        final viewportHeight=constraints.maxHeight;
        if(!viewportWidth.isFinite || !viewportHeight.isFinite ||
            viewportWidth<1 || viewportHeight<1){
          return const SizedBox.shrink();
        }
        const referenceWidth=414.0;
        final logicalWidth=viewportWidth<referenceWidth ? referenceWidth : viewportWidth;
        final logicalHeight=viewportHeight*(logicalWidth/viewportWidth);
        return ClipRect(child:SizedBox(
          width:viewportWidth,height:viewportHeight,
          child:FittedBox(
            fit:BoxFit.contain,
            alignment:Alignment.topLeft,
            child:SizedBox(
              width:logicalWidth,height:logicalHeight,
              child:ExpressMotoPresentationPhone(
                role:role,step:step,fare:fare,
                origin:origin,destination:destination,onAction:send,
              ),
            ),
          ),
        ));
      }),
    );
  }
}