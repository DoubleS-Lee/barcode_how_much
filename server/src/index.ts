import 'express-async-errors';
import express from 'express';
import cors from 'cors';
import morgan from 'morgan';
import dotenv from 'dotenv';
import priceRouter from './routes/price';
import scansRouter from './routes/scans';
import recommendRouter from './routes/recommend';
import postsRouter from './routes/posts';
import { errorHandler } from './middleware/error';

dotenv.config();

const app = express();
const PORT = parseInt(process.env.PORT || '3000');

app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

app.get('/health', (_, res) => res.json({ status: 'ok', timestamp: new Date() }));

app.use('/api/v1/price', priceRouter);
app.use('/api/v1/scans', scansRouter);
app.use('/api/v1/recommend', recommendRouter);
app.use('/api/v1/posts', postsRouter);

app.use(errorHandler);

app.listen(PORT, () => {
  console.log(`[Server] Running on http://localhost:${PORT}`);
});

export default app;
