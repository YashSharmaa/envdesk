// envdesk: a small native Mac app to see, add and update API keys in your .env files and shell profile.
// It reads and writes plain files on this Mac and never sends anything anywhere. MIT licensed.
import AppKit
import LocalAuthentication
import SwiftUI

// MARK: - Files

struct Store: Identifiable, Hashable {
    let id: String
    let label: String
    let path: String
    let shellExport: Bool  // ~/.zshenv uses `export NAME=value` and is also pushed to launchctl
}

let home = FileManager.default.homeDirectoryForCurrentUser.path
let macStore = Store(id: "mac", label: "Mac (~/.zshenv + launchctl)", path: home + "/.zshenv", shellExport: true)

/// A project is a name and the env files that belong to it. Saved in ~/.config/envdesk/projects.json.
struct Project: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var files: [String]
}

let configPath = home + "/.config/envdesk/projects.json"

func loadProjects() -> [Project] {
    guard let data = FileManager.default.contents(atPath: configPath),
          let list = try? JSONDecoder().decode([Project].self, from: data) else { return [] }
    return list
}

func saveProjects(_ list: [Project]) {
    let dir = (configPath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? enc.encode(list) { FileManager.default.createFile(atPath: configPath, contents: data) }
}

func storesFor(_ project: Project?) -> [Store] {
    [macStore] + (project?.files ?? []).map {
        Store(id: $0, label: $0.replacingOccurrences(of: home, with: "~"), path: $0, shellExport: false)
    }
}

/// Env files in a folder and one level down, for a new project.
func envFiles(in folder: String) -> [String] {
    let fm = FileManager.default
    let names = [".env.local", ".env", ".env.development.local", ".env.production.local", ".env.development", ".env.production"]
    var found: [String] = []
    for dir in [folder] + ((try? fm.contentsOfDirectory(atPath: folder)) ?? []).map({ folder + "/" + $0 }) {
        for n in names where fm.fileExists(atPath: dir + "/" + n) { found.append(dir + "/" + n) }
    }
    return found.isEmpty ? [folder + "/.env.local"] : found
}

let suggested = [
    "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "ELEVENLABS_API_KEY", "GROQ_API_KEY",
    "GITHUB_TOKEN", "STRIPE_SECRET_KEY", "STRIPE_PUBLISHABLE_KEY", "DATABASE_URL",
    "GOOGLE_OAUTH_CLIENT_ID", "GOOGLE_OAUTH_CLIENT_SECRET", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY",
    "SUPABASE_URL", "SUPABASE_ANON_KEY", "TELEGRAM_BOT_TOKEN", "SLACK_BOT_TOKEN",
]

struct Entry: Identifiable, Hashable {
    var id: String { store.id + ":" + name }
    let store: Store
    let name: String
    let value: String
}

let linePattern = try! NSRegularExpression(pattern: #"^\s*(export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$"#)
let namePattern = #"^[A-Za-z_][A-Za-z0-9_]*$"#

func unquote(_ raw: String) -> String {
    var v = raw.trimmingCharacters(in: .whitespaces)
    if v.count >= 2, let f = v.first, let l = v.last, (f == "\"" && l == "\"") || (f == "'" && l == "'") {
        v = String(v.dropFirst().dropLast())
    }
    return v
}

func parseLines(_ text: String) -> [(String, String)] {
    text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
        let s = String(line)
        guard let m = linePattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let n = Range(m.range(at: 2), in: s), let v = Range(m.range(at: 3), in: s) else { return nil }
        return (String(s[n]), unquote(String(s[v])))
    }
}

func read(_ store: Store) -> [Entry] {
    guard let text = try? String(contentsOfFile: store.path, encoding: .utf8) else { return [] }
    return parseLines(text).map { Entry(store: store, name: $0.0, value: $0.1) }
}

func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

/// Replaces NAME's line, or appends one, keeping every other line as it was. nil removes it.
func write(_ store: Store, name: String, value: String?) throws {
    let fm = FileManager.default
    var lines = ((try? String(contentsOfFile: store.path, encoding: .utf8)) ?? "")
        .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if lines.last == "" { lines.removeLast() }
    let newLine = value.map { (store.shellExport ? "export " : "") + name + "=" + quoted($0) }
    var found = false
    lines = lines.compactMap { line in
        guard let m = linePattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let n = Range(m.range(at: 2), in: line), String(line[n]) == name else { return line }
        if found { return nil }
        found = true
        return newLine
    }
    if !found, let newLine { lines.append(newLine) }
    if fm.fileExists(atPath: store.path) {
        let backup = store.path + ".bak"
        try? fm.removeItem(atPath: backup)
        try fm.copyItem(atPath: store.path, toPath: backup)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup)
    } else {
        try fm.createDirectory(atPath: (store.path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    }
    try (lines.joined(separator: "\n") + "\n").write(toFile: store.path, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.path)
    if store.shellExport { run("/bin/launchctl", value.map { ["setenv", name, $0] } ?? ["unsetenv", name]) }
}

@discardableResult
func run(_ tool: String, _ args: [String], in dir: String? = nil) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    if let dir { p.currentDirectoryURL = URL(fileURLWithPath: dir) }
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

/// True when the file is inside a git repo and git does NOT ignore it, so it could be committed.
func committable(_ path: String) -> Bool {
    let dir = (path as NSString).deletingLastPathComponent
    guard FileManager.default.fileExists(atPath: "/usr/bin/git"),
          run("/usr/bin/git", ["rev-parse", "--is-inside-work-tree"], in: dir) == 0 else { return false }
    return run("/usr/bin/git", ["check-ignore", "-q", path], in: dir) != 0
}

/// KEY=VALUE lines, or a JSON object (nested ones are flattened: web.client_id -> CLIENT_ID).
func parseImport(_ text: String) -> [(String, String)] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        var out: [(String, String)] = []
        func walk(_ o: [String: Any]) {
            for (k, v) in o.sorted(by: { $0.key < $1.key }) {
                if let s = v as? String {
                    let n = k.uppercased().replacingOccurrences(of: "[^A-Z0-9_]", with: "_", options: .regularExpression)
                    out.append((n, s))
                } else if let d = v as? [String: Any] { walk(d) }
            }
        }
        walk(obj)
        return out
    }
    return parseLines(trimmed)
}

