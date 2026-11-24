import Testing
@testable import Core

@Suite("Session")
struct SessionTests {
    @Test func loginFormMirrorsBackendSchema() throws {
        try LoginForm.validate(customerCode: " 100000001 ", password: "changeme123")
        #expect(throws: LoginFormError.customerCodeTooShort) {
            try LoginForm.validate(customerCode: "  12  ", password: "changeme123")
        }
        #expect(throws: LoginFormError.passwordTooShort) {
            try LoginForm.validate(customerCode: "100000001", password: "1234567")
        }
        #expect(LoginForm.normalizedCustomerCode(" 100000001\n") == "100000001")
    }

    @Test(arguments: [
        (true, true, SessionRestorePolicy.RemoteCheck?.some(.valid), SessionRestorePolicy.Outcome.online),
        (true, true, .some(.unreachable), .offline),
        (true, true, nil, .offline),
        (false, true, .some(.unreachable), .signedOut),
        (true, true, .some(.unauthorized), .signedOut),
        (true, false, nil, .signedOut),
    ])
    func restoreOutcome(
        cached: Bool, credential: Bool,
        remote: SessionRestorePolicy.RemoteCheck?, expected: SessionRestorePolicy.Outcome
    ) {
        #expect(SessionRestorePolicy.outcome(hasCachedSummary: cached, hasCredential: credential, remote: remote) == expected)
    }

    @Test func checksRemoteOnlyWithCredential() {
        #expect(SessionRestorePolicy.shouldCheckRemote(hasCredential: true))
        #expect(!SessionRestorePolicy.shouldCheckRemote(hasCredential: false))
    }
}
