import AppKit
import SwiftUI

struct ThemeGalleryView: View {
    @ObservedObject var store: AppDataStore
    @State private var search = ""
    @State private var error: String?
    @Environment(\.companionTheme) private var currentTheme

    private var matches: [AppVisualTheme] {
        AppVisualTheme.allCases.filter { search.isEmpty || $0.title.localizedStandardContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("当前：\(store.settings.visualTheme.title)", systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(AppVisualTheme.allCases.count) 个主题").font(.caption).foregroundStyle(.secondary)
            }
            TextField("搜索主题", text: $search).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("theme-search")
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 18)], spacing: 18) {
                    ForEach(matches) { theme in
                        Button { select(theme) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                ThemePreview(theme: theme, store: store).frame(height: 208)
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(theme.title).font(.system(size: 14, weight: .semibold))
                                        Text("内置主题").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if theme == store.settings.visualTheme {
                                        Label("使用中", systemImage: "checkmark.circle.fill")
                                            .font(.caption).foregroundStyle(currentTheme.accent)
                                    } else {
                                        Text("应用主题").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(16)
                            }
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(theme == store.settings.visualTheme ? currentTheme.accent.opacity(0.65) : currentTheme.line.opacity(0.55), lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).focusEffectDisabled()
                        .accessibilityLabel("应用\(theme.title)")
                        .accessibilityValue(theme == store.settings.visualTheme ? "使用中" : "未使用")
                    }
                }
                if matches.isEmpty {
                    ContentUnavailableView.search(text: search).padding(.top, 40)
                }
            }.scrollIndicators(.visible)
        }
        .alert("主题未保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func select(_ theme: AppVisualTheme) {
        do { try store.selectVisualTheme(theme) }
        catch { self.error = error.localizedDescription }
    }
}

private struct ThemePreview: View {
    let theme: AppVisualTheme
    let store: AppDataStore

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "pawprint").font(.system(size: 15))
                ForEach(0..<3) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index == 0 ? theme.accent.opacity(0.14) : theme.line.opacity(0.25))
                        .frame(height: 7)
                }
                Spacer()
                Image(systemName: "paintpalette").font(.caption)
            }.padding(14).frame(width: 70).background(theme.wash)
            VStack(alignment: .leading, spacing: 12) {
                Text("PetPetKnows").font(.system(size: 12, weight: .semibold))
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("accommodate").font(.system(size: 16, weight: .semibold))
                        Text("v. 容纳；适应").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                if theme == .forest {
                    ForestPetStage {
                        if let pet = store.pets.first(where: { $0.id == "whisky-color" }),
                           let image = store.previewImage(for: pet) {
                            Image(nsImage: image).resizable().scaledToFit()
                        }
                    }.frame(height: 96)
                } else if theme == .storybook,
                   let url = AppResourceLocator.file(named: "Themes/storybook-duo", extension: "png"),
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 80)
                } else if let pet = store.pets.first(where: { $0.id == "whisky-ink" }),
                          let image = store.previewImage(for: pet) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 80)
                }
            }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.paper)
        }
        .foregroundStyle(theme.ink)
        .accessibilityHidden(true)
    }
}
