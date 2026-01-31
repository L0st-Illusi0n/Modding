import os
import ctypes
from ctypes import wintypes
from pathlib import Path

import time
import threading

from PySide6.QtWidgets import (
    QApplication, QWidget,
    QLabel, QTabWidget,
    QVBoxLayout, QHBoxLayout,
    QFrame, QScrollArea, QLineEdit,
    QPushButton, QCheckBox, QComboBox,
    QSlider, QMessageBox, QListWidget, QListWidgetItem,
)
from PySide6.QtGui import (
    QPainter, QPen, QBrush, QColor, QLinearGradient, QRadialGradient,
    QFont, QFontMetrics, QPainterPath,
)
from PySide6.QtCore import Qt, QFileSystemWatcher, Signal, QTimer

_MUTEX_HANDLE = None


def _ensure_single_instance() -> bool:
    if os.name != "nt":
        return True
    global _MUTEX_HANDLE
    name = "Global\\BlackboxOverlayMutex"
    try:
        _MUTEX_HANDLE = ctypes.windll.kernel32.CreateMutexW(None, True, name)
        if ctypes.windll.kernel32.GetLastError() == 183:  # ERROR_ALREADY_EXISTS
            return False
    except Exception:
        return True
    return True


if not _ensure_single_instance():
    raise SystemExit(0)


def _base_dir() -> Path:
    import sys

    candidates = []
    try:
        candidates.append(Path(sys.argv[0]).absolute().parent)
    except Exception:
        pass
    try:
        candidates.append(Path(sys.executable).absolute().parent)
    except Exception:
        pass
    try:
        candidates.append(Path(__file__).absolute().parent)
    except Exception:
        pass
    try:
        candidates.append(Path.cwd())
    except Exception:
        pass

    for c in candidates:
        try:
            if (c / "bridge_cmd.txt").exists() or c.name.lower() == "external":
                return c
        except Exception:
            continue

    for c in candidates:
        if isinstance(c, Path):
            return c
    return Path.cwd()


BASE_DIR = _base_dir()
CMD_PATH = str(BASE_DIR / "bridge_cmd.txt")
ACK_PATH = str(BASE_DIR / "bridge_ack.txt")
NOTICE_PATH = str(BASE_DIR / "bridge_notice.txt")
REGISTRY_PATH = str(BASE_DIR / "bridge_registry.txt")
STATE_PATH = str(BASE_DIR / "bridge_state.txt")
GAME_EXE = "SpeciesUnknown-Win64-Shipping.exe"
GAME_WINDOW_TITLE = "SpeciesUnknown"
# Prefer process checks (more reliable than window-title). Add more names if needed.
GAME_PROCESS_NAMES = [
    "SpeciesUnknown-Win64-Shipping.exe",
    "SpeciesUnknown.exe",
]

# ===== Robust game-process detection =====
_GAME_PID_CACHE = None
_GAME_EXE_CACHE = None  # lowercase exe name
_GAME_CACHE_TIME = 0.0
_GAME_CACHE_TTL_S = 0.5
PROCESS_CHECK_INTERVAL_MS = 1000

CONTRACT_PROP_CONFIG = [
    {
        "name": "Valid_13_7EC50B9D43830CC60C6CFB89C4A56633",
        "label": "Valid",
        "kind": "bool",
        "exclude": True,
        "default": True,
    },
    {
        "name": "ContractType_2_AD7B8E08435CF5A38556E7BA67C34760",
        "label": "Contract Type",
        "kind": "int",
        "exclude": False,
        "default": 0,
    },
    {
        "name": "Difficulty_5_84E907A245C9C4C6CA73B4B492F85329",
        "label": "Difficulty",
        "kind": "int",
        "exclude": False,
        "default": 0,
    },
    {
        "name": "Map_33_3AB0E6BD42FE920DECF2A89E52105CBF",
        "label": "Map",
        "kind": "int",
        "exclude": False,
        "default": 0,
    },
    {
        "name": "Bonus_37_1897E8074DDDA168BDAA24BC50497746",
        "label": "Bonus",
        "kind": "int",
        "exclude": False,
        "default": 0,
    },
    {
        "name": "RespawnTicket_8_A88C5BA64BADD031647C7BBAB7B1DCD3",
        "label": "Respawn Tickets",
        "kind": "int",
        "exclude": False,
        "default": 0,
    },
    {
        "name": "PowerAtStart_11_C457EA0B40DD327B66E17FBA29A033CD",
        "label": "Power At Start",
        "kind": "bool",
        "exclude": False,
        "default": False,
    },
    {
        "name": "PirateInfasion_16_0C40614A4525CF1F61426D8C1612CD02",
        "label": "Pirate Infasion",
        "kind": "bool",
        "exclude": True,
        "default": False,
    },
    {
        "name": "ExplosiveItems_26_911C078943295906DC83AD9AE6E41C50",
        "label": "Explosive Items",
        "kind": "bool",
        "exclude": False,
        "default": False,
    },
    {
        "name": "WeaponsCat1_18_791AA0694D75543C3E72E9BF6CBDDED7",
        "label": "Weapons Cat 1",
        "kind": "bool",
        "exclude": False,
        "default": False,
    },
    {
        "name": "WeaponsCat2_20_3287E6454140FA9F9FAEA2BBE0683E3A",
        "label": "Weapons Cat 2",
        "kind": "bool",
        "exclude": False,
        "default": False,
    },
    {
        "name": "WeaponBeep_30_A709702A49C40150494FC5A3BC396644",
        "label": "Weapon Beep",
        "kind": "bool",
        "exclude": False,
        "default": False,
    },
    {
        "name": "PaidAmmoAndHealingPoint_28_DD503146439664BB746EE4BCD5F9EB11",
        "label": "Paid Ammo + Healing",
        "kind": "bool",
        "exclude": False,
        "default": False,
    },
    {
        "name": "PowerInstable_43_08F6519448E0B007804A8E98E1C81DBB",
        "label": "Unstable Power",
        "kind": "bool",
        "exclude": False,
        "default": False,
    },
    {
        "name": "Turret_44_40482A9D49BF678F60534D8484469ECC",
        "label": "Turret",
        "kind": "bool",
        "exclude": True,
        "default": False,
    },
    {
        "name": "TimeLimit_23_33123F0347EBBAC12A84EF8683EDF14B",
        "label": "Time Limit",
        "kind": "int",
        "exclude": True,
        "default": 0,
    },
    {
        "name": "MaxBounty_40_41D52ADA489C1A0CC271FC8E07865CA3",
        "label": "Max Bounty",
        "kind": "int",
        "exclude": False,
        "default": 1000,
    },
    {
        "name": "TestModif_46_FC4300D547CDC9E3BD1A80B3F37854FB",
        "label": "Test Modif",
        "kind": "bool",
        "exclude": True,
        "default": False,
    },
]

WEAPON_TYPES = [
    ("RIFLE", "Rifle"),
    ("SMG", "SMG"),
    ("SHOTGUN", "Shotgun"),
    ("FROST", "Frost Gun"),
    ("LASER", "Laser Gun"),
    ("LIGHTNING", "Lightning Gun"),
    ("FLAME", "Flame Thrower"),
]
WEAPON_LABELS = {code: label for code, label in WEAPON_TYPES}

_IS_WINDOWS = os.name == "nt"
if _IS_WINDOWS:
    _kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _user32 = ctypes.WinDLL("user32", use_last_error=True)

    try:
        ULONG_PTR = wintypes.ULONG_PTR
    except AttributeError:
        ULONG_PTR = ctypes.c_void_p

    TH32CS_SNAPPROCESS = 0x00000002
    INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

    class PROCESSENTRY32(ctypes.Structure):
        _fields_ = [
            ("dwSize", wintypes.DWORD),
            ("cntUsage", wintypes.DWORD),
            ("th32ProcessID", wintypes.DWORD),
            ("th32DefaultHeapID", ULONG_PTR),
            ("th32ModuleID", wintypes.DWORD),
            ("cntThreads", wintypes.DWORD),
            ("th32ParentProcessID", wintypes.DWORD),
            ("pcPriClassBase", wintypes.LONG),
            ("dwFlags", wintypes.DWORD),
            ("szExeFile", wintypes.WCHAR * 260),
        ]

    _kernel32.CreateToolhelp32Snapshot.argtypes = (wintypes.DWORD, wintypes.DWORD)
    _kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    _kernel32.Process32FirstW.argtypes = (wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32))
    _kernel32.Process32FirstW.restype = wintypes.BOOL
    _kernel32.Process32NextW.argtypes = (wintypes.HANDLE, ctypes.POINTER(PROCESSENTRY32))
    _kernel32.Process32NextW.restype = wintypes.BOOL
    _kernel32.CloseHandle.argtypes = (wintypes.HANDLE,)
    _kernel32.CloseHandle.restype = wintypes.BOOL

    _user32.GetForegroundWindow.restype = wintypes.HWND
    _user32.GetWindowThreadProcessId.argtypes = (wintypes.HWND, ctypes.POINTER(wintypes.DWORD))
    _user32.GetWindowThreadProcessId.restype = wintypes.DWORD
    _user32.IsWindowVisible.argtypes = (wintypes.HWND,)
    _user32.IsWindowVisible.restype = wintypes.BOOL
    _user32.IsZoomed.argtypes = (wintypes.HWND,)
    _user32.IsZoomed.restype = wintypes.BOOL
    WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    _user32.EnumWindows.argtypes = (WNDENUMPROC, wintypes.LPARAM)
    _user32.EnumWindows.restype = wintypes.BOOL
    _user32.GetWindowTextW.argtypes = (wintypes.HWND, wintypes.LPWSTR, ctypes.c_int)
    _user32.GetWindowTextW.restype = ctypes.c_int
    _user32.GetWindowTextLengthW.argtypes = (wintypes.HWND,)
    _user32.GetWindowTextLengthW.restype = ctypes.c_int


def _get_pids_by_name(name: str) -> list[int]:
    if not _IS_WINDOWS:
        return []
    name = str(name or "").lower()
    if not name:
        return []
    snapshot = _kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snapshot == INVALID_HANDLE_VALUE:
        return []
    pids = []
    entry = PROCESSENTRY32()
    entry.dwSize = ctypes.sizeof(PROCESSENTRY32)
    if _kernel32.Process32FirstW(snapshot, ctypes.byref(entry)):
        while True:
            exe = str(entry.szExeFile or "").lower()
            if exe == name:
                pids.append(int(entry.th32ProcessID))
            if not _kernel32.Process32NextW(snapshot, ctypes.byref(entry)):
                break
    _kernel32.CloseHandle(snapshot)
    return pids


def _query_process_image_name(pid: int) -> str | None:
    """Return full path to process image for pid, or None."""
    try:
        kernel32 = ctypes.windll.kernel32
        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not handle:
            return None
        try:
            buf_len = wintypes.DWORD(32768)
            buf = ctypes.create_unicode_buffer(buf_len.value)
            ok = kernel32.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(buf_len))
            if not ok:
                return None
            return buf.value
        finally:
            kernel32.CloseHandle(handle)
    except Exception:
        return None


def _pid_is_alive(pid: int) -> bool:
    """True if pid exists and is still active."""
    try:
        kernel32 = ctypes.windll.kernel32
        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not handle:
            return False
        try:
            exit_code = wintypes.DWORD()
            if not kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
                return False
            STILL_ACTIVE = 259
            return exit_code.value == STILL_ACTIVE
        finally:
            kernel32.CloseHandle(handle)
    except Exception:
        return False


def _detect_game_process() -> tuple[int, str] | None:
    """Detect the game process. Returns (pid, exe_lower) or None."""
    global _GAME_PID_CACHE, _GAME_EXE_CACHE, _GAME_CACHE_TIME
    now = time.time()
    if _GAME_PID_CACHE and (now - _GAME_CACHE_TIME) < _GAME_CACHE_TTL_S:
        if _pid_is_alive(_GAME_PID_CACHE):
            return (_GAME_PID_CACHE, _GAME_EXE_CACHE or "")
        _GAME_PID_CACHE = None
        _GAME_EXE_CACHE = None

    try:
        kernel32 = ctypes.windll.kernel32
        TH32CS_SNAPPROCESS = 0x00000002
        class PROCESSENTRY32(ctypes.Structure):
            _fields_ = [
                ("dwSize", wintypes.DWORD),
                ("cntUsage", wintypes.DWORD),
                ("th32ProcessID", wintypes.DWORD),
                ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
                ("th32ModuleID", wintypes.DWORD),
                ("cntThreads", wintypes.DWORD),
                ("th32ParentProcessID", wintypes.DWORD),
                ("pcPriClassBase", ctypes.c_long),
                ("dwFlags", wintypes.DWORD),
                ("szExeFile", ctypes.c_wchar * 260),
            ]
        snap = kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
        INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value
        if snap and snap != INVALID_HANDLE_VALUE:
            try:
                entry = PROCESSENTRY32()
                entry.dwSize = ctypes.sizeof(PROCESSENTRY32)
                ok = kernel32.Process32FirstW(snap, ctypes.byref(entry))
                want_exact = {n.lower() for n in GAME_PROCESS_NAMES}
                while ok:
                    exe = (entry.szExeFile or "").lower()
                    pid = int(entry.th32ProcessID)
                    if exe in want_exact or exe.startswith("speciesunknown"):
                        _GAME_PID_CACHE = pid
                        _GAME_EXE_CACHE = exe
                        _GAME_CACHE_TIME = now
                        return (pid, exe)
                    ok = kernel32.Process32NextW(snap, ctypes.byref(entry))
            finally:
                kernel32.CloseHandle(snap)
    except Exception:
        pass

    _GAME_CACHE_TIME = now
    return None


def _get_pid_from_hwnd(hwnd) -> int | None:
    if not _IS_WINDOWS or not hwnd:
        return None
    pid = wintypes.DWORD(0)
    _user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return int(pid.value) if pid.value else None


def _get_window_titles() -> list[tuple[int, str]]:
    if not _IS_WINDOWS:
        return []
    results = []

    @WNDENUMPROC
    def _enum_cb(hwnd, lparam):
        if not _user32.IsWindowVisible(hwnd):
            return True
        length = _user32.GetWindowTextLengthW(hwnd)
        if length <= 0:
            return True
        buf = ctypes.create_unicode_buffer(length + 1)
        if _user32.GetWindowTextW(hwnd, buf, length + 1) > 0:
            title = buf.value
            if title:
                results.append((int(hwnd), title))
        return True

    _user32.EnumWindows(_enum_cb, 0)
    return results


def _find_windows_by_title(title: str) -> list[tuple[int, str]]:
    if not _IS_WINDOWS:
        return []
    needle = str(title or "").strip().lower()
    if not needle:
        return []
    matches = []
    for hwnd, window_title in _get_window_titles():
        if needle in str(window_title).lower():
            matches.append((hwnd, window_title))
    return matches


def _get_foreground_pid_zoomed():
    if not _IS_WINDOWS:
        return None, False, False
    hwnd = _user32.GetForegroundWindow()
    if not hwnd:
        return None, False, False
    pid = wintypes.DWORD(0)
    _user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    visible = bool(_user32.IsWindowVisible(hwnd))
    zoomed = bool(_user32.IsZoomed(hwnd))
    return int(pid.value), visible, zoomed


def _get_foreground_title_zoomed():
    if not _IS_WINDOWS:
        return "", False, False, None
    hwnd = _user32.GetForegroundWindow()
    if not hwnd:
        return "", False, False, None
    length = _user32.GetWindowTextLengthW(hwnd)
    title = ""
    if length > 0:
        buf = ctypes.create_unicode_buffer(length + 1)
        if _user32.GetWindowTextW(hwnd, buf, length + 1) > 0:
            title = buf.value or ""
    visible = bool(_user32.IsWindowVisible(hwnd))
    zoomed = bool(_user32.IsZoomed(hwnd))
    pid = _get_pid_from_hwnd(hwnd)
    return title, visible, zoomed, pid


class CommandBridge:
    def __init__(self, cmd_path: str):
        self.cmd_path = str(cmd_path or "")
        self._cmd_id = 1

    def send(self, name: str, arg: str = "") -> int | None:
        try:
            cmd = str(name or "").strip().lower()
            if not cmd:
                return None
            arg_s = "" if arg is None else str(arg)
            arg_s = arg_s.replace("\r", " ").replace("\n", " ").replace("|", " ")
            cmd_id = int(self._cmd_id)
            self._cmd_id += 1
            line = f"CMD|{cmd_id}|{cmd}|{arg_s}\n"
            with open(self.cmd_path, "a", encoding="utf-8", newline="\n") as f:
                f.write(line)
            return cmd_id
        except Exception:
            return None


