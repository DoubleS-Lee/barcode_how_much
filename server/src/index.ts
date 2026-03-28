import 'express-async-errors';
import express from 'express';
import cors from 'cors';
import morgan from 'morgan';
import dotenv from 'dotenv';
import path from 'path';
import { rateLimit } from 'express-rate-limit';
import priceRouter from './routes/price';
import scansRouter from './routes/scans';
import recommendRouter from './routes/recommend';
import postsRouter from './routes/posts';
import devicesRouter from './routes/devices';
import favoritesRouter from './routes/favorites';
import savedLocationsRouter from './routes/saved-locations';
import { errorHandler } from './middleware/error';
import { logger } from './utils/logger';
dotenv.config();

const app = express();
const PORT = parseInt(process.env.PORT || '3000');

app.use(cors({
  origin: process.env.CORS_ORIGIN ? process.env.CORS_ORIGIN.split(',') : true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
  allowedHeaders: ['Content-Type'],
}));
app.use(express.json());
app.use(morgan('dev'));

// 일반 API: IP당 15분에 200회
const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'TOO_MANY_REQUESTS', message: '잠시 후 다시 시도해주세요.' },
});

// 가격 조회: IP당 1분에 30회 (외부 API 호출 비용 보호)
const priceLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'TOO_MANY_REQUESTS', message: '가격 조회는 1분에 30회까지 가능합니다.' },
});

app.use('/api/v1', generalLimiter);
app.use('/api/v1/price', priceLimiter);

// 업로드 이미지 정적 서빙
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

app.get('/health', (_, res) => res.json({ status: 'ok', timestamp: new Date() }));

app.use('/api/v1/price', priceRouter);
app.use('/api/v1/scans', scansRouter);
app.use('/api/v1/recommend', recommendRouter);
app.use('/api/v1/posts', postsRouter);
app.use('/api/v1/devices', devicesRouter);
app.use('/api/v1/favorites', favoritesRouter);
app.use('/api/v1/saved-locations', savedLocationsRouter);

app.use(errorHandler);

app.listen(PORT, () => {
  logger.info('Server', `Running on http://localhost:${PORT} [${process.env.NODE_ENV ?? 'development'}]`);
});

export default app;
