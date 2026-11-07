import SwiftUI

/// Wizard 4 bước. Thanh tiến độ + nút điều hướng dùng kính; lựa chọn đáp án dùng card nền đặc (spec mục 6).
struct EligibilityWizard: View {
    @State private var viewModel: EligibilityViewModel
    @FocusState private var incomeFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.analytics) private var analytics

    init(viewModel: EligibilityViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            MeshBackground()
            switch viewModel.loadState {
            case .loading:
                ProgressView()
            case .failed:
                ContentUnavailableView {
                    Label("Không tải được bộ câu hỏi", systemImage: "wifi.exclamationmark")
                } actions: {
                    Button("Thử lại") { Task { await viewModel.load() } }
                }
            case .ready:
                if let result = viewModel.result {
                    EligibilityResultView(result: result) {
                        withAnimation(animation) { viewModel.restart() }
                    }
                } else {
                    questionFlow
                }
            }
        }
        .navigationTitle("Kiểm tra điều kiện")
        .navigationBarTitleDisplayMode(.inline)
        .task { if viewModel.catalog.items(in: .eligibilitySubject).isEmpty { await viewModel.load() } }
        // Chỉ gửi mức kết quả — KHÔNG gửi câu trả lời (thu nhập, hôn nhân…).
        .onChange(of: viewModel.result?.level) { _, level in
            guard let level else { return }
            analytics.track(AnalyticsEvent(name: AnalyticsEvent.eligibilityCompleted, props: ["level": String(describing: level)]))
        }
    }

    private var animation: Animation? { Motion.resolve(Motion.snappy, reduceMotion: reduceMotion) }

    private var questionFlow: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.s)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    question
                }
                .padding(Spacing.l)
                .id(viewModel.step)
                .transition(.opacity)
            }
            .scrollDismissesKeyboard(.interactively)

            navigationButtons
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.s)
        }
    }

    private var progressBar: some View {
        HStack(spacing: Spacing.m) {
            ProgressView(value: viewModel.progress)
                .tint(Color.brandPrimary)
            Text("Bước \(viewModel.stepNumber)/\(EligibilityViewModel.Step.allCases.count)")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .adaptiveGlass(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var question: some View {
        switch viewModel.step {
        case .subject:
            title("Bạn thuộc nhóm đối tượng nào?")
            ForEach(viewModel.subjects, id: \.self) { subject in
                option(viewModel.catalog.label(for: subject), isSelected: viewModel.answers.subject == subject) {
                    viewModel.answers.subject = subject
                }
            }
        case .housing:
            title("Tình trạng nhà ở của vợ chồng bạn tại tỉnh/thành có dự án?")
            ForEach(viewModel.housingConditions, id: \.self) { condition in
                option(viewModel.catalog.label(for: condition), isSelected: viewModel.answers.housing == condition) {
                    viewModel.answers.housing = condition
                }
            }
        case .family:
            title("Tình trạng hôn nhân?")
            option(String(localized: "Độc thân"), isSelected: viewModel.answers.family == .single) {
                viewModel.answers.family = .single
            }
            option(String(localized: "Độc thân, đang nuôi con dưới 18 tuổi"),
                   isSelected: viewModel.answers.family == .singleWithMinorChild) {
                viewModel.answers.family = .singleWithMinorChild
            }
            option(String(localized: "Đã kết hôn"), isSelected: viewModel.answers.family == .married) {
                viewModel.answers.family = .married
            }
        case .income:
            incomeQuestion
        }
    }

    @ViewBuilder
    private var incomeQuestion: some View {
        if viewModel.isIncomeExempt {
            title("Thu nhập")
            Text("Nhóm đối tượng của bạn không xét theo trần thu nhập thông thường. Bạn có thể bỏ qua bước này.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            title(viewModel.answers.family == .married
                  ? "Tổng thu nhập bình quân hằng tháng của hai vợ chồng?"
                  : "Thu nhập bình quân hằng tháng của bạn?")
            HStack {
                TextField("Ví dụ: 12,5", text: $viewModel.incomeText)
                    .keyboardType(.decimalPad)
                    .focused($incomeFocused)
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text("triệu đồng/tháng").foregroundStyle(.secondary)
            }
            .padding(Spacing.l)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .onAppear { incomeFocused = true }

            if viewModel.isIncomeInvalid {
                Label("Nhập số triệu đồng, ví dụ 12 hoặc 12,5.", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.brandAccent)
            }
            Text("Thu nhập bình quân 12 tháng gần nhất, theo xác nhận của cơ quan, đơn vị (không có hợp đồng lao động: Công an xã/phường xác nhận). Tỉnh/thành có thể áp hệ số điều chỉnh.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: Spacing.s) {
            if !viewModel.isFirstStep {
                Button {
                    withAnimation(animation) { viewModel.back() }
                } label: {
                    Label("Quay lại", systemImage: "chevron.left")
                }
                .controlSize(.large)
                .adaptiveGlassButton()
            }
            PrimaryButton(title: viewModel.isLastStep ? "Xem kết quả" : "Tiếp", systemImage: nil) {
                incomeFocused = false
                withAnimation(animation) { viewModel.next() }
            }
            .disabled(!viewModel.canAdvance)
        }
    }

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.title3.weight(.bold))
    }

    /// Card nền đặc; đã chọn = viền brand + ✓ (không chỉ dựa vào màu).
    private func option(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                Text(verbatim: label)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Spacing.s)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.brandPrimary : .secondary)
            }
            .padding(Spacing.l)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(isSelected ? Color.brandPrimary : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

struct EligibilityResultView: View {
    let result: EligibilityResult
    let onRestart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                GlassCard(style: .tinted(Self.color(result.level).opacity(0.5))) {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: Self.symbol(result.level))
                            .font(.largeTitle)
                            .foregroundStyle(Self.color(result.level))
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Kết quả").font(.caption).foregroundStyle(.secondary)
                            Text(Self.title(result.level)).font(.title2.weight(.bold))
                        }
                    }
                }

                if result.usesMockRules {
                    Label("Ngưỡng tổng hợp từ báo chí, chưa đối chiếu nguyên văn văn bản pháp luật.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.statusSoon.opacity(0.18), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }

                VStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(result.checks) { check in
                        HStack(alignment: .top, spacing: Spacing.m) {
                            Image(systemName: Self.symbol(check.level))
                                .foregroundStyle(Self.color(check.level))
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(Self.criterionTitle(check.criterion)).font(.subheadline.weight(.semibold))
                                Text(verbatim: check.explanation).font(.subheadline)
                                if !check.legalReference.isEmpty {
                                    Text("Căn cứ: \(check.legalReference)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.s) {
                    Label { Text(verbatim: result.disclaimer) } icon: { Image(systemName: "info.circle") }
                    Label("Câu trả lời không được lưu lên máy chủ.", systemImage: "lock.shield")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button(action: onRestart) {
                    Label("Làm lại", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .adaptiveGlassButton()
            }
            .padding(Spacing.l)
        }
    }

    static func title(_ level: EligibilityLevel) -> LocalizedStringKey {
        switch level {
        case .likelyEligible: "Có thể đủ điều kiện"
        case .needsReview: "Cần kiểm tra thêm"
        case .notEligible: "Chưa đủ điều kiện"
        }
    }

    static func symbol(_ level: EligibilityLevel) -> String {
        switch level {
        case .likelyEligible: "checkmark.circle.fill"
        case .needsReview: "questionmark.circle.fill"
        case .notEligible: "xmark.circle.fill"
        }
    }

    static func color(_ level: EligibilityLevel) -> Color {
        switch level {
        case .likelyEligible: .statusOpen
        case .needsReview: .statusSoon
        case .notEligible: .brandAccent
        }
    }

    static func criterionTitle(_ criterion: EligibilityCheck.Criterion) -> LocalizedStringKey {
        switch criterion {
        case .subject: "Đối tượng"
        case .housing: "Nhà ở"
        case .income: "Thu nhập"
        }
    }
}

#Preview {
    NavigationStack {
        EligibilityWizard(viewModel: EligibilityViewModel(container: .preview))
    }
}
