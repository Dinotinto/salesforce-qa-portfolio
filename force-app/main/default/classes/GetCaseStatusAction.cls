/**
 * Agentforce action: tell a verified customer the status of their case.
 */
public with sharing class GetCaseStatusAction {

    public class Request {
        @InvocableVariable(label='Case Number' description='The case number the customer gave, for example 00001026 or 1026.' required=true)
        public String caseNumber;

        @InvocableVariable(label='Verified Customer Email' description='The email address the customer verified earlier in this conversation.' required=true)
        public String customerEmail;
    }

    public class Result {
        @InvocableVariable(label='Found' description='True only when the case exists and belongs to the verified customer.')
        public Boolean found;

        @InvocableVariable(label='Case Number')
        public String caseNumber;

        @InvocableVariable(label='Status')
        public String status;

        @InvocableVariable(label='Priority')
        public String priority;

        @InvocableVariable(label='Subject')
        public String subject;

        @InvocableVariable(label='Message' description='A customer-safe sentence the agent can pass on as-is.')
        public String message;
    }

    @InvocableMethod(
        label='Get Case Status'
        description='Looks up the status of a support case for a verified customer. Never returns details of a case that belongs to someone else.'
        category='Case Management'
    )
    public static List<Result> getStatus(List<Request> requests) {
        Set<String> numbers = new Set<String>();
        for (Request req : requests) {
            String n = CaseAgentGateway.normalizeCaseNumber(req.caseNumber);
            if (n != null) {
                numbers.add(n);
            }
        }
        Map<String, Case> cases = CaseAgentGateway.findCasesByNumber(numbers);

        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Case c = cases.get(CaseAgentGateway.normalizeCaseNumber(req.caseNumber));
            Result r = new Result();
            if (!CaseAgentGateway.isVerifiedContact(c, req.customerEmail)) {
                r.found = false;
                r.message = CaseAgentGateway.NOT_FOUND_MESSAGE;
            } else {
                r.found = true;
                r.caseNumber = c.CaseNumber;
                r.status = c.Status;
                r.priority = c.Priority;
                r.subject = c.Subject;
                r.message = 'Case ' + c.CaseNumber + ' ("' + c.Subject + '") is ' + c.Status +
                    ' with ' + c.Priority + ' priority.';
            }
            results.add(r);
        }
        return results;
    }
}
