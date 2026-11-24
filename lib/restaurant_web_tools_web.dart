import 'dart:html' as html;
import 'dart:js' as js;

/// Aviso sonoro corto (dos tonos). Algunos navegadores solo permiten sonido después
/// de que la persona toque la página una vez.
void restaurantBeep() {
  try {
    final ctor = js.context['AudioContext'] ?? js.context['webkitAudioContext'];
    if (ctor == null) return;
    final ctx = js.JsObject(ctor as js.JsFunction);
    void tone(double freq, double start, double length) {
      final osc = ctx.callMethod('createOscillator') as js.JsObject;
      final gain = ctx.callMethod('createGain') as js.JsObject;
      osc['type'] = 'sine';
      (osc['frequency'] as js.JsObject)['value'] = freq;
      (gain['gain'] as js.JsObject)['value'] = 0.25;
      osc.callMethod('connect', [gain]);
      gain.callMethod('connect', [ctx['destination']]);
      final now = (ctx['currentTime'] as num).toDouble();
      osc.callMethod('start', [now + start]);
      osc.callMethod('stop', [now + start + length]);
    }

    tone(880, 0, 0.18);
    tone(1175, 0.22, 0.28);
  } catch (_) {}
}

void restaurantDownloadText(String filename, String text,
    {String mime = 'text/csv;charset=utf-8'}) {
  try {
    // BOM para que Excel lea bien las tildes.
    final blob = html.Blob(['﻿$text'], mime);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final a = html.AnchorElement(href: url)..download = filename;
    html.document.body?.append(a);
    a.click();
    a.remove();
    html.Url.revokeObjectUrl(url);
  } catch (_) {}
}

void restaurantPrintHtml(String htmlText) {
  try {
    final frame = html.IFrameElement()
      ..style.position = 'fixed'
      ..style.width = '0'
      ..style.height = '0'
      ..style.border = '0'
      ..srcdoc = htmlText;
    html.document.body?.append(frame);
    frame.onLoad.first.then((_) {
      try {
        final window = js.JsObject.fromBrowserObject(frame)['contentWindow'];
        (window as js.JsObject).callMethod('print');
      } catch (_) {}
      Future<void>.delayed(const Duration(seconds: 30), frame.remove);
    });
  } catch (_) {}
}
