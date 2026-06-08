from __future__ import annotations

import io
import multiprocessing
import os
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from zipfile import BadZipFile
import xml.etree.ElementTree as ET

try:
    import cv2
    from PIL import Image, ImageDraw, ImageFont, ImageTk
    from openpyxl import Workbook, load_workbook
    from openpyxl.drawing.image import Image as XlsxImage
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
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


APP_TITLE = "Passport creator"
PROJECT_ROOT = Path.home() / "Documents" / "MA2_passports"
PHOTO_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".heic", ".heif"}
XML_EXTENSIONS = {".xml"}

BLACK = "#000000"
PANEL = "#141414"
PANEL_2 = "#202020"
YELLOW = "#ffb800"
SILVER = "#cfcfcf"
MUTED = "#9c9c9c"
RED = "#ff4545"


@dataclass(frozen=True)
class PresetItem:
    preset_no: str
    preset_name: str
    fixture_id: str

    @property
    def preset_label(self) -> str:
        return self.preset_name.strip() or self.preset_no.strip()

    @property
    def file_stem(self) -> str:
        return safe_filename(f"{self.preset_no}_{self.fixture_id}")


@dataclass
class PassportRow:
    preset_label: str
    fixture_id: str
    preset_no: str
    photo_path: Optional[Path] = None
    description: str = ""

    @property
    def group_key(self) -> tuple[str, str, str]:
        return (self.preset_label, self.fixture_id, self.preset_no)

    @property
    def file_stem(self) -> str:
        return safe_filename(f"{self.preset_no}_{self.fixture_id}")


@dataclass(frozen=True)
class PartituraRow:
    number: str
    name: str
    fade: str
    downfade: str
    delay: str
    trigger: str
    trigger_time: str
    info: str
    command: str

    def value(self, field_id: str) -> str:
        return {
            "number": self.number,
            "name": self.name,
            "fade": self.fade,
            "downfade": self.downfade,
            "delay": self.delay,
            "trigger": self.trigger,
            "trigger_time": self.trigger_time,
            "info": self.info,
            "command": self.command,
        }.get(field_id, "")


@dataclass
class PartituraField:
    field_id: str
    title: str
    enabled: bool


@dataclass(frozen=True)
class Project:
    title: str
    directory: Path
    xml_path: Path


PARTITURA_DEFAULT_FIELDS = [
    PartituraField("number", "Номер", True),
    PartituraField("name", "Реплика", True),
    PartituraField("trigger", "Trigger", False),
    PartituraField("trigger_time", "Trigger time", False),
    PartituraField("fade", "Fade", True),
    PartituraField("downfade", "Downfade", False),
    PartituraField("delay", "Delay", False),
    PartituraField("info", "Инфо", True),
    PartituraField("command", "Command", False),
]


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def child_by_name(parent: ET.Element, name: str) -> Optional[ET.Element]:
    for child in parent:
        if local_name(child.tag) == name:
            return child
    return None


def children_by_name(parent: ET.Element, name: str) -> list[ET.Element]:
    return [child for child in parent if local_name(child.tag) == name]


def first_non_empty(*values: Optional[str]) -> str:
    for value in values:
        text = (value or "").strip()
        if text:
            return text
    return ""


def natural_key(value: str) -> tuple[int, int | str]:
    return (0, int(value)) if value.isdigit() else (1, value)


def safe_filename(value: str) -> str:
    value = re.sub(r"[^0-9A-Za-zА-Яа-яЁё_. -]+", "_", value, flags=re.UNICODE)
    value = re.sub(r"\s+", " ", value).strip(" ._")
    return value or "show"


def project_dir_for_title(title: str) -> Path:
    return PROJECT_ROOT / safe_filename(title)


def display_title(value: str) -> str:
    return value.replace("_", " ")


def ensure_project_root() -> None:
    PROJECT_ROOT.mkdir(parents=True, exist_ok=True)


def project_xml_path(project_dir: Path) -> Optional[Path]:
    xmls = sorted(path for path in project_dir.iterdir() if path.suffix.lower() in XML_EXTENSIONS and path.is_file())
    return xmls[0] if xmls else None


def list_projects() -> list[Project]:
    ensure_project_root()
    projects: list[Project] = []
    for directory in sorted([path for path in PROJECT_ROOT.iterdir() if path.is_dir()], key=lambda p: p.name.lower()):
        xml_path = project_xml_path(directory)
        if xml_path:
            projects.append(Project(display_title(directory.name), directory, xml_path))
    return projects


def copy_xml_to_project(source: Path, title: str) -> Project:
    ensure_project_root()
    project_dir = project_dir_for_title(title)
    project_dir.mkdir(parents=True, exist_ok=True)
    target = project_dir / f"{safe_filename(title)}.xml"
    if source.resolve() != target.resolve():
        shutil.copy2(source, target)
    return Project(display_title(title), project_dir, target)


def preset_xlsx_path(project_dir: Path, title: str) -> Path:
    return project_dir / f"{safe_filename(title)}_пресеты.xlsx"


def preset_pdf_path(project_dir: Path, title: str) -> Path:
    return project_dir / f"{safe_filename(title)}_пресеты.pdf"


def partitura_xlsx_path(project_dir: Path, title: str) -> Path:
    return project_dir / f"{safe_filename(title)}_партитура.xlsx"


def partitura_pdf_path(project_dir: Path, title: str) -> Path:
    return project_dir / f"{safe_filename(title)}_партитура.pdf"


def photos_dir(project_dir: Path) -> Path:
    path = project_dir / "photos"
    path.mkdir(parents=True, exist_ok=True)
    return path


def find_existing_presets_xlsx(project_dir: Path) -> Optional[Path]:
    candidates = sorted(path for path in project_dir.glob("*_пресеты.xlsx") if not path.name.startswith("._"))
    if candidates:
        return candidates[0]
    legacy = project_dir / "passport.xlsx"
    return legacy if legacy.exists() else None


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
        preset_name = (preset.get("name") or "").strip()
        no_parts = [
            (node.text or "").strip()
            for node in children_by_name(preset, "No")
            if (node.text or "").strip()
        ]
        preset_no = ".".join(no_parts)
        if not fixture_id or not preset_name or not preset_no:
            continue

        ordered.setdefault((preset_no, preset_name), set()).add(fixture_id)

    result: list[PresetItem] = []
    for (preset_no, preset_name), fixture_ids in ordered.items():
        for fixture_id in sorted(fixture_ids, key=natural_key):
            result.append(PresetItem(preset_no, preset_name, fixture_id))
    return result


def format_cue_number(number: str, sub_number: str) -> str:
    if not sub_number or sub_number == "0":
        return number
    try:
        value = int(sub_number)
        if value % 100 == 0:
            return f"{number}.{value // 100}"
        if value % 10 == 0:
            return f"{number}.{value // 10}"
        return f"{number}.{value}"
    except ValueError:
        return f"{number}.{sub_number}"


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

        cue_number = format_cue_number(number_node.get("number", ""), number_node.get("sub_number", "0"))
        trigger_node = child_by_name(cue, "Trigger")
        trigger = trigger_node.get("type") if trigger_node is not None else "Go"
        trigger_time = trigger_node.get("data_f", "") if trigger_node is not None else ""
        cue_info = ""
        cue_command = ""

        info_items = child_by_name(cue, "InfoItems")
        if info_items is not None:
            info_node = child_by_name(info_items, "Info")
            if info_node is not None and info_node.text:
                cue_info = info_node.text.strip()

        for child in cue:
            if local_name(child.tag) in {"Command", "Cmd", "CueCommand", "CLI", "CommandLine"}:
                cue_command = first_non_empty(
                    child.get("command"),
                    child.get("cmd"),
                    child.get("command_text"),
                    child.text,
                    cue_command,
                )

        for cue_part in cue.iter():
            if local_name(cue_part.tag) != "CuePart":
                continue
            if (cue_part.get("index") or "0") != "0":
                continue

            part_info = ""
            part_command = ""
            for child in cue_part.iter():
                if child is cue_part:
                    continue
                child_name = local_name(child.tag)
                if child_name == "Info" and child.text:
                    part_info = child.text.strip()
                elif child_name in {"Command", "Cmd", "CueCommand", "CLI", "CommandLine"}:
                    part_command = first_non_empty(
                        child.get("command"),
                        child.get("cmd"),
                        child.get("command_text"),
                        child.text,
                        part_command,
                    )

            rows.append(
                PartituraRow(
                    number=cue_number,
                    name=cue_part.get("name", "cue"),
                    fade=cue_part.get("basic_fade", "0"),
                    downfade=cue_part.get("basic_downfade", ""),
                    delay=cue_part.get("basic_delay", ""),
                    trigger=trigger or "Go",
                    trigger_time=trigger_time,
                    info=part_info or cue_info,
                    command=part_command or cue_command,
                )
            )
    return rows