class ToastWidget(QWidget):
    closed = Signal(object)

    def __init__(self, text: str, level: str = "INFO", duration_ms: int = 2500, base_font: QFont | None = None):
        super().__init__()
        self.text = str(text or "")
        self.level = str(level or "INFO").upper()
        self.duration_ms = max(800, int(duration_ms) if duration_ms is not None else 2500)

        self.font = QFont(base_font) if base_font else QFont("Agency FB", 10, QFont.Bold)
        self.font.setPointSize(max(10, self.font.pointSize()))
        self.font.setLetterSpacing(QFont.PercentageSpacing, 105)

        self.setWindowFlags(
            Qt.WindowStaysOnTopHint
            | Qt.FramelessWindowHint
            | Qt.Tool
            | Qt.WindowTransparentForInput
        )
        self.setAttribute(Qt.WA_TranslucentBackground, True)
        self.setAttribute(Qt.WA_TransparentForMouseEvents, True)

        fm = QFontMetrics(self.font)
        w = max(300, fm.horizontalAdvance(self.text) + 60)
        h = max(48, fm.height() + 24)
        self.resize(w, h)

        self._alpha = 0.0
        self._phase = "fade_in"
        self._t0 = time.time()

        self._timer = QTimer(self)
        self._timer.setInterval(16)
        self._timer.timeout.connect(self._tick)
        self._timer.start()

    def _accent_color(self):
        if self.level in ("OK", "SUCCESS", "GOOD"):
            return QColor(90, 210, 140, 230)
        if self.level in ("WARN", "WARNING"):
            return QColor(240, 180, 80, 230)
        if self.level in ("ERR", "ERROR", "ALERT", "FAIL"):
            return QColor(240, 90, 90, 230)
        return QColor(150, 110, 230, 230)

    def _tick(self):
        now = time.time()
        dt = now - self._t0

        fade_in_s = 0.14
        fade_out_s = 0.18
        hold_s = max(0.0, (self.duration_ms / 1000.0) - (fade_in_s + fade_out_s))

        if self._phase == "fade_in":
            self._alpha = min(1.0, dt / fade_in_s)
            if dt >= fade_in_s:
                self._phase = "hold"
                self._t0 = now
        elif self._phase == "hold":
            self._alpha = 1.0
            if dt >= hold_s:
                self._phase = "fade_out"
                self._t0 = now
        else:
            self._alpha = max(0.0, 1.0 - (dt / fade_out_s))
            if dt >= fade_out_s:
                self._timer.stop()
                self.close()
                self.closed.emit(self)
                return

        self.update()

    def paintEvent(self, event):  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing, True)

        r = self.rect()
        radius = 14
        path = QPainterPath()
        path.addRoundedRect(r.adjusted(2, 2, -2, -2), radius, radius)

        accent = self._accent_color()

        glow = QRadialGradient(r.center(), max(r.width(), r.height()) * 0.9)
        glow.setColorAt(0.0, QColor(accent.red(), accent.green(), accent.blue(), int(110 * self._alpha)))
        glow.setColorAt(0.7, QColor(50, 24, 90, int(40 * self._alpha)))
        glow.setColorAt(1.0, QColor(0, 0, 0, 0))
        painter.fillPath(path, glow)

        bg_grad = QLinearGradient(r.topLeft(), r.bottomRight())
        bg_grad.setColorAt(0.0, QColor(8, 6, 14, int(230 * self._alpha)))
        bg_grad.setColorAt(1.0, QColor(26, 14, 40, int(230 * self._alpha)))
        painter.fillPath(path, bg_grad)

        painter.setPen(QPen(QColor(accent.red(), accent.green(), accent.blue(), int(190 * self._alpha)), 2))
        painter.drawPath(path)

        inner = r.adjusted(6, 6, -6, -6)
        painter.setPen(QPen(QColor(210, 170, 255, int(140 * self._alpha)), 1))
        painter.drawRoundedRect(inner, radius - 4, radius - 4)

        painter.setFont(self.font)
        painter.setPen(QPen(QColor(235, 220, 255, int(255 * self._alpha)), 1))
        painter.drawText(r.adjusted(18, 0, -18, 0), Qt.AlignVCenter | Qt.AlignLeft, self.text)


