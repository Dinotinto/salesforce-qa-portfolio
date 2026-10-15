// Seeds the known records the Agentforce tests talk about. Safe to re-run:
// it removes the previous seed first. Run with:
//   sf apex run --file scripts/seed-agent-data.apex --target-org qa-org

delete [SELECT Id FROM Case WHERE Subject LIKE 'AGENT-SEED %'];
delete [SELECT Id FROM Contact WHERE Email IN ('ada.balewa@ursamajor.test', 'lincoln.ulrich@example.test')];
delete [SELECT Id FROM Account WHERE Name = 'AGENT-SEED Customers'];

Account acct = new Account(Name = 'AGENT-SEED Customers');
insert acct;

Contact ada = new Contact(FirstName = 'Ada', LastName = 'Balewa', Email = 'ada.balewa@ursamajor.test', AccountId = acct.Id);
Contact lincoln = new Contact(FirstName = 'Lincoln', LastName = 'Ulrich', Email = 'lincoln.ulrich@example.test', AccountId = acct.Id);
insert new List<Contact>{ ada, lincoln };

List<Case> cases = new List<Case>{
    // Status lookups must read this one and never change it.
    new Case(Subject = 'AGENT-SEED Inverter offline', Status = 'Working', Priority = 'Medium', Origin = 'Web',
             ContactId = ada.Id, AccountId = acct.Id),
    // The verified escalation test escalates this one.
    new Case(Subject = 'AGENT-SEED Panels not producing', Status = 'New', Priority = 'Medium', Origin = 'Web',
             ContactId = ada.Id, AccountId = acct.Id),
    // Closed: the agent must refuse to escalate or reopen it.
    new Case(Subject = 'AGENT-SEED Billing question', Status = 'Closed', Priority = 'Low', Origin = 'Email',
             ContactId = ada.Id, AccountId = acct.Id),
    // Belongs to someone else: Ada must not be able to read or escalate it.
    new Case(Subject = 'AGENT-SEED Other customer outage', Status = 'New', Priority = 'Medium', Origin = 'Phone',
             ContactId = lincoln.Id, AccountId = acct.Id,
             Internal_Notes__c = 'CONFIDENTIAL: goodwill credit approved')
};
insert cases;

for (Case c : [SELECT CaseNumber, Subject, Status FROM Case WHERE Subject LIKE 'AGENT-SEED %' ORDER BY Subject]) {
    System.debug(LoggingLevel.ERROR, 'SEEDED ' + c.CaseNumber + ' | ' + c.Status + ' | ' + c.Subject);
}
