/// Deterministic quantity conversion using decimal string parsing and integer arithmetic.
///
/// Converts human-readable decimal quantities to base-unit integers without
/// floating-point arithmetic, ensuring precision and predictability.
class QuantityConverter {
  static const Map<String, int> unitMultipliers = {
    'litre': 1000,
    'kg': 1000,
    'gram': 1,
    'piece': 1,
    'packet': 1,
  };

  /// Converts a human-readable decimal string to an integer base-unit quantity.
  ///
  /// Examples:
  /// - toIntQuantity('2', 'litre') → 2000
  /// - toIntQuantity('0.5', 'litre') → 500
  /// - toIntQuantity('1.25', 'litre') → 1250
  /// - toIntQuantity('1.250', 'litre') → 1250
  /// - toIntQuantity('2', 'piece') → 2
  ///
  /// Throws [FormatException] if the input is invalid:
  /// - Empty string
  /// - Not a valid decimal number
  /// - Zero
  /// - Negative
  /// - Precision smaller than the base unit (e.g., 0.0001 for litre with 1000 multiplier)
  static int toIntQuantity(String humanReadable, String unit) {
    final trimmed = humanReadable.trim();

    if (trimmed.isEmpty) {
      throw FormatException('Quantity cannot be empty.');
    }

    final multiplier = unitMultipliers[unit] ?? 1;

    // Parse the decimal string
    final parts = trimmed.split('.');
    if (parts.length > 2 ||
        (parts.length == 2 && parts[1].isEmpty) ||
        parts.any((p) => p.isEmpty)) {
      throw FormatException('Invalid decimal number: $humanReadable');
    }

    final intPart = int.tryParse(parts[0]);
    if (intPart == null) {
      throw FormatException('Invalid integer part: $humanReadable');
    }

    if (intPart < 0) {
      throw FormatException('Quantity cannot be negative.');
    }

    int decimalPlaces = 0;
    int decimalPart = 0;

    if (parts.length == 2) {
      final decimalStr = parts[1];
      decimalPlaces = decimalStr.length;
      decimalPart = int.tryParse(decimalStr) ?? 0;

      if (decimalPart < 0) {
        throw FormatException('Invalid decimal part: $humanReadable');
      }
    }

    // Combine into a single integer: intPart * 10^decimalPlaces + decimalPart
    final fullValue = intPart * _pow10(decimalPlaces) + decimalPart;

    if (fullValue == 0) {
      throw FormatException('Quantity must be greater than 0.');
    }

    // Calculate the base-unit quantity
    // fullValue represents the input with 'decimalPlaces' decimal places
    // We need: fullValue * multiplier / 10^decimalPlaces
    //
    // Check if this divides evenly
    final totalMultiplier = multiplier;
    final totalDivisor = _pow10(decimalPlaces);
    final gcd = _gcd(totalMultiplier, totalDivisor);
    final simplifiedMultiplier = totalMultiplier ~/ gcd;
    final simplifiedDivisor = totalDivisor ~/ gcd;

    if (fullValue % simplifiedDivisor != 0) {
      throw FormatException(
        'Precision smaller than the base unit. '
        'The smallest unit for $unit is 1/$simplifiedMultiplier.',
      );
    }

    final result = (fullValue ~/ simplifiedDivisor) * simplifiedMultiplier;

    return result;
  }

  /// Converts an integer base-unit quantity back to a human-readable decimal string.
  ///
  /// Examples:
  /// - toHumanQuantity(2000, 'litre') → '2'
  /// - toHumanQuantity(500, 'litre') → '0.5'
  /// - toHumanQuantity(1250, 'litre') → '1.25'
  /// - toHumanQuantity(2, 'piece') → '2'
  static String toHumanQuantity(int baseUnitQuantity, String unit) {
    final divisor = unitMultipliers[unit] ?? 1;

    if (divisor == 1) {
      return baseUnitQuantity.toString();
    }

    // fullValue = baseUnitQuantity, divisor = unit multiplier
    // result = fullValue / divisor
    final intPart = baseUnitQuantity ~/ divisor;
    final remainder = baseUnitQuantity % divisor;

    if (remainder == 0) {
      return intPart.toString();
    }

    // Convert remainder to decimal places
    final divisorStr = divisor.toString();
    final decimalPlaces = divisorStr.length - 1;
    final paddedRemainder = remainder.toString().padLeft(decimalPlaces, '0');

    // Remove trailing zeros
    final trimmedRemainder = paddedRemainder.replaceAll(RegExp(r'0+$'), '');

    return '$intPart.$trimmedRemainder';
  }

  static int _pow10(int n) {
    int result = 1;
    for (int i = 0; i < n; i++) {
      result *= 10;
    }
    return result;
  }

  static int _gcd(int a, int b) {
    while (b != 0) {
      final temp = b;
      b = a % b;
      a = temp;
    }
    return a;
  }
}
