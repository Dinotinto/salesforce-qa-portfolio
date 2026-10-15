/**
 * The only place the customer-facing agent touches case data.
 *
 * The Agentforce Service Agent runs as a low-privilege user with no Case access,
 * so this class runs in system mode. It compensates by being deliberately narrow:
 *   - a case is returned only when the caller proves they are its contact
 *     (the verified email matches the case's Contact Email or Web Email);
 *   - "not found" and "not yours" look identical, so the agent can't be used to
 *     discover whether a case number exists;
 *   - the only write is an escalation, which touches exactly three fields.
 */
public without sharing class CaseAgentGateway {

    public static final String NOT_FOUND_MESSAGE =
        'I couldn\'t find a case with that number for the email address you verified. ' +
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
            SELECT Id, CaseNumber, Subject, Status, Priority, IsClosed,
                   ContactEmail, SuppliedEmail, Escalation_Reason__c
            FROM Case
            WHERE CaseNumber IN :caseNumbers
        ]) {
            byNumber.put(c.CaseNumber, c);
        }
        return byNumber;
    }

    public static Boolean isVerifiedContact(Case c, String customerEmail) {
        if (c == null || String.isBlank(customerEmail)) {
            return false;
        }
        String email = customerEmail.trim().toLowerCase();
        return (c.ContactEmail != null && c.ContactEmail.toLowerCase() == email)
            || (c.SuppliedEmail != null && c.SuppliedEmail.toLowerCase() == email);
    }

    public static void applyEscalations(Map<Id, String> reasonByCaseId) {
        if (reasonByCaseId == null || reasonByCaseId.isEmpty()) {
            return;
        }
        List<Case> updates = new List<Case>();
        for (Id caseId : reasonByCaseId.keySet()) {
            updates.add(new Case(
                Id = caseId,
                Status = CaseService.STATUS_ESCALATED,
                Priority = 'High',
                Escalation_Reason__c = reasonByCaseId.get(caseId).left(255)
            ));
        }
        update updates;
    }
}
