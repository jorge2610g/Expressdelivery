import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/email_typo_guard.dart';

void main() {
  test('sugiere el dominio correcto para errores comunes', () {
    expect(EmailTypoGuard.suggestion('ana@gmial.com'), 'ana@gmail.com');
    expect(EmailTypoGuard.suggestion('ana@gmail.con'), 'ana@gmail.com');
    expect(EmailTypoGuard.suggestion('ana@gmai.com'), 'ana@gmail.com');
    expect(EmailTypoGuard.suggestion('Ana@Hotmal.com '), 'ana@hotmail.com');
    expect(EmailTypoGuard.suggestion('ana@outlok.com'), 'ana@outlook.com');
  });

  test('no toca dominios correctos ni desconocidos', () {
    expect(EmailTypoGuard.suggestion('ana@gmail.com'), isNull);
    expect(EmailTypoGuard.suggestion('ana@expressviajes.online'), isNull);
    expect(EmailTypoGuard.suggestion('ana@empresa.com.bo'), isNull);
  });

  test('valida el formato', () {
    expect(EmailTypoGuard.isValidFormat(' ana.perez@gmail.com '), isTrue);
    expect(EmailTypoGuard.isValidFormat('ana@gmail'), isFalse);
    expect(EmailTypoGuard.isValidFormat('ana gmail.com'), isFalse);
    expect(EmailTypoGuard.isValidFormat('ana@@gmail.com'), isFalse);
    expect(EmailTypoGuard.isValidFormat('ana..p@gmail.com'), isFalse);
  });
}
