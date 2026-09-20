"""HoneyChain telemetry -> 28-feature One-Class SVM inference.

The simulator and physical IoT ingestion use this same service. The model is
an anomaly detector only; it does not diagnose a biological disease.
"""
from __future__ import annotations

import math
import os
from collections import defaultdict, deque
from pathlib import Path
from typing import Any

import joblib
import numpy as np

FEATURES = [
    "temperature", "humidity", "hive_power", "audio_density",
    "audio_density_ratio", "density_variation", "acoustic_mean",
    "acoustic_std", "observation_count",
    "temperature_delta_1", "temperature_delta_4",
    "temperature_rolling_mean_4", "temperature_rolling_std_4",
    "humidity_delta_1", "humidity_delta_4",
    "humidity_rolling_mean_4", "humidity_rolling_std_4",
    "audio_density_delta_1", "audio_density_delta_4",
    "audio_density_rolling_mean_4", "audio_density_rolling_std_4",
    "acoustic_mean_delta_1", "acoustic_mean_delta_4",
    "acoustic_std_delta_1", "acoustic_std_delta_4",
    "hive_power_delta", "hive_power_rolling_mean",
    "hive_power_rolling_std",
]

MAX_HISTORY = 64
WARMUP = 8
STRONG_Z = 3.0
MODERATE_Z = 2.0


def _repo_model_dir() -> Path:
    override = os.getenv("HONEYCHAIN_ML_MODEL_DIR", "").strip()
    if override:
        return Path(override)
    return Path(__file__).resolve().parents[3] / "ml" / "models_honeychain_event"


