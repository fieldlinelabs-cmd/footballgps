//
//  FieldsListView.swift
//  FootballGPS
//
//  Created on 2025/01/08.
//

import SwiftUI

/// フィールド一覧画面
struct FieldsListView: View {
    @StateObject private var fieldManager = FieldManager.shared
    @State private var showingAddField = false
    @State private var editingField: Field? = nil
    @State private var actionField: Field? = nil
    @State private var fieldPendingDeletion: Field? = nil

    private var isActionDialogPresented: Binding<Bool> {
        Binding(
            get: { actionField != nil },
            set: { isPresented in
                if !isPresented { actionField = nil }
            }
        )
    }

    private var isDeleteConfirmPresented: Binding<Bool> {
        Binding(
            get: { fieldPendingDeletion != nil },
            set: { isPresented in
                if !isPresented { fieldPendingDeletion = nil }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if fieldManager.fields.isEmpty {
                    emptyStateView
                } else {
                    fieldsList
                }
            }
            .navigationTitle("Fields")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddField = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddField) {
                FieldEditorView(mode: .add)
            }
            .sheet(item: $editingField) { field in
                FieldEditorView(mode: .edit(field))
            }
            .confirmationDialog(
                actionField?.name ?? "",
                isPresented: isActionDialogPresented,
                titleVisibility: .visible
            ) {
                if let field = actionField {
                    Button("編集") {
                        editingField = field
                    }
                    Button("削除", role: .destructive) {
                        fieldPendingDeletion = field
                    }
                    Button("キャンセル", role: .cancel) {}
                }
            }
            .confirmationDialog(
                "「\(fieldPendingDeletion?.name ?? "")」を削除しますか？",
                isPresented: isDeleteConfirmPresented,
                titleVisibility: .visible
            ) {
                if let field = fieldPendingDeletion {
                    Button("削除する", role: .destructive) {
                        fieldManager.deleteField(field)
                    }
                    Button("キャンセル", role: .cancel) {}
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            
            Text("フィールドがありません")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("＋ボタンから\nフィールドを追加してください")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            Button {
                showingAddField = true
            } label: {
                Label("フィールドを追加", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var fieldsList: some View {
        List {
            ForEach(fieldManager.fields) { field in
                Button {
                    actionField = field
                } label: {
                    FieldRow(field: field)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        fieldPendingDeletion = field
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
        }
    }
}

// MARK: - Field Row

struct FieldRow: View {
    let field: Field

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(field.name)
                    .font(.headline)
                
                HStack(spacing: 16) {
                    Label("\(Int(field.dimensions.length))m × \(Int(field.dimensions.width))m", systemImage: "ruler")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // 座標設定済みか
                    if field.corners.topLeft.latitude != 0 {
                        Label("座標設定済み", systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("座標未設定", systemImage: "location.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FieldsListView()
}
