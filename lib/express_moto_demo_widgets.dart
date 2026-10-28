part of 'video_style_home.dart';

/* Matches the official driver's PIN de abordaje confirmation dialog.
 * The presentation validates locally against a DEMO PIN, with no Supabase calls.
 * It must never advance a trip if the code is missing or incorrect.
 */
Future<String?> showExpressMotoDemoPinDialog(BuildContext context) async {
  final controller = TextEditingController();
  bool showError = false;
  try {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void confirmPin() {
            final pin = controller.text.trim();
            if (pin == '4826') {
              Navigator.of(dialogContext).pop(pin);
            } else {
              setDialogState(() => showError = true);
            }
          }
          return AlertDialog(
            title: const Text('PIN de abordaje'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              onChanged: (_) {
                if (showError) setDialogState(() => showError = false);
              },
              onSubmitted: (_) => confirmPin(),
              decoration: InputDecoration(
                hintText: '0000',
                helperText: 'Pide al pasajero su PIN de 4 dígitos.',
                errorText: showError
                    ? 'PIN incorrecto. Usa 4826 en esta demostración.'
                    : null,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: confirmPin,
                child: const Text('Iniciar viaje'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    controller.dispose();
  }
}


/// Public presentation facade that reuses the EXACT production Flutter widgets.
/// No Supabase initialization, authentication, RPC, or trip mutations occur here.
class ExpressMotoPresentationPhone extends StatefulWidget {
  final String role;
  final int step;
  final double fare;
  final String origin;
  final String destination;
  final ValueChanged<String> onAction;

  const ExpressMotoPresentationPhone({
    super.key,
    required this.role,
    required this.step,
    required this.fare,
    required this.origin,
    required this.destination,
    required this.onAction,
  });

  @override
  State<ExpressMotoPresentationPhone> createState() => _ExpressMotoPresentationPhoneState();
}

class _ExpressMotoPresentationPhoneState extends State<ExpressMotoPresentationPhone> {
  final _sender = TextEditingController();
  final _senderPhone = TextEditingController();
  final _recipient = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _description = TextEditingController();
  bool online = false;
  int rating = 5;

  void send(String action) => widget.onAction(action);

  Future<void> _confirmDemoStartWithPin() async {
    final pin = await showExpressMotoDemoPinDialog(context);
    if (!mounted || pin == null) return;
    // The parent advances BOTH demo phones directly to the in-progress state.
    // No real driver request, trip mutation or payment is performed here.
    send('pin-verified');
  }

  @override
  void dispose() {
    for (final c in [_sender, _senderPhone, _recipient, _recipientPhone, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  static const _start = LatLng(-14.8328, -64.9036);
  static const _end = LatLng(-14.8277, -64.8977);

  Map<String, dynamic> get ride => {
    'id':'demo-request','pickup_address': widget.origin,
    'destination_address': widget.destination,
    'pickup_latitude': _start.latitude,'pickup_longitude': _start.longitude,
    'destination_latitude':_end.latitude,'destination_longitude':_end.longitude,
    'category':'motorcycle','service_mode':'ride','currency':'BOB',
    'proposed_fare':widget.fare,'route_distance_km':2.8,
    'payment_method':'cash',
    'created_at':DateTime.now().toUtc().toIso8601String(),
    'expires_at':DateTime.now().toUtc().add(const Duration(minutes: 3)).toIso8601String(),
    'quick_offer_steps':[1,2,3],
  };

  String get tripStatus {
    if(widget.step==7)return 'driver_arriving';
    if(widget.step==8||widget.step==9)return 'driver_waiting';
    if(widget.step==10)return 'in_progress';
    return 'driver_assigned';
  }

  Map<String,dynamic> get trip => {
    'id':'demo-trip','status':tripStatus,'final_fare':widget.fare,
    'boarding_pin':'4826','currency':'BOB','ride_requests':ride,
    'waiting_since':DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String(),
  };

  Widget officialMap(BuildContext context) {
    final showRoute = widget.step>=3 && widget.step<=11;
    final showMoto = widget.step>=5 && widget.step<=11;
    const a = _start;
    const b = _end;
    final moved = widget.step>=10 ? LatLng(-14.829, -64.900)
        : widget.step>=8 ? a : LatLng(-14.8362, -64.9055);
    return FlutterMap(
      options: const MapOptions(initialCenter: LatLng(-14.832, -64.901), initialZoom: 14.5,
        interactionOptions: InteractionOptions(flags: InteractiveFlag.none)),
      children: [
        _expressMapTileLayer(context),
        if(showRoute) PolylineLayer(polylines:[
          Polyline(points:[a,LatLng(-14.834, -64.899),LatLng(-14.8305,-64.899),b],color:expressBlue,strokeWidth:5),
        ]),
        MarkerLayer(markers: [
          Marker(point:a,width:42,height:42,child: const Icon(Icons.trip_origin,color:expressBlue,size:32)),
          if(showRoute) Marker(point:b,width:44,height:44,child: const Icon(Icons.location_on_rounded,color:Color(0xFFFFB000),size:37)),
          if(showMoto) Marker(point:moved,width:46,height:46,child: Container(
            decoration:BoxDecoration(color:expressBlue,shape:BoxShape.circle,border:Border.all(color:Colors.white,width:3)),
            child: const Icon(Icons.two_wheeler_rounded,color:Colors.white,size:25),
          )),
        ]),
      ],
    );
  }

  Widget officialSurface(Widget child, {double? maxFraction}) {
    return Align(alignment:Alignment.bottomCenter,child: FractionallySizedBox(
      widthFactor:1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight:530),
        child: SingleChildScrollView(
          padding:EdgeInsets.zero,
          child:child,
        ),
      ),
    ));
  }

  Widget panel(List<Widget> content) => _PanelShell(controller:null,children:content);

  Widget passenger(BuildContext context) {
    final step=widget.step;
    if (step<=1) return officialSurface(panel([
      const Text('¿A dónde vas?',textAlign:TextAlign.center,style:TextStyle(fontSize:25,fontWeight:FontWeight.w900,color:expressDark)),
      const SizedBox(height:12),
      _HomeDestinationSearch(serviceType:'ride',onTap:()=>send('advance')),
      const SizedBox(height:15),
      const _RiderSectionTitle('Lugares guardados'),
      const SizedBox(height:8),
      _SavedPlacesGrid(saved: const [],onSaved:(_){send('advance');},onManage:()=>send('advance')),
      const SizedBox(height:10),
      SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:()=>send('advance'),icon:const Icon(Icons.search_rounded),label:const Text('Buscar destino'))),
    ]));
    if (step==2) return officialSurface(panel([
      const Text('Confirma tu ruta',textAlign:TextAlign.center,style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),
      const SizedBox(height:8),
      Text('Origen: ${widget.origin}',style:const TextStyle(fontSize:13)),
      const SizedBox(height:14),
      for(final place in const ['Plaza Principal','Terminal de Buses','Mercado Central'])
        ListTile(leading:const Icon(Icons.place_outlined,color:expressBlue),title:Text(place),
          onTap:()=>send('destination:'+place),trailing:const Icon(Icons.chevron_right)),
      const Text('Selecciona un destino de ejemplo.',style:TextStyle(fontSize:12,color:expressMuted)),
    ]));
    if (step==3) return officialSurface(_RideServiceChooserPanel(
      serviceType:'ride',parcelAvailable:false,parcelKind:null,onParcelKind:(_){},
      parcelSenderName:_sender,parcelSenderPhone:_senderPhone,
      parcelRecipientName:_recipient,parcelRecipientPhone:_recipientPhone,
      parcelDescription:_description,parcelPhotoCount:0,parcelPhotosUploading:false,onAddParcelPhotos:(){},
      onType:(_){},services: const [
        {'service_key':'motorcycle','name':'Moto','description':'Más ágil','vehicle_type':'motorcycle','enabled':true,'allow_bidding':true,'allow_fixed_price':true},
      ],settings:const {},zoneName:'Trinidad',currencyCode:'BOB',category:'motorcycle',payment:'cash',
      fare:widget.fare,minimumFare:5,fareReady:true,scheduledFor:null,
      routeDistanceKm:2.8,routeDurationMinutes:8,routing:false,quoting:false,creating:false,
      onReviewRoute:()=>send('back'),onRetryFare:(){},onCategory:(_){},
      onFare:(v)=>send('fare:'+v.toString()),onEditFare:()=>send('fare-plus'),
      onSchedule:(){},onPayment:(){},onCreate:()=>send('advance'),
    ));
    if (step==4||step==5) return officialSurface(panel([
      _PassengerSearchStatusCard(ride:ride,viewedCount:step==5?1:0,
        viewers:const [],nearbyCount:2,autoAcceptNearest:false,onAutoAcceptNearest:(_){},
        onCancel:()=>send('cancel')),
      SizedBox(width:double.infinity,child:FilledButton(
        onPressed:()=>send('advance'),child:const Text('Continuar demostración'))),
    ]));
    if (step==6)return officialSurface(panel([
      const Text('Elige a un conductor',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900)),
      const SizedBox(height:9),
      const Text('Todos los conductores están verificados',style:TextStyle(fontSize:12,fontWeight:FontWeight.w700)),
      const SizedBox(height:12),
      _PassengerDriverOfferCard(offer:{'id':'demo-offer','proposed_fare':widget.fare,'eta_minutes':4,
        'driver_user':{'full_name':'Carlos M.'},
        'driver_profiles':{'rating':4.9,'completed_trips':120,'vehicle_summary':'Moto negra · MOT-218'}},
        currency:'BOB',remainingSeconds:28,passengerFare:widget.fare,
        onAccept:()=>send('advance'),onReject:()=>send('cancel')),
    ]));
    if (step>=7&&step<=10) return officialSurface(panel([
      _PassengerActiveTripCard(trip:trip,driver:const {'full_name':'Carlos M.'},
        driverProfile:const {'rating':4.9,'completed_trips':120,'vehicle_summary':'Moto negra'},
        vehicle:const {'color':'Negra','brand':'Moto','model':'125','plate':'MOT-218'},
        adSettings:const {},onMap:()=>send('info:navegación'),
        onChat:()=>send('info:chat'),onCall:()=>send('info:llamada'),
        onShare:()=>send('info:compartir'),onEmergency:()=>send('info:seguridad'),
        onPassengerOnWay:()async{send('info:ya voy');return true;},onCancel:()=>send('cancel')),
      if(step==9) ...[
        const SizedBox(height:10),
        const Center(child: Text('PIN de recogida · 4826',style:TextStyle(fontWeight:FontWeight.bold,fontSize:17,color:expressBlue))),
      ],
    ]));
    if(step==11)return officialSurface(panel([
      const Center(child:Icon(Icons.check_circle_rounded,color:Color(0xFF16A36B),size:56)),
      const Text('¡Llegaste a destino!',textAlign:TextAlign.center,style:TextStyle(fontSize:21,fontWeight:FontWeight.w900)),
      const SizedBox(height:8),
      Text('Total acordado: ${_rideMoney(widget.fare,'BOB')}',textAlign:TextAlign.center),
      SizedBox(width:double.infinity,child:FilledButton(onPressed:()=>send('advance'),child:const Text('Calificar al conductor'))),
    ]));
    if(step==12)return officialSurface(panel([
      const Center(child:Icon(Icons.star_rounded,color:Color(0xFFFFC928),size:48)),
      const Text('Califica al conductor',textAlign:TextAlign.center,style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),
      const SizedBox(height:12),
      Row(mainAxisAlignment:MainAxisAlignment.center,children:List.generate(5,(i)=>IconButton(
        onPressed:()=>setState(()=>rating=i+1),
        icon:Icon(i<rating?Icons.star_rounded:Icons.star_border_rounded,color:const Color(0xFFFFC928),size:30)))),
      SizedBox(width:double.infinity,child:FilledButton(onPressed:()=>send('advance'),child:const Text('Enviar calificación'))),
    ]));
    return officialSurface(panel([
      const Text('Mis servicios',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),
      const SizedBox(height:8),
      const ListTile(leading:Icon(Icons.check_circle,color:Color(0xFF16A36B)),title:Text('Viaje completado'),subtitle:Text('Moto · Trinidad')),
      Text('${widget.origin}  →  ${widget.destination}'),
      const SizedBox(height:8),
      Text('Tarifa final: ${_rideMoney(widget.fare,'BOB')}',style:const TextStyle(fontWeight:FontWeight.bold)),
      SizedBox(width:double.infinity,child:FilledButton(onPressed:()=>send('reset'),child:const Text('Nueva demostración'))),
    ]));
  }

  Widget driver(BuildContext context) {
    final s=widget.step;
    if(s<=4){
      final data=_DriverStateData(service:ExpressService(),profile:{'approval_status':'approved','online_status':s>=3?'online':'offline'},
        rides:s==4?[ride]:[]);
      return officialSurface(_DriverBottomPanel(controller:null,data:data,transitionBusy:false,
        current:_start,onToggle:()=>send('advance'),onRequests:()=>send('advance'),
        onDelivery:(_){},onTripTracking:(_){},onDeliveryTracking:(_){},
        onAdvanceTrip:(_){},onAdvanceDelivery:(_){},onCancelTrip:(_){},onCancelDelivery:(_){},onRatePending:(_){},
      ));
    }
    if(s==5||s==6) return _DriverRequestPopup(
      ride:ride,current:_start,remainingSeconds:26,automatic:true,
      onClose:()=>send('info:ignorar oferta'),onOffer:()=>send('advance'),
      onQuickOffer:(v)=>send('fare:'+v.toString()),onAccept:()=>send('advance'),
    );
    if(s>=7&&s<=10)return officialSurface(panel([
      _DriverActiveTripCard(trip:trip,passenger:const {'full_name':'Pasajero Express'},
        onMap:()=>send('info:waze'),onChat:()=>send('info:chat'),onCall:()=>send('info:llamada'),
        primaryLabel:_driverTripNextLabel(tripStatus),
        onPrimary:tripStatus=='driver_waiting' ? _confirmDemoStartWithPin : ()=>send('advance'),
        onCancel:()=>send('cancel')),
      if(s==9)...[
        const SizedBox(height:10),
        const Center(child:Text('PIN de demostración: 4826',style:TextStyle(color:expressBlue,fontWeight:FontWeight.bold))),
      ],
    ]));
    if(s==11)return officialSurface(panel([
      const Center(child:Icon(Icons.check_circle_rounded,color:Color(0xFF16A36B),size:56)),
      const Text('Viaje completado',textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.w900,fontSize:22)),
      const SizedBox(height:8),Text('Monto: ${_rideMoney(widget.fare,'BOB')}'),
      SizedBox(width:double.infinity,child:FilledButton(onPressed:()=>send('advance'),child:const Text('Continuar'))),
    ]));
    if(s==12)return officialSurface(panel([
      const Text('Califica al pasajero',style:TextStyle(fontWeight:FontWeight.w900,fontSize:22)),
      const SizedBox(height:9),
      Row(mainAxisAlignment:MainAxisAlignment.center,children:List.generate(5,(i)=>IconButton(
        onPressed:()=>setState(()=>rating=i+1),icon:Icon(i<rating?Icons.star_rounded:Icons.star_border_rounded,color:const Color(0xFFFFC928))))),
      SizedBox(width:double.infinity,child:FilledButton(onPressed:()=>send('advance'),child:const Text('Guardar calificación'))),
    ]));
    return officialSurface(panel([
      const Text('Ganancias',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),
      ListTile(title:const Text('Viaje Moto completado'),subtitle:Text('${_rideMoney(widget.fare,'BOB')} · Pago en efectivo')),
      SizedBox(width:double.infinity,child:FilledButton(onPressed:()=>send('reset'),child:const Text('Reiniciar'))),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:const Color(0xFFF5F7FB),
      body:Stack(children:[
        Positioned.fill(child:officialMap(context)),
        Positioned(top:0,left:0,right:0,child:Container(
          padding:const EdgeInsets.fromLTRB(12,29,12,7),color:Colors.white.withValues(alpha:.91),
          child:Row(children:[
            IconButton(onPressed:()=>send('back'),icon:const Icon(Icons.menu_rounded,color:expressDark)),
            Expanded(child:FittedBox(
              fit:BoxFit.scaleDown,alignment:Alignment.centerLeft,
              child:Text(widget.role=='conductor'?'Express · Conductor':'Express',
                maxLines:1,softWrap:false,
                style:const TextStyle(fontWeight:FontWeight.w900,color:expressBlue,fontSize:20)),
            )),
            const Chip(label:Text('DEMO',style:TextStyle(fontSize:10))),
          ]),
        )),
        Positioned.fill(child: widget.role=='conductor'?driver(context):passenger(context)),
      ]),
    );
  }
}