def find_photo_for_stem(stem: str, photo_dir: Path) -> Optional[Path]:
    for extension in [".jpg", ".jpeg", ".png", ".webp", ".bmp"]:
        exact = photo_dir / f"{stem}{extension}"
        if exact.exists():
            return exact
    matches = sorted(
        path
        for path in photo_dir.glob(f"{stem}_*")
        if path.suffix.lower() in PHOTO_EXTENSIONS and path.is_file()
    )
    return matches[0] if matches else None


def read_passport_rows_from_sheet(sheet, item_by_group: dict[tuple[str, str], PresetItem]) -> list[PassportRow]:
    header_row = 2 if sheet.max_row >= 2 and sheet.cell(2, 1).value == "Пресет" else 1
    if sheet.cell(header_row, 1).value != "Пресет":
        return []

    rows: list[PassportRow] = []
    last_preset = ""
    last_fixture = ""
    for values in sheet.iter_rows(min_row=header_row + 1, values_only=True):
        preset, fixture, _photo, description = (list(values) + [None, None, None, None])[:4]
        preset_text = str(preset).strip() if preset is not None else last_preset
        fixture_text = str(fixture).strip() if fixture is not None else last_fixture
        description_text = "" if description is None else str(description)
        if not preset_text and not fixture_text and not description_text.strip():
            continue
        last_preset = preset_text
        last_fixture = fixture_text
        item = item_by_group.get((preset_text, fixture_text))
        preset_no = item.preset_no if item else ""
        rows.append(PassportRow(preset_text, fixture_text, preset_no, None, description_text))
    return rows


def load_passport_rows(items: list[PresetItem], project_dir: Path, title: str) -> tuple[list[PassportRow], Optional[str]]:
    item_by_group = {(item.preset_label, item.fixture_id): item for item in items}
    photo_dir = photos_dir(project_dir)
    xlsx_path = find_existing_presets_xlsx(project_dir)
    warning = None
    rows: list[PassportRow] = []

    if xlsx_path is not None:
        try:
            workbook = load_workbook(xlsx_path, data_only=True)
            rows = read_passport_rows_from_sheet(workbook.active, item_by_group)
        except (BadZipFile, OSError, ValueError) as exc:
            warning = f"Не удалось прочитать таблицу {xlsx_path.name}: {exc}"

    if not rows:
        rows = [PassportRow(item.preset_label, item.fixture_id, item.preset_no) for item in items]

    existing_groups = {(row.preset_label, row.fixture_id) for row in rows}
    for item in items:
        if (item.preset_label, item.fixture_id) not in existing_groups:
            rows.append(PassportRow(item.preset_label, item.fixture_id, item.preset_no))

    counters: dict[str, int] = {}
    for row in rows:
        if not row.preset_no:
            item = item_by_group.get((row.preset_label, row.fixture_id))
            row.preset_no = item.preset_no if item else ""
        stem = row.file_stem
        counters[stem] = counters.get(stem, 0) + 1
        if counters[stem] == 1:
            row.photo_path = find_photo_for_stem(stem, photo_dir)
        else:
            row.photo_path = find_photo_for_stem(f"{stem}_{counters[stem]}", photo_dir)
    return rows, warning


def source_from_text(value: str):
    value = value.strip().split()[0] if value.strip() else "0"
    return int(value) if value.isdigit() else value


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
                time.sleep(0.04)
                continue

            ok, encoded = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 92])
            if not ok:
                continue
            if not connected:
                frame_queue.put(("connected", backend_name))
                connected = True
            try:
                frame_queue.put_nowait(("frame", encoded.tobytes(), time.time()))
            except queue.Full:
                pass
            time.sleep(0.025)
    finally:
        capture.release()


class PlaceholderText(tk.Text):
    def __init__(self, master, placeholder: str, **kwargs):
        super().__init__(master, **kwargs)
        self.placeholder = placeholder
        self.placeholder_visible = False
        self.bind("<FocusIn>", self._hide_placeholder)
        self.bind("<FocusOut>", self._show_placeholder_if_empty)
        self._show_placeholder_if_empty()

    def _hide_placeholder(self, _event=None) -> None:
        if self.placeholder_visible:
            self.delete("1.0", "end")
            self.configure(foreground="white")
            self.placeholder_visible = False

    def _show_placeholder_if_empty(self, _event=None) -> None:
        if self.get("1.0", "end").strip():
            return
        self.placeholder_visible = True
        self.configure(foreground=MUTED)
        self.delete("1.0", "end")
        self.insert("1.0", self.placeholder)

    def real_text(self) -> str:
        if self.placeholder_visible:
            return ""
        return self.get("1.0", "end").strip()

    def set_real_text(self, value: str) -> None:
        self.placeholder_visible = False
        self.configure(foreground="white")
        self.delete("1.0", "end")
        if value:
            self.insert("1.0", value)
        self._show_placeholder_if_empty()


class PassportApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(APP_TITLE)
        self.geometry("1180x780")
        self.minsize(980, 680)
        self.configure(bg=BLACK)

        self.project: Optional[Project] = None
        self.mode = "start"
        self.items: list[PresetItem] = []
        self.rows: list[PassportRow] = []
        self.partitura_fields = [PartituraField(f.field_id, f.title, f.enabled) for f in PARTITURA_DEFAULT_FIELDS]
        self.index = 0
        self.loading_description = False
        self.syncing_selection = False
        self.reviewing_photo = False
        self.captured_temp: Optional[Path] = None

        self.camera_running = False
        self.camera_opening = False
        self.camera_process: Optional[multiprocessing.Process] = None
        self.camera_queue = None
        self.camera_stop_event = None
        self.camera_last_frame_time = 0.0
        self.current_frame_bytes: Optional[bytes] = None
        self.preview_image = None

        self.frames: dict[str, tk.Frame] = {}
        self._configure_style()
        self._build_pages()
        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.show_start()

    def _configure_style(self) -> None:
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure(".", background=BLACK, foreground="white", fieldbackground=PANEL, bordercolor=YELLOW)
        style.configure("TFrame", background=BLACK)
        style.configure("Panel.TFrame", background=PANEL)
        style.configure("TLabel", background=BLACK, foreground="white")
        style.configure("Title.TLabel", background=BLACK, foreground=YELLOW, font=("", 22, "bold"))
        style.configure("Yellow.TButton", background=BLACK, foreground=YELLOW, bordercolor=YELLOW, focusthickness=2, focuscolor=YELLOW, padding=8)
        style.map("Yellow.TButton", background=[("active", PANEL_2)], foreground=[("disabled", MUTED)])
        style.configure("Silver.TButton", background=BLACK, foreground=SILVER, bordercolor=SILVER, padding=8)
        style.map("Silver.TButton", background=[("active", PANEL_2)], foreground=[("disabled", MUTED)])
        style.configure("Danger.TButton", background=BLACK, foreground=RED, bordercolor=RED, padding=6)
        style.configure("Treeview", background=PANEL, foreground="white", fieldbackground=PANEL, rowheight=30, bordercolor=BLACK)
        style.configure("Treeview.Heading", background=BLACK, foreground=YELLOW, font=("", 11, "bold"))
        style.map("Treeview", background=[("selected", YELLOW)], foreground=[("selected", BLACK)])
        style.configure("TCheckbutton", background=BLACK, foreground="white")
        style.map("TCheckbutton", foreground=[("disabled", MUTED)])
        style.configure("TCombobox", fieldbackground=PANEL, background=PANEL, foreground="white")

    def _build_pages(self) -> None:
        container = tk.Frame(self, bg=BLACK)
        container.pack(fill="both", expand=True)
        for name in ["start", "preset_setup", "project_list", "files", "workspace", "partitura"]:
            frame = tk.Frame(container, bg=BLACK)
            frame.grid(row=0, column=0, sticky="nsew")
            self.frames[name] = frame
        container.rowconfigure(0, weight=1)
        container.columnconfigure(0, weight=1)
        self._build_start_page()
        self._build_preset_setup_page()
        self._build_project_list_page()
        self._build_files_page()
        self._build_workspace_page()
        self._build_partitura_page()

    def show_frame(self, name: str) -> None:
        self.mode = name
        self.frames[name].tkraise()

    def _logo_widget(self, parent, large: bool = False):
        logo_path = Path(__file__).parent / "ios_app/GrandMA2Passport/GrandMA2Passport/Assets.xcassets/Logo.imageset/logoPC.png"
        if logo_path.exists():
            image = Image.open(logo_path)
            size = (240, 240) if large else (120, 120)
            image.thumbnail(size)
            photo = ImageTk.PhotoImage(image)
            label = tk.Label(parent, image=photo, bg=BLACK)
            label.image = photo
            return label
        return ttk.Label(parent, text=APP_TITLE, style="Title.TLabel")

    def _build_start_page(self) -> None:
        frame = self.frames["start"]
        frame.columnconfigure(0, weight=1)
        frame.rowconfigure(0, weight=1)
        content = tk.Frame(frame, bg=BLACK)
        content.grid(row=0, column=0)
        self._logo_widget(content, large=True).pack(pady=(0, 28))
        ttk.Button(content, text="Пресеты", style="Yellow.TButton", command=self.show_preset_setup).pack(fill="x", pady=8, ipady=8)
        ttk.Button(content, text="Партитура", style="Yellow.TButton", command=self.show_partitura).pack(fill="x", pady=8, ipady=8)

    def _build_preset_setup_page(self) -> None:
        frame = self.frames["preset_setup"]
        frame.columnconfigure(0, weight=1)
        top = tk.Frame(frame, bg=BLACK)
        top.grid(row=0, column=0, sticky="ew", padx=18, pady=18)
        ttk.Button(top, text="Назад", style="Silver.TButton", command=self.show_start).pack(side="left")
        ttk.Label(top, text="Пресеты", style="Title.TLabel").pack(side="left", padx=18)

        body = tk.Frame(frame, bg=BLACK)
        body.grid(row=1, column=0, sticky="nsew", padx=36, pady=20)
        body.columnconfigure(0, weight=1)

        camera = tk.Frame(body, bg=PANEL)
        camera.grid(row=0, column=0, sticky="ew", pady=(0, 24))
        camera.columnconfigure(1, weight=1)
        tk.Label(camera, text="Камера", bg=PANEL, fg=SILVER, font=("", 13, "bold")).grid(row=0, column=0, padx=14, pady=14, sticky="w")
        self.camera_source_var = tk.StringVar(value="0 iPhone")
        self.camera_source = ttk.Combobox(camera, textvariable=self.camera_source_var, values=["0 iPhone", "1 FaceTime", "2", "3"], width=28)
        self.camera_source.grid(row=0, column=1, padx=8, sticky="ew")
        self.zoom_var = tk.DoubleVar(value=1.0)
        ttk.Button(camera, text="Подключить", style="Silver.TButton", command=self.connect_camera).grid(row=0, column=2, padx=8)
        ttk.Button(camera, text="Остановить", style="Silver.TButton", command=self.stop_camera).grid(row=0, column=3, padx=(0, 14))

        actions = tk.Frame(body, bg=BLACK)
        actions.grid(row=1, column=0, sticky="ew")
        actions.columnconfigure(0, weight=1)
        actions.columnconfigure(1, weight=1)
        ttk.Button(actions, text="Открыть проект", style="Yellow.TButton", command=lambda: self.show_project_list("presets")).grid(row=0, column=0, sticky="ew", padx=(0, 10), ipady=12)
        ttk.Button(actions, text="Загрузить XML", style="Yellow.TButton", command=self.create_preset_project_from_xml).grid(row=0, column=1, sticky="ew", padx=(10, 0), ipady=12)

        self.preset_setup_status = tk.StringVar(value=f"Проекты хранятся в {PROJECT_ROOT}")
        ttk.Label(body, textvariable=self.preset_setup_status).grid(row=2, column=0, sticky="w", pady=20)

    def _build_project_list_page(self) -> None:
        frame = self.frames["project_list"]
        frame.columnconfigure(0, weight=1)
        frame.rowconfigure(2, weight=1)
        top = tk.Frame(frame, bg=BLACK)
        top.grid(row=0, column=0, sticky="ew", padx=18, pady=18)
        ttk.Button(top, text="Назад", style="Silver.TButton", command=self.back_from_project_list).pack(side="left")
        self.project_list_title = tk.StringVar(value="Проекты")
        ttk.Label(top, textvariable=self.project_list_title, style="Title.TLabel").pack(side="left", padx=18)

        self.project_listbox = tk.Listbox(frame, bg=PANEL, fg="white", selectbackground=YELLOW, selectforeground=BLACK, font=("", 22), activestyle="none")
        self.project_listbox.grid(row=2, column=0, sticky="nsew", padx=36, pady=(0, 14))
        self.project_listbox.bind("<Double-Button-1>", lambda _e: self.open_selected_project())
        self.project_listbox.bind("<Return>", lambda _e: self.open_selected_project())
        self.project_listbox.bind("<Button-3>", self.show_project_menu)
        self.project_listbox.bind("<Button-2>", self.show_project_menu)

        buttons = tk.Frame(frame, bg=BLACK)
        buttons.grid(row=3, column=0, sticky="ew", padx=36, pady=(0, 24))
        buttons.columnconfigure((0, 1, 2, 3), weight=1)
        ttk.Button(buttons, text="Открыть", style="Yellow.TButton", command=self.open_selected_project).grid(row=0, column=0, sticky="ew", padx=(0, 8))
        ttk.Button(buttons, text="Файлы", style="Silver.TButton", command=self.open_selected_project_files).grid(row=0, column=1, sticky="ew", padx=8)
        ttk.Button(buttons, text="Переименовать", style="Silver.TButton", command=self.rename_selected_project).grid(row=0, column=2, sticky="ew", padx=8)
        ttk.Button(buttons, text="Удалить", style="Danger.TButton", command=self.delete_selected_project).grid(row=0, column=3, sticky="ew", padx=(8, 0))

        self.project_menu = tk.Menu(self, tearoff=False)
        self.project_menu.add_command(label="Открыть", command=self.open_selected_project)
        self.project_menu.add_command(label="Файлы", command=self.open_selected_project_files)
        self.project_menu.add_command(label="Переименовать", command=self.rename_selected_project)
        self.project_menu.add_command(label="Удалить", command=self.delete_selected_project)

    def _build_files_page(self) -> None:
        frame = self.frames["files"]
        frame.columnconfigure(0, weight=1)
        frame.rowconfigure(1, weight=1)
        top = tk.Frame(frame, bg=BLACK)
        top.grid(row=0, column=0, sticky="ew", padx=18, pady=18)
        ttk.Button(top, text="Назад", style="Silver.TButton", command=self.back_from_files).pack(side="left")
        self.files_title = tk.StringVar(value="Файлы")
        ttk.Label(top, textvariable=self.files_title, style="Title.TLabel").pack(side="left", padx=18)

        self.files_listbox = tk.Listbox(frame, bg=PANEL, fg="white", selectbackground=YELLOW, selectforeground=BLACK, font=("", 15), activestyle="none")
        self.files_listbox.grid(row=1, column=0, sticky="nsew", padx=36, pady=(0, 14))
        self.files_listbox.bind("<Double-Button-1>", lambda _e: self.open_selected_file())
        self.files_listbox.bind("<Return>", lambda _e: self.open_selected_file())
        self.files_listbox.bind("<Button-3>", self.show_file_menu)
        self.files_listbox.bind("<Button-2>", self.show_file_menu)

        buttons = tk.Frame(frame, bg=BLACK)
        buttons.grid(row=2, column=0, sticky="ew", padx=36, pady=(0, 24))
        buttons.columnconfigure((0, 1, 2), weight=1)
        ttk.Button(buttons, text="Открыть", style="Yellow.TButton", command=self.open_selected_file).grid(row=0, column=0, sticky="ew", padx=(0, 8))
        ttk.Button(buttons, text="Показать в папке", style="Silver.TButton", command=self.reveal_selected_file).grid(row=0, column=1, sticky="ew", padx=8)
        ttk.Button(buttons, text="Удалить", style="Danger.TButton", command=self.delete_selected_file).grid(row=0, column=2, sticky="ew", padx=(8, 0))

        self.file_menu = tk.Menu(self, tearoff=False)
        self.file_menu.add_command(label="Открыть", command=self.open_selected_file)
        self.file_menu.add_command(label="Показать в папке", command=self.reveal_selected_file)
        self.file_menu.add_command(label="Удалить", command=self.delete_selected_file)

    def _build_workspace_page(self) -> None:
        frame = self.frames["workspace"]
        frame.columnconfigure(0, weight=3)
        frame.columnconfigure(1, weight=2)
        frame.rowconfigure(1, weight=1)

        top = tk.Frame(frame, bg=BLACK)
        top.grid(row=0, column=0, columnspan=2, sticky="ew", padx=14, pady=12)
        ttk.Button(top, text="Назад", style="Silver.TButton", command=lambda: self.show_project_list("presets")).pack(side="left", padx=(0, 8))
        ttk.Button(top, text="Файлы", style="Yellow.TButton", command=lambda: self.show_files("presets")).pack(side="left", padx=8)
        self.workspace_summary = tk.StringVar(value="")
        ttk.Label(top, textvariable=self.workspace_summary).pack(side="left", padx=16)

        left = tk.Frame(frame, bg=BLACK)
        left.grid(row=1, column=0, sticky="nsew", padx=(14, 8), pady=(0, 14))
        left.columnconfigure(0, weight=1)
        left.rowconfigure(2, weight=1)

        self.current_var = tk.StringVar(value="")
        ttk.Label(left, textvariable=self.current_var, font=("", 16, "bold")).grid(row=0, column=0, sticky="ew", pady=(0, 8))

        self.video_container = tk.Frame(left, bg=PANEL)
        self.video_container.grid(row=1, column=0, sticky="nsew", pady=(0, 10))
        self.video_container.columnconfigure(0, weight=1)
        self.video_container.rowconfigure(0, weight=1)
        self.video_label = tk.Label(self.video_container, bg=PANEL, fg=SILVER, text="", font=("", 16), compound="center")
        self.video_label.grid(row=0, column=0, sticky="nsew")
        self.delete_photo_button = ttk.Button(self.video_container, text="Удалить", style="Danger.TButton", command=self.delete_current_photo)
        self.delete_photo_button.place_forget()

        description_frame = tk.Frame(left, bg=BLACK)
        description_frame.grid(row=2, column=0, sticky="nsew", pady=(0, 10))
        description_frame.columnconfigure(0, weight=1)
        description_frame.rowconfigure(0, weight=1)
        self.description_text = PlaceholderText(
            description_frame,
            "Напиши тут описание пресета.",
            height=4,
            wrap="word",
            bg=PANEL,
            fg="white",
            insertbackground=YELLOW,
            relief="flat",
            padx=10,
            pady=10,
        )
        self.description_text.grid(row=0, column=0, sticky="nsew")
        self.description_text.bind("<KeyRelease>", self.on_description_changed)

        controls = tk.Frame(left, bg=BLACK)
        controls.grid(row=3, column=0, sticky="ew")
        controls.columnconfigure((0, 1, 2, 3, 4), weight=1)
        self.photo_button = ttk.Button(controls, text="Фото", style="Yellow.TButton", command=self.take_photo)
        self.photo_button.grid(row=0, column=0, sticky="ew", padx=(0, 8))
        self.upload_photo_button = ttk.Button(controls, text="Загрузить фото", style="Yellow.TButton", command=self.upload_photo)
        self.upload_photo_button.grid(row=0, column=1, sticky="ew", padx=8)
        self.use_button = ttk.Button(controls, text="Готово", style="Yellow.TButton", command=self.use_photo)
        self.use_button.grid(row=0, column=2, sticky="ew", padx=8)
        self.retake_button = ttk.Button(controls, text="Переснять", style="Yellow.TButton", command=self.retake_photo)
        self.retake_button.grid(row=0, column=3, sticky="ew", padx=8)
        self.add_row_button = ttk.Button(controls, text="Добавить", style="Yellow.TButton", command=self.add_extra_row)
        self.add_row_button.grid(row=0, column=4, sticky="ew", padx=(8, 0))

        zoom_controls = tk.Frame(controls, bg=BLACK)
        zoom_controls.grid(row=1, column=0, columnspan=5, sticky="ew", pady=(10, 0))
        zoom_controls.columnconfigure(1, weight=1)
        tk.Label(zoom_controls, text="Зум", bg=BLACK, fg=SILVER, font=("", 11, "bold")).grid(row=0, column=0, padx=(0, 10))
        self.zoom_scale = tk.Scale(
            zoom_controls,
            from_=1.0,
            to=5.0,
            resolution=0.1,
            variable=self.zoom_var,
            orient="horizontal",
            bg=BLACK,
            fg=YELLOW,
            troughcolor=PANEL,
            highlightthickness=0,
            activebackground=YELLOW,
            command=lambda _v: self.refresh_zoom_preview(),
        )
        self.zoom_scale.grid(row=0, column=1, sticky="ew")

        right = tk.Frame(frame, bg=BLACK)
        right.grid(row=1, column=1, sticky="nsew", padx=(8, 14), pady=(0, 14))
        right.columnconfigure(0, weight=1)
        right.rowconfigure(1, weight=1)
        self.progress_var = tk.StringVar(value="0 / 0")
        ttk.Label(right, textvariable=self.progress_var, font=("", 13, "bold")).grid(row=0, column=0, sticky="ew", pady=(0, 8))
        columns = ("photo", "preset", "fixture", "description")
        self.table = ttk.Treeview(right, columns=columns, show="headings", height=22)
        self.table.heading("photo", text="Фото")
        self.table.heading("preset", text="Пресет")
        self.table.heading("fixture", text="Прибор")
        self.table.heading("description", text="Описание")
        self.table.column("photo", width=54, anchor="center")
        self.table.column("preset", width=230)
        self.table.column("fixture", width=80, anchor="center")
        self.table.column("description", width=160)
        self.table.grid(row=1, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(right, orient="vertical", command=self.table.yview)
        scroll.grid(row=1, column=1, sticky="ns")
        self.table.configure(yscrollcommand=scroll.set)
        self.table.bind("<<TreeviewSelect>>", self.on_table_select)
        self.table.bind("<Button-3>", self.show_table_menu)
        self.table.bind("<Button-2>", self.show_table_menu)
        self.table_menu = tk.Menu(self, tearoff=False)
        self.table_menu.add_command(label="Удалить запись", command=self.delete_current_row)

    def _build_partitura_page(self) -> None:
        frame = self.frames["partitura"]
        frame.columnconfigure(0, weight=1)
        frame.rowconfigure(3, weight=1)
        top = tk.Frame(frame, bg=BLACK)
        top.grid(row=0, column=0, sticky="ew", padx=18, pady=18)
        ttk.Button(top, text="Назад", style="Silver.TButton", command=self.show_start).pack(side="left")
        ttk.Label(top, text="Партитура", style="Title.TLabel").pack(side="left", padx=18)

        actions = tk.Frame(frame, bg=BLACK)
        actions.grid(row=1, column=0, sticky="ew", padx=36, pady=(0, 18))
        actions.columnconfigure((0, 1), weight=1)
        ttk.Button(actions, text="Открыть проект", style="Yellow.TButton", command=lambda: self.show_project_list("partitura")).grid(row=0, column=0, sticky="ew", padx=(0, 10), ipady=8)
        ttk.Button(actions, text="Загрузить XML", style="Yellow.TButton", command=self.create_partitura_project_from_xml).grid(row=0, column=1, sticky="ew", padx=(10, 0), ipady=8)

        self.partitura_project_var = tk.StringVar(value="Проект не выбран")
        ttk.Label(frame, textvariable=self.partitura_project_var).grid(row=2, column=0, sticky="nw", padx=36)

        fields_frame = tk.Frame(frame, bg=BLACK)
        fields_frame.grid(row=3, column=0, sticky="nsew", padx=36, pady=18)
        fields_frame.columnconfigure(0, weight=1)
        fields_frame.rowconfigure(0, weight=1)
        self.field_listbox = tk.Listbox(fields_frame, bg=PANEL, fg="white", selectbackground=YELLOW, selectforeground=BLACK, font=("", 22), height=9, activestyle="none")
        self.field_listbox.grid(row=0, column=0, sticky="nsew")
        field_buttons = tk.Frame(fields_frame, bg=BLACK)
        field_buttons.grid(row=0, column=1, sticky="ns", padx=(12, 0))
        ttk.Button(field_buttons, text="Вкл/выкл", style="Silver.TButton", command=self.toggle_partitura_field).pack(fill="x", pady=(0, 12), ipady=8)
        ttk.Button(field_buttons, text="Вверх", style="Silver.TButton", command=lambda: self.move_partitura_field(-1)).pack(fill="x", pady=12, ipady=8)
        ttk.Button(field_buttons, text="Вниз", style="Silver.TButton", command=lambda: self.move_partitura_field(1)).pack(fill="x", pady=12, ipady=8)
        self.refresh_partitura_fields()

        bottom = tk.Frame(frame, bg=BLACK)
        bottom.grid(row=4, column=0, sticky="ew", padx=36, pady=(0, 28))
        bottom.columnconfigure(0, weight=1)
        ttk.Button(bottom, text="Создать партитуру", style="Yellow.TButton", command=self.create_partitura_files).grid(row=0, column=0, sticky="ew", ipady=10)

    def show_start(self) -> None:
        self.show_frame("start")

    def show_preset_setup(self) -> None:
        self.show_frame("preset_setup")

    def show_partitura(self) -> None:
        self.show_frame("partitura")

    def back_from_project_list(self) -> None:
        self.show_partitura() if self.project_list_mode == "partitura" else self.show_preset_setup()

    def back_from_files(self) -> None:
        self.show_partitura() if self.files_mode == "partitura" else self.show_project_list("presets")

    def show_project_list(self, mode: str) -> None:
        self.project_list_mode = mode
        self.project_list_title.set("Проекты партитуры" if mode == "partitura" else "Проекты пресетов")
        self.projects = list_projects()
        self.project_listbox.delete(0, "end")
        for project in self.projects:
            self.project_listbox.insert("end", project.title)
        self.show_frame("project_list")

    def selected_project(self) -> Optional[Project]:
        selection = self.project_listbox.curselection()
        if not selection:
            messagebox.showwarning(APP_TITLE, "Выберите проект.")
            return None
        return self.projects[selection[0]]

    def show_project_menu(self, event) -> None:
        index = self.project_listbox.nearest(event.y)
        self.project_listbox.selection_clear(0, "end")
        self.project_listbox.selection_set(index)
        self.project_menu.tk_popup(event.x_root, event.y_root)

    def open_selected_project(self) -> None:
        project = self.selected_project()
        if not project:
            return
        if self.project_list_mode == "partitura":
            self.project = project
            self.partitura_project_var.set(f"Активный проект: {project.title}")
            self.show_partitura()
        else:
            self.open_preset_project(project)

    def open_selected_project_files(self) -> None:
        project = self.selected_project()
        if not project:
            return
        self.project = project
        self.show_files(self.project_list_mode)

    def rename_selected_project(self) -> None:
        project = self.selected_project()
        if not project:
            return
        new_title = simpledialog.askstring(APP_TITLE, "Новое название проекта:", initialvalue=project.title, parent=self)
        if new_title is None:
            return
        new_title = new_title.strip()
        if not new_title:
            return
        new_dir = project_dir_for_title(new_title)
        if new_dir.exists() and new_dir != project.directory:
            messagebox.showerror(APP_TITLE, "Проект с таким названием уже есть.")
            return
        project.directory.rename(new_dir)
        xml = project_xml_path(new_dir)
        if xml:
            target_xml = new_dir / f"{safe_filename(new_title)}.xml"
            if xml != target_xml:
                xml.rename(target_xml)
        self.show_project_list(self.project_list_mode)

    def delete_selected_project(self) -> None:
        project = self.selected_project()
        if not project:
            return
        if messagebox.askyesno(APP_TITLE, f"Удалить проект «{project.title}» целиком?"):
            shutil.rmtree(project.directory)
            self.show_project_list(self.project_list_mode)

    def create_preset_project_from_xml(self) -> None:
        project = self.create_project_from_xml_dialog()
        if project:
            self.open_preset_project(project)

    def create_partitura_project_from_xml(self) -> None:
        project = self.create_project_from_xml_dialog()
        if project:
            self.project = project
            self.partitura_project_var.set(f"Активный проект: {project.title}")
            self.show_partitura()

    def create_project_from_xml_dialog(self) -> Optional[Project]:
        filename = filedialog.askopenfilename(title="Выберите XML GrandMA2", filetypes=[("GrandMA2 XML", "*.xml"), ("Все файлы", "*.*")])
        if not filename:
            return None
        source = Path(filename)
        title = simpledialog.askstring(APP_TITLE, "Название спектакля:", initialvalue=source.stem, parent=self)
        if title is None:
            return None
        title = title.strip() or source.stem
        try:
            return copy_xml_to_project(source, title)
        except Exception as exc:
            messagebox.showerror(APP_TITLE, f"Не удалось создать проект:\n{exc}")
            return None

    def open_preset_project(self, project: Project) -> None:
        try:
            items = parse_grandma2_presets(project.xml_path)
            if not items:
                messagebox.showwarning(APP_TITLE, "В XML не нашлось пресетов с приборами.")
                return
            rows, warning = load_passport_rows(items, project.directory, project.title)
        except Exception as exc:
            messagebox.showerror(APP_TITLE, f"Не удалось открыть проект:\n{exc}")
            return
        self.project = project
        self.items = items
        self.rows = rows
        self.index = 0
        self.reviewing_photo = False
        self.workspace_summary.set(f"{project.title}: пресетов {len({(i.preset_no, i.preset_name) for i in items})}, строк {len(rows)}")
        self.refresh_table()
        self.show_frame("workspace")
        self.show_current_item()
        self.autosave_passport()
        self.connect_camera(silent=True)
        if warning:
            messagebox.showwarning(APP_TITLE, warning)

    def show_files(self, mode: str) -> None:
        if not self.project:
            self.show_project_list(mode)
            return
        self.files_mode = mode
        self.files_title.set(f"Файлы: {self.project.title}")
        self.files_listbox.delete(0, "end")
        self.current_files = []
        suffixes = ["_пресеты.xlsx", "_пресеты.pdf"] if mode == "presets" else ["_партитура.xlsx", "_партитура.pdf"]
        for path in sorted(self.project.directory.iterdir(), key=lambda p: p.name.lower()):
            if path.is_file() and any(path.name.endswith(suffix) for suffix in suffixes):
                self.current_files.append(path)
                self.files_listbox.insert("end", path.name)
        self.show_frame("files")

    def selected_file(self) -> Optional[Path]:
        selection = self.files_listbox.curselection()
        if not selection:
            messagebox.showwarning(APP_TITLE, "Выберите файл.")
            return None
        return self.current_files[selection[0]]

    def show_file_menu(self, event) -> None:
        index = self.files_listbox.nearest(event.y)
        self.files_listbox.selection_clear(0, "end")
        self.files_listbox.selection_set(index)
        self.file_menu.tk_popup(event.x_root, event.y_root)

    def open_selected_file(self) -> None:
        path = self.selected_file()
        if path:
            open_path(path)

    def reveal_selected_file(self) -> None:
        path = self.selected_file()
        if path:
            reveal_path(path)

    def delete_selected_file(self) -> None:
        path = self.selected_file()
        if path and messagebox.askyesno(APP_TITLE, f"Удалить файл {path.name}?"):
            path.unlink()
            self.show_files(self.files_mode)

    def refresh_table(self) -> None:
        self.table.delete(*self.table.get_children())
        for index, row in enumerate(self.rows):
            self.table.insert("", "end", iid=str(index), values=self.table_values(row))

    def table_values(self, row: PassportRow) -> tuple[str, str, str, str]:
        mark = "✓" if row.photo_path and row.photo_path.exists() else ""
        desc = row.description.replace("\n", " ")
        return mark, row.preset_label, row.fixture_id, desc

    def mark_table_row(self, row_index: int) -> None:
        if 0 <= row_index < len(self.rows):
            self.table.item(str(row_index), values=self.table_values(self.rows[row_index]))

    def show_current_item(self) -> None:
        if not self.rows:
            return
        self.index = max(0, min(self.index, len(self.rows) - 1))
        row = self.rows[self.index]
        self.current_var.set(f"{self.index + 1}/{len(self.rows)}  Пресет: {row.preset_label}   Прибор: {row.fixture_id}")
        self.loading_description = True
        self.description_text.set_real_text(row.description)
        self.loading_description = False
        self.syncing_selection = True
        self.table.selection_set(str(self.index))
        self.table.focus(str(self.index))
        self.table.see(str(self.index))
        self.after_idle(lambda: setattr(self, "syncing_selection", False))
        self.update_progress()
        self.update_photo_area()

    def update_photo_area(self) -> None:
        self.delete_photo_button.place_forget()
        self.hide_review_buttons()
        row = self.rows[self.index]
        if row.photo_path and row.photo_path.exists():
            self.reviewing_photo = True
            self.show_photo_preview(row.photo_path)
            self.delete_photo_button.place(x=12, y=12)
            self.photo_button.configure(text="Переснять", state="normal")
            self.add_row_button.grid()
        else:
            self.reviewing_photo = False
            self.video_label.configure(image="", text="Фото еще нет\nили нажми кнопку «Фото» внизу")
            self.preview_image = None
            self.photo_button.configure(text="Фото", state="normal")
            self.add_row_button.grid_remove()

    def on_table_select(self, _event=None) -> None:
        if self.syncing_selection:
            return
        selection = self.table.selection()
        if not selection:
            return
        self.save_current_description()
        self.index = int(selection[0])
        self.clear_capture()
        self.show_current_item()

    def show_table_menu(self, event) -> None:
        row_id = self.table.identify_row(event.y)
        if not row_id:
            return
        self.table.selection_set(row_id)
        self.on_table_select()
        self.table_menu.tk_popup(event.x_root, event.y_root)

    def on_description_changed(self, _event=None) -> None:
        if self.loading_description or not self.rows:
            return
        self.rows[self.index].description = self.description_text.real_text()
        self.mark_table_row(self.index)
        self.autosave_passport()

    def save_current_description(self) -> None:
        if self.rows:
            self.rows[self.index].description = self.description_text.real_text()
            self.mark_table_row(self.index)

    def connect_camera(self, silent: bool = False) -> None:
        if self.camera_opening:
            return
        self.stop_camera()
        source = source_from_text(self.camera_source_var.get())
        self.camera_opening = True
        self.camera_queue = multiprocessing.get_context("spawn").Queue(maxsize=3)
        self.camera_stop_event = multiprocessing.get_context("spawn").Event()
        self.camera_process = multiprocessing.get_context("spawn").Process(
            target=camera_worker,
            args=(source, self.camera_queue, self.camera_stop_event),
            daemon=True,
        )
        self.camera_process.start()
        if not silent:
            self.workspace_summary.set("Подключаю камеру...")
        self.after(50, lambda: self.poll_camera(silent))

    def poll_camera(self, silent: bool = False) -> None:
        if self.camera_queue is None:
            return
        got_frame = False
        try:
            while True:
                message = self.camera_queue.get_nowait()
                if message[0] == "connected":
                    self.camera_opening = False
                    self.camera_running = True
                    if not silent and self.project:
                        self.workspace_summary.set(f"{self.project.title}: камера подключена ({message[1]})")
                elif message[0] == "frame":
                    self.current_frame_bytes = message[1]
                    self.camera_last_frame_time = message[2]
                    got_frame = True
                elif message[0] == "error":
                    self.handle_camera_error(message[1], silent)
                    return
        except queue.Empty:
            pass
        if got_frame and not self.reviewing_photo and self.current_frame_bytes is not None and self.mode == "workspace":
            self.show_frame_bytes(self.current_frame_bytes)
        if self.camera_process is not None and self.camera_process.exitcode is not None and self.camera_process.exitcode != 0:
            self.handle_camera_error(f"Драйвер камеры упал, код {self.camera_process.exitcode}", silent)
            return
        if self.camera_running or self.camera_opening:
            self.after(30, lambda: self.poll_camera(silent))

    def handle_camera_error(self, detail: str, silent: bool = False) -> None:
        self.stop_camera()
        if not silent:
            messagebox.showerror(
                APP_TITLE,
                f"{detail}.\n\nПопробуйте другой источник камеры: 0, 1, 2, 3.",
            )

    def stop_camera(self) -> None:
        self.camera_opening = False
        self.camera_running = False
        if self.camera_stop_event is not None:
            self.camera_stop_event.set()
        if self.camera_process is not None and self.camera_process.is_alive():
            self.camera_process.join(timeout=0.4)
            if self.camera_process.is_alive():
                self.camera_process.terminate()
        self.camera_process = None
        self.camera_queue = None
        self.camera_stop_event = None

    def apply_zoom(self, image: Image.Image) -> Image.Image:
        try:
            zoom = max(1.0, float(self.zoom_var.get()))
        except tk.TclError:
            zoom = 1.0
        if zoom <= 1.01:
            return image
        width, height = image.size
        crop_w = max(1, int(width / zoom))
        crop_h = max(1, int(height / zoom))
        left = (width - crop_w) // 2
        top = (height - crop_h) // 2
        return image.crop((left, top, left + crop_w, top + crop_h))

    def fit_to_video_label(self, image: Image.Image) -> ImageTk.PhotoImage:
        label_width = max(self.video_label.winfo_width(), 640)
        label_height = max(self.video_label.winfo_height(), 360)
        image.thumbnail((label_width, label_height))
        return ImageTk.PhotoImage(image)

    def show_frame_bytes(self, frame_bytes: bytes) -> None:
        image = Image.open(io.BytesIO(frame_bytes)).convert("RGB")
        image = self.apply_zoom(image)
        self.preview_image = self.fit_to_video_label(image)
        self.video_label.configure(image=self.preview_image, text="")

    def show_photo_preview(self, path: Path) -> None:
        image = Image.open(path).convert("RGB")
        self.preview_image = self.fit_to_video_label(image)
        self.video_label.configure(image=self.preview_image, text="")

    def take_photo(self) -> None:
        if self.rows[self.index].photo_path and self.rows[self.index].photo_path.exists():
            self.delete_current_photo(autosave=False)
        if self.current_frame_bytes is None:
            messagebox.showwarning(APP_TITLE, "Нет кадра с камеры.")
            return
        image = Image.open(io.BytesIO(self.current_frame_bytes)).convert("RGB")
        image = self.apply_zoom(image)
        tmp_dir = Path(tempfile.gettempdir()) / "passport_creator"
        tmp_dir.mkdir(parents=True, exist_ok=True)
        self.captured_temp = tmp_dir / f"capture_{int(time.time() * 1000)}.jpg"
        image.save(self.captured_temp, quality=94)
        self.reviewing_photo = True
        self.show_photo_preview(self.captured_temp)
        self.show_review_buttons()

    def show_review_buttons(self) -> None:
        self.photo_button.grid_remove()
        self.upload_photo_button.grid_remove()
        self.add_row_button.grid_remove()
        self.use_button.grid()
        self.retake_button.grid()

    def hide_review_buttons(self) -> None:
        self.use_button.grid_remove()
        self.retake_button.grid_remove()
        self.photo_button.grid()
        self.upload_photo_button.grid()

    def refresh_zoom_preview(self) -> None:
        if self.reviewing_photo:
            return
        if self.current_frame_bytes is not None and self.mode == "workspace":
            self.show_frame_bytes(self.current_frame_bytes)

    def use_photo(self) -> None:
        if self.captured_temp is None or self.project is None:
            return
        self.save_current_description()
        target = self.unique_photo_path(self.rows[self.index].file_stem)
        if self.rows[self.index].photo_path:
            self.delete_photo_file(self.rows[self.index].photo_path)
        shutil.move(str(self.captured_temp), target)
        self.rows[self.index].photo_path = target
        self.captured_temp = None
        self.mark_table_row(self.index)
        self.autosave_passport()
        self.index = self.next_index_after_photo()
        self.show_current_item()

    def retake_photo(self) -> None:
        self.clear_capture()
        self.reviewing_photo = False
        if self.current_frame_bytes:
            self.show_frame_bytes(self.current_frame_bytes)
        self.hide_review_buttons()

    def next_index_after_photo(self) -> int:
        if not self.rows:
            return 0
        for candidate in range(self.index + 1, len(self.rows)):
            row = self.rows[candidate]
            if not row.photo_path or not row.photo_path.exists():
                return candidate
        for candidate in range(0, self.index):
            row = self.rows[candidate]
            if not row.photo_path or not row.photo_path.exists():
                return candidate
        return min(self.index + 1, len(self.rows) - 1)

    def clear_capture(self) -> None:
        if self.captured_temp and self.captured_temp.exists():
            self.captured_temp.unlink()
        self.captured_temp = None

    def unique_photo_path(self, stem: str) -> Path:
        assert self.project is not None
        photo_dir = photos_dir(self.project.directory)
        path = photo_dir / f"{stem}.jpg"
        counter = 2
        while path.exists():
            path = photo_dir / f"{stem}_{counter}.jpg"
            counter += 1
        return path

    def upload_photo(self) -> None:
        filename = filedialog.askopenfilename(
            title="Выберите фото",
            filetypes=[("Фото", "*.jpg *.jpeg *.png *.webp *.bmp *.heic *.heif"), ("Все файлы", "*.*")],
        )
        if not filename:
            return
        source = Path(filename)
        if source.suffix.lower() not in PHOTO_EXTENSIONS:
            messagebox.showwarning(APP_TITLE, "Выберите файл изображения.")
            return
        target = self.unique_photo_path(self.rows[self.index].file_stem)
        with Image.open(source) as image:
            image.convert("RGB").save(target, quality=94)
        self.rows[self.index].photo_path = target
        self.autosave_passport()
        self.show_current_item()

    def add_extra_row(self) -> None:
        self.save_current_description()
        base = self.rows[self.index]
        new_row = PassportRow(base.preset_label, base.fixture_id, base.preset_no)
        self.rows.insert(self.index + 1, new_row)
        self.refresh_table()
        self.index += 1
        self.autosave_passport()
        self.show_current_item()

    def delete_current_photo(self, autosave: bool = True) -> None:
        if not self.rows:
            return
        self.delete_photo_file(self.rows[self.index].photo_path)
        self.rows[self.index].photo_path = None
        self.mark_table_row(self.index)
        if autosave:
            self.autosave_passport()
        self.show_current_item()

    def delete_current_row(self) -> None:
        if len(self.rows) <= 1:
            messagebox.showwarning(APP_TITLE, "Последнюю запись удалить нельзя.")
            return
        row = self.rows[self.index]
        if not messagebox.askyesno(APP_TITLE, f"Удалить запись {row.preset_label} | {row.fixture_id}?"):
            return
        self.delete_photo_file(row.photo_path)
        del self.rows[self.index]
        self.index = min(self.index, len(self.rows) - 1)
        self.refresh_table()
        self.autosave_passport()
        self.show_current_item()

    def delete_photo_file(self, path: Optional[Path]) -> None:
        if path and path.exists():
            path.unlink()

    def update_progress(self) -> None:
        ready = sum(1 for row in self.rows if row.photo_path and row.photo_path.exists())
        self.progress_var.set(f"{ready} / {len(self.rows)} с фото")

    def autosave_passport(self) -> None:
        if not self.project:
            return
        try:
            create_passport_xlsx(self.rows, preset_xlsx_path(self.project.directory, self.project.title), self.project.title)
            create_passport_pdf(self.rows, preset_pdf_path(self.project.directory, self.project.title), self.project.title)
        except Exception as exc:
            self.workspace_summary.set(f"Ошибка автосохранения: {exc}")

    def refresh_partitura_fields(self) -> None:
        self.field_listbox.delete(0, "end")
        for field in self.partitura_fields:
            mark = "✓" if field.enabled else " "
            self.field_listbox.insert("end", f"[{mark}] {field.title}")
            if not field.enabled:
                self.field_listbox.itemconfig("end", fg=MUTED)

    def selected_partitura_field_index(self) -> Optional[int]:
        selection = self.field_listbox.curselection()
        return selection[0] if selection else None

    def toggle_partitura_field(self) -> None:
        index = self.selected_partitura_field_index()
        if index is None:
            return
        self.partitura_fields[index].enabled = not self.partitura_fields[index].enabled
        self.refresh_partitura_fields()
        self.field_listbox.selection_set(index)

    def move_partitura_field(self, direction: int) -> None:
        index = self.selected_partitura_field_index()
        if index is None:
            return
        new_index = index + direction
        if not 0 <= new_index < len(self.partitura_fields):
            return
        self.partitura_fields[index], self.partitura_fields[new_index] = self.partitura_fields[new_index], self.partitura_fields[index]
        self.refresh_partitura_fields()
        self.field_listbox.selection_set(new_index)

    def create_partitura_files(self) -> None:
        if not self.project:
            messagebox.showwarning(APP_TITLE, "Сначала выберите или создайте проект.")
            return
        fields = [field for field in self.partitura_fields if field.enabled]
        if not fields:
            messagebox.showwarning(APP_TITLE, "Включите хотя бы одно поле.")
            return
        try:
            rows = parse_partitura(self.project.xml_path)
            create_partitura_xlsx(rows, fields, partitura_xlsx_path(self.project.directory, self.project.title), self.project.title)
            create_partitura_pdf(rows, fields, partitura_pdf_path(self.project.directory, self.project.title), self.project.title)
        except Exception as exc:
            messagebox.showerror(APP_TITLE, f"Не удалось создать партитуру:\n{exc}")
            return
        self.show_files("partitura")

    def on_close(self) -> None:
        self.save_current_description()
        self.autosave_passport()
        self.stop_camera()
        self.destroy()


def create_cell_photo(source: Path, target: Path, width: int, height: int) -> None:
    with Image.open(source) as image:
        image = image.convert("RGB")
        image.thumbnail((width, height))
        canvas = Image.new("RGB", (width, height), "white")
        left = (width - image.width) // 2
        top = (height - image.height) // 2
        canvas.paste(image, (left, top))
        canvas.save(target)


def create_passport_xlsx(rows: list[PassportRow], path: Path, title: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    wb = Workbook()
    ws = wb.active
    ws.title = "Паспорт"
    ws.append([title])
    ws.merge_cells("A1:D1")
    ws.append(["Пресет", "Прибор", "Фото", "Описание"])

    thin = Side(style="thin", color="999999")
    border = Border(left=thin, right=thin, top=thin, bottom=thin)
    ws["A1"].font = Font(bold=True, size=16)
    ws["A1"].alignment = Alignment(horizontal="center", vertical="center")
    ws.row_dimensions[1].height = 30
    for cell in ws[2]:
        cell.font = Font(bold=True)
        cell.alignment = Alignment(horizontal="center", vertical="center")
        cell.border = border
        cell.fill = PatternFill("solid", fgColor="EEEEEE")

    ws.column_dimensions["A"].width = 38
    ws.column_dimensions["B"].width = 12
    ws.column_dimensions["C"].width = 42
    ws.column_dimensions["D"].width = 34
    photo_width = 300
    photo_height = 180

    with tempfile.TemporaryDirectory() as temp_dir:
        prepared_photos: list[Path] = []
        for row_index, row in enumerate(rows, start=3):
            ws.cell(row=row_index, column=1, value=row.preset_label)
            ws.cell(row=row_index, column=2, value=row.fixture_id)
            ws.cell(row=row_index, column=4, value=row.description)
            ws.row_dimensions[row_index].height = 138
            for col in range(1, 5):
                cell = ws.cell(row=row_index, column=col)
                cell.border = border
                cell.alignment = Alignment(horizontal="center" if col != 4 else "left", vertical="center", wrap_text=True)
            if row.photo_path and row.photo_path.exists():
                prepared = Path(temp_dir) / f"photo_{row_index}.png"
                create_cell_photo(row.photo_path, prepared, photo_width, photo_height)
                prepared_photos.append(prepared)
                img = XlsxImage(str(prepared))
                img.width = photo_width
                img.height = photo_height
                ws.add_image(img, f"C{row_index}")

        merge_duplicate_passport_cells(ws, rows)
        ws.freeze_panes = "A3"
        wb.save(path)


def merge_duplicate_passport_cells(ws, rows: list[PassportRow]) -> None:
    start = 3
    while start < len(rows) + 3:
        key = rows[start - 3].group_key
        end = start
        while end + 1 < len(rows) + 3 and rows[end - 2].group_key == key:
            end += 1
        if end > start:
            ws.merge_cells(start_row=start, start_column=1, end_row=end, end_column=1)
            ws.merge_cells(start_row=start, start_column=2, end_row=end, end_column=2)
        start = end + 1


def create_partitura_xlsx(rows: list[PartituraRow], fields: list[PartituraField], path: Path, title: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    wb = Workbook()
    ws = wb.active
    ws.title = "Партитура"
    last_col = max(1, len(fields))
    ws.append([title])
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=last_col)
    ws.append([field.title for field in fields])

    thin = Side(style="thin", color="555555")
    border = Border(left=thin, right=thin, top=thin, bottom=thin)
    ws["A1"].font = Font(bold=True, size=16)
    ws["A1"].alignment = Alignment(horizontal="center", vertical="center")
    ws.row_dimensions[1].height = 28
    for cell in ws[2]:
        cell.font = Font(bold=True)
        cell.alignment = Alignment(horizontal="center", vertical="center")
        cell.border = border

    widths = {
        "number": 12,
        "name": 48,
        "trigger": 13,
        "trigger_time": 15,
        "fade": 10,
        "downfade": 12,
        "delay": 10,
        "info": 54,
        "command": 32,
    }
    for index, field in enumerate(fields, start=1):
        ws.column_dimensions[column_letter(index)].width = widths.get(field.field_id, 18)

    for row in rows:
        ws.append([row.value(field.field_id) for field in fields])

    for sheet_row in ws.iter_rows(min_row=3):
        for col_index, cell in enumerate(sheet_row, start=1):
            field = fields[col_index - 1]
            align = "left" if field.field_id in {"name", "info", "command"} else "center"
            cell.alignment = Alignment(horizontal=align, vertical="center", wrap_text=True)
            cell.border = border

    ws.freeze_panes = "A3"
    wb.save(path)


def column_letter(index: int) -> str:
    result = ""
    while index:
        index, remainder = divmod(index - 1, 26)
        result = chr(65 + remainder) + result
    return result


def create_passport_pdf(rows: list[PassportRow], path: Path, title: str) -> None:
    try:
        from reportlab.lib import colors
        from reportlab.lib.pagesizes import landscape, A4
        from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
        from reportlab.lib.units import mm
        from reportlab.platypus import Image as PdfImage
        from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
    except ImportError:
        create_simple_pdf_placeholder(path, title, "Установите reportlab для PDF.")
        return

    font_name, bold_font_name = register_pdf_fonts()
    doc = SimpleDocTemplate(str(path), pagesize=landscape(A4), rightMargin=12 * mm, leftMargin=12 * mm, topMargin=10 * mm, bottomMargin=10 * mm)
    styles = getSampleStyleSheet()
    styles["Title"].fontName = bold_font_name
    normal = ParagraphStyle("normal", parent=styles["Normal"], fontName=font_name, fontSize=8, leading=10, alignment=1)
    left = ParagraphStyle("left", parent=normal, alignment=0)
    story = [Paragraph(title, styles["Title"]), Spacer(1, 5 * mm)]
    data = [["Пресет", "Прибор", "Фото", "Описание"]]
    temp_files: list[Path] = []
    for row in rows:
        photo = ""
        if row.photo_path and row.photo_path.exists():
            prepared = Path(tempfile.gettempdir()) / f"passport_pdf_{time.time_ns()}.jpg"
            create_cell_photo(row.photo_path, prepared, 240, 145)
            temp_files.append(prepared)
            photo = PdfImage(str(prepared), width=64 * mm, height=38 * mm)
        data.append([Paragraph(row.preset_label, normal), Paragraph(row.fixture_id, normal), photo, Paragraph(row.description, left)])
    table = Table(data, colWidths=[62 * mm, 22 * mm, 70 * mm, 90 * mm], repeatRows=1)
    style_commands = [
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
        ("BACKGROUND", (0, 0), (-1, 0), colors.whitesmoke),
        ("FONTNAME", (0, 0), (-1, 0), bold_font_name),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]
    start = 1
    while start <= len(rows):
        key = rows[start - 1].group_key
        end = start
        while end < len(rows) and rows[end].group_key == key:
            end += 1
        if end > start:
            style_commands.append(("SPAN", (0, start), (0, end)))
            style_commands.append(("SPAN", (1, start), (1, end)))
        start = end + 1
    table.setStyle(TableStyle(style_commands))
    story.append(table)
    doc.build(story)
    for temp in temp_files:
        temp.unlink(missing_ok=True)


def create_partitura_pdf(rows: list[PartituraRow], fields: list[PartituraField], path: Path, title: str) -> None:
    try:
        from reportlab.lib import colors
        from reportlab.lib.pagesizes import A4
        from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
        from reportlab.lib.units import mm
        from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
    except ImportError:
        create_simple_pdf_placeholder(path, title, "Установите reportlab для PDF.")
        return

    font_name, bold_font_name = register_pdf_fonts()
    doc = SimpleDocTemplate(str(path), pagesize=A4, rightMargin=10 * mm, leftMargin=10 * mm, topMargin=10 * mm, bottomMargin=10 * mm)
    styles = getSampleStyleSheet()
    styles["Title"].fontName = bold_font_name
    small = ParagraphStyle("small", parent=styles["Normal"], fontName=font_name, fontSize=6.4, leading=7.4)
    header = ParagraphStyle("header", parent=small, fontName=bold_font_name, alignment=1)
    story = [Paragraph(title, styles["Title"]), Spacer(1, 4 * mm)]
    data = [[Paragraph(field.title, header) for field in fields]]
    for row in rows:
        data.append([Paragraph(row.value(field.field_id).replace("\n", "<br/>"), small) for field in fields])
    weights = [partitura_pdf_weight(field.field_id) for field in fields]
    total = sum(weights) or 1
    width = 190 * mm
    col_widths = [width * weight / total for weight in weights]
    table = Table(data, colWidths=col_widths, repeatRows=1)
    table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.45, colors.black),
        ("BACKGROUND", (0, 0), (-1, 0), colors.white),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))
    story.append(table)
    doc.build(story)


