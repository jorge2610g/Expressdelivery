update private.driver_subscription_provider_settings
set api_base_url='https://veripagos.com',
    create_path='/api/bcp/generar-qr',
    status_path='/api/bcp/verificar-estado-qr',
    updated_at=now()
where id=true;