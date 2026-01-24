try:
    import keyboard  # global hotkey (may require admin privileges)
except Exception:
    keyboard = None
from pathlib import Path

import time
import threading

from PySide6.QtWidgets import (
    QApplication, QWidget,
    QLabel, QTabWidget,
    QVBoxLayout, QHBoxLayout,
    QFrame, QScrollArea, QLineEdit,
    QPushButton, QCheckBox, QComboBox,
    QSlider, QMessageBox,
)
from PySide6.QtCore import Qt, QFileSystemWatcher, Signal


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

class ActionPanel(QWidget):
    _invoke = Signal(object)

    def __init__(self, send_cmd_cb):
        super().__init__()
        self._send_cmd = send_cmd_cb
        self.setObjectName("actionPanel")
        self.setWindowTitle("Blackbox Console")
        self.setFixedSize(640, 820)
        self.setWindowFlags(
            Qt.WindowStaysOnTopHint
            | Qt.FramelessWindowHint
            | Qt.Tool
        )
        self.setAttribute(Qt.WA_TranslucentBackground)

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

        status = QFrame()
        status.setObjectName("panelStatus")
        status_l = QHBoxLayout(status)
        status_l.setContentsMargins(8, 6, 8, 6)
        status_l.setSpacing(8)

        self.link_lbl = QLabel("LINK: OK")
        self.link_lbl.setObjectName("panelChip")
        status_l.addWidget(self.link_lbl)

        self.input_lbl = QLabel("INPUT: ENABLED")
        self.input_lbl.setObjectName("panelChip")
        status_l.addWidget(self.input_lbl)

        status_l.addStretch(1)
        body_l.addWidget(status)

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
        puzzles_layout = _make_tab("Puzzles")
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

                col_l.addLayout(row)
                self.pipe_rows.append({
                    "color": color_key,
                    "idx": idx,
                    "label": lbl,
                    "status": status,
                    "on": on_btn,
                    "off": off_btn,
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

        # ================== DEBUG ==================
        debug_box = QFrame()
        debug_box.setObjectName("groupBox")
        debug_l = QVBoxLayout(debug_box)
        debug_l.setContentsMargins(12, 10, 12, 10)
        debug_l.setSpacing(8)

        debug_hdr = QLabel("DEBUG")
        debug_hdr.setObjectName("groupHeader")
        debug_l.addWidget(debug_hdr)

        self.hook_prints_cb = QCheckBox("Hook Prints")
        self.hook_prints_cb.setObjectName("panelCheck")
        debug_l.addWidget(self.hook_prints_cb)

        debug_hint = QLabel("Prints a log line when any hook fires.")
        debug_hint.setObjectName("panelHint")
        debug_hint.setWordWrap(True)
        debug_l.addWidget(debug_hint)

        debug_layout.addWidget(debug_box)
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
        self.air_enable_all_btn.clicked.connect(lambda: self._airlock_all(True))
        self.air_disable_all_btn.clicked.connect(lambda: self._airlock_all(False))
        for row in self.air_rows:
            row["on"].clicked.connect(
                lambda _=False, i=row["idx"]: self._airlock_set(i, True)
            )
            row["off"].clicked.connect(
                lambda _=False, i=row["idx"]: self._airlock_set(i, False)
            )

        self.hook_prints_cb.stateChanged.connect(self._toggle_hook_prints)

        self._invoke.connect(self._run_invoked)

        # Ack polling (bridge responses)
        self._ack_path = ACK_PATH
        self._ack_handlers = {}
        self._ack_watcher = QFileSystemWatcher(self)
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
        self._player_names = []
        self._self_name = None
        self._refresh_queue = []

        self._update_target_actions()
        self._update_tp_actions()
        self._update_puzzle_actions()

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

        # Initial sync
        self._schedule(0.15, self._refresh_players)
        self._schedule(0.20, self._refresh_tp_state)
        self._schedule(0.25, self._refresh_puzzles)

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
            return self._send_cmd(name, arg)
        except Exception:
            return None

    def showEvent(self, event):
        super().showEvent(event)
        self._schedule(0.05, self._refresh_players)
        self._schedule(0.08, self._refresh_tp_state)
        self._schedule(0.11, self._refresh_puzzles)

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
        state = "on" if self.hook_prints_cb.isChecked() else "off"
        self._send("hookprints", state)

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
        if started:
            self._refresh_queue.pop(0)

    def _queue_ack(self, cmd_id, handler, timeout_s: float):
        try:
            ack_id = str(cmd_id)
            deadline = time.time() + float(timeout_s)
            self._ack_handlers[ack_id] = (deadline, handler)
        except Exception:
            pass

    def _cleanup_acks(self):
        now = time.time()
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

    def _process_notice_line(self, line: str):
        if not line:
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

    def _apply_player_list(self, payload: str):
        entries = [e for e in str(payload or "").split(";") if e]
        current = self.target_combo.currentData()
        tp_current = self.tp_target_combo.currentData() if self.tp_target_combo else None
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
        self.bridge = CommandBridge(CMD_PATH)
        self.panel = ActionPanel(self.bridge.send)
        self.panel.show()

        # F1 toggle: global hotkey if available, focused shortcut as fallback.
        if keyboard is not None:
            try:
                keyboard.add_hotkey("f1", self.toggle_panel)
            except Exception:
                pass

    def toggle_panel(self):
        if self.panel.isVisible():
            self.panel.hide()
        else:
            self.panel.show()
            self.panel.raise_()
            self.panel.activateWindow()

    def run(self):
        self.app.exec()


if __name__ == "__main__":
    OverlayApp().run()
