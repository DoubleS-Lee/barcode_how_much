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

// GET /api/v1/devices/nickname/check?nickname=... — 닉네임 중복 확인
router.get('/nickname/check', async (req: Request, res: Response) => {
  const nickname = (req.query.nickname as string)?.trim();
  if (!nickname) return res.status(400).json({ error: 'nickname required' });

  const exists = await prisma.socialAccount.findFirst({
    where: { nickname: { equals: nickname, mode: 'insensitive' } },
    select: { id: true },
  });

  return res.json({ available: !exists });
});

// GET /api/v1/devices/nickname?device_uuid=... — 현재 닉네임 조회
router.get('/nickname', async (req: Request, res: Response) => {
  const device_uuid = req.query.device_uuid as string;
  if (!device_uuid) return res.status(400).json({ error: 'device_uuid required' });

  const device = await prisma.device.findUnique({
    where: { deviceUuid: device_uuid },
    select: { socialProvider: true, socialId: true },
  });

  if (!device?.socialProvider || !device?.socialId) {
    return res.json({ nickname: null });
  }

  const account = await prisma.socialAccount.findUnique({
    where: { provider_socialId: { provider: device.socialProvider, socialId: device.socialId } },
    select: { nickname: true },
  });

  return res.json({ nickname: account?.nickname ?? null });
});

// POST /api/v1/devices/nickname — 닉네임 설정 (SocialAccount에 저장, 전역 중복 불허)
router.post('/nickname', async (req: Request, res: Response) => {
  const schema = z.object({
    device_uuid: z.string().uuid(),
    nickname: z.string().min(2).max(15).regex(/^[가-힣a-zA-Z0-9_]+$/, '한글, 영문, 숫자, _만 사용 가능합니다'),
  });

  const result = schema.safeParse(req.body);
  if (!result.success) {
    return res.status(400).json({ error: 'INVALID_NICKNAME', details: result.error.flatten() });
  }

  const { device_uuid, nickname } = result.data;

  // 현재 기기의 소셜 로그인 정보 조회
  const device = await prisma.device.findUnique({
    where: { deviceUuid: device_uuid },
    select: { socialProvider: true, socialId: true },
  });

  if (!device?.socialProvider || !device?.socialId) {
    return res.status(400).json({ error: 'NOT_LOGGED_IN', message: '소셜 로그인 후 닉네임을 설정할 수 있습니다' });
  }

  // 전역 중복 확인 (SocialAccount 기준)
  const existing = await prisma.socialAccount.findFirst({
    where: { nickname: { equals: nickname, mode: 'insensitive' } },
  });
  if (existing) {
    return res.status(409).json({ error: 'NICKNAME_TAKEN', message: '이미 사용 중인 닉네임입니다' });
  }

  // SocialAccount에 닉네임 저장 (이 (provider, socialId)에 영구 귀속)
  const account = await prisma.socialAccount.upsert({
    where: { provider_socialId: { provider: device.socialProvider, socialId: device.socialId } },
    update: { nickname },
    create: { provider: device.socialProvider, socialId: device.socialId, nickname },
  });

  return res.json({ nickname: account.nickname });
});

// POST /api/v1/devices/social-link — 소셜 로그인 연동 & 닉네임 복원
// 닉네임은 SocialAccount (provider, socialId) 쌍에 귀속 — 기기가 바뀌거나 다른 계정으로
// 전환해도 원래 계정으로 돌아오면 닉네임이 자동 복원됨
router.post('/social-link', async (req: Request, res: Response) => {
  const schema = z.object({
    device_uuid: z.string().uuid(),
    provider: z.enum(['google', 'kakao', 'naver']),
    social_id: z.string().min(1).max(200),
  });

  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_REQUEST' });

  const { device_uuid, provider, social_id } = parsed.data;

  // SocialAccount에서 이 (provider, socialId)의 닉네임 조회 (없으면 새로 생성)
  const socialAccount = await prisma.socialAccount.upsert({
    where: { provider_socialId: { provider, socialId: social_id } },
    update: {},
    create: { provider, socialId: social_id },
  });

  const finalNickname = socialAccount.nickname ?? null;

  // 기기의 현재 소셜 로그인 상태 업데이트
  await prisma.device.upsert({
    where: { deviceUuid: device_uuid },
    update: { socialProvider: provider, socialId: social_id, lastSeenAt: new Date() },
    create: { deviceUuid: device_uuid, os: 'android', socialProvider: provider, socialId: social_id },
  });

  return res.json({ nickname: finalNickname });
});

export default router;
