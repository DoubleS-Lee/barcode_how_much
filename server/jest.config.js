module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['**/*.test.ts'],
  collectCoverageFrom: ['src/**/*.ts', '!src/index.ts'],
  coverageThreshold: {
    // 핵심 서비스는 80% 이상 유지
    'src/services/price-orchestrator.service.ts': { lines: 80 },
  },
};
