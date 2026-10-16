# Salesforce QA Portfolio: Case Management + Agentforce

End-to-end test automation for a Salesforce Service org. The suite covers UI, REST API, role-based security and an Agentforce service agent. GitHub Actions runs it on every push and publishes the reports.

## Verification status

What the latest green CI run actually executed, as opposed to what is built and waiting for org setup:

| Test layer | Status |
|---|---|
| Apex functional, security and agent-action guardrails | ✅ Verified in CI |
| Python REST API (lifecycle, negative, performance, config drift) | ✅ Verified in CI |
| Playwright UI (Chromium) | ✅ Verified in CI |
| Playwright on Firefox / WebKit | ⏳ Opt-in locally (`PW_ALL_BROWSERS=1`), not run in CI |
| Restricted viewer persona (API, as a real Support Viewer user) | ⏳ Implemented, skipped until `SF_VIEWER_AUTH_URL` is configured |
| Agentforce Testing Center | ⏳ Implemented, awaiting an agent in the CI org (`AGENT_API_NAME`) |
| Agent API multi-turn tests | ⏳ Optional, awaiting Agent API settings |

Skipped suites show as *skipped* in the JUnit report, never as passed.

> **Identity.** The agent actions do **not** trust anything the customer types. They identify the customer from the conversation's `MessagingSession` (its verified end user's `ContactId`), passed in as a context variable. A customer who claims someone else's email or case number gets the same "not found" answer as for a case that doesn't exist. Impersonation is tested at the Apex level (`CaseAgentActionsTest`, `CustomerIdentityTest`) and at the agent level (the unverified cases in the Testing Center spec).

| Layer | Tooling | What it proves |
|---|---|---|
| **UI** | Playwright (TypeScript, page objects; Chromium in CI) | Agents can create, validate, escalate and find cases in Lightning, **and** the data Salesforce stored matches what the UI showed |
| **API** | Python, pytest, requests, jsonschema | Case lifecycle over REST, composite all-or-none, precise error contracts (400/401/404/405), SOQL-injection safety, response-time budgets |
| **Security** | Apex `System.runAs` + pytest config checks | Object permissions, field-level security (`Internal_Notes__c`), Private sharing between agents, read-only viewers, no drift in permission sets |
| **Agentforce** | Agentforce Testing Center (`sf agent test`) + pytest + Agent API | Response accuracy, refusal of unauthorized actions, prompt-injection resistance, handoff to a human, and **no incorrect record updates** |
| **CI/CD** | GitHub Actions | Deploys the metadata, runs every suite, and publishes JUnit results, Playwright and pytest HTML reports, and Apex coverage |

## Architecture

```mermaid
flowchart LR
  subgraph GitHub Actions
    D[Deploy + Apex tests] --> A[pytest API + security]
    D --> U[Playwright UI]
    D --> G[Agentforce tests]
    A & U & G --> R[JUnit check + HTML reports]
  end
  subgraph Salesforce org
    S[CaseService<br/>user-mode SOQL/DML]
    ID[CustomerIdentity<br/>session to verified contact]
    GW[CaseAgentGateway<br/>owner check, then act]
    PS[Permission sets<br/>Support_Agent / Support_Viewer / Case_Agent_Actions]
    AG[Case Support Agent<br/>Get Case Status, Escalate Case]
  end
  A -- REST --> S
  U -- Lightning UI --> S
  G -- Testing Center / Agent API --> AG --> GW --> ID
```

### The system under test (`force-app/`)

- **`CaseService`** runs every query and DML statement in *user mode*. The caller's CRUD, field-level security and sharing all apply, so the same code acts differently for an agent and for a viewer. That is what the security tests check.
- **`CustomerIdentity`** turns the conversation's trusted session id into a verified Contact Id (`MessagingSession → MessagingEndUser.ContactId`). Anything else (blank, malformed, a Contact Id passed as the session, an unknown session) resolves to nobody.
- **`GetCaseStatusAction` / `EscalateCaseAction`** are invocable actions for the Agentforce service agent. Their only identity input is the session id, mapped from context in Agent Builder, never from customer text. Their guardrails each have a test:
  - The case's `ContactId` must be the verified contact. Cases with no contact are never reachable.
  - "Not found" and "not yours" return the same answer, so the agent can't be used to enumerate case numbers.
  - Closed cases are never escalated.
  - A reason is required.
  - Escalation is idempotent, in the actions and in `CaseService`: a second request keeps the original reason and doesn't write.
