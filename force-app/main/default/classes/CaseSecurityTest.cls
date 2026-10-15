/**
 * Role-based security suite: object permissions, field-level security and
 * record sharing for the three support personas.
 *
 *   agentA / agentB  -> Support_Agent  (create/read/edit own cases, Internal Notes)
 *   viewer           -> Support_Viewer (read-only, no Internal Notes)
 *   noAccess         -> no permission set (Minimum Access profile only)
 */
@IsTest
private class CaseSecurityTest {

    @TestSetup
    static void setup() {
        CaseTestFactory.createPersonas(new Map<String, String>{
            'agentA'   => 'Support_Agent',
            'agentB'   => 'Support_Agent',
            'viewer'   => 'Support_Viewer',
            'noAccess' => null
        });
    }

    private static Case createCaseAs(User u, String subject) {
        Case c;
        System.runAs(u) {
            c = CaseService.createCase(subject, 'Created by ' + u.Username, null, 'Medium');
        }
        return c;
    }

    // ---------------------------------------------------------------- object access

    @IsTest
    static void agentCanCreateReadAndEscalateOwnCase() {
        User agentA = CaseTestFactory.persona('agentA');
        Case c = createCaseAs(agentA, 'Inverter fault');

        System.runAs(agentA) {
            Test.startTest();
            Case escalated = CaseService.escalate(c.Id, 'Customer has no power');
            Test.stopTest();

            Assert.areEqual('Escalated', escalated.Status, 'Agent should be able to escalate their own case');
            Assert.areEqual('High', escalated.Priority, 'Escalation should raise priority');
            Assert.areEqual('Customer has no power', escalated.Escalation_Reason__c);
        }
    }

