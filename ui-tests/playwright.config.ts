import { defineConfig, devices } from '@playwright/test';
import { lightningUrl } from './src/support/env';

/**
 * Lightning is slow to boot and the suite shares one org, so tests run
 * serially with generous timeouts. Every failure keeps a trace, screenshot
 * and video for the HTML report.
 */
export default defineConfig({
  testDir: './tests',
  globalSetup: require.resolve('./src/support/global-setup'),
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  timeout: 120_000,
  expect: { timeout: 20_000 },
  forbidOnly: !!process.env.CI,
  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
    ['junit', { outputFile: 'results/junit.xml' }],
    ['json', { outputFile: 'results/results.json' }],
  ],
  use: {
    baseURL: lightningUrl(),
    storageState: 'state/auth.json',
    viewport: { width: 1440, height: 900 },
    actionTimeout: 20_000,
    navigationTimeout: 60_000,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  // CI runs Chromium only. PW_ALL_BROWSERS=1 adds Firefox and WebKit for a local
  // cross-browser pass; they are not part of the verified CI run yet.
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } },
    ...(process.env.PW_ALL_BROWSERS
      ? [
          { name: 'firefox', use: { ...devices['Desktop Firefox'], viewport: { width: 1440, height: 900 } } },
          { name: 'webkit', use: { ...devices['Desktop Safari'], viewport: { width: 1440, height: 900 } } },
        ]
      : []),
  ],
});
