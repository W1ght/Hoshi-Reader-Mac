import Foundation

@main
private enum AnkiFieldTemplateTests {
    static func main() {
        let lapis = AnkiFieldTemplate.autofilledMappings(
            noteType: "Lapis",
            availableFields: ["Expression", "MainDefinition", "Sentence", "SentenceAudio", "Picture", "UnknownField"],
            existing: [:],
            preset: .novel
        )
        precondition(lapis["Expression"] == Handlebars.expression.rawValue)
        precondition(lapis["MainDefinition"] == Handlebars.glossaryFirst.rawValue)
        precondition(lapis["Sentence"] == Handlebars.sentence.rawValue)
        precondition(lapis["SentenceAudio"] == Handlebars.sasayakiAudio.rawValue)
        precondition(lapis["Picture"] == Handlebars.bookCover.rawValue)
        precondition(lapis["UnknownField"] == nil)

        let animeLapis = AnkiFieldTemplate.autofilledMappings(
            noteType: "Lapis",
            availableFields: ["Expression", "SentenceAudio", "Picture"],
            existing: [:],
            preset: .anime
        )
        precondition(animeLapis["Expression"] == Handlebars.expression.rawValue)
        precondition(animeLapis["SentenceAudio"] == Handlebars.videoAudioClip.rawValue)
        precondition(animeLapis["Picture"] == Handlebars.videoScreenshot.rawValue)

        let custom = AnkiFieldTemplate.autofilledMappings(
            noteType: "Lapis",
            availableFields: ["Expression", "MainDefinition"],
            existing: [
                "Expression": "{custom-expression}",
                "MainDefinition": "   ",
                "RemovedField": "{sentence}"
            ],
            preset: .anime
        )
        precondition(custom["Expression"] == "{custom-expression}")
        precondition(custom["MainDefinition"] == Handlebars.glossaryFirst.rawValue)
        precondition(custom["RemovedField"] == nil)

        let kiku = AnkiFieldTemplate.autofilledMappings(
            noteType: "Kiku",
            availableFields: ["ExpressionAudio", "SentenceAudio", "Picture"],
            existing: [:],
            preset: .anime
        )
        precondition(kiku["ExpressionAudio"] == Handlebars.audio.rawValue)
        precondition(kiku["SentenceAudio"] == Handlebars.videoAudioClip.rawValue)
        precondition(kiku["Picture"] == Handlebars.videoScreenshot.rawValue)

        let senren = AnkiFieldTemplate.autofilledMappings(
            noteType: "Senren",
            availableFields: ["word", "definition", "wordAudio", "sentenceAudio", "picture"],
            existing: [:],
            preset: .anime
        )
        precondition(senren["word"] == Handlebars.expression.rawValue)
        precondition(senren["definition"] == Handlebars.glossaryFirst.rawValue)
        precondition(senren["wordAudio"] == Handlebars.audio.rawValue)
        precondition(senren["sentenceAudio"] == Handlebars.videoAudioClip.rawValue)
        precondition(senren["picture"] == Handlebars.videoScreenshot.rawValue)

        let unknown = ["Front": "{expression}"]
        precondition(AnkiFieldTemplate.autofilledMappings(
            noteType: "Custom",
            availableFields: ["Front"],
            existing: unknown,
            preset: .anime
        ) == unknown)

        let restoredLapis = AnkiFieldTemplate.appliedDefaultMappings(
            noteType: "Lapis",
            availableFields: ["Expression", "Sentence", "SentenceAudio", "Picture", "ExtraField"],
            existing: [
                "Expression": "{custom-expression}",
                "Sentence": Handlebars.videoSubtitle.rawValue,
                "Picture": Handlebars.videoScreenshot.rawValue,
                "ExtraField": "{custom-extra}",
                "RemovedField": "{removed}"
            ],
            preset: .novel
        )
        precondition(restoredLapis["Expression"] == Handlebars.expression.rawValue)
        precondition(restoredLapis["Sentence"] == Handlebars.sentence.rawValue)
        precondition(restoredLapis["SentenceAudio"] == Handlebars.sasayakiAudio.rawValue)
        precondition(restoredLapis["Picture"] == Handlebars.bookCover.rawValue)
        precondition(restoredLapis["ExtraField"] == "{custom-extra}")
        precondition(restoredLapis["RemovedField"] == nil)

        let restoredAnime = AnkiFieldTemplate.appliedDefaultMappings(
            noteType: "Lapis",
            availableFields: ["Expression", "SentenceAudio", "Picture", "ExtraField"],
            existing: [
                "Expression": "{custom-expression}",
                "SentenceAudio": Handlebars.sasayakiAudio.rawValue,
                "Picture": Handlebars.bookCover.rawValue,
                "ExtraField": "{custom-extra}"
            ],
            preset: .anime
        )
        precondition(restoredAnime["Expression"] == Handlebars.expression.rawValue)
        precondition(restoredAnime["SentenceAudio"] == Handlebars.videoAudioClip.rawValue)
        precondition(restoredAnime["Picture"] == Handlebars.videoScreenshot.rawValue)
        precondition(restoredAnime["ExtraField"] == "{custom-extra}")

        let definitionPictureRegression = AnkiFieldTemplate.appliedDefaultMappings(
            noteType: "Lapis",
            availableFields: ["Expression", "DefinitionPicture", "CustomField"],
            existing: [
                "DefinitionPicture": Handlebars.glossary.rawValue,
                "CustomField": "{custom-extra}"
            ],
            preset: .novel
        )
        precondition(definitionPictureRegression["Expression"] == Handlebars.expression.rawValue)
        precondition(definitionPictureRegression["DefinitionPicture"] == nil)
        precondition(definitionPictureRegression["CustomField"] == "{custom-extra}")
        precondition(AnkiFieldTemplate.clearsMapping(noteType: "Lapis", field: "DefinitionPicture"))
        precondition(!AnkiFieldTemplate.clearsMapping(noteType: "Lapis", field: "CustomField"))
        precondition(!AnkiFieldTemplate.clearsMapping(noteType: "Kiku", field: "DefinitionPicture"))

        precondition(AnkiFieldTemplate.appliedDefaultMappings(
            noteType: "Custom",
            availableFields: ["Front"],
            existing: unknown,
            preset: .novel
        ) == unknown)
        precondition(AnkiFieldTemplate.hasDefaults(noteType: "Lapis"))
        precondition(!AnkiFieldTemplate.hasDefaults(noteType: "Custom"))

        precondition(Handlebars.phoneticTranscriptions.rawValue == "{phonetic-transcriptions}")

        let profileConfig = AnkiProfileConfig(
            selectedDeck: "English Mining",
            selectedNoteType: "Lapis",
            allowDupes: false,
            compactGlossaries: true,
            embedMedia: true,
            fieldMappings: ["Pronunciation": Handlebars.phoneticTranscriptions.rawValue],
            tags: "english",
            duplicateScope: .deck,
            checkAllModels: true
        )
        let profileData = try! JSONEncoder().encode(profileConfig)
        let profileJSON = String(decoding: profileData, as: UTF8.self)
        precondition(!profileJSON.contains("url"))
        precondition(!profileJSON.contains("timeout"))
        precondition(!profileJSON.contains("forceSync"))
        let decodedProfileConfig = try! JSONDecoder().decode(AnkiProfileConfig.self, from: profileData)
        precondition(decodedProfileConfig == profileConfig)

        let manager = try! String(contentsOfFile: "Core/AnkiManager.swift", encoding: .utf8)
        let popup = try! String(contentsOfFile: "Features/Popup/popup.js", encoding: .utf8)
        precondition(manager.contains("case .phoneticTranscriptions:"))
        precondition(manager.contains("content[\"phoneticTranscriptions\"]"))
        precondition(popup.contains("constructPhoneticTranscriptionsHtml"))
        precondition(popup.contains("phoneticTranscriptions,"))
        let settings = try! String(contentsOfFile: "Features/Settings/AnkiView.swift", encoding: .utf8)
        precondition(manager.contains("func autofillFieldMappings() -> Bool"))
        precondition(manager.contains("if autofillFieldMappings() {"))
        precondition(manager.contains("pruneFieldMappings(availableFields: noteType.fields)\n            autofillFieldMappings()"))
        precondition(manager.contains("func applyDefaultFieldMappings(preset: AnkiFieldMappingPreset) -> Bool"))
        precondition(settings.contains("ankiManager.autofillFieldMappings()\n                            ankiManager.save()"))
        precondition(settings.contains("Apply Novel Defaults"))
        precondition(settings.contains("Apply Anime Defaults"))
        precondition(settings.contains("ankiManager.applyDefaultFieldMappings(preset: preset)"))

        print("Anki field template tests passed")
    }
}
