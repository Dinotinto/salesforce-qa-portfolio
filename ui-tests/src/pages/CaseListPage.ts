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

  private lastSearch = '';

  async search(text: string): Promise<void> {
    this.lastSearch = text;
    const box = this.page.getByPlaceholder('Search this list...');
    await box.fill(text);
    await box.press('Enter');
    await this.settled();
  }

  /** Waits until the list shows its result summary ("3 items • ...") or the empty state. */
  private async settled(): Promise<void> {
    await expect(this.page.getByText(/No items to display|\d+\+?\s+items?\s*•/).first()).toBeVisible();
  }

  /**
   * Lightning serves list views from a client-side cache, so a record changed over the
   * API moments ago can be missing (or still present) until the list is refreshed.
   * Instead of sleeping, refresh with the list's own Refresh button and re-run the
   * search until the expected state shows up, within a bounded time.
   */
  private async refreshAndSearchAgain(): Promise<void> {
    await this.page.getByRole('button', { name: 'Refresh', exact: true }).first().click();
    await this.settled();
    if (this.lastSearch) {
      await this.search(this.lastSearch);
    }
  }

  private rowsWithSubject(subject: string) {
    return this.page.getByRole('grid').first().getByText(subject, { exact: true });
  }

  async expectRowWithSubject(subject: string): Promise<void> {
    let attempt = 0;
    await expect(async () => {
      if (attempt++ > 0) {
        await this.refreshAndSearchAgain();
      }
      await expect(this.rowsWithSubject(subject).first()).toBeVisible({ timeout: 5_000 });
    }, `"${subject}" should appear in the list`).toPass({ timeout: 60_000 });
  }

  async expectNoRowWithSubject(subject: string): Promise<void> {
    let attempt = 0;
    await expect(async () => {
      if (attempt++ > 0) {
        await this.refreshAndSearchAgain();
      }
      await this.settled();
      await expect(this.rowsWithSubject(subject)).toHaveCount(0, { timeout: 5_000 });
    }, `"${subject}" should not be in the list`).toPass({ timeout: 60_000 });
  }
}
