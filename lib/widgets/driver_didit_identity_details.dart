import 'package:flutter/material.dart';

/// Read-only summary of the limited identity fields returned by Didit.
/// Do not add address, marital status, birthplace, raw photos or video here.
class DriverDiditIdentityDetails extends StatelessWidget {
  const DriverDiditIdentityDetails({super.key, required this.verification});

  final Map<String, dynamic> verification;

  Map<String, dynamic> _asMap(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _date(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return 'No informado · revisión pendiente';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final date = parsed.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _gender(String value) {
    switch (value.trim().toLowerCase()) {
      case 'm':
      case 'male':
      case 'masculino':
        return 'Masculino';
      case 'f':
      case 'female':
      case 'femenino':
        return 'Femenino';
      default:
        return value.isEmpty ? 'No informado' : value;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_text(verification['status']).toLowerCase() != 'verified') {
      return const SizedBox.shrink();
    }

    final result = _asMap(verification['result']);
    final identity = _asMap(result['identity']);
    final fullName = _text(identity['full_name']).isNotEmpty
        ? _text(identity['full_name'])
        : <String>[
            _text(identity['first_name']),
            _text(identity['last_name']),
          ].where((part) => part.isNotEmpty).join(' ');
    final number = _text(identity['document_number']).isNotEmpty
        ? _text(identity['document_number'])
        : _text(identity['personal_number']);


    final fields = <(String, String)>[
      ('Nombre completo', fullName),
      ('Número de documento', number),
      ('Tipo de documento', _text(result['document_type'])),
      ('Nacionalidad', _text(identity['nationality'])),
      ('Fecha de nacimiento', _date(identity['date_of_birth'])),
      ('Fecha de emisión', _date(identity['date_of_issue'])),
      ('Fecha de vencimiento', _date(identity['expiration_date'])),
      ('Género', _gender(_text(identity['gender']))),
    ];

    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Datos verificados con Didit',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Estos datos se obtuvieron automáticamente del documento. '
            'No necesitas ingresarlos de nuevo.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          for (final field in fields) ...[
            Divider(color: scheme.outlineVariant, height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 138,
                  child: Text(
                    field.$1,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    field.$2.isEmpty ? 'No informado' : field.$2,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
