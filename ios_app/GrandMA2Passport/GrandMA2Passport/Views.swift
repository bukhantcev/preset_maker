import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var xmlMode: ProjectMode = .presets
    @State private var showXmlPicker = false
    @State private var pickedXml: URL?
    @State private var showTitleDialog = false
    @State private var titleInput = ""
    @State private var showCamera = false
    @State private var cameraDevice: UIImagePickerController.CameraDevice = .rear
    @State private var showLibrary = false
    @State private var shareURL: URL?
    @State private var previewURL: URL?

    var body: some View {
        ZStack {
            Brand.black.ignoresSafeArea()
            content
            if showTitleDialog {
                titleDialog
            }
        }
        .foregroundStyle(Brand.text)
        .alert("Ошибка", isPresented: Binding(get: { store.errorText != nil }, set: { if !$0 { store.errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorText ?? "")
        }
        .alert(item: Binding(get: { store.replacePrompt }, set: { if $0 == nil { store.replacePrompt = nil } })) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .destructive(Text(prompt.confirmTitle)) {
                    store.replacePrompt = nil
                    prompt.action()
                },
                secondaryButton: .cancel(Text("Отмена")) {
                    store.replacePrompt = nil
                }
            )
        }
        .sheet(isPresented: $showXmlPicker) {
            DocumentPicker { url in
                DebugLog.write("RootView xml picked callback \(url.path)")
                pickedXml = url
                titleInput = url.deletingPathExtension().lastPathComponent
                showXmlPicker = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    DebugLog.write("RootView show title dialog")
                    showTitleDialog = true
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(device: cameraDevice) { image in
                store.pendingPhoto = image
                store.screen = .presetWorkspace
                showCamera = false
            } onCancel: {
                store.screen = .presetWorkspace
                showCamera = false
            }
        }
        .sheet(isPresented: $showLibrary) {
            ImagePicker(source: .library) { image in
                store.pendingPhoto = image
            }
        }
        .sheet(item: Binding(get: { shareURL.map { ShareURL(url: $0) } }, set: { _ in shareURL = nil })) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(item: Binding(get: { previewURL.map { ShareURL(url: $0) } }, set: { _ in previewURL = nil })) { item in
            FilePreview(url: item.url)
        }
    }

    private var titleDialog: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Название спектакля")
                    .font(.title3.bold())
                    .foregroundStyle(Brand.yellow)
                TextField("Название", text: $titleInput)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(Brand.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.yellow, lineWidth: 1))
                HStack(spacing: 12) {
                    AppButton("Отмена", service: true) {
                        pickedXml = nil
                        showTitleDialog = false
                    }
                    AppButton("Открыть") {
                        DebugLog.write("RootView title dialog open tapped")
                        let url = pickedXml
                        pickedXml = nil
                        showTitleDialog = false
                        if let url {
                            DebugLog.write("RootView create project \(url.path)")
                            store.createProject(from: url, title: titleInput.isEmpty ? "show" : titleInput, mode: xmlMode)
                        }
                    }
                }
            }
            .padding(18)
            .background(Brand.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.yellow, lineWidth: 2))
            .padding(24)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.screen {
        case .start:
            StartView(
                projects: { store.openProjectSource() }
            )
        case .projectSource:
            ProjectSourceView(back: store.goBack)
        case .presetSetup:
            PresetSetupView(
                cameraDevice: $cameraDevice,
                loadXml: { xmlMode = .presets; showXmlPicker = true },
                openProject: { store.openProjectList(.presets) },
                back: store.goBack
            )
        case .partituraSetup:
            PartituraSetupView(
                loadXml: { xmlMode = .partitura; showXmlPicker = true },
                openProject: { store.openProjectList(.partitura) },
                back: store.goBack
            )
        case .projectList(let mode):
            ProjectListView(mode: mode, createProject: { xmlMode = .presets; showXmlPicker = true }, back: store.goBack)
        case .projectMode(let project):
            ProjectModeView(project: project, open: store.openProjectBuilder, files: store.openProjectFiles, back: store.goBack)
        case .projectFiles(let mode):
            ProjectFilesView(mode: mode, open: { previewURL = $0 }, share: { shareURL = $0 }, back: store.goBack)
        case .presetWorkspace:
            PresetWorkspaceView(
                cameraDevice: $cameraDevice,
                takePhoto: { store.screen = .camera; showCamera = true },
                loadPhoto: { showLibrary = true },
                back: {
                    store.savePassportQuietly()
                    store.reloadProjects()
                    store.lastProjectListMode = .presets
                    store.screen = .projectList(.presets)
                }
            )
        case .camera:
            EmptyView().onAppear { showCamera = true }
        case .loading(let message):
            VStack(spacing: 14) {
                Text(message).font(.title2.bold()).foregroundStyle(Brand.yellow)
                if !store.remoteStatus.isEmpty {
                    Text(store.remoteStatus)
                        .font(.headline.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Brand.silver)
                        .padding(.horizontal, 18)
                }
            }
        }
    }
}