class HoneyChainML:
    """Shared stateful inference engine for simulator + real telemetry."""

    def __init__(self, model_dir: Path | None = None) -> None:
        self.model_dir = model_dir or _repo_model_dir()
        self.model = None
        self.scaler = None
        self.threshold: float | None = None
        self.load_error: str | None = None
        self.history: dict[str, deque[dict[str, float]]] = defaultdict(
            lambda: deque(maxlen=MAX_HISTORY)
        )
        self.status_history: dict[str, deque[str]] = defaultdict(
            lambda: deque(maxlen=64)
        )
        self.latest: dict[str, dict[str, Any]] = {}

    def _ensure_loaded(self) -> bool:
        if self.model is not None:
            return True
        try:
            model_file = self.model_dir / "one_class_svm.joblib"
            scaler_file = self.model_dir / "scaler.joblib"
            threshold_file = self.model_dir / "production_threshold.joblib"
            missing = [str(p) for p in (model_file, scaler_file, threshold_file) if not p.exists()]
            if missing:
                raise FileNotFoundError("Missing ML artifact(s): " + ", ".join(missing))
            self.model = joblib.load(model_file)
            self.scaler = joblib.load(scaler_file)
            threshold_data = joblib.load(threshold_file)
            self.threshold = float(threshold_data["threshold"])
            if len(FEATURES) != int(getattr(self.model, "n_features_in_", len(FEATURES))):
                raise ValueError("Model feature count does not match HoneyChain 28-feature contract")
            return True
        except Exception as exc:
            self.load_error = str(exc)
            return False

    @property
    def available(self) -> bool:
        return self._ensure_loaded()

    def baseline(self) -> dict[str, float]:
        """Use the trained scaler medians for simulator initialization."""
        if not self._ensure_loaded():
            return {
                "temperature": 30.0,
                "humidity": 60.0,
                "hive_power": 20.0,
                "audio_density": 50.0,
                "acoustic_mean": 220.0,
            }
        center = np.asarray(getattr(self.scaler, "center_", np.zeros(28)), dtype=float)
        return {
            "temperature": float(center[0]),
            "humidity": float(center[1]),
            "hive_power": float(center[2]),
            "audio_density": float(center[3]),
            "acoustic_mean": float(center[6]),
        }

    @staticmethod
    def _clean_number(value: Any) -> float | None:
        try:
            x = float(value)
        except (TypeError, ValueError):
            return None
        return x if math.isfinite(x) else None

    def _raw(self, payload: dict[str, Any]) -> dict[str, float] | None:
        values = {
            "temperature": payload.get("temperature_c"),
            "humidity": payload.get("humidity_percent"),
            "hive_power": payload.get("hive_weight_kg"),
            "audio_density": payload.get("bee_activity"),
            "acoustic_mean": payload.get("acoustic_frequency_hz"),
        }
        cleaned = {k: self._clean_number(v) for k, v in values.items()}
        if any(v is None for v in cleaned.values()):
            return None
        if not (-20 <= cleaned["temperature"] <= 80):
            return None
        if not (0 <= cleaned["humidity"] <= 100):
            return None
        if not (0 <= cleaned["hive_power"] <= 500):
            return None
        if not (0 <= cleaned["audio_density"] <= 500):
            return None
        if not (0 <= cleaned["acoustic_mean"] <= 2000):
            return None
        return {k: float(v) for k, v in cleaned.items()}

    @staticmethod
    def _delta(values: list[float], lag: int) -> float:
        if len(values) <= lag:
            return 0.0
        return values[-1] - values[-1 - lag]

    @staticmethod
    def _mean(values: list[float]) -> float:
        return float(np.mean(values)) if values else 0.0

    @staticmethod
    def _std(values: list[float]) -> float:
        return float(np.std(values, ddof=1)) if len(values) >= 2 else 0.0

    def _features(self, history: list[dict[str, float]]) -> np.ndarray:
        def vals(key: str) -> list[float]:
            return [r[key] for r in history]

        t = vals("temperature")
        h = vals("humidity")
        p = vals("hive_power")
        a = vals("audio_density")
        ac = vals("acoustic_mean")

        a_roll = a[-4:]
        ac_roll = ac[-4:]
        acoustic_std_series = [
            self._std(ac[:i]) for i in range(1, len(ac) + 1)
        ]
        acoustic_std_1 = self._delta(acoustic_std_series, 1)
        acoustic_std_4 = self._delta(acoustic_std_series, 4)

        audio_ratio = 0.0
        if len(a) >= 2 and abs(a[-2]) > 1e-9:
            audio_ratio = (a[-1] - a[-2]) / abs(a[-2])

        row = [
            t[-1], h[-1], p[-1], a[-1], audio_ratio, self._std(a_roll),
            ac[-1], self._std(ac_roll), min(len(history), 32),
            self._delta(t, 1), self._delta(t, 4), self._mean(t[-4:]), self._std(t[-4:]),
            self._delta(h, 1), self._delta(h, 4), self._mean(h[-4:]), self._std(h[-4:]),
            self._delta(a, 1), self._delta(a, 4), self._mean(a[-4:]), self._std(a[-4:]),
            self._delta(ac, 1), self._delta(ac, 4), acoustic_std_1, acoustic_std_4,
            self._delta(p, 1), self._mean(p[-4:]), self._std(p[-4:]),
        ]
        return np.asarray(row, dtype=float).reshape(1, -1)

    def _evidence(
        self,
        current: dict[str, float],
        history: list[dict[str, float]],
    ) -> tuple[list[str], dict[str, float], int]:
        if len(history) < WARMUP:
            return [], {}, 0
        evidence: list[str] = []
        deviations: dict[str, float] = {}
        for key, label in (
            ("temperature", "temperature"),
            ("humidity", "humidity"),
            ("hive_power", "hive_power"),
            ("audio_density", "bee_activity"),
            ("acoustic_mean", "acoustic_mean"),
        ):
            base = np.asarray([r[key] for r in history[:-1]], dtype=float)
            median = float(np.median(base))
            mad = float(np.median(np.abs(base - median)))
            scale = max(
                1.4826 * mad,
                float(np.std(base, ddof=1)) if len(base) > 1 else 0.0,
                1e-6,
            )
            z = abs(current[key] - median) / scale
            deviations[label] = round(z, 2)
            if z >= STRONG_Z:
                evidence.append(label)
        moderate = sum(1 for z in deviations.values() if z >= MODERATE_Z)
        return evidence, deviations, moderate

    def ingest(
        self,
        device_id: str,
        payload: dict[str, Any],
        timestamp: str | None = None,
    ) -> dict[str, Any]:
        raw = self._raw(payload)
        if raw is None:
            result = {
                "status": "SENSOR_FAULT",
                "ml_available": self.available,
                "ml_anomaly": False,
                "score": None,
                "threshold": self.threshold,
                "evidence": ["invalid_or_missing_sensor_value"],
                "deviations": {},
                "reason": "Sensor data is missing, non-finite, or outside the valid sensor range.",
                "recommendation": "Check the affected sensor and wiring before interpreting hive behavior.",
                "persistence_observations": 0,
                "warmup": False,
            }
            self.latest[device_id] = result
            return result

        history_deque = self.history[device_id]
        history_deque.append(raw)
        history = list(history_deque)

        evidence, deviations, moderate = self._evidence(raw, history)
        score: float | None = None
        ml_anomaly = False
        warmup = len(history) < WARMUP

        if self._ensure_loaded() and not warmup:
            x = self._features(history)
            if not np.isfinite(x).all():
                raise ValueError("Non-finite value reached HoneyChain ML inference")
            scaled = self.scaler.transform(x)
            score = float(self.model.decision_function(scaled)[0])
            ml_anomaly = score < float(self.threshold)

        previous = self.status_history[device_id]
        persistent = sum(
            1 for s in list(previous)[-6:]
            if s in ("MONITOR", "CHECK_HIVE", "HIGH_ATTENTION")
        )

        if warmup:
            status = "NORMAL"
            reason = f"ML warm-up: {len(history)}/{WARMUP} readings collected."
            recommendation = "Continue telemetry collection; no anomaly conclusion yet."
        elif ml_anomaly and evidence and (persistent >= 2 or moderate >= 2):
            status = "HIGH_ATTENTION"
            reason = "ML anomaly coincides with unusual physical sensor behavior."
            recommendation = "Inspect hive conditions and verify the affected sensor readings."
        elif (len(evidence) >= 2 and persistent >= 2) or (moderate >= 3 and persistent >= 2):
            status = "HIGH_ATTENTION"
            reason = "Multiple sensor changes persisted across consecutive readings."
            recommendation = "Inspect the hive and verify the sensor readings."
        elif (len(evidence) >= 2 or moderate >= 2) and persistent >= 1:
            status = "CHECK_HIVE"
            reason = "Multiple unusual sensor readings are persisting."
            recommendation = "Check hive ventilation, colony activity, and visible signs of stress."
        elif ml_anomaly or evidence or moderate >= 1:
            status = "MONITOR"
            reason = "Telemetry is unusual relative to the recent hive baseline."
            recommendation = "Continue monitoring and inspect if the change persists."
        else:
            status = "NORMAL"
            reason = "Telemetry is within the recent hive baseline."
            recommendation = "No immediate action; continue monitoring."

        self.status_history[device_id].append(status)
        result = {
            "status": status,
            "ml_available": self.model is not None,
            "ml_anomaly": ml_anomaly,
            "score": score,
            "threshold": self.threshold,
            "evidence": evidence,
            "deviations": deviations,
            "reason": reason,
            "recommendation": recommendation,
            "persistence_observations": persistent + (1 if status != "NORMAL" else 0),
            "warmup": warmup,
            "timestamp": timestamp,
        }
        self.latest[device_id] = result
        return result

    def latest_for(self, device_id: str) -> dict[str, Any]:
        return dict(self.latest.get(device_id, {
            "status": "NORMAL",
            "ml_available": self.available,
            "ml_anomaly": False,
            "score": None,
            "threshold": self.threshold,
            "evidence": [],
            "deviations": {},
            "reason": "No ML inference has been run for this device yet.",
            "recommendation": "Start the simulator.",
            "persistence_observations": 0,
            "warmup": True,
        }))

    def reset(self, device_id: str) -> None:
        self.history.pop(device_id, None)
        self.status_history.pop(device_id, None)
        self.latest.pop(device_id, None)