class ToastManager:
    def __init__(self):
        self._toasts = []
        self._base_font = QFont("Agency FB", 10, QFont.Bold)
        self._base_font.setLetterSpacing(QFont.PercentageSpacing, 105)

    def show(self, text: str, level: str = "INFO", duration_ms: int = 2500):
        text = str(text or "").strip()
        if not text:
            return
        toast = ToastWidget(text, level, duration_ms, self._base_font)
        toast.closed.connect(self._on_toast_closed)
        self._toasts.append(toast)
        self._reposition()
        toast.show()
        toast.raise_()

    def _on_toast_closed(self, toast):
        if toast in self._toasts:
            self._toasts.remove(toast)
            self._reposition()

    def _reposition(self):
        try:
            screen = QApplication.primaryScreen()
            geo = screen.availableGeometry() if screen else None
            if not geo:
                return
            spacing = 10
            y = geo.y() + int(geo.height() * 0.12)
            for toast in list(self._toasts):
                w = toast.width()
                x = geo.x() + max(0, (geo.width() - w) // 2)
                toast.move(x, y)
                y += toast.height() + spacing
        except Exception:
            pass

class ActionPanel(QWidget):
    _invoke = Signal(object)

    def __init__(self, send_cmd_cb):
        super().__init__()
        self._send_cmd = send_cmd_cb
        self._panel_request_cb = None
        self._panel_requested = None
        self.setObjectName("actionPanel")
        self.setWindowTitle("Blackbox Console")
        self.setFixedSize(720, 900)
        self.setWindowFlags(
            Qt.WindowStaysOnTopHint
            | Qt.FramelessWindowHint
            | Qt.Tool
        )
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_ShowWithoutActivating, True)

        self._toast_mgr = ToastManager()
        self._toast_mgr_external = None
        self._initial_splash_shown = False

        root = QVBoxLayout(self)
        root.setContentsMargins(10, 10, 10, 10)
        root.setSpacing(10)

        # Header
        hdr = QFrame()
        hdr.setObjectName("panelHeader")
        hdr_l = QHBoxLayout(hdr)
        hdr_l.setContentsMargins(16, 12, 16, 12)
        hdr_l.setSpacing(10)

        title_box = QWidget()
        title_l = QVBoxLayout(title_box)
        title_l.setContentsMargins(0, 0, 0, 0)
        title_l.setSpacing(2)

        self.title_lbl = QLabel("BLACKBOX")
        self.title_lbl.setObjectName("panelTitle")
        title_l.addWidget(self.title_lbl)

        self.subtitle_lbl = QLabel("ACCESS CONSOLE")
        self.subtitle_lbl.setObjectName("panelSubtitle")
        title_l.addWidget(self.subtitle_lbl)

        hdr_l.addWidget(title_box, 1)

        self.map_lbl = QLabel("STATUS: READY")
        self.map_lbl.setObjectName("panelChip")
        hdr_l.addWidget(self.map_lbl, 0)

        root.addWidget(hdr)

        body = QFrame()
        body.setObjectName("panelBody")
        body_l = QVBoxLayout(body)
        body_l.setContentsMargins(12, 12, 12, 12)
        body_l.setSpacing(10)

        info_bar = QFrame()
        info_bar.setObjectName("panelStatus")
        info_l = QVBoxLayout(info_bar)
        info_l.setContentsMargins(10, 8, 10, 8)
        info_l.setSpacing(6)

        info_top = QHBoxLayout()
        info_top.setSpacing(8)

        self.info_status_lbl = QLabel("STATUS: --")
        self.info_status_lbl.setObjectName("panelChip")
        info_top.addWidget(self.info_status_lbl)

        self.info_radar_lbl = QLabel("RADAR: --")
        self.info_radar_lbl.setObjectName("panelChip")
        info_top.addWidget(self.info_radar_lbl)

        self.info_pawn_lbl = QLabel("PAWN: --")
        self.info_pawn_lbl.setObjectName("panelChip")
        info_top.addWidget(self.info_pawn_lbl)

        self.info_map_lbl = QLabel("MAP: --")
        self.info_map_lbl.setObjectName("panelChip")
        info_top.addWidget(self.info_map_lbl)

        info_top.addStretch(1)
        info_l.addLayout(info_top)

        info_bottom = QHBoxLayout()
        info_bottom.setSpacing(8)
        self.info_world_lbl = QLabel("WORLD: --")
        self.info_world_lbl.setObjectName("panelChip")
        info_bottom.addWidget(self.info_world_lbl)

        self.info_tracked_lbl = QLabel("TRACKED: --")
        self.info_tracked_lbl.setObjectName("panelChip")
        info_bottom.addWidget(self.info_tracked_lbl)

        self.info_events_lbl = QLabel("EVENTS: --")
        self.info_events_lbl.setObjectName("panelChip")
        info_bottom.addWidget(self.info_events_lbl)

        self.info_bridge_lbl = QLabel("BRIDGE: --")
        self.info_bridge_lbl.setObjectName("panelChip")
        info_bottom.addWidget(self.info_bridge_lbl)

        info_bottom.addStretch(1)

        info_l.addLayout(info_bottom)
        body_l.addWidget(info_bar)

        tabs = QTabWidget()
        tabs.setObjectName("panelTabs")
        body_l.addWidget(tabs, 1)
        root.addWidget(body, 1)

        def _make_tab(title: str):
            scroll = QScrollArea()
            scroll.setWidgetResizable(True)
            scroll.setFrameShape(QFrame.NoFrame)
            scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
            scroll.setObjectName("panelScroll")
            container = QWidget()
            scroll.setWidget(container)
            layout = QVBoxLayout(container)
            layout.setContentsMargins(0, 0, 0, 0)
            layout.setSpacing(12)
            tabs.addTab(scroll, title)
            return layout

        tp_layout = _make_tab("Teleport")
        player_layout = _make_tab("Player")
        weapons_layout = _make_tab("Weapons")
        world_layout = _make_tab("World")
        puzzles_layout = _make_tab("Puzzles")
        contracts_layout = _make_tab("Contracts")
        debug_layout = _make_tab("Debug")

        # ================== TELEPORT ==================
        tp_top = QFrame()
        tp_top.setObjectName("groupBox")
        tp_top_l = QVBoxLayout(tp_top)
        tp_top_l.setContentsMargins(12, 10, 12, 10)
        tp_top_l.setSpacing(8)

        tp_hdr = QLabel("TELEPORT")
        tp_hdr.setObjectName("groupHeader")
        tp_top_l.addWidget(tp_hdr)

        tp_row = QHBoxLayout()
        self.tp_refresh_btn = QPushButton("Refresh Teleports")
        self.tp_refresh_btn.setObjectName("panelButton")
        tp_row.addWidget(self.tp_refresh_btn)

        self.tp_map_lbl = QLabel("Map: Unknown")
        self.tp_map_lbl.setObjectName("panelChip")
        tp_row.addWidget(self.tp_map_lbl)
        tp_row.addStretch(1)
        tp_top_l.addLayout(tp_row)

        tp_hint = QLabel("Automatic return saving is always on.")
        tp_hint.setObjectName("panelHint")
        tp_top_l.addWidget(tp_hint)
        tp_layout.addWidget(tp_top)

        # Return point
        tp_return = QFrame()
        tp_return.setObjectName("groupBox")
        tp_return_l = QVBoxLayout(tp_return)
        tp_return_l.setContentsMargins(12, 10, 12, 10)
        tp_return_l.setSpacing(8)

        tp_return_hdr = QLabel("RETURN POINT")
        tp_return_hdr.setObjectName("groupHeader")
        tp_return_l.addWidget(tp_return_hdr)

        tp_return_row = QHBoxLayout()
        self.tp_set_return_btn = QPushButton("Set Return Point")
        self.tp_set_return_btn.setObjectName("panelButtonPrimary")
        tp_return_row.addWidget(self.tp_set_return_btn)

        self.tp_return_btn = QPushButton("Return")
        self.tp_return_btn.setObjectName("panelButton")
        tp_return_row.addWidget(self.tp_return_btn)
        tp_return_l.addLayout(tp_return_row)

        tp_layout.addWidget(tp_return)

        # Map teleports
        tp_map_box = QFrame()
        tp_map_box.setObjectName("groupBox")
        tp_map_l = QVBoxLayout(tp_map_box)
        tp_map_l.setContentsMargins(12, 10, 12, 10)
        tp_map_l.setSpacing(8)

        tp_map_hdr = QLabel("MAP TELEPORTS")
        tp_map_hdr.setObjectName("groupHeader")
        tp_map_l.addWidget(tp_map_hdr)

        self.tp_map_empty_lbl = QLabel("No teleport data.")
        self.tp_map_empty_lbl.setObjectName("panelHint")
        tp_map_l.addWidget(self.tp_map_empty_lbl)

        tp_map_row = QHBoxLayout()
        self.tp_map_combo = QComboBox()
        self.tp_map_combo.setObjectName("panelCombo")
        tp_map_row.addWidget(self.tp_map_combo, 1)

        self.tp_map_btn = QPushButton("Teleport")
        self.tp_map_btn.setObjectName("panelButtonPrimary")
        tp_map_row.addWidget(self.tp_map_btn)
        tp_map_l.addLayout(tp_map_row)

        tp_layout.addWidget(tp_map_box)

        # Nearest object
        tp_near_box = QFrame()
        tp_near_box.setObjectName("groupBox")
        tp_near_l = QVBoxLayout(tp_near_box)
        tp_near_l.setContentsMargins(12, 10, 12, 10)
        tp_near_l.setSpacing(8)

        tp_near_hdr = QLabel("NEAREST OBJECT")
        tp_near_hdr.setObjectName("groupHeader")
        tp_near_l.addWidget(tp_near_hdr)

        tp_near_row = QHBoxLayout()
        self.tp_near_combo = QComboBox()
        self.tp_near_combo.setObjectName("panelCombo")
        self.tp_near_combo.addItem("Monster", "MONSTER")
        self.tp_near_combo.addItem("Keycard", "KEYCARD")
        self.tp_near_combo.addItem("Data Disk", "DATA")
        self.tp_near_combo.addItem("Blackbox", "BLACKBOX")
        self.tp_near_combo.addItem("Weapon", "WEAPON")
        tp_near_row.addWidget(self.tp_near_combo, 1)

        self.tp_near_tp_btn = QPushButton("Teleport")
        self.tp_near_tp_btn.setObjectName("panelButtonPrimary")
        tp_near_row.addWidget(self.tp_near_tp_btn)

        self.tp_near_bring_btn = QPushButton("Bring")
        self.tp_near_bring_btn.setObjectName("panelButton")
        tp_near_row.addWidget(self.tp_near_bring_btn)
        tp_near_l.addLayout(tp_near_row)

        tp_layout.addWidget(tp_near_box)

        # Players
        tp_players_box = QFrame()
        tp_players_box.setObjectName("groupBox")
        tp_players_l = QVBoxLayout(tp_players_box)
        tp_players_l.setContentsMargins(12, 10, 12, 10)
        tp_players_l.setSpacing(8)

        tp_players_hdr = QLabel("PLAYERS")
        tp_players_hdr.setObjectName("groupHeader")
        tp_players_l.addWidget(tp_players_hdr)

        self.tp_bring_all_btn = QPushButton("Bring All Players")
        self.tp_bring_all_btn.setObjectName("panelButtonPrimary")
        tp_players_l.addWidget(self.tp_bring_all_btn)

        tp_target_row = QHBoxLayout()
        self.tp_target_combo = QComboBox()
        self.tp_target_combo.setObjectName("panelCombo")
        tp_target_row.addWidget(self.tp_target_combo, 1)

        self.tp_player_btn = QPushButton("Teleport Player")
        self.tp_player_btn.setObjectName("panelButton")
        tp_target_row.addWidget(self.tp_player_btn)
        tp_players_l.addLayout(tp_target_row)

        tp_dest_row = QHBoxLayout()
        self.tp_dest_combo = QComboBox()
        self.tp_dest_combo.setObjectName("panelCombo")
        tp_dest_row.addWidget(self.tp_dest_combo, 1)
        tp_players_l.addLayout(tp_dest_row)

        tp_all_row = QHBoxLayout()
        self.tp_all_combo = QComboBox()
        self.tp_all_combo.setObjectName("panelCombo")
        tp_all_row.addWidget(self.tp_all_combo, 1)

        self.tp_all_btn = QPushButton("Teleport All Players")
        self.tp_all_btn.setObjectName("panelButton")
        tp_all_row.addWidget(self.tp_all_btn)
        tp_players_l.addLayout(tp_all_row)

        tp_layout.addWidget(tp_players_box)

        # Unfinished (disabled)
        tp_unfinished = QFrame()
        tp_unfinished.setObjectName("groupBox")
        tp_unfinished_l = QVBoxLayout(tp_unfinished)
        tp_unfinished_l.setContentsMargins(12, 10, 12, 10)
        tp_unfinished_l.setSpacing(8)

        tp_unfinished_hdr = QLabel("UNFINISHED")
        tp_unfinished_hdr.setObjectName("groupHeader")
        tp_unfinished_l.addWidget(tp_unfinished_hdr)

        self.tp_unfinished_buttons = []
        for label in (
            "Custom Coordinates (Unfinished)",
            "Teleport History (Unfinished)",
            "Multiple Return Slots (Unfinished)",
            "Danger-aware Validation (Unfinished)",
            "Saved Teleport Presets (Unfinished)",
        ):
            btn = QPushButton(label)
            btn.setObjectName("panelButton")
            btn.setEnabled(False)
            tp_unfinished_l.addWidget(btn)
            self.tp_unfinished_buttons.append(btn)

        tp_layout.addWidget(tp_unfinished)
        tp_layout.addStretch(1)

        # ================== WORLD ==================
        world_box = QFrame()
        world_box.setObjectName("groupBox")
        world_l = QVBoxLayout(world_box)
        world_l.setContentsMargins(12, 10, 12, 10)
        world_l.setSpacing(8)

        world_hdr = QLabel("WORLD REGISTRY")
        world_hdr.setObjectName("groupHeader")
        world_l.addWidget(world_hdr)

        world_row = QHBoxLayout()
        self.world_refresh_btn = QPushButton("Refresh Registry")
        self.world_refresh_btn.setObjectName("panelButton")
        world_row.addWidget(self.world_refresh_btn)

        self.world_count_lbl = QLabel("Items: 0")
        self.world_count_lbl.setObjectName("panelChip")
        world_row.addWidget(self.world_count_lbl)
        world_row.addStretch(1)
        world_l.addLayout(world_row)

        world_filter_row = QHBoxLayout()
        self.world_filter_combo = QComboBox()
        self.world_filter_combo.setObjectName("panelCombo")
        self.world_filter_combo.addItem("All", "ALL")
        self.world_filter_combo.addItem("Monsters", "MONSTER")
        self.world_filter_combo.addItem("Money", "MONEY")
        self.world_filter_combo.addItem("Keycards", "OBJECTIVE")
        self.world_filter_combo.addItem("Data Disks", "DATA")
        self.world_filter_combo.addItem("Blackbox", "BLACKBOX")
        self.world_filter_combo.addItem("Weapons", "WEAPON")
        world_filter_row.addWidget(self.world_filter_combo, 1)

        self.world_sort_combo = QComboBox()
        self.world_sort_combo.setObjectName("panelCombo")
        self.world_sort_combo.addItem("Sort: Category", "CATEGORY")
        self.world_sort_combo.addItem("Sort: Distance", "DISTANCE")
        self.world_sort_combo.addItem("Sort: Name", "NAME")
        world_filter_row.addWidget(self.world_sort_combo, 1)
        world_l.addLayout(world_filter_row)

        self.world_list = QListWidget()
        self.world_list.setObjectName("panelList")
        self.world_list.setSelectionMode(QListWidget.SingleSelection)
        world_l.addWidget(self.world_list, 1)

        world_btns = QHBoxLayout()
        self.world_tp_btn = QPushButton("Teleport To")
        self.world_tp_btn.setObjectName("panelButtonPrimary")
        world_btns.addWidget(self.world_tp_btn)

        self.world_bring_btn = QPushButton("Bring To Me")
        self.world_bring_btn.setObjectName("panelButton")
        world_btns.addWidget(self.world_bring_btn)
        world_l.addLayout(world_btns)

        world_hint = QLabel("Event-driven registry. Refresh forces a full resync.")
        world_hint.setObjectName("panelHint")
        world_hint.setWordWrap(True)
        world_l.addWidget(world_hint)

        world_layout.addWidget(world_box)

        world_unfinished = QFrame()
        world_unfinished.setObjectName("groupBox")
        world_unfinished_l = QVBoxLayout(world_unfinished)
        world_unfinished_l.setContentsMargins(12, 10, 12, 10)
        world_unfinished_l.setSpacing(8)

        world_unfinished_hdr = QLabel("UNFINISHED")
        world_unfinished_hdr.setObjectName("groupHeader")
        world_unfinished_l.addWidget(world_unfinished_hdr)

        self.world_unfinished_buttons = []
        for label in (
            "Object Highlighting / Ping (Unfinished)",
            "Multi-Select Actions (Unfinished)",
            "Bulk Bring / Teleport (Unfinished)",
            "Advanced Filters (Unfinished)",
            "Inspect Actor Properties (Unfinished)",
        ):
            btn = QPushButton(label)
            btn.setObjectName("panelButton")
            btn.setEnabled(False)
            world_unfinished_l.addWidget(btn)
            self.world_unfinished_buttons.append(btn)

        world_layout.addWidget(world_unfinished)
        world_layout.addStretch(1)

        # ================== PUZZLES ==================
        puzzles_top = QFrame()
        puzzles_top.setObjectName("groupBox")
        puzzles_top_l = QVBoxLayout(puzzles_top)
        puzzles_top_l.setContentsMargins(12, 10, 12, 10)
        puzzles_top_l.setSpacing(8)

        puzzles_hdr = QLabel("PUZZLES")
        puzzles_hdr.setObjectName("groupHeader")
        puzzles_top_l.addWidget(puzzles_hdr)

        puzzles_row = QHBoxLayout()
        self.puzzle_refresh_btn = QPushButton("Refresh Terminals")
        self.puzzle_refresh_btn.setObjectName("panelButton")
        puzzles_row.addWidget(self.puzzle_refresh_btn)

        self.puzzle_status_lbl = QLabel("Status: Unknown")
        self.puzzle_status_lbl.setObjectName("panelChip")
        puzzles_row.addWidget(self.puzzle_status_lbl)
        puzzles_row.addStretch(1)
        puzzles_top_l.addLayout(puzzles_row)

        puzzles_layout.addWidget(puzzles_top)

        # Pipes
        pipes_box = QFrame()
        pipes_box.setObjectName("groupBox")
        pipes_l = QVBoxLayout(pipes_box)
        pipes_l.setContentsMargins(12, 10, 12, 10)
        pipes_l.setSpacing(8)

        pipes_hdr = QLabel("PIPES")
        pipes_hdr.setObjectName("groupHeader")
        pipes_l.addWidget(pipes_hdr)

        self.pipes_term_lbl = QLabel("Terminal: Unknown")
        self.pipes_term_lbl.setObjectName("panelChip")
        pipes_l.addWidget(self.pipes_term_lbl)

        pipes_btn_row = QHBoxLayout()
        self.pipes_enable_all_btn = QPushButton("Enable All")
        self.pipes_enable_all_btn.setObjectName("panelButtonPrimary")
        pipes_btn_row.addWidget(self.pipes_enable_all_btn)
        self.pipes_disable_all_btn = QPushButton("Disable All")
        self.pipes_disable_all_btn.setObjectName("panelButton")
        pipes_btn_row.addWidget(self.pipes_disable_all_btn)
        pipes_btn_row.addStretch(1)
        pipes_l.addLayout(pipes_btn_row)

        pipes_cols = QHBoxLayout()
        self.pipe_rows = []
        for color_name, color_key in (("Red", "red"), ("Blue", "blue")):
            col_box = QFrame()
            col_box.setObjectName("panelInset")
            col_l = QVBoxLayout(col_box)
            col_l.setContentsMargins(8, 8, 8, 8)
            col_l.setSpacing(6)

            col_hdr = QLabel(f"{color_name} Pipes")
            col_hdr.setObjectName("panelSubTitle")
            col_l.addWidget(col_hdr)

            for idx in range(1, 9):
                row = QHBoxLayout()
                lbl = QLabel(f"{color_name} {idx}")
                lbl.setObjectName("panelSubTitle")
                row.addWidget(lbl, 1)

                status = QLabel("?")
                status.setObjectName("panelChip")
                row.addWidget(status, 0)

                on_btn = QPushButton("Enable")
                on_btn.setObjectName("panelButtonPrimary")
                row.addWidget(on_btn, 0)

                off_btn = QPushButton("Disable")
                off_btn.setObjectName("panelButton")
                row.addWidget(off_btn, 0)

                tp_btn = QPushButton("Teleport")
                tp_btn.setObjectName("panelButton")
                row.addWidget(tp_btn, 0)

                col_l.addLayout(row)
                self.pipe_rows.append({
                    "color": color_key,
                    "idx": idx,
                    "label": lbl,
                    "status": status,
                    "on": on_btn,
                    "off": off_btn,
                    "tp": tp_btn,
                })

            pipes_cols.addWidget(col_box, 1)

        pipes_l.addLayout(pipes_cols)
        puzzles_layout.addWidget(pipes_box)

        # Airlock
        air_box = QFrame()
        air_box.setObjectName("groupBox")
        air_l = QVBoxLayout(air_box)
        air_l.setContentsMargins(12, 10, 12, 10)
        air_l.setSpacing(8)

        air_hdr = QLabel("LAB AIRLOCK")
        air_hdr.setObjectName("groupHeader")
        air_l.addWidget(air_hdr)

        self.air_term_lbl = QLabel("Terminal: Unknown")
        self.air_term_lbl.setObjectName("panelChip")
        air_l.addWidget(self.air_term_lbl)

        air_btn_row = QHBoxLayout()
        self.air_enable_all_btn = QPushButton("Enable All")
        self.air_enable_all_btn.setObjectName("panelButtonPrimary")
        air_btn_row.addWidget(self.air_enable_all_btn)
        self.air_disable_all_btn = QPushButton("Disable All")
        self.air_disable_all_btn.setObjectName("panelButton")
        air_btn_row.addWidget(self.air_disable_all_btn)
        air_btn_row.addStretch(1)
        air_l.addLayout(air_btn_row)

        self.air_rows = []
        for idx in range(1, 5):
            row = QHBoxLayout()
            lbl = QLabel(f"Container {idx}")
            lbl.setObjectName("panelSubTitle")
            row.addWidget(lbl, 1)

            status = QLabel("?")
            status.setObjectName("panelChip")
            row.addWidget(status, 0)

            on_btn = QPushButton("Enable")
            on_btn.setObjectName("panelButtonPrimary")
            row.addWidget(on_btn, 0)

            off_btn = QPushButton("Disable")
            off_btn.setObjectName("panelButton")
            row.addWidget(off_btn, 0)

            air_l.addLayout(row)
            self.air_rows.append({
                "idx": idx,
                "label": lbl,
                "status": status,
                "on": on_btn,
                "off": off_btn,
            })

        puzzles_layout.addWidget(air_box)
        puzzles_layout.addStretch(1)

        # ================== CONTRACTS ==================
        self._contract_props = list(CONTRACT_PROP_CONFIG)
        self._contract_controls = {}
        self._contract_defaults = {cfg["name"]: cfg.get("default") for cfg in self._contract_props}

        contract_status_box = QFrame()
        contract_status_box.setObjectName("groupBox")
        contract_status_l = QVBoxLayout(contract_status_box)
        contract_status_l.setContentsMargins(12, 10, 12, 10)
        contract_status_l.setSpacing(8)

        contract_status_hdr = QLabel("CONTRACT STATUS")
        contract_status_hdr.setObjectName("groupHeader")
        contract_status_l.addWidget(contract_status_hdr)

        contract_row = QHBoxLayout()
        self.contract_refresh_btn = QPushButton("Refresh Status")
        self.contract_refresh_btn.setObjectName("panelButton")
        contract_row.addWidget(self.contract_refresh_btn)

        self.contract_status_lbl = QLabel("Status: --")
        self.contract_status_lbl.setObjectName("panelChip")
        contract_row.addWidget(self.contract_status_lbl)

        self.contract_map_lbl = QLabel("Map: --")
        self.contract_map_lbl.setObjectName("panelChip")
        contract_row.addWidget(self.contract_map_lbl)

        self.contract_lists_lbl = QLabel("Lists: --")
        self.contract_lists_lbl.setObjectName("panelChip")
        contract_row.addWidget(self.contract_lists_lbl)
        contract_row.addStretch(1)
        contract_status_l.addLayout(contract_row)

        contract_row2 = QHBoxLayout()
        self.contract_open_btn = QPushButton("Open Contracts")
        self.contract_open_btn.setObjectName("panelButtonPrimary")
        contract_row2.addWidget(self.contract_open_btn)

        self.contract_start_btn = QPushButton("Start Contract")
        self.contract_start_btn.setObjectName("panelButton")
        contract_row2.addWidget(self.contract_start_btn)

        self.contract_hooks_lbl = QLabel("Hooks: --")
        self.contract_hooks_lbl.setObjectName("panelChip")
        contract_row2.addWidget(self.contract_hooks_lbl)

        self.contract_age_lbl = QLabel("Hook Age: --")
        self.contract_age_lbl.setObjectName("panelChip")
        contract_row2.addWidget(self.contract_age_lbl)

        self.contract_props_lbl = QLabel("Props: --")
        self.contract_props_lbl.setObjectName("panelChip")
        contract_row2.addWidget(self.contract_props_lbl)
        contract_row2.addStretch(1)
        contract_status_l.addLayout(contract_row2)

        contract_hint = QLabel("Open the contract terminal in Lobby to register lists.")
        contract_hint.setObjectName("panelHint")
        contract_hint.setWordWrap(True)
        contract_status_l.addWidget(contract_hint)

        contracts_layout.addWidget(contract_status_box)

        contract_set_box = QFrame()
        contract_set_box.setObjectName("groupBox")
        contract_set_l = QVBoxLayout(contract_set_box)
        contract_set_l.setContentsMargins(12, 10, 12, 10)
        contract_set_l.setSpacing(8)

        contract_set_hdr = QLabel("SET CONTRACT")
        contract_set_hdr.setObjectName("groupHeader")
        contract_set_l.addWidget(contract_set_hdr)

        excluded_defaults = []
        for cfg in self._contract_props:
            if not cfg.get("exclude"):
                continue
            val = cfg.get("default")
            if isinstance(val, bool):
                val = "true" if val else "false"
            excluded_defaults.append(f"{cfg.get('label')}={val}")
        defaults_hint = "Excluded defaults: " + ", ".join(excluded_defaults)
        contract_defaults_lbl = QLabel(defaults_hint)
        contract_defaults_lbl.setObjectName("panelHint")
        contract_defaults_lbl.setWordWrap(True)
        contract_set_l.addWidget(contract_defaults_lbl)

        values_hdr = QLabel("VALUES")
        values_hdr.setObjectName("panelSubTitle")
        contract_set_l.addWidget(values_hdr)

        contract_dropdowns = {
            "ContractType_2_AD7B8E08435CF5A38556E7BA67C34760": [
                ("Elimination", 0),
                ("Self Destruct", 1),
                ("Capture", 2),
                ("Extraction", 3),
            ],
            "Difficulty_5_84E907A245C9C4C6CA73B4B492F85329": [
                ("Discovery", 0),
                ("Easy", 1),
                ("Normal", 2),
                ("Hard", 3),
                ("Nightmare", 4),
            ],
            "Map_33_3AB0E6BD42FE920DECF2A89E52105CBF": [
                ("Hawking", 0),
            ],
        }

        for cfg in self._contract_props:
            if cfg.get("exclude") or cfg.get("kind") != "int":
                continue
            row = QHBoxLayout()
            lbl = QLabel(cfg.get("label") or cfg.get("name") or "Value")
            lbl.setObjectName("panelSubTitle")
            row.addWidget(lbl, 1)

            dropdown = contract_dropdowns.get(cfg.get("name"))
            if dropdown:
                edit = QComboBox()
                edit.setObjectName("panelCombo")
                for text, val in dropdown:
                    edit.addItem(text, val)
                edit.setCurrentIndex(max(0, edit.findData(cfg.get("default", 0))))
            else:
                edit = QLineEdit()
                edit.setObjectName("panelInput")
                edit.setText(str(cfg.get("default", 0)))
            row.addWidget(edit, 0)

            status = QLabel(str(cfg.get("default", 0)))
            status.setObjectName("panelChip")
            row.addWidget(status, 0)

            contract_set_l.addLayout(row)
            self._contract_controls[cfg["name"]] = {
                "kind": "int",
                "label": cfg.get("label") or cfg.get("name"),
                "widget": edit,
                "status": status,
                "dropdown": bool(dropdown),
            }

        flags_hdr = QLabel("FLAGS")
        flags_hdr.setObjectName("panelSubTitle")
        contract_set_l.addWidget(flags_hdr)

        for cfg in self._contract_props:
            if cfg.get("exclude") or cfg.get("kind") != "bool":
                continue
            row = QHBoxLayout()
            cb = QCheckBox(cfg.get("label") or cfg.get("name") or "Flag")
            cb.setObjectName("panelCheck")
            cb.setChecked(bool(cfg.get("default", False)))
            row.addWidget(cb, 0)

            status = QLabel("ON" if cb.isChecked() else "OFF")
            status.setObjectName("panelChip")
            row.addWidget(status, 0)
            row.addStretch(1)
            contract_set_l.addLayout(row)

            self._contract_controls[cfg["name"]] = {
                "kind": "bool",
                "label": cfg.get("label") or cfg.get("name"),
                "widget": cb,
                "status": status,
            }

        contract_apply_row = QHBoxLayout()
        self.contract_apply_btn = QPushButton("Apply Contract")
        self.contract_apply_btn.setObjectName("panelButtonPrimary")
        contract_apply_row.addWidget(self.contract_apply_btn)
        contract_apply_row.addStretch(1)
        contract_set_l.addLayout(contract_apply_row)

        contracts_layout.addWidget(contract_set_box)
        contracts_layout.addStretch(1)

        # ================== DEBUG ==================
        debug_actions = QFrame()
        debug_actions.setObjectName("groupBox")
        debug_actions_l = QVBoxLayout(debug_actions)
        debug_actions_l.setContentsMargins(12, 10, 12, 10)
        debug_actions_l.setSpacing(8)

        debug_hdr = QLabel("DEBUG ACTIONS")
        debug_hdr.setObjectName("groupHeader")
        debug_actions_l.addWidget(debug_hdr)

        debug_btn_row = QHBoxLayout()
        self.debug_refresh_btn = QPushButton("Force Refresh")
        self.debug_refresh_btn.setObjectName("panelButtonPrimary")
        debug_btn_row.addWidget(self.debug_refresh_btn)

        self.debug_resync_btn = QPushButton("Force Full Resync")
        self.debug_resync_btn.setObjectName("panelButton")
        debug_btn_row.addWidget(self.debug_resync_btn)

        self.debug_clear_btn = QPushButton("Clear Registry")
        self.debug_clear_btn.setObjectName("panelButton")
        debug_btn_row.addWidget(self.debug_clear_btn)

        self.debug_rebuild_btn = QPushButton("Rebuild Registry")
        self.debug_rebuild_btn.setObjectName("panelButton")
        debug_btn_row.addWidget(self.debug_rebuild_btn)
        debug_actions_l.addLayout(debug_btn_row)

        debug_toggle_row = QHBoxLayout()
        self.verbose_cb = QCheckBox("Verbose Logging")
        self.verbose_cb.setObjectName("panelCheck")
        debug_toggle_row.addWidget(self.verbose_cb)
        debug_toggle_row.addStretch(1)
        debug_actions_l.addLayout(debug_toggle_row)

        debug_layout.addWidget(debug_actions)

        core_box = QFrame()
        core_box.setObjectName("groupBox")
        core_l = QVBoxLayout(core_box)
        core_l.setContentsMargins(12, 10, 12, 10)
        core_l.setSpacing(6)

        core_hdr = QLabel("CORE STATE")
        core_hdr.setObjectName("groupHeader")
        core_l.addWidget(core_hdr)

        self.debug_map_lbl = QLabel("Map: --")
        self.debug_map_lbl.setObjectName("panelChip")
        core_l.addWidget(self.debug_map_lbl)

        self.debug_world_lbl = QLabel("World Ready: --")
        self.debug_world_lbl.setObjectName("panelChip")
        core_l.addWidget(self.debug_world_lbl)

        self.debug_pawn_lbl = QLabel("Pawn: --")
        self.debug_pawn_lbl.setObjectName("panelChip")
        core_l.addWidget(self.debug_pawn_lbl)

        self.debug_pos_lbl = QLabel("Local Pos: --")
        self.debug_pos_lbl.setObjectName("panelChip")
        core_l.addWidget(self.debug_pos_lbl)

        self.debug_radar_lbl = QLabel("Radar: --")
        self.debug_radar_lbl.setObjectName("panelChip")
        core_l.addWidget(self.debug_radar_lbl)

        self.debug_proto_lbl = QLabel("Protocol: --")
        self.debug_proto_lbl.setObjectName("panelChip")
        core_l.addWidget(self.debug_proto_lbl)

        debug_layout.addWidget(core_box)

        reg_box = QFrame()
        reg_box.setObjectName("groupBox")
        reg_l = QVBoxLayout(reg_box)
        reg_l.setContentsMargins(12, 10, 12, 10)
        reg_l.setSpacing(6)

        reg_hdr = QLabel("REGISTRY")
        reg_hdr.setObjectName("groupHeader")
        reg_l.addWidget(reg_hdr)

        self.debug_reg_total_lbl = QLabel("Total Tracked: --")
        self.debug_reg_total_lbl.setObjectName("panelChip")
        reg_l.addWidget(self.debug_reg_total_lbl)

        self.debug_reg_counts_lbl = QLabel("Monsters: -- | Keycards: -- | Disks: -- | Blackbox: -- | Weapons: -- | Money: --")
        self.debug_reg_counts_lbl.setObjectName("panelChip")
        self.debug_reg_counts_lbl.setWordWrap(True)
        reg_l.addWidget(self.debug_reg_counts_lbl)

        self.debug_reg_update_lbl = QLabel("Last Registry Update: --")
        self.debug_reg_update_lbl.setObjectName("panelChip")
        reg_l.addWidget(self.debug_reg_update_lbl)

        self.debug_reg_prune_lbl = QLabel("Last Prune: --")
        self.debug_reg_prune_lbl.setObjectName("panelChip")
        reg_l.addWidget(self.debug_reg_prune_lbl)

        debug_layout.addWidget(reg_box)

        self.debug_adv_box = QFrame()
        self.debug_adv_box.setObjectName("groupBox")
        adv_l = QVBoxLayout(self.debug_adv_box)
        adv_l.setContentsMargins(12, 10, 12, 10)
        adv_l.setSpacing(8)

        adv_hdr = QLabel("ADVANCED")
        adv_hdr.setObjectName("groupHeader")
        adv_l.addWidget(adv_hdr)

        self.debug_bridge_lbl = QLabel("Bridge: --")
        self.debug_bridge_lbl.setObjectName("panelChip")
        adv_l.addWidget(self.debug_bridge_lbl)

        self.debug_state_write_lbl = QLabel("State Write: --")
        self.debug_state_write_lbl.setObjectName("panelChip")
        adv_l.addWidget(self.debug_state_write_lbl)

        self.debug_state_read_lbl = QLabel("State Read: --")
        self.debug_state_read_lbl.setObjectName("panelChip")
        adv_l.addWidget(self.debug_state_read_lbl)

        self.debug_cmd_lbl = QLabel("Last Cmd/Ack: --")
        self.debug_cmd_lbl.setObjectName("panelChip")
        adv_l.addWidget(self.debug_cmd_lbl)

        self.debug_perf_lbl = QLabel("Perf: --")
        self.debug_perf_lbl.setObjectName("panelChip")
        adv_l.addWidget(self.debug_perf_lbl)

        self.debug_adv_box.setVisible(True)
        debug_layout.addWidget(self.debug_adv_box)
        debug_layout.addStretch(1)

        # ================== PLAYER TARGET ==================
        target_box = QFrame()
        target_box.setObjectName("groupBox")
        target_l = QVBoxLayout(target_box)
        target_l.setContentsMargins(12, 10, 12, 10)
        target_l.setSpacing(8)

        target_hdr = QLabel("PLAYER TARGET")
        target_hdr.setObjectName("groupHeader")
        target_l.addWidget(target_hdr)

        target_row = QHBoxLayout()
        self.target_combo = QComboBox()
        self.target_combo.setObjectName("panelCombo")
        self.target_combo.addItem("No Players Found", "")
        self.target_combo.setEnabled(False)
        target_row.addWidget(self.target_combo, 1)

        self.refresh_players_btn = QPushButton("Refresh Players")
        self.refresh_players_btn.setObjectName("panelButton")
        target_row.addWidget(self.refresh_players_btn)
        target_l.addLayout(target_row)

        target_btns = QHBoxLayout()
        self.goto_player_btn = QPushButton("Go To")
        self.goto_player_btn.setObjectName("panelButtonPrimary")
        target_btns.addWidget(self.goto_player_btn)

        self.bring_player_btn = QPushButton("Bring")
        self.bring_player_btn.setObjectName("panelButton")
        target_btns.addWidget(self.bring_player_btn)
        target_l.addLayout(target_btns)

        target_hint = QLabel("Use Refresh Players to update the list.")
        target_hint.setObjectName("panelHint")
        target_hint.setWordWrap(True)
        target_l.addWidget(target_hint)

        player_layout.addWidget(target_box)

        # ================== HEALTH ==================
        hp_box = QFrame()
        hp_box.setObjectName("groupBox")
        hp_l = QVBoxLayout(hp_box)
        hp_l.setContentsMargins(12, 10, 12, 10)
        hp_l.setSpacing(8)

        hp_hdr = QLabel("HEALTH")
        hp_hdr.setObjectName("groupHeader")
        hp_l.addWidget(hp_hdr)

        heal_row = QHBoxLayout()
        self.heal_btn = QPushButton("Heal")
        self.heal_btn.setObjectName("panelButtonPrimary")
        heal_row.addWidget(self.heal_btn)
        hp_l.addLayout(heal_row)

        self._max_hp_default = 100

        hp_row = QHBoxLayout()
        hp_label = QLabel("HP")
        hp_label.setObjectName("panelSubTitle")
        hp_row.addWidget(hp_label, 0)

        self.hp_slider = QSlider(Qt.Horizontal)
        self.hp_slider.setObjectName("panelSlider")
        self.hp_slider.setRange(1, self._max_hp_default)
        self.hp_slider.setValue(self._max_hp_default)
        hp_row.addWidget(self.hp_slider, 1)

        self.hp_value_lbl = QLabel(str(self.hp_slider.value()))
        self.hp_value_lbl.setObjectName("panelChip")
        hp_row.addWidget(self.hp_value_lbl, 0)

        self.hp_apply_btn = QPushButton("Apply")
        self.hp_apply_btn.setObjectName("panelButton")
        hp_row.addWidget(self.hp_apply_btn, 0)
        hp_l.addLayout(hp_row)

        max_hp_row = QHBoxLayout()
        max_hp_label = QLabel("Max HP")
        max_hp_label.setObjectName("panelSubTitle")
        max_hp_row.addWidget(max_hp_label, 0)

        self.max_hp_slider = QSlider(Qt.Horizontal)
        self.max_hp_slider.setObjectName("panelSlider")
        self.max_hp_slider.setRange(1, 1000)
        self.max_hp_slider.setValue(self._max_hp_default)
        max_hp_row.addWidget(self.max_hp_slider, 1)

        self.max_hp_value_lbl = QLabel(str(self.max_hp_slider.value()))
        self.max_hp_value_lbl.setObjectName("panelChip")
        max_hp_row.addWidget(self.max_hp_value_lbl, 0)

        self.max_hp_apply_btn = QPushButton("Apply")
        self.max_hp_apply_btn.setObjectName("panelButton")
        max_hp_row.addWidget(self.max_hp_apply_btn, 0)

        self.max_hp_default_btn = QPushButton("Default")
        self.max_hp_default_btn.setObjectName("panelButton")
        max_hp_row.addWidget(self.max_hp_default_btn, 0)
        hp_l.addLayout(max_hp_row)

        player_layout.addWidget(hp_box)

        # ================== MODIFIERS ==================
        mod_box = QFrame()
        mod_box.setObjectName("groupBox")
        mod_l = QVBoxLayout(mod_box)
        mod_l.setContentsMargins(12, 10, 12, 10)
        mod_l.setSpacing(8)

        mod_hdr = QLabel("MODIFIERS")
        mod_hdr.setObjectName("groupHeader")
        mod_l.addWidget(mod_hdr)

        self.godmode_cb = QCheckBox("God Mode")
        self.godmode_cb.setObjectName("panelCheck")
        mod_l.addWidget(self.godmode_cb)

        self.unlimited_stamina_cb = QCheckBox("Unlimited Stamina")
        self.unlimited_stamina_cb.setObjectName("panelCheck")
        mod_l.addWidget(self.unlimited_stamina_cb)

        self.unlimited_battery_cb = QCheckBox("Unlimited Battery")
        self.unlimited_battery_cb.setObjectName("panelCheck")
        mod_l.addWidget(self.unlimited_battery_cb)

        self.invisible_cb = QCheckBox("Invisible")
        self.invisible_cb.setObjectName("panelCheck")
        mod_l.addWidget(self.invisible_cb)

        player_layout.addWidget(mod_box)

        # ================== MOVEMENT ==================
        mv_box = QFrame()
        mv_box.setObjectName("groupBox")
        mv_l = QVBoxLayout(mv_box)
        mv_l.setContentsMargins(12, 10, 12, 10)
        mv_l.setSpacing(8)

        mv_hdr = QLabel("MOVEMENT")
        mv_hdr.setObjectName("groupHeader")
        mv_l.addWidget(mv_hdr)

        self._walkspeed_default = 170

        sp_row = QHBoxLayout()
        sp_label = QLabel("Walkspeed")
        sp_label.setObjectName("panelSubTitle")
        sp_row.addWidget(sp_label, 0)

        self.walkspeed_slider = QSlider(Qt.Horizontal)
        self.walkspeed_slider.setObjectName("panelSlider")
        self.walkspeed_slider.setRange(1, 1500)
        self.walkspeed_slider.setValue(self._walkspeed_default)
        sp_row.addWidget(self.walkspeed_slider, 1)

        self.walkspeed_value_lbl = QLabel(str(self.walkspeed_slider.value()))
        self.walkspeed_value_lbl.setObjectName("panelChip")
        sp_row.addWidget(self.walkspeed_value_lbl, 0)

        self.walkspeed_apply_btn = QPushButton("Apply")
        self.walkspeed_apply_btn.setObjectName("panelButtonPrimary")
        sp_row.addWidget(self.walkspeed_apply_btn, 0)

        self.walkspeed_default_btn = QPushButton("Default")
        self.walkspeed_default_btn.setObjectName("panelButton")
        sp_row.addWidget(self.walkspeed_default_btn, 0)
        mv_l.addLayout(sp_row)

        player_layout.addWidget(mv_box)
        player_layout.addStretch(1)

        # ================== WEAPONS ==================
        weapon_target_box = QFrame()
        weapon_target_box.setObjectName("groupBox")
        weapon_target_l = QVBoxLayout(weapon_target_box)
        weapon_target_l.setContentsMargins(12, 10, 12, 10)
        weapon_target_l.setSpacing(8)

        weapon_target_hdr = QLabel("WEAPON TARGET")
        weapon_target_hdr.setObjectName("groupHeader")
        weapon_target_l.addWidget(weapon_target_hdr)

        weapon_target_row = QHBoxLayout()
        self.weapon_target_combo = QComboBox()
        self.weapon_target_combo.setObjectName("panelCombo")
        self.weapon_target_combo.addItem("No Players Found", "SELF")
        self.weapon_target_combo.setEnabled(False)
        weapon_target_row.addWidget(self.weapon_target_combo, 1)

        self.weapon_refresh_players_btn = QPushButton("Refresh Players")
        self.weapon_refresh_players_btn.setObjectName("panelButton")
        weapon_target_row.addWidget(self.weapon_refresh_players_btn)
        weapon_target_l.addLayout(weapon_target_row)

        weapon_target_hint = QLabel("Weapons apply to the selected player (default: Self).")
        weapon_target_hint.setObjectName("panelHint")
        weapon_target_hint.setWordWrap(True)
        weapon_target_l.addWidget(weapon_target_hint)

        weapons_layout.addWidget(weapon_target_box)

        weapon_focus_box = QFrame()
        weapon_focus_box.setObjectName("groupBox")
        weapon_focus_l = QVBoxLayout(weapon_focus_box)
        weapon_focus_l.setContentsMargins(12, 10, 12, 10)
        weapon_focus_l.setSpacing(8)

        weapon_focus_hdr = QLabel("FOCUSED WEAPON")
        weapon_focus_hdr.setObjectName("groupHeader")
        weapon_focus_l.addWidget(weapon_focus_hdr)

        self.weapon_focus_lbl = QLabel("Focused: -- | Target: --")
        self.weapon_focus_lbl.setObjectName("panelChip")
        self.weapon_focus_lbl.setWordWrap(True)
        weapon_focus_l.addWidget(self.weapon_focus_lbl)

        weapon_focus_hint = QLabel("Auto-updates from the selected player's current weapon.")
        weapon_focus_hint.setObjectName("panelHint")
        weapon_focus_hint.setWordWrap(True)
        weapon_focus_l.addWidget(weapon_focus_hint)

        weapons_layout.addWidget(weapon_focus_box)

        weapon_cmd_box = QFrame()
        weapon_cmd_box.setObjectName("groupBox")
        weapon_cmd_l = QVBoxLayout(weapon_cmd_box)
        weapon_cmd_l.setContentsMargins(12, 10, 12, 10)
        weapon_cmd_l.setSpacing(8)

        weapon_cmd_hdr = QLabel("WEAPON COMMANDS")
        weapon_cmd_hdr.setObjectName("groupHeader")
        weapon_cmd_l.addWidget(weapon_cmd_hdr)

        dmg_row = QHBoxLayout()
        dmg_label = QLabel("Damage")
        dmg_label.setObjectName("panelSubTitle")
        dmg_row.addWidget(dmg_label, 0)

        self.weapon_dmg_input = QLineEdit("100")
        self.weapon_dmg_input.setObjectName("panelInput")
        self.weapon_dmg_input.setFixedWidth(80)
        dmg_row.addWidget(self.weapon_dmg_input, 0)
        dmg_row.addStretch(1)

        self.weapon_dmg_apply_btn = QPushButton("Apply")
        self.weapon_dmg_apply_btn.setObjectName("panelButtonPrimary")
        dmg_row.addWidget(self.weapon_dmg_apply_btn, 0)
        weapon_cmd_l.addLayout(dmg_row)

        self.weapon_unlimited_cb = QCheckBox("Unlimited Ammo")
        self.weapon_unlimited_cb.setObjectName("panelCheck")
        weapon_cmd_l.addWidget(self.weapon_unlimited_cb)

        max_row = QHBoxLayout()
        self.weapon_maxammo_btn = QPushButton("Max Ammo")
        self.weapon_maxammo_btn.setObjectName("panelButton")
        max_row.addWidget(self.weapon_maxammo_btn)
        max_row.addStretch(1)
        weapon_cmd_l.addLayout(max_row)

        weapons_layout.addWidget(weapon_cmd_box)

        weapon_types_box = QFrame()
        weapon_types_box.setObjectName("groupBox")
        weapon_types_l = QVBoxLayout(weapon_types_box)
        weapon_types_l.setContentsMargins(12, 10, 12, 10)
        weapon_types_l.setSpacing(8)

        weapon_types_hdr = QLabel("WEAPON TYPES")
        weapon_types_hdr.setObjectName("groupHeader")
        weapon_types_l.addWidget(weapon_types_hdr)

        self.weapon_rows = []
        for code, label in WEAPON_TYPES:
            row = QHBoxLayout()
            name_lbl = QLabel(label)
            name_lbl.setObjectName("panelSubTitle")
            row.addWidget(name_lbl, 1)

            dist_lbl = QLabel("Nearest: --")
            dist_lbl.setObjectName("panelChip")
            row.addWidget(dist_lbl, 0)

            goto_btn = QPushButton("Go To")
            goto_btn.setObjectName("panelButtonPrimary")
            goto_btn.setEnabled(False)
            row.addWidget(goto_btn, 0)

            bring_btn = QPushButton("Bring")
            bring_btn.setObjectName("panelButton")
            bring_btn.setEnabled(False)
            row.addWidget(bring_btn, 0)

            weapon_types_l.addLayout(row)
            self.weapon_rows.append({
                "code": code,
                "label": label,
                "dist": dist_lbl,
                "goto": goto_btn,
                "bring": bring_btn,
            })

        weapon_types_hint = QLabel("Distances update from the world registry.")
        weapon_types_hint.setObjectName("panelHint")
        weapon_types_hint.setWordWrap(True)
        weapon_types_l.addWidget(weapon_types_hint)

        weapons_layout.addWidget(weapon_types_box)
        weapons_layout.addStretch(1)

        # Wire events
        self.refresh_players_btn.clicked.connect(self._refresh_players)
        self.target_combo.currentIndexChanged.connect(self._update_target_actions)
        self.goto_player_btn.clicked.connect(self._goto_player)
        self.bring_player_btn.clicked.connect(self._bring_player)
        self.heal_btn.clicked.connect(self._heal)
        self.hp_slider.valueChanged.connect(self._on_hp_slider)
        self.max_hp_slider.valueChanged.connect(self._on_max_hp_slider)
        self.hp_apply_btn.clicked.connect(self._set_hp)
        self.max_hp_apply_btn.clicked.connect(self._set_max_hp)
        self.max_hp_default_btn.clicked.connect(self._set_default_max_hp)
        self.godmode_cb.stateChanged.connect(self._toggle_godmode)
        self.unlimited_stamina_cb.stateChanged.connect(self._toggle_stamina)
        self.unlimited_battery_cb.stateChanged.connect(self._toggle_battery)
        self.invisible_cb.stateChanged.connect(self._toggle_invisible)
        self.walkspeed_slider.valueChanged.connect(self._on_walkspeed_slider)
        self.walkspeed_apply_btn.clicked.connect(self._set_walkspeed)
        self.walkspeed_default_btn.clicked.connect(self._set_default_walkspeed)

        self.weapon_refresh_players_btn.clicked.connect(self._refresh_players)
        self.weapon_target_combo.currentIndexChanged.connect(self._on_weapon_target_changed)
        self.weapon_dmg_apply_btn.clicked.connect(self._set_weapon_damage)
        self.weapon_unlimited_cb.stateChanged.connect(self._toggle_unlimited_ammo)
        self.weapon_maxammo_btn.clicked.connect(self._max_ammo)
        for row in self.weapon_rows:
            row["goto"].clicked.connect(
                lambda _=False, c=row["code"]: self._weapon_goto(c)
            )
            row["bring"].clicked.connect(
                lambda _=False, c=row["code"]: self._weapon_bring(c)
            )

        self.world_refresh_btn.clicked.connect(self._refresh_world)
        self.world_filter_combo.currentIndexChanged.connect(self._refresh_world_list)
        self.world_sort_combo.currentIndexChanged.connect(self._refresh_world_list)
        self.world_list.currentItemChanged.connect(self._update_world_actions)
        self.world_tp_btn.clicked.connect(self._world_teleport)
        self.world_bring_btn.clicked.connect(self._world_bring)

        self.tp_refresh_btn.clicked.connect(self._refresh_tp_state)
        self.tp_set_return_btn.clicked.connect(self._tp_set_return)
        self.tp_return_btn.clicked.connect(self._tp_return)
        self.tp_map_btn.clicked.connect(self._tp_map_teleport)
        self.tp_map_combo.currentIndexChanged.connect(self._update_tp_actions)
        self.tp_near_tp_btn.clicked.connect(self._tp_nearest)
        self.tp_near_bring_btn.clicked.connect(self._tp_bring_nearest)
        self.tp_near_combo.currentIndexChanged.connect(self._update_tp_actions)
        self.tp_bring_all_btn.clicked.connect(self._tp_bring_all)
        self.tp_target_combo.currentIndexChanged.connect(self._on_tp_target_changed)
        self.tp_dest_combo.currentIndexChanged.connect(self._update_tp_actions)
        self.tp_player_btn.clicked.connect(self._tp_player_to)
        self.tp_all_combo.currentIndexChanged.connect(self._update_tp_actions)
        self.tp_all_btn.clicked.connect(self._tp_all_players)

        self.puzzle_refresh_btn.clicked.connect(self._refresh_puzzles)
        self.pipes_enable_all_btn.clicked.connect(lambda: self._pipe_all(True))
        self.pipes_disable_all_btn.clicked.connect(lambda: self._pipe_all(False))
        for row in self.pipe_rows:
            row["on"].clicked.connect(
                lambda _=False, c=row["color"], i=row["idx"]: self._pipe_set(c, i, True)
            )
            row["off"].clicked.connect(
                lambda _=False, c=row["color"], i=row["idx"]: self._pipe_set(c, i, False)
            )
            row["tp"].clicked.connect(
                lambda _=False, c=row["color"], i=row["idx"]: self._pipe_tp(c, i)
            )
        self.air_enable_all_btn.clicked.connect(lambda: self._airlock_all(True))
        self.air_disable_all_btn.clicked.connect(lambda: self._airlock_all(False))
        for row in self.air_rows:
            row["on"].clicked.connect(
                lambda _=False, i=row["idx"]: self._airlock_set(i, True)
            )
            row["off"].clicked.connect(
                lambda _=False, i=row["idx"]: self._airlock_set(i, False)
            )

        self.contract_refresh_btn.clicked.connect(self._refresh_contract_state)
        self.contract_open_btn.clicked.connect(self._open_contracts)
        self.contract_start_btn.clicked.connect(self._start_contract)
        self.contract_apply_btn.clicked.connect(self._apply_contract)
        for name, row in self._contract_controls.items():
            if row.get("kind") == "bool":
                row["widget"].stateChanged.connect(lambda _=False, n=name: self._on_contract_toggle(n))
            else:
                if row.get("dropdown"):
                    row["widget"].currentIndexChanged.connect(
                        lambda _=False, n=name: self._on_contract_value_changed(n)
                    )
                else:
                    row["widget"].textChanged.connect(
                        lambda _=False, n=name: self._on_contract_value_changed(n)
                    )

        self.verbose_cb.stateChanged.connect(self._toggle_hook_prints)
        self.debug_refresh_btn.clicked.connect(self._debug_force_refresh)
        self.debug_resync_btn.clicked.connect(self._debug_force_resync)
        self.debug_clear_btn.clicked.connect(self._debug_clear_registry)
        self.debug_rebuild_btn.clicked.connect(self._debug_rebuild_registry)

        self._invoke.connect(self._run_invoked)

        # Ack polling (bridge responses)
        self._ack_path = ACK_PATH
        self._ack_handlers = {}
        self._ack_watcher = QFileSystemWatcher(self)
        self._last_ack_time = 0.0
        try:
            if self._ack_path:
                if not Path(self._ack_path).exists():
                    Path(self._ack_path).write_text("", encoding="utf-8")
                self._ack_watcher.addPath(self._ack_path)
        except Exception:
            pass
        self._ack_watcher.fileChanged.connect(self._on_ack_changed)

        # Teleport state cache
        self._tp_state = {
            "map": "Unknown",
            "pawn": False,
            "return": False,
            "teleports": [],
            "near": {},
            "others": 0,
        }
        self._puzzle_state = {
            "pipe_found": False,
            "pipe_red": [None] * 8,
            "pipe_blue": [None] * 8,
            "air_found": False,
            "air_entries": [],
        }
        self._contract_state = {
            "ready": False,
            "map": "Unknown",
            "lists": 0,
            "first": False,
            "props": 0,
            "hooks": 0,
            "age": None,
            "types": {},
            "values": {},
        }
        self._world_entries = []
        self._world_self_pos = None
        self._last_cmd_sent = ""
        self._last_cmd_time = 0.0
        self._player_names = []
        self._self_name = None
        self._refresh_queue = []
        self._state_data = {}
        self._weapon_state = {}
        self._last_weapon_state_request = 0.0

        self._update_target_actions()
        self._update_tp_actions()
        self._update_puzzle_actions()
        self._sync_contract_controls_from_state()
        self._update_contract_actions()

        # Notice watcher (event-based updates from UE4SS)
        self._notice_path = NOTICE_PATH
        self._notice_watcher = QFileSystemWatcher(self)
        self._last_notice_line = ""
        try:
            if self._notice_path:
                if not Path(self._notice_path).exists():
                    Path(self._notice_path).write_text("", encoding="utf-8")
                self._notice_watcher.addPath(self._notice_path)
        except Exception:
            pass
        self._notice_watcher.fileChanged.connect(self._on_notice_changed)

        # Registry watcher (world registry updates)
        self._registry_path = REGISTRY_PATH
        self._registry_watcher = QFileSystemWatcher(self)
        self._last_registry_line = ""
        self._last_registry_update = 0.0
        try:
            if self._registry_path:
                if not Path(self._registry_path).exists():
                    Path(self._registry_path).write_text("", encoding="utf-8")
                self._registry_watcher.addPath(self._registry_path)
        except Exception:
            pass
        self._registry_watcher.fileChanged.connect(self._on_registry_changed)

        # State polling (info/debug bar)
        self._state_path = STATE_PATH
        self._last_state_line = ""
        self._last_state_read = 0.0
        self._last_state_write = 0.0
        try:
            if self._state_path and not Path(self._state_path).exists():
                Path(self._state_path).write_text("", encoding="utf-8")
        except Exception:
            pass
        self._state_timer = QTimer(self)
        self._state_timer.setInterval(250)
        self._state_timer.timeout.connect(self._poll_state)
        self._state_timer.start()

        self._weapon_state_timer = QTimer(self)
        self._weapon_state_timer.setInterval(600)
        self._weapon_state_timer.timeout.connect(self._tick_weapon_state)
        self._weapon_state_timer.start()

        # Initial sync
        self._schedule(0.15, self._refresh_players)
        self._schedule(0.20, self._refresh_tp_state)
        self._schedule(0.25, self._refresh_puzzles)
        self._schedule(0.30, self._refresh_contract_state)

        self.setStyleSheet("""
            QWidget {
                color: rgba(220, 210, 255, 225);
                font-family: "Cascadia Mono", "Consolas";
                font-size: 11px;
            }
            QWidget#actionPanel {
                background: transparent;
            }
            QFrame#panelHeader {
                background: qlineargradient(x1:0, y1:0, x2:1, y2:1,
                    stop:0 rgba(6, 6, 12, 240),
                    stop:1 rgba(20, 10, 30, 240));
                border: 1px solid rgba(140, 100, 220, 190);
                border-radius: 14px;
            }
            QLabel#panelTitle {
                color: rgba(235, 220, 255, 240);
                font-family: "Agency FB";
                font-size: 20px;
                font-weight: 700;
                letter-spacing: 3px;
            }
            QLabel#panelSubtitle {
                color: rgba(170, 140, 220, 220);
                font-size: 10px;
                letter-spacing: 4px;
            }
            QLabel#panelSubTitle {
                color: rgba(190, 170, 240, 230);
                font-weight: 600;
            }
            QLabel#panelChip {
                background: rgba(10, 8, 16, 230);
                border: 1px solid rgba(140, 100, 220, 200);
                border-radius: 10px;
                padding: 4px 8px;
                font-size: 10px;
                letter-spacing: 1px;
            }
            QFrame#panelBody {
                background: rgba(6, 6, 10, 220);
                border: 1px solid rgba(90, 70, 130, 140);
                border-radius: 12px;
            }
            QFrame#panelStatus {
                background: rgba(12, 10, 18, 220);
                border: 1px solid rgba(110, 90, 170, 140);
                border-radius: 10px;
            }
            QTabWidget::pane {
                border: 1px solid rgba(80, 60, 120, 140);
                border-radius: 10px;
                background: rgba(8, 8, 14, 230);
            }
            QTabBar::tab {
                background: rgba(14, 10, 20, 220);
                border: 1px solid rgba(90, 70, 140, 140);
                border-bottom: none;
                border-top-left-radius: 8px;
                border-top-right-radius: 8px;
                padding: 7px 14px;
                margin-right: 6px;
            }
            QTabBar::tab:selected {
                background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
                    stop:0 rgba(130, 90, 220, 220),
                    stop:1 rgba(170, 120, 240, 220));
                color: rgba(240, 230, 255, 240);
            }
            QTabBar::tab:hover {
                background: rgba(40, 28, 60, 220);
            }
            QScrollArea#panelScroll {
                background: transparent;
            }
            QFrame#groupBox {
                background: qlineargradient(x1:0, y1:0, x2:1, y2:1,
                    stop:0 rgba(10, 10, 18, 230),
                    stop:1 rgba(18, 12, 28, 230));
                border: 1px solid rgba(120, 90, 200, 150);
                border-radius: 12px;
            }
            QFrame#groupBox:hover {
                border: 1px solid rgba(160, 120, 230, 190);
            }
            QLabel#groupHeader {
                color: rgba(210, 190, 255, 240);
                font-family: "Agency FB";
                font-size: 12px;
                font-weight: 700;
                letter-spacing: 2px;
            }
            QLabel#panelHint {
                color: rgba(150, 130, 200, 210);
                font-size: 10px;
            }
            QLabel#panelList, QListWidget#panelList {
                background: rgba(8, 8, 14, 230);
                border: 1px solid rgba(100, 80, 160, 140);
                border-radius: 8px;
                padding: 6px 8px;
                font-size: 10px;
            }
            QListWidget#panelList::item {
                padding: 4px 2px;
            }
            QListWidget#panelList::item:selected {
                background: rgba(120, 90, 210, 140);
            }
            QComboBox#panelCombo {
                background: rgba(8, 8, 14, 235);
                border: 1px solid rgba(120, 90, 200, 150);
                padding: 6px;
                border-radius: 8px;
            }
            QComboBox::drop-down {
                border: none;
                width: 24px;
            }
            QComboBox QAbstractItemView {
                background: rgba(8, 8, 14, 240);
                border: 1px solid rgba(120, 90, 200, 150);
                selection-background-color: rgba(130, 90, 220, 120);
            }
            QLineEdit#panelInput {
                background: rgba(8, 8, 14, 235);
                border: 1px solid rgba(120, 90, 200, 150);
                padding: 4px 6px;
                border-radius: 6px;
            }
            QLineEdit#panelInput:focus {
                border: 1px solid rgba(180, 140, 255, 210);
            }
            QLineEdit#panelInput:disabled {
                color: rgba(140, 130, 160, 160);
                background: rgba(20, 18, 24, 140);
                border: 1px solid rgba(60, 60, 80, 120);
            }
            QCheckBox#panelCheck {
                spacing: 6px;
            }
            QCheckBox#panelCheck::indicator {
                width: 14px;
                height: 14px;
                border-radius: 3px;
                border: 1px solid rgba(140, 110, 210, 190);
                background: rgba(8, 8, 12, 230);
            }
            QCheckBox#panelCheck::indicator:checked {
                background: rgba(160, 120, 240, 230);
                border: 1px solid rgba(200, 160, 255, 220);
            }
            QCheckBox#panelCheck:disabled {
                color: rgba(140, 130, 160, 160);
            }
            QPushButton#panelButtonPrimary {
                background: rgba(120, 90, 210, 220);
                border: 1px solid rgba(170, 120, 240, 230);
                border-radius: 8px;
                padding: 6px 10px;
                font-weight: 600;
            }
            QPushButton#panelButtonPrimary:hover { background: rgba(170, 120, 240, 230); }
            QPushButton#panelButton {
                background: rgba(20, 16, 28, 220);
                border: 1px solid rgba(110, 80, 180, 180);
                border-radius: 8px;
                padding: 6px 10px;
            }
            QPushButton#panelButton:hover { background: rgba(32, 24, 44, 230); }
            QPushButton:disabled {
                color: rgba(140, 130, 160, 160);
                background: rgba(20, 18, 24, 140);
                border: 1px solid rgba(60, 60, 80, 120);
            }
            QSlider#panelSlider::groove:horizontal {
                height: 8px;
                background: rgba(8, 8, 14, 230);
                border: 1px solid rgba(120, 90, 200, 120);
                border-radius: 6px;
            }
            QSlider#panelSlider::handle:horizontal {
                width: 14px;
                background: rgba(160, 120, 240, 230);
                border-radius: 7px;
                margin: -4px 0;
                border: 1px solid rgba(200, 160, 255, 200);
            }
            QScrollBar:vertical {
                background: rgba(8, 8, 14, 180);
                width: 10px;
                margin: 2px 2px 2px 2px;
                border-radius: 5px;
            }
            QScrollBar::handle:vertical {
                background: rgba(130, 90, 220, 180);
                border-radius: 5px;
                min-height: 20px;
            }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
                height: 0px;
            }
            QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {
                background: none;
            }
        """)

        # Move to right side (top-right-ish)
        try:
            screen = QApplication.primaryScreen()
            geo = screen.availableGeometry() if screen else None
            if geo:
                x = geo.x() + geo.width() - self.width() - 20
                y = geo.y() + 20
                self.move(max(geo.x(), x), y)
        except Exception:
            pass

    # ----------------- Commands -----------------
    def _send(self, name: str, arg: str = ""):
        if self._send_cmd is None:
            return None
        try:
            self._last_cmd_sent = f"{name} {arg}".strip()
            self._last_cmd_time = time.monotonic()
            return self._send_cmd(name, arg)
        except Exception:
            return None

    def show_toast(self, text: str, level: str = "INFO", duration_ms: int = 2500):
        try:
            mgr = self._toast_mgr_external or self._toast_mgr
            mgr.show(text, level, duration_ms)
        except Exception:
            pass

    def set_toast_manager(self, mgr):
        if mgr is not None:
            self._toast_mgr_external = mgr

    def showEvent(self, event):
        super().showEvent(event)
        if not self._initial_splash_shown:
            self._initial_splash_shown = True
            self.show_toast("Blackbox Loaded!", "OK", 2400)
        self._schedule(0.05, self._refresh_players)
        self._schedule(0.08, self._refresh_tp_state)
        self._schedule(0.11, self._refresh_puzzles)
        self._schedule(0.14, self._refresh_contract_state)
        self._schedule(0.17, self._refresh_weapon_state)

    def set_panel_request_cb(self, cb):
        self._panel_request_cb = cb

    def _emit_panel_request(self, open_value: bool):
        want = open_value and True or False
        if self._panel_requested == want:
            return
        self._panel_requested = want
        if self._panel_request_cb:
            try:
                self._panel_request_cb(want)
            except Exception:
                pass

    def _target_text(self) -> str:
        if self.target_combo is None:
            return ""
        if not self.target_combo.isEnabled():
            return ""
        if self._is_self_selected():
            return ""
        data = self.target_combo.currentData()
        if data is None or str(data).strip() == "":
            return ""
        return str(data).strip()

    def _is_self_selected(self) -> bool:
        if not self.target_combo or not self.target_combo.isEnabled():
            return True
        text = str(self.target_combo.currentText() or "").strip().lower()
        if text.startswith("self") or "(self)" in text:
            return True
        data = self.target_combo.currentData()
        if data is None or str(data).strip() == "" or str(data).upper() == "SELF":
            return True
        return False

    def _update_target_actions(self):
        disable = (not self.target_combo.isEnabled()) or self._is_self_selected()
        self.goto_player_btn.setEnabled(not disable)
        self.bring_player_btn.setEnabled(not disable)

    def _weapon_target_name(self) -> str:
        if not self.weapon_target_combo or not self.weapon_target_combo.isEnabled():
            return "self"
        data = self.weapon_target_combo.currentData()
        if data is None or str(data).strip() == "":
            return "self"
        if str(data).strip().upper() == "SELF":
            return "self"
        return str(data).strip()

    def _weapon_target_display(self, target: str | None = None) -> str:
        target = str(target or "").strip()
        if not target:
            target = self._weapon_target_name()
        if target.lower() == "self":
            if self._self_name:
                return f"{self._self_name} (Self)"
            return "Self"
        if self._self_name and target.lower() == str(self._self_name).strip().lower():
            return f"{self._self_name} (Self)"
        return target

    def _weapon_arg_with_target(self, arg: str) -> str:
        target = self._weapon_target_name()
        if target and target.lower() != "self":
            if arg:
                return f"{arg} {target}"
            return target
        return arg

    def _set_weapon_focus_label(
        self,
        name: str | None,
        code: str | None,
        target: str | None,
        ok: bool | None,
        cls: str | None = None,
    ):
        if not self.weapon_focus_lbl:
            return
        target_label = self._weapon_target_display(target)
        if ok is False:
            focus_text = "Focused: None"
        elif name or code:
            if name and code and code not in name:
                focus_text = f"Focused: {name} ({code})"
            else:
                focus_text = f"Focused: {name or code}"
        else:
            focus_text = "Focused: --"
        self.weapon_focus_lbl.setText(f"{focus_text} | Target: {target_label}")
        if cls:
            tip_parts = []
            if name or code:
                tip_parts.append(f"{name or ''}{f' ({code})' if code else ''}".strip())
            tip_parts.append(str(cls))
            self.weapon_focus_lbl.setToolTip("\n".join([p for p in tip_parts if p]))
        else:
            self.weapon_focus_lbl.setToolTip("")

    def _on_weapon_target_changed(self):
        self._set_weapon_focus_label(None, None, self._weapon_target_name(), None)
        self._refresh_weapon_state()

    def _refresh_weapon_targets(self, current=None):
        if not self.weapon_target_combo:
            return
        self.weapon_target_combo.blockSignals(True)
        self.weapon_target_combo.clear()

        self_name = self._self_name
        others = []
        for name in self._player_names:
            if self_name and str(name).strip().lower() == str(self_name).strip().lower():
                continue
            others.append(name)

        if not others and not self_name:
            self.weapon_target_combo.addItem("No Players Found", "SELF")
            self.weapon_target_combo.setEnabled(False)
        else:
            self.weapon_target_combo.setEnabled(True)
            if self_name:
                self.weapon_target_combo.addItem(f"{self_name} (Self)", "SELF")
            else:
                self.weapon_target_combo.addItem("Self", "SELF")
            for name in sorted(others, key=lambda s: str(s).lower()):
                self.weapon_target_combo.addItem(name, name)
            if current:
                idx = self.weapon_target_combo.findData(current)
                if idx >= 0:
                    self.weapon_target_combo.setCurrentIndex(idx)
        self.weapon_target_combo.blockSignals(False)
        self._set_weapon_focus_label(None, None, self._weapon_target_name(), None)

    def _with_target(self, base: str) -> str:
        t = self._target_text()
        if t:
            return (f"{base} {t}").strip()
        return base.strip()

    def _refresh_players(self):
        if self._ack_handlers:
            return
        cmd_id = self._send("listplayers_gui", "")
        if not cmd_id:
            return
        self._queue_ack(cmd_id, self._handle_players_ack, 2.5)

    def _goto_player(self):
        t = self._target_text()
        if not t:
            return
        self._send("gotoplayer", t)

    def _bring_player(self):
        t = self._target_text()
        if not t:
            return
        self._send("bringplayer", t)

    def _set_weapon_damage(self):
        if not self.weapon_dmg_input:
            return
        raw = str(self.weapon_dmg_input.text() or "").strip()
        if not raw:
            self.show_toast("Enter a damage value.", "WARN", 2000)
            return
        try:
            dmg = float(raw)
        except Exception:
            self.show_toast("Invalid damage value.", "ERROR", 2200)
            return
        arg = self._weapon_arg_with_target(str(dmg))
        self._send("setweapondmg", arg)

    def _toggle_unlimited_ammo(self):
        state = "on" if self.weapon_unlimited_cb.isChecked() else "off"
        arg = self._weapon_arg_with_target(state)
        self._send("unlimitedammo", arg)

    def _max_ammo(self):
        arg = self._weapon_arg_with_target("")
        self._send("maxammo", arg)

    def _weapon_goto(self, code: str):
        code = str(code or "").strip().upper()
        if not code:
            return
        self._send("gotoweapon", code)

    def _weapon_bring(self, code: str):
        code = str(code or "").strip().upper()
        if not code:
            return
        self._send("bringweapon", code)

    def _refresh_weapon_state(self):
        if self._ack_handlers:
            return False
        target = self._weapon_target_name()
        arg = "" if target.lower() == "self" else target
        cmd_id = self._send("weapon_gui_state", arg)
        if not cmd_id:
            return False
        self._last_weapon_state_request = time.monotonic()
        self._queue_ack(cmd_id, self._handle_weapon_state_ack, 1.5)
        return True

    def _handle_weapon_state_ack(self, ok: bool, msg: str):
        if not ok or not msg.startswith("WEAPONSTATE="):
            return
        payload = msg[len("WEAPONSTATE="):]
        data = {}
        for part in str(payload or "").split("#"):
            if ":" not in part:
                continue
            key, val = part.split(":", 1)
            data[key.strip().upper()] = val.strip()
        self._weapon_state = data
        self._apply_weapon_state()

    def _apply_weapon_state(self):
        data = self._weapon_state or {}
        ok = str(data.get("OK") or "").strip().lower() in ("1", "true", "yes", "on")
        name = data.get("NAME") or ""
        code = data.get("CODE") or ""
        code_key = code.upper() if code else ""
        target = data.get("TARGET") or ""
        cls = data.get("CLASS") or ""

        current_target = self._weapon_target_name()
        if target and current_target and target.lower() != current_target.lower():
            return

        if not ok:
            self._set_weapon_focus_label(None, None, target, False, None)
            return
        if not name and code:
            name = WEAPON_LABELS.get(code_key, code)
        self._set_weapon_focus_label(name, code_key or code, target, True, cls if cls else None)

    def _tick_weapon_state(self):
        if not self.isVisible():
            return
        if self._ack_handlers:
            return
        now = time.monotonic()
        if (now - self._last_weapon_state_request) < 0.5:
            return
        self._refresh_weapon_state()

    def _weapon_nearest_distances(self) -> dict:
        out = {}
        for entry in self._world_entries:
            if str(entry.get("tag") or "").upper() != "WEAPON":
                continue
            code = str(entry.get("code") or "").upper()
            if not code:
                continue
            if str(entry.get("status") or "").lower() == "collected":
                continue
            dist = self._world_distance(entry)
            if dist is None:
                continue
            prev = out.get(code)
            if not prev or dist < prev["dist"]:
                out[code] = {"dist": dist, "entry": entry}
        return out

    def _refresh_weapon_rows(self):
        if not getattr(self, "weapon_rows", None):
            return
        distances = self._weapon_nearest_distances()
        for row in self.weapon_rows:
            code = row.get("code")
            info = distances.get(str(code or "").upper())
            if info and info.get("dist") is not None:
                dist = float(info["dist"])
                row["dist"].setText(f"Nearest: {dist:.1f}m")
                row["goto"].setEnabled(True)
                row["bring"].setEnabled(True)
            else:
                row["dist"].setText("Nearest: --")
                row["goto"].setEnabled(False)
                row["bring"].setEnabled(False)

    def _heal(self):
        self._send("heal", self._with_target(""))

    def _on_hp_slider(self, v: int):
        self.hp_value_lbl.setText(str(int(v)))

    def _on_max_hp_slider(self, v: int):
        v = max(1, int(v))
        self.max_hp_value_lbl.setText(str(v))
        self.hp_slider.setMaximum(v)
        if self.hp_slider.value() > v:
            self.hp_slider.setValue(v)

    def _set_hp(self):
        v = str(self.hp_slider.value())
        self._send("sethp", self._with_target(v))

    def _set_max_hp(self):
        v = str(self.max_hp_slider.value())
        self._send("setmaxhp", self._with_target(v))

    def _set_default_max_hp(self):
        self.max_hp_slider.setValue(int(self._max_hp_default))
        self._set_max_hp()

    def _toggle_godmode(self):
        state = "on" if self.godmode_cb.isChecked() else "off"
        self._send("god", self._with_target(state))

    def _toggle_stamina(self):
        state = "on" if self.unlimited_stamina_cb.isChecked() else "off"
        self._send("stamina", self._with_target(state))

    def _toggle_battery(self):
        state = "on" if self.unlimited_battery_cb.isChecked() else "off"
        self._send("battery", self._with_target(state))

    def _toggle_invisible(self):
        state = "on" if self.invisible_cb.isChecked() else "off"
        self._send("invisible", self._with_target(state))

    def _toggle_hook_prints(self):
        state = "on" if self.verbose_cb.isChecked() else "off"
        self._send("hookprints", state)

    def _debug_force_refresh(self):
        self._send("state_snapshot", "")

    def _debug_force_resync(self):
        self._world_entries = []
        self._world_self_pos = None
        if self.world_list:
            self.world_list.clear()
        self._refresh_weapon_rows()
        self._send("state_snapshot", "")
        self._refresh_players()
        self._refresh_tp_state()
        self._refresh_puzzles()
        self._refresh_contract_state()
        self._refresh_world()

    def _debug_clear_registry(self):
        if QMessageBox.question(self, "Confirm", "Clear world registry?") != QMessageBox.Yes:
            return
        self._send("registry_clear", "")

    def _debug_rebuild_registry(self):
        if QMessageBox.question(self, "Confirm", "Rebuild world registry (full rescan)?") != QMessageBox.Yes:
            return
        self._send("registry_rebuild", "")

    def _on_walkspeed_slider(self, v: int):
        self.walkspeed_value_lbl.setText(str(int(v)))

    def _set_walkspeed(self):
        v = str(self.walkspeed_slider.value())
        self._send("walkspeed", self._with_target(v))

    def _set_default_walkspeed(self):
        self.walkspeed_slider.setValue(int(self._walkspeed_default))
        self._set_walkspeed()

    def _refresh_tp_state(self):
        if self._ack_handlers:
            return False
        cmd_id = self._send("tp_gui_state", "")
        if not cmd_id:
            return False
        self._queue_ack(cmd_id, self._handle_tp_state_ack, 2.5)
        return True

    def _refresh_puzzles(self):
        if self._ack_handlers:
            return False
        cmd_id = self._send("puzzlestate", "")
        if not cmd_id:
            return False
        self._queue_ack(cmd_id, self._handle_puzzles_ack, 2.5)
        return True

    def _refresh_contract_state(self):
        if self._ack_handlers:
            return False
        cmd_id = self._send("contract_gui_state", "")
        if not cmd_id:
            return False
        self._queue_ack(cmd_id, self._handle_contract_state_ack, 2.5)
        return True

    def _refresh_world(self):
        if self._ack_handlers:
            return False
        cmd_id = self._send("world_registry_scan", "")
        return bool(cmd_id)

    def _queue_followup_refreshes(self):
        self._enqueue_refresh("tp")
        self._enqueue_refresh("puzzles")
        self._run_refresh_queue()

    def _enqueue_refresh(self, key: str):
        if key not in self._refresh_queue:
            self._refresh_queue.append(key)

    def _run_refresh_queue(self):
        if self._ack_handlers or not self._refresh_queue:
            return
        next_key = self._refresh_queue[0]
        started = False
        if next_key == "tp":
            started = self._refresh_tp_state()
        elif next_key == "puzzles":
            started = self._refresh_puzzles()
        elif next_key == "contracts":
            started = self._refresh_contract_state()
        if started:
            self._refresh_queue.pop(0)

    def _queue_ack(self, cmd_id, handler, timeout_s: float):
        try:
            ack_id = str(cmd_id)
            deadline = time.monotonic() + float(timeout_s)
            self._ack_handlers[ack_id] = (deadline, handler)
        except Exception:
            pass

    def _cleanup_acks(self):
        now = time.monotonic()
        expired = [k for k, v in self._ack_handlers.items() if v[0] < now]
        for k in expired:
            del self._ack_handlers[k]

    def _on_ack_changed(self, _path: str):
        self._cleanup_acks()
        try:
            if not self._ack_path:
                return
            with open(self._ack_path, "r", encoding="utf-8") as f:
                line = (f.read() or "").strip()
        except Exception:
            return
        if not line:
            return
        self._last_ack_time = time.monotonic()
        parts = line.split("|", 3)
        if len(parts) < 4 or parts[0] != "ACK":
            return
        ack_id = parts[1]
        ok = parts[2] == "1"
        msg = parts[3] or ""
        handler_entry = self._ack_handlers.get(ack_id)
        if not handler_entry:
            if ack_id == "0":
                if msg.startswith("PUZZLES="):
                    payload = msg[len("PUZZLES="):]
                    self._apply_puzzles_state(payload)
                elif msg.startswith("TPSTATE="):
                    payload = msg[len("TPSTATE="):]
                    self._apply_tp_state(payload)
                elif msg.startswith("CONTRACTS="):
                    payload = msg[len("CONTRACTS="):]
                    self._apply_contract_state(payload)
            return
        _, handler = handler_entry
        del self._ack_handlers[ack_id]
        try:
            handler(ok, msg)
        except Exception:
            pass

        try:
            if self._ack_path and self._ack_path not in self._ack_watcher.files():
                self._ack_watcher.addPath(self._ack_path)
        except Exception:
            pass

    def _handle_players_ack(self, ok: bool, msg: str):
        if not ok or not msg.startswith("PLAYERS="):
            return
        payload = msg[len("PLAYERS="):]
        self._apply_player_list(payload)
        self._run_refresh_queue()

    def _handle_tp_state_ack(self, ok: bool, msg: str):
        if not ok or not msg.startswith("TPSTATE="):
            return
        payload = msg[len("TPSTATE="):]
        self._apply_tp_state(payload)
        self._run_refresh_queue()

    def _handle_puzzles_ack(self, ok: bool, msg: str):
        if not ok or not msg.startswith("PUZZLES="):
            return
        payload = msg[len("PUZZLES="):]
        self._apply_puzzles_state(payload)
        self._run_refresh_queue()

    def _handle_contract_state_ack(self, ok: bool, msg: str):
        if not ok or not msg.startswith("CONTRACTS="):
            return
        payload = msg[len("CONTRACTS="):]
        self._apply_contract_state(payload)
        self._run_refresh_queue()

    def _on_notice_changed(self, _path: str):
        try:
            if not self._notice_path:
                return
            p = Path(self._notice_path)
            if not p.exists():
                p.write_text("", encoding="utf-8")
                self._notice_watcher.addPath(self._notice_path)
                return
            data = p.read_text(encoding="utf-8") if p.stat().st_size > 0 else ""
        except Exception:
            return

        line = ""
        for raw in (data or "").splitlines():
            if raw.strip():
                line = raw.strip()
        if not line:
            return
        self._process_notice_line(line)

        try:
            if self._notice_path not in self._notice_watcher.files():
                self._notice_watcher.addPath(self._notice_path)
        except Exception:
            pass

    def _on_registry_changed(self, _path: str):
        try:
            if not self._registry_path:
                return
            p = Path(self._registry_path)
            if not p.exists():
                p.write_text("", encoding="utf-8")
                self._registry_watcher.addPath(self._registry_path)
                return
            data = p.read_text(encoding="utf-8") if p.stat().st_size > 0 else ""
        except Exception:
            return

        line = ""
        for raw in (data or "").splitlines():
            if raw.strip():
                line = raw.strip()
        if not line:
            return
        self._process_registry_line(line)

        try:
            if self._registry_path not in self._registry_watcher.files():
                self._registry_watcher.addPath(self._registry_path)
        except Exception:
            pass

    def _process_notice_line(self, line: str):
        if not line:
            return
        if self._handle_toast_notice(line):
            return
        if line == self._last_notice_line:
            return
        self._last_notice_line = line

        if line.startswith("PLAYERS="):
            payload = line[len("PLAYERS="):]
            self._apply_player_list(payload)
        elif line.startswith("TPSTATE="):
            payload = line[len("TPSTATE="):]
            self._apply_tp_state(payload)
        elif line.startswith("PUZZLES="):
            payload = line[len("PUZZLES="):]
            self._apply_puzzles_state(payload)
        elif line.startswith("CONTRACTS="):
            payload = line[len("CONTRACTS="):]
            self._apply_contract_state(payload)
        elif line.startswith("PANEL="):
            payload = line[len("PANEL="):]
            self._apply_panel_state(payload)
        else:
            self.show_toast(line, "INFO", 2200)

    def _handle_toast_notice(self, line: str) -> bool:
        if not line:
            return False
        if not (line.startswith("SPLASH|") or line.startswith("NOTICE|") or line.startswith("ALERT|")):
            return False
        parts = line.split("|", 3)
        kind = parts[0].upper()
        default_level = "ERROR" if kind == "ALERT" else "INFO"
        text = ""
        duration = 2500
        level = default_level

        def _parse_int(value, fallback):
            try:
                return int(float(value))
            except Exception:
                return fallback

        if len(parts) == 2:
            text = parts[1]
        elif len(parts) == 3:
            if parts[1].upper() in ("INFO", "OK", "SUCCESS", "WARN", "WARNING", "ERROR", "ALERT"):
                level = parts[1].upper()
                text = parts[2]
            else:
                text = parts[1]
                duration = _parse_int(parts[2], duration)
        else:
            if parts[1].upper() in ("INFO", "OK", "SUCCESS", "WARN", "WARNING", "ERROR", "ALERT"):
                level = parts[1].upper()
                duration = _parse_int(parts[2], duration)
                text = parts[3]
            else:
                text = parts[1]
                duration = _parse_int(parts[2], duration)
                level = parts[3].upper() if parts[3] else default_level

        text = str(text or "").strip()
        if text:
            self.show_toast(text, level, duration)
        return True

    def _process_registry_line(self, line: str):
        if not line:
            return
        if line == self._last_registry_line:
            return
        self._last_registry_line = line
        if line.startswith("WORLD="):
            payload = line[len("WORLD="):]
            self._apply_world_list(payload)
            self._last_registry_update = time.monotonic()

    def _poll_state(self):
        try:
            if not self._state_path:
                return
            p = Path(self._state_path)
            if not p.exists():
                return
            data = p.read_text(encoding="utf-8") if p.stat().st_size > 0 else ""
        except Exception:
            return

        line = ""
        for raw in (data or "").splitlines():
            if raw.strip():
                line = raw.strip()
        if not line:
            return
        self._last_state_read = time.monotonic()
        if line != self._last_state_line:
            self._last_state_line = line
            self._parse_state_line(line)
        else:
            # Still update freshness-based UI
            self._update_info_bar()
            self._update_debug_fields()

    def _parse_state_line(self, line: str):
        if not line.startswith("STATE="):
            return
        payload = line[len("STATE="):]
        data = {}
        for part in str(payload or "").split("#"):
            if ":" not in part:
                continue
            key, val = part.split(":", 1)
            data[key.strip().upper()] = val.strip()
        self._state_data = data
        panel_val = data.get("PANEL")
        if panel_val is not None:
            self._apply_panel_state(panel_val)
        try:
            self._last_state_write = float(data.get("STATEWRITE", "0") or 0)
        except Exception:
            self._last_state_write = 0.0
        self._update_info_bar()
        self._update_debug_fields()
        self._update_contract_actions()

    def _apply_panel_state(self, payload: str):
        val = str(payload or "").strip().lower()
        open_value = val in ("1", "true", "on", "open", "show", "yes")
        self._emit_panel_request(open_value)

    def _apply_player_list(self, payload: str):
        entries = [e for e in str(payload or "").split(";") if e]
        current = self.target_combo.currentData()
        tp_current = self.tp_target_combo.currentData() if self.tp_target_combo else None
        weapon_current = self.weapon_target_combo.currentData() if self.weapon_target_combo else None
        self.target_combo.blockSignals(True)
        self.target_combo.clear()

        self_name = None
        names = []
        for entry in entries:
            if entry.startswith("SELF:"):
                self_name = entry[5:]
            elif entry.startswith("P:"):
                names.append(entry[2:])
            else:
                names.append(entry)

        names = [n for n in names if n]
        all_names = set(names)
        if self_name:
            all_names.add(self_name)
        player_names = sorted(all_names, key=lambda s: str(s).lower())
        self._player_names = player_names
        self._self_name = self_name
        if not names and not self_name:
            self.target_combo.addItem("No Players Found", "")
            self.target_combo.setEnabled(False)
        else:
            self.target_combo.setEnabled(True)
            self_lower = str(self_name or "").strip().lower()
            added_self = False
            for name in sorted(names, key=lambda s: str(s).lower()):
                if self_lower and str(name).strip().lower() == self_lower:
                    self.target_combo.addItem(f"{name} (Self)", "SELF")
                    added_self = True
                else:
                    self.target_combo.addItem(name, name)
            if (not added_self) and self_name:
                self.target_combo.addItem(f"{self_name} (Self)", "SELF")
            if current:
                idx = self.target_combo.findData(current)
                if idx >= 0:
                    self.target_combo.setCurrentIndex(idx)
        self.target_combo.blockSignals(False)
        self._refresh_tp_targets(tp_current)
        self._refresh_tp_destinations()
        self._refresh_weapon_targets(weapon_current)
        self._schedule(0.2, self._refresh_weapon_state)
        self._update_target_actions()
        self._update_tp_actions()
        self._queue_followup_refreshes()

    def _player_label(self, name: str) -> str:
        name = str(name or "")
        if not name:
            return name
        if self._self_name and name.strip().lower() == str(self._self_name).strip().lower():
            return f"{name} (Self)"
        return name

    def _refresh_tp_targets(self, current=None):
        if not self.tp_target_combo:
            return
        self.tp_target_combo.blockSignals(True)
        self.tp_target_combo.clear()
        if not self._player_names:
            self.tp_target_combo.addItem("No Players Found", "")
            self.tp_target_combo.setEnabled(False)
        else:
            self.tp_target_combo.setEnabled(True)
            for name in self._player_names:
                self.tp_target_combo.addItem(self._player_label(name), name)
            if current:
                idx = self.tp_target_combo.findData(current)
                if idx >= 0:
                    self.tp_target_combo.setCurrentIndex(idx)
        self.tp_target_combo.blockSignals(False)

    def _refresh_tp_map_combo(self):
        tps = list(self._tp_state.get("teleports") or [])
        current = self.tp_map_combo.currentData()
        self.tp_map_combo.blockSignals(True)
        self.tp_map_combo.clear()
        for key, name in tps:
            self.tp_map_combo.addItem(str(name), str(key))
        self.tp_map_combo.blockSignals(False)
        if current:
            idx = self.tp_map_combo.findData(current)
            if idx >= 0:
                self.tp_map_combo.setCurrentIndex(idx)
        self.tp_map_empty_lbl.setVisible(len(tps) == 0)

        current_all = self.tp_all_combo.currentData()
        self.tp_all_combo.blockSignals(True)
        self.tp_all_combo.clear()
        for key, name in tps:
            self.tp_all_combo.addItem(str(name), str(key))
        self.tp_all_combo.blockSignals(False)
        if current_all:
            idx = self.tp_all_combo.findData(current_all)
            if idx >= 0:
                self.tp_all_combo.setCurrentIndex(idx)

    def _refresh_tp_destinations(self):
        if not self.tp_dest_combo:
            return
        target = self._tp_target_name()
        current = self.tp_dest_combo.currentData()
        self.tp_dest_combo.blockSignals(True)
        self.tp_dest_combo.clear()

        tps = list(self._tp_state.get("teleports") or [])
        for key, name in tps:
            self.tp_dest_combo.addItem(f"TP: {name}", f"TP:{key}")

        for name in self._player_names:
            if target and str(name).strip().lower() == str(target).strip().lower():
                continue
            label = self._player_label(name)
            self.tp_dest_combo.addItem(f"Player: {label}", f"P:{name}")

        if self.tp_dest_combo.count() == 0:
            self.tp_dest_combo.addItem("No Destinations", "")
            self.tp_dest_combo.setEnabled(False)
        else:
            self.tp_dest_combo.setEnabled(True)
            if current:
                idx = self.tp_dest_combo.findData(current)
                if idx >= 0:
                    self.tp_dest_combo.setCurrentIndex(idx)
        self.tp_dest_combo.blockSignals(False)

    # ----------------- Teleport UI -----------------
    def _apply_tp_state(self, payload: str):
        state = {
            "map": "Unknown",
            "pawn": False,
            "return": False,
            "teleports": [],
            "near": {},
            "others": 0,
        }
        for part in str(payload or "").split("#"):
            if ":" not in part:
                continue
            key, val = part.split(":", 1)
            key = key.strip().upper()
            val = val.strip()
            if key == "MAP":
                state["map"] = val or "Unknown"
            elif key == "PAWN":
                state["pawn"] = val == "1"
            elif key == "RETURN":
                state["return"] = val == "1"
            elif key == "OTHERS":
                try:
                    state["others"] = int(val)
                except Exception:
                    state["others"] = 0
            elif key == "TPS":
                tps = []
                for entry in val.split(","):
                    if "=" not in entry:
                        continue
                    k, n = entry.split("=", 1)
                    k = k.strip()
                    n = n.strip()
                    if k:
                        tps.append((k, n or k))
                state["teleports"] = tps
            elif key == "NEAR":
                near = {}
                for entry in val.split(","):
                    if "=" not in entry:
                        continue
                    k, v = entry.split("=", 1)
                    near[k.strip().upper()] = v.strip() == "1"
                state["near"] = near

        self._tp_state = state
        self.tp_map_lbl.setText(f"Map: {state['map']}")
        self._refresh_tp_map_combo()
        self._refresh_tp_destinations()
        self._update_tp_actions()

    # ----------------- Puzzles UI -----------------
    def _parse_pipe_string(self, value: str):
        out = []
        for ch in list(str(value or ""))[:8]:
            if ch == "1":
                out.append(True)
            elif ch == "0":
                out.append(False)
            else:
                out.append(None)
        while len(out) < 8:
            out.append(None)
        return out

    def _parse_air_entries(self, value: str):
        entries = []
        for part in str(value or "").split(","):
            part = part.strip()
            if not part or "=" not in part:
                continue
            letter, val = part.split("=", 1)
            letter = letter.strip() or "?"
            val = val.strip()
            if val == "1":
                v = True
            elif val == "0":
                v = False
            else:
                v = None
            entries.append({"letter": letter, "valid": v})
        return entries

    def _apply_puzzles_state(self, payload: str):
        state = {
            "pipe_found": False,
            "pipe_red": [None] * 8,
            "pipe_blue": [None] * 8,
            "air_found": False,
            "air_entries": [],
        }
        for part in str(payload or "").split("#"):
            if ":" not in part:
                continue
            key, val = part.split(":", 1)
            key = key.strip().upper()
            val = val.strip()
            if key == "PIPEFOUND":
                state["pipe_found"] = val == "1"
            elif key == "PIPER":
                state["pipe_red"] = self._parse_pipe_string(val)
            elif key == "PIPEB":
                state["pipe_blue"] = self._parse_pipe_string(val)
            elif key == "AIRFOUND":
                state["air_found"] = val == "1"
            elif key == "AIR":
                state["air_entries"] = self._parse_air_entries(val)

        self._puzzle_state = state

        pipe_status = "Found" if state["pipe_found"] else "Not Found"
        air_status = "Found" if state["air_found"] else "Not Found"
        self.puzzle_status_lbl.setText(f"Status: Pipes={pipe_status} | Airlock={air_status}")
        self.pipes_term_lbl.setText(f"Terminal: {pipe_status}")
        self.air_term_lbl.setText(f"Terminal: {air_status}")

        for row in self.pipe_rows:
            values = state["pipe_red"] if row["color"] == "red" else state["pipe_blue"]
            idx = row["idx"] - 1
            v = values[idx] if idx < len(values) else None
            if v is True:
                row["status"].setText("ON")
            elif v is False:
                row["status"].setText("OFF")
            else:
                row["status"].setText("?")

        entries = state.get("air_entries") or []
        for row in self.air_rows:
            idx = row["idx"] - 1
            if idx < len(entries):
                entry = entries[idx]
                letter = entry.get("letter") or "?"
                row["label"].setText(f"Container {letter}")
                valid = entry.get("valid")
                if valid is True:
                    row["status"].setText("VALID")
                elif valid is False:
                    row["status"].setText("INVALID")
                else:
                    row["status"].setText("?")
            else:
                row["label"].setText(f"Container {row['idx']}")
                row["status"].setText("?")

        self._update_puzzle_actions()

    # ----------------- Contract UI -----------------
    def _parse_contract_kv(self, value: str):
        out = {}
        for part in str(value or "").split(","):
            part = part.strip()
            if not part or "=" not in part:
                continue
            key, val = part.split("=", 1)
            out[key.strip()] = val.strip()
        return out

    def _parse_contract_bool(self, value: str):
        val = str(value or "").strip().lower()
        if val in ("1", "true", "on", "yes"):
            return True
        if val in ("0", "false", "off", "no"):
            return False
        return None

    def _parse_contract_int(self, value: str):
        if value is None:
            return None
        try:
            return int(float(str(value).strip()))
        except Exception:
            return None

    def _contract_ready(self):
        state = self._contract_state or {}
        map_name = str(state.get("map") or "")
        map_ok = "lobby" in map_name.strip().lower()
        list_ok = int(state.get("lists") or 0) > 0
        first_ok = bool(state.get("first"))
        pawn_ok = self._state_bool("PAWN") is True
        return map_ok and list_ok and first_ok and pawn_ok

    def _sync_contract_controls_from_state(self):
        state = self._contract_state or {}
        values = state.get("values") or {}
        for name, row in self._contract_controls.items():
            if row.get("kind") == "bool":
                raw = values.get(name)
                val = self._parse_contract_bool(raw)
                if val is None:
                    val = bool(self._contract_defaults.get(name, False))
                widget = row["widget"]
                widget.blockSignals(True)
                widget.setChecked(bool(val))
                widget.blockSignals(False)
                row["status"].setText("ON" if widget.isChecked() else "OFF")
            else:
                raw = values.get(name)
                val = self._parse_contract_int(raw)
                if val is None:
                    val = int(self._contract_defaults.get(name, 0) or 0)
                widget = row["widget"]
                if row.get("dropdown"):
                    widget.blockSignals(True)
                    idx = widget.findData(val)
                    if idx < 0:
                        idx = 0
                    widget.setCurrentIndex(idx)
                    widget.blockSignals(False)
                    row["status"].setText(str(widget.currentData()))
                else:
                    widget.blockSignals(True)
                    widget.setText(str(val))
                    widget.blockSignals(False)
                    row["status"].setText(str(val))

    def _update_contract_actions(self):
        ready = self._contract_ready()
        for row in self._contract_controls.values():
            row["widget"].setEnabled(ready)
            row["status"].setEnabled(ready)
        if self.contract_apply_btn:
            self.contract_apply_btn.setEnabled(ready)

        state = self._contract_state or {}
        map_name = str(state.get("map") or "Unknown")
        list_count = int(state.get("lists") or 0)
        first_ok = bool(state.get("first"))
        hooks = int(state.get("hooks") or 0)
        props = int(state.get("props") or 0)
        age = state.get("age")

        map_ok = "lobby" in map_name.strip().lower()
        pawn_ok = self._state_bool("PAWN") is True
        status_txt = "READY" if ready else "NOT READY"
        if not map_ok:
            status_txt = "WRONG MAP"
        elif not pawn_ok:
            status_txt = "NO PAWN"
        elif not list_count:
            status_txt = "NO LIST"
        elif not first_ok:
            status_txt = "NO CONTRACT"

        self.contract_status_lbl.setText(f"Status: {status_txt}")
        self.contract_map_lbl.setText(f"Map: {map_name or '--'}")
        self.contract_lists_lbl.setText(f"Lists: {list_count}")
        self.contract_hooks_lbl.setText(f"Hooks: {hooks}")
        if age is None or age < 0:
            self.contract_age_lbl.setText("Hook Age: --")
        else:
            self.contract_age_lbl.setText(f"Hook Age: {age:.1f}s")
        self.contract_props_lbl.setText(f"Props: {props}")

    def _apply_contract_state(self, payload: str):
        state = {
            "ready": False,
            "map": "Unknown",
            "lists": 0,
            "first": False,
            "props": 0,
            "hooks": 0,
            "age": None,
            "types": {},
            "values": {},
        }
        for part in str(payload or "").split("#"):
            if ":" not in part:
                continue
            key, val = part.split(":", 1)
            key = key.strip().upper()
            val = val.strip()
            if key == "READY":
                state["ready"] = val == "1"
            elif key == "MAP":
                state["map"] = val or "Unknown"
            elif key == "LISTS":
                try:
                    state["lists"] = int(val)
                except Exception:
                    state["lists"] = 0
            elif key == "FIRST":
                state["first"] = val == "1"
            elif key == "PROPS":
                try:
                    state["props"] = int(val)
                except Exception:
                    state["props"] = 0
            elif key == "HOOKS":
                try:
                    state["hooks"] = int(val)
                except Exception:
                    state["hooks"] = 0
            elif key == "AGE":
                try:
                    state["age"] = float(val)
                except Exception:
                    state["age"] = None
            elif key == "TYPES":
                state["types"] = self._parse_contract_kv(val)
            elif key == "VALUES":
                state["values"] = self._parse_contract_kv(val)

        self._contract_state = state
        self._sync_contract_controls_from_state()
        self._update_contract_actions()

    def _on_contract_toggle(self, name: str):
        row = self._contract_controls.get(name)
        if not row:
            return
        checked = row["widget"].isChecked()
        row["status"].setText("ON" if checked else "OFF")

    def _on_contract_value_changed(self, name: str):
        row = self._contract_controls.get(name)
        if not row:
            return
        widget = row["widget"]
        if row.get("dropdown"):
            row["status"].setText(str(widget.currentData()))
        else:
            text = str(widget.text() or "").strip()
            row["status"].setText(text if text else "--")

    def _open_contracts(self):
        self._send("opencontracts", "")
        self._schedule(0.6, self._refresh_contract_state)

    def _start_contract(self):
        self._send("startcontract", "")
        self._schedule(0.6, self._refresh_contract_state)

    def _apply_contract(self):
        if not self._contract_ready():
            self.show_toast("Contract system not ready. Open the terminal in Lobby.", "WARN", 2600)
            return
        values = []
        for cfg in self._contract_props:
            name = cfg.get("name")
            if not name:
                continue
            if cfg.get("exclude"):
                val = cfg.get("default")
                state_val = (self._contract_state.get("values") or {}).get(name)
                if cfg.get("kind") == "bool":
                    parsed = self._parse_contract_bool(state_val)
                    if parsed is not None:
                        val = parsed
                else:
                    parsed = self._parse_contract_int(state_val)
                    if parsed is not None:
                        val = parsed
            else:
                row = self._contract_controls.get(name)
                if not row:
                    val = cfg.get("default")
                elif row.get("kind") == "bool":
                    val = row["widget"].isChecked()
                else:
                    if row.get("dropdown"):
                        parsed = self._parse_contract_int(row["widget"].currentData())
                    else:
                        parsed = self._parse_contract_int(row["widget"].text())
                    if parsed is None:
                        self.show_toast(f"Invalid number for {cfg.get('label')}.", "ERROR", 2600)
                        return
                    val = parsed
            if isinstance(val, bool):
                values.append("true" if val else "false")
            else:
                try:
                    values.append(str(int(val)))
                except Exception:
                    values.append(str(val))

        arg = " ".join(values)
        self._send("setcontract", arg)
        self._schedule(0.15, self._refresh_contract_state)

    # ----------------- World Registry UI -----------------
    def _apply_world_list(self, payload: str):
        entries = []
        self_pos = None
        for raw in str(payload or "").split(";"):
            raw = raw.strip()
            if not raw:
                continue
            parts = raw.split(",")
            tag = parts[0].strip() if len(parts) > 0 else ""
            code = parts[1].strip() if len(parts) > 1 else ""
            name = parts[2].strip() if len(parts) > 2 else ""
            x = parts[3].strip() if len(parts) > 3 else ""
            y = parts[4].strip() if len(parts) > 4 else ""
            z = parts[5].strip() if len(parts) > 5 else ""
            entry_id = parts[6].strip() if len(parts) > 6 else ""
            status = parts[7].strip() if len(parts) > 7 else ""

            if tag.upper() == "SELF":
                try:
                    self_pos = {
                        "x": float(x),
                        "y": float(y),
                        "z": float(z),
                    }
                except Exception:
                    self_pos = None
                continue

            def _num(v):
                try:
                    return float(v)
                except Exception:
                    return None

            entries.append({
                "tag": tag.upper(),
                "code": code,
                "name": name,
                "x": _num(x),
                "y": _num(y),
                "z": _num(z),
                "id": entry_id,
                "status": status.upper() if status else "UNKNOWN",
            })

        self._world_entries = entries
        self._world_self_pos = self_pos
        self.world_count_lbl.setText(f"Items: {len(entries)}")
        self._refresh_world_list()
        self._refresh_weapon_rows()

    def _state_str(self, key: str, default: str = "--") -> str:
        return str(self._state_data.get(str(key).upper(), default))

    def _state_float(self, key: str):
        try:
            return float(self._state_str(key, ""))
        except Exception:
            return None

    def _state_bool(self, key: str) -> bool | None:
        val = str(self._state_data.get(str(key).upper(), "")).strip()
        if val == "":
            return None
        return val in ("1", "true", "yes", "on")

    def _update_info_bar(self):
        now = time.monotonic()
        map_name = self._state_str("MAP", "Unknown")
        world_ready = self._state_bool("WORLD")
        pawn_ok = self._state_bool("PAWN")
        radar_on = self._state_bool("RADAR")

        tracked = self._state_str("REGTOTAL", "0")

        bridge_ok = (now - self._last_state_read) < 2.0
        events_ok = (now - self._last_registry_update) < 3.0 if self._last_registry_update > 0 else False

        status = "OK"
        if world_ready is False or pawn_ok is False or not bridge_ok:
            status = "WARN"
        if world_ready is False and pawn_ok is False and map_name.lower() in ("unknown", ""):
            if (now - self._last_state_read) > 3.0:
                status = "ERROR"

        self.info_status_lbl.setText(f"STATUS: {status}")
        self.info_map_lbl.setText(f"MAP: {map_name}")
        self.info_world_lbl.setText(f"WORLD: {'READY' if world_ready else 'MENU' if world_ready is False else '--'}")
        self.info_pawn_lbl.setText(f"PAWN: {'OK' if pawn_ok else 'NONE' if pawn_ok is False else '--'}")
        self.info_radar_lbl.setText(f"RADAR: {'ON' if radar_on else 'OFF' if radar_on is False else '--'}")
        self.info_tracked_lbl.setText(f"TRACKED: {tracked}")
        self.info_events_lbl.setText(f"EVENTS: {'OK' if events_ok else 'STALE'}")
        self.info_bridge_lbl.setText(f"BRIDGE: {'OK' if bridge_ok else 'STALE'}")

    def _update_debug_fields(self):
        now = time.monotonic()
        map_name = self._state_str("MAP", "Unknown")
        world_ready = self._state_bool("WORLD")
        pawn_ok = self._state_bool("PAWN")
        radar_on = self._state_bool("RADAR")
        proto = self._state_str("PROTO", "--")

        self.debug_map_lbl.setText(f"Map: {map_name}")
        self.debug_world_lbl.setText(f"World Ready: {str(world_ready).lower() if world_ready is not None else '--'}")
        self.debug_pawn_lbl.setText(f"Pawn: {'valid' if pawn_ok else 'invalid' if pawn_ok is False else '--'}")

        if self._world_self_pos:
            x = self._world_self_pos.get("x", 0.0)
            y = self._world_self_pos.get("y", 0.0)
            z = self._world_self_pos.get("z", 0.0)
            self.debug_pos_lbl.setText(f"Local Pos: {x:.1f} {y:.1f} {z:.1f}")
        else:
            self.debug_pos_lbl.setText("Local Pos: --")

        self.debug_radar_lbl.setText(f"Radar: {'enabled' if radar_on else 'disabled' if radar_on is False else '--'}")
        self.debug_proto_lbl.setText(f"Protocol: {proto}")

        total = self._state_str("REGTOTAL", "0")
        mon = self._state_str("MON", "0")
        key = self._state_str("KEY", "0")
        disk = self._state_str("DISK", "0")
        black = self._state_str("BLACK", "0")
        weapon = self._state_str("WEAPON", "0")
        money = self._state_str("MONEY", "0")

        self.debug_reg_total_lbl.setText(f"Total Tracked: {total}")
        self.debug_reg_counts_lbl.setText(
            f"Monsters: {mon} | Keycards: {key} | Disks: {disk} | Blackbox: {black} | Weapons: {weapon} | Money: {money}"
        )

        state_write_clock = self._state_float("STATEWRITE")
        last_emit = self._state_float("EMIT")
        last_prune = self._state_float("PRUNE")
        emit_txt = "--"
        prune_txt = "--"
        if state_write_clock and last_emit and state_write_clock >= last_emit:
            emit_age = state_write_clock - last_emit
            emit_txt = f"{emit_age:.1f}s ago"
        if state_write_clock and last_prune and state_write_clock >= last_prune:
            prune_age = state_write_clock - last_prune
            prune_txt = f"{prune_age:.1f}s ago"

        self.debug_reg_update_lbl.setText(f"Last Registry Update: {emit_txt}")
        self.debug_reg_prune_lbl.setText(f"Last Prune: {prune_txt}")

        bridge_ok = (now - self._last_state_read) < 2.0
        self.debug_bridge_lbl.setText(f"Bridge: {'OK' if bridge_ok else 'STALE'}")

        write_txt = "--"
        if self._last_state_read > 0:
            write_age = now - self._last_state_read
            write_txt = f"{write_age:.1f}s ago"
        read_txt = f"{(now - self._last_state_read):.1f}s ago" if self._last_state_read > 0 else "--"
        self.debug_state_write_lbl.setText(f"State Write: {write_txt}")
        self.debug_state_read_lbl.setText(f"State Read: {read_txt}")

        cmd_txt = "--"
        if self._last_cmd_sent:
            cmd_age = now - self._last_cmd_time if self._last_cmd_time else 0.0
            ack_age = now - self._last_ack_time if self._last_ack_time else None
            if ack_age is not None and self._last_ack_time > 0:
                cmd_txt = f"{self._last_cmd_sent} | ack {ack_age:.1f}s"
            else:
                cmd_txt = f"{self._last_cmd_sent} | sent {cmd_age:.1f}s"
        self.debug_cmd_lbl.setText(f"Last Cmd/Ack: {cmd_txt}")
        self.debug_perf_lbl.setText("Perf: UI tick ~4Hz")
    def _world_category_label(self, tag: str) -> str:
        tag = str(tag or "").upper()
        if tag == "MONSTER":
            return "Monster"
        if tag == "MONEY":
            return "Money"
        if tag == "OBJECTIVE":
            return "Keycard"
        if tag == "DATA":
            return "Data Disk"
        if tag == "BLACKBOX":
            return "Blackbox"
        if tag == "WEAPON":
            return "Weapon"
        return tag.title() if tag else "Unknown"

    def _world_category_order(self, tag: str) -> int:
        order = {
            "MONSTER": 1,
            "MONEY": 2,
            "OBJECTIVE": 3,
            "DATA": 4,
            "BLACKBOX": 5,
            "WEAPON": 6,
        }
        return order.get(str(tag or "").upper(), 99)

    def _world_distance(self, entry) -> float | None:
        if not entry or not self._world_self_pos:
            return None
        try:
            if entry.get("x") is None or entry.get("y") is None or entry.get("z") is None:
                return None
            dx = entry.get("x") - self._world_self_pos.get("x", 0)
            dy = entry.get("y") - self._world_self_pos.get("y", 0)
            dz = entry.get("z") - self._world_self_pos.get("z", 0)
            return (dx * dx + dy * dy + dz * dz) ** 0.5
        except Exception:
            return None

    def _world_filter_tag(self) -> str:
        if not self.world_filter_combo:
            return "ALL"
        return str(self.world_filter_combo.currentData() or "ALL").upper()

    def _world_sort_mode(self) -> str:
        if not self.world_sort_combo:
            return "CATEGORY"
        return str(self.world_sort_combo.currentData() or "CATEGORY").upper()

    def _refresh_world_list(self, *_args):
        if not self.world_list:
            return
        selected_id = None
        current_item = self.world_list.currentItem()
        if current_item:
            selected_id = current_item.data(Qt.UserRole)

        tag_filter = self._world_filter_tag()
        entries = []
        for e in self._world_entries:
            if tag_filter != "ALL" and str(e.get("tag") or "").upper() != tag_filter:
                continue
            entries.append(e)

        sort_mode = self._world_sort_mode()
        if sort_mode == "DISTANCE":
            entries.sort(key=lambda e: (self._world_distance(e) is None,
                                        self._world_distance(e) or 0,
                                        str(e.get("name") or "").lower()))
        elif sort_mode == "NAME":
            entries.sort(key=lambda e: str(e.get("name") or "").lower())
        else:
            entries.sort(key=lambda e: (self._world_category_order(e.get("tag")),
                                        str(e.get("name") or "").lower()))

        self.world_list.blockSignals(True)
        self.world_list.clear()
        if not entries:
            item = QListWidgetItem("No world items registered.")
            item.setFlags(item.flags() & ~Qt.ItemIsSelectable & ~Qt.ItemIsEnabled)
            self.world_list.addItem(item)
        else:
            for e in entries:
                tag = e.get("tag") or "OBJECT"
                code = e.get("code") or ""
                name = e.get("name") or "Unknown"
                status = e.get("status") or "Unknown"
                dist = self._world_distance(e)
                if str(status).lower() == "collected":
                    dist_str = "N/A"
                else:
                    dist_str = f"{dist:.1f}m" if dist is not None else "N/A"
                label = f"{name} | {self._world_category_label(tag)} | {dist_str} | {status}"
                item = QListWidgetItem(label)
                item.setData(Qt.UserRole, e.get("id") or "")
                self.world_list.addItem(item)

        if selected_id:
            for i in range(self.world_list.count()):
                it = self.world_list.item(i)
                if it and it.data(Qt.UserRole) == selected_id:
                    self.world_list.setCurrentItem(it)
                    break
        self.world_list.blockSignals(False)
        self._update_world_actions()

    def _get_selected_world_entry(self):
        item = self.world_list.currentItem() if self.world_list else None
        if not item:
            return None
        sel_id = item.data(Qt.UserRole)
        if not sel_id:
            return None
        for e in self._world_entries:
            if e.get("id") == sel_id:
                return e
        return None

    def _world_ready(self) -> bool:
        return self._world_self_pos is not None

    def _update_world_actions(self, *_args):
        entry = self._get_selected_world_entry()
        ready = self._world_ready()
        valid = bool(entry)
        status = str(entry.get("status") or "").lower() if entry else ""
        can_use = ready and valid and status != "collected"
        self.world_tp_btn.setEnabled(can_use)
        self.world_bring_btn.setEnabled(can_use)

    def _world_teleport(self):
        entry = self._get_selected_world_entry()
        if not entry:
            return
        if not self._world_ready():
            return
        if str(entry.get("tag") or "").upper() == "MONSTER":
            if QMessageBox.question(self, "Confirm", "Teleport to selected Monster?") != QMessageBox.Yes:
                return
        obj_id = entry.get("id") or ""
        if not obj_id:
            return
        self._send("world_tp", str(obj_id))

    def _world_bring(self):
        entry = self._get_selected_world_entry()
        if not entry:
            return
        if not self._world_ready():
            return
        if str(entry.get("tag") or "").upper() == "MONSTER":
            if QMessageBox.question(self, "Confirm", "Bring selected Monster to you?") != QMessageBox.Yes:
                return
        obj_id = entry.get("id") or ""
        if not obj_id:
            return
        self._send("world_bring", str(obj_id))

    def _update_tp_actions(self):
        pawn_ok = bool(self._tp_state.get("pawn"))
        map_ok = pawn_ok and (self._tp_state.get("map") or "Unknown") != "Unknown"
        return_ok = pawn_ok and bool(self._tp_state.get("return"))
        others = int(self._tp_state.get("others") or 0)

        self.tp_set_return_btn.setEnabled(pawn_ok)
        self.tp_return_btn.setEnabled(return_ok)

        has_tps = self.tp_map_combo.count() > 0
        self.tp_map_combo.setEnabled(map_ok and has_tps)
        self.tp_map_btn.setEnabled(map_ok and has_tps and bool(self.tp_map_combo.currentData()))

        near = self._tp_state.get("near") or {}
        current_type = str(self.tp_near_combo.currentData() or "").upper()
        near_ok = pawn_ok and near.get(current_type, False)
        self.tp_near_tp_btn.setEnabled(near_ok)
        self.tp_near_bring_btn.setEnabled(near_ok)

        self.tp_bring_all_btn.setEnabled(pawn_ok and others > 0)
        has_all_tps = self.tp_all_combo.count() > 0
        self.tp_all_combo.setEnabled(map_ok and has_all_tps)
        self.tp_all_btn.setEnabled(map_ok and has_all_tps and others > 0)

        target_ok = bool(self._tp_target_name())
        dest_ok = bool(self._tp_dest_spec())
        self.tp_target_combo.setEnabled(len(self._player_names) > 0)
        self.tp_player_btn.setEnabled(pawn_ok and target_ok and dest_ok)

    def _update_puzzle_actions(self):
        pipe_found = bool(self._puzzle_state.get("pipe_found"))
        for row in self.pipe_rows:
            row["on"].setEnabled(pipe_found)
            row["off"].setEnabled(pipe_found)
            row["tp"].setEnabled(pipe_found)
        self.pipes_enable_all_btn.setEnabled(pipe_found)
        self.pipes_disable_all_btn.setEnabled(pipe_found)

        air_found = bool(self._puzzle_state.get("air_found"))
        entries = self._puzzle_state.get("air_entries") or []
        for row in self.air_rows:
            idx = row["idx"] - 1
            enabled = air_found and idx < len(entries)
            row["on"].setEnabled(enabled)
            row["off"].setEnabled(enabled)
        self.air_enable_all_btn.setEnabled(air_found)
        self.air_disable_all_btn.setEnabled(air_found)

    def _tp_set_return(self):
        self._send("tpsetreturn", "")
        self._schedule(0.15, self._refresh_tp_state)

    def _tp_return(self):
        self._send("tpreturn", "")
        self._schedule(0.15, self._refresh_tp_state)

    def _tp_map_teleport(self, key: str = ""):
        if not key:
            key = self.tp_map_combo.currentData()
        if not key:
            return
        self._send("tpmap", str(key))
        self._schedule(0.15, self._refresh_tp_state)

    def _on_tp_target_changed(self):
        self._refresh_tp_destinations()
        self._update_tp_actions()

    def _tp_target_name(self) -> str:
        if not self.tp_target_combo or not self.tp_target_combo.isEnabled():
            return ""
        data = self.tp_target_combo.currentData()
        if data is None or str(data).strip() == "":
            return ""
        return str(data)

    def _tp_dest_spec(self) -> str:
        if not self.tp_dest_combo or not self.tp_dest_combo.isEnabled():
            return ""
        data = self.tp_dest_combo.currentData()
        if data is None or str(data).strip() == "":
            return ""
        return str(data)

    def _encode_arg(self, value: str) -> str:
        s = str(value or "")
        s = s.replace("%", "%25")
        s = s.replace(" ", "%20")
        return s

    def _tp_player_to(self):
        target = self._tp_target_name()
        dest = self._tp_dest_spec()
        if not target or not dest:
            return
        arg = f"{self._encode_arg(target)} {self._encode_arg(dest)}"
        self._send("tpplayerto", arg)
        self._schedule(0.15, self._refresh_tp_state)

    def _pipe_set(self, color: str, idx: int, enable: bool):
        color = str(color or "").lower()
        if color not in ("red", "blue"):
            return
        state = "on" if enable else "off"
        self._send("pipeset", f"{color} {int(idx)} {state}")
        self._schedule(0.15, self._refresh_puzzles)

    def _pipe_tp(self, color: str, idx: int):
        color = str(color or "").lower()
        if color not in ("red", "blue"):
            return
        self._send("pipegoto", f"{color} {int(idx)}")

    def _pipe_all(self, enable: bool):
        state = "on" if enable else "off"
        self._send("pipeall", state)
        self._schedule(0.15, self._refresh_puzzles)

    def _airlock_set(self, idx: int, enable: bool):
        state = "on" if enable else "off"
        self._send("labairlockset", f"{int(idx)} {state}")
        self._schedule(0.15, self._refresh_puzzles)

    def _airlock_all(self, enable: bool):
        state = "on" if enable else "off"
        self._send("labairlockset", f"all {state}")
        self._schedule(0.15, self._refresh_puzzles)

    def _tp_nearest(self):
        obj_type = str(self.tp_near_combo.currentData() or "").upper()
        if obj_type == "MONSTER":
            if QMessageBox.question(self, "Confirm", "Teleport to nearest Monster?") != QMessageBox.Yes:
                return
        self._send("tpnearest", obj_type)
        self._schedule(0.15, self._refresh_tp_state)

    def _tp_bring_nearest(self):
        obj_type = str(self.tp_near_combo.currentData() or "").upper()
        if obj_type == "MONSTER":
            if QMessageBox.question(self, "Confirm", "Bring nearest Monster to you?") != QMessageBox.Yes:
                return
        self._send("bringnearest", obj_type)
        self._schedule(0.15, self._refresh_tp_state)

    def _tp_bring_all(self):
        self._send("bringallplayers", "")
        self._schedule(0.15, self._refresh_tp_state)

    def _tp_all_players(self):
        key = self.tp_all_combo.currentData()
        if not key:
            return
        self._send("tpallmap", str(key))
        self._schedule(0.15, self._refresh_tp_state)

    def _run_invoked(self, fn):
        try:
            fn()
        except Exception:
            pass

    def _schedule(self, delay_s: float, fn):
        try:
            delay = max(0.0, float(delay_s))
        except Exception:
            delay = 0.0
        if delay <= 0:
            self._invoke.emit(fn)
            return
        try:
            t = threading.Timer(delay, lambda: self._invoke.emit(fn))
            t.daemon = True
            t.start()
        except Exception:
            self._invoke.emit(fn)


