import { test as base } from '@playwright/test';
import { randomBytes } from 'crypto';
import { CaseListPage } from '../pages/CaseListPage';
import { CaseRecordPage } from '../pages/CaseRecordPage';
import { NewCaseModal } from '../pages/NewCaseModal';
import { SfApi } from './sf-api';

/** Every case this run creates starts with this prefix, so cleanup can find them all. */
export const RUN_PREFIX = `QA-UI-${randomBytes(4).toString('hex')}`;

type TestFixtures = {
  subject: string;
  newCase: NewCaseModal;
  caseRecord: CaseRecordPage;
  caseList: CaseListPage;
};

type WorkerFixtures = {
  api: SfApi;
};

export const test = base.extend<TestFixtures, WorkerFixtures>({
  api: [
    async ({}, use) => {
      const api = await SfApi.create();
      await use(api);
      for (const c of await api.findCasesBySubjectPrefix(RUN_PREFIX)) {
        await api.deleteCase(c.Id);
      }
      await api.dispose();
    },
    { scope: 'worker' },
  ],

  subject: async ({}, use, testInfo) => {
    const slug = testInfo.title.replace(/[^A-Za-z0-9 ]/g, '').slice(0, 60);
    await use(`${RUN_PREFIX} ${slug}`);
  },

  newCase: async ({ page }, use) => use(new NewCaseModal(page)),
  caseRecord: async ({ page }, use) => use(new CaseRecordPage(page)),
  caseList: async ({ page }, use) => use(new CaseListPage(page)),
});

export { expect } from '@playwright/test';
