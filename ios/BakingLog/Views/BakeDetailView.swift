import SwiftUI

struct BakeDetailView: View {
    let bakeId: String
    @State private var bake: Bake?
    @State private var isLoading = true
    @State private var showingEdit = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let bake {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Photos
                        if let photos = bake.photos, !photos.isEmpty {
                            PhotoCarousel(photos: photos)
                        }

                        // Ingredients
                        if let ingredients = bake.ingredients, !ingredients.isEmpty {
                            SectionBlock(title: "Ingredients") {
                                Text(ingredients)
                                    .font(.body.monospaced())
                            }
                        }

                        // Schedule
                        if let schedule = bake.schedule, !schedule.isEmpty {
                            SectionBlock(title: "Schedule") {
                                ForEach(schedule) { entry in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(entry.time)
                                            .font(.subheadline.monospaced())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 80, alignment: .trailing)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.action)
                                                .font(.body)
                                            if let note = entry.note, !note.isEmpty {
                                                Text(note)
                                                    .font(.caption)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Notes
                        if let notes = bake.notes, !notes.isEmpty {
                            SectionBlock(title: "Notes") {
                                Text(notes)
                                    .font(.body)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(bake?.title ?? "Bake")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if bake != nil {
                Button("Edit") {
                    showingEdit = true
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let bake {
                BakeEditView(existing: bake) {
                    showingEdit = false
                    Task { await load() }
                }
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        bake = try? await APIClient.shared.getBake(id: bakeId)
        isLoading = false
    }
}

struct SectionBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.bold())
            content
        }
    }
}

struct PhotoCarousel: View {
    let photos: [Photo]
    @State private var selectedPhoto: Photo?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(photos) { photo in
                    AsyncImage(url: APIClient.shared.photoURL(for: photo.id)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Rectangle()
                                .fill(.quaternary)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                        default:
                            Rectangle()
                                .fill(.quaternary)
                                .overlay { ProgressView() }
                        }
                    }
                    .frame(width: 280, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { selectedPhoto = photo }
                }
            }
            .padding(.horizontal, 1)
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            FullScreenPhoto(photo: photo)
        }
    }
}

struct FullScreenPhoto: View {
    let photo: Photo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: APIClient.shared.photoURL(for: photo.id)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                default:
                    ProgressView()
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .padding()
        }
    }
}
