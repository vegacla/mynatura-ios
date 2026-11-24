import APIClient
import SwiftUI

struct LoginScreen: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(BackendSettings.key) private var backendURL = ""

    @State private var customerCode = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @FocusState private var focus: Field?

    private enum Field { case code, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Código de cliente", text: $customerCode)
                        .textContentType(.username)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .code)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Contraseña", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                } footer: {
                    Text("Usa la contraseña de MyNatura, no la de Natura.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Ingresar").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSubmitting || customerCode.isEmpty || password.isEmpty)
                }

                Section {
                    ServerURLField(text: $backendURL)
                } header: {
                    Text("Servidor")
                } footer: {
                    Text("Ejemplo: 192.168.1.10:3000 (PC en la misma Wi‑Fi) o una URL https de túnel.")
                }
            }
            .navigationTitle("MyNatura")
            .onAppear {
                if customerCode.isEmpty { customerCode = session.lastCustomerCode }
                focus = customerCode.isEmpty ? .code : .password
            }
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            let message = await session.login(customerCode: customerCode, password: password)
            isSubmitting = false
            if let message {
                errorMessage = message
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else {
                password = ""
            }
        }
    }
}

/// Campo de URL del servidor, compartido entre Login y Diagnóstico.
struct ServerURLField: View {
    @Binding var text: String

    var body: some View {
        TextField("http://192.168.1.10:3000", text: $text)
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        if !text.isEmpty, BackendURL.parse(text) == nil {
            Text("URL inválida").font(.footnote).foregroundStyle(.red)
        }
    }
}
