from __future__ import annotations

import re
import sys
import time
import shutil
import tempfile
import io
import queue
import multiprocessing
from zipfile import BadZipFile
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
import xml.etree.ElementTree as ET

try:
    import cv2
    from PIL import Image, ImageTk
    from openpyxl import Workbook, load_workbook
    from openpyxl.drawing.image import Image as XlsxImage
    from openpyxl.styles import Alignment, Font
except ImportError as exc:
    missing = str(exc).split("No module named ")[-1].strip("'")
    print(
        f"Не хватает библиотеки {missing}.\n"
        "Установите зависимости командой:\n"
        "  .venv/bin/pip install -r requirements.txt\n"
        "Потом запустите:\n"
        "  .venv/bin/python main.py"
    )
    sys.exit(1)

import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog, ttk


APP_TITLE = "Паспорт спектакля GrandMA2"


@dataclass(frozen=True)
class PresetItem:
    preset_no: str
    preset_name: str
    fixture_id: str

    @property
    def preset_label(self) -> str:
        if self.preset_no and self.preset_name:
            return f"{self.preset_no} {self.preset_name}"
        return self.preset_name or self.preset_no

    @property
    def file_stem(self) -> str:
        return safe_filename(f"{self.preset_no}_{self.fixture_id}")


@dataclass
class PassportRow:
    preset_label: str
    fixture_id: str
    photo_path: Optional[Path]
    description: str
    skipped: bool = False


@dataclass(frozen=True)
class PartituraRow:
    number: str
    cue_name: str
    time: str
    trigger: str
    info: str


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def child_by_name(parent: ET.Element, name: str) -> Optional[ET.Element]:
    for child in parent:
        if local_name(child.tag) == name:
            return child
    return None


def children_by_name(parent: ET.Element, name: str) -> list[ET.Element]:
    return [child for child in parent if local_name(child.tag) == name]


def natural_key(value: str) -> tuple[int, int | str]:
    return (0, int(value)) if value.isdigit() else (1, value)


def safe_filename(value: str) -> str:
    value = re.sub(r"[^0-9A-Za-zА-Яа-яЁё_.-]+", "_", value, flags=re.UNICODE)
    return value.strip("_") or "photo"


def passport_dir_for_xml(xml_path: Path) -> Path:
    return xml_path.with_suffix("").parent / f"{xml_path.stem}_passport"


def find_existing_presets_xlsx(output_dir: Path) -> Optional[Path]:
    candidates = sorted(path for path in output_dir.glob("*_пресеты.xlsx") if not path.name.startswith("._"))
    if candidates:
        return candidates[0]
    legacy = output_dir / "passport.xlsx"
    if legacy.exists():
        return legacy
    return None


def load_existing_passport(items: list[PresetItem], output_dir: Path, default_title: str) -> tuple[str, list[PassportRow], Optional[str]]:
    xlsx_path = find_existing_presets_xlsx(output_dir)
    title = default_title
    descriptions: dict[tuple[str, str], str] = {}
    warning = None

    if xlsx_path is not None:
        try:
            workbook = load_workbook(xlsx_path, data_only=True)
            sheet = workbook.active
            if sheet["A1"].value:
                title = str(sheet["A1"].value)
            descriptions = read_descriptions_from_sheet(sheet)
        except (BadZipFile, OSError, ValueError) as exc:
            warning = f"Не удалось прочитать таблицу {xlsx_path.name}: {exc}"

    photos_dir = output_dir / "photos"
    rows: list[PassportRow] = []
    for item in items:
        photo_path = find_photo_for_item(item, photos_dir)
        description = descriptions.get((item.preset_label, item.fixture_id), "")
        rows.append(PassportRow(item.preset_label, item.fixture_id, photo_path, description))
    return title, rows, warning


def read_descriptions_from_sheet(sheet) -> dict[tuple[str, str], str]:
    header_row = 2 if sheet.max_row >= 2 and sheet.cell(2, 1).value == "Пресет" else 1
    if sheet.cell(header_row, 1).value != "Пресет":
        return {}
    descriptions: dict[tuple[str, str], str] = {}
    for row in sheet.iter_rows(min_row=header_row + 1, values_only=True):
        preset, fixture, _photo, description = (list(row) + [None, None, None, None])[:4]
        if preset is None or fixture is None:
            continue
        descriptions[(str(preset), str(fixture))] = "" if description is None else str(description)
    return descriptions


def find_photo_for_item(item: PresetItem, photos_dir: Path) -> Optional[Path]:
    if not photos_dir.exists():
        return None
    exact = photos_dir / f"{item.file_stem}.jpg"
    if exact.exists():
        return exact
    matches = sorted(photos_dir.glob(f"{item.file_stem}_*.jpg"))
    return matches[0] if matches else None


