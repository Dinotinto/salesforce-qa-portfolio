/**
 * Resolves WHO the customer is from trusted platform context, never from what
 * the customer types.
 *
 * The agent actions receive the conversation's MessagingSession Id as a context
 * variable (mapped in Agentforce Builder from the session, not from user input).
 * The verified contact is read from MessagingSession -> MessagingEndUser.ContactId,
 * which the platform sets when the end user is authenticated or verified. A
 * customer who merely claims an email address or case number gains nothing.
 *
 * Runs without sharing because the agent's running user can't see MessagingSession
 * rows through sharing; it only ever reads one field of one session the caller names.
 *
 * Tests swap in a fake resolver through the @TestVisible instance.
 */
public virtual without sharing class CustomerIdentity {

    @TestVisible
    private static CustomerIdentity instance = new CustomerIdentity();

    /** Returns the verified Contact Id for a trusted session key, or null if there is none. */
    public static Id verifiedContactId(String sessionKey) {
        return instance.resolve(sessionKey);
    }

    protected virtual Id resolve(String sessionKey) {
        Id sessionId = toId(sessionKey);
        if (sessionId == null) {
            return null;
        }
        try {
            // Dynamic SOQL so the class compiles in orgs without Messaging enabled.
            List<SObject> rows = Database.query(
                'SELECT MessagingEndUser.ContactId FROM MessagingSession WHERE Id = :sessionId LIMIT 1'
            );
            if (rows.isEmpty()) {
                return null;
            }
            SObject endUser = rows[0].getSObject('MessagingEndUser');
            return endUser == null ? null : (Id) endUser.get('ContactId');
        } catch (Exception e) {
            return null; // no Messaging in this org, or no access: treat as unverified
        }
    }

    @TestVisible
    private static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value.trim());
        } catch (Exception e) {
            return null;
        }
    }
}
