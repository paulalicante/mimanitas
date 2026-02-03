/// Validators for Spanish identification documents and bank accounts.
/// Used for tax compliance (DAC7/Modelo 238) and SEPA payments.
class SpanishValidators {
  /// Control letter lookup table for DNI/NIE validation
  static const String _controlLetters = 'TRWAGMYFPDXBNJZSQVHLCKE';

  /// Validates a Spanish DNI (Documento Nacional de Identidad)
  /// Format: 8 digits + 1 control letter (e.g., 12345678Z)
  ///
  /// The control letter is calculated as: number % 23 → lookup in letter table
  static ValidationResult validateDNI(String dni) {
    if (dni.isEmpty) {
      return ValidationResult(false, 'El DNI es obligatorio');
    }

    // Clean input: remove spaces and convert to uppercase
    final cleaned = dni.replaceAll(' ', '').toUpperCase();

    // Check format: exactly 8 digits followed by 1 letter
    final dniRegex = RegExp(r'^[0-9]{8}[A-Z]$');
    if (!dniRegex.hasMatch(cleaned)) {
      return ValidationResult(
        false,
        'Formato inválido. El DNI debe tener 8 números y una letra (ej: 12345678Z)',
      );
    }

    // Extract number and letter
    final number = int.parse(cleaned.substring(0, 8));
    final letter = cleaned[8];

    // Calculate expected control letter
    final expectedLetter = _controlLetters[number % 23];

    if (letter != expectedLetter) {
      return ValidationResult(
        false,
        'La letra de control no es correcta',
      );
    }

    return ValidationResult(true, null, cleaned);
  }

  /// Validates a Spanish NIE (Número de Identidad de Extranjero)
  /// Format: X/Y/Z + 7 digits + 1 control letter (e.g., X1234567L)
  ///
  /// For validation, the initial letter is converted:
  /// X → 0, Y → 1, Z → 2, then validated like a DNI
  static ValidationResult validateNIE(String nie) {
    if (nie.isEmpty) {
      return ValidationResult(false, 'El NIE es obligatorio');
    }

    // Clean input: remove spaces and convert to uppercase
    final cleaned = nie.replaceAll(' ', '').toUpperCase();

    // Check format: X/Y/Z followed by 7 digits and 1 letter
    final nieRegex = RegExp(r'^[XYZ][0-9]{7}[A-Z]$');
    if (!nieRegex.hasMatch(cleaned)) {
      return ValidationResult(
        false,
        'Formato inválido. El NIE debe empezar con X, Y o Z, seguido de 7 números y una letra (ej: X1234567L)',
      );
    }

    // Convert first letter to number for validation
    String converted = cleaned;
    converted = converted.replaceFirst('X', '0');
    converted = converted.replaceFirst('Y', '1');
    converted = converted.replaceFirst('Z', '2');

    // Now validate like a DNI
    final number = int.parse(converted.substring(0, 8));
    final letter = cleaned[8];
    final expectedLetter = _controlLetters[number % 23];

    if (letter != expectedLetter) {
      return ValidationResult(
        false,
        'La letra de control no es correcta',
      );
    }

    return ValidationResult(true, null, cleaned);
  }

  /// Validates either a DNI or NIE
  /// Automatically detects which type based on the first character
  static ValidationResult validateDNIorNIE(String value) {
    if (value.isEmpty) {
      return ValidationResult(false, 'El DNI/NIE es obligatorio');
    }

    final cleaned = value.replaceAll(' ', '').toUpperCase();

    // Check if it starts with X, Y, or Z (NIE) or a digit (DNI)
    if (cleaned.isNotEmpty && 'XYZ'.contains(cleaned[0])) {
      return validateNIE(cleaned);
    } else {
      return validateDNI(cleaned);
    }
  }

  /// Validates a Spanish IBAN
  /// Format: ES + 2 check digits + 20 digits (total 24 characters)
  /// Example: ES9121000418450200051332
  ///
  /// Validation uses ISO 13616 mod-97 algorithm
  static ValidationResult validateSpanishIBAN(String iban) {
    if (iban.isEmpty) {
      return ValidationResult(false, 'El IBAN es obligatorio');
    }

    // Clean input: remove spaces and convert to uppercase
    final cleaned = iban.replaceAll(' ', '').replaceAll('-', '').toUpperCase();

    // Check country code
    if (!cleaned.startsWith('ES')) {
      return ValidationResult(
        false,
        'El IBAN debe ser español (empezar con ES)',
      );
    }

    // Check length (ES = 24 characters)
    if (cleaned.length != 24) {
      return ValidationResult(
        false,
        'El IBAN español debe tener 24 caracteres',
      );
    }

    // Check format: ES + 2 digits + 20 digits
    final ibanRegex = RegExp(r'^ES[0-9]{22}$');
    if (!ibanRegex.hasMatch(cleaned)) {
      return ValidationResult(
        false,
        'Formato inválido. Solo debe contener números después de ES',
      );
    }

    // IBAN mod-97 validation (ISO 13616)
    // 1. Move first 4 characters to end
    final rearranged = cleaned.substring(4) + cleaned.substring(0, 4);

    // 2. Convert letters to numbers (A=10, B=11, ..., Z=35)
    final numericString = rearranged.split('').map((char) {
      final code = char.codeUnitAt(0);
      if (code >= 65 && code <= 90) {
        // A-Z
        return (code - 55).toString();
      }
      return char;
    }).join();

    // 3. Calculate mod 97 (using BigInt for large numbers)
    final remainder = BigInt.parse(numericString) % BigInt.from(97);

    if (remainder != BigInt.one) {
      return ValidationResult(
        false,
        'El IBAN no es válido (dígitos de control incorrectos)',
      );
    }

    // Format nicely for storage/display
    final formatted = '${cleaned.substring(0, 4)} ${cleaned.substring(4, 8)} '
        '${cleaned.substring(8, 12)} ${cleaned.substring(12, 16)} '
        '${cleaned.substring(16, 20)} ${cleaned.substring(20, 24)}';

    return ValidationResult(true, null, cleaned, formatted);
  }

