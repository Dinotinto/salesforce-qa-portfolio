/** Connection settings, read from the environment (CI fills them from `sf org display --json`). */

export function instanceUrl(): string {
  const url = process.env.SF_INSTANCE_URL;
  if (!url) {
    throw new Error('SF_INSTANCE_URL is not set. See README.md > Running locally.');
  }
  return url.replace(/\/$/, '');
}

export function accessToken(): string {
  const token = process.env.SF_ACCESS_TOKEN;
  if (!token) {
    throw new Error('SF_ACCESS_TOKEN is not set. See README.md > Running locally.');
  }
  return token;
}

export const apiVersion = (): string => process.env.SF_API_VERSION ?? '64.0';

/** https://acme.my.salesforce.com -> https://acme.lightning.force.com (also handles *.develop.* domains). */
export function lightningUrl(): string | undefined {
  const url = process.env.SF_INSTANCE_URL;
  return url ? url.replace(/\/$/, '').replace('.my.salesforce.com', '.lightning.force.com') : undefined;
}
