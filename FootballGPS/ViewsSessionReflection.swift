//
//  ViewsSessionReflection.swift
//  FootballGPS
//
//  振り返りの表示と入力（機能仕様書 §9.7）。相手や味方など記録に残らない条件を、
//  ユーザーが自分の言葉で残し、2回を比べる画面で読み返せるようにする。
//

import SwiftUI

// MARK: - 詳細画面のカード

struct SessionReflectionCard: View {
    let session: TrainingSession
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(Color.accentColor)
                if let reflection = session.reflection {
                    VStack(alignment: .leading, spacing: 4) {
                        if !reflection.tagLabels.isEmpty {
                            Text(reflection.tagLabels.joined(separator: "・"))
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                        }
                        if let memo = reflection.memo {
                            Text(memo)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .multilineTextAlignment(.leading)
                } else {
                    Text("振り返りを書く")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

// MARK: - 入力シート

struct SessionReflectionSheet: View {
    let session: TrainingSession

    @State private var draft: SessionReflection
    @State private var detent: PresentationDetent = .medium
    @ObservedObject private var dataManager = SessionDataManager.shared
    @Environment(\.dismiss) private var dismiss

    init(session: TrainingSession) {
        self.session = session
        _draft = State(initialValue: session.reflection ?? SessionReflection())
    }

    private static let minimizedDetent = PresentationDetent.height(90)
    private static let lowDetent = PresentationDetent.fraction(0.3)

    /// どの回の振り返りかをシートに出す（2回を比べる画面では、左右どちらも書けるため）
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter
    }()

    private var hasChanges: Bool {
        draft.normalized != session.reflection
    }

    private var memoBinding: Binding<String> {
        Binding(get: { draft.memo ?? "" }, set: { draft.memo = $0 })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    tagRow("相手", selection: $draft.opponent)
                    tagRow("結果", selection: $draft.result)
                    tagRow("体調", selection: $draft.condition)
                    tagRow("天気", selection: $draft.weather)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("メモ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("味方のタイプ、試したこと、気づいたことなど", text: memoBinding, axis: .vertical)
                            .lineLimit(4...)
                            .padding(10)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("振り返り")
            .navigationSubtitle(Self.dateFormatter.string(from: session.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        dataManager.updateReflection(for: session.id, reflection: draft)
                        dismiss()
                    }
                }
            }
        }
        // 結果を見ながら書けるよう、裏の画面を操作できるようにする。キーボードを出すと
        // シートが持ち上がって裏が隠れるので、裏を広く見られる低い高さも用意する
        // 一番下まで下げても消さず、上部だけ残す。閉じるのは「キャンセル」か「保存」
        .presentationDetents([Self.minimizedDetent, Self.lowDetent, .medium, .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled()
    }

    /// 1つだけ選べるタグの行。選択中のタグをもう一度押すと解除する
    private func tagRow<Tag: CaseIterable & RawRepresentable & Equatable>(
        _ title: String,
        selection: Binding<Tag?>
    ) -> some View where Tag.RawValue == String {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(Tag.allCases), id: \.rawValue) { tag in
                    let isSelected = selection.wrappedValue == tag
                    Button {
                        selection.wrappedValue = isSelected ? nil : tag
                    } label: {
                        Text(tag.rawValue)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.accentColor : Color(.systemGray6))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 比較画面の表示

struct SessionReflectionSummary: View {
    let reflection: SessionReflection?
    /// この欄の回を書いている最中か（枠で示す）
    var isEditing = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let reflection {
                ForEach(reflection.tagLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption.bold())
                }
                if let memo = reflection.memo {
                    Text(memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("振り返りを書く", systemImage: "square.and.pencil")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }
}