def partitura_pdf_weight(field_id: str) -> float:
    return {
        "number": 0.75,
        "name": 2.4,
        "trigger": 0.9,
        "trigger_time": 1.05,
        "fade": 0.65,
        "downfade": 0.8,
        "delay": 0.65,
        "info": 2.6,
        "command": 1.4,
    }.get(field_id, 1.0)


def register_pdf_fonts() -> tuple[str, str]:
    try:
        from reportlab.pdfbase import pdfmetrics
        from reportlab.pdfbase.ttfonts import TTFont
    except ImportError:
        return "Helvetica", "Helvetica-Bold"

    candidates = [
        (
            Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
            Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf"),
        ),
        (
            Path("/Library/Fonts/Arial.ttf"),
            Path("/Library/Fonts/Arial Bold.ttf"),
        ),
        (
            Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
            Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"),
        ),
    ]
    for regular, bold in candidates:
        if regular.exists() and bold.exists():
            try:
                if "PassportArial" not in pdfmetrics.getRegisteredFontNames():
                    pdfmetrics.registerFont(TTFont("PassportArial", str(regular)))
                if "PassportArialBold" not in pdfmetrics.getRegisteredFontNames():
                    pdfmetrics.registerFont(TTFont("PassportArialBold", str(bold)))
                return "PassportArial", "PassportArialBold"
            except Exception:
                continue
    return "Helvetica", "Helvetica-Bold"


