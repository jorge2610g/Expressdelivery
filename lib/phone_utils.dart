const Map<String, String> expressPhoneDialCodes = {
  'CL': '+56',
  'BO': '+591',
};

String expressPhoneCountryFromNumber(String? phone) {
  final value = (phone ?? '').trim().replaceAll(RegExp(r'[\s()-]'), '');
  if (value.startsWith('+591')) return 'BO';
  if (value.startsWith('+56')) return 'CL';
  return 'CL';
}

String expressPhoneDialCode(String countryCode) =>
    expressPhoneDialCodes[countryCode.toUpperCase()] ?? '+56';

String expressNormalizePhone(String countryCode, String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  final dialDigits =
      expressPhoneDialCode(countryCode).replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith(dialDigits)) {
    digits = digits.substring(dialDigits.length);
  }
  while (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return expressPhoneDialCode(countryCode) + digits;
}

String expressLocalPhone(String? phone) {
  final country = expressPhoneCountryFromNumber(phone);
  final dial = expressPhoneDialCode(country);
  final value = (phone ?? '').trim().replaceAll(RegExp(r'[\s()-]'), '');
  return value.startsWith(dial) ? value.substring(dial.length) : value;
}
