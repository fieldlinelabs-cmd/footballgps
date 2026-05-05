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
    
    var body: some View {
        NavigationStack {
            Group {
                if fieldManager.fields.isEmpty {
                    emptyStateView
                } else {
                    fieldsList
                }
            }
            .navigationTitle("フィールド")
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
                    // フィールドを選択
                    fieldManager.selectField(field.id)
                } label: {
                    FieldRow(field: field, isSelected: fieldManager.selectedFieldId == field.id)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        editingField = field
                    } label: {
                        Label("編集", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        fieldManager.deleteField(field)
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        fieldManager.deleteField(field)
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
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // 選択インジケーター
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .green : .secondary)
                .font(.title3)
            
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