def create_simple_pdf_placeholder(path: Path, title: str, message: str) -> None:
    image = Image.new("RGB", (1240, 1754), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default()
    draw.text((80, 80), title, fill="black", font=font)
    draw.text((80, 130), message, fill="black", font=font)
    image.save(path, "PDF")


def open_path(path: Path) -> None:
    if sys.platform == "darwin":
        subprocess.run(["open", str(path)], check=False)
    elif os.name == "nt":
        os.startfile(path)  # type: ignore[attr-defined]
    else:
        subprocess.run(["xdg-open", str(path)], check=False)


def reveal_path(path: Path) -> None:
    if sys.platform == "darwin":
        subprocess.run(["open", "-R", str(path)], check=False)
    elif os.name == "nt":
        subprocess.run(["explorer", f"/select,{path}"], check=False)
    else:
        open_path(path.parent)


def print_xml_summary(xml_path: Path) -> None:
    items = parse_grandma2_presets(xml_path)
    print(f"XML: {xml_path}")
    print(f"Пресетов: {len({(item.preset_no, item.preset_name) for item in items})}")
    print(f"Строк пресет-прибор: {len(items)}")
    for item in items[:10]:
        print(f"  {item.preset_label} | {item.preset_no} | fixture {item.fixture_id}")
    if len(items) > 10:
        print("  ...")


def print_camera_check() -> None:
    context = multiprocessing.get_context("spawn")
    for index in range(6):
        frame_queue = context.Queue(maxsize=3)
        stop_event = context.Event()
        process = context.Process(target=camera_worker, args=(index, frame_queue, stop_event), daemon=True)
        process.start()
        got_frame = False
        error = ""
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                message = frame_queue.get(timeout=0.2)
            except queue.Empty:
                continue
            if message[0] == "frame":
                got_frame = True
                break
            if message[0] == "error":
                error = message[1]
                break
        stop_event.set()
        process.join(timeout=0.5)
        if process.is_alive():
            process.terminate()
        print(f"{index}: {'OK' if got_frame else 'нет кадра ' + error}".strip())


if __name__ == "__main__":
    multiprocessing.freeze_support()
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        print_xml_summary(Path(sys.argv[2]))
    elif len(sys.argv) == 2 and sys.argv[1] == "--camera-check":
        print_camera_check()
    else:
        app = PassportApp()
        app.mainloop()
