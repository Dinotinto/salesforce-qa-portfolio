import { expect, Page } from '@playwright/test';

/** The Cases object home / list view. */
export class CaseListPage {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  async open(listViewApiName = 'AllOpenCases'): Promise<void> {
    await this.page.goto(`/lightning/o/Case/list?filterName=${listViewApiName}`);
    await expect(this.page.getByRole('grid').first()).toBeVisible();
  }

  async search(text: string): Promise<void> {
    const box = this.page.getByPlaceholder('Search this list...');
    await box.fill(text);
    await box.press('Enter');
  }

  async expectRowWithSubject(subject: string): Promise<void> {
    await expect(this.page.getByRole('grid').first().getByText(subject, { exact: true }).first()).toBeVisible();
  }

  async expectNoRowWithSubject(subject: string): Promise<void> {
    // Wait for the search to settle (either rows or the empty-state message) before asserting absence.
    await expect(this.page.getByText(/No items to display|items?\s*•/).first()).toBeVisible();
    await expect(this.page.getByRole('grid').first().getByText(subject, { exact: true })).toHaveCount(0);
  }
}
