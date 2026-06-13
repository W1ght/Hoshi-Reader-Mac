//
//  CustomSearchField.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct CustomSearchField: View {
    @Binding var searchText: String
    @Binding var isFocused: Bool
    @FocusState private var fieldFocused: Bool
    let onSubmit: () -> Void

    var body: some View {
        TextField("", text: $searchText)
            .textFieldStyle(.plain)
            .focused($fieldFocused)
            .onSubmit {
                isFocused = false
                onSubmit()
            }
            .onChange(of: isFocused, initial: true) { _, isFocused in
                fieldFocused = isFocused
            }
            .onChange(of: fieldFocused) { _, fieldFocused in
                isFocused = fieldFocused
            }
    }
}
