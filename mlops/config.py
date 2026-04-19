"""MLOps configuration for text classification model."""

from enum import Enum
from pathlib import Path

import os


# Text Classification Categories (French National Assembly domains)
class Category(str, Enum):
    """Categories for parliamentary interventions."""
    SANTE = "santé"
    ECONOMIE = "économie"
    EDUCATION = "éducation"
    DEFENSE = "défense"
    JUSTICE = "justice"
    ENVIRONNEMENT = "environnement"
    CULTURE = "culture"
    TRANSPORT = "transport"
    FINANCES = "finances"
    ADMINISTRATIVE = "administrative"
    AUTRE = "autre"


# Model Configuration
MODEL_NAME = os.getenv("MLOPS_MODEL_NAME", "distiluse-base-multilingual-cased-v2")
PRETRAINED_MODEL = os.getenv(
    "MLOPS_PRETRAINED_MODEL",
    "distilbert-base-multilingual-cased"
)
MAX_LENGTH = int(os.getenv("MLOPS_MAX_LENGTH", "512"))
BATCH_SIZE = int(os.getenv("MLOPS_BATCH_SIZE", "32"))
LEARNING_RATE = float(os.getenv("MLOPS_LEARNING_RATE", "2e-5"))
NUM_EPOCHS = int(os.getenv("MLOPS_NUM_EPOCHS", "3"))
EVAL_STEPS = int(os.getenv("MLOPS_EVAL_STEPS", "500"))

# Model Registry (MLflow)
MLFLOW_TRACKING_URI = os.getenv("MLFLOW_TRACKING_URI", "http://localhost:5000")
MLFLOW_EXPERIMENT_NAME = "parleman-text-classification"
MLFLOW_MODEL_REGISTRY_URI = os.getenv(
    "MLFLOW_MODEL_REGISTRY_URI",
    MLFLOW_TRACKING_URI
)

# Storage
# Use repo-local defaults for local runs; containerized deployments can override with env vars.
MODEL_STORAGE_PATH = Path(os.getenv("MLOPS_MODEL_PATH", "models"))
TRAINING_DATA_PATH = Path(os.getenv("MLOPS_TRAINING_DATA_PATH", "data/training"))

# Data
TRAIN_TEST_SPLIT = float(os.getenv("MLOPS_TRAIN_TEST_SPLIT", "0.8"))
VAL_TEST_SPLIT = float(os.getenv("MLOPS_VAL_TEST_SPLIT", "0.5"))
SEED = int(os.getenv("MLOPS_SEED", "42"))

# Performance Thresholds
MIN_ACCURACY = float(os.getenv("MLOPS_MIN_ACCURACY", "0.75"))
MIN_F1_SCORE = float(os.getenv("MLOPS_MIN_F1_SCORE", "0.70"))

# Inference
INFERENCE_BATCH_SIZE = int(os.getenv("MLOPS_INFERENCE_BATCH_SIZE", "64"))
INFERENCE_CONFIDENCE_THRESHOLD = float(
    os.getenv("MLOPS_CONFIDENCE_THRESHOLD", "0.6")
)

# Categories mapping
CATEGORIES = {c.value: i for i, c in enumerate(Category)}
ID_TO_CATEGORY = {v: k for k, v in CATEGORIES.items()}
NUM_LABELS = len(CATEGORIES)
