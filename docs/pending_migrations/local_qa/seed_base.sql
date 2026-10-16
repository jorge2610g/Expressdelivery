-- Datos sintéticos. Un pasajero y dos conductores de auditoría ficticios, en un grupo de prueba.
insert into public.users(id, full_name) values
 ('aaaaaaaa-0000-4000-8000-000000000001','Pasajero sintético'),
 ('bbbbbbbb-0000-4000-8000-000000000001','Conductor sintético 1'),
 ('bbbbbbbb-0000-4000-8000-000000000002','Conductor sintético 2');
insert into public.driver_profiles(id) values
 ('bbbbbbbb-0000-4000-8000-000000000001'),('bbbbbbbb-0000-4000-8000-000000000002');
insert into public.audit_test_groups(id,name,slug,active) values
 ('cccccccc-0000-4000-8000-000000000001','Grupo sintético local','local-synthetic',true);
insert into public.audit_test_group_members(group_id,user_id,role,enabled) values
 ('cccccccc-0000-4000-8000-000000000001','aaaaaaaa-0000-4000-8000-000000000001','passenger',true),
 ('cccccccc-0000-4000-8000-000000000001','bbbbbbbb-0000-4000-8000-000000000001','driver',true),
 ('cccccccc-0000-4000-8000-000000000001','bbbbbbbb-0000-4000-8000-000000000002','driver',true);
