import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_error_reporter.dart';
import '../core/supabase_client.dart';
import '../core/local_cache.dart';

class ExpressService {
  static Map<String, dynamic>? _preloadedPassengerHomeState;
  static String? _preloadedPassengerUserId;

  static const Duration _configFreshFor = Duration(seconds: 45);
  static const Duration _configUsableFor = Duration(minutes: 10);
  static Future<Map<String, dynamic>>? _runtimeConfigRefresh;
  static final Map<String, Future<List<Map<String, dynamic>>>>
      _serviceCatalogRefreshes =
      <String, Future<List<Map<String, dynamic>>>>{};

  Map<String, dynamic>? _myUserMemory;
  DateTime? _myUserMemoryAt;
  Map<String, dynamic>? _myDriverProfileMemory;
  DateTime? _myDriverProfileMemoryAt;
  List<Map<String, dynamic>>? _myVehiclesMemory;
  DateTime? _myVehiclesMemoryAt;

  bool _memoryFresh(DateTime? savedAt, Duration ttl) {
    if (savedAt == null) return false;
    return DateTime.now().toUtc().difference(savedAt) <= ttl;
  }

  String get userId {
    final id = supabase.auth.currentUser?.id;
    if (id == null) throw StateError('Sesión no disponible.');
    return id;
  }

  Future<Map<String, dynamic>> _fetchPassengerHomeState() async {
    try {
      await supabase.rpc('cleanup_expired_ride_offers');
    } catch (error, stack) {
      await AppErrorReporter.warning(
        'No se pudo limpiar ofertas vencidas; el Home continuará cargando.',
        source: 'passenger_home_cleanup',
        screen: 'passenger_home',
        eventName: 'OFFER_CLEANUP_FAILED_NON_BLOCKING',
        context: {'error_type': error.runtimeType.toString()},
      );
      // La limpieza es mantenimiento secundario. Nunca debe impedir que el
      // pasajero vea su solicitud, ofertas o viaje activo.
    }

    final row = await supabase.rpc('passenger_home_state');
    return Map<String, dynamic>.from(row as Map);
  }

  Future<Map<String, dynamic>> preloadPassengerHomeState() async {
    final state = await _fetchPassengerHomeState();
    _preloadedPassengerUserId = userId;
    _preloadedPassengerHomeState = Map<String, dynamic>.from(state);
    return state;
  }

  Future<Map<String, dynamic>?> passengerActiveTripLiveState() async {
    final row = await supabase.rpc('passenger_active_trip_live_state');
    if (row is Map) return Map<String, dynamic>.from(row);
    return null;
  }

  Future<bool> acknowledgeDriverWaiting(String tripId) async {
    final result = await supabase.rpc(
      'acknowledge_driver_waiting',
      params: {'p_trip_id': tripId},
    );
    return result == true;
  }

  Future<Map<String, dynamic>> passengerHomeState() async {
    if (_preloadedPassengerUserId == userId &&
        _preloadedPassengerHomeState != null) {
      final state =
          Map<String, dynamic>.from(_preloadedPassengerHomeState!);
      _preloadedPassengerHomeState = null;
      _preloadedPassengerUserId = null;
      return state;
    }
    return _fetchPassengerHomeState();
  }

  Future<Map<String, dynamic>> passengerLiveOfferState() async {
    final row = await supabase.rpc('passenger_live_offer_state');
    return Map<String, dynamic>.from(row as Map);
  }

  Stream<List<Map<String, dynamic>>> watchRideOffers(
    String rideRequestId,
  ) {
    return supabase
        .from('driver_offers')
        .stream(primaryKey: ['id'])
        .eq('ride_request_id', rideRequestId)
        .map(
          (rows) => rows
              .map((row) => Map<String, dynamic>.from(row))
              .toList(),
        );
  }

