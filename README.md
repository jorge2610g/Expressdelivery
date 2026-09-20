# Express Delivery

Aplicación multiplataforma desarrollada con Flutter.

## Objetivo

Este repositorio será la fuente principal del proyecto. La misma base de código podrá utilizarse para:

- Android / APK
- Web
- iOS, si posteriormente se requiere

## Desarrollo local

Instala Flutter y ejecuta:

```bash
flutter pub get
flutter run -d chrome
```

Para preparar Android posteriormente:

```bash
flutter create .
flutter pub get
flutter run
```

Para generar el APK:

```bash
flutter build apk --release
```

Para generar la versión web:

```bash
flutter build web --release
```

El proyecto irá creciendo por etapas con las funcionalidades de Express Delivery.
