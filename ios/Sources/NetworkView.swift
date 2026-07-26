import SwiftUI
import UIKit

// MARK: - Network list

/// Everyone the graph holds, plus free-text search over all of them.
struct NetworkView: View {
    @State private var people: [RosterPerson] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var showEnroll = false

    @State private var question = ""
    @State private var answer: NetworkAnswer?
    @State private var asking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    askPanel

                    if let answer {
                        answerPanel(answer)
                    }

                    HStack {
                        SectionLabel("Your network", icon: "person.2.fill")
                        Spacer()
                        if !people.isEmpty {
                            Text("\(people.count)")
                                .font(.rcLabel)
                                .foregroundStyle(Color.rcTextDim)
                        }
                    }
                    .padding(.top, 4)

                    if loading && people.isEmpty {
                        ProgressView()
                            .tint(.rcAccent)
                            .padding(.top, 40)
                    } else if let errorText, people.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.rcAlert)
                            Text(errorText)
                                .font(.rcCaption)
                                .foregroundStyle(Color.rcTextDim)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                        .padding(.horizontal, 24)
                    } else if people.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.2")
                                .font(.system(size: 30))
                                .foregroundStyle(Color.rcAccent)
                            Text("Nobody in the graph yet.")
                                .font(.rcBodyMedium)
                                .foregroundStyle(Color.rcText)
                            Text("Use Listen to log an intro, or tap + to enroll a face.")
                                .font(.rcCaption)
                                .foregroundStyle(Color.rcTextDim)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(people) { person in
                            NavigationLink(value: person.name) {
                                personRow(person)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .recallScreen()
            .navigationTitle("Network")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: String.self) { name in
                ContactView(name: name, onForgot: { await reload() })
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEnroll = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.rcAccent)
                    }
                }
            }
            .sheet(isPresented: $showEnroll) {
                EnrollSheet(onDone: { await reload() })
            }
            .refreshable { await reload() }
            .task { await reload() }
        }
    }

    // MARK: Ask your network

    private var askPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Ask your network", icon: "sparkle.magnifyingglass")
            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $question,
                    prompt: Text("Who did I meet working on payments?")
                        .foregroundColor(Color.rcTextDim)
                )
                .font(.rcBody)
                .foregroundStyle(Color.rcText)
                .submitLabel(.search)
                .onSubmit { Task { await ask() } }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color.rcSurfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    Task { await ask() }
                } label: {
                    if asking {
                        ProgressView().tint(.white).frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                    }
                }
                .padding(10)
                .background(Color.rcAccent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(asking || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .panel()
    }

    private func answerPanel(_ answer: NetworkAnswer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("Answer")
                Spacer()
                Text("searched \(answer.searched)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.rcTextDim)
            }
            if !answer.reason.isEmpty {
                Text(answer.reason)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.rcText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if answer.matches.isEmpty {
                Text("No one in the graph fits that yet.")
                    .font(.rcCaption)
                    .foregroundStyle(Color.rcTextDim)
            } else {
                ForEach(answer.matches) { match in
                    NavigationLink(value: match.name) {
                        HStack(spacing: 10) {
                            Avatar(name: match.name, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(match.name)
                                    .font(.rcBodyMedium)
                                    .foregroundStyle(Color.rcText)
                                if !match.org.isEmpty || !match.last.isEmpty {
                                    Text(
                                        [match.org, match.last]
                                            .filter { !$0.isEmpty }
                                            .joined(separator: " · ")
                                    )
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Color.rcTextDim)
                                    .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.rcTextDim.opacity(0.6))
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panel()
    }

    // MARK: Rows

    private func personRow(_ person: RosterPerson) -> some View {
        HStack(spacing: 13) {
            Avatar(name: person.name, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(person.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.rcText)
                    if person.enrolledFace {
                        Image(systemName: "faceid")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.rcAccent)
                            .accessibilityLabel("Face enrolled")
                    }
                }
                if !person.subtitle.isEmpty {
                    Text(person.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rcTextDim)
                        .lineLimit(1)
                } else if !person.relationship.isEmpty {
                    Text(person.relationship)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rcTextDim)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(person.encounters)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(
                        person.encounters > 0 ? Color.rcAccent : Color.rcTextDim
                    )
                Text(person.encounters == 1 ? "meet" : "meets")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.rcTextDim)
            }
        }
        .panel()
    }

    // MARK: Data

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            people = try await RecallAPI.roster()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func ask() async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !asking else { return }
        asking = true
        defer { asking = false }
        do {
            answer = try await RecallAPI.query(question: text)
        } catch {
            answer = NetworkAnswer(
                matches: [], reason: error.localizedDescription, searched: 0
            )
        }
    }
}

// MARK: - Avatar

struct Avatar: View {
    let name: String
    var size: CGFloat = 46

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(Color.rcAccent.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .stroke(Color.rcAccent.opacity(0.35), lineWidth: 1)
                )
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(Color.rcAccent)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Contact page

struct ContactView: View {
    let name: String
    var onForgot: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var card: PersonCard?
    @State private var errorText: String?
    @State private var confirmForget = false
    @State private var forgetting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let card {
                    MarkdownText(md: card.md.isEmpty ? "# \(card.name)" : card.md)
                        .panel()
                } else if let errorText {
                    Text(errorText)
                        .font(.rcCaption)
                        .foregroundStyle(Color.rcAlert)
                        .panel()
                } else {
                    ProgressView()
                        .tint(.rcAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 50)
                }

                if card != nil {
                    Button {
                        confirmForget = true
                    } label: {
                        if forgetting {
                            ProgressView().tint(.rcAlert).frame(maxWidth: .infinity)
                        } else {
                            Label("Forget \(name)", systemImage: "eraser")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(GhostButtonStyle(tint: .rcAlert))

                    Text("Forgetting deletes their face signature, every note, and every encounter from the graph. One call, no tombstone.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.rcTextDim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .recallScreen()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Forget \(name)?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) { Task { await forget() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their face signature and everything the graph knows about them is permanently removed.")
        }
        .task {
            do {
                card = try await RecallAPI.personCard(name: name)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func forget() async {
        forgetting = true
        defer { forgetting = false }
        do {
            try await RecallAPI.forget(name: name)
            await onForgot()
            dismiss()
        } catch {
            errorText = "Couldn't forget: \(error.localizedDescription)"
        }
    }
}

// MARK: - Enroll sheet

struct EnrollSheet: View {
    var onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = ""
    @State private var org = ""
    @State private var relationship = ""
    @State private var photo: UIImage?
    @State private var showCamera = false
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Attach a face so Capture recognises them on sight. If Listen already logged them, this links to the same record.")
                        .font(.rcCaption)
                        .foregroundStyle(Color.rcTextDim)

                    field("Name", text: $name, prompt: "Nadia Rahman")
                    field("Role", text: $role, prompt: "Founder")
                    field("Company", text: $org, prompt: "Loopwire")
                    field("Where you met", text: $relationship, prompt: "Fintech track, JacHacks")

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Face photo — required")
                        HStack(spacing: 14) {
                            if let photo {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 76, height: 76)
                                    .clipShape(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    )
                            }
                            Button {
                                showCamera = true
                            } label: {
                                Label(
                                    photo == nil ? "Take a photo" : "Retake",
                                    systemImage: "camera.fill"
                                )
                            }
                            .buttonStyle(GhostButtonStyle(tint: .rcAccent))
                        }
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.rcCaption)
                            .foregroundStyle(Color.rcAlert)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Add to network")
                        }
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(
                        name.trimmingCharacters(in: .whitespaces).isEmpty
                            || photo == nil || saving
                    )
                    .opacity(
                        name.trimmingCharacters(in: .whitespaces).isEmpty
                            || photo == nil ? 0.45 : 1
                    )
                }
                .padding(20)
            }
            .recallScreen()
            .navigationTitle("Enroll a face")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.rcTextDim)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker(image: $photo)
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func field(
        _ label: String, text: Binding<String>, prompt: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            TextField(
                "", text: text,
                prompt: Text(prompt).foregroundColor(Color.rcTextDim)
            )
            .font(.rcBody)
            .foregroundStyle(Color.rcText)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color.rcSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.rcLine, lineWidth: 1)
            )
        }
    }

    private func save() async {
        guard let jpeg = photo?.jpegData(compressionQuality: 0.8) else {
            errorText = "A face photo is required so Capture can match them."
            return
        }
        saving = true
        defer { saving = false }
        do {
            _ = try await RecallAPI.enroll(
                name: name.trimmingCharacters(in: .whitespaces),
                role: role.trimmingCharacters(in: .whitespaces),
                org: org.trimmingCharacters(in: .whitespaces),
                relationship: relationship.trimmingCharacters(in: .whitespaces),
                photoJpeg: jpeg
            )
            await onDone()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Camera picker

/// UIImagePickerController wrapper: camera when available, photo library
/// otherwise (simulator-friendly).
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType =
            UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController, context: Context
    ) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
        UINavigationControllerDelegate
    {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image =
                (info[.editedImage] as? UIImage)
                ?? (info[.originalImage] as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
