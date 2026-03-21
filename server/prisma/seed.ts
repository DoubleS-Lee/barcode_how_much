/**
 * 샘플 데이터 시드 스크립트
 * 실행: npx ts-node prisma/seed.ts
 * 환경변수: SEED_DEVICE_UUID=<앱에서 확인한 UUID>
 */
import { PrismaClient } from '@prisma/client';
import * as dotenv from 'dotenv';
dotenv.config();

const prisma = new PrismaClient();

// 앱에서 확인한 UUID를 환경변수로 넘기거나 기본값 사용
const DEVICE_UUID = process.env.SEED_DEVICE_UUID || 'test-demo-uuid-0000-000000000001';

const products: {
  barcode: string;
  name: string;
  imageUrl?: string;
  scans: { daysAgo: number; coupang: number; naver: number; offline?: number; store?: string }[];
}[] = [
  {
    barcode: '8801234567890',
    name: '농심 신라면 멀티팩 5봉',
    scans: [
      { daysAgo: 90, coupang: 4290, naver: 4480, offline: 5200, store: '이마트' },
      { daysAgo: 60, coupang: 4190, naver: 4380 },
      { daysAgo: 30, coupang: 4490, naver: 4600, offline: 5400, store: '홈플러스' },
      { daysAgo: 5,  coupang: 4350, naver: 4500 },
    ],
  },
  {
    barcode: '8804800012345',
    name: 'CJ 비비고 왕교자 만두',
    scans: [
      { daysAgo: 70, coupang: 8900, naver: 9200, offline: 11900, store: '이마트' },
      { daysAgo: 40, coupang: 8500, naver: 8900 },
      { daysAgo: 10, coupang: 8750, naver: 9100, offline: 10900, store: '롯데마트' },
    ],
  },
  {
    barcode: '8801117010015',
    name: '오리온 초코파이 정 12개입',
    scans: [
      { daysAgo: 100, coupang: 6300, naver: 6700, offline: 7900, store: '홈플러스' },
      { daysAgo: 75,  coupang: 6500, naver: 6800 },
      { daysAgo: 50,  coupang: 6200, naver: 6500, offline: 7500, store: '이마트' },
      { daysAgo: 25,  coupang: 6700, naver: 6900 },
      { daysAgo: 7,   coupang: 6450, naver: 6750, offline: 7800, store: '롯데마트' },
    ],
  },
  {
    barcode: '8806095123456',
    name: '피죤 세탁세제 드럼용 3L',
    scans: [
      { daysAgo: 50, coupang: 15900, naver: 16500, offline: 18900, store: '이마트' },
      { daysAgo: 25, coupang: 14900, naver: 15800 },
      { daysAgo: 3,  coupang: 16500, naver: 17000, offline: 19500, store: '홈플러스' },
    ],
  },
  {
    barcode: '8801190013407',
    name: '매일유업 바나나맛 우유 240ml',
    scans: [
      { daysAgo: 20, coupang: 1350, naver: 1450 },
      { daysAgo: 10, coupang: 1280, naver: 1390, offline: 1680, store: 'GS25' },
      { daysAgo: 1,  coupang: 1300, naver: 1400 },
    ],
  },
];

function daysAgoDate(days: number): Date {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d;
}

async function main() {
  console.log(`🌱 시드 시작 — Device UUID: ${DEVICE_UUID}`);

  const device = await prisma.device.upsert({
    where: { deviceUuid: DEVICE_UUID },
    update: { lastSeenAt: new Date() },
    create: {
      deviceUuid: DEVICE_UUID,
      os: 'android',
      appVersion: '1.0.0',
    },
  });
  console.log(`📱 디바이스: ID=${device.id}\n`);

  for (const product of products) {
    // products 테이블 upsert (스캔 기록에서 이름 표시용)
    await prisma.product.upsert({
      where: { barcode: product.barcode },
      update: { name: product.name },
      create: { barcode: product.barcode, name: product.name, imageUrl: product.imageUrl ?? null },
    });

    console.log(`📦 ${product.name} (${product.barcode})`);
    for (const s of product.scans) {
      const scan = await prisma.scan.create({
        data: {
          deviceId: device.id,
          scanType: 'product',
          barcode: product.barcode,
          scannedAt: daysAgoDate(s.daysAgo),
        },
      });

      const coupangIsLowest = s.coupang <= s.naver;
      await prisma.onlinePrice.createMany({
        data: [
          { scanId: scan.id, platform: 'coupang', price: s.coupang, isLowest: coupangIsLowest },
          { scanId: scan.id, platform: 'naver',   price: s.naver,   isLowest: !coupangIsLowest },
        ],
      });

      if (s.offline) {
        await prisma.offlinePrice.create({
          data: { scanId: scan.id, price: s.offline, storeHint: s.store ?? null },
        });
      }

      console.log(
        `  ✅ ${s.daysAgo}일 전 — 쿠팡 ${s.coupang.toLocaleString()}원` +
        ` / 네이버 ${s.naver.toLocaleString()}원` +
        (s.offline ? ` / 오프라인 ${s.offline.toLocaleString()}원 (${s.store})` : '')
      );
    }
    console.log('');
  }

  console.log('✅ 시드 완료!');
  console.log('💡 앱 스캔 기록에서 위 5개 상품이 보여야 합니다.');
}

main()
  .catch((e) => { console.error('❌ 시드 실패:', e); process.exit(1); })
  .finally(() => prisma.$disconnect());
