/**
 * Functional tests for the case lifecycle, run as a Support Agent persona.
 */
@IsTest
private class CaseServiceTest {

    @TestSetup
    static void setup() {
        CaseTestFactory.createPersonas(new Map<String, String>{ 'agent' => 'Support_Agent' });
    }

    @IsTest
    static void createCaseDefaultsStatusOriginAndPriority() {
        System.runAs(CaseTestFactory.persona('agent')) {
            Case c = CaseService.createCase('  Panel cracked  ', 'Hail damage', null, null);
            Case saved = CaseService.getCase(c.Id);
            Assert.areEqual('Panel cracked', saved.Subject, 'Subject should be trimmed');
            Assert.areEqual('New', saved.Status);
            Assert.areEqual('Medium', saved.Priority, 'Priority defaults to Medium');
            Assert.isFalse(saved.IsClosed);
        }
    }

    @IsTest
    static void createCaseRequiresSubject() {
        System.runAs(CaseTestFactory.persona('agent')) {
            for (String blank : new List<String>{ null, '', '   ' }) {
                try {
                    CaseService.createCase(blank, null, null, null);
                    Assert.fail('Blank subject should be rejected: "' + blank + '"');
                } catch (CaseService.CaseServiceException e) {
                    Assert.areEqual('Subject is required.', e.getMessage());
                }
            }
        }
    }

    @IsTest
    static void escalateRequiresReason() {
        System.runAs(CaseTestFactory.persona('agent')) {
            Case c = CaseService.createCase('Needs reason', null, null, 'Low');
            try {
                CaseService.escalate(c.Id, ' ');
                Assert.fail('Escalation without a reason should be rejected');
            } catch (CaseService.CaseServiceException e) {
                Assert.areEqual('An escalation reason is required.', e.getMessage());
            }
            Assert.areEqual('New', CaseService.getCase(c.Id).Status);
        }
    }

    @IsTest
    static void escalationReasonIsTruncatedTo255Characters() {
        System.runAs(CaseTestFactory.persona('agent')) {
            Case c = CaseService.createCase('Long reason', null, null, null);
            Case escalated = CaseService.escalate(c.Id, 'x'.repeat(400));
            Assert.areEqual(255, escalated.Escalation_Reason__c.length());
        }
    }

    @IsTest
    static void closedCaseCannotBeEscalated() {
        System.runAs(CaseTestFactory.persona('agent')) {
            Case c = CaseService.createCase('Resolved already', null, null, null);
            Case closed = CaseService.closeCase(c.Id);
            Assert.isTrue(closed.IsClosed);
            try {
                CaseService.escalate(c.Id, 'Reopen please');
                Assert.fail('Closed cases must not be escalated');
            } catch (CaseService.CaseServiceException e) {
                Assert.areEqual('Closed cases cannot be escalated.', e.getMessage());
            }
        }
    }

    @IsTest
    static void closingAClosedCaseIsANoOp() {
        System.runAs(CaseTestFactory.persona('agent')) {
            Case c = CaseService.createCase('Close twice', null, null, null);
            CaseService.closeCase(c.Id);
            Case again = CaseService.closeCase(c.Id);
            Assert.areEqual('Closed', again.Status);
        }
    }

    @IsTest
    static void getCaseWithUnknownIdGivesGenericMessage() {
        System.runAs(CaseTestFactory.persona('agent')) {
            Id fakeId = Id.valueOf(Case.SObjectType.getDescribe().getKeyPrefix() + '0'.repeat(12));
            try {
                CaseService.getCase(fakeId);
                Assert.fail('Unknown id should throw');
            } catch (CaseService.CaseServiceException e) {
                Assert.areEqual('Case not found or you do not have access to it.', e.getMessage());
            }
        }
    }

    @IsTest
    static void internalNotesAreAppendedWithTimestamps() {
        System.runAs(CaseTestFactory.persona('agent')) {
            Case c = CaseService.createCase('Notes', null, null, null);
            CaseService.addInternalNote(c.Id, 'first');
            CaseService.addInternalNote(c.Id, 'second');
            String notes = CaseService.getInternalNotes(c.Id);
            Assert.isTrue(notes.indexOf('first') < notes.indexOf('second'), 'Notes should be in order');
            Assert.areEqual(2, notes.split('\n').size());
        }
    }
}
