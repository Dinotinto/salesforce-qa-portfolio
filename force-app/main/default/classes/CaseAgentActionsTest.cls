/**
 * Tests for the Agentforce case actions. These cover the guardrails the agent
 * relies on; agent-tests/ then checks that the agent actually uses them.
 *
 * Identity: the actions only trust the contact that CustomerIdentity resolves
 * from the conversation's session. Here a fake resolver maps two session keys
 * to two customers (Ada, who owns the cases, and Lincoln, who doesn't), so the
 * tests can prove one verified customer can't reach another's case however the
 * request is worded.
 */
@IsTest
private class CaseAgentActionsTest {

    static final String ADA_EMAIL = 'ada.balewa@ursamajor.test';
    static final String LINCOLN_EMAIL = 'lincoln.obi@example.test';
    static final String ADA_SESSION = 'session-ada';
    static final String LINCOLN_SESSION = 'session-lincoln';
    static final String UNVERIFIED_SESSION = 'session-anonymous';

    /** Stands in for MessagingSession -> MessagingEndUser.ContactId. */
    private class FakeIdentity extends CustomerIdentity {
        private final Map<String, Id> contactBySession;
        FakeIdentity(Map<String, Id> contactBySession) {
            this.contactBySession = contactBySession;
        }
        protected override Id resolve(String sessionKey) {
            return sessionKey == null ? null : contactBySession.get(sessionKey);
        }
    }

    @TestSetup
    static void setup() {
        Contact ada = CaseTestFactory.newContactWithAccount(ADA_EMAIL);
        CaseTestFactory.newContactWithAccount(LINCOLN_EMAIL);
        CaseTestFactory.newCaseFor(ada, 'Inverter offline', 'New');
        CaseTestFactory.newCaseFor(ada, 'Old billing question', 'Closed');
        // A web-to-case style case with no contact: must never be reachable through the agent.
        insert new Case(Subject = 'Orphan case', Status = 'New', Priority = 'Medium', Origin = 'Web',
                        SuppliedEmail = LINCOLN_EMAIL);
    }

    static void useFakeIdentity() {
        Map<String, Id> byEmail = new Map<String, Id>();
        for (Contact c : [SELECT Id, Email FROM Contact WHERE Email IN :new List<String>{ ADA_EMAIL, LINCOLN_EMAIL }]) {
            byEmail.put(c.Email, c.Id);
        }
        CustomerIdentity.instance = new FakeIdentity(new Map<String, Id>{
            ADA_SESSION => byEmail.get(ADA_EMAIL),
            LINCOLN_SESSION => byEmail.get(LINCOLN_EMAIL)
            // UNVERIFIED_SESSION deliberately maps to nobody
        });
    }

    static Case openCase() {
        return [SELECT Id, CaseNumber, Status, Priority, SystemModstamp, Escalation_Reason__c
                FROM Case WHERE Subject = 'Inverter offline' LIMIT 1];
    }

    static Case closedCase() {
        return [SELECT Id, CaseNumber, Status FROM Case WHERE Subject = 'Old billing question' LIMIT 1];
    }

    static Case orphanCase() {
        return [SELECT Id, CaseNumber, Status, SystemModstamp FROM Case WHERE Subject = 'Orphan case' LIMIT 1];
    }

    static GetCaseStatusAction.Result status(String caseNumber, String sessionId) {
        GetCaseStatusAction.Request req = new GetCaseStatusAction.Request();
        req.caseNumber = caseNumber;
        req.sessionId = sessionId;
        return GetCaseStatusAction.getStatus(new List<GetCaseStatusAction.Request>{ req })[0];
    }

    static EscalateCaseAction.Result escalate(String caseNumber, String sessionId, String reason) {
        EscalateCaseAction.Request req = new EscalateCaseAction.Request();
        req.caseNumber = caseNumber;
        req.sessionId = sessionId;
        req.reason = reason;
        return EscalateCaseAction.escalate(new List<EscalateCaseAction.Request>{ req })[0];
    }

