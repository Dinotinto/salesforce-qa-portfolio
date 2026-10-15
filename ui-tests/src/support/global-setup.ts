import { chromium, FullConfig } from '@playwright/test';
import { mkdirSync } from 'fs';
import { accessToken, instanceUrl } from './env';

/**
 * Signs in once through frontdoor.jsp with the CI user's OAuth access token
 * (the same mechanism `sf org open` uses), then saves the session cookies so
 * every test starts already logged in. No password is ever typed.
 */
export default async function globalSetup(_config: FullConfig): Promise<void> {
  mkdirSync('state', { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const retURL = encodeURIComponent('/lightning/page/home');

  await page.goto(`${instanceUrl()}/secur/frontdoor.jsp?sid=${encodeURIComponent(accessToken())}&retURL=${retURL}`);
  await page.waitForURL(/\/lightning\//, { timeout: 90_000 });
  // Wait for the Lightning shell so the session cookies for both domains are set.
  await page.getByRole('navigation', { name: /Global/i }).first().waitFor({ timeout: 90_000 }).catch(() => undefined);

  await page.context().storageState({ path: 'state/auth.json' });
  await browser.close();
}
