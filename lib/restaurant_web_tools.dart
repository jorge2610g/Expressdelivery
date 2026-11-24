// Herramientas del navegador para el portal de restaurantes (sonido, descarga de
// archivos e impresión). En plataformas sin navegador no hacen nada.
export 'restaurant_web_tools_stub.dart'
    if (dart.library.html) 'restaurant_web_tools_web.dart';