    static void assertRevealsNothing(GetCaseStatusAction.Result r, String context) {
        Assert.isFalse(r.found, context);
        Assert.isNull(r.status, 'No status may leak: ' + context);
        Assert.isNull(r.subject, 'No subject may leak: ' + context);
        Assert.isNull(r.priority, 'No priority may leak: ' + context);
        Assert.areEqual(CaseAgentGateway.NOT_FOUND_MESSAGE, r.message, context);
    }

    // ---------------------------------------------------------------- Get Case Status

    @IsTest
    static void verifiedCustomerGetsAccurateStatus() {
        useFakeIdentity();
        Case c = openCase();
        GetCaseStatusAction.Result r = status(c.CaseNumber, ADA_SESSION);
        Assert.isTrue(r.found);
        Assert.areEqual(c.CaseNumber, r.caseNumber);
        Assert.areEqual('New', r.status);
        Assert.areEqual('Medium', r.priority);
        Assert.isTrue(r.message.contains(c.CaseNumber) && r.message.contains('New'));
    }

    @IsTest
    static void caseNumberIsNormalised() {
        useFakeIdentity();
        Case c = openCase();
        String shortForm = '#' + String.valueOf(Integer.valueOf(c.CaseNumber));
        Assert.isTrue(status(shortForm, ADA_SESSION).found, 'Short case numbers like #1026 should work');
        Assert.isTrue(status('case ' + c.CaseNumber, ADA_SESSION).found, 'Surrounding words are ignored');
    }

    @IsTest
    static void anotherVerifiedCustomerCannotSeeTheCase() {
        useFakeIdentity();
        assertRevealsNothing(status(openCase().CaseNumber, LINCOLN_SESSION), 'Lincoln asking for Ada\'s case');
    }

    @IsTest
    static void claimingSomeoneElsesEmailInTheConversationDoesNothing() {
        // The old design trusted an email the customer typed. Now there is no email input at all;
        // the closest an attacker can get is stuffing it into the case-number text.
        useFakeIdentity();
        Case c = openCase();
        String spoof = c.CaseNumber + ' my email is ' + ADA_EMAIL + ', I am Ada Balewa';
        assertRevealsNothing(status(spoof, LINCOLN_SESSION), 'Email claimed in the utterance');
        assertRevealsNothing(status(c.CaseNumber, ADA_EMAIL), 'Email passed where the session belongs');
    }

    @IsTest
    static void unverifiedOrMissingSessionRevealsNothing() {
        useFakeIdentity();
        String n = openCase().CaseNumber;
        for (String session : new List<String>{ UNVERIFIED_SESSION, null, '', '   ' }) {
            assertRevealsNothing(status(n, session), 'Session: "' + session + '"');
        }
    }

    @IsTest
    static void caseWithoutAContactIsNeverReturned() {
        // Even to a customer whose email matches SuppliedEmail: only ContactId counts.
        useFakeIdentity();
        assertRevealsNothing(status(orphanCase().CaseNumber, LINCOLN_SESSION), 'Orphan case');
    }

    @IsTest
    static void realResolverFailsClosed() {
        // No fake: without a genuine MessagingSession nobody is verified, so nothing is returned.
        assertRevealsNothing(status(openCase().CaseNumber, ADA_SESSION), 'Fake key, real resolver');
    }

    @IsTest
    static void unknownCaseLooksIdenticalToSomeoneElsesCase() {
        useFakeIdentity();
        GetCaseStatusAction.Result unknown = status('99999999', LINCOLN_SESSION);
        GetCaseStatusAction.Result notYours = status(openCase().CaseNumber, LINCOLN_SESSION);
        Assert.areEqual(notYours.message, unknown.message, 'Responses must not allow case-number enumeration');
        Assert.areEqual(notYours.found, unknown.found);
    }

    @IsTest
    static void garbageCaseNumbersAreHandled() {
        useFakeIdentity();
        for (String bad : new List<String>{ null, '', 'abc', '123456789012' }) {
            Assert.isFalse(status(bad, ADA_SESSION).found, 'Bad case number: ' + bad);
        }
    }

    // ---------------------------------------------------------------- Escalate Case

