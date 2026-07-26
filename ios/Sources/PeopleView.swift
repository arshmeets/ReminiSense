import SwiftUI
import UIKit

// MARK: - People list

struct PeopleView: View {
    @State private var people: [PersonNode] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var showEnroll = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if loading && people.isEmpty {
                        ProgressView("Remembering…")
                            .padding(.top, 60)
                            .tint(.rsTerracotta)
                    } else if let errorText, people.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 30))
                                .foregroundStyle(Color.rsWarn)
                            Text(errorText)
                                .font(.rsCaption)
                                .foregroundStyle(Color.rsInkSoft)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 60)
                        .padding(.horizontal, 30)
                    } else if people.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "person.2")
                                .font(.system(size: 34))
                                .foregroundStyle(Color.rsAmber)
                            Text("No one enrolled yet.")
                                .font(.rsBody)
                                .foregroundStyle(Color.rsInkSoft)
                            Text("Tap the plus to introduce someone.")
                                .font(.rsCaption)
                                .foregroundStyle(Color.rsInkSoft.opacity(0.8))
                        }
                        .padding(.top, 60)
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
            .background(Color.rsCream.ignoresSafeArea())
            .navigationTitle("People")
            .navigationDestination(for: String.self) { name in
                PersonDetailView(name: name, onForgot: { await reload() })
            }
            .toolbar {
                Button {
                    showEnroll = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.rsTerracotta)
                }
            }
            .sheet(isPresented: $showEnroll) {
                EnrollSheet(onDone: { await reload() })
            }
            .refreshable { await reload() }
            .task { await reload() }
        }
    }

    private func personRow(_ person: PersonNode) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.rsAmber.opacity(0.7), .rsTerracotta.opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                Text(String(person.name.prefix(1)).uppercased())
                    .font(.rsSerif(22))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(person.name)
                    .font(.rsSerif(21, .medium))
                    .foregroundStyle(Color.rsInk)
                if person.pulse > 0 {
                    Label(
                        "Seen recently",
                        systemImage: "circle.fill"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.rsSage)
                } else {
                    Text("In your circle")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rsInkSoft)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.rsInkSoft.opacity(0.5))
        }
        .softCard()
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            people = try await ReminiAPI.people()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Person detail (keepsake page)

struct PersonDetailView: View {
    let name: String
    var onForgot: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var card: PersonCard?
    @State private var errorText: String?
    @State private var confirmForget = false
    @State private var forgetting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let card {
                    MarkdownText(md: card.md.isEmpty ? "# \(card.name)" : card.md)
                        .softCard()
                } else if let errorText {
                    Text(errorText)
                        .font(.rsCaption)
                        .foregroundStyle(Color.rsWarn)
                        .softCard()
                } else {
                    ProgressView("Gathering memories…")
                        .tint(.rsTerracotta)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }

                if card != nil {
                    Button(role: .destructive) {
                        confirmForget = true
                    } label: {
                        if forgetting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("Forget this person", systemImage: "eraser")
                                .font(.rsCaption.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.rsWarn)
                    .padding(.top, 8)

                    Text("Forgetting removes their face signature and every memory of them from ReminiSense. This cannot be undone.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rsInkSoft)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .background(Color.rsCream.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Forget \(name)?", isPresented: $confirmForget) {
            Button("Forget forever", role: .destructive) {
                Task { await forget() }
            }
            Button("Keep remembering", role: .cancel) {}
        } message: {
            Text("Their face signature and all memories will be permanently removed.")
        }
        .task {
            do {
                card = try await ReminiAPI.personCard(name: name)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func forget() async {
        forgetting = true
        defer { forgetting = false }
        do {
            try await ReminiAPI.forget(name: name)
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
    @State private var relationship = ""
    @State private var notes = ""
    @State private var photo: UIImage?
    @State private var showCamera = false
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Introduce someone ReminiSense should recognize and gently reintroduce.")
                        .font(.rsBody)
                        .foregroundStyle(Color.rsInkSoft)

                    field("Name", text: $name, prompt: "Maya")
                    field("Relationship", text: $relationship, prompt: "Your daughter")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.rsCaption.weight(.semibold))
                            .foregroundStyle(Color.rsInk)
                        TextEditor(text: $notes)
                            .font(.rsBody)
                            .frame(minHeight: 100)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color.rsCard)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        Text("Little things that spark conversation — her pottery class, the trip to Lisbon…")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.rsInkSoft)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Photo (optional)")
                            .font(.rsCaption.weight(.semibold))
                            .foregroundStyle(Color.rsInk)
                        HStack(spacing: 14) {
                            if let photo {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            Button {
                                showCamera = true
                            } label: {
                                Label(
                                    photo == nil ? "Take a photo" : "Retake",
                                    systemImage: "camera.fill"
                                )
                                .font(.rsCaption.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .tint(.rsTerracotta)
                        }
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.rsCaption)
                            .foregroundStyle(Color.rsWarn)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        } else {
                            Text("Add to my circle")
                                .font(.rsBodyMedium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.rsTerracotta)
                    .clipShape(Capsule())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
                .padding(20)
            }
            .background(Color.rsCream.ignoresSafeArea())
            .navigationTitle("Enroll someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.rsInkSoft)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker(image: $photo)
                    .ignoresSafeArea()
            }
        }
    }

    private func field(
        _ label: String, text: Binding<String>, prompt: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.rsCaption.weight(.semibold))
                .foregroundStyle(Color.rsInk)
            TextField(prompt, text: text)
                .font(.rsBody)
                .padding(12)
                .background(Color.rsCard)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await ReminiAPI.enroll(
                name: name.trimmingCharacters(in: .whitespaces),
                relationship: relationship.trimmingCharacters(in: .whitespaces),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                photoJpeg: photo?.jpegData(compressionQuality: 0.7)
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
