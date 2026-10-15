import { expect, test } from '../src/support/fixtures';

/**
 * Case-management workflows driven through the Lightning UI. Each test checks
 * what the user sees AND what Salesforce actually stored (via the REST API),
 * so a UI that looks right but saves the wrong data still fails.
 */
test.describe('Case management', () => {
  test('agent creates a case from the New Case form', async ({ newCase, caseRecord, api, subject }) => {
    await newCase.open();
    await newCase.fill({
      subject,
      description: 'Inverter shows error E-21 after the storm.',
      priority: 'High',
      origin: 'Phone',
    });
    const caseId = await newCase.saveAndGetId();

    await caseRecord.expectToast(/Case "\d{8}" was created/);
    const saved = await api.getCase(caseId);
    expect(saved).toMatchObject({ Subject: subject, Priority: 'High', Origin: 'Phone', Status: 'New', IsClosed: false });
    await expect(caseRecord.page.getByText(saved.CaseNumber).first()).toBeVisible();
  });

  test('required Case Origin blocks save and nothing is created', async ({ newCase, api, subject }) => {
    await newCase.open();
    await newCase.fill({ subject });

    await newCase.save();

    await newCase.expectRequiredFieldError('Case Origin');
    await newCase.cancel();
    expect(await api.findCasesBySubjectPrefix(subject)).toHaveLength(0);
  });

  test('agent escalates a case with inline edit', async ({ caseRecord, api, subject }) => {
    const caseId = await api.createCase({ Subject: subject, Priority: 'Medium' });
    await caseRecord.open(caseId);

    await caseRecord.inlineEditPicklist('Status', 'Escalated');

    await expect.poll(async () => (await api.getCase(caseId)).Status).toBe('Escalated');
    await caseRecord.expectFieldValue('Status', 'Escalated');
  });

  test('a new open case appears in the All Open Cases list', async ({ caseList, api, subject }) => {
    await api.createCase({ Subject: subject });

    await caseList.open('AllOpenCases');
    await caseList.search(subject);

    await caseList.expectRowWithSubject(subject);
  });

  test('a case closed elsewhere shows as closed and leaves the open list', async ({ caseRecord, caseList, api, subject }) => {
    const caseId = await api.createCase({ Subject: subject });
    await api.updateCase(caseId, { Status: 'Closed' });

    await caseRecord.open(caseId);
    await caseRecord.expectFieldValue('Status', 'Closed');

    await caseList.open('AllOpenCases');
    await caseList.search(subject);
    await caseList.expectNoRowWithSubject(subject);
  });
});
