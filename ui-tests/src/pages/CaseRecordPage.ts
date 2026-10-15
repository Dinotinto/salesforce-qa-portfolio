import { expect, Locator, Page } from '@playwright/test';

/** A Case record page (highlights panel + details tab) in Lightning Experience. */
export class CaseRecordPage {
  readonly page: Page;
  readonly toast: Locator;

  constructor(page: Page) {
    this.page = page;
    this.toast = page.locator('.forceToastMessage, [role="alert"]').filter({ hasText: /\S/ });
  }

  async open(caseId: string): Promise<void> {
    await this.page.goto(`/lightning/r/Case/${caseId}/view`);
    await this.waitForRecord();
  }

  async waitForRecord(): Promise<void> {
    await expect(this.page.locator('records-highlights2, .slds-page-header').first()).toBeVisible();
  }

  async openDetailsTab(): Promise<void> {
    const details = this.page.getByRole('tab', { name: 'Details' });
    if (await details.count()) {
      await details.first().click();
    }
  }

  /** A field (label + value) on the Details tab. Lightning tags each one with its label. */
  field(label: string): Locator {
    return this.page.locator(`records-record-layout-item[field-label="${label}"]`).first();
  }

  async expectFieldValue(label: string, value: string): Promise<void> {
    await this.openDetailsTab();
    await expect(this.field(label)).toContainText(value);
  }

  /** Inline-edits a picklist on the Details tab and saves. */
  async inlineEditPicklist(label: string, option: string): Promise<void> {
    await this.openDetailsTab();
    await this.page.getByRole('button', { name: `Edit ${label}` }).first().click();
    const combobox = this.page.getByRole('combobox', { name: label }).first();
    await combobox.click();
    await this.page.getByRole('option', { name: option, exact: true }).click();
    await this.page.getByRole('button', { name: 'Save', exact: true }).click();
    await expect(this.page.getByRole('button', { name: 'Save', exact: true })).toBeHidden();
  }

  async expectToast(text: string | RegExp): Promise<void> {
    await expect(this.toast.filter({ hasText: text }).first()).toBeVisible();
  }
}
