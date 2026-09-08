from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field


@dataclass
class RiskAssessment:
    hive_id: str
    risk_level: str  # LOW | MEDIUM | HIGH
    risk_score: int  # 0..100, higher = more stress
    contributing_factors: list[dict[str, str]] = field(default_factory=list)
    recommended_action: str = ""
    simulated: bool = False


class RiskEngine(ABC):
    @abstractmethod
    def assess(self, hive_id: str, readings: list[dict]) -> RiskAssessment: ...


def build_risk_engine(name: str) -> RiskEngine:
    from .risk_engine_adapter import RiskEngineAdapter

    if name and name.lower() in ("risk_engine", "ai"):
        return RiskEngineAdapter()
    return RiskEngineAdapter()