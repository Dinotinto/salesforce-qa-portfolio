/**
 * Tests for the Agentforce case actions. These cover the guardrails the agent
 * relies on; agent-tests/ then checks that the agent actually uses them.
 */
@IsTest
private class CaseAgentActionsTest {

    static final String OWNER_EMAIL = 'ada.balewa@ursamajor.test';
    static final String OTHER_EMAIL = 'someone.else@example.test';

    @TestSetup
    static void setup() {
        Contact owner = CaseTestFactory.newContactWithAccount(OWNER_EMAIL);
        CaseTestFactory.newCaseFor(owner, 'Inverter offline', 'New');
        CaseTestFactory.newCaseFor(owner, 'Old billing question', 'Closed');
    }

    static Case openCase() {
        return [SELECT Id, CaseNumber, Status, Priority, LastModifiedDate, Escalation_Reason__c
                FROM Case WHERE Subject = 'Inverter offline' LIMIT 1];
    }

    static Case closedCase() {
        return [SELECT Id, CaseNumber, Status FROM Case WHERE Subject = 'Old billing question' LIMIT 1];
    }

    static GetCaseStatusAction.Result status(String caseNumber, String email) {
        GetCaseStatusAction.Request req = new GetCaseStatusAction.Request();
        req.caseNumber = caseNumber;
        req.customerEmail = email;
        return GetCaseStatusAction.getStatus(new List<GetCaseStatusAction.Request>{ req })[0];
    }

    static EscalateCaseAction.Result escalate(String caseNumber, String email, String reason) {
        EscalateCaseAction.Request req = new EscalateCaseAction.Request();
        req.caseNumber = caseNumber;
        req.customerEmail = email;
        req.reason = reason;
        return EscalateCaseAction.escalate(new List<EscalateCaseAction.Request>{ req })[0];
    }

    // ---------------------------------------------------------------- Get Case Status

    @IsTest
    static void verifiedCustomerGetsAccurateStatus() {
        Case c = openCase();
        GetCaseStatusAction.Result r = status(c.CaseNumber, OWNER_EMAIL);
        Assert.isTrue(r.found);
        Assert.areEqual(c.CaseNumber, r.caseNumber);
        Assert.areEqual('New', r.status);
        Assert.areEqual('Medium', r.priority);
        Assert.isTrue(r.message.contains(c.CaseNumber) && r.message.contains('New'));
    }

    @IsTest
    static void caseNumberIsNormalised() {
        Case c = openCase();
        String shortForm = '#' + String.valueOf(Integer.valueOf(c.CaseNumber));
        Assert.isTrue(status(shortForm, OWNER_EMAIL).found, 'Short case numbers like #1026 should work');
        Assert.isTrue(status(c.CaseNumber, '  ' + OWNER_EMAIL.toUpperCase() + ' ').found,
            'Email match should ignore case and whitespace');
    }

    @IsTest
    static void wrongEmailRevealsNothing() {
        Case c = openCase();
        GetCaseStatusAction.Result r = status(c.CaseNumber, OTHER_EMAIL);
        Assert.isFalse(r.found);
        Assert.isNull(r.status, 'No status may leak to an unverified caller');
        Assert.isNull(r.subject, 'No subject may leak to an unverified caller');
        Assert.areEqual(CaseAgentGateway.NOT_FOUND_MESSAGE, r.message);
    }

    @IsTest
    static void unknownCaseLooksIdenticalToSomeoneElsesCase() {
        GetCaseStatusAction.Result unknown = status('99999999', OWNER_EMAIL);
        GetCaseStatusAction.Result notYours = status(openCase().CaseNumber, OTHER_EMAIL);
        Assert.areEqual(notYours.message, unknown.message, 'Responses must not allow case-number enumeration');
        Assert.areEqual(notYours.found, unknown.found);
    }

    @IsTest
    static void garbageInputIsHandled() {
        for (String bad : new List<String>{ null, '', 'abc', '123456789012' }) {
            Assert.isFalse(status(bad, OWNER_EMAIL).found, 'Bad case number: ' + bad);
        }
        Assert.isFalse(status(openCase().CaseNumber, null).found, 'Missing email must not match');
    }

    // ---------------------------------------------------------------- Escalate Case

    @IsTest
    static void verifiedCustomerCanEscalateOpenCase() {
        Case c = openCase();
        EscalateCaseAction.Result r = escalate(c.CaseNumber, OWNER_EMAIL, 'No power for two days');
        Assert.isTrue(r.escalated);
        Case after = openCase();
        Assert.areEqual('Escalated', after.Status);
        Assert.areEqual('High', after.Priority);
        Assert.areEqual('No power for two days', after.Escalation_Reason__c);
    }

    @IsTest
    static void unverifiedCallerCannotEscalate() {
        Case before = openCase();
        EscalateCaseAction.Result r = escalate(before.CaseNumber, OTHER_EMAIL, 'Escalate this now');
        Assert.isFalse(r.escalated);
        Assert.isNull(r.status, 'No status may leak to an unverified caller');
        Case after = openCase();
        Assert.areEqual(before.Status, after.Status, 'Record must not change');
        Assert.areEqual(before.LastModifiedDate, after.LastModifiedDate, 'Record must not be touched at all');
    }

    @IsTest
    static void closedCaseIsNotEscalatedOrReopened() {
        Case c = closedCase();
        EscalateCaseAction.Result r = escalate(c.CaseNumber, OWNER_EMAIL, 'Please reopen');
        Assert.isFalse(r.escalated);
        Assert.isTrue(r.message.contains('closed'));
        Assert.areEqual('Closed', closedCase().Status);
    }

    @IsTest
    static void reasonIsRequired() {
        Case c = openCase();
        EscalateCaseAction.Result r = escalate(c.CaseNumber, OWNER_EMAIL, '   ');
        Assert.isFalse(r.escalated);
        Assert.areEqual('New', openCase().Status);
    }

    @IsTest
    static void alreadyEscalatedCaseIsNotUpdatedAgain() {
        Case c = openCase();
        escalate(c.CaseNumber, OWNER_EMAIL, 'First reason');
        Case afterFirst = openCase();

        EscalateCaseAction.Result second = escalate(c.CaseNumber, OWNER_EMAIL, 'Second reason');
        Assert.isFalse(second.escalated);
        Assert.areEqual('First reason', openCase().Escalation_Reason__c, 'Original reason must be kept');
        Assert.areEqual(afterFirst.LastModifiedDate, openCase().LastModifiedDate);
    }

    @IsTest
    static void bulkRequestsAreHandledInOneTransaction() {
        Case c = openCase();
        List<EscalateCaseAction.Request> reqs = new List<EscalateCaseAction.Request>();
        for (Integer i = 0; i < 200; i++) {
            EscalateCaseAction.Request req = new EscalateCaseAction.Request();
            req.caseNumber = c.CaseNumber;
            req.customerEmail = Math.mod(i, 2) == 0 ? OWNER_EMAIL : OTHER_EMAIL;
            req.reason = 'Bulk ' + i;
            reqs.add(req);
        }
        Test.startTest();
        List<EscalateCaseAction.Result> results = EscalateCaseAction.escalate(reqs);
        Test.stopTest();

        Integer escalatedCount = 0;
        for (EscalateCaseAction.Result r : results) {
            if (r.escalated) {
                escalatedCount++;
            }
        }
        Assert.areEqual(200, results.size());
        Assert.areEqual(1, escalatedCount, 'The same case must be escalated exactly once');
        Assert.areEqual('Bulk 0', openCase().Escalation_Reason__c);
    }
}
