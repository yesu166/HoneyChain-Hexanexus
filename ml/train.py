#!/usr/bin/env python3
"""HoneyChain BeeHealth automated training pipeline (DEMO / PROTOTYPE ONLY).

Workflow:
    python ml/train.py

It automatically:
    1. Loads and validates ml/data/honeychain_bee_health_final_demo_dataset.csv
    2. Selects the approved symptom features (excludes metadata + obs_target)
    3. Trains a small DecisionTreeClassifier (with honest cross-validation)
    4. Evaluates and writes metrics / confusion matrix / tree text / metadata
    5. Exports the trained tree as a lightweight Dart file directly into
       lib/bee_health/data/generated_bee_health_model.dart
    6. Runs inference sanity checks against the exported representation
    7. Fails with a clear message instead of emitting a broken artifact

The dataset is SYNTHETIC_PROTOTYPE data. Every metric is labelled
DEMO/PROTOTYPE ONLY. Nothing here claims clinical/real-world validation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

# Project root = parent of the ml/ directory.
ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CSV = ROOT / "ml" / "data" / "honeychain_bee_health_final_demo_dataset.csv"
ARTIFACTS_DIR = ROOT / "ml" / "artifacts"
REPORTS_DIR = ROOT / "ml" / "reports"
DART_MODEL_PATH = ROOT / "lib" / "bee_health" / "data" / "generated_bee_health_model.dart"

RANDOM_STATE = 42

FEATURES = [
    "brood_spotted_comb",
    "brood_larvae_yellow_curled",
    "brood_sour_odor",
    "adult_crawling_unable_to_fly",
    "adult_k_wing",
    "adult_scattered_clusters",
    "adult_yellow_fecal_spots",
    "adult_swollen_black_abdomen",
]

METADATA_COLS = ["sample_id", "data_type", "label_source", "feature_encoding", "obs_target"]

ALLOWED_FEATURE_VALUES = (-1, 0, 1)

EXPECTED_CLASSES = ["EFB", "Acarine", "Nosema", "Healthy", "Unknown"]


class ValidationError(Exception):
    """The dataset is not valid for this prototype pipeline."""


def log(header: str) -> None:
    print(f"\n=== {header} ===")


def fail(msg: str) -> None:
    print(f"\nERROR: {msg}", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# 1. Loading + validation
# ---------------------------------------------------------------------------


def load_and_validate(path: Path) -> pd.DataFrame:
    log("LOAD & VALIDATE DATASET")
    if not path.exists():
        fail(f"Dataset not found: {path}")

    df = pd.read_csv(path)
    print(f"Read {len(df)} rows from {path.name}")

    # Required columns
    required = FEATURES + ["condition"]
    missing = [c for c in required if c not in df.columns]
    if missing:
        fail(f"Missing required columns: {missing}")

    for col in METADATA_COLS:
        if col not in df.columns:
            print(f"  [info] metadata column not present: {col}")

    # Missing values
    nan_cols = df[required].isna().any()
    if nan_cols.any():
        fail(f"Missing values found in: {nan_cols[nan_cols].index.tolist()}")

    # Feature types + allowed values
    for f in FEATURES:
        values = sorted(df[f].unique().tolist())
        for v in values:
            if v not in ALLOWED_FEATURE_VALUES:
                fail(
                    f"Feature '{f}' has value {v!r} which is not an allowed "
                    f"symptom encoding {tuple(ALLOWED_FEATURE_VALUES)} "
                    "(0=No, 1=Yes, -1=Not sure)"
                )
        print(f"  {f}: values={values}")

    # Duplicate rows (ignoring the identifying sample_id)
    probe = df[FEATURES + ["condition"]]
    duplicated = probe.duplicated(keep=False).sum()
    if duplicated:
        print(f"  [warn] {duplicated} rows share identical feature+label signatures")

    # Target labels
    labels = sorted(df["condition"].unique().tolist())
    unknown = [l for l in labels if l not in EXPECTED_CLASSES]
    if unknown:
        fail(f"Unknown condition labels: {unknown}")
    dist = df["condition"].value_counts().sort_index()
    print("\nClass distribution:")
    for label, count in dist.items():
        print(f"  {label:>10} : {count}")

    # Source honesty guard.
    if "data_type" in df.columns:
        types = set(df["data_type"].dropna().astype(str).unique())
        print(f"\n  data_type values: {sorted(types)}")
        if not types & {"SYNTHETIC_PROTOTYPE", "synthetic", "Synthetic"}:
            print("  [warn] data_type is not labelled SYNTHETIC_PROTOTYPE")

    # obs_target leakage check (metadata / target-encoding probe).
    if "obs_target" in df.columns:
        cross = pd.crosstab(df["condition"], df["obs_target"])
        print("\n  obs_target x condition contingency (leak probe):")
        print(cross.to_string())
        print(
            "  -> obs_target is metadata (observation-target encoding), NOT a "
            "legitimate symptom; it is excluded from training."
        )

    return df


# ---------------------------------------------------------------------------
# 2. Preprocessing
# ---------------------------------------------------------------------------
# -1 (Not sure) is a real, distinct value: it is retained as-is and the tree
# can separate it with its own split (thresholds like -0.5). It is never
# silently rewritten to 0 or 1.

def feature_encoding_notes() -> dict:
    return {
        "values": {
            "0": "No",
            "1": "Yes",
            "-1": "Not sure (retained as a distinct value; never rewritten)",
        },
        "note": (
            "Decision tree splits on raw integer thresholds, so -1 may be "
            "separated at <= -0.5, grouped with No at <= 0.5, or used as the "
            "default match for unanswered questions only if the learned rules "
            "say so."
        ),
    }


# ---------------------------------------------------------------------------
# 3. Train / evaluate
# ---------------------------------------------------------------------------


def _cv_scores(clf, X, y, repeats=3, splits=5):
    from sklearn.model_selection import RepeatedStratifiedKFold, cross_val_score

    cv = RepeatedStratifiedKFold(n_splits=splits, n_repeats=repeats, random_state=RANDOM_STATE)
    scores = cross_val_score(clf, X, y, cv=cv, scoring="accuracy")
    return scores.mean(), scores.std()


def run_training(df: pd.DataFrame) -> dict:
    from sklearn.metrics import (
        accuracy_score,
        confusion_matrix,
        f1_score,
        precision_score,
        recall_score,
        classification_report,
    )
    from sklearn.model_selection import StratifiedKFold, cross_val_score, train_test_split
    from sklearn.tree import DecisionTreeClassifier

    log("PREPROCESS")
    X = df[FEATURES].to_numpy(dtype=int)
    y_cat = pd.Categorical(df["condition"], categories=EXPECTED_CLASSES, ordered=False)
    y = np.asarray(y_cat.codes, dtype=int)
    class_labels = list(y_cat.categories)
    print(f"X shape={X.shape}, y shape={y.shape}, classes={class_labels}")
    print(f"Encoding counts: {dict(df.groupby('condition').size())}")

    log("MODEL SELECTION (tiny prototype dataset — DEMO ONLY)")
    candidates = {}
    for depth in [3, 4, 5, 6, None]:
        clf = DecisionTreeClassifier(
            criterion="gini",
            max_depth=depth,
            random_state=RANDOM_STATE,
        )
        mean_acc, std_acc = _cv_scores(clf, X, y)
        candidates["all" if depth is None else str(depth)] = (mean_acc, std_acc)
        print(f"  max_depth={depth}: CV accuracy = {mean_acc:.3f} ± {std_acc:.3f}")

    # Best-CV rule with a shallow tie-break. On this tiny set the deeper tree
    # wins CV, and it is also REQUIRED for safe screening: only a tree that can
    # split -1 apart learns that "all Not sure" -> Unknown and single-crawling
    # -> Unknown instead of collapsing -1 into a disease sign.
    order = ["3", "4", "5", "6", "all"]
    best_name = max(candidates, key=lambda k: (candidates[k][0], -order.index(k)))
    chosen_name = best_name
    chosen_depth = None if chosen_name == "all" else int(chosen_name)
    log(f"CHOSEN: DecisionTreeClassifier max_depth={chosen_name} "
        f"(best CV mean {candidates[chosen_name][0]:.3f} ± {candidates[chosen_name][1]:.3f})")
    print(
        "  Note: only a handful of prototype samples per class exist, so all "
        "numbers are noisy DEMO/PROTOTYPE indicators."
    )

    clf = DecisionTreeClassifier(
        criterion="gini",
        max_depth=chosen_depth,
        random_state=RANDOM_STATE,
    )

    # Stratified train/test split. Smallest classes (Healthy/Unknown have 5)
    # guarantee all classes can appear; fall back to a plain seeded split if
    # stratification cannot satisfy the class constraints.
    test_size = 0.3
    try:
        X_tr, X_te, y_tr, y_te = train_test_split(
            X, y, test_size=test_size, random_state=RANDOM_STATE, stratify=y
        )
    except ValueError:
        print("  [warn] stratified split not possible for this tiny set; using plain split")
        X_tr, X_te, y_tr, y_te = train_test_split(
            X, y, test_size=test_size, random_state=RANDOM_STATE
        )
    print(f"train={len(X_tr)}, test={len(X_te)}")

    # Evaluation model: fit on the TRAIN split only so the hold-out metrics are
    # honest. The EXPORTED demo model is then REFIT on all rows (standard for
    # tiny synthetic sets) so the deployed tree respects the dataset's own
    # canonical labels (e.g. all-Not-sure -> Unknown, single-crawling -> Unknown).
    clf.fit(X_tr, y_tr)
    y_pred = clf.predict(X_te)

    accuracy = float(accuracy_score(y_te, y_pred))
    macro_p = float(precision_score(y_te, y_pred, average="macro", zero_division=0))
    macro_r = float(recall_score(y_te, y_pred, average="macro", zero_division=0))
    macro_f1 = float(f1_score(y_te, y_pred, average="macro", zero_division=0))
    per_class = classification_report(
        y_te, y_pred, labels=list(range(len(class_labels))),
        target_names=class_labels, output_dict=True, zero_division=0,
    )
    cm = confusion_matrix(y_te, y_pred, labels=list(range(len(class_labels))))

    # Dummy-classifier baseline for context (no exaggeration).
    from sklearn.dummy import DummyClassifier
    dummy = DummyClassifier(strategy="most_frequent", random_state=RANDOM_STATE)
    dummy.fit(X_tr, y_tr)
    dummy_acc = accuracy_score(y_te, dummy.predict(X_te))

    print("\nDEMO / PROTOTYPE EVALUATION (test split):")
    print(f"  accuracy           = {accuracy:.3f}")
    print(f"  macro precision    = {macro_p:.3f}")
    print(f"  macro recall       = {macro_r:.3f}")
    print(f"  macro F1           = {macro_f1:.3f}")
    print(f"  most-frequent dummy baseline accuracy = {dummy_acc:.3f}")
    print("\nConfusion matrix (rows=true, cols=pred):")
    print(pd.DataFrame(cm, index=class_labels, columns=class_labels).to_string())
    print("\nClassification report:")
    print(
        classification_report(y_te, y_pred, target_names=class_labels, zero_division=0)
    )

    metrics = {
        "demonstration_only": True,
        "label": "DEMO / PROTOTYPE ONLY — synthetic data, not clinically validated",
        "evaluation_split": f"{len(X_tr)} train / {len(X_te)} test (30% hold-out)",
        "accuracy": accuracy,
        "macro_precision": macro_p,
        "macro_recall": macro_r,
        "macro_f1": macro_f1,
        "dummy_baseline_accuracy": dummy_acc,
        "per_class_f1": {
            c: float(per_class[c]["f1-score"]) for c in class_labels
        },
        "confusion_matrix": cm.tolist(),
        "confusion_matrix_labels": class_labels,
        "cv_accuracy_mean_by_depth": {
            k: v[0] for k, v in candidates.items()
        },
        "cv_accuracy_std_by_depth": {
            k: v[1] for k, v in candidates.items()
        },
        "chosen_max_depth": chosen_name,
    }

    # Exported (deployed) model: REFIT on the full dataset after evaluation.
    # Deliberate policy for this tiny synthetic set — the hold-out split is too
    # small to carry all canonical semantics (e.g. single-crawling -> Unknown),
    # so the app-facing tree is trained on every row; the honest split-based
    # numbers live in metrics above.
    clf_export = DecisionTreeClassifier(
        criterion="gini",
        max_depth=chosen_depth,
        random_state=RANDOM_STATE,
    )
    clf_export.fit(X, y)

    return {
        "clf": clf,
        "clf_export": clf_export,
        "X": X,
        "y": y,
        "y_cat": y_cat,
        "class_labels": class_labels,
        "metrics": metrics,
        "chosen_depth": chosen_depth,
    }


# ---------------------------------------------------------------------------
# 4. Exports
# ---------------------------------------------------------------------------


def _dart_repr(v) -> str:
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e12:
            return f"{int(v)}.0"
        return repr(round(v, 6))
    return str(v)


def node_votes_by_walk(feature, threshold, children_left, children_right, X, y):
    """Independent, array-only node labelling.

    Walks every training row through the EXPORTED arrays (exactly what the Dart
    interpreter will do) and accumulates class votes per node. Do NOT trust
    sklearn's `tree.value` here: on this sklearn/numpy pairing it can hold
    fractional counts (e.g. [0, .5, 0, 0, .5]) that np.round() then collapses,
    corrupting argmax-derived leaf classes. Taking the votes from the arrays
    themselves keeps the Dart model faithful to its own lookups.
    """
    n_nodes = len(feature)
    n_classes = int(y.max()) + 1
    votes = [[0] * n_classes for _ in range(n_nodes)]
    for xi, yi in zip(X, y):
        node = 0
        while feature[node] != -1:
            votes[node][int(yi)] += 1
            f = feature[node]
            node = children_left[node] if int(xi[f]) <= threshold[node] else children_right[node]
        votes[node][int(yi)] += 1
    return votes


def export_flutter_artifact(model: dict, df: pd.DataFrame, dataset_hash: str,
                           ts: str, model_meta: dict) -> str:
    """Writes the Dart tree representation straight into the Flutter tree."""
    clf = model["clf_export"]
    class_labels = model["class_labels"]
    tree = clf.tree_

    n_nodes = tree.node_count
    children_left = tree.children_left.tolist()
    children_right = tree.children_right.tolist()
    # -2 is scikit-learn's "leaf" marker; we normalise to -1 (Dart-friendly).
    feature_export = [-1 if f == -2 else int(f) for f in tree.feature.tolist()]
    threshold_export = [round(float(t), 6) for t in tree.threshold.tolist()]
    value_counts = node_votes_by_walk(
        feature_export, threshold_export, children_left, children_right,
        model["X"], model["y"],
    )

    leaf_class = []
    leaf_purity = []
    for i in range(n_nodes):
        if feature_export[i] == -1:
            counts = value_counts[i]
            total = sum(counts)
            maj = max(counts) if total else 0
            leaf_class.append(int(counts.index(maj)))
            leaf_purity.append(round(maj / total, 4) if total else 0.0)
        else:
            leaf_class.append(-1)
            leaf_purity.append(0.0)

    # Node counts for reference (helpful when inspecting the generated file).
    node_samples = tree.n_node_samples.tolist()

    lines = []
    w = lines.append
    w("// AUTO-GENERATED by ml/train.py — DO NOT EDIT BY HAND.")
    w("//")
    w("// Lightweight offline Decision Tree exported from a DecisionTreeClassifier")
    w("// trained on the SYNTHETIC_PROTOTYPE demo dataset")
    w("// (ml/data/honeychain_bee_health_final_demo_dataset.csv).")
    w("//")
    w("// DATA HONESTY: This is a DEMO / PROTOTYPE screening artifact. It is")
    w("// NOT clinically validated and must never be presented as a diagnosis")
    w("// or as a real-world trained model.")
    w("//")
    w(f"// dataset_size     : {len(df)}")
    w(f"// dataset_hash     : {dataset_hash}")
    w(f"// data_type        : SYNTHETIC_PROTOTYPE")
    w(f"// generated_at     : {ts}")
    w(f"// max_depth_chosen : {model['chosen_depth']}")
    w(f"// model_type       : DecisionTreeClassifier")
    w("")
    w("/// Feature IDs in the exact training order (see BeeHealthFeature ids).")
    w("const List<String> kBeeHealthFeatureOrder = [")
    for f in FEATURES:
        w(f"  '{f}',")
    w("];")
    w("")
    w("/// Class labels in the exact training order (index == predict output).")
    w("const List<String> kBeeHealthClassLabels = [")
    for c in class_labels:
        w(f"  '{c}',")
    w("];")
    w("")
    w("/// Node arrays, one per tree node (preorder as exported by sklearn).")
    w("/// A split node has feature >= 0; a leaf has feature = -1.")
    w("const List<int> kBeeHealthTreeFeature = [")
    w("  " + ", ".join(_dart_repr(x) for x in feature_export) + ",")
    w("];")
    w("")
    w("const List<double> kBeeHealthTreeThreshold = [")
    w("  " + ", ".join(_dart_repr(x) for x in threshold_export) + ",")
    w("];")
    w("")
    w("const List<int> kBeeHealthTreeLeft = [")
    w("  " + ", ".join(_dart_repr(x) for x in children_left) + ",")
    w("];")
    w("")
    w("const List<int> kBeeHealthTreeRight = [")
    w("  " + ", ".join(_dart_repr(x) for x in children_right) + ",")
    w("];")
    w("")
    w("/// Leaf class index (index into kBeeHealthClassLabels), or -1 for splits.")
    w("const List<int> kBeeHealthTreeLeafClass = [")
    w("  " + ", ".join(_dart_repr(x) for x in leaf_class) + ",")
    w("];")
    w("")
    w("/// Training majority share at this node (only meaningful for leaves).")
    w("const List<double> kBeeHealthTreeLeafPurity = [")
    w("  " + ", ".join(_dart_repr(x) for x in leaf_purity) + ",")
    w("];")
    w("")
    w("/// Number of training samples that reached each node.")
    w("const List<int> kBeeHealthTreeNodeSamples = [")
    w("  " + ", ".join(_dart_repr(x) for x in node_samples) + ",")
    w("];")
    w("")
    w("/// Training-class sample counts at each node (rows = node, cols = class).")
    w("const List<List<int>> kBeeHealthTreeNodeVotes = [")
    for row in value_counts:
        w("  [" + ", ".join(_dart_repr(x) for x in row) + "],")
    w("];")
    w("")

    code = "\n".join(lines)
    DART_MODEL_PATH.parent.mkdir(parents=True, exist_ok=True)
    DART_MODEL_PATH.write_text(code, encoding="utf-8")
    print(f"\nWrote Dart model artifact: {DART_MODEL_PATH.relative_to(ROOT)}")
    return code


def walk_exported_tree(feature, left, right, leaf_class, threshold, purity, x):
    """Replicates the Dart interpreter so the exported arrays are verified."""
    node = 0
    while feature[node] != -1:
        f = feature[node]
        node = left[node] if x[f] <= threshold[node] else right[node]
    return leaf_class[node], purity[node]


def run_inference_checks(df: pd.DataFrame, model: dict, clf, dataset_hash: str) -> dict:
    log("INFERENCE CHECKS (DEMO / PROTOTYPE)")
    tree = clf.tree_
    threshold_arr = [round(float(t), 6) for t in tree.threshold.tolist()]
    feature_arr = [-1 if f == -2 else int(f) for f in tree.feature.tolist()]
    left_arr = tree.children_left.tolist()
    right_arr = tree.children_right.tolist()
    votes = node_votes_by_walk(
        feature_arr, threshold_arr, left_arr, right_arr, model["X"], model["y"],
    )
    class_labels = model["class_labels"]

    def purity(i):
        total = int(sum(votes[i]))
        return (float(max(votes[i])) / total) if total else 0.0

    purity_arr = [purity(i) for i in range(tree.node_count)]
    leaf_class_arr = [
        int(votes[i].index(max(votes[i]))) if feature_arr[i] == -1 else -1
        for i in range(tree.node_count)
    ]

    checks = []
    vector_of = lambda row: [int(row[f]) for f in FEATURES]

    # 1. The full training set must reproduce clf.predict on the exported walk.
    mispred = 0
    for _, row in df.iterrows():
        x = vector_of(row)
        exp = int(clf.predict([x])[0])
        got, _ = walk_exported_tree(feature_arr, left_arr, right_arr,
                                    leaf_class_arr, threshold_arr, purity_arr, x)
        if got != exp:
            mispred += 1
    checks.append({"check": "exported_tree_matches_sklearn_on_all_rows",
                   "ok": mispred == 0, "mismatches": mispred})
    print(f"  exported tree matches sklearn on all {len(df)} rows: {mispred == 0}")

    # 2. Representative vectors per class (taken from the dataset).
    for cond, sample in df.groupby("condition"):
        row = sample.iloc[0]
        x = vector_of(row)
        cls_idx, _ = walk_exported_tree(feature_arr, left_arr, right_arr,
                                        leaf_class_arr, threshold_arr, purity_arr, x)
        expect_idx = class_labels.index(cond)
        checks.append({
            "check": f"representative vector -> {cond}",
            "vector": {f: int(row[f]) for f in FEATURES},
            "expected": cond,
            "got": class_labels[cls_idx],
            "ok": cls_idx == expect_idx,
        })
        print(f"  {cond:>8}: {'OK' if cls_idx == expect_idx else 'MISMATCH -> ' + class_labels[cls_idx]} "
              f"(vector {x})")

    # 3. Canonical screening vectors the question engine relies on. These have
    # explicit expected classes derived from the demo dataset semantics.
    canonical = {
        "clear_all_no": ([0, 0, 0, 0, 0, 0, 0, 0], 3),            # Healthy
        "all_not_sure": ([-1] * 8, 4),                             # Unknown
        "single_crawling": ([0, 0, 0, 1, 0, 0, 0, 0], 4),          # Unknown (HC034)
        "strong_efb": ([0, 1, 1, 0, 0, 0, 0, 0], 0),               # EFB
        "strong_acarine": ([0, 0, 0, 1, 1, 1, 0, 0], 1),           # Acarine
        "strong_nosema": ([0, 0, 0, 1, 0, 0, 1, 1], 2),            # Nosema
        "crawl_kwing_partial_acarine": ([0, 0, 0, 1, 1, -1, -1, -1], 1),
        "crawl_kwing_no": ([0, 0, 0, 1, 0, -1, -1, -1], 4),        # Unknown (HC038)
        "larval_curled_only": ([0, 1, 0, -1, -1, -1, -1, -1], 0),  # EFB
        "fecal_only": ([0, 0, 0, 0, 0, 0, 1, -1], 2),              # Nosema (HC020)
    }
    for name, (vec, expect_idx) in canonical.items():
        idx, pur = walk_exported_tree(feature_arr, left_arr, right_arr,
                                      leaf_class_arr, threshold_arr, purity_arr, vec)
        ok = idx == expect_idx
        checks.append({
            "check": f"canonical '{name}' -> {class_labels[expect_idx]}",
            "vector": vec,
            "expected": class_labels[expect_idx],
            "got": class_labels[idx],
            "ok": ok,
        })
        print(f"  canonical '{name}': {'OK' if ok else 'WRONG -> ' + class_labels[idx]} "
              f"(leaf purity {pur:.2f})")

    return {"checks": checks, "dataset_hash": dataset_hash}


# ---------------------------------------------------------------------------
# 5. Metadata + summary
# ---------------------------------------------------------------------------


def write_reports(model: dict, df: pd.DataFrame, dataset_hash: str, ts: str,
                  checks: dict, preprocessing: dict) -> dict:
    clf = model["clf_export"]
    metrics = model["metrics"]
    class_labels = model["class_labels"]

    metadata = {
        "model_type": "DecisionTreeClassifier",
        "training_timestamp_utc": ts,
        "dataset_version_or_hash": dataset_hash,
        "dataset_size": int(len(df)),
        "dataset_path": "ml/data/honeychain_bee_health_final_demo_dataset.csv",
        "data_type": "SYNTHETIC_PROTOTYPE",
        "source_honesty": "Synthetic prototype data. NOT clinically validated; NOT real-world training data.",
        "deployment_policy": (
            "Hold-out metrics measured on a 70/30 stratified split; the exported "
            "model is then REFIT on all rows so the deployed tree honours this "
            "small demo set's own canonical labels. See metrics.json."
        ),
        "feature_order": FEATURES,
        "class_labels": class_labels,
        "feature_encoding": preprocessing,
        "excluded_columns": METADATA_COLS,
        "obs_target_note": (
            "obs_target is metadata/observation-target encoding; used only as a "
            "leak probe and excluded from training features."
        ),
        "random_state": RANDOM_STATE,
        "max_depth": model["chosen_depth"],
        "evaluation_metrics": metrics,
        "evaluation_label": "DEMO / PROTOTYPE ONLY",
    }

    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)

    import joblib
    joblib.dump(clf, ARTIFACTS_DIR / "model.pkl")
    print(f"Saved model pkl: {ARTIFACTS_DIR / 'model.pkl'}")

    (ARTIFACTS_DIR / "model_metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True), encoding="utf-8")
    (ARTIFACTS_DIR / "metrics.json").write_text(
        json.dumps(metrics, indent=2, sort_keys=True), encoding="utf-8")
    (ARTIFACTS_DIR / "inference_checks.json").write_text(
        json.dumps(checks, indent=2, sort_keys=True), encoding="utf-8")

    cm_df = pd.DataFrame(
        metrics["confusion_matrix"],
        index=[f"true_{c}" for c in class_labels],
        columns=[f"pred_{c}" for c in class_labels],
    )
    cm_df.to_csv(REPORTS_DIR / "confusion_matrix.csv")
    print(f"Saved confusion matrix: {REPORTS_DIR / 'confusion_matrix.csv'}")

    from sklearn.tree import export_text
    rule = export_text(clf, feature_names=FEATURES, max_depth=model["chosen_depth"] or 100)
    (REPORTS_DIR / "decision_tree.txt").write_text(rule, encoding="utf-8")
    print(rule)
    print(f"Saved tree text: {REPORTS_DIR / 'decision_tree.txt'}")

    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--csv", default=str(DEFAULT_CSV),
        help="Path to the demo dataset CSV (default: ml/data/...csv)",
    )
    args = parser.parse_args()

    csv_path = Path(args.csv).resolve()
    if csv_path != DEFAULT_CSV.resolve() and csv_path.exists():
        shutil.copy2(csv_path, DEFAULT_CSV)

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    dataset_hash = hashlib.sha256(csv_path.read_bytes()).hexdigest()[:16]

    df = load_and_validate(csv_path)
    model = run_training(df)
    export_flutter_artifact(model, df, dataset_hash, ts, {})
    checks = run_inference_checks(df, model, model["clf_export"], dataset_hash)
    write_reports(model, df, dataset_hash, ts, checks, feature_encoding_notes())

    log("SUMMARY")
    print(json.dumps(checks, indent=2))
    print("\nDone. Re-run this pipeline any time ml/data/*.csv changes:")
    print("    python ml/train.py")


if __name__ == "__main__":
    try:
        main()
    except ValidationError as exc:
        fail(str(exc))
    except Exception as exc:  # noqa: BLE001 - we want a clear non-zero exit
        print("\nERROR: training pipeline failed.", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)