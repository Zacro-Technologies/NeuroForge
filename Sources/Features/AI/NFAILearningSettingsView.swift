import SwiftUI

/// Shared copy for the integrated AI surfaces. Keep the two supported app
/// languages together until these strings join the generated catalog.
enum NFAILearningCopy {
    static func text(_ english: String, _ japanese: String, localeIdentifier: String? = nil) -> String {
        let language = localeIdentifier ?? NFAppLocalization.preferredLanguageCode
        return language.lowercased().hasPrefix("ja") ? japanese : english
    }

    static func connectionFailure(_ error: Error, localeIdentifier: String? = nil) -> String {
        if let error = error as? NFAILearningError {
            let message: (String, String)
            switch error {
            case .disabled:
                message = ("AI is turned off. Enable it in AI settings to ask for an explanation.", "AIはオフになっています。解説を求めるには、AIの設定で有効にしてください。")
            case .notConfigured, .localUnavailable:
                message = ("No model is available. Check AI settings; saved explanations and practice remain available.", "利用できるモデルがありません。AIの設定を確認してください。保存した解説と練習は利用できます。")
            case .invalidConfiguration:
                message = ("Enter the provider's complete HTTPS chat completions endpoint and model identifier.", "プロバイダのチャット補完用の完全なHTTPSエンドポイントとモデルIDを入力してください。")
            case .credentialRequired:
                message = ("Enter an API key for this endpoint.", "このエンドポイントのAPIキーを入力してください。")
            case .credentialStorage:
                message = ("The saved provider could not be accessed. Try saving its settings again.", "保存した接続設定にアクセスできませんでした。設定を保存し直してください。")
            case .authentication:
                message = ("The provider did not accept the key or model access. Check both in AI settings.", "プロバイダがキーまたはモデルへのアクセスを許可しませんでした。AIの設定で両方を確認してください。")
            case .rateLimited:
                message = ("The provider is at its usage limit. Try again later or select an available on-device model.", "プロバイダの利用上限に達しています。時間をおいて試すか、利用可能なオンデバイスモデルを選んでください。")
            case .timedOut:
                message = ("The model took too long to respond. Your question is still here to retry.", "モデルの応答がタイムアウトしました。質問は残っているので、もう一度お試しください。")
            case .connectionFailed, .serverUnavailable:
                message = ("The model could not be reached. Check your connection or try an available on-device model.", "モデルに接続できませんでした。接続を確認するか、利用可能なオンデバイスモデルをお試しください。")
            case .inputTooLarge:
                message = ("This question and its context are too large for the model. Try a shorter question or another model.", "質問と文脈がモデルの上限を超えています。質問を短くするか、別のモデルをお試しください。")
            case .refused:
                message = ("The model could not answer this question. Try rephrasing what you want to understand.", "モデルはこの質問に回答できませんでした。理解したい内容を別の言い方で質問してください。")
            case .invalidSchema, .unsupportedSchema, .outputTooLarge, .invalidResponse, .incompleteResponse:
                message = ("The model did not return a usable explanation. Your question is still here to retry.", "モデルから利用可能な解説が返されませんでした。質問は残っているので、もう一度お試しください。")
            }
            return text(message.0, message.1, localeIdentifier: localeIdentifier)
        }
        if let error = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost].contains(error.code) {
            return text(
                "The model could not be reached. Check your connection, or use an available on-device model.",
                "モデルに接続できませんでした。接続を確認するか、利用可能なオンデバイスモデルを使ってください。",
                localeIdentifier: localeIdentifier
            )
        }
        if let error = error as? URLError, error.code == .timedOut {
            return text("The model took too long to respond. Try again.", "モデルの応答がタイムアウトしました。もう一度お試しください。", localeIdentifier: localeIdentifier)
        }
        return text(
            "The model could not complete this request. Check its availability and your provider settings, then try again.",
            "モデルがリクエストを完了できませんでした。モデルの利用状況と接続設定を確認して、もう一度お試しください。",
            localeIdentifier: localeIdentifier
        )
    }
}

struct NFAILearningSettingsView: View {
    @Environment(AppStore.self) private var store

    @State private var endpoint = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var savedConfiguration: NFAICloudConfiguration?
    @State private var hasSavedCredential = false
    @State private var localAvailable: Bool?
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var isRemovingProvider = false
    @State private var status: String?
    @State private var statusIsError = false
    @State private var operationID: UUID?
    @State private var operationTask: Task<Void, Never>?

    private let service: NFAILearningService

