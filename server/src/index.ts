import 'express-async-errors';
import express from 'express';
import cors from 'cors';
import morgan from 'morgan';
import dotenv from 'dotenv';
import path from 'path';
import priceRouter from './routes/price';
import scansRouter from './routes/scans';
import recommendRouter from './routes/recommend';
import postsRouter from './routes/posts';
import devicesRouter from './routes/devices';
import favoritesRouter from './routes/favorites';
import { errorHandler } from './middleware/error';
import { logger } from './utils/logger';
dotenv.config();

const app = express();
const PORT = parseInt(process.env.PORT || '3000');

app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

// 업로드 이미지 정적 서빙
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

app.get('/health', (_, res) => res.json({ status: 'ok', timestamp: new Date() }));

app.use('/api/v1/price', priceRouter);
app.use('/api/v1/scans', scansRouter);
app.use('/api/v1/recommend', recommendRouter);
app.use('/api/v1/posts', postsRouter);
app.use('/api/v1/devices', devicesRouter);
app.use('/api/v1/favorites', favoritesRouter);

app.use(errorHandler);

app.listen(PORT, () => {
  logger.info('Server', `Running on http://localhost:${PORT} [${process.env.NODE_ENV ?? 'development'}]`);
});

export default app;
