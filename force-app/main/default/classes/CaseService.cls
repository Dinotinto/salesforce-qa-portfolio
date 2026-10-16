/**
 * Case-management service used by the UI, the REST tests and the security suite.
 *
 * Every query and DML statement runs in USER mode, so the caller's object
 * permissions, field-level security and sharing are all enforced. That is what
 * lets CaseSecurityTest prove that a Support Viewer cannot edit a case or read
 * Internal Notes, even though they call exactly the same code as an agent.
 */
public with sharing class CaseService {

    public class CaseServiceException extends Exception {}

    public static final String STATUS_NEW = 'New';
    public static final String STATUS_ESCALATED = 'Escalated';
    public static final String STATUS_CLOSED = 'Closed';

    /** One definition of "already escalated", shared by the service and the agent actions. */
    public static Boolean isEscalated(Case c) {
        return c != null && c.Status == STATUS_ESCALATED;
    }

    public static Case createCase(String subject, String description, Id accountId, String priority) {
        if (String.isBlank(subject)) {
            throw new CaseServiceException('Subject is required.');
        }
        Case c = new Case(
            Subject = subject.trim(),
            Description = description,
            AccountId = accountId,
            Priority = String.isBlank(priority) ? 'Medium' : priority,
            Origin = 'Web',
            Status = STATUS_NEW
        );
        insert as user c;
        return c;
    }

    public static Case getCase(Id caseId) {
        List<Case> rows = [
            SELECT Id, CaseNumber, Subject, Status, Priority, IsClosed, IsEscalated,
                   Escalation_Reason__c, OwnerId
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            // Same message whether the case doesn't exist or isn't shared with the
            // caller, so the response can't be used to discover other users' cases.
            throw new CaseServiceException('Case not found or you do not have access to it.');
        }
        return rows[0];
    }

    public static Case escalate(Id caseId, String reason) {
        if (String.isBlank(reason)) {
            throw new CaseServiceException('An escalation reason is required.');
        }
        Case c = getCase(caseId);
        if (c.IsClosed) {
            throw new CaseServiceException('Closed cases cannot be escalated.');
        }
        if (isEscalated(c)) {
            // Idempotent, like EscalateCaseAction: keep the original reason and leave the record untouched.
            return c;
        }
        Case changes = new Case(
            Id = c.Id,
            Status = STATUS_ESCALATED,
            Priority = 'High',
            Escalation_Reason__c = reason.left(255)
        );
        update as user changes;
        return getCase(caseId);
    }

    public static Case closeCase(Id caseId) {
        Case c = getCase(caseId);
        if (c.IsClosed) {
            return c;
        }
        update as user new Case(Id = c.Id, Status = STATUS_CLOSED);
        return getCase(caseId);
    }

    public static String getInternalNotes(Id caseId) {
        // Throws a QueryException if the caller has no FLS on Internal_Notes__c.
        List<Case> rows = [
            SELECT Id, Internal_Notes__c
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new CaseServiceException('Case not found or you do not have access to it.');
        }
        return rows[0].Internal_Notes__c;
    }

    public static void addInternalNote(Id caseId, String note) {
        String existing = getInternalNotes(caseId);
        String stamp = '[' + System.now().formatGmt('yyyy-MM-dd HH:mm') + ' UTC] ';
        String updated = String.isBlank(existing) ? stamp + note : existing + '\n' + stamp + note;
        update as user new Case(Id = caseId, Internal_Notes__c = updated);
    }
}
