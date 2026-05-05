//
//  FieldEditorView.swift
//  FootballGPS
//
//  Created on 2025/01/08.
//

import SwiftUI
import MapKit

/// フィールド追加・編集画面
struct FieldEditorView: View {
    enum Mode {
        case add
        case edit(Field)
    }
    
    let mode: Mode
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var fieldManager = FieldManager.shared
    
    @State private var name: String = ""
    @State private var fieldCorners: Field.FieldCorners?  // 直角補正済みの4隅
    @State private var showingMapSetup = false
    
    // 4隅から縦・横を計算
    private var calculatedDimensions: Field.FieldDimensions? {
        guard let c = fieldCorners, c.topLeft.latitude != 0 else { return nil }
        let tl = CLLocation(latitude: c.topLeft.latitude, longitude: c.topLeft.longitude)
        let tr = CLLocation(latitude: c.topRight.latitude, longitude: c.topRight.longitude)
        let bl = CLLocation(latitude: c.bottomLeft.latitude, longitude: c.bottomLeft.longitude)
        return Field.FieldDimensions(length: tl.distance(from: tr), width: tl.distance(from: bl))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    TextField("フィールド名", text: $name)
                        .textInputAutocapitalization(.never)
                }
                
                Section {
                    if let dim = calculatedDimensions {
                        HStack {
                            Text("縦（長さ）")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f m", dim.length))
                        }
                        HStack {
                            Text("横（幅）")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f m", dim.width))
                        }
                    } else {
                        Text("4隅を設定するとサイズが自動計算されます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("サイズ（自動計算）")
                }
                
                Section {
                    Button {
                        showingMapSetup = true
                    } label: {
                        HStack {
                            Image(systemName: "map")
                                .foregroundStyle(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("地図で4隅を設定")
                                    .foregroundStyle(.primary)
                                
                                if let c = fieldCorners, c.topLeft.latitude != 0 {
                                    Text("設定済み")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                } else {
                                    Text("未設定")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("位置情報")
                } footer: {
                    Text("4隅を指定してください。自動で直角に補正されます。")
                }
            }
            .navigationTitle(mode.isAdd ? "フィールド追加" : "フィールド編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveField()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .sheet(isPresented: $showingMapSetup) {
                MapFieldSetupView(corners: $fieldCorners)
            }
            .onAppear {
                loadData()
            }
        }
    }
    
    private func loadData() {
        switch mode {
        case .add:
            name = ""
            fieldCorners = nil
            
        case .edit(let field):
            name = field.name
            fieldCorners = field.corners.topLeft.latitude != 0 ? field.corners : nil
        }
    }
    
    private func saveField() {
        let zero = Field.Coordinate(latitude: 0, longitude: 0)
        let corners = fieldCorners ?? Field.FieldCorners(
            topLeft: zero, topRight: zero, bottomRight: zero, bottomLeft: zero
        )
        let dimensions = calculatedDimensions ?? .standard
        
        switch mode {
        case .add:
            let newField = Field(
                teamId: "default_team",
                name: name,
                createdBy: "temp_user",
                corners: corners,
                dimensions: dimensions
            )
            fieldManager.addField(newField)
            
        case .edit(let field):
            let updatedField = Field(
                id: field.id,
                teamId: field.teamId,
                name: name,
                createdBy: field.createdBy,
                createdAt: field.createdAt,
                corners: corners,
                dimensions: dimensions
            )
            fieldManager.updateField(updatedField)
        }
        
        dismiss()
    }
}

extension FieldEditorView.Mode {
    var isAdd: Bool {
        if case .add = self {
            return true
        }
        return false
    }
}

#Preview {
    FieldEditorView(mode: .add)
}