def parse_grandma2_presets(xml_path: Path) -> list[PresetItem]:
    tree = ET.parse(xml_path)
    root = tree.getroot()
    ordered: dict[tuple[str, str], set[str]] = {}

    for cue_data in root.iter():
        if local_name(cue_data.tag) != "CueData":
            continue

        channel = child_by_name(cue_data, "Channel")
        preset = child_by_name(cue_data, "Preset")
        if channel is None or preset is None:
            continue

        fixture_id = channel.get("fixture_id") or channel.get("channel_id")
        if not fixture_id:
            continue

        no_parts = [
            (node.text or "").strip()
            for node in children_by_name(preset, "No")
            if (node.text or "").strip() != ""
        ]
        preset_no = ".".join(no_parts)
        preset_name = (preset.get("name") or "").strip()
        key = (preset_no, preset_name)
        ordered.setdefault(key, set()).add(fixture_id)

    result: list[PresetItem] = []
    for (preset_no, preset_name), fixture_ids in ordered.items():
        for fixture_id in sorted(fixture_ids, key=natural_key):
            result.append(PresetItem(preset_no, preset_name, fixture_id))
    return result


def parse_partitura(xml_path: Path) -> list[PartituraRow]:
    tree = ET.parse(xml_path)
    root = tree.getroot()
    rows: list[PartituraRow] = []

    for cue in root.iter():
        if local_name(cue.tag) != "Cue":
            continue

        number_node = child_by_name(cue, "Number")
        if number_node is None:
            continue

        info = ""
        info_items = child_by_name(cue, "InfoItems")
        if info_items is not None:
            info_node = child_by_name(info_items, "Info")
            if info_node is not None and info_node.text:
                info = info_node.text

        trigger_node = child_by_name(cue, "Trigger")
        trigger = trigger_node.get("type") if trigger_node is not None else "Go"
        cue_number = format_cue_number(
            number_node.get("number", ""),
            number_node.get("sub_number", "0"),
        )

        for cue_part in cue.iter():
            if local_name(cue_part.tag) != "CuePart":
                continue
            rows.append(
                PartituraRow(
                    number=cue_number,
                    cue_name=cue_part.get("name", "cue"),
                    time=cue_part.get("basic_fade", "0"),
                    trigger=trigger or "Go",
                    info=info,
                )
            )

    return rows


def format_cue_number(number: str, sub_number: str) -> str:
    if sub_number in ("", "0"):
        return number
    try:
        return f"{number}.{int(int(sub_number) * 0.01)}"
    except ValueError:
        return f"{number}.{sub_number}"


def source_from_text(value: str):
    value = value.strip()
    value = value.split()[0] if value else "0"
    if value.isdigit():
        return int(value)
    return value


def camera_backends_for_source(source) -> list[int]:
    if isinstance(source, int) and sys.platform == "darwin":
        return [cv2.CAP_AVFOUNDATION, cv2.CAP_ANY]
    return [cv2.CAP_ANY]


def open_capture(source):
    for backend in camera_backends_for_source(source):
        capture = cv2.VideoCapture(source, backend)
        if not capture.isOpened():
            capture.release()
            continue
        capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        return capture, backend
    return None, None


def camera_worker(source_value, frame_queue, stop_event) -> None:
    capture, backend = open_capture(source_value)
    if capture is None:
        frame_queue.put(("error", "Камера не открылась"))
        return

    backend_name = "AVFoundation" if backend == cv2.CAP_AVFOUNDATION else "default"
    deadline = time.time() + 3
    connected = False

    try:
        while not stop_event.is_set():
            ok, frame = capture.read()
            if not ok or frame is None:
                if not connected and time.time() >= deadline:
                    frame_queue.put(("error", "Камера открылась, но не дала кадр"))
                    return
                time.sleep(0.05)
                continue

            ok, encoded = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 85])
            if not ok:
                continue

            if not connected:
                frame_queue.put(("connected", backend_name))
                connected = True

            try:
                frame_queue.put_nowait(("frame", encoded.tobytes(), time.time()))
            except queue.Full:
                pass

            time.sleep(0.03)
    finally:
        capture.release()


class PassportApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(APP_TITLE)
        self.geometry("1120x760")
        self.minsize(980, 680)

        self.xml_path: Optional[Path] = None
        self.output_dir: Optional[Path] = None
        self.photos_dir: Optional[Path] = None
        self.show_title = ""
        self.items: list[PresetItem] = []
        self.rows: list[PassportRow] = []
        self.index = 0
        self.workflow_running = False
        self.loading_description = False
        self.syncing_selection = False

        self.camera_running = False
        self.camera_opening = False
        self.camera_connect_id = 0
        self.camera_last_frame_time = 0.0
        self.camera_process: Optional[multiprocessing.Process] = None
        self.camera_queue = None
        self.camera_stop_event = None
        self.current_frame_bytes: Optional[bytes] = None
        self.preview_image = None
        self.captured_temp: Optional[Path] = None
        self.reviewing_photo = False

        self._build_ui()
        self.after(200, self.ask_xml_on_start)
        self.protocol("WM_DELETE_WINDOW", self.on_close)

    def _build_ui(self) -> None:
        self.columnconfigure(0, weight=1)
        self.rowconfigure(1, weight=1)

        toolbar = ttk.Frame(self, padding=(12, 10))
        toolbar.grid(row=0, column=0, sticky="ew")
        toolbar.columnconfigure(6, weight=1)

        ttk.Button(toolbar, text="Открыть XML", command=self.choose_xml).grid(row=0, column=0, padx=(0, 8))
        self.partitura_button = ttk.Button(toolbar, text="Партитура", command=self.export_partitura, state="disabled")
        self.partitura_button.grid(row=0, column=1, padx=(0, 12))
        ttk.Label(toolbar, text="Камера:").grid(row=0, column=2, padx=(0, 6))
        self.camera_source_var = tk.StringVar(value="0")
        self.camera_source = ttk.Combobox(
            toolbar,
            textvariable=self.camera_source_var,
            values=["0 FaceTime", "1 iPhone", "2", "3", "0", "1"],
            width=22,
        )
        self.camera_source.grid(row=0, column=3, padx=(0, 8))
        ttk.Button(toolbar, text="Подключить", command=self.connect_camera).grid(row=0, column=4, padx=(0, 8))
        ttk.Button(toolbar, text="Остановить", command=self.stop_camera).grid(row=0, column=5, padx=(0, 12))

        self.summary_var = tk.StringVar(value="Выберите XML файл GrandMA2")
        ttk.Label(toolbar, textvariable=self.summary_var).grid(row=0, column=6, sticky="w")

        main = ttk.Frame(self, padding=(12, 0, 12, 12))
        main.grid(row=1, column=0, sticky="nsew")
        main.columnconfigure(0, weight=3)
        main.columnconfigure(1, weight=2)
        main.rowconfigure(0, weight=1)

        left = ttk.Frame(main)
        left.grid(row=0, column=0, sticky="nsew", padx=(0, 12))
        left.columnconfigure(0, weight=1)
        left.rowconfigure(2, weight=1)

        self.current_var = tk.StringVar(value="Пока нет загруженного файла")
        ttk.Label(left, textvariable=self.current_var, font=("", 16, "bold")).grid(row=0, column=0, sticky="ew", pady=(0, 10))

        description_frame = ttk.Frame(left)
        description_frame.grid(row=1, column=0, sticky="ew", pady=(0, 10))
        description_frame.columnconfigure(0, weight=1)
        ttk.Label(description_frame, text="Описание:").grid(row=0, column=0, sticky="w", pady=(0, 4))
        self.description_text = tk.Text(description_frame, height=3, wrap="word")
        self.description_text.grid(row=1, column=0, sticky="ew")
        self.description_text.bind("<KeyRelease>", self.on_description_changed)

        self.video_label = ttk.Label(left, anchor="center", background="#111111")
        self.video_label.grid(row=2, column=0, sticky="nsew")

        controls = ttk.Frame(left, padding=(0, 10, 0, 0))
        controls.grid(row=3, column=0, sticky="ew")
        for col in range(6):
            controls.columnconfigure(col, weight=1)

        self.start_button = ttk.Button(controls, text="Начать", command=self.toggle_workflow, state="disabled")
        self.start_button.grid(row=0, column=0, sticky="ew", padx=(0, 6))
        self.photo_button = ttk.Button(controls, text="Фото", command=self.take_photo, state="disabled")
        self.photo_button.grid(row=0, column=1, sticky="ew", padx=6)
        self.use_button = ttk.Button(controls, text="Использовать", command=self.use_photo, state="disabled")
        self.use_button.grid(row=0, column=2, sticky="ew", padx=6)
        self.retake_button = ttk.Button(controls, text="Переснять", command=self.retake_photo, state="disabled")
        self.retake_button.grid(row=0, column=3, sticky="ew", padx=6)
        self.skip_button = ttk.Button(controls, text="Пропустить", command=self.skip_item, state="disabled")
        self.skip_button.grid(row=0, column=4, sticky="ew", padx=6)
        self.export_button = ttk.Button(controls, text="Экспорт XLSX", command=self.export_xlsx, state="disabled")
        self.export_button.grid(row=0, column=5, sticky="ew", padx=(6, 0))
        self.hide_review_buttons()

        right = ttk.Frame(main)
        right.grid(row=0, column=1, sticky="nsew")
        right.columnconfigure(0, weight=1)
        right.rowconfigure(1, weight=1)

        self.progress_var = tk.StringVar(value="0 / 0")
        ttk.Label(right, textvariable=self.progress_var, font=("", 13, "bold")).grid(row=0, column=0, sticky="ew", pady=(0, 8))

        columns = ("preset", "fixture", "description")
        self.table = ttk.Treeview(right, columns=columns, show="headings", height=22)
        self.table.heading("preset", text="Пресет")
        self.table.heading("fixture", text="Прибор")
        self.table.heading("description", text="Описание")
        self.table.column("preset", width=250)
        self.table.column("fixture", width=80, anchor="center")
        self.table.column("description", width=170)
        self.table.grid(row=1, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(right, orient="vertical", command=self.table.yview)
        scroll.grid(row=1, column=1, sticky="ns")
        self.table.configure(yscrollcommand=scroll.set)
        self.table.bind("<<TreeviewSelect>>", self.on_table_select)
        self.table.bind("<Button-2>", self.show_table_menu)
        self.table.bind("<Button-3>", self.show_table_menu)

        table_actions = ttk.Frame(right, padding=(0, 8, 0, 0))
        table_actions.grid(row=2, column=0, sticky="ew")
        table_actions.columnconfigure(0, weight=1)
        table_actions.columnconfigure(1, weight=1)
        self.delete_button = ttk.Button(table_actions, text="Удалить", command=self.delete_selected_result, state="disabled")
        self.delete_button.grid(row=0, column=0, sticky="ew", padx=(0, 6))
        self.retake_selected_button = ttk.Button(
            table_actions,
            text="Переснять",
            command=self.retake_selected_result,
            state="disabled",
        )
        self.retake_selected_button.grid(row=0, column=1, sticky="ew")

        self.table_menu = tk.Menu(self, tearoff=False)
        self.table_menu.add_command(label="Удалить", command=self.delete_selected_result)
        self.table_menu.add_command(label="Переснять", command=self.retake_selected_result)

    def ask_xml_on_start(self) -> None:
        if messagebox.askyesno(APP_TITLE, "Выбрать XML файл спектакля GrandMA2?"):
            self.choose_xml()

    def choose_xml(self) -> None:
        filename = filedialog.askopenfilename(
            title="Выберите XML GrandMA2",
            filetypes=[("GrandMA2 XML", "*.xml"), ("Все файлы", "*.*")],
        )
        if not filename:
            return
        self.load_xml(Path(filename))

    def load_xml(self, path: Path) -> None:
        try:
            items = parse_grandma2_presets(path)
        except Exception as exc:
            messagebox.showerror(APP_TITLE, f"Не удалось прочитать XML:\n{exc}")
            return

        if not items:
            messagebox.showwarning(APP_TITLE, "В файле не нашлось пресетов с приборами.")
            return

        output_dir = passport_dir_for_xml(path)
        is_existing_project = output_dir.exists()
        load_warning = None
        if is_existing_project:
            show_title, rows, load_warning = load_existing_passport(items, output_dir, path.stem)
        else:
            show_title = simpledialog.askstring(
                APP_TITLE,
                "Название спектакля:",
                initialvalue=path.stem,
                parent=self,
            )
            if show_title is None:
                return
            show_title = show_title.strip() or path.stem
            rows = [PassportRow(item.preset_label, item.fixture_id, None, "") for item in items]

        self.xml_path = path
        self.show_title = show_title
        self.items = items
        self.rows = rows
        self.index = 0
        self.workflow_running = False
        self.reviewing_photo = False
        self.clear_description()
        self.output_dir = output_dir
        self.photos_dir = self.output_dir / "photos"
        self.photos_dir.mkdir(parents=True, exist_ok=True)
        self.refresh_table()
        for row_index in range(len(self.rows)):
            self.mark_table_row(row_index)
        presets_count = len({(item.preset_no, item.preset_name) for item in items})
        self.summary_var.set(f"{path.name}: пресетов {presets_count}, строк с приборами {len(items)}")
        self.current_var.set("Проект открыт для редактирования." if is_existing_project else "Файл загружен. Нажмите «Начать».")
        self.update_progress()
        self.start_button.configure(text="Начать", command=self.toggle_workflow, state="normal")
        self.export_button.configure(state="normal")
        self.partitura_button.configure(state="normal")
        if is_existing_project:
            loaded_photos = sum(1 for row in self.rows if row.photo_path and row.photo_path.exists())
            loaded_descriptions = sum(1 for row in self.rows if row.description)
            warning_text = f"\n\n{load_warning}" if load_warning else ""
            messagebox.showinfo(
                APP_TITLE,
                f"Открыт существующий паспорт:\n{self.output_dir}\n\n"
                f"Пресетов: {presets_count}\n"
                f"Строк с приборами: {len(items)}\n"
                f"Фото загружено: {loaded_photos}\n"
                f"Описаний загружено: {loaded_descriptions}"
                f"{warning_text}"
            )
        else:
            messagebox.showinfo(
                APP_TITLE,
                f"Найдено пресетов: {presets_count}\n"
                f"Приборов в пресетах: {len(items)}\n\n"
                "Можно начинать проход."
            )

    def toggle_workflow(self) -> None:
        if self.workflow_running:
            self.stop_workflow(save_result=True)
        else:
            self.start_workflow()

    def start_workflow(self) -> None:
        if not self.items:
            return
        if self.camera_opening:
            return
        if self.camera_running:
            self.finish_start_workflow()
            return
        messagebox.showwarning(APP_TITLE, "Сначала нажмите «Подключить» и дождитесь изображения с камеры.")

    def finish_start_workflow(self) -> None:
        if self.workflow_running:
            return
        self.workflow_running = True
        self.index = min(self.index, len(self.items) - 1)
        self.photo_button.configure(state="normal")
        self.skip_button.configure(state="normal")
        self.start_button.configure(text="Стоп", command=self.toggle_workflow, state="normal")
        self.after_idle(self.show_current_item)

    def cancel_camera_opening(self) -> None:
        self.stop_camera()
        self.workflow_running = False
        self.start_button.configure(text="Начать", command=self.toggle_workflow, state="normal")
        self.summary_var.set("Подключение камеры отменено")

    def stop_workflow(self, save_result: bool) -> None:
        self.save_current_description()
        self.workflow_running = False
        self.reviewing_photo = False
        if self.captured_temp and self.captured_temp.exists():
            self.captured_temp.unlink()
        self.captured_temp = None
        self.photo_button.configure(state="disabled")
        self.skip_button.configure(state="disabled")
        self.hide_review_buttons()
        self.start_button.configure(text="Начать", command=self.toggle_workflow, state="normal")
        if save_result:
            saved_path = self.export_xlsx(show_message=False)
            if saved_path is not None:
                messagebox.showinfo(APP_TITLE, f"Проход остановлен. Текущий результат сохранён:\n{saved_path}")

    def connect_camera(self, on_connected=None) -> None:
        if self.camera_opening:
            return
        self.stop_camera()
        self.camera_connect_id += 1
        source = source_from_text(self.camera_source_var.get())
        self.camera_opening = True
        self.summary_var.set("Подключаю камеру...")

        context = multiprocessing.get_context("spawn")
        self.camera_queue = context.Queue(maxsize=3)
        self.camera_stop_event = context.Event()
        self.camera_process = context.Process(
            target=camera_worker,
            args=(source, self.camera_queue, self.camera_stop_event),
            daemon=True,
        )
        self.camera_process.start()
        self.after(50, lambda: self.poll_camera(on_connected))

    def poll_camera(self, on_connected=None) -> None:
        if self.camera_queue is None:
            return

        got_frame = False
        try:
            while True:
                message = self.camera_queue.get_nowait()
                kind = message[0]
                if kind == "connected":
                    self.camera_opening = False
                    self.camera_running = True
                    self.summary_var.set(f"Камера подключена ({message[1]})")
                    if on_connected:
                        callback = on_connected
                        on_connected = None
                        callback()
                elif kind == "frame":
                    self.current_frame_bytes = message[1]
                    self.camera_last_frame_time = message[2]
                    got_frame = True
                elif kind == "error":
                    self.handle_camera_error(message[1])
                    return
        except queue.Empty:
            pass

        if got_frame and not self.reviewing_photo and self.current_frame_bytes is not None:
            self.show_frame_bytes(self.current_frame_bytes)

        if self.camera_process is not None and self.camera_process.exitcode is not None:
            if self.camera_process.exitcode != 0:
                self.handle_camera_error(f"Драйвер камеры упал, код {self.camera_process.exitcode}")
                return

        if self.camera_running or self.camera_opening:
            if self.camera_running and time.time() - self.camera_last_frame_time > 2:
                self.summary_var.set("Камера подключена, жду кадр...")
            self.after(30, lambda: self.poll_camera(on_connected))

    def handle_camera_error(self, detail: str) -> None:
        self.stop_camera()
        self.workflow_running = False
        self.photo_button.configure(state="disabled")
        self.skip_button.configure(state="disabled")
        self.hide_review_buttons()
        if self.items:
            self.start_button.configure(text="Начать", command=self.toggle_workflow, state="normal")
        self.summary_var.set("Камера не подключилась")
        messagebox.showerror(
            APP_TITLE,
            f"{detail}.\n\n"
            "Попробуйте источник «1 iPhone» или другой номер: 0, 1, 2, 3.\n"
            "Если macOS спросит доступ к камере, разрешите его для Python/Terminal/PyCharm."
        )

    def stop_camera(self) -> None:
        self.camera_opening = False
        self.camera_running = False
        self.camera_connect_id += 1
        if self.camera_stop_event is not None:
            self.camera_stop_event.set()
        if self.camera_process is not None and self.camera_process.is_alive():
            self.camera_process.join(timeout=0.5)
            if self.camera_process.is_alive():
                self.camera_process.terminate()
        self.camera_process = None
        self.camera_queue = None
        self.camera_stop_event = None

    def show_frame_bytes(self, frame_bytes: bytes) -> None:
        image = Image.open(io.BytesIO(frame_bytes))
        label_width = max(self.video_label.winfo_width(), 640)
        label_height = max(self.video_label.winfo_height(), 420)
        image.thumbnail((label_width, label_height))
        self.preview_image = ImageTk.PhotoImage(image)
        self.video_label.configure(image=self.preview_image)

    def show_photo_preview(self, path: Path) -> None:
        image = Image.open(path)
        label_width = max(self.video_label.winfo_width(), 640)
        label_height = max(self.video_label.winfo_height(), 420)
        image.thumbnail((label_width, label_height))
        self.preview_image = ImageTk.PhotoImage(image)
        self.video_label.configure(image=self.preview_image)

    def show_current_item(self) -> None:
        if self.index >= len(self.items):
            self.finish_workflow()
            return
        item = self.items[self.index]
        row = self.rows[self.index]
        self.current_var.set(
            f"{self.index + 1}/{len(self.items)}  Пресет: {item.preset_label}   Прибор: {item.fixture_id}"
        )
        self.update_progress()
        self.syncing_selection = True
        self.table.selection_set(str(self.index))
        self.table.see(str(self.index))
        self.after_idle(self.clear_selection_sync)
        self.load_description(row.description)
        self.photo_button.configure(state="normal" if self.workflow_running else "disabled")
        self.skip_button.configure(state="normal" if self.workflow_running else "disabled")
        self.hide_review_buttons()
        if row.photo_path and row.photo_path.exists():
            self.reviewing_photo = True
            self.show_photo_preview(row.photo_path)
        else:
            self.reviewing_photo = False
        self.update_row_action_buttons()

    def clear_selection_sync(self) -> None:
        self.syncing_selection = False

    def take_photo(self) -> None:
        if self.current_frame_bytes is None:
            messagebox.showwarning(APP_TITLE, "Нет кадра с камеры.")
            return
        tmp_dir = Path(tempfile.gettempdir()) / "grandma2_passport"
        tmp_dir.mkdir(parents=True, exist_ok=True)
        self.captured_temp = tmp_dir / f"capture_{int(time.time() * 1000)}.jpg"
        self.captured_temp.write_bytes(self.current_frame_bytes)
        self.reviewing_photo = True
        self.show_photo_preview(self.captured_temp)
        self.photo_button.configure(state="disabled")
        self.skip_button.configure(state="disabled")
        self.show_review_buttons()

    def use_photo(self) -> None:
        if self.captured_temp is None or self.photos_dir is None:
            return
        item = self.items[self.index]
        target = self.unique_photo_path(item.file_stem)
        self.delete_photo_file(self.rows[self.index].photo_path)
        shutil.move(str(self.captured_temp), target)
        self.captured_temp = None
        self.reviewing_photo = False
        description = self.get_description()
        self.rows[self.index] = PassportRow(item.preset_label, item.fixture_id, target, description)
        self.mark_table_row(self.index)
        self.index = self.next_index_after_save()
        self.show_current_item()

    def retake_photo(self) -> None:
        if self.captured_temp and self.captured_temp.exists():
            self.captured_temp.unlink()
        self.captured_temp = None
        self.reviewing_photo = False
        self.photo_button.configure(state="normal")
        self.skip_button.configure(state="normal")
        self.hide_review_buttons()

    def skip_item(self) -> None:
        item = self.items[self.index]
        description = self.get_description()
        self.delete_photo_file(self.rows[self.index].photo_path)
        self.rows[self.index] = PassportRow(item.preset_label, item.fixture_id, None, description, True)
        self.mark_table_row(self.index)
        self.index = self.next_index_after_save()
        self.show_current_item()

    def unique_photo_path(self, stem: str) -> Path:
        assert self.photos_dir is not None
        path = self.photos_dir / f"{stem}.jpg"
        counter = 2
        while path.exists():
            path = self.photos_dir / f"{stem}_{counter}.jpg"
            counter += 1
        return path

    def finish_workflow(self) -> None:
        self.current_var.set("Готово. Можно экспортировать XLSX.")
        self.update_progress()
        self.photo_button.configure(state="disabled")
        self.skip_button.configure(state="disabled")
        self.hide_review_buttons()
        self.workflow_running = False
        self.stop_camera()
        self.start_button.configure(text="Начать", command=self.toggle_workflow, state="normal")
        self.export_button.configure(state="normal")
        messagebox.showinfo(APP_TITLE, "Весь список пройден. Экспортируйте таблицу XLSX.")

    def show_review_buttons(self) -> None:
        self.use_button.grid()
        self.retake_button.grid()
        self.use_button.configure(state="normal")
        self.retake_button.configure(state="normal")

    def hide_review_buttons(self) -> None:
        self.use_button.configure(state="disabled")
        self.retake_button.configure(state="disabled")
        self.use_button.grid_remove()
        self.retake_button.grid_remove()

    def refresh_table(self) -> None:
        self.table.delete(*self.table.get_children())
        for i, item in enumerate(self.items):
            self.table.insert("", "end", iid=str(i), values=(item.preset_label, item.fixture_id, ""))

    def mark_table_row(self, row_index: int) -> None:
        item = self.items[row_index]
        row = self.rows[row_index]
        description = row.description
        if row.photo_path and row.photo_path.exists():
            description = f"фото {description}" if description else "фото"
        elif row.skipped:
            description = f"пропуск {description}" if description else "пропуск"
        self.table.item(str(row_index), values=(item.preset_label, item.fixture_id, description))

    def get_description(self) -> str:
        return self.description_text.get("1.0", "end").strip()

    def clear_description(self) -> None:
        self.loading_description = True
        self.description_text.delete("1.0", "end")
        self.loading_description = False

    def load_description(self, description: str) -> None:
        self.loading_description = True
        self.description_text.delete("1.0", "end")
        if description:
            self.description_text.insert("1.0", description)
        self.loading_description = False

    def on_description_changed(self, _event=None) -> None:
        if self.loading_description or not self.rows:
            return
        self.rows[self.index].description = self.get_description()
        self.mark_table_row(self.index)

    def save_current_description(self) -> None:
        if not self.rows or self.index >= len(self.rows):
            return
        self.rows[self.index].description = self.get_description()
        self.mark_table_row(self.index)

    def on_table_select(self, _event=None) -> None:
        if self.syncing_selection:
            return
        selection = self.table.selection()
        if not selection:
            return
        selected_index = int(selection[0])
        if selected_index == self.index:
            return
        self.save_current_description()
        self.index = selected_index
        if self.captured_temp and self.captured_temp.exists():
            self.captured_temp.unlink()
            self.captured_temp = None
        self.show_current_item()

    def show_table_menu(self, event) -> None:
        row_id = self.table.identify_row(event.y)
        if not row_id:
            return
        self.table.selection_set(row_id)
        self.on_table_select()
        row = self.rows[int(row_id)]
        can_delete = bool(row.photo_path or row.description or row.skipped)
        self.table_menu.entryconfigure("Удалить", state="normal" if can_delete else "disabled")
        self.table_menu.entryconfigure(
            "Переснять",
            label="Переснять" if row.photo_path else "Добавить фото",
            state="normal" if self.workflow_running else "disabled",
        )
        self.table_menu.tk_popup(event.x_root, event.y_root)

    def update_row_action_buttons(self) -> None:
        if not self.rows:
            self.delete_button.configure(state="disabled")
            self.retake_selected_button.configure(state="disabled", text="Переснять")
            return
        row = self.rows[self.index]
        can_delete = bool(row.photo_path or row.description or row.skipped)
        self.delete_button.configure(state="normal" if can_delete else "disabled")
        self.retake_selected_button.configure(
            text="Переснять" if row.photo_path else "Добавить фото",
            state="normal" if self.workflow_running else "disabled",
        )

    def delete_selected_result(self) -> None:
        if not self.rows:
            return
        self.delete_photo_file(self.rows[self.index].photo_path)
        item = self.items[self.index]
        self.rows[self.index] = PassportRow(item.preset_label, item.fixture_id, None, "")
        self.mark_table_row(self.index)
        self.load_description("")
        self.reviewing_photo = False
        if self.workflow_running:
            self.photo_button.configure(state="normal")
            self.skip_button.configure(state="normal")
        self.update_progress()
        self.update_row_action_buttons()

    def retake_selected_result(self) -> None:
        if not self.workflow_running:
            messagebox.showwarning(APP_TITLE, "Нажмите «Начать», чтобы включить камеру.")
            return
        self.save_current_description()
        self.delete_photo_file(self.rows[self.index].photo_path)
        self.rows[self.index].photo_path = None
        self.rows[self.index].skipped = False
        self.mark_table_row(self.index)
        self.reviewing_photo = False
        self.photo_button.configure(state="normal")
        self.skip_button.configure(state="normal")
        self.hide_review_buttons()
        self.update_progress()
        self.update_row_action_buttons()

    def delete_photo_file(self, path: Optional[Path]) -> None:
        if path and path.exists():
            path.unlink()

    def update_progress(self) -> None:
        done = sum(1 for row in self.rows if (row.photo_path and row.photo_path.exists()) or row.skipped)
        self.progress_var.set(f"{done} / {len(self.items)} готово")

    def next_index_after_save(self) -> int:
        for offset in range(1, len(self.items) + 1):
            candidate = (self.index + offset) % len(self.items)
            row = self.rows[candidate]
            if not row.photo_path and not row.skipped:
                return candidate
        return len(self.items)

    def export_xlsx(self, show_message: bool = True) -> Optional[Path]:
        if not self.items or self.output_dir is None:
            return None
        self.save_current_description()
        export_rows = self.rows[:]

        xlsx_path = self.output_dir / f"{safe_filename(self.show_title)}_пресеты.xlsx"
        try:
            create_xlsx(export_rows, xlsx_path, self.show_title)
        except Exception as exc:
            messagebox.showerror(APP_TITLE, f"Не удалось экспортировать XLSX:\n{exc}")
            return None
        if show_message:
            messagebox.showinfo(APP_TITLE, f"Таблица сохранена:\n{xlsx_path}")
        return xlsx_path

    def export_partitura(self) -> None:
        if self.xml_path is None or self.output_dir is None:
            messagebox.showwarning(APP_TITLE, "Сначала выберите XML файл.")
            return
        xlsx_path = self.output_dir / f"{safe_filename(self.show_title)}_партитура.xlsx"
        try:
            rows = parse_partitura(self.xml_path)
            create_partitura_xlsx(rows, xlsx_path, self.show_title)
        except Exception as exc:
            messagebox.showerror(APP_TITLE, f"Не удалось экспортировать партитуру:\n{exc}")
            return
        messagebox.showinfo(APP_TITLE, f"Партитура сохранена:\n{xlsx_path}")

    def on_close(self) -> None:
        self.stop_camera()
        self.destroy()


def create_xlsx(rows: list[PassportRow], path: Path, title: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    wb = Workbook()
    ws = wb.active
    ws.title = "Паспорт"
    ws.append([title])
    ws.merge_cells("A1:D1")
    ws.append(["Пресет", "Прибор", "Фото", "Описание"])

    ws["A1"].font = Font(bold=True, size=16)
    ws["A1"].alignment = Alignment(horizontal="center", vertical="center")
    ws.row_dimensions[1].height = 28

    for cell in ws[2]:
        cell.font = Font(bold=True)
        cell.alignment = Alignment(horizontal="center", vertical="center")

    ws.column_dimensions["A"].width = 42
    ws.column_dimensions["B"].width = 12
    ws.column_dimensions["C"].width = 42
    ws.column_dimensions["D"].width = 24

    photo_width = 300
    photo_height = 190

    with tempfile.TemporaryDirectory() as temp_dir:
        prepared_photos: list[Path] = []
        for row_index, row in enumerate(rows, start=3):
            ws.cell(row=row_index, column=1, value=row.preset_label)
            ws.cell(row=row_index, column=2, value=row.fixture_id)
            ws.cell(row=row_index, column=4, value=row.description)
            ws.row_dimensions[row_index].height = 145
            for column in range(1, 5):
                ws.cell(row=row_index, column=column).alignment = Alignment(vertical="center", wrap_text=True)

            if row.photo_path and row.photo_path.exists():
                prepared = Path(temp_dir) / f"photo_{row_index}.png"
                create_cell_photo(row.photo_path, prepared, photo_width, photo_height)
                prepared_photos.append(prepared)
                img = XlsxImage(str(prepared))
                img.width = photo_width
                img.height = photo_height
                ws.add_image(img, f"C{row_index}")

        ws.freeze_panes = "A3"
        wb.save(path)


def create_cell_photo(source: Path, target: Path, width: int, height: int) -> None:
    with Image.open(source) as image:
        image = image.convert("RGB")
        image.thumbnail((width, height))
        canvas = Image.new("RGB", (width, height), "white")
        left = (width - image.width) // 2
        top = (height - image.height) // 2
        canvas.paste(image, (left, top))
        canvas.save(target)


def create_partitura_xlsx(rows: list[PartituraRow], path: Path, title: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    wb = Workbook()
    ws = wb.active
    ws.title = "Партитура"
    ws.append([title])
    ws.merge_cells("A1:E1")
    ws.append(["Номер", "Реплика", "Время", "Триггер", "Информация"])

    ws["A1"].font = Font(bold=True, size=16)
    ws["A1"].alignment = Alignment(horizontal="center", vertical="center")
    ws.row_dimensions[1].height = 28

    for cell in ws[2]:
        cell.font = Font(bold=True)
        cell.alignment = Alignment(horizontal="center", vertical="center")

    ws.column_dimensions["A"].width = 12
    ws.column_dimensions["B"].width = 60
    ws.column_dimensions["C"].width = 12
    ws.column_dimensions["D"].width = 14
    ws.column_dimensions["E"].width = 60

    for row in rows:
        ws.append([row.number, row.cue_name, row.time, row.trigger, row.info])

    for sheet_row in ws.iter_rows(min_row=3):
        for cell in sheet_row:
            cell.alignment = Alignment(vertical="top", wrap_text=True)

    ws.freeze_panes = "A3"
    wb.save(path)


def print_xml_summary(xml_path: Path) -> None:
    items = parse_grandma2_presets(xml_path)
    presets_count = len({(item.preset_no, item.preset_name) for item in items})
    print(f"XML: {xml_path}")
    print(f"Пресетов: {presets_count}")
    print(f"Строк пресет-прибор: {len(items)}")
    for item in items[:10]:
        print(f"  {item.preset_label} | fixture {item.fixture_id}")
    if len(items) > 10:
        print("  ...")


def print_camera_check() -> None:
    context = multiprocessing.get_context("spawn")
    for index in range(6):
        frame_queue = context.Queue(maxsize=3)
        stop_event = context.Event()
        process = context.Process(target=camera_worker, args=(index, frame_queue, stop_event), daemon=True)
        process.start()
        backend_name = ""
        got_frame = False
        error = ""
        deadline = time.time() + 5
        while time.time() < deadline:
            if process.exitcode is not None:
                break
            try:
                message = frame_queue.get(timeout=0.2)
            except queue.Empty:
                continue
            if message[0] == "connected":
                backend_name = message[1]
            elif message[0] == "frame":
                got_frame = True
                break
            elif message[0] == "error":
                error = message[1]
                break
        stop_event.set()
        process.join(timeout=0.5)
        if process.is_alive():
            process.terminate()
        if process.exitcode not in (None, 0):
            print(f"{index}: процесс камеры упал, код {process.exitcode}")
        elif got_frame:
            print(f"{index}: OK, backend={backend_name}")
        else:
            print(f"{index}: нет кадра {error}".strip())


if __name__ == "__main__":
    multiprocessing.freeze_support()
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        print_xml_summary(Path(sys.argv[2]))
    elif len(sys.argv) == 2 and sys.argv[1] == "--camera-check":
        print_camera_check()
    else:
        app = PassportApp()
        app.mainloop()