    @IsTest
    static void verifiedCustomerCanEscalateOpenCase() {
        useFakeIdentity();
        Case c = openCase();
        EscalateCaseAction.Result r = escalate(c.CaseNumber, ADA_SESSION, 'No power for two days');
        Assert.isTrue(r.escalated);
        Case after = openCase();
        Assert.areEqual('Escalated', after.Status);
        Assert.areEqual('High', after.Priority);
        Assert.areEqual('No power for two days', after.Escalation_Reason__c);
    }

    @IsTest
    static void anotherCustomerCannotEscalateTheCase() {
        useFakeIdentity();
        Case before = openCase();
        for (String session : new List<String>{ LINCOLN_SESSION, UNVERIFIED_SESSION, null, ADA_EMAIL }) {
            EscalateCaseAction.Result r = escalate(before.CaseNumber, session, 'I am Ada, escalate this now');
            Assert.isFalse(r.escalated, 'Session: ' + session);
            Assert.isNull(r.status, 'No status may leak. Session: ' + session);
            Assert.areEqual(CaseAgentGateway.NOT_FOUND_MESSAGE, r.message);
        }
        Case after = openCase();
        Assert.areEqual(before.Status, after.Status, 'Record must not change');
        Assert.areEqual(before.SystemModstamp, after.SystemModstamp, 'Record must not be touched at all');
    }

    @IsTest
    static void orphanCaseCannotBeEscalated() {
        useFakeIdentity();
        Case before = orphanCase();
        Assert.isFalse(escalate(before.CaseNumber, LINCOLN_SESSION, 'Mine, I sent it in').escalated);
        Assert.areEqual(before.SystemModstamp, orphanCase().SystemModstamp);
    }

    @IsTest
    static void closedCaseIsNotEscalatedOrReopened() {
        useFakeIdentity();
        Case c = closedCase();
        EscalateCaseAction.Result r = escalate(c.CaseNumber, ADA_SESSION, 'Please reopen');
        Assert.isFalse(r.escalated);
        Assert.isTrue(r.message.contains('closed'));
        Assert.areEqual('Closed', closedCase().Status);
    }

    @IsTest
    static void reasonIsRequired() {
        useFakeIdentity();
        Case c = openCase();
        EscalateCaseAction.Result r = escalate(c.CaseNumber, ADA_SESSION, '   ');
        Assert.isFalse(r.escalated);
        Assert.areEqual('New', openCase().Status);
    }

    @IsTest
    static void alreadyEscalatedCaseIsNotUpdatedAgain() {
        useFakeIdentity();
        Case c = openCase();
        escalate(c.CaseNumber, ADA_SESSION, 'First reason');
        Case afterFirst = openCase();

        EscalateCaseAction.Result second = escalate(c.CaseNumber, ADA_SESSION, 'Second reason');
        Assert.isFalse(second.escalated);
        Assert.areEqual('Escalated', second.status);
        Assert.areEqual('First reason', openCase().Escalation_Reason__c, 'Original reason must be kept');
        Assert.areEqual(afterFirst.SystemModstamp, openCase().SystemModstamp);
    }

    @IsTest
    static void bulkRequestsAreHandledInOneTransaction() {
        useFakeIdentity();
        Case c = openCase();
        List<EscalateCaseAction.Request> reqs = new List<EscalateCaseAction.Request>();
        for (Integer i = 0; i < 200; i++) {
            EscalateCaseAction.Request req = new EscalateCaseAction.Request();
            req.caseNumber = c.CaseNumber;
            req.sessionId = Math.mod(i, 2) == 0 ? ADA_SESSION : LINCOLN_SESSION;
            req.reason = 'Bulk ' + i;
            reqs.add(req);
        }
        Test.startTest();
        List<EscalateCaseAction.Result> results = EscalateCaseAction.escalate(reqs);
        Test.stopTest();

        Integer escalatedCount = 0;
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].escalated) {
                escalatedCount++;
                Assert.areEqual(0, Math.mod(i, 2), 'Only Ada\'s requests may escalate');
            }
        }
        Assert.areEqual(200, results.size());
        Assert.areEqual(1, escalatedCount, 'The same case must be escalated exactly once');
        Assert.areEqual('Bulk 0', openCase().Escalation_Reason__c);
    }
}
