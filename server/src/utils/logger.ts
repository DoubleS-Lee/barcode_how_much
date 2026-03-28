type LogLevel = 'INFO' | 'WARN' | 'ERROR' | 'DEBUG';

function log(level: LogLevel, module: string, message: string, data?: unknown) {
  const ts = new Date().toISOString();
  const base = `[${ts}] [${level}] [${module}] ${message}`;
  if (data !== undefined) {
    const extra = data instanceof Error
      ? { message: data.message, stack: data.stack }
      : data;
    console[level === 'ERROR' ? 'error' : level === 'WARN' ? 'warn' : 'log'](base, JSON.stringify(extra));
  } else {
    console[level === 'ERROR' ? 'error' : level === 'WARN' ? 'warn' : 'log'](base);
  }
}

export const logger = {
  info:  (module: string, message: string, data?: unknown) => log('INFO',  module, message, data),
  warn:  (module: string, message: string, data?: unknown) => log('WARN',  module, message, data),
  error: (module: string, message: string, data?: unknown) => log('ERROR', module, message, data),
  debug: (module: string, message: string, data?: unknown) => {
    if (process.env.NODE_ENV !== 'production') log('DEBUG', module, message, data);
  },
};