private struct ShareURL: Identifiable {
    var id: URL { url }
    var url: URL
}

struct StartView: View {
    @EnvironmentObject var store: AppStore
    var projects: () -> Void
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 360)
                .padding(.horizontal, 18)
            AppButton("Проекты", action: projects)
            AppButton(store.remoteConnected ? "Облако подключено" : "Настройки облака", service: !store.remoteConnected) { showSettings = true }
            Spacer()
        }
        .padding(24)
        .sheet(isPresented: $showSettings) {
            SftpSettingsView()
                .environmentObject(store)
        }
    }
}

struct ProjectSourceView: View {
    @EnvironmentObject var store: AppStore
    var back: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Проекты")
                .font(.largeTitle.bold())
                .foregroundStyle(Brand.text)
            Spacer()
            AppButton("Устройство") { store.openLocalProjects() }
                .frame(minWidth: 260)
            AppButton("Облако") { store.openCloudProjects() }
                .frame(minWidth: 260)
            Text(store.remoteConnected ? "✓ облако подключено" : "облако подключится при открытии")
                .font(.headline.bold())
                .foregroundStyle(store.remoteConnected ? Color.green : Brand.muted)
                .padding(.top, 10)
            Spacer()
            AppButton("Назад", service: true, action: back)
        }
        .padding(24)
    }
}

struct StoragePanel: View {
    @EnvironmentObject var store: AppStore
    @Binding var showSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Хранилище")
                .font(.headline.bold())
                .foregroundStyle(Brand.silver)
            HStack(spacing: 12) {
                storageButton("Локально", selected: !store.remoteSettings.remoteMode) {
                    store.setRemoteMode(false)
                }
                storageButton("Облако", selected: store.remoteSettings.remoteMode) {
                    store.setRemoteMode(true)
                }
            }
            Text(store.remoteSettings.remoteMode ? (store.remoteConnected ? "✓ подключено" : "✕ нет подключения") : "Локально: MA2_passports")
                .font(.headline.bold())
                .foregroundStyle(store.remoteSettings.remoteMode ? (store.remoteConnected ? Color.green : Color.red) : Brand.silver)
            if store.remoteSettings.remoteMode {
                AppButton("Настройка подключения", service: true) {
                    showSettings = true
                }
            }
        }
        .padding(14)
        .background(Brand.panel)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.yellow, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func storageButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.bold())
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
        }
        .foregroundStyle(selected ? Brand.yellow : Brand.silver)
        .background(Brand.black)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Brand.yellow : Brand.silverDark, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SftpSettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var cloudURL = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""
    @State private var remoteDir = RemoteSFTPService.rootName

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                remoteField("SFTP сервер", text: $cloudURL)
                    .keyboardType(.URL)
                remoteField("Порт", text: $port)
                    .keyboardType(.numberPad)
                remoteField("Пользователь", text: $username)
                SecureField("Пароль", text: $password)
                    .padding(12)
                    .background(Brand.panel)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.yellow, lineWidth: 1))
                remoteField("Папка", text: $remoteDir)
                AppButton("Подключить и сохранить") {
                    let parsedPort = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 22
                    let cleanDir = remoteDir.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.saveRemoteSettings(RemoteServerSettings(
                        remoteMode: true,
                        url: cloudURL.trimmingCharacters(in: .whitespacesAndNewlines),
                        port: parsedPort,
                        username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password,
                        remoteDir: cleanDir.isEmpty ? RemoteSFTPService.rootName : cleanDir
                    ))
                    dismiss()
                }
                Spacer()
            }
            .padding(24)
            .background(Brand.black.ignoresSafeArea())
            .foregroundStyle(Brand.text)
            .navigationTitle("Настройка облака")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Назад") { dismiss() }
                        .foregroundStyle(Brand.silver)
                }
            }
            .onAppear {
                cloudURL = store.remoteSettings.url
                port = String(store.remoteSettings.port == 0 ? 22 : store.remoteSettings.port)
                username = store.remoteSettings.username
                password = store.remoteSettings.password
                remoteDir = store.remoteSettings.remoteDir.isEmpty ? RemoteSFTPService.rootName : store.remoteSettings.remoteDir
            }
        }
    }

    private func remoteField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(Brand.panel)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.yellow, lineWidth: 1))
    }
}

