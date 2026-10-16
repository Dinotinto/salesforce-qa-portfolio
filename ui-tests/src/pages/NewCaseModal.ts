import { expect, Locator, Page } from '@playwright/test';

export interface NewCaseInput {
  subject: string;
  description?: string;
  origin?: string;
  priority?: string;
  status?: string;
}

/** The standard "New Case" record-create modal in Lightning Experience. */
export class NewCaseModal {
  readonly page: Page;
  readonly dialog: Locator;

  constructor(page: Page) {
    this.page = page;
    this.dialog = page.getByRole('dialog', { name: 'New Case' });
  }

  async open(): Promise<void> {
    await this.page.goto('/lightning/o/Case/new');
    await expect(this.dialog).toBeVisible();
    await expect(this.dialog.getByRole('textbox', { name: 'Subject' })).toBeEditable();
  }

  async choose(fieldLabel: string, option: string): Promise<void> {
    await this.dialog.getByRole('combobox', { name: fieldLabel }).click();
    await this.page.getByRole('option', { name: option, exact: true }).click();
    await expect(this.dialog.getByRole('combobox', { name: fieldLabel })).toHaveText(new RegExp(option));
  }

  async fill(input: NewCaseInput): Promise<void> {
    await this.dialog.getByRole('textbox', { name: 'Subject' }).fill(input.subject);
    if (input.description) {
      await this.dialog.getByRole('textbox', { name: 'Description' }).fill(input.description);
    }
    if (input.status) {
      await this.choose('Status', input.status);
    }
    if (input.priority) {
      await this.choose('Priority', input.priority);
    }
    if (input.origin) {
      await this.choose('Case Origin', input.origin);
    }
  }

  async save(): Promise<void> {
    await this.dialog.getByRole('button', { name: 'Save', exact: true }).click();
  }

  /** Saves and waits for the record page; returns the new case's Id. */
  async saveAndGetId(): Promise<string> {
    await this.save();
    // Lightning uses /lightning/r/Case/<id>/view or the shorter /lightning/r/<id>/view.
    await this.page.waitForURL(/\/lightning\/r\/(?:Case\/)?500[A-Za-z0-9]{12,15}\/view/);
    const match = this.page.url().match(/\/r\/(?:Case\/)?(500[A-Za-z0-9]{12,15})\//);
    if (!match) {
      throw new Error(`Could not read the new case Id from ${this.page.url()}`);
    }
    return match[1];
  }

  async expectRequiredFieldError(fieldLabel: string): Promise<void> {
    // The field is flagged inline in every org; some orgs also show a "We hit a snag." summary.
    await expect(this.dialog.getByRole('combobox', { name: fieldLabel })).toHaveAttribute('aria-invalid', 'true');
    await expect(this.dialog.getByText('Complete this field.').first()).toBeVisible();
    await expect(this.dialog, 'The modal must stay open when validation fails').toBeVisible();
  }

  async cancel(): Promise<void> {
    await this.dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
    await expect(this.dialog).toBeHidden();
  }
}
