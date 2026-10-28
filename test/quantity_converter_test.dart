import 'package:flutter_test/flutter_test.dart';

import 'package:vyom_business/utils/quantity_converter.dart';

void main() {
  group('QuantityConverter.toIntQuantity', () {
    test('converts whole number like 2 to 2000 for litre', () {
      final result = QuantityConverter.toIntQuantity('2', 'litre');
      expect(result, 2000);
    });

    test('converts decimal 0.5 to 500 for litre', () {
      final result = QuantityConverter.toIntQuantity('0.5', 'litre');
      expect(result, 500);
    });

    test('converts 1.25 to 1250 for litre', () {
      final result = QuantityConverter.toIntQuantity('1.25', 'litre');
      expect(result, 1250);
    });

    test('converts 1.250 to 1250 for litre (removes trailing zeros)', () {
      final result = QuantityConverter.toIntQuantity('1.250', 'litre');
      expect(result, 1250);
    });

    test('converts 0.001 to 1 for litre (1000 multiplier)', () {
      final result = QuantityConverter.toIntQuantity('0.001', 'litre');
      expect(result, 1);
    });

    test('converts 2 to 2 for piece (1x multiplier)', () {
      final result = QuantityConverter.toIntQuantity('2', 'piece');
      expect(result, 2);
    });

    test('converts 2.0 to 2 for piece', () {
      final result = QuantityConverter.toIntQuantity('2.0', 'piece');
      expect(result, 2);
    });

    test('converts 5.5 to 5500 for kg', () {
      final result = QuantityConverter.toIntQuantity('5.5', 'kg');
      expect(result, 5500);
    });

    test('rejects empty string', () {
      expect(
        () => QuantityConverter.toIntQuantity('', 'litre'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects whitespace-only string', () {
      expect(
        () => QuantityConverter.toIntQuantity('   ', 'litre'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects zero', () {
      expect(
        () => QuantityConverter.toIntQuantity('0', 'litre'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects 0.0', () {
      expect(
        () => QuantityConverter.toIntQuantity('0.0', 'litre'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects negative values', () {
      expect(
        () => QuantityConverter.toIntQuantity('-2', 'litre'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects negative decimals', () {
      expect(
        () => QuantityConverter.toIntQuantity('-1.5', 'litre'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed decimals like 1.2.3', () {
      expect(
        () => QuantityConverter.toIntQuantity('1.2.3', 'litre'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects precision smaller than base unit (0.0001 for litre)', () {
      expect(
        () => QuantityConverter.toIntQuantity('0.0001', 'litre'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-numeric strings', () {
      expect(
        () => QuantityConverter.toIntQuantity('abc', 'litre'),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts decimal with trailing dot correctly', () {
      // This should fail since ".5" is malformed
      expect(
        () => QuantityConverter.toIntQuantity('.5', 'litre'),
        throwsA(isA<FormatException>()),
      );
    });

    test('trims whitespace before parsing', () {
      final result = QuantityConverter.toIntQuantity('  2.5  ', 'litre');
      expect(result, 2500);
    });

    test('converts 0.125 to 125 for litre', () {
      final result = QuantityConverter.toIntQuantity('0.125', 'litre');
      expect(result, 125);
    });

    test('converts 10.5 to 10500 for litre', () {
      final result = QuantityConverter.toIntQuantity('10.5', 'litre');
      expect(result, 10500);
    });
  });

  group('QuantityConverter.toHumanQuantity', () {
    test('converts 2000 to "2" for litre', () {
      final result = QuantityConverter.toHumanQuantity(2000, 'litre');
      expect(result, '2');
    });

    test('converts 500 to "0.5" for litre', () {
      final result = QuantityConverter.toHumanQuantity(500, 'litre');
      expect(result, '0.5');
    });

    test('converts 1250 to "1.25" for litre', () {
      final result = QuantityConverter.toHumanQuantity(1250, 'litre');
      expect(result, '1.25');
    });

    test('converts 1 to "0.001" for litre', () {
      final result = QuantityConverter.toHumanQuantity(1, 'litre');
      expect(result, '0.001');
    });

    test('converts 2 to "2" for piece', () {
      final result = QuantityConverter.toHumanQuantity(2, 'piece');
      expect(result, '2');
    });

    test('converts 5500 to "5.5" for kg', () {
      final result = QuantityConverter.toHumanQuantity(5500, 'kg');
      expect(result, '5.5');
    });

    test('converts 125 to "0.125" for litre', () {
      final result = QuantityConverter.toHumanQuantity(125, 'litre');
      expect(result, '0.125');
    });

    test('converts 10500 to "10.5" for litre', () {
      final result = QuantityConverter.toHumanQuantity(10500, 'litre');
      expect(result, '10.5');
    });
  });

  group('QuantityConverter round-trip conversions', () {
    test('round-trip: 2 -> 2000 -> 2', () {
      final intValue = QuantityConverter.toIntQuantity('2', 'litre');
      final humanValue = QuantityConverter.toHumanQuantity(intValue, 'litre');
      expect(humanValue, '2');
    });

    test('round-trip: 0.5 -> 500 -> 0.5', () {
      final intValue = QuantityConverter.toIntQuantity('0.5', 'litre');
      final humanValue = QuantityConverter.toHumanQuantity(intValue, 'litre');
      expect(humanValue, '0.5');
    });

    test('round-trip: 1.25 -> 1250 -> 1.25', () {
      final intValue = QuantityConverter.toIntQuantity('1.25', 'litre');
      final humanValue = QuantityConverter.toHumanQuantity(intValue, 'litre');
      expect(humanValue, '1.25');
    });

    test('round-trip: 1.250 -> 1250 -> 1.25', () {
      final intValue = QuantityConverter.toIntQuantity('1.250', 'litre');
      final humanValue = QuantityConverter.toHumanQuantity(intValue, 'litre');
      // Trailing zeros are removed in the round trip
      expect(humanValue, '1.25');
    });

    test('round-trip: 0.001 -> 1 -> 0.001', () {
      final intValue = QuantityConverter.toIntQuantity('0.001', 'litre');
      final humanValue = QuantityConverter.toHumanQuantity(intValue, 'litre');
      expect(humanValue, '0.001');
    });
  });

  group('QuantityConverter edge cases', () {
    test('handles very large integers', () {
      final result = QuantityConverter.toIntQuantity('1000000', 'litre');
      expect(result, 1000000000);
    });

    test('handles very small decimals', () {
      final result = QuantityConverter.toIntQuantity('0.001', 'litre');
      expect(result, 1);
    });

    test('converts 2.5 for gram (1x multiplier)', () {
      // For gram with multiplier 1, precision must be whole number
      expect(
        () => QuantityConverter.toIntQuantity('2.5', 'gram'),
        throwsA(isA<FormatException>()),
      );
    });

    test('converts 3 for packet (1x multiplier)', () {
      final result = QuantityConverter.toIntQuantity('3', 'packet');
      expect(result, 3);
    });
  });
}
