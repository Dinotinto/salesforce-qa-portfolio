/**
 * The only place the customer-facing agent touches case data.
 *
 * The Agentforce Service Agent runs as a low-privilege user with no Case access,
 * so this class runs in system mode. It compensates by being deliberately narrow:
 *   - a case is returned only when it belongs to the contact that CustomerIdentity
 *     resolved from trusted session context (never from conversation text);
 *   - "not found" and "not yours" look identical, so the agent can't be used to
 *     discover whether a case number exists;
 *   - the only write is an escalation, which touches exactly three fields and is
 *     idempotent (see CaseService.isEscalated).
 */
public without sharing class CaseAgentGateway {

    public static final String NOT_FOUND_MESSAGE =
        'I couldn\'t find a case with that number on your account. ' +
        'Please check the case number, or I can connect you with a support specialist.';

    /** Normalises "#1026", "case 1026" or "00001026" to the stored 8-digit form. */
    public static String normalizeCaseNumber(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String digits = raw.replaceAll('[^0-9]', '');
        if (String.isBlank(digits) || digits.length() > 8) {
            return null;
        }
        return digits.leftPad(8, '0');
    }

    public static Map<String, Case> findCasesByNumber(Set<String> caseNumbers) {
        Map<String, Case> byNumber = new Map<String, Case>();
        if (caseNumbers == null || caseNumbers.isEmpty()) {
            return byNumber;
        }
        for (Case c : [
            SELECT Id, CaseNumber, Subject, Status, Priority, IsClosed, ContactId, Escalation_Reason__c
            FROM Case
            WHERE CaseNumber IN :caseNumbers
        ]) {
            byNumber.put(c.CaseNumber, c);
        }
        return byNumber;
    }

    /** True only when the case belongs to the verified contact. A null contact never matches. */
    public static Boolean belongsTo(Case c, Id verifiedContactId) {
        return c != null && verifiedContactId != null && c.ContactId == verifiedContactId;
    }

    public static void applyEscalations(Map<Id, String> reasonByCaseId) {
        if (reasonByCaseId == null || reasonByCaseId.isEmpty()) {
            return;
        }
        // Re-read inside the write path so a case escalated since the caller looked is left alone.
        List<Case> updates = new List<Case>();
        for (Case c : [
            SELECT Id, Status, IsClosed FROM Case WHERE Id IN :reasonByCaseId.keySet() FOR UPDATE
        ]) {
            if (c.IsClosed || CaseService.isEscalated(c)) {
                continue;
            }
            updates.add(new Case(
                Id = c.Id,
                Status = CaseService.STATUS_ESCALATED,
                Priority = 'High',
                Escalation_Reason__c = reasonByCaseId.get(c.Id).left(255)
            ));
        }
        update updates;
    }
}
