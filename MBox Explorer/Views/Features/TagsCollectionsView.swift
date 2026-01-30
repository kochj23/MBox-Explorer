//
//  TagsCollectionsView.swift
//  MBox Explorer
//
//  Manage tags, collections, favorites, and notes
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import SwiftUI

struct TagsCollectionsView: View {
    @ObservedObject var viewModel: MboxViewModel
    @StateObject private var tagManager = TagManager.shared
    @State private var selectedTab = 0
    @State private var showingNewTag = false
    @State private var showingNewCollection = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("View", selection: $selectedTab) {
                Text("Tags").tag(0)
                Text("Collections").tag(1)
                Text("Favorites").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Content
            switch selectedTab {
            case 0:
                tagsView
            case 1:
                collectionsView
            case 2:
                favoritesView
            default:
                EmptyView()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Tags View

    private var tagsView: some View {
        VStack(spacing: 0) {
            // Tag list
            if tagManager.tags.isEmpty {
                emptyTagsState
            } else {
                List {
                    ForEach(tagManager.tags) { tag in
                        TagRow(tag: tag, emailCount: emailCount(for: tag))
                            .contextMenu {
                                Button("Edit") {
                                    // Edit tag
                                }
                                Button("Delete", role: .destructive) {
                                    tagManager.deleteTag(tag)
                                }
                            }
                    }
                }
            }

            Divider()

            // Add tag button
            HStack {
                Button(action: { showingNewTag = true }) {
                    Label("New Tag", systemImage: "plus")
                }

                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showingNewTag) {
            NewTagSheet(tagManager: tagManager)
        }
    }

    private var emptyTagsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tag")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No tags yet")
                .font(.headline)
            Text("Create tags to organize your emails")
                .foregroundColor(.secondary)
            Button("Create Tag") {
                showingNewTag = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Collections View

    private var collectionsView: some View {
        VStack(spacing: 0) {
            if tagManager.collections.isEmpty {
                emptyCollectionsState
            } else {
                List {
                    ForEach(tagManager.collections) { collection in
                        CollectionRow(
                            collection: collection,
                            emailCount: tagManager.getEmails(in: collection, from: viewModel.emails).count
                        )
                        .contextMenu {
                            Button("Edit") {
                                // Edit collection
                            }
                            Button("Delete", role: .destructive) {
                                tagManager.deleteCollection(collection)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button(action: { showingNewCollection = true }) {
                    Label("New Collection", systemImage: "plus")
                }

                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showingNewCollection) {
            NewCollectionSheet(tagManager: tagManager)
        }
    }

    private var emptyCollectionsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No collections yet")
                .font(.headline)
            Text("Create smart collections to filter emails")
                .foregroundColor(.secondary)
            Button("Create Collection") {
                showingNewCollection = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Favorites View

    private var favoritesView: some View {
        VStack(spacing: 0) {
            let favorites = tagManager.getFavorites(from: viewModel.emails)

            if favorites.isEmpty {
                emptyFavoritesState
            } else {
                List {
                    ForEach(favorites) { email in
                        FavoriteEmailRow(email: email)
                            .onTapGesture {
                                viewModel.selectedEmail = email
                            }
                            .contextMenu {
                                Button("Remove from Favorites") {
                                    tagManager.toggleFavorite(email.id)
                                }
                            }
                    }
                }
            }
        }
    }

    private var emptyFavoritesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No favorites yet")
                .font(.headline)
            Text("Star emails to add them to favorites")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func emailCount(for tag: EmailTag) -> Int {
        tagManager.getEmails(with: tag, from: viewModel.emails).count
    }
}

// MARK: - Tag Row

struct TagRow: View {
    let tag: EmailTag
    let emailCount: Int

    var body: some View {
        HStack {
            Image(systemName: tag.icon)
                .foregroundColor(tag.color.color)
                .frame(width: 24)

            Text(tag.name)
                .fontWeight(.medium)

            Spacer()

            Text("\(emailCount)")
                .foregroundColor(.secondary)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Collection Row

struct CollectionRow: View {
    let collection: EmailCollection
    let emailCount: Int

    var body: some View {
        HStack {
            Image(systemName: collection.icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .fontWeight(.medium)

                if collection.isSmartCollection {
                    Text("Smart Collection")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text("\(emailCount)")
                .foregroundColor(.secondary)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(8)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Favorite Email Row

struct FavoriteEmailRow: View {
    let email: Email

    var body: some View {
        HStack {
            Image(systemName: "star.fill")
                .foregroundColor(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(email.subject)
                    .lineLimit(1)

                Text(email.from)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(email.date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New Tag Sheet

struct NewTagSheet: View {
    @ObservedObject var tagManager: TagManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedColor: TagColor = .blue
    @State private var selectedIcon = "tag"

    private let icons = ["tag", "flag", "star", "heart", "bookmark", "folder", "doc", "person", "briefcase", "cart", "dollarsign", "house", "car", "airplane", "gift"]

    var body: some View {
        VStack(spacing: 20) {
            Text("New Tag")
                .font(.headline)

            TextField("Tag Name", text: $name)
                .textFieldStyle(.roundedBorder)

            // Color picker
            VStack(alignment: .leading) {
                Text("Color")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    ForEach(TagColor.allCases, id: \.self) { color in
                        Circle()
                            .fill(color.color)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                            )
                            .onTapGesture {
                                selectedColor = color
                            }
                    }
                }
            }

            // Icon picker
            VStack(alignment: .leading) {
                Text("Icon")
                    .font(.caption)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 8) {
                    ForEach(icons, id: \.self) { icon in
                        Image(systemName: icon)
                            .frame(width: 36, height: 36)
                            .background(selectedIcon == icon ? Color.accentColor : Color.clear)
                            .foregroundColor(selectedIcon == icon ? .white : .primary)
                            .cornerRadius(8)
                            .onTapGesture {
                                selectedIcon = icon
                            }
                    }
                }
            }

            // Preview
            HStack {
                Image(systemName: selectedIcon)
                    .foregroundColor(selectedColor.color)
                Text(name.isEmpty ? "Tag Name" : name)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Create") {
                    _ = tagManager.createTag(name: name, color: selectedColor, icon: selectedIcon)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 350, height: 450)
    }
}

// MARK: - New Collection Sheet

struct NewCollectionSheet: View {
    @ObservedObject var tagManager: TagManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "folder"
    @State private var isSmartCollection = true
    @State private var rules: [CollectionRule] = []

    var body: some View {
        VStack(spacing: 20) {
            Text("New Collection")
                .font(.headline)

            TextField("Collection Name", text: $name)
                .textFieldStyle(.roundedBorder)

            Toggle("Smart Collection", isOn: $isSmartCollection)

            if isSmartCollection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rules")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                        HStack {
                            Text("\(rule.field.rawValue) \(rule.operator_.rawValue) \"\(rule.value)\"")
                                .font(.caption)

                            Spacer()

                            Button(action: { rules.remove(at: index) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    Button("Add Rule") {
                        rules.append(CollectionRule(field: .from, operator_: .contains, value: ""))
                    }
                }
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Create") {
                    _ = tagManager.createCollection(name: name, icon: icon, rules: rules)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 400)
    }
}

#Preview {
    TagsCollectionsView(viewModel: MboxViewModel())
}
