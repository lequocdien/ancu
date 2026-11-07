import SwiftUI

/// Ghim dự án. Là content: hình tròn màu đặc, viền trắng 2pt, shadow — KHÔNG dùng kính (spec mục 6).
struct ProjectPinView: View {
    let project: Project
    let catalog: LookupCatalog
    var isSelected = false

    var body: some View {
        let color = catalog.color(for: project.status)
        Image(systemName: catalog.symbolName(for: project.status, default: "house.fill"))
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            .pulsing(project.status == .acceptingApplications && !isSelected)
            .scaleEffect(isSelected ? 1.3 : 1)
            .animation(Motion.snappy, value: isSelected)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "\(project.name), \(catalog.label(for: project.status))"))
            .accessibilityAddTraits(.isButton)
    }
}

/// Cụm nhiều dự án khi zoom out. Màu brand trung tính, không theo trạng thái (cụm có thể lẫn trạng thái).
struct ClusterView: View {
    let cluster: ProjectCluster

    var body: some View {
        Text(cluster.projects.count, format: .number)
            .font(.callout.weight(.bold).monospacedDigit())
            .foregroundStyle(Color.onBrandPrimary)
            .frame(minWidth: 36, minHeight: 36)
            .padding(.horizontal, Spacing.xs)
            .background(Color.brandPrimary, in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            .accessibilityElement()
            .accessibilityLabel(Text("\(cluster.projects.count) dự án"))
            .accessibilityHint(Text("Phóng to để xem từng dự án"))
            .accessibilityAddTraits(.isButton)
    }
}