struct PresetSetupView: View {
    @Binding var cameraDevice: UIImagePickerController.CameraDevice
    var loadXml: () -> Void
    var openProject: () -> Void
    var back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Камера").foregroundStyle(Brand.silver).font(.title3)
            Picker("", selection: $cameraDevice) {
                Text("Задняя камера").tag(UIImagePickerController.CameraDevice.rear)
                Text("Передняя камера").tag(UIImagePickerController.CameraDevice.front)
            }
            .pickerStyle(.segmented)
            .tint(Brand.silver)
            Text("Проект").font(.title3).padding(.top, 24)
            AppButton("Загрузить XML", action: loadXml)
            AppButton("Открыть проект", action: openProject)
            Spacer()
            AppButton("Назад", service: true, action: back)
        }
        .padding(24)
    }
}

struct PartituraSetupView: View {
    @EnvironmentObject var store: AppStore
    var loadXml: () -> Void
    var openProject: () -> Void
    var back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Партитура").font(.largeTitle)
            if store.projectModeProject?.dir != store.selectedPartituraProject?.dir {
                AppButton("Загрузить XML", action: loadXml)
                AppButton(store.selectedPartituraProject.map { "Проект: \(displayTitle($0.title))" } ?? "Открыть проект", action: openProject)
            } else if let project = store.selectedPartituraProject {
                Text("Проект: \(displayTitle(project.title))")
                    .font(.title3.bold())
                    .foregroundStyle(Brand.silver)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
            Text("Включи нужные поля.").foregroundStyle(Brand.text).padding(.top, 8)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($store.partituraFields) { $field in
                        Toggle("\(index(of: field) + 1). \(field.title)", isOn: $field.enabled)
                            .toggleStyle(.checkboxLike(active: field.enabled))
                            .draggable(field.id)
                            .dropDestination(for: String.self) { items, _ in
                                guard let from = items.first,
                                      let fromIndex = store.partituraFields.firstIndex(where: { $0.id == from }),
                                      let toIndex = store.partituraFields.firstIndex(where: { $0.id == field.id }) else { return false }
                                let moved = store.partituraFields.remove(at: fromIndex)
                                store.partituraFields.insert(moved, at: toIndex)
                                return true
                            }
                    }
                }
            }
            AppButton("Создать партитуру") { store.createPartitura() }
            AppButton("Назад", service: true, action: back)
        }
        .padding(24)
    }

    private func index(of field: PartituraField) -> Int {
        store.partituraFields.firstIndex(where: { $0.id == field.id }) ?? 0
    }
}