  Future<int> rideRequestViewCount(String rideRequestId) async {
    final value = await supabase.rpc(
      'ride_request_view_count',
      params: {'p_ride_request_id': rideRequestId},
    );
    return (value as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> rideRequestViewers(
    String rideRequestId,
  ) async {
    final row = await supabase.rpc(
      'ride_request_viewers',
      params: {'p_ride_request_id': rideRequestId},
    );
    if (row is! List) return const [];
    return row
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> markRideRequestsViewed(List<String> rideRequestIds) async {
    if (rideRequestIds.isEmpty) return;
    await supabase.rpc(
      'mark_ride_requests_viewed',
      params: {'p_ride_request_ids': rideRequestIds},
    );
  }

  Future<Set<String>> myViewedRideRequestIds() async {
    final row = await supabase.rpc('my_viewed_ride_request_ids');
    if (row is! List) return <String>{};
    return row
        .map((value) => value?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Future<Map<String, dynamic>> renewRideRequest(
    String rideRequestId, {
    num? proposedFare,
  }) async {
    final row = await supabase.rpc(
      'renew_ride_request',
      params: {
        'p_ride_request_id': rideRequestId,
        'p_proposed_fare': proposedFare,
      },
    );
    return Map<String, dynamic>.from(row as Map);
  }

  Future<List<Map<String, dynamic>>> nearbyOnlineDriverMarkers({
    required double latitude,
    required double longitude,
    double radiusKm = 5,
    String? vehicleType,
  }) async {
    final row = await supabase.rpc(
      'nearby_online_driver_markers',
      params: {
        'p_lat': latitude,
        'p_lng': longitude,
        'p_radius_km': radiusKm,
        'p_vehicle_type': vehicleType,
      },
    );
    if (row is! List) return const [];
    return row
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> declineRideOffer(String offerId) async {
    await supabase.rpc(
      'decline_ride_offer',
      params: {'p_offer_id': offerId},
    );
  }

  Future<Map<String, dynamic>> quoteFare({
    required String serviceKey,
    required num distanceKm,
    required num durationMinutes,
    double? pickupLatitude,
    double? pickupLongitude,
    bool previewDemand = false,
  }) async {
    final row = await supabase.rpc(
      'dynamic_pricing_quote',
      params: {
        'p_service_key': serviceKey,
        'p_distance_km': distanceKm,
        'p_duration_minutes': durationMinutes,
        'p_pickup_lat': pickupLatitude,
        'p_pickup_lng': pickupLongitude,
        'p_preview': previewDemand,
      },
    );
    return Map<String, dynamic>.from(row as Map);
  }

  Future<bool> _ratingAlreadyExists({
    String? tripId,
    String? deliveryId,
  }) async {
    if ((tripId == null || tripId.isEmpty) &&
        (deliveryId == null || deliveryId.isEmpty)) {
      return false;
    }

    dynamic query = supabase
        .from('ratings')
        .select('id')
        .eq('from_user_id', userId);

    if (tripId != null && tripId.isNotEmpty) {
      query = query.eq('trip_id', tripId);
    } else if (deliveryId != null && deliveryId.isNotEmpty) {
      query = query.eq('delivery_id', deliveryId);
    }

    final row = await query.limit(1).maybeSingle();
    return row != null;
  }

  Future<Map<String, dynamic>?> pendingRatingService() async {
    try {
      final settings = await appSettings();
      if (settings['ratings_enabled'] == false) return null;
    } catch (_) {}

    final row = await supabase.rpc('pending_rating_service');
    if (row == null) return null;
    final pending = Map<String, dynamic>.from(row as Map);

    // Durante pruebas una misma cuenta puede alternar Pasajero/Conductor.
    // No se debe intentar calificar a la propia cuenta porque RLS lo prohíbe.
    if (pending['to_user_id']?.toString() == userId) return null;

    // Defensa adicional contra estados/cachés antiguos: si la calificación ya
    // existe, nunca volvemos a mostrar la tarjeta pendiente.
    final kind = pending['kind']?.toString();
    final id = pending['id']?.toString();
    if (id != null &&
        await _ratingAlreadyExists(
          tripId: kind == 'trip' ? id : null,
          deliveryId: kind == 'delivery' ? id : null,
        )) {
      return null;
    }

    return pending;
  }


  Future<Map<String, dynamic>?> myUser({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _myUserMemory != null &&
        _memoryFresh(_myUserMemoryAt, const Duration(seconds: 30))) {
      return Map<String, dynamic>.from(_myUserMemory!);
    }

    final row = await supabase
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row != null) {
      final value = Map<String, dynamic>.from(row);
      _myUserMemory = value;
      _myUserMemoryAt = DateTime.now().toUtc();
      return Map<String, dynamic>.from(value);
    }

    final repaired = await supabase.rpc('ensure_my_profile');
    if (repaired == null) return null;
    final value = Map<String, dynamic>.from(repaired as Map);
    _myUserMemory = value;
    _myUserMemoryAt = DateTime.now().toUtc();
    return Map<String, dynamic>.from(value);
  }

  Future<Map<String, dynamic>?> userById(String id) async {
    final row = await supabase
        .from('users')
        .select('id,full_name,phone,avatar_url,active_mode')
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>?> driverProfileById(String id) async {
    final row = await supabase
        .from('driver_profiles')
        .select('id,rating,completed_trips,vehicle_summary,city,approval_status,online_status,latitude,longitude')
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? avatarUrl,
  }) async {
    await supabase.from('users').update({
      if (fullName != null) 'full_name': fullName,
      if (phone != null) 'phone': phone,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);
    _myUserMemory = null;
    _myUserMemoryAt = null;
  }

  Future<void> setActiveMode(String mode) async {
    await supabase.from('users').update({
      'active_mode': mode,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);
    _myUserMemory = null;
    _myUserMemoryAt = null;
  }

  Future<Map<String, dynamic>?> myDriverProfile({
    bool forceRefresh = false,
  }) async {
    // approval_status / online_status / ubicación operativa son datos dinámicos.
    // Nunca se sirven desde caché: el backend es la fuente de verdad.
    final row = await supabase
        .from('driver_profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> ensureDriverProfile() async {
    final current = await myDriverProfile();
    if (current != null) return current;
    final row = await supabase.from('driver_profiles').insert({
      'id': userId,
      'approval_status': 'pending',
      'online_status': 'offline',
    }).select().single();
    final value = Map<String, dynamic>.from(row);
    _myDriverProfileMemory = value;
    _myDriverProfileMemoryAt = DateTime.now().toUtc();
    return Map<String, dynamic>.from(value);
  }

  Future<void> setDriverOnline(bool online) async {
    final profile = await ensureDriverProfile();
    if (profile['approval_status'] != 'approved') {
      throw StateError('Tu perfil de conductor todavía está pendiente de aprobación.');
    }
    await supabase.from('driver_profiles').update({
      'online_status': online ? 'online' : 'offline',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);
    _myDriverProfileMemory = null;
    _myDriverProfileMemoryAt = null;
  }

  Future<void> updateDriverDetails({
    String? licenseNumber,
    String? vehicleSummary,
    String? city,
    double? latitude,
    double? longitude,
    double? headingDegrees,
  }) async {
    await ensureDriverProfile();
    await supabase.from('driver_profiles').update({
      if (licenseNumber != null) 'license_number': licenseNumber,
      if (vehicleSummary != null) 'vehicle_summary': vehicleSummary,
      if (city != null) 'city': city,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (headingDegrees != null) 'heading_degrees': headingDegrees,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);

    if (_myDriverProfileMemory != null) {
      final updated = Map<String, dynamic>.from(_myDriverProfileMemory!);
      if (licenseNumber != null) updated['license_number'] = licenseNumber;
      if (vehicleSummary != null) updated['vehicle_summary'] = vehicleSummary;
      if (city != null) updated['city'] = city;
      if (latitude != null) updated['latitude'] = latitude;
      if (longitude != null) updated['longitude'] = longitude;
      if (headingDegrees != null) updated['heading_degrees'] = headingDegrees;
      updated['updated_at'] = DateTime.now().toUtc().toIso8601String();
      _myDriverProfileMemory = updated;
      _myDriverProfileMemoryAt = DateTime.now().toUtc();
    }
  }

  Future<List<Map<String, dynamic>>> myVehicles({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _myVehiclesMemory != null &&
        _memoryFresh(_myVehiclesMemoryAt, const Duration(minutes: 2))) {
      return _myVehiclesMemory!
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }

    final rows = await supabase
        .from('driver_vehicles')
        .select()
        .eq('driver_id', userId)
        .order('created_at');
    final value = List<Map<String, dynamic>>.from(rows);
    _myVehiclesMemory = value;
    _myVehiclesMemoryAt = DateTime.now().toUtc();
    return value.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>?> driverVehicleById(String driverId) async {
    final rows = await supabase
        .from('driver_vehicles')
        .select('id,driver_id,vehicle_type,brand,model,color,plate,year,is_active')
        .eq('driver_id', driverId)
        .order('is_active', ascending: false)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<void> saveVehicle({
    required String vehicleType,
    String? brand,
    String? model,
    String? color,
    String? plate,
    int? year,
  }) async {
    await ensureDriverProfile();
    await supabase.from('driver_vehicles').insert({
      'driver_id': userId,
      'vehicle_type': vehicleType,
      'brand': brand,
      'model': model,
      'color': color,
      'plate': plate,
      'year': year,
    });
    _myVehiclesMemory = null;
    _myVehiclesMemoryAt = null;
  }

  Future<Map<String, dynamic>> createRideRequest({
    required String category,
    required String pickupAddress,
    required String destinationAddress,
    required num proposedFare,
    String paymentMethod = 'cash',
    double? pickupLatitude,
    double? pickupLongitude,
    double? destinationLatitude,
    double? destinationLongitude,
    double? routeDistanceKm,
    int? routeDurationMinutes,
    DateTime? scheduledFor,
    num? baseFare,
    num? demandMultiplier,
    String? demandLevel,
    int? demandRequests,
    int? demandDrivers,
    String? demandSectorKey,
  }) async {
    final settings = await appSettings(forceRefresh: true);
    Map<String, dynamic>? operationalContext;

    if (pickupLatitude != null && pickupLongitude != null) {
      operationalContext = await zoneContext(
        latitude: pickupLatitude,
        longitude: pickupLongitude,
        audience: 'passenger',
      );
      if (operationalContext['inside_coverage'] != true) {
        throw StateError(
          'Este punto de origen está fuera de una zona activa de Express.',
        );
      }

      final rawServices = operationalContext['services'];
      final allowed = rawServices is List &&
          rawServices.whereType<Map>().any(
                (service) =>
                    service['service_key']?.toString() == category &&
                    service['enabled'] != false &&
                    service['passenger_visible'] != false,
              );
      if (!allowed) {
        final zone = operationalContext['zone'];
        final zoneName = zone is Map
            ? (zone['name']?.toString() ?? 'esta zona')
            : 'esta zona';
        throw StateError(
          'Este servicio no está disponible en $zoneName.',
        );
      }
    }
    if (scheduledFor != null &&
        settings['scheduled_rides_enabled'] == false) {
      throw StateError('Los viajes programados están desactivados.');
    }

    bool paymentEnabled(String value) {
      final zone = operationalContext?['zone'];
      if (zone is Map) {
        final enabled = zone['payment_enabled'] != false;
        if (!enabled) return false;
        final country = (zone['country']?.toString() ?? '').toLowerCase();
        final provider = zone['payment_provider']?.toString() ??
            (country == 'bolivia'
                ? 'veripagos_qr'
                : country == 'chile'
                    ? 'mercado_pago'
                    : '');
        if (provider == 'veripagos_qr') return value == 'pagorut';
        if (provider == 'mercado_pago') return value == 'mercado_pago';
      }

      switch (value) {
        case 'card':
          return settings['allow_card'] == true;
        case 'wallet':
          return settings['allow_wallet'] == true;
        case 'pagorut':
          return settings['allow_pagorut'] == true;
        case 'mercado_pago':
          return settings['allow_mercadopago'] == true;
        case 'santander':
          return settings['allow_santander'] == true;
        case 'mach':
          return settings['allow_mach'] == true;
        case 'tenpo':
          return settings['allow_tenpo'] == true;
        default:
          return settings['allow_cash'] != false;
      }
    }

    if (!paymentEnabled(paymentMethod)) {
      throw StateError('El método de pago seleccionado no está habilitado.');
    }

    final rawSearchSeconds =
        (settings['search_timeout_seconds'] as num?)?.toInt() ?? 180;
    final searchSeconds = rawSearchSeconds.clamp(30, 1800).toInt();
    final expiresAt = scheduledFor == null
        ? DateTime.now().toUtc().add(Duration(seconds: searchSeconds))
        : scheduledFor.toUtc().add(const Duration(minutes: 30));

    final row = await supabase.from('ride_requests').insert({
      'passenger_id': userId,
      'category': category,
      'pickup_address': pickupAddress,
      'pickup_latitude': pickupLatitude,
      'pickup_longitude': pickupLongitude,
      'destination_address': destinationAddress,
      'destination_latitude': destinationLatitude,
      'destination_longitude': destinationLongitude,
      'route_distance_km': routeDistanceKm,
      'route_duration_minutes': routeDurationMinutes,
      'proposed_fare': proposedFare,
      if (baseFare != null) 'base_fare': baseFare,
      if (demandMultiplier != null) 'demand_multiplier': demandMultiplier,
      if (demandLevel != null) 'demand_level': demandLevel,
      if (demandRequests != null) 'demand_requests': demandRequests,
      if (demandDrivers != null) 'demand_drivers': demandDrivers,
      if (demandSectorKey != null) 'demand_sector_key': demandSectorKey,
      'currency': (() {
        final zone = operationalContext?['zone'];
        if (zone is Map && zone['currency_code'] != null) {
          return zone['currency_code'].toString();
        }
        return (settings['currency'] ?? 'BOB').toString();
      })(),
      'payment_method': paymentMethod,
      'status': 'searching',
      'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    }).select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> cancelRideRequest(String rideRequestId, {String? reason}) async {
    await supabase.rpc('cancel_ride_request', params: {
      'p_ride_request_id': rideRequestId,
      'p_reason': reason,
    });
  }

  Future<List<Map<String, dynamic>>> myRideRequests({
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    dynamic query = supabase
        .from('ride_requests')
        .select()
        .eq('passenger_id', userId);
    if (from != null) {
      query = query.gte('created_at', from.toUtc().toIso8601String());
    }
    if (to != null) {
      query = query.lt('created_at', to.toUtc().toIso8601String());
    }
    query = query.order('created_at', ascending: false);
    if (limit != null) query = query.limit(limit);
    final rows = await query;
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> availableRideRequests() async {
    // El RPC autoritativo ya excluye solicitudes vencidas con
    // expires_at > now(). La limpieza es mantenimiento y no debe sumar una
    // ida de red antes de mostrar solicitudes al conductor.
    unawaited(
      supabase
          .rpc('cleanup_expired_ride_requests')
          .catchError((Object _) => null),
    );

    // Solicitudes y vehículo son independientes: arrancarlos juntos evita dos
    // esperas de red consecutivas en cada refresco/push del modo conductor.
    final requestsFuture =
        supabase.rpc('available_ride_requests_for_driver');
    final vehiclesFuture = myVehicles().catchError(
      (Object _) => <Map<String, dynamic>>[],
    );

    final raw = await requestsFuture;
    final vehicles = await vehiclesFuture;
    final rows = raw is List
        ? List<Map<String, dynamic>>.from(
            raw.map((row) => Map<String, dynamic>.from(row as Map)),
          )
        : <Map<String, dynamic>>[];

    String? vehicleType;
    if (vehicles.isNotEmpty) {
      final active = vehicles.firstWhere(
        (row) => row['is_active'] == true,
        orElse: () => vehicles.first,
      );
      final stored = active['vehicle_type']?.toString().trim();
      if (stored != null && stored.isNotEmpty) vehicleType = stored;
    }

    bool matchesVehicle(Map<String, dynamic> row) {
      // Durante pruebas/onboarding, si aún no existe vehículo activo,
      // mostramos las solicitudes para no dejar el modo conductor vacío.
      if (vehicleType == null) return true;

      final category = row['category']?.toString() ?? 'economy';
      if (vehicleType == 'motorcycle') return category == 'motorcycle';
      if (vehicleType == 'xl') {
        return category == 'xl' ||
            category == 'economy' ||
            category == 'comfort';
      }
      return category == 'economy' || category == 'comfort';
    }

    return rows.where(matchesVehicle).toList();
  }

  Future<Map<String, dynamic>> createRideOffer({
    required String rideRequestId,
    required num fare,
    int? etaMinutes,
  }) async {
    final settings = await appSettings(forceRefresh: true);
    final minOffer = (settings['min_driver_offer'] as num?) ?? 1;
    final maxOffer = (settings['max_driver_offer'] as num?) ?? 9999;
    if (fare < minOffer || fare > maxOffer) {
      throw StateError(
        'La oferta debe estar entre $minOffer y $maxOffer.',
      );
    }

    final rawTimeout =
        (settings['offer_timeout_seconds'] as num?)?.toInt() ?? 30;
    final timeoutSeconds = rawTimeout.clamp(10, 600).toInt();
    final row = await supabase.from('driver_offers').upsert({
      'ride_request_id': rideRequestId,
      'driver_id': userId,
      'proposed_fare': fare,
      'eta_minutes': etaMinutes,
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'expires_at': DateTime.now()
          .toUtc()
          .add(Duration(seconds: timeoutSeconds))
          .toIso8601String(),
    }, onConflict: 'ride_request_id,driver_id').select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> offersForRide(String rideRequestId) async {
    final raw = await supabase.rpc(
      'passenger_pending_ride_offers',
      params: {'p_ride_request_id': rideRequestId},
    );
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<String> selectRideOffer(String offerId) async {
    final result = await supabase.rpc('select_ride_offer', params: {
      'p_offer_id': offerId,
    });
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> myTrips({
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    dynamic query = supabase
        .from('trips')
        .select('*,ride_requests(*)')
        .or('passenger_id.eq.$userId,driver_id.eq.$userId');
    if (from != null) {
      query = query.gte('created_at', from.toUtc().toIso8601String());
    }
    if (to != null) {
      query = query.lt('created_at', to.toUtc().toIso8601String());
    }
    query = query.order('created_at', ascending: false);
    if (limit != null) query = query.limit(limit);
    final rows = await query;

    final trips = List<Map<String, dynamic>>.from(
      rows.map((row) => Map<String, dynamic>.from(row)),
    );

    // Algunas sesiones antiguas/RLS pueden devolver el viaje pero no hidratar
    // la relación ride_requests. El historial y el mapa del conductor no deben
    // quedar sin origen, destino o coordenadas por ese motivo.
    final missingRideIds = trips
        .where((trip) => trip['ride_requests'] is! Map)
        .map((trip) => trip['ride_request_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    if (missingRideIds.isNotEmpty) {
      final routeRows = await supabase
          .from('ride_requests')
          .select()
          .inFilter('id', missingRideIds.toList());
      final byId = <String, Map<String, dynamic>>{
        for (final raw in routeRows)
          if (raw['id'] != null)
            raw['id'].toString(): Map<String, dynamic>.from(raw),
      };
      for (final trip in trips) {
        if (trip['ride_requests'] is Map) continue;
        final rideId = trip['ride_request_id']?.toString();
        final route = rideId == null ? null : byId[rideId];
        if (route != null) trip['ride_requests'] = route;
      }
    }

    return trips;
  }

  Future<void> advanceTrip(String tripId, String status) async {
    await supabase.rpc('advance_trip', params: {
      'p_trip_id': tripId,
      'p_status': status,
    });
  }

  Future<void> startTripWithPin({
    required String tripId,
    required String pin,
  }) async {
    await supabase.rpc(
      'start_trip_with_pin',
      params: {
        'p_trip_id': tripId,
        'p_pin': pin.trim(),
      },
    );
  }

  Future<void> cancelTrip(String tripId, {String? reason}) async {
    await supabase.rpc('cancel_trip', params: {
      'p_trip_id': tripId,
      'p_reason': reason,
    });
  }

  Future<List<Map<String, dynamic>>> tripHistory(String tripId) async {
    final rows = await supabase
        .from('trip_status_history')
        .select()
        .eq('trip_id', tripId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> createDelivery({
    required String packageType,
    required String pickupAddress,
    required String dropoffAddress,
    required num proposedFare,
    String paymentMethod = 'cash',
    String? details,
    double? pickupLatitude,
    double? pickupLongitude,
    double? dropoffLatitude,
    double? dropoffLongitude,
    double? routeDistanceKm,
    int? routeDurationMinutes,
  }) async {
    final row = await supabase.from('delivery_requests').insert({
      'customer_id': userId,
      'package_type': packageType,
      'pickup_address': pickupAddress,
      'pickup_latitude': pickupLatitude,
      'pickup_longitude': pickupLongitude,
      'dropoff_address': dropoffAddress,
      'dropoff_latitude': dropoffLatitude,
      'dropoff_longitude': dropoffLongitude,
      'route_distance_km': routeDistanceKm,
      'route_duration_minutes': routeDurationMinutes,
      'details': details,
      'proposed_fare': proposedFare,
      'currency': 'BOB',
      'payment_method': paymentMethod,
      'status': 'searching',
    }).select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> myDeliveries({
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    dynamic query = supabase
        .from('delivery_requests')
        .select()
        .or('customer_id.eq.$userId,courier_id.eq.$userId');
    if (from != null) {
      query = query.gte('created_at', from.toUtc().toIso8601String());
    }
    if (to != null) {
      query = query.lt('created_at', to.toUtc().toIso8601String());
    }
    query = query.order('created_at', ascending: false);
    if (limit != null) query = query.limit(limit);
    final rows = await query;
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> availableDeliveries() async {
    final rows = await supabase
        .from('delivery_requests')
        .select()
        .eq('status', 'searching')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> claimDelivery(String deliveryId) async {
    await supabase.rpc('claim_delivery', params: {
      'p_delivery_id': deliveryId,
    });
  }

  Future<void> advanceDelivery(String deliveryId, String status) async {
    await supabase.rpc('advance_delivery', params: {
      'p_delivery_id': deliveryId,
      'p_status': status,
    });
  }

  Future<void> cancelDelivery(String deliveryId, {String? reason}) async {
    await supabase.rpc('cancel_delivery', params: {
      'p_delivery_id': deliveryId,
      'p_reason': reason,
    });
  }

  Future<List<Map<String, dynamic>>> deliveryHistory(String deliveryId) async {
    final rows = await supabase
        .from('delivery_status_history')
        .select()
        .eq('delivery_id', deliveryId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> submitRating({
    String? tripId,
    String? deliveryId,
    required String toUserId,
    required int score,
    String? comment,
  }) async {
    if (toUserId == userId) return;
    if ((tripId == null || tripId.isEmpty) &&
        (deliveryId == null || deliveryId.isEmpty)) {
      throw StateError('No se encontró el servicio a calificar.');
    }

    final settings = await appSettings(forceRefresh: true);
    if (settings['ratings_enabled'] == false) {
      throw StateError('Las calificaciones están desactivadas.');
    }
    final minScore = ((settings['rating_min'] as num?)?.toInt() ?? 1)
        .clamp(1, 5)
        .toInt();
    final maxScore = ((settings['rating_max'] as num?)?.toInt() ?? 5)
        .clamp(minScore, 5)
        .toInt();
    if (score < minScore || score > maxScore) {
      throw StateError(
        'La calificación debe estar entre $minScore y $maxScore.',
      );
    }

    // Idempotencia: si este usuario ya calificó este servicio, consideramos
    // la operación completada. Así un refresh/reintento no vuelve a mostrar
    // la tarjeta ni expone un error de índice único al usuario.
    if (await _ratingAlreadyExists(
      tripId: tripId,
      deliveryId: deliveryId,
    )) {
      return;
    }

    try {
      await supabase.from('ratings').insert({
        'trip_id': tripId,
        'delivery_id': deliveryId,
        'from_user_id': userId,
        'to_user_id': toUserId,
        'score': score,
        'comment':
            settings['rating_comment_enabled'] == false ? null : comment,
      });
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        // Otro intento ya insertó la misma calificación. El resultado final
        // deseado ya existe, por lo que el envío se considera exitoso.
        return;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> myRatingSummary() async {
    final raw = await supabase.rpc('my_rating_summary');
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{
      'count': 0,
      'average': 0,
      'five': 0,
      'four': 0,
      'three': 0,
      'two': 0,
      'one': 0,
    };
  }

  Future<void> createPayment({
    String? tripId,
    String? deliveryId,
    String? payeeId,
    required String method,
    required num amount,
  }) async {
    await supabase.from('payment_transactions').insert({
      'payer_id': userId,
      'payee_id': payeeId,
      'trip_id': tripId,
      'delivery_id': deliveryId,
      'method': method,
      'amount': amount,
      'currency': 'BOB',
      'status': method == 'cash' ? 'pending' : 'pending',
    });
  }

  Future<List<Map<String, dynamic>>> myPayments() async {
    final rows = await supabase
        .from('payment_transactions')
        .select()
        .or('payer_id.eq.$userId,payee_id.eq.$userId')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> myWallet() async {
    final row = await supabase.rpc('ensure_wallet');
    return Map<String, dynamic>.from(row as Map);
  }

  Future<Map<String, dynamic>> _fetchAndCacheRuntimeConfig() {
    final existing = _runtimeConfigRefresh;
    if (existing != null) return existing;

    final future = (() async {
      final value = await supabase.rpc('app_runtime_config');
      final config = value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
      await LocalJsonCache.write('runtime_config_v1', config);
      return config;
    })();

    _runtimeConfigRefresh = future;
    future.whenComplete(() {
      if (identical(_runtimeConfigRefresh, future)) {
        _runtimeConfigRefresh = null;
      }
    });
    return future;
  }

  Future<Map<String, dynamic>> runtimeConfig({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await LocalJsonCache.read('runtime_config_v1');
      if (cached?.value is Map) {
        final age = cached!.age(DateTime.now().toUtc());
        if (age <= _configUsableFor) {
          final value = Map<String, dynamic>.from(cached.value as Map);
          if (age > _configFreshFor) {
            unawaited(_fetchAndCacheRuntimeConfig());
          }
          return value;
        }
      }
    }
    return _fetchAndCacheRuntimeConfig();
  }

  Future<List<Map<String, dynamic>>> _fetchAndCacheServiceCatalog(
    String audience,
  ) {
    final existing = _serviceCatalogRefreshes[audience];
    if (existing != null) return existing;

    final future = (() async {
      try {
        final raw = await supabase.rpc(
          'app_service_catalog',
          params: {'p_for': audience},
        );
        if (raw is List) {
          final rows = raw
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          await LocalJsonCache.write(
            'service_catalog_v1_$audience',
            rows,
          );
          return rows;
        }
      } catch (_) {
        // Compatibilidad con backend anterior al catálogo por audiencia.
      }

      final config = await runtimeConfig(forceRefresh: true);
      final raw = config['services'];
      final rows = raw is List
          ? raw
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      await LocalJsonCache.write('service_catalog_v1_$audience', rows);
      return rows;
    })();

    _serviceCatalogRefreshes[audience] = future;
    future.whenComplete(() {
      if (identical(_serviceCatalogRefreshes[audience], future)) {
        _serviceCatalogRefreshes.remove(audience);
      }
    });
    return future;
  }

  Future<List<Map<String, dynamic>>> serviceCatalog({
    String audience = 'passenger',
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached =
          await LocalJsonCache.read('service_catalog_v1_$audience');
      if (cached?.value is List) {
        final age = cached!.age(DateTime.now().toUtc());
        if (age <= _configUsableFor) {
          final rows = (cached.value as List)
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          if (age > _configFreshFor) {
            unawaited(_fetchAndCacheServiceCatalog(audience));
          }
          return rows;
        }
      }
    }
    return _fetchAndCacheServiceCatalog(audience);
  }

  Future<Map<String, dynamic>> zoneContext({
    required double latitude,
    required double longitude,
    String audience = 'passenger',
  }) async {
    final value = await supabase.rpc(
      'app_zone_context',
      params: {
        'p_lat': latitude,
        'p_lng': longitude,
        'p_for': audience,
      },
    );

    // Mantener la última zona conocida del usuario permite segmentar
    // promociones/avisos por ciudad sin depender del modo conductor.
    unawaited(() async {
      try {
        await supabase.rpc(
          'set_my_zone_from_location',
          params: {
            'p_lat': latitude,
            'p_lng': longitude,
          },
        );
      } catch (_) {
        // La geolocalización operativa no debe fallar si la persistencia
        // auxiliar de la zona no está disponible temporalmente.
      }
    }());

    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{
      'inside_coverage': false,
      'zone': null,
      'services': const <Map<String, dynamic>>[],
      'subscription': null,
    };
  }

  Future<List<Map<String, dynamic>>> serviceCatalogForLocation({
    required double latitude,
    required double longitude,
    String audience = 'passenger',
  }) async {
    final context = await zoneContext(
      latitude: latitude,
      longitude: longitude,
      audience: audience,
    );
    final raw = context['services'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> quoteServiceFareForLocation({
    required String serviceKey,
    required num distanceKm,
    required int durationMinutes,
    required double latitude,
    required double longitude,
  }) async {
    final value = await supabase.rpc(
      'quote_service_fare_for_location',
      params: {
        'p_service_key': serviceKey,
        'p_distance_km': distanceKm,
        'p_duration_minutes': durationMinutes,
        'p_lat': latitude,
        'p_lng': longitude,
      },
    );
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> specialFareForRoute({
    required String serviceKey,
    required double pickupLatitude,
    required double pickupLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) async {
    final value = await supabase.rpc(
      'special_fare_for_my_route',
      params: {
        'p_service_key': serviceKey,
        'p_pickup_lat': pickupLatitude,
        'p_pickup_lng': pickupLongitude,
        'p_destination_lat': destinationLatitude,
        'p_destination_lng': destinationLongitude,
      },
    );
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{'matched': false};
  }

  Future<Map<String, dynamic>> driverSubscriptionCatalog() async {
    final value = await supabase.rpc('driver_subscription_catalog_for_me');
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> driverSubscriptionState() async {
    final value = await supabase.rpc('my_driver_subscription_state');
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> payDriverSubscriptionWithWallet(
    int planId,
  ) async {
    final value = await supabase.rpc(
      'pay_driver_subscription_with_wallet',
      params: {'p_plan_id': planId},
    );
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> activeSecurityZones({
    bool forceRefresh = false,
  }) async {
    try {
      final config = await runtimeConfig(forceRefresh: forceRefresh);
      final raw = config['security_zones'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      }
    } catch (_) {}
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> geoPolicy({
    required double latitude,
    required double longitude,
    String audience = 'passenger',
  }) async {
    final value = await supabase.rpc(
      'app_geo_policy',
      params: {
        'p_lat': latitude,
        'p_lng': longitude,
        'p_for': audience,
      },
    );
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{
      'coverage_enforced': false,
      'inside_coverage': true,
      'security_zones': const <Map<String, dynamic>>[],
    };
  }


  Future<Map<String, dynamic>> appSettings({
    bool forceRefresh = false,
  }) async {
    try {
      final config = await runtimeConfig(forceRefresh: forceRefresh);
      final settings = config['settings'];
      if (settings is Map) {
        return Map<String, dynamic>.from(settings);
      }
    } catch (_) {}

    final row = await supabase
        .from('app_settings')
        .select()
        .eq('id', true)
        .maybeSingle();
    if (row == null) {
      return <String, dynamic>{
        'currency': 'BOB',
        'commission_percent': 0,
        'allow_cash': true,
        'allow_card': false,
        'allow_wallet': false,
      };
    }
    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> walletTransactions() async {
    final rows = await supabase
        .from('wallet_transactions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<String> requestWalletTopup(num amount) async {
    final result = await supabase.rpc(
      'request_wallet_topup',
      params: {'p_amount': amount},
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> walletTopupRequests() async {
    final rows = await supabase
        .from('wallet_topup_requests')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> supportMessages() async {
    final rows = await supabase
        .from('support_messages')
        .select()
        .eq('user_id', userId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> sendSupportMessage(String body) async {
    final text = body.trim();
    if (text.isEmpty) return;
    await supabase.from('support_messages').insert({
      'user_id': userId,
      'sender_id': userId,
      'sender_role': 'user',
      'body': text,
      'read_by_user': true,
      'read_by_admin': false,
    });
  }

  Future<List<Map<String, dynamic>>> messages({
    String? tripId,
    String? deliveryId,
  }) async {
    var query = supabase.from('service_messages').select();
    if (tripId != null) query = query.eq('trip_id', tripId);
    if (deliveryId != null) query = query.eq('delivery_id', deliveryId);
    final rows = await query.order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> sendMessage({
    String? tripId,
    String? deliveryId,
    required String body,
  }) async {
    await supabase.from('service_messages').insert({
      'trip_id': tripId,
      'delivery_id': deliveryId,
      'sender_id': userId,
      'body': body.trim(),
    });
  }

  Future<List<Map<String, dynamic>>> savedAddresses() async {
    final rows = await supabase
        .from('saved_addresses')
        .select()
        .eq('user_id', userId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> addSavedAddress({
    required String label,
    required String address,
    double? latitude,
    double? longitude,
  }) async {
    await supabase.from('saved_addresses').insert({
      'user_id': userId,
      'label': label,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  Future<void> deleteSavedAddress(String addressId) async {
    await supabase
        .from('saved_addresses')
        .delete()
        .eq('id', addressId)
        .eq('user_id', userId);
  }

  Future<List<Map<String, dynamic>>> trustedContacts() async {
    final rows = await supabase
        .from('trusted_contacts')
        .select()
        .eq('user_id', userId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> addTrustedContact({required String name, required String phone}) async {
    await supabase.from('trusted_contacts').insert({
      'user_id': userId,
      'name': name,
      'phone': phone,
    });
  }

  Future<void> createEmergency({
    String? tripId,
    String? deliveryId,
    double? latitude,
    double? longitude,
  }) async {
    await supabase.rpc('raise_emergency', params: {
      'p_trip_id': tripId,
      'p_delivery_id': deliveryId,
      'p_latitude': latitude,
      'p_longitude': longitude,
    });
  }

  Future<Map<String, dynamic>> deleteMyAccount() async {
    final result = await supabase.rpc('delete_my_account');
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return <String, dynamic>{'deleted': result == true};
  }

  Future<List<Map<String, dynamic>>> myNotifications() async {
    final rows = await supabase
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .eq('type', 'admin_announcement')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }
}