    @IsTest
    static void agentCannotDeleteCases() {
        User agentA = CaseTestFactory.persona('agentA');
        Case c = createCaseAs(agentA, 'Delete attempt');

        System.runAs(agentA) {
            Assert.isFalse(Schema.SObjectType.Case.isDeletable(), 'Support_Agent must not grant Case delete');
            Boolean blocked = false;
            try {
                delete as user new Case(Id = c.Id);
            } catch (Exception e) {
                blocked = true;
            }
            Assert.isTrue(blocked, 'Deleting a case as an agent should be blocked');
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Case WHERE Id = :c.Id], 'Case should still exist');
    }

    @IsTest
    static void userWithoutPermissionSetCannotCreateOrReadCases() {
        User noAccess = CaseTestFactory.persona('noAccess');
        Case adminCase = new Case(Subject = 'Admin case', Status = 'New', Origin = 'Phone');
        insert adminCase;

        System.runAs(noAccess) {
            Assert.isFalse(Schema.SObjectType.Case.isCreateable(), 'No permission set means no create');
            Assert.isFalse(Schema.SObjectType.Case.isAccessible(), 'No permission set means no read');

            Boolean createBlocked = false;
            try {
                CaseService.createCase('Should fail', null, null, null);
            } catch (Exception e) {
                createBlocked = true;
            }
            Assert.isTrue(createBlocked, 'Create should be blocked');

            Boolean readBlocked = false;
            try {
                CaseService.getCase(adminCase.Id);
            } catch (Exception e) {
                readBlocked = true;
            }
            Assert.isTrue(readBlocked, 'Read should be blocked');
        }
    }

    @IsTest
    static void viewerCanReadSharedCaseButCannotEditIt() {
        assumeCaseSharingIsPrivate();
        User agentA = CaseTestFactory.persona('agentA');
        User viewer = CaseTestFactory.persona('viewer');
        Case c = createCaseAs(agentA, 'Shared with viewer');
        insert new CaseShare(CaseId = c.Id, UserOrGroupId = viewer.Id, CaseAccessLevel = 'Read');

        System.runAs(viewer) {
            Case seen = CaseService.getCase(c.Id);
            Assert.areEqual('Shared with viewer', seen.Subject, 'Viewer should read a case shared with them');

            Assert.isFalse(Schema.SObjectType.Case.isUpdateable(), 'Support_Viewer must be read-only');
            Boolean blocked = false;
            try {
                CaseService.escalate(c.Id, 'Viewer trying to escalate');
            } catch (Exception e) {
                blocked = true;
            }
            Assert.isTrue(blocked, 'Viewer must not be able to escalate');
        }
        Assert.areEqual('New', [SELECT Status FROM Case WHERE Id = :c.Id].Status, 'Case must be unchanged');
    }

    // ---------------------------------------------------------------- record sharing

    @IsTest
    static void agentCannotSeeAnotherAgentsCase() {
        assumeCaseSharingIsPrivate();
        User agentA = CaseTestFactory.persona('agentA');
        User agentB = CaseTestFactory.persona('agentB');
        Case c = createCaseAs(agentA, 'Private to agent A');

        System.runAs(agentB) {
            Boolean hidden = false;
            try {
                CaseService.getCase(c.Id);
            } catch (CaseService.CaseServiceException e) {
                hidden = true;
                Assert.isTrue(e.getMessage().contains('not found or you do not have access'),
                    'Message should not reveal whether the case exists');
            }
            Assert.isTrue(hidden, 'Agent B must not see agent A\'s case under Private sharing');
            Assert.areEqual(0, [SELECT COUNT() FROM Case WHERE Id = :c.Id WITH USER_MODE],
                'User-mode SOQL should return nothing for agent B');
        }
    }

    @IsTest
    static void agentCannotEscalateAnotherAgentsCase() {
        assumeCaseSharingIsPrivate();
        User agentA = CaseTestFactory.persona('agentA');
        User agentB = CaseTestFactory.persona('agentB');
        Case c = createCaseAs(agentA, 'Do not touch');

        System.runAs(agentB) {
            Boolean blocked = false;
            try {
                CaseService.escalate(c.Id, 'Not my case');
            } catch (Exception e) {
                blocked = true;
            }
            Assert.isTrue(blocked, 'Agent B must not escalate agent A\'s case');
        }
        Assert.areEqual('New', [SELECT Status FROM Case WHERE Id = :c.Id].Status);
    }

    // ---------------------------------------------------------------- field-level security

    @IsTest
    static void viewerCannotReadInternalNotes() {
        assumeCaseSharingIsPrivate();
        User agentA = CaseTestFactory.persona('agentA');
        User viewer = CaseTestFactory.persona('viewer');
        Case c = createCaseAs(agentA, 'Has internal notes');
        System.runAs(agentA) {
            CaseService.addInternalNote(c.Id, 'Customer threatened to churn');
        }
        insert new CaseShare(CaseId = c.Id, UserOrGroupId = viewer.Id, CaseAccessLevel = 'Read');

        List<Case> rawRows = [SELECT Id, Subject, Internal_Notes__c FROM Case WHERE Id = :c.Id];

        System.runAs(viewer) {
            Assert.isFalse(Schema.SObjectType.Case.fields.Internal_Notes__c.isAccessible(),
                'Internal Notes must be hidden from viewers');

            Boolean blocked = false;
            try {
                CaseService.getInternalNotes(c.Id);
            } catch (QueryException e) {
                blocked = true;
            }
            Assert.isTrue(blocked, 'User-mode query of Internal Notes should fail for a viewer');

            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.READABLE, rawRows);
            Assert.isTrue(decision.getRemovedFields().get('Case').contains('Internal_Notes__c'),
                'stripInaccessible should remove Internal Notes for a viewer');
            Assert.isFalse(decision.getRecords()[0].isSet('Internal_Notes__c'));
        }
    }

    @IsTest
    static void agentCanReadAndWriteInternalNotesOnOwnCase() {
        User agentA = CaseTestFactory.persona('agentA');
        Case c = createCaseAs(agentA, 'Notes round trip');

        System.runAs(agentA) {
            Assert.isTrue(Schema.SObjectType.Case.fields.Internal_Notes__c.isUpdateable());
            CaseService.addInternalNote(c.Id, 'Called customer back');
            Assert.isTrue(CaseService.getInternalNotes(c.Id).contains('Called customer back'));
        }
    }

    @IsTest
    static void viewerCannotEditEscalationReason() {
        User viewer = CaseTestFactory.persona('viewer');
        System.runAs(viewer) {
            Assert.isTrue(Schema.SObjectType.Case.fields.Escalation_Reason__c.isAccessible());
            Assert.isFalse(Schema.SObjectType.Case.fields.Escalation_Reason__c.isUpdateable());
        }
    }

    private static void assumeCaseSharingIsPrivate() {
        Assert.isTrue(CaseTestFactory.caseSharingIsPrivate(),
            'Case org-wide default must be Private for the sharing tests. ' +
            'Deploy force-app/main/default/objects/Case/Case.object-meta.xml first.');
    }
}
