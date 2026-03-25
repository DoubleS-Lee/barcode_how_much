import cron from 'node-cron';
import prisma from '../db/prisma';
import { priceOrchestrator } from './price-orchestrator.service';
import { sendFavoriteDropNotification } from './fcm.service';

/**
 * 6시간마다 실행: FCM 토큰 있는 기기의 찜한 상품 가격 확인
 * 조건: 찜한 상품의 현재 온라인가 < 마지막으로 기록된 온라인가 이면 알림 발송
 */
export function startPriceAlertCron(): void {
  // 6시간마다 (00:00, 06:00, 12:00, 18:00 KST)
  cron.schedule('0 */6 * * *', runPriceCheck, { timezone: 'Asia/Seoul' });
  console.log('[PriceAlert] Cron started (every 6 hours, favorites-based)');
}

async function runPriceCheck(): Promise<void> {
  console.log('[PriceAlert] Starting favorites price check...');

  const devices = await prisma.device.findMany({
    where: { fcmToken: { not: null } },
    select: { id: true, deviceUuid: true, fcmToken: true },
  });

  console.log(`[PriceAlert] Checking ${devices.length} devices`);

  for (const device of devices) {
    try {
      await checkDeviceFavorites(device as { id: bigint; deviceUuid: string; fcmToken: string });
    } catch (e) {
      console.error(`[PriceAlert] Error for device ${device.deviceUuid}:`, e);
    }
  }
}

async function checkDeviceFavorites(device: {
  id: bigint;
  deviceUuid: string;
  fcmToken: string;
}): Promise<void> {
  // 이 기기의 찜 목록
  const favorites = await prisma.deviceFavorite.findMany({
    where: { deviceUuid: device.deviceUuid },
    select: { barcode: true },
  });

  if (favorites.length === 0) return;
  console.log(`[PriceAlert] ${device.deviceUuid.slice(0, 8)} has ${favorites.length} favorites`);

  for (const { barcode } of favorites) {
    try {
      // 이 기기의 마지막 온라인 스캔 가격 (기준점)
      const lastScan = await prisma.scan.findFirst({
        where: {
          deviceId: device.id,
          barcode,
          scanType: 'product',
          onlinePrices: { some: {} },
        },
        orderBy: { scannedAt: 'desc' },
        include: {
          onlinePrices: {
            where: { isLowest: true },
            orderBy: { fetchedAt: 'desc' },
            take: 1,
          },
        },
      });

      const lastKnownPrice = lastScan?.onlinePrices[0]?.price;
      if (!lastKnownPrice) continue; // 스캔 이력 없으면 건너뜀

      // 상품명 조회
      const product = await prisma.product.findUnique({
        where: { barcode },
        select: { name: true },
      });
      const productName = product?.name ?? barcode;

      // 현재 온라인 최저가 조회
      const result = await priceOrchestrator(barcode, productName);
      if (!result) continue;

      const currentOnlinePrice = result.lowest_price as number;

      // 마지막 기록 가격보다 현재 더 싸면 알림
      if (currentOnlinePrice < lastKnownPrice) {
        await sendFavoriteDropNotification({
          token: device.fcmToken,
          productName,
          currentPrice: currentOnlinePrice,
          previousPrice: lastKnownPrice,
          barcode,
        });
        // 연속 알림 방지
        await new Promise((r) => setTimeout(r, 1000));
      }
    } catch (e) {
      console.error(`[PriceAlert] Error checking barcode ${barcode}:`, e);
    }
  }
}
