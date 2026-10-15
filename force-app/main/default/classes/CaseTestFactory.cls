/**
 * Builds the test personas and data shared by the Apex test classes.
 *
 * Personas start on the "Minimum Access - Salesforce" profile (no object access
 * at all) so that everything they can do comes from the permission set under
 * test. That keeps the security assertions honest.
 */
@IsTest
public class CaseTestFactory {

    public static final String PERSONA_PREFIX = 'QAPortfolio_';
    public static final String MIN_ACCESS_PROFILE = 'Minimum Access - Salesforce';

    public static User newUser(String persona) {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = :MIN_ACCESS_PROFILE LIMIT 1];
        if (profiles.isEmpty()) {
            throw new IllegalArgumentException(
                'Profile "' + MIN_ACCESS_PROFILE + '" not found. It ships with all recent orgs; ' +
                'the security tests depend on it so personas start with zero access.');
        }
        String unique = persona.toLowerCase() + '.' + UserInfo.getOrganizationId() + '.' +
            String.valueOf(Datetime.now().getTime()) + '.' + String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        return new User(
            ProfileId = profiles[0].Id,
            LastName = PERSONA_PREFIX + persona,
            FirstName = 'Test',
            Alias = persona.left(8),
            Email = persona.toLowerCase() + '@qa-portfolio.test',
            Username = unique.left(70) + '@qa-portfolio.test',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Africa/Lagos'
        );
    }

    /** Inserts users and permission set assignments as the current admin (avoids mixed DML). */
    public static Map<String, User> createPersonas(Map<String, String> permSetByPersona) {
        Map<String, User> users = new Map<String, User>();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            for (String persona : permSetByPersona.keySet()) {
                users.put(persona, newUser(persona));
            }
            insert users.values();

            Set<String> names = new Set<String>(permSetByPersona.values());
            names.remove(null);
            Map<String, Id> psIds = new Map<String, Id>();
            for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN :names]) {
                psIds.put(ps.Name, ps.Id);
            }
            List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
            for (String persona : permSetByPersona.keySet()) {
                String psName = permSetByPersona.get(persona);
                if (psName == null) {
                    continue;
                }
                if (!psIds.containsKey(psName)) {
                    throw new IllegalArgumentException('Permission set ' + psName + ' is not deployed.');
                }
                psas.add(new PermissionSetAssignment(AssigneeId = users.get(persona).Id, PermissionSetId = psIds.get(psName)));
            }
            insert psas;
        }
        return users;
    }

    public static User persona(String persona) {
        return [SELECT Id, Username FROM User WHERE LastName = :(PERSONA_PREFIX + persona) ORDER BY CreatedDate DESC LIMIT 1];
    }

    public static Contact newContactWithAccount(String email) {
        Account a = new Account(Name = 'QA Portfolio Customer ' + email);
        insert a;
        Contact c = new Contact(LastName = 'Customer', FirstName = 'QA', Email = email, AccountId = a.Id);
        insert c;
        return c;
    }

    public static Case newCaseFor(Contact contact, String subject, String status) {
        Case c = new Case(
            Subject = subject,
            Status = status,
            Priority = 'Medium',
            Origin = 'Web',
            ContactId = contact.Id,
            AccountId = contact.AccountId
        );
        insert c;
        return [SELECT Id, CaseNumber, Status, Priority, IsClosed, Escalation_Reason__c, LastModifiedDate
                FROM Case WHERE Id = :c.Id];
    }

    public static Boolean caseSharingIsPrivate() {
        List<EntityDefinition> defs = [
            SELECT InternalSharingModel FROM EntityDefinition WHERE QualifiedApiName = 'Case' LIMIT 1
        ];
        return !defs.isEmpty() && defs[0].InternalSharingModel == 'Private';
    }
}
