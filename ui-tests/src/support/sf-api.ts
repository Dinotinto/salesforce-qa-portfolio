import { APIRequestContext, request } from '@playwright/test';
import { accessToken, apiVersion, instanceUrl } from './env';

export interface CaseRecord {
  Id: string;
  CaseNumber: string;
  Subject: string;
  Status: string;
  Priority: string;
  Origin: string | null;
  IsClosed: boolean;
  Escalation_Reason__c?: string | null;
}

/**
 * REST helper the UI tests use as an independent oracle (check what the UI
 * really saved) and for fast setup/cleanup that doesn't go through the UI.
 */
export class SfApi {
  private constructor(private readonly ctx: APIRequestContext) {}

  static async create(): Promise<SfApi> {
    const ctx = await request.newContext({
      baseURL: `${instanceUrl()}/services/data/v${apiVersion()}/`,
      extraHTTPHeaders: { Authorization: `Bearer ${accessToken()}`, Accept: 'application/json' },
    });
    return new SfApi(ctx);
  }

  async dispose(): Promise<void> {
    await this.ctx.dispose();
  }

  async createCase(fields: Record<string, unknown>): Promise<string> {
    const res = await this.ctx.post('sobjects/Case', { data: { Origin: 'Web', Status: 'New', ...fields } });
    if (res.status() !== 201) {
      throw new Error(`create Case failed ${res.status()}: ${await res.text()}`);
    }
    return (await res.json()).id;
  }

  async getCase(id: string): Promise<CaseRecord> {
    const fields = 'Id,CaseNumber,Subject,Status,Priority,Origin,IsClosed';
    const res = await this.ctx.get(`sobjects/Case/${id}`, { params: { fields } });
    if (!res.ok()) {
      throw new Error(`get Case ${id} failed ${res.status()}: ${await res.text()}`);
    }
    return res.json();
  }

  async updateCase(id: string, fields: Record<string, unknown>): Promise<void> {
    const res = await this.ctx.patch(`sobjects/Case/${id}`, { data: fields });
    if (res.status() !== 204) {
      throw new Error(`update Case ${id} failed ${res.status()}: ${await res.text()}`);
    }
  }

  async findCasesBySubjectPrefix(prefix: string): Promise<CaseRecord[]> {
    const escaped = prefix.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
    const soql = `SELECT Id, CaseNumber, Subject, Status, Priority, Origin, IsClosed FROM Case WHERE Subject LIKE '${escaped}%'`;
    const res = await this.ctx.get('query', { params: { q: soql } });
    if (!res.ok()) {
      throw new Error(`query failed ${res.status()}: ${await res.text()}`);
    }
    return (await res.json()).records;
  }

  async deleteCase(id: string): Promise<void> {
    const res = await this.ctx.delete(`sobjects/Case/${id}`);
    if (![204, 404].includes(res.status())) {
      throw new Error(`delete Case ${id} failed ${res.status()}: ${await res.text()}`);
    }
  }
}
