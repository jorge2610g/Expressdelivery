import '../core/supabase_client.dart';

class ExpressService {
  static Map<String, dynamic>? _preloadedPassengerHomeState;
  static String? _preloadedPassengerUserId;

  String get userId {
    final id = supabase.auth.currentUser?.id;
    if (id == null) throw StateError('Sesión no disponible.');
    return id;
  }

  Future<Map<String, dynamic>> _fetchPassengerHomeState() async {
    await supabase.rpc('cleanup_expired_ride_offers');
    final row = await supabase.rpc('passenger_home_state');
    return Map<String, dynamic>.from(row as Map);
  }

  Future<Map<String, dynamic>> preloadPassengerHomeState() async {
    final state = await _fetchPassengerHomeState();
    _preloadedPassengerUserId = userId;
    _preloadedPassengerHomeState = Map<String, dynamic>.from(state);
    return state;
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
  }) async {
    final row = await supabase.rpc(
      'quote_service_fare',
      params: {
        'p_service_key': serviceKey,
        'p_distance_km': distanceKm,
        'p_duration_minutes': durationMinutes,
      },
    );
    return Map<String, dynamic>.from(row as Map);
  }

  Future<Map<String, dynamic>?> pendingRatingService() async {
    final row = await supabase.rpc('pending_rating_service');
    if (row == null) return null;
    final pending = Map<String, dynamic>.from(row as Map);

    // Durante pruebas una misma cuenta puede alternar Pasajero/Conductor.
    // No se debe intentar calificar a la propia cuenta porque RLS lo prohíbe.
    if (pending['to_user_id']?.toString() == userId) return null;

    return pending;
  }


  Future<Map<String, dynamic>?> myUser() async {
    final row = await supabase
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row != null) {
      return Map<String, dynamic>.from(row);
    }

    final repaired = await supabase.rpc('ensure_my_profile');
    if (repaired == null) return null;
    return Map<String, dynamic>.from(repaired as Map);
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
  }

  Future<void> setActiveMode(String mode) async {
    await supabase.from('users').update({
      'active_mode': mode,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);
  }

  Future<Map<String, dynamic>?> myDriverProfile() async {
    final row = await supabase
        .from('driver_profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> ensureDriverProfile() async {
    final current = await myDriverProfile();
    if (current != null) return current;
    final row = await supabase.from('driver_profiles').insert({
      'id': userId,
      'approval_status': 'pending',
      'online_status': 'offline',
    }).select().single();
    return Map<String, dynamic>.from(row);
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
  }

  Future<void> updateDriverDetails({
    String? licenseNumber,
    String? vehicleSummary,
    String? city,
    double? latitude,
    double? longitude,
  }) async {
    await ensureDriverProfile();
    await supabase.from('driver_profiles').update({
      if (licenseNumber != null) 'license_number': licenseNumber,
      if (vehicleSummary != null) 'vehicle_summary': vehicleSummary,
      if (city != null) 'city': city,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);
  }

  Future<List<Map<String, dynamic>>> myVehicles() async {
    final rows = await supabase
        .from('driver_vehicles')
        .select()
        .eq('driver_id', userId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
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
  }) async {
    final expiresAt = scheduledFor == null
        ? DateTime.now().toUtc().add(const Duration(minutes: 3))
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
      'currency': 'BOB',
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

  Future<List<Map<String, dynamic>>> myRideRequests() async {
    final rows = await supabase
        .from('ride_requests')
        .select()
        .eq('passenger_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> availableRideRequests() async {
    try {
      await supabase.rpc('cleanup_expired_ride_requests');
    } catch (_) {}

    final raw = await supabase.rpc('available_ride_requests_for_driver');
    final rows = raw is List
        ? List<Map<String, dynamic>>.from(
            raw.map((row) => Map<String, dynamic>.from(row as Map)),
          )
        : <Map<String, dynamic>>[];

    String? vehicleType;
    try {
      final vehicles = await myVehicles();
      if (vehicles.isNotEmpty) {
        final active = vehicles.firstWhere(
          (row) => row['is_active'] == true,
          orElse: () => vehicles.first,
        );
        final stored = active['vehicle_type']?.toString().trim();
        if (stored != null && stored.isNotEmpty) vehicleType = stored;
      }
    } catch (_) {}

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
    final row = await supabase.from('driver_offers').upsert({
      'ride_request_id': rideRequestId,
      'driver_id': userId,
      'proposed_fare': fare,
      'eta_minutes': etaMinutes,
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 20))
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

  Future<List<Map<String, dynamic>>> myTrips() async {
    final rows = await supabase
        .from('trips')
        .select('*,ride_requests(*)')
        .or('passenger_id.eq.$userId,driver_id.eq.$userId')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
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

  Future<List<Map<String, dynamic>>> myDeliveries() async {
    final rows = await supabase
        .from('delivery_requests')
        .select()
        .or('customer_id.eq.$userId,courier_id.eq.$userId')
        .order('created_at', ascending: false);
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
    await supabase.from('ratings').insert({
      'trip_id': tripId,
      'delivery_id': deliveryId,
      'from_user_id': userId,
      'to_user_id': toUserId,
      'score': score,
      'comment': comment,
    });
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

  Future<List<Map<String, dynamic>>> walletTransactions() async {
    final rows = await supabase
        .from('wallet_transactions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
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

  Future<List<Map<String, dynamic>>> myNotifications() async {
    final rows = await supabase
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }
}