    init(service: NFAILearningService = .shared) {
        self.service = service
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(copy("Learning assistance", "学習サポート"))
                    .font(.headline)
                    .accessibilityHeading(.h3)
                Text(copy(
                    "Use AI for explanations and feedback on written answers. Saved practice stays available offline.",
                    "AIによる解説や記述式回答へのフィードバックを利用できます。保存した練習はオフラインでも使えます。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)

                Picker(copy("Use AI", "AIの利用"), selection: modeBinding) {
                    Text(copy("Automatic", "自動")).tag(AIMode.automatic)
                    Text(copy("On device", "オンデバイス")).tag(AIMode.onDeviceOnly)
                    Text(copy("Off", "オフ")).tag(AIMode.disabled)
                }
                .pickerStyle(.menu)
                .disabled(!store.isOnboardingComplete)
                .accessibilityIdentifier("ai-learning-mode")

                Text(modeExplanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent(copy("On-device model", "オンデバイスモデル"), value: localStatus)
                    .font(.footnote)
                    .accessibilityIdentifier("ai-local-availability")
            }
            .nfCard(cornerRadius: 16, padding: 16)

            VStack(alignment: .leading, spacing: 14) {
                Text(copy("Connected model", "接続するモデル"))
                    .font(.headline)
                    .accessibilityHeading(.h3)
                Text(copy(
                    "Connect a compatible AI provider for learning assistance when online. Enter its full chat completions endpoint and model identifier.",
                    "対応するAIプロバイダに接続すると、オンラインで学習サポートを利用できます。チャット補完の完全なエンドポイントとモデルIDを入力してください。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)

                labeledField(copy("Endpoint", "エンドポイント")) {
                    TextField("https://api.example.com/v1/chat/completions", text: $endpoint)
                        .accessibilityLabel(copy("Provider endpoint", "プロバイダのエンドポイント"))
                        .accessibilityIdentifier("ai-provider-endpoint")
                }
                labeledField(copy("Model", "モデル")) {
                    TextField(copy("Model identifier", "モデルID"), text: $model)
                        .accessibilityIdentifier("ai-provider-model")
                }
                labeledField(copy("API key", "APIキー")) {
                    SecureField(copy("Enter API key", "APIキーを入力"), text: $apiKey)
                        .accessibilityIdentifier("ai-provider-key")
                }
                Text(copy(
                    !hasSavedCredential
                        ? "Your key is saved in the system Keychain."
                        : "Leave the key blank to keep the saved key for this endpoint. Changing the endpoint requires its key.",
                    !hasSavedCredential
                        ? "キーはシステムのキーチェーンに保存されます。"
                        : "このエンドポイントの保存済みキーを使うには、キーを空欄にしてください。エンドポイントを変更する場合は、対応するキーが必要です。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(copy(
                    "Save and check sends one small request to this provider; its normal usage charges may apply.",
                    "「保存して確認」はプロバイダに小さなリクエストを1件送信します。通常の利用料金がかかる場合があります。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { providerActions }
                    VStack(alignment: .leading, spacing: 12) { providerActions }
                }

                if let status {
                    Label(status, systemImage: statusIsError ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(statusIsError ? NFTheme.amberForeground : .secondary)
                        .accessibilityIdentifier("ai-provider-status")
                }
                if isWorking {
                    ProgressView(isRemovingProvider ? copy("Removing provider…", "接続設定を削除中…") : copy("Checking connection…", "接続を確認中…"))
                        .font(.footnote)
                }
            }
            .nfCard(cornerRadius: 16, padding: 16)
            .disabled(isLoading || !store.isOnboardingComplete)
        }
        .task { await loadSettings() }
        .onDisappear {
            operationTask?.cancel()
            operationTask = nil
            operationID = nil
            isWorking = false
            apiKey = ""
        }
    }

    private var modeBinding: Binding<AIMode> {
        Binding(get: { store.profileSnapshot.aiMode }, set: { store.updateAIMode($0) })
    }

    private var modeExplanation: String {
        switch store.profileSnapshot.aiMode {
        case .automatic:
            copy("Use an available model for the task. A connected provider needs an internet connection.", "タスクに利用可能なモデルを使います。接続先のプロバイダにはインターネット接続が必要です。")
        case .onDeviceOnly:
            copy("Use only an available on-device model. Saved practice and exact answer checks work without it.", "利用可能なオンデバイスモデルだけを使います。モデルがなくても、保存済みの練習と正解が明確な回答のチェックは利用できます。")
        case .disabled:
            copy("AI requests are off. Continue saved practice and review earlier explanations.", "AIへのリクエストはオフです。保存済みの練習や以前の解説を利用できます。")
        }
    }

    private var localStatus: String {
        guard let localAvailable else { return copy("Checking availability…", "利用状況を確認中…") }
        return localAvailable ? copy("Available offline", "オフラインで利用可能") : copy("Unavailable on this device", "このデバイスでは利用できません")
    }

    @ViewBuilder
    private var providerActions: some View {
        Button(copy("Save and check", "保存して確認")) { saveAndCheck() }
            .buttonStyle(.borderedProminent)
            .tint(NFTheme.controlTint(for: "indigo"))
            .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
            .disabled(isWorking || endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("ai-provider-save-check")
        if isWorking && !isRemovingProvider {
            Button(copy("Cancel check", "確認をキャンセル")) { cancelOperation() }
                .buttonStyle(.bordered)
        } else if !isWorking && savedConfiguration != nil {
            Button(copy("Remove provider", "接続設定を削除"), role: .destructive) { removeProvider() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ai-provider-remove")
        }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.medium))
            content()
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .disabled(isWorking)
        }
    }

    @MainActor
    private func loadSettings() async {
        defer { isLoading = false }
        do {
            let configuration = try await service.configuration()
            guard !Task.isCancelled else { return }
            savedConfiguration = configuration
            endpoint = configuration?.endpoint.absoluteString ?? ""
            model = configuration?.model ?? ""
            hasSavedCredential = try await service.hasSavedCredential()
        } catch {
            status = copy("Saved provider settings could not be read. Try reopening this section.", "保存した接続設定を読み込めませんでした。このセクションを開き直してください。")
            statusIsError = true
        }
        let availability = await service.availability(mode: .onDeviceOnly)
        guard !Task.isCancelled else { return }
        localAvailable = availability.localAvailable
    }

    private func saveAndCheck() {
        let endpointText = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpointText), url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil else {
            status = copy("Enter a complete HTTPS endpoint without a username, password, or fragment.", "ユーザー名、パスワード、フラグメントを含まない完全なHTTPSエンドポイントを入力してください。")
            statusIsError = true
            return
        }
        let configuration = NFAICloudConfiguration(endpoint: url, model: model.trimmingCharacters(in: .whitespacesAndNewlines), providerName: url.host ?? "Cloud AI")
        let suppliedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID()
        operationID = id
        isWorking = true
        isRemovingProvider = false
        status = nil
        operationTask = Task { @MainActor in
            defer { if operationID == id { isWorking = false; operationTask = nil } }
            do {
                try await service.saveConfiguration(configuration, apiKey: suppliedKey.isEmpty ? nil : suppliedKey)
                guard operationID == id, !Task.isCancelled else { return }
                savedConfiguration = configuration
                hasSavedCredential = true
                apiKey = ""
                _ = try await service.testConfiguration()
                guard operationID == id, !Task.isCancelled else { return }
                status = copy("Settings saved. The model responded successfully.", "設定を保存しました。モデルから応答がありました。")
                statusIsError = false
            } catch {
                guard operationID == id, !Task.isCancelled else { return }
                status = NFAILearningCopy.connectionFailure(error)
                statusIsError = true
            }
        }
    }

    private func removeProvider() {
        let id = UUID()
        operationID = id
        isWorking = true
        isRemovingProvider = true
        status = nil
        operationTask = Task { @MainActor in
            defer { if operationID == id { isWorking = false; operationTask = nil } }
            do {
                try await service.deleteConfiguration()
                guard operationID == id, !Task.isCancelled else { return }
                savedConfiguration = nil
                hasSavedCredential = false
                endpoint = ""
                model = ""
                apiKey = ""
                status = copy("Provider settings and saved key removed.", "接続設定と保存済みキーを削除しました。")
                statusIsError = false
            } catch {
                guard operationID == id, !Task.isCancelled else { return }
                status = copy("The provider could not be removed. Try again.", "接続設定を削除できませんでした。もう一度お試しください。")
                statusIsError = true
            }
        }
    }

    private func cancelOperation() {
        operationTask?.cancel()
        operationTask = nil
        operationID = nil
        isWorking = false
        status = copy("Connection check canceled.", "接続の確認をキャンセルしました。")
        statusIsError = false
    }

    private func copy(_ english: String, _ japanese: String) -> String {
        NFAILearningCopy.text(english, japanese)
    }
}