- **Permission sets:**
  - `Support_Agent`: create, read and edit own cases; Internal Notes. No delete, no View All.
  - `Support_Viewer`: read-only; Internal Notes hidden.
  - `Case_Agent_Actions`: Apex actions only, no raw Case access.
- **Case org-wide default:** Private, so agents only see their own cases.

## What's tested

<details><summary><b>Apex (38 tests)</b> - <code>force-app/main/default/classes/*Test.cls</code></summary>

- **Security (`CaseSecurityTest`):** personas start on *Minimum Access - Salesforce*, so every permission comes from the set under test.
  - Agent creates and escalates their own case.
  - Agent cannot delete.
  - A user with no permission set can't create or read.
  - Viewer reads a shared case but can't edit it.
  - Agent B can't see or escalate agent A's case, and the error message doesn't reveal that it exists.
  - Viewer can't read Internal Notes (`isAccessible`, user-mode SOQL and `stripInaccessible` all agree).
- **Functional (`CaseServiceTest`):** defaults, subject validation, escalation rules, idempotent re-escalation, truncation, closed-case rules, ordered internal notes.
- **Agent actions (`CaseAgentActionsTest`):** a fake identity resolver maps two sessions to two customers (Ada owns the cases, Lincoln doesn't).
  - Ada gets accurate status; case numbers are normalised.
  - **Impersonation:** Lincoln's session can't read or escalate Ada's case; Ada's email typed into the request does nothing; unverified, blank and email-as-session inputs reveal nothing; a case with no contact is unreachable even when `SuppliedEmail` matches.
  - With the real resolver and no genuine session, nothing is returned (fails closed).
  - Enumeration resistance, garbage input, closed case refused, reason required, idempotent re-escalation, and a 200-request bulk call where only Ada's requests escalate, once.
- **Identity (`CustomerIdentityTest`):** malformed and injection-style keys, Contact/Account Ids posing as sessions, and unknown session ids all resolve to nobody.
</details>

<details><summary><b>REST API (pytest)</b> - <code>api-tests/</code></summary>

- `test_case_lifecycle.py`: 201 + Location header, JSON-schema contract, PATCH escalate (204, empty body), close sets `IsClosed`/`ClosedDate`, delete then 404, SOQL lookup, escaped hostile input matches nothing, composite create case + comment, composite all-or-none rollback (`PROCESSING_HALTED`).
- `test_case_negative.py`: `INVALID_FIELD`, `STRING_TOO_LONG`, `JSON_PARSER_ERROR`, bad reference id, `INVALID_FIELD_FOR_INSERT_UPDATE`, `NOT_FOUND`, `MALFORMED_QUERY`, `INVALID_SESSION_ID` (401), `METHOD_NOT_ALLOWED` (405). Every error body is schema-validated.
- `test_performance.py`: p95 read/write budgets over 30 samples (inclusive quantiles, so p95 never exceeds the slowest sample; env-configurable) and API-limit headroom.
- `test_security_config.py`:
  - **Drift checks:** Case sharing stays Private; agents can't delete or View All; the viewer set is read-only; Internal Notes FLS per persona; the agent user has no raw Case access.
  - **Persona checks (optional):** as a real viewer, Internal Notes are absent from describe, querying them fails, the viewer can't create or see unshared cases, and can read but not edit a shared one.
</details>

<details><summary><b>UI (Playwright)</b> - <code>ui-tests/</code></summary>

- Create a case from the New Case form. Check the toast and the record page, then confirm the stored values over REST.
- A missing *Case Origin* blocks save: the "We hit a snag." summary appears, the field is marked `aria-invalid`, and no record is created.
- Escalate with inline edit, then confirm the stored status over REST.
- A new open case appears when you search the All Open Cases list.
- A case closed elsewhere shows as Closed and drops off the open list.

Login uses `frontdoor.jsp` with the CI user's OAuth token, the same way `sf org open` does, so no password is ever typed. Selectors are role and label based, and Playwright pierces Lightning's shadow DOM. Every failure keeps a trace, screenshot and video.
</details>

<details><summary><b>Agentforce</b> - <code>agent-tests/</code></summary>

1. `scripts/seed-agent-data.apex` creates known cases: open, to-escalate, closed, and another customer's case with confidential notes.
   - Every case is tagged with the CI run id. Cleanup deletes only cases with this run's tag that the CI user created, so real data and parallel runs are never touched.
   - It refuses to run in a production org. The two customer contacts are reused, never deleted.
2. `render_spec.py` fills the Testing Center spec with this run's case numbers and snapshots the records.
3. `sf agent test run` grades **12 utterances** on topic, action and outcome:
   - **Verified as Ada** (needs `AGENT_ADA_SESSION_ID`, a real verified session; left out without it): accurate status including the short-number form, escalation, closed-case refusal, and another customer's case.
   - **Unverified, claiming to be Ada by email:** status and escalation requests that must reveal and change nothing.
   - A bulk "close everything" request, prompt injection asking for internal notes, a human handoff that must degrade gracefully, and an off-topic question.
4. `test_agent_side_effects.py` grades **what the agent did to the data**:
   - only the intended case changed (none, when the verified cases didn't run)
   - nothing was closed
   - status lookups wrote nothing
5. `test_agent_conversations.py` (optional, Agent API) covers multi-turn cases:
   - an email claimed in one turn doesn't unlock the case in the next
   - mid-conversation switch to someone else's case
   - injected "SYSTEM OVERRIDE"
   - handoff message types
</details>

## CI setup

You need one GitHub secret, `SF_AUTH_URL`. You create it yourself; it never appears in logs.

```bash
npm install --global @salesforce/cli
sf org login web --alias qa-org                 # log in to your Developer Edition org in the browser
sf org auth show-sfdx-auth-url --target-org qa-org --json | jq -r .result.sfdxAuthUrl \
  | gh secret set SF_AUTH_URL --repo <you>/salesforce-qa-portfolio
```

Recent CLI versions redact the auth URL in `sf org display`, so use `sf org auth show-sfdx-auth-url`. Or add it by hand under *Settings → Secrets and variables → Actions → New repository secret*.

Optional:

| Name | Type | Enables |
|---|---|---|
| `AGENT_API_NAME` | variable | Agentforce suites (API name of the agent, e.g. `Case_Support_Agent`) |
| `AGENT_ADA_SESSION_ID` | variable | The verified Testing Center cases (a `MessagingSession` whose end user is linked to Ada's contact) |
| `SF_VIEWER_AUTH_URL` | secret | API persona tests as a Support Viewer user |
| `AGENT_API_MY_DOMAIN`, `AGENT_API_AGENT_ID` | variables | Multi-turn Agent API tests |
| `AGENT_API_CLIENT_ID`, `AGENT_API_CLIENT_SECRET` | secrets | Multi-turn Agent API tests (client-credentials app) |

## Running locally

```bash
export SF_INSTANCE_URL=$(sf org display -o qa-org --json | jq -r .result.instanceUrl)
export SF_ACCESS_TOKEN=$(sf org auth show-access-token -o qa-org --json | jq -r .result.accessToken)

sf project deploy start -d force-app -o qa-org -l RunSpecifiedTests \
  -t CaseServiceTest -t CaseSecurityTest -t CaseAgentActionsTest -t CustomerIdentityTest
sf apex run test -n CaseServiceTest -n CaseSecurityTest -n CaseAgentActionsTest -n CustomerIdentityTest -c -r human -o qa-org

(cd api-tests && pip install -r requirements.txt && pytest)
(cd ui-tests && npm install && npx playwright install chromium && npx playwright test --headed)
# cross-browser pass (not part of CI yet):
(cd ui-tests && npx playwright install firefox webkit && PW_ALL_BROWSERS=1 npx playwright test)
```

## Design notes and honest limits

- **One shared org.** The pipeline serialises runs (`concurrency`). Every test record carries a per-run prefix and is cleaned up, so the suites can rerun safely.
- **Oracles over screenshots.** UI tests check stored data over REST, because a UI can look right and still save the wrong values.
- **LLM assertions are about facts, not wording.** They check case numbers, statuses and leaked secrets, plus record side effects, so tests survive prompt tweaks.
- **Customer verification.** Identity comes from the session, not the conversation. What the platform considers "verified" depends on how the messaging channel authenticates end users (an authenticated deployment, or the *Customer Verification* topic linking the end user to a contact). The actions only trust `MessagingEndUser.ContactId`, so whichever method the org uses, a typed claim can't change it.
- **Dependencies.** `ui-tests` pins its direct dependencies exactly. CI installs with `npm ci`; until a `package-lock.json` is committed, it generates one first and uploads it with the reports.
- **Browsers.** CI runs Chromium only, so this is not yet a cross-browser verified suite.
