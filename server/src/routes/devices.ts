import { Router, Request, Response } from 'express';
import { z } from 'zod';
import prisma from '../db/prisma';

const router = Router();

// POST /api/v1/devices/token — FCM 토큰 등록/갱신
router.post('/token', async (req: Request, res: Response) => {
  const schema = z.object({
    device_uuid: z.string().uuid(),
    fcm_token: z.string().min(1),
    os: z.enum(['ios', 'android']).optional(),
  });

  const result = schema.safeParse(req.body);
  if (!result.success) {
    return res.status(400).json({ error: 'INVALID_REQUEST' });
  }

  const { device_uuid, fcm_token, os } = result.data;

  await prisma.device.upsert({
    where: { deviceUuid: device_uuid },
    update: { fcmToken: fcm_token, lastSeenAt: new Date() },
    create: {
      deviceUuid: device_uuid,
      fcmToken: fcm_token,
      os: os ?? 'android',
    },
  });

  return res.json({ ok: true });
});

export default router;