  /// Validates any IBAN (not just Spanish)
  /// Useful if you want to support other EU countries in the future
  static ValidationResult validateIBAN(String iban) {
    if (iban.isEmpty) {
      return ValidationResult(false, 'El IBAN es obligatorio');
    }

    final cleaned = iban.replaceAll(' ', '').replaceAll('-', '').toUpperCase();

    // Basic format check: 2 letters + 2 digits + up to 30 alphanumeric
    final ibanRegex = RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]{1,30}$');
    if (!ibanRegex.hasMatch(cleaned)) {
      return ValidationResult(false, 'Formato de IBAN inválido');
    }

    // IBAN length by country (common ones)
    final ibanLengths = {
      'ES': 24, // Spain
      'PT': 25, // Portugal
      'FR': 27, // France
      'DE': 22, // Germany
      'IT': 27, // Italy
      'GB': 22, // UK (legacy)
      'NL': 18, // Netherlands
      'BE': 16, // Belgium
    };

    final countryCode = cleaned.substring(0, 2);
    final expectedLength = ibanLengths[countryCode];

    if (expectedLength != null && cleaned.length != expectedLength) {
      return ValidationResult(
        false,
        'El IBAN de $countryCode debe tener $expectedLength caracteres',
      );
    }

    // Mod-97 validation
    final rearranged = cleaned.substring(4) + cleaned.substring(0, 4);
    final numericString = rearranged.split('').map((char) {
      final code = char.codeUnitAt(0);
      if (code >= 65 && code <= 90) {
        return (code - 55).toString();
      }
      return char;
    }).join();

    final remainder = BigInt.parse(numericString) % BigInt.from(97);

    if (remainder != BigInt.one) {
      return ValidationResult(false, 'El IBAN no es válido');
    }

    return ValidationResult(true, null, cleaned);
  }

  /// Validates a Spanish phone number
  /// Accepts formats: +34 612345678, 612345678, 0034612345678
  static ValidationResult validateSpanishPhone(String phone) {
    if (phone.isEmpty) {
      return ValidationResult(false, 'El teléfono es obligatorio');
    }

    // Clean: remove spaces, dashes, parentheses
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Remove country code variations
    if (cleaned.startsWith('+34')) {
      cleaned = cleaned.substring(3);
    } else if (cleaned.startsWith('0034')) {
      cleaned = cleaned.substring(4);
    } else if (cleaned.startsWith('34') && cleaned.length == 11) {
      cleaned = cleaned.substring(2);
    }

    // Spanish mobile numbers start with 6 or 7, landlines with 9
    final phoneRegex = RegExp(r'^[679][0-9]{8}$');
    if (!phoneRegex.hasMatch(cleaned)) {
      return ValidationResult(
        false,
        'Número de teléfono español inválido',
      );
    }

    // Return with +34 prefix for storage
    return ValidationResult(true, null, '+34$cleaned');
  }

  /// Validates a Spanish postal code
  /// Format: 5 digits, ranging from 01001 to 52999
  static ValidationResult validateSpanishPostalCode(String postalCode) {
    if (postalCode.isEmpty) {
      return ValidationResult(false, 'El código postal es obligatorio');
    }

    final cleaned = postalCode.replaceAll(' ', '');

    // Must be exactly 5 digits
    if (!RegExp(r'^[0-9]{5}$').hasMatch(cleaned)) {
      return ValidationResult(
        false,
        'El código postal debe tener 5 dígitos',
      );
    }

    // Valid range: 01001 - 52999 (Spanish provinces)
    final number = int.parse(cleaned);
    if (number < 1001 || number > 52999) {
      return ValidationResult(
        false,
        'Código postal fuera de rango válido',
      );
    }

    return ValidationResult(true, null, cleaned);
  }
}

/// Result of a validation operation
class ValidationResult {
  /// Whether the validation passed
  final bool isValid;

  /// Error message if validation failed (null if valid)
  final String? errorMessage;

  /// Cleaned/normalized value (null if invalid)
  final String? cleanedValue;

  /// Formatted value for display (optional)
  final String? formattedValue;

  ValidationResult(
    this.isValid,
    this.errorMessage, [
    this.cleanedValue,
    this.formattedValue,
  ]);

  @override
  String toString() {
    if (isValid) {
      return 'Valid: $cleanedValue';
    }
    return 'Invalid: $errorMessage';
  }
}
