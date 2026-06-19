import CHoshiDicts
import Foundation
import Observation
import SwiftUI

protocol LookupSurface {
    func makeSelection(text: String, sentence: String, rect: CGRect, normalizedOffset: Int?) -> SelectionData
}

extension LookupSurface {
    func makeSelection(text: String, sentence: String, rect: CGRect, normalizedOffset: Int? = nil) -> SelectionData {
        SelectionData(
            text: text,
            sentence: sentence,
            rect: rect,
            normalizedOffset: normalizedOffset
        )
    }
}

@Observable
@MainActor
final class PopupPresentationCoordinator {
    var popups: [PopupItem] = []

    func present(
        selection: SelectionData,
        userConfig: UserConfig,
        replacingExisting: Bool = false,
        isVertical: Bool = false,
        isFullWidth: Bool = false
    ) -> Int? {
        if replacingExisting {
            popups.removeAll()
        }

        let results = LookupEngine.shared.lookup(
            selection.text,
            maxResults: userConfig.maxResults,
            scanLength: userConfig.scanLength
        )
        guard let firstResult = results.first else { return nil }

        let styles = Dictionary(uniqueKeysWithValues: LookupEngine.shared.getStyles().map {
            (String($0.dict_name), String($0.styles))
        })
        let popup = PopupItem(
            showPopup: false,
            currentSelection: selection,
            lookupResults: results,
            dictionaryStyles: styles,
            isVertical: isVertical,
            isFullWidth: isFullWidth,
            clearSelection: false
        )
        popups.append(popup)
        withAnimation(.default.speed(2.2)) {
            setVisibility(id: popup.id, visible: true)
        }
        return String(firstResult.matched).count
    }

    func closeAll(completion: (() -> Void)? = nil) {
        let ids = Set(popups.map(\.id))
        guard !ids.isEmpty else {
            completion?()
            return
        }
        withAnimation(.default.speed(2.4)) {
            for index in popups.indices {
                popups[index].showPopup = false
            }
        } completion: {
            self.popups.removeAll { ids.contains($0.id) }
            completion?()
        }
    }

    func closeChildren(of id: UUID) {
        guard let index = popups.firstIndex(where: { $0.id == id }) else { return }
        let ids = Set(popups.dropFirst(index + 1).map(\.id))
        guard !ids.isEmpty else { return }
        withAnimation(.default.speed(2.4)) {
            for childIndex in popups.indices where ids.contains(popups[childIndex].id) {
                popups[childIndex].showPopup = false
            }
        } completion: {
            self.popups.removeAll { ids.contains($0.id) }
        }
    }

    /// Applies the shared popup-stack behavior for a click handled by a popup itself:
    /// keep that popup open and dismiss only popups presented from it.
    func handleTapInsidePopup(id: UUID) {
        closeChildren(of: id)
    }

    func dismiss(id: UUID, completion: (() -> Void)? = nil) {
        guard let index = popups.firstIndex(where: { $0.id == id }) else { return }
        if index == 0 {
            closeAll(completion: completion)
        } else {
            popups[index - 1].clearSelection.toggle()
            closeChildren(of: popups[index - 1].id)
        }
    }

    func setVisibility(id: UUID, visible: Bool) {
        guard let index = popups.firstIndex(where: { $0.id == id }) else { return }
        popups[index].showPopup = visible
    }
}
