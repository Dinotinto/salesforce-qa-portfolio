/**
 * Agentforce action: escalate a verified customer's open case.
 *
 * Guardrails (each one has a matching Apex test and agent test):
 *   - the customer must be the case's contact, otherwise nothing changes;
 *   - closed cases are never reopened or escalated;
 *   - a reason is required, so every escalation is explainable;
 *   - an already-escalated case is not updated again.
 */
public with sharing class EscalateCaseAction {

    public class Request {
        @InvocableVariable(label='Case Number' description='The case number the customer gave.' required=true)
        public String caseNumber;

        @InvocableVariable(label='Verified Customer Email' description='The email address the customer verified earlier in this conversation.' required=true)
        public String customerEmail;

        @InvocableVariable(label='Reason' description='The customer\'s reason for escalating, in their own words.' required=true)
        public String reason;
    }

    public class Result {
        @InvocableVariable(label='Escalated' description='True only when this call changed the case to Escalated.')
        public Boolean escalated;

        @InvocableVariable(label='Status' description='The case status after this call, when the case belongs to the customer.')
        public String status;

        @InvocableVariable(label='Message' description='A customer-safe sentence the agent can pass on as-is.')
        public String message;
    }

    @InvocableMethod(
        label='Escalate Case'
        description='Escalates an open support case for a verified customer and records why. Refuses closed cases and cases that belong to someone else.'
        category='Case Management'
    )
    public static List<Result> escalate(List<Request> requests) {
        Set<String> numbers = new Set<String>();
        for (Request req : requests) {
            String n = CaseAgentGateway.normalizeCaseNumber(req.caseNumber);
            if (n != null) {
                numbers.add(n);
            }
        }
        Map<String, Case> cases = CaseAgentGateway.findCasesByNumber(numbers);

        Map<Id, String> toEscalate = new Map<Id, String>();
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Case c = cases.get(CaseAgentGateway.normalizeCaseNumber(req.caseNumber));
            Result r = new Result();
            r.escalated = false;

            if (!CaseAgentGateway.isVerifiedContact(c, req.customerEmail)) {
                r.message = CaseAgentGateway.NOT_FOUND_MESSAGE;
            } else if (c.IsClosed) {
                r.status = c.Status;
                r.message = 'Case ' + c.CaseNumber + ' is closed, so it can\'t be escalated. ' +
                    'I can open a new case for you instead.';
            } else if (String.isBlank(req.reason)) {
                r.status = c.Status;
                r.message = 'Please tell me why you\'d like case ' + c.CaseNumber + ' escalated.';
            } else if (c.Status == CaseService.STATUS_ESCALATED || toEscalate.containsKey(c.Id)) {
                r.status = CaseService.STATUS_ESCALATED;
                r.message = 'Case ' + c.CaseNumber + ' is already escalated. A specialist is reviewing it.';
            } else {
                toEscalate.put(c.Id, req.reason.trim());
                r.escalated = true;
                r.status = CaseService.STATUS_ESCALATED;
                r.message = 'I\'ve escalated case ' + c.CaseNumber + '. A specialist will review it with high priority.';
            }
            results.add(r);
        }

        CaseAgentGateway.applyEscalations(toEscalate);
        return results;
    }
}