struct ProjectListView: View {
    @EnvironmentObject var store: AppStore
    var mode: ProjectMode
    var createProject: () -> Void
    var back: () -> Void
    @State private var renameProject: Project?
    @State private var renameTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.remoteSettings.remoteMode ? "Проекты: облако" : "Проекты: устройство")
                .font(.largeTitle.bold())
            if !store.remoteSettings.remoteMode {
                AppButton("Создать новый проект", action: createProject)
            }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(store.projects) { project in
                        ProjectCard(project: project)
                            .onTapGesture {
                                store.openProjectMode(project)
                            }
                            .contextMenu {
                                if !store.remoteSettings.remoteMode {
                                    Button("Открыть") {
                                        store.openProjectMode(project)
                                    }
                                }
                                Button("Переименовать") {
                                    renameProject = project
                                    renameTitle = displayTitle(project.title)
                                }
                                if store.remoteSettings.remoteMode {
                                    Button("Загрузить на устройство") {
                                        store.requestSaveProjectToLocal(project)
                                    }
                                } else {
                                    Button("Загрузить в облако") {
                                        store.requestSaveProjectToRemote(project)
                                    }
                                }
                                Button("Удалить", role: .destructive) {
                                    if store.remoteSettings.remoteMode {
                                        Task {
                                            try? await RemoteSFTPService.deleteProject(project.dir.lastPathComponent, settings: store.remoteSettings, remoteRoot: store.remoteRootPath)
                                        }
                                    }
                                    try? FileManager.default.removeItem(at: project.dir)
                                    store.reloadProjects()
                                }
                            }
                    }
                }
            }
            AppButton("Назад", service: true, action: back)
        }
        .padding(24)
        .onAppear { store.reloadProjects() }
        .alert("Переименовать проект", isPresented: Binding(get: { renameProject != nil }, set: { if !$0 { renameProject = nil } })) {
            TextField("Название", text: $renameTitle)
            Button("Переименовать") {
                if let project = renameProject {
                    store.renameProject(project, to: renameTitle)
                }
                renameProject = nil
            }
            Button("Отмена", role: .cancel) { renameProject = nil }
        }
    }
}

struct ProjectModeView: View {
    @EnvironmentObject var store: AppStore
    var project: Project
    var open: (Project, ProjectMode) -> Void
    var files: (Project, ProjectMode) -> Void
    var back: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(displayTitle(project.title))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Spacer()
            projectBlock(title: "Пресеты", mode: .presets)
            projectBlock(title: "Партитура", mode: .partitura)
            Spacer()
            AppButton("Назад", service: true, action: back)
        }
        .padding(24)
    }

    private func projectBlock(title: String, mode: ProjectMode) -> some View {
        Button {
            if store.projectModeCloud {
                files(project, mode)
            } else {
                open(project, mode)
            }
        } label: {
            Text(title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 84)
        }
        .foregroundStyle(Brand.yellow)
        .background(Brand.black)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.yellow, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            if !store.projectModeCloud {
                Button("Открыть") {
                    open(project, mode)
                }
            }
            if !store.projectModeCloud {
                Button("Файлы") {
                    files(project, mode)
                }
            }
            if store.projectModeCloud {
                Button("Загрузить на устройство") {
                    store.requestSaveProjectToLocal(project)
                }
            } else {
                Button("Загрузить в облако") {
                    store.requestSaveProjectToRemote(project)
                }
            }
        }
    }
}

