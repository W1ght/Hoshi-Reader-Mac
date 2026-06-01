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
    let onSubmit: () -> Void

    var body: some View {
        DictionarySearchTextFieldBridge(
            searchText: $searchText,
            isFocused: $isFocused,
            onSubmit: onSubmit
        )
    }
}
