import { z } from 'zod';

// price.ts와 동일한 스키마
const barcodeSchema = z.string().regex(/^\d{8,13}$/, 'Barcode must be 8-13 digits');

describe('바코드 유효성 검증', () => {
  const valid = [
    '88012345',          // 8자리 (최소)
    '8801234567890',     // 13자리 EAN-13
    '012345678905',      // 12자리 UPC-A
    '12345678',          // 8자리
  ];

  const invalid = [
    '1234567',           // 7자리 (너무 짧음)
    '12345678901234',    // 14자리 (너무 김)
    'abcd1234567',       // 문자 포함
    '',                  // 빈 문자열
    '1234 5678',         // 공백 포함
    '1234567.8',         // 특수문자 포함
  ];

  test.each(valid)('유효한 바코드: %s', (barcode) => {
    expect(barcodeSchema.safeParse(barcode).success).toBe(true);
  });

  test.each(invalid)('유효하지 않은 바코드: %s', (barcode) => {
    expect(barcodeSchema.safeParse(barcode).success).toBe(false);
  });
});
