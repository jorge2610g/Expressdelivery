import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'services/express_service.dart';
import 'marketplace_merchant_page.dart';

/// Independent responsive web entrypoint at /restaurantes/
/// No taxi routes, customer screens or privileged role bypass.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url:supabaseUrl,publishableKey:supabasePublishableKey);
  runApp(const ExpressRestaurantPortal());
}

class ExpressRestaurantPortal extends StatefulWidget {
  const ExpressRestaurantPortal({super.key});
  @override
  State<ExpressRestaurantPortal> createState()=>_RestaurantPortalState();
}

class _RestaurantPortalState extends State<ExpressRestaurantPortal> {
  StreamSubscription<AuthState>? _sub;
  bool _loggedIn = supabase.auth.currentSession!=null;
  @override
  void initState(){
    super.initState();
    _sub=supabase.auth.onAuthStateChange.listen((event){
      if(mounted)setState(()=>_loggedIn=supabase.auth.currentSession!=null);
    });
  }
  @override
  void dispose(){_sub?.cancel();super.dispose();}
  @override
  Widget build(BuildContext context)=>MaterialApp(
    debugShowCheckedModeBanner:false,
    title:'Restaurantes Express',
    theme:ThemeData(useMaterial3:true,
      colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF195DCB)),
      scaffoldBackgroundColor:const Color(0xFFF4F6FB)),
    darkTheme:ThemeData(useMaterial3:true,brightness:Brightness.dark,
      colorScheme:ColorScheme.fromSeed(
        seedColor:const Color(0xFF195DCB),
        brightness:Brightness.dark)),
    themeMode:ThemeMode.system,
    home:_loggedIn?const _RestaurantDashboardGate():const _RestaurantLogin(),
  );
}

