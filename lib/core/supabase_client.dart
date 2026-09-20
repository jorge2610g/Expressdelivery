import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://cdgemtkumzxlbhdgxlwn.supabase.co';
const supabasePublishableKey = 'sb_publishable_j7QozgTeNDz7jHch6W0XKg_VgSsvxXq';

SupabaseClient get supabase => Supabase.instance.client;