func masked(_ v: String) -> String {
    v.count <= 8 ? String(repeating: "•", count: v.count) : String(v.prefix(4)) + String(repeating: "•", count: 8) + String(v.suffix(4))
}

// MARK: - View

struct ContentView: View {
    @State private var entries: [Entry] = []
    @State private var revealed: Set<String> = []
    @State private var filter = ""
    @State private var name = ""
    @State private var value = ""
    @State private var targets: Set<String> = ["mac"]
    @State private var status = ""
    @State private var projects: [Project] = loadProjects()
    @State private var unlockedUntil = Date.distantPast
    @State private var importing = false
    @State private var importText = ""
    @State private var importPrefix = ""
    @State private var risky: Set<String> = []
    @AppStorage("project") private var projectName = ""
    @AppStorage("clearClipboardSeconds") private var clearSeconds = 30
    @AppStorage("requireUnlock") private var requireUnlock = true

    var project: Project? { projects.first { $0.name == projectName } ?? projects.first }
    var stores: [Store] { storesFor(project) }
    var defaultTargets: Set<String> { [stores.dropFirst().first?.id ?? "mac"] }
    var shown: [Entry] { filter.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(filter) } }
    /// Names whose value is not the same in every file that has them.
    var differing: Set<String> {
        Set(Dictionary(grouping: entries, by: \.name).filter { Set($0.value.map(\.value)).count > 1 }.keys)
    }

    func reload() {
        entries = stores.flatMap(read)
        risky = Set(stores.filter { !$0.shellExport && committable($0.path) }.map(\.id))
    }

    /// Touch ID or the Mac password before any value is shown or copied, then 5 minutes free.
    func unlocked(_ then: @escaping () -> Void) {
        if !requireUnlock || Date() < unlockedUntil { then(); return }
        let ctx = LAContext()
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "show or copy a secret") { ok, _ in
            DispatchQueue.main.async {
                if ok { unlockedUntil = Date().addingTimeInterval(300); then() } else { status = "Not unlocked." }
            }
        }
    }

    func save(_ pairs: [(String, String)]) {
        let good = pairs.map { ($0.0.trimmingCharacters(in: .whitespaces), $0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.1.isEmpty && $0.0.range(of: namePattern, options: .regularExpression) != nil }
        guard !good.isEmpty else { status = "Nothing to save: a name is letters, digits and _, and a value can't be empty."; return }
        guard !targets.isEmpty else { status = "Tick at least one place to save to."; return }
        do {
            for s in stores where targets.contains(s.id) { for (n, v) in good { try write(s, name: n, value: v) } }
            status = "Saved \(good.count) key(s) to \(targets.count) place(s). Restart your app or open a new terminal to pick them up."
            reload()
        } catch { status = "Couldn't save: \(error.localizedDescription)" }
    }

    func copy(_ text: String, label: String) {
        let pb = NSPasteboard.general
        pb.clearContents(); pb.setString(text, forType: .string)
        let count = pb.changeCount
        status = clearSeconds > 0 ? "Copied \(label). The clipboard clears in \(clearSeconds) s." : "Copied \(label)."
        if clearSeconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(clearSeconds)) {
                if NSPasteboard.general.changeCount == count { NSPasteboard.general.clearContents() }
            }
        }
    }

    func reveal(_ e: Entry) {
        unlocked {
            revealed.insert(e.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { revealed.remove(e.id) }
        }
    }

    func exportExample() {
        guard let p = project, let first = p.files.first else { return }
        let names = Array(Set(entries.filter { !$0.store.shellExport }.map(\.name))).sorted()
        let path = ((first as NSString).deletingLastPathComponent as NSString).appendingPathComponent(".env.example")
        let body = "# Names only. Copy to .env.local and fill in the values.\n" + names.map { $0 + "=" }.joined(separator: "\n") + "\n"
        do { try body.write(toFile: path, atomically: true, encoding: .utf8); status = "Wrote \(names.count) names to \(path.replacingOccurrences(of: home, with: "~"))." }
        catch { status = "Couldn't write .env.example: \(error.localizedDescription)" }
    }

    func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Add project"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let n = url.lastPathComponent
        projects.removeAll { $0.name == n }
        projects.append(Project(name: n, files: envFiles(in: url.path)))
        saveProjects(projects); projectName = n; reload(); targets = defaultTargets
        status = "Added \(n)."
    }

    func addFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.showsHiddenFiles = true; panel.prompt = "Add env file"
        guard panel.runModal() == .OK, let url = panel.url, var p = project, let i = projects.firstIndex(of: p) else { return }
        if !p.files.contains(url.path) { p.files.append(url.path) }
        projects[i] = p; saveProjects(projects); reload()
    }

    func removeProject() {
        guard let p = project else { return }
        projects.removeAll { $0 == p }; saveProjects(projects)
        projectName = projects.first?.name ?? ""; reload(); targets = defaultTargets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Project", selection: $projectName) {
                    if projects.isEmpty { Text("None yet").tag("") }
                    ForEach(projects) { p in Text(p.name).tag(p.name) }
                }.frame(width: 260)
                .onChange(of: projectName) { reload(); targets = defaultTargets }
                Button("Add project…", action: addProject)
                Button("Add env file…", action: addFile).disabled(project == nil)
                Button("Remove project", action: removeProject).disabled(project == nil)
                Spacer()
                Button("Export .env.example", action: exportExample).disabled(project == nil)
            }
            if !risky.isEmpty {
                Label("Not ignored by git, so it could be committed: " + risky.map { $0.replacingOccurrences(of: home, with: "~") }.joined(separator: ", ") + ". Add it to .gitignore.",
                      systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            }
            GroupBox("Add or update a key") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("NAME, e.g. OPENAI_API_KEY", text: $name).frame(minWidth: 280)
                        Menu("Common") { ForEach(suggested, id: \.self) { s in Button(s) { name = s } } }.frame(width: 100)
                        Button("Paste many…") { importText = ""; importing = true }
                    }
                    SecureField("Paste the value", text: $value)
                    ScrollView(.horizontal) {
                        HStack { ForEach(stores) { s in
                            Toggle(s.label, isOn: Binding(get: { targets.contains(s.id) },
                                                          set: { on in if on { targets.insert(s.id) } else { targets.remove(s.id) } }))
                        } }
                    }
                    HStack {
                        Button("Save and activate") { save([(name, value)]); name = ""; value = "" }.keyboardShortcut(.return)
                        Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.padding(6)
            }
            HStack {
                TextField("Search", text: $filter)
                Button("Reload", action: reload)
                Toggle("Touch ID to show or copy", isOn: $requireUnlock)
                Picker("Clear clipboard", selection: $clearSeconds) {
                    Text("never").tag(0); Text("15 s").tag(15); Text("30 s").tag(30); Text("60 s").tag(60)
                }.frame(width: 190)
            }
            Table(shown) {
                TableColumn("Name") { e in
                    HStack(spacing: 4) {
                        Text(e.name).font(.system(.body, design: .monospaced))
                        if differing.contains(e.name) {
                            Text("differs").font(.caption2).padding(.horizontal, 4).background(.orange.opacity(0.25)).clipShape(Capsule())
                                .help("This name has a different value in another file.")
                        }
                    }
                }
                TableColumn("Where") { e in Text(e.store.label).foregroundStyle(.secondary) }
                TableColumn("Value") { e in
                    Text(revealed.contains(e.id) ? e.value : masked(e.value))
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled).lineLimit(1)
                }
                TableColumn("") { e in
                    HStack {
                        Button(revealed.contains(e.id) ? "Hide" : "Show") {
                            if revealed.contains(e.id) { revealed.remove(e.id) } else { reveal(e) }
                        }
                        Button("Copy") { unlocked { copy(e.value, label: e.name) } }
                        Button("Edit") { name = e.name; value = ""; targets = [e.store.id] }
                        Button("Delete") {
                            do { try write(e.store, name: e.name, value: nil); reload(); status = "Deleted \(e.name) from \(e.store.label)." }
                            catch { status = "Couldn't delete: \(error.localizedDescription)" }
                        }
                    }
                }.width(min: 230)
            }
            Text(project == nil ? "Add a project to manage its .env files. Mac variables live in ~/.zshenv and are pushed to launchctl." :
                 "A .bak copy is kept beside each file on every change, and files are set to owner-only (600).")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(minWidth: 960, minHeight: 560)
        .onAppear { reload(); targets = defaultTargets }
        .sheet(isPresented: $importing) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Paste KEY=VALUE lines, a .env file, or a JSON credentials file").font(.headline)
                TextEditor(text: $importText).font(.system(.body, design: .monospaced)).frame(minWidth: 560, minHeight: 220)
                HStack {
                    TextField("Prefix for JSON keys, e.g. GOOGLE_OAUTH_", text: $importPrefix).frame(width: 300)
                    Spacer()
                    Text("\(parseImport(importText).count) found").foregroundStyle(.secondary)
                    Button("Cancel") { importing = false; importText = "" }
                    Button("Save all") {
                        let isJSON = importText.trimmingCharacters(in: .whitespaces).hasPrefix("{")
                        save(parseImport(importText).map { (isJSON ? importPrefix.uppercased() + $0.0 : $0.0, $0.1) })
                        importing = false; importText = ""
                    }.keyboardShortcut(.return)
                }
                Text("Saves to the places ticked in the main window. Nothing leaves this Mac.").font(.footnote).foregroundStyle(.secondary)
            }.padding(16)
        }
    }
}

@main
struct EnvdeskApp: App {
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene { WindowGroup("envdesk") { ContentView() } }
}
