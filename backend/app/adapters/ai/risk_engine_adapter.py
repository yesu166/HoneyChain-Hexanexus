from __future__ import annotations

from typing import Any

from .base import RiskAssessment, RiskEngine

# Biologically plausible bands for Apis cerana / A. mellifera apiaries.
_TEMP_LOW, _TEMP_HIGH = 18.0, 36.0
_HUMID_LOW, _HUMID_HIGH = 35.0, 80.0


class RiskEngineAdapter(RiskEngine):
    """Rule-based colony-stress / inspection-priority model.

    This is an inspection-priority signal, not a disease diagnosis. It derives
    from recorded readings only; when no readings exist it returns insufficient
    evidence instead of inventing numbers.
    """

    def assess(self, hive_id: str, readings: list[dict]) -> RiskAssessment:
        if not readings:
            return RiskAssessment(
                hive_id=hive_id,
                risk_level="LOW",
                risk_score=0,
                contributing_factors=[
                    {"factor": "no readings", "contribution": "insufficient data"}
                ],
                recommended_action=(
                    "Not enough data for an inspection-priority assessment."
                ),
                simulated=False,
            )

        issues: list[str] = []
        temperatures = [
            float(r.get("temperature_c"))
            for r in readings
            if r.get("temperature_c") is not None
        ]
        humidities = [
            float(r.get("humidity_percent"))
            for r in readings
            if r.get("humidity_percent") is not None
        ]
        weights = [
            float(r.get("weight_kg"))
            for r in readings
            if r.get("weight_kg") is not None
        ]

        if temperatures:
            avg_t = sum(temperatures) / len(temperatures)
            if avg_t < _TEMP_LOW:
                issues.append("temperature below the colony comfort band")
            if avg_t > _TEMP_HIGH:
                issues.append("temperature above the colony comfort band")
        if humidities:
            avg_h = sum(humidities) / len(humidities)
            if avg_h < _HUMID_LOW:
                issues.append("low humidity stresses brood")
            if avg_h > _HUMID_HIGH:
                issues.append("high humidity raises disease pressure")
        if len(weights) >= 2:
            trend = weights[-1] - weights[0]
            if trend / max(abs(weights[0]), 1e-6) < -0.1:
                issues.append("weight trend is sharply negative")

        score = min(100, 15 + 25 * len(issues))
        level = "HIGH" if score >= 65 else "MEDIUM" if score >= 40 else "LOW"
        factors = [
            {"factor": issue, "contribution": "recorded reading deviation"}
            for issue in issues
        ]
        action = {
            "HIGH": "Inspect the apiary soon and check colony strength.",
            "MEDIUM": "Schedule an inspection; review the latest readings.",
            "LOW": "Continue routine inspection cadence.",
        }[level]
        if not issues:
            action = "Continue routine inspection cadence."
        return RiskAssessment(
            hive_id=hive_id,
            risk_level=level,
            risk_score=score,
            contributing_factors=factors,
            recommended_action=action,
            simulated=False,
        )