import cron from 'node-cron';
import prisma from '../db/prisma';
import { priceOrchestrator } from './price-orchestrator.service';
import { sendPriceDropNotification } from './fcm.service';

/**
 * 6시간마다 실행: FCM 토큰 있는 기기의 감시 상품 가격 확인
 * 조건: 마트 가격 기록된 상품 중 현재 온라인가 < 기록 마트가 이면 알림 발송
 */
export function startPriceAlertCron(): void {
  // 6시간마다 (00:00, 06:00, 12:00, 18:00)
  cron.schedule('0 */6 * * *', runPriceCheck, { timezone: 'Asia/Seoul' });
  console.log('[PriceAlert] Cron started (every 6 hours)');
}

async function runPriceCheck(): Promise<void> {
  console.log('[PriceAlert] Starting price check...');

  const devices = await prisma.device.findMany({
    where: { fcmToken: { not: null } },
    select: { id: true, deviceUuid: true, fcmToken: true },
  });

  console.log(`[PriceAlert] Checking ${devices.length} devices`);

  for (const device of devices) {
    try {
      await checkDeviceProducts(device as { id: bigint; deviceUuid: string; fcmToken: string });
    } catch (e) {
      console.error(`[PriceAlert] Error for device ${device.deviceUuid}:`, e);
    }
  }
}

async function checkDeviceProducts(device: {
  id: bigint;
  deviceUuid: string;
  fcmToken: string;
}): Promise<void> {
  // 최근 30일 내 오프라인 가격이 기록된 스캔 (바코드별 최신 마트가격 추출)
  const scans = await prisma.scan.findMany({
    where: {
      deviceId: device.id,
      barcode: { not: null },
      scanType: 'product',
      scannedAt: { gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) },
      offlinePrices: { some: {} },
    },
    include: {
      offlinePrices: { orderBy: { createdAt: 'desc' }, take: 1 },
    },
    orderBy: { scannedAt: 'desc' },
  });

  // 바코드별 최신 마트가격 집계
  const watchMap = new Map<string, number>();
  for (const scan of scans) {
    if (!scan.barcode || scan.offlinePrices.length === 0) continue;
    if (!watchMap.has(scan.barcode)) {
      watchMap.set(scan.barcode, scan.offlinePrices[0].price);
    }
  }

  for (const [barcode, lastOfflinePrice] of watchMap) {
    try {
      // products 테이블에서 상품명 조회
      const product = await prisma.product.findUnique({
        where: { barcode },
        select: { name: true },
      });
      const productName = product?.name ?? barcode;

      // 현재 온라인 최저가 조회
      const result = await priceOrchestrator(barcode, productName);
      if (!result) continue;

      const currentOnlinePrice = result.lowest_price as number;
      if (currentOnlinePrice < lastOfflinePrice) {
        await sendPriceDropNotification({
          token: device.fcmToken,
          productName,
          onlinePrice: currentOnlinePrice,
          offlinePrice: lastOfflinePrice,
          barcode,
        });
        // 너무 자주 알림 보내지 않도록 1초 대기
        await new Promise((r) => setTimeout(r, 1000));
      }
    } catch (e) {
      console.error(`[PriceAlert] Error checking barcode ${barcode}:`, e);
    }
  }
}
