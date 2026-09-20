from pathlib import Path

import numpy as np
import pytest

from app.services.honeychain_ml_service import HoneyChainML, FEATURES


def _history(n=8):
    return [
        {
            "temperature": 30.0 + i * 0.02,
            "humidity": 60.0 + i * 0.05,
            "hive_power": 20.0 + i * 0.01,
            "audio_density": 50.0 + i * 0.10,
            "acoustic_mean": 220.0 + i * 0.20,
        }
        for i in range(n)
    ]


def test_feature_contract_has_28_features():
    engine = HoneyChainML(Path("."))
    x = engine._features(_history())
    assert x.shape == (1, 28)
    assert len(FEATURES) == 28
    assert np.isfinite(x).all()


def test_sensor_fault_never_reaches_model():
    engine = HoneyChainML(Path("."))
    result = engine.ingest(
        "TEST-SENSOR",
        {
            "temperature_c": None,
            "humidity_percent": 60,
            "hive_weight_kg": 20,
            "bee_activity": 50,
            "acoustic_frequency_hz": 220,
        },
    )
    assert result["status"] == "SENSOR_FAULT"
    assert result["ml_anomaly"] is False


@pytest.mark.skipif(
    not (
        Path("../ml/models_honeychain_event/one_class_svm.joblib").exists()
        and Path("../ml/models_honeychain_event/scaler.joblib").exists()
        and Path("../ml/models_honeychain_event/production_threshold.joblib").exists()
    ),
    reason="Local HoneyChain ML artifacts are not present in the repository checkout",
)
def test_real_model_inference_uses_production_threshold():
    model_dir = Path("../ml/models_honeychain_event")
    engine = HoneyChainML(model_dir)
    payload = {
        "temperature_c": 30.0,
        "humidity_percent": 60.0,
        "hive_weight_kg": 20.0,
        "bee_activity": 50.0,
        "acoustic_frequency_hz": 220.0,
    }
    for _ in range(8):
        result = engine.ingest("REAL-MODEL", payload)
    result = engine.latest_for("REAL-MODEL")
    assert engine.threshold == pytest.approx(-0.16589167633131208)
    assert result["score"] is not None
