/**
 * Tests for the real identity resolver. CaseAgentActionsTest swaps in a fake;
 * these make sure the real one fails closed for anything that isn't a genuine,
 * verified MessagingSession.
 */
@IsTest
private class CustomerIdentityTest {

    @IsTest
    static void blankOrMalformedKeysResolveToNobody() {
        for (String bad : new List<String>{ null, '', '   ', 'not-an-id', 'ada.balewa@ursamajor.test',
                                            '0Mw\' OR Id != null --' }) {
            Assert.isNull(CustomerIdentity.toId(bad), 'Should not parse: ' + bad);
            Assert.isNull(CustomerIdentity.verifiedContactId(bad), 'Should not resolve: ' + bad);
        }
    }

    @IsTest
    static void wellFormedIdThatIsNotASessionResolvesToNobody() {
        // An attacker who learns a Contact Id and passes it as the "session" gains nothing.
        Contact ada = CaseTestFactory.newContactWithAccount('ada.balewa@ursamajor.test');
        Assert.isNotNull(CustomerIdentity.toId(ada.Id), 'A real Id parses');
        Assert.isNull(CustomerIdentity.verifiedContactId(ada.Id), 'A Contact Id is not a verified session');
        Assert.isNull(CustomerIdentity.verifiedContactId(ada.AccountId), 'An Account Id is not a verified session');
    }

    @IsTest
    static void unknownSessionIdResolvesToNobody() {
        // Right key prefix for MessagingSession, but no such record.
        Assert.isNull(CustomerIdentity.verifiedContactId('0Mw000000000000AAA'));
    }

    @IsTest
    static void idsAreTrimmed() {
        Contact c = CaseTestFactory.newContactWithAccount('trim.test@ursamajor.test');
        Assert.areEqual(c.Id, CustomerIdentity.toId('  ' + c.Id + '  '));
    }
}
