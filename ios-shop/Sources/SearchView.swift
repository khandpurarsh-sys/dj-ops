import SwiftUI

/** Real search (Android SearchScreen.kt parity): searches the full connected catalog
 *  (every piece on dressjet.com), title and type plus category hints from the site's own
 *  curated collections, newest first, as you type. Clean white screen: back, pill field,
 *  bag; results in the same 2-col cards as the rest of the app. A failed catalog fetch
 *  must not blank search - the pool falls back to the already-loaded products, and type
 *  collections load HERE (not via home's section pipeline) so cold-start type searches
 *  still find their pieces. */
struct SearchView: View {
    @ObservedObject var repo: Repo
    let bagCount: Int
    let onBack: () -> Void
    let onBag: () -> Void
    let onProduct: (DjProduct) -> Void

    // 236: hoisted to RootView so Back from a product keeps the typed search.
    @Binding var query: String
    @State private var all: [DjProduct]? = nil
    @State private var typeColls: [String: [DjProduct]] = [:]
    @FocusState private var focused: Bool

    private var pool: [DjProduct] {
        let a = all ?? []
        return a.isEmpty ? repo.products : a
    }

    private var hints: [Int64: String] {
        var m: [Int64: String] = [:]
        for (c, items) in repo.sections {
            for p in items {
                m[p.id] = (m[p.id] ?? "") + " " + c.title + " " + c.handle.replacingOccurrences(of: "-", with: " ")
            }
        }
        for (h, items) in typeColls {
            for p in items {
                m[p.id] = (m[p.id] ?? "") + " " + h.replacingOccurrences(of: "-", with: " ")
            }
        }
        return m
    }

    private var results: [DjProduct] {
        Feed.searchProducts(pool, hints: hints, query: query)
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Text("‹").font(.system(size: 24)).foregroundStyle(Dj.navy)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                HStack(spacing: 10) {
                    Text("⌕").font(.system(size: 16)).foregroundStyle(Dj.navy)
                    TextField("Search DressJet", text: $query)
                        .font(Dj.assistant(15, weight: .medium))
                        .foregroundStyle(Dj.navy)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Text("✕").font(.system(size: 14)).foregroundStyle(Dj.ink3)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(Color(red: 0xF4/255, green: 0xF6/255, blue: 0xF8/255), in: RoundedRectangle(cornerRadius: 23))
                .overlay(RoundedRectangle(cornerRadius: 23).stroke(Dj.line, lineWidth: 1))
                Button(action: onBag) { BagIcon(count: bagCount, tint: Dj.navy) }
            }
            .frame(height: 64)
            .padding(.horizontal, 20)

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    SerifTitle(text: "Find your piece.", color: Dj.ink2, size: 26)
                    Eyebrow(text: "Every piece on dressjet.com", color: Dj.ink3)
                }
                Spacer()
            } else if results.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    SerifTitle(text: "No pieces match \"\(query)\".", color: Dj.ink2, size: 24)
                    Eyebrow(text: "Try a fabric, fit or name", color: Dj.ink3)
                }
                Spacer()
            } else {
                Text("\(results.count) pieces")
                    .font(Dj.assistant(12)).tracking(1)
                    .foregroundStyle(Dj.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                ScrollView {
                    let rows = stride(from: 0, to: results.count, by: 2).map { Array(results[$0..<min($0 + 2, results.count)]) }
                    LazyVStack(spacing: 30) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(row) { p in
                                    GridCard(product: p, repo: repo, onTap: { onProduct(p) })
                                        .frame(maxWidth: .infinity)
                                }
                                if row.count == 1 { Spacer().frame(maxWidth: .infinity) }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .onAppear {
            focused = true
            all = repo.peekCollection(Feed.ALL_HANDLE)
            for h in Feed.HOME_SECTION_HANDLES {
                if let l = repo.peekCollection(h) { typeColls[h] = l }
            }
        }
        .task {
            await repo.loadCollection(Feed.ALL_HANDLE)
            if let l = repo.peekCollection(Feed.ALL_HANDLE), !l.isEmpty { all = l }
            for h in Feed.HOME_SECTION_HANDLES {
                await repo.loadCollection(h)
                if let l = repo.peekCollection(h), !l.isEmpty { typeColls[h] = l }
            }
        }
    }
}