class OverlayApp:
    def __init__(self):
        self.app = QApplication([])
        self.app.setQuitOnLastWindowClosed(False)
        self.bridge = CommandBridge(CMD_PATH)
        self.panel = ActionPanel(self.bridge.send)
        self.toast_mgr = ToastManager()
        self.panel.set_toast_manager(self.toast_mgr)
        self.panel.set_panel_request_cb(self._on_panel_request)

        self._panel_requested = False
        self._game_running = False
        self._game_focused = False
        self._game_pids = []
        self.shutting_down = False
        det = _detect_game_process()
        if det is not None:
            self._game_pid, self._game_exe = det
        else:
            self._game_pid, self._game_exe = (None, None)

        self.panel.hide()

        self._game_timer = QTimer(self.panel)
        self._game_timer.setInterval(2500)
        self._game_timer.timeout.connect(self._update_game_running)
        self._game_timer.start()

        self._focus_timer = QTimer(self.panel)
        self._focus_timer.setInterval(200)
        self._focus_timer.timeout.connect(self._update_game_focus)
        self._focus_timer.start()

        self.process_timer = QTimer(self.panel)
        self.process_timer.timeout.connect(self.check_game_running)
        self.process_timer.start(PROCESS_CHECK_INTERVAL_MS)

        self._update_game_running()
        self._update_game_focus()
        if self._game_pid is None:
            self.toast_mgr.show(
                "Game not found, make sure game is open before running!",
                "ERROR",
                3000,
            )
            QTimer.singleShot(3000, self.app.quit)

    def _on_panel_request(self, open_value: bool):
        self._panel_requested = open_value and True or False
        self._apply_visibility()

    def _update_game_running(self):
        matches = _find_windows_by_title(GAME_WINDOW_TITLE)
        running = len(matches) > 0
        if self._game_running and not running:
            self._panel_requested = False
        self._game_running = running
        pids = []
        for hwnd, _title in matches:
            pid = _get_pid_from_hwnd(hwnd)
            if pid and pid not in pids:
                pids.append(pid)
        self._game_pids = pids
        self._apply_visibility()

    def _update_game_focus(self):
        focused = False
        if self._game_running:
            title, visible, zoomed, pid = _get_foreground_title_zoomed()
            title_ok = GAME_WINDOW_TITLE.lower() in str(title or "").lower()
            focused = title_ok and visible and zoomed
        if focused != self._game_focused:
            self._game_focused = focused
            self._apply_visibility()

    def check_game_running(self):
        if self.shutting_down:
            return

        pid = getattr(self, "_game_pid", None)
        exe = getattr(self, "_game_exe", None)
        if pid is None:
            det = _detect_game_process()
            if det is not None:
                pid, exe = det
                self._game_pid = pid
                self._game_exe = exe
            else:
                self.shutting_down = True
                app = QApplication.instance()
                if app:
                    app.quit()
                if self.panel:
                    self.panel.close()
                return

        if not _pid_is_alive(int(pid)):
            self.shutting_down = True
            app = QApplication.instance()
            if app:
                app.quit()
            if self.panel:
                self.panel.close()
            return

        if exe:
            path = _query_process_image_name(int(pid))
            if path:
                base = os.path.basename(path).lower()
                want_exact = {n.lower() for n in GAME_PROCESS_NAMES}
                if not (base == exe or base in want_exact or base.startswith("speciesunknown")):
                    self.shutting_down = True
                    app = QApplication.instance()
                    if app:
                        app.quit()
                    if self.panel:
                        self.panel.close()

    def _apply_visibility(self):
        # Show whenever panel is requested and game is running.
        # Focus/maximized gating was too strict and hid the panel.
        should_show = self._panel_requested and self._game_running
        if should_show:
            if not self.panel.isVisible():
                self.panel.show()
                self.panel.raise_()
        else:
            if self.panel.isVisible():
                self.panel.hide()

    def run(self):
        self.app.exec()


if __name__ == "__main__":
    OverlayApp().run()