struct ProjectFilesView: View {
    @EnvironmentObject var store: AppStore
    var mode: ProjectMode
    var open: (URL) -> Void
    var share: (URL) -> Void
    var back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Файлы").font(.largeTitle)
            ScrollView {
                VStack(spacing: 12) {
                    let files = store.projectFiles(mode: mode)
                    if files.isEmpty {
                        Text("Файлы еще не созданы")
                            .foregroundStyle(Brand.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }
                    ForEach(files, id: \.self) { file in
                        FileCard(file: file)
                            .onTapGesture { open(file) }
                            .contextMenu {
                                Button("Открыть") { open(file) }
                                Button("Отправить") { share(file) }
                                Button("Удалить", role: .destructive) { try? FileManager.default.removeItem(at: file) }
                            }
                    }
                }
            }
            AppButton("Назад", service: true, action: back)
        }
        .padding(24)
    }
}

struct PresetWorkspaceView: View {
    @EnvironmentObject var store: AppStore
    @Binding var cameraDevice: UIImagePickerController.CameraDevice
    var takePhoto: () -> Void
    var loadPhoto: () -> Void
    var back: () -> Void
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            Group {
                if landscape {
                    landscapeBody
                } else {
                    portraitBody
                }
            }
            .padding(landscape ? 10 : 14)
            .contentShape(Rectangle())
            .onTapGesture { hideKeyboard() }
            .gesture(
                DragGesture(minimumDistance: 42)
                    .onEnded { value in
                        if abs(value.translation.width) > abs(value.translation.height) {
                            value.translation.width < 0 ? nextRow() : previousRow()
                        }
                    }
            )
        }
        .onDisappear { store.savePassportQuietly() }
    }

    @ViewBuilder
    private var portraitBody: some View {
        if let row = store.currentRow {
            VStack(spacing: 10) {
                header(row)
                photoArea(row, height: 310)
                descriptionEditor
                Text("Строк: \(store.rows.count)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                cameraPicker
                rowsList
                actionRow(row)
            }
        }
    }

    @ViewBuilder
    private var landscapeBody: some View {
        if let row = store.currentRow {
            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    header(row)
                    photoArea(row, height: nil)
                    actionRow(row)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 8) {
                    HStack {
                        Text("Строк: \(store.rows.count)")
                        Spacer()
                    }
                    cameraPicker
                    descriptionEditor.frame(height: 96)
                    rowsList
                }
                .frame(width: max(320, UIScreen.main.bounds.width * 0.40))
            }
        }
    }

    private func header(_ row: PassportRow) -> some View {
        HStack(spacing: 10) {
            AppButton("Назад", service: true, action: back)
                .frame(width: 112)
            Text("\(store.currentIndex + 1)/\(store.rows.count)  Пресет: \(row.presetLabel)  Прибор: \(row.fixtureId)")
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var descriptionEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(
                get: { store.rows.indices.contains(store.currentIndex) ? store.rows[store.currentIndex].description : "" },
                set: { if store.rows.indices.contains(store.currentIndex) { store.rows[store.currentIndex].description = $0; store.savePassportQuietly() } }
            ))
            .focused($descriptionFocused)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(Brand.panel)
            if store.rows.indices.contains(store.currentIndex),
               store.rows[store.currentIndex].description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Напиши тут описание пресета")
                    .foregroundStyle(Brand.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 86)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.silverDark, lineWidth: 1))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    descriptionFocused = false
                    hideKeyboard()
                }
            }
        }
    }

    private var rowsList: some View {
        List {
            ForEach(Array(store.rows.enumerated()), id: \.element.id) { i, row in
                HStack(spacing: 8) {
                    Image(systemName: row.photoName == nil ? "camera" : "checkmark.circle.fill")
                        .foregroundStyle(i == store.currentIndex ? .black : (row.photoName == nil ? Brand.silver : Brand.yellow))
                        .frame(width: 22)
                    Text("\(row.presetLabel) | \(row.fixtureId) | \(row.description)")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .foregroundStyle(i == store.currentIndex ? .black : Brand.text)
                .listRowBackground(i == store.currentIndex ? Brand.yellow : Brand.panelAlt)
                .onTapGesture {
                    descriptionFocused = false
                    hideKeyboard()
                    store.currentIndex = i
                    store.pendingPhoto = nil
                }
                .contextMenu {
                    Button("Удалить запись", role: .destructive) {
                        store.currentIndex = i
                        store.deleteCurrentRow()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var cameraPicker: some View {
        Picker("", selection: $cameraDevice) {
            Text("Задняя камера").tag(UIImagePickerController.CameraDevice.rear)
            Text("Передняя камера").tag(UIImagePickerController.CameraDevice.front)
        }
        .pickerStyle(.segmented)
        .tint(Brand.silver)
    }

    @ViewBuilder
    private func photoArea(_ row: PassportRow, height: CGFloat?) -> some View {
        ZStack(alignment: .topLeading) {
            Brand.panel
            if let pending = store.pendingPhoto {
                Image(uiImage: pending).resizable().scaledToFit()
            } else if let photo = image(for: row) {
                Image(uiImage: photo).resizable().scaledToFit()
                Button("Удалить") { store.deletePhoto() }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(6)
            } else {
                VStack {
                    AppButton("Загрузить фото", action: loadPhoto)
                    Text("или нажми кнопку Фото внизу").foregroundStyle(Brand.muted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .frame(maxHeight: height == nil ? .infinity : height)
        .clipped()
    }

    @ViewBuilder
    private func actionRow(_ row: PassportRow) -> some View {
        HStack(spacing: 10) {
            if store.pendingPhoto != nil {
                AppButton("Готово") { store.usePendingPhoto() }
                AppButton("Переснять", action: takePhoto)
            } else {
                AppButton(row.photoName == nil ? "Фото" : "Переснять", action: takePhoto)
                if row.photoName != nil {
                    AppButton("Добавить") { store.addRowAfterCurrent() }
                }
            }
        }
    }

    private func image(for row: PassportRow) -> UIImage? {
        guard let name = row.photoName, let photosDir = store.photosDir else { return nil }
        return UIImage(contentsOfFile: photosDir.appendingPathComponent(name).path)
    }

    private func previousRow() {
        guard store.currentIndex > 0 else { return }
        descriptionFocused = false
        hideKeyboard()
        store.currentIndex -= 1
        store.pendingPhoto = nil
    }

    private func nextRow() {
        guard store.currentIndex < store.rows.count - 1 else { return }
        descriptionFocused = false
        hideKeyboard()
        store.currentIndex += 1
        store.pendingPhoto = nil
    }
}

struct AppButton: View {
    var title: String
    var service: Bool
    var action: () -> Void

    init(_ title: String, service: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.service = service
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.bold())
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .foregroundStyle(service ? Brand.silver : Brand.yellow)
        .background(Brand.black)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(service ? Brand.silver : Brand.yellow, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 5)
    }
}

struct ProjectCard: View {
    var project: Project
    var body: some View {
        Text(displayTitle(project.title))
            .font(.title2.bold())
            .foregroundStyle(Brand.yellow)
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(Brand.black)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.yellow, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct FileCard: View {
    var file: URL
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.lastPathComponent).font(.headline.bold()).foregroundStyle(Brand.yellow)
            Text(fileSize(file)).foregroundStyle(Brand.text)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.black)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.yellow, lineWidth: 2))
    }

    private func fileSize(_ url: URL) -> String {
        let bytes = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value) ?? 0
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / 1024.0 / 1024.0)
    }
}

struct CheckboxLikeToggle: ToggleStyle {
    var active: Bool
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                configuration.label
                Spacer()
            }
            .font(.headline.bold())
            .foregroundStyle(configuration.isOn ? Brand.yellow : Brand.silver)
            .padding()
            .background(Brand.panel)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(configuration.isOn ? Brand.yellow : Brand.silverDark, lineWidth: 1))
        }
    }
}

extension ToggleStyle where Self == CheckboxLikeToggle {
    static func checkboxLike(active: Bool) -> CheckboxLikeToggle {
        CheckboxLikeToggle(active: active)
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