class _RestaurantLogin extends StatefulWidget {
  const _RestaurantLogin();
  @override
  State<_RestaurantLogin> createState()=>_RestaurantLoginState();
}
class _RestaurantLoginState extends State<_RestaurantLogin> {
  final email=TextEditingController(),password=TextEditingController();
  bool register=false,busy=false,hidePassword=true;
  String? feedback;
  @override
  void dispose(){email.dispose();password.dispose();super.dispose();}
  Future<void> _submit() async {
    if(busy)return;
    if(!email.text.contains('@')||password.text.length<8){
      setState(()=>feedback='Ingresa un correo válido y una contraseña de al menos 8 caracteres.');
      return;
    }
    setState((){busy=true;feedback=null;});
    try{
      if(register){
        await supabase.auth.signUp(email:email.text.trim(),
          password:password.text);
        if(mounted)setState(()=>feedback='Cuenta creada. Verifica tu correo y espera que Express te asigne un restaurante.');
      } else {
        await supabase.auth.signInWithPassword(email:email.text.trim(),
          password:password.text);
      }
    }catch(_){
      if(mounted)setState(()=>feedback='No se pudo iniciar sesión. Revisa tus datos y el estado de tu cuenta.');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _emailAccessLink() async {
    if (busy) return;
    final mail = email.text.trim();
    if (!mail.contains('@')) {
      setState(() => feedback =
        'Escribe tu correo de Express para recibir un enlace de acceso.');
      return;
    }
    setState(() { busy = true; feedback = null; });
    try {
      // Only existing accounts. Never create an unbound Production account
      // when a Preview administrator requests a passwordless email link.
      await supabase.auth.signInWithOtp(
        email: mail,
        shouldCreateUser: false,
        emailRedirectTo: 'https://expressviajes.online/restaurantes/',
      );
      if (mounted) {
        setState(() => feedback =
          'Si tu correo ya está registrado, recibirás un enlace para ingresar. '
          'Revisa también la carpeta de spam. No necesitas contraseña.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => feedback =
          'No se pudo enviar el enlace. Comprueba el correo y vuelve a intentar. '
          'Si persiste, contacta al administrador de Express.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _googleLogin() async {
    if (busy) return;
    setState(() { busy = true; feedback = null; });
    try {
      // This is a separate web origin from Admin Express. Google OAuth
      // must create its own browser session, never copy admin credentials.
      final started = await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'https://expressviajes.online/restaurantes/',
      );
      if (!started && mounted) {
        setState(() => feedback =
          'No se pudo abrir Google. Intenta nuevamente.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => feedback =
          'No se pudo conectar con Google. Verifica la conexión e inténtalo otra vez.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(20),
      child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:440),
        child:Card(child:Padding(padding:const EdgeInsets.all(25),
          child:Column(mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            const Icon(Icons.storefront_rounded,size:54,color:Color(0xFF2563EB)),
            const SizedBox(height:10),
            Text('Restaurantes Express',textAlign:TextAlign.center,
              style:Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight:FontWeight.w900)),
            const SizedBox(height:5),
            const Text('Pedidos, transferencias, productos y liquidaciones',
              textAlign:TextAlign.center),
            const SizedBox(height:22),
            TextField(controller:email,keyboardType:TextInputType.emailAddress,
              autofillHints:const [AutofillHints.email],
              decoration:const InputDecoration(labelText:'Correo electrónico',
                prefixIcon:Icon(Icons.mail_outline))),
            const SizedBox(height:12),
            TextField(controller:password,obscureText:hidePassword,
              onSubmitted:(_)=>_submit(),
              decoration:InputDecoration(labelText:'Contraseña',
                prefixIcon:const Icon(Icons.lock_outline),
                suffixIcon:IconButton(
                  onPressed:()=>setState(()=>hidePassword=!hidePassword),
                  icon:Icon(hidePassword?Icons.visibility:Icons.visibility_off)))),
            const SizedBox(height:16),
            FilledButton.icon(onPressed:busy?null:_submit,
              icon:Icon(register?Icons.person_add_alt:Icons.login),
              label:Text(busy?'Procesando…':register?'Solicitar acceso':'Ingresar al restaurante')),
            const SizedBox(height:12),
            OutlinedButton.icon(
              onPressed:busy?null:_googleLogin,
              icon:const Icon(Icons.account_circle_outlined),
              label:const Text('Ingresar con Google'),
            ),
            const SizedBox(height:10),
            OutlinedButton.icon(
              onPressed:busy?null:_emailAccessLink,
              icon:const Icon(Icons.mark_email_unread_outlined),
              label:const Text('Recibir acceso por correo (sin contraseña)'),
            ),
            const SizedBox(height:8),
            const Text(
              'Usa tu cuenta autorizada de Express: Google si está vinculada '
              'a tu usuario, o un enlace enviado a tu correo registrado. '
              'Preview y Producción mantienen sus accesos separados.',
              textAlign:TextAlign.center,
              style:TextStyle(fontSize:12),
            ),
            TextButton(onPressed:busy?null:()=>setState((){
              register=!register;feedback=null;
            }),child:Text(register?'Ya tengo una cuenta':'Crear cuenta para solicitar acceso')),
            if(feedback!=null)Padding(padding:const EdgeInsets.all(7),
              child:Text(feedback!,textAlign:TextAlign.center)),
            const Divider(),
            const Text('El administrador de Express debe aprobar y asignar '
              'tu cuenta antes de que puedas gestionar un local.',
              textAlign:TextAlign.center,
              style:TextStyle(fontSize:12)),
          ])))))),
  );
}

class _RestaurantDashboardGate extends StatefulWidget {
  const _RestaurantDashboardGate();
  @override
  State<_RestaurantDashboardGate> createState()=>_RestaurantDashboardGateState();
}
class _RestaurantDashboardGateState extends State<_RestaurantDashboardGate> {
  final service=ExpressService();
  late Future<List<Map<String,dynamic>>> accessFuture;
  @override
  void initState(){super.initState();_load();}
  void _load(){
    accessFuture=()async {
      final result=await supabase.rpc('resolve_current_runtime_environment');
      if(result is! Map)throw StateError('No se pudo validar el entorno.');
      final environment=result['environment']?.toString()??'';
      if(result['allowed']!=true||
         (environment!='preview'&&environment!='production')){
        throw StateError('Esta cuenta no tiene un entorno operativo habilitado.');
      }
      ExpressRuntimeChannel.applyResolvedEnvironment(environment);
      return service.marketplaceMyMerchantAccess();
    }();
  }
  Future<void> _logout()async{
    await supabase.auth.signOut();
    ExpressRuntimeChannel.resetToCompiledMode();
  }
  @override
  Widget build(BuildContext context)=>FutureBuilder<List<Map<String,dynamic>>>(
    future:accessFuture,builder:(context,snapshot){
      if(snapshot.connectionState!=ConnectionState.done){
        return const Scaffold(body:Center(child:CircularProgressIndicator()));
      }
      if(snapshot.hasError||snapshot.data==null||snapshot.data!.isEmpty){
        return Scaffold(appBar:AppBar(title:const Text('Restaurantes Express'),
          actions:[IconButton(onPressed:_logout,icon:const Icon(Icons.logout))]),
          body:Center(child:ConstrainedBox(
            constraints:const BoxConstraints(maxWidth:440),
            child:Padding(padding:const EdgeInsets.all(20),
              child:Column(mainAxisSize:MainAxisSize.min,children:[
                const Icon(Icons.store_outlined,size:48),
                const SizedBox(height:14),
                const Text('Acceso del restaurante pendiente de aprobación',
                  textAlign:TextAlign.center,style:TextStyle(fontSize:18,
                    fontWeight:FontWeight.w800)),
                const SizedBox(height:10),
                Text(snapshot.hasError?snapshot.error.toString():
                  'Has iniciado sesión correctamente. '
                  'Para acceder a un restaurante demo, abre '
                  'Admin Express → Restaurantes → Restaurantes demo → '
                  'Asignar usuario y selecciona esta cuenta. '
                  'El usuario debe pertenecer al mismo entorno.',
                  textAlign:TextAlign.center),
                const SizedBox(height:16),
                FilledButton.icon(onPressed:()=>setState(_load),
                  icon:const Icon(Icons.refresh),label:const Text('Actualizar acceso')),
              ])))));
      }
      return MarketplaceMerchantPanelPage(service:service,access:snapshot.data!);
    });
}
