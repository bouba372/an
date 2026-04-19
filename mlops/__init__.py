"""Compact MLOps API for ParlemAN text classification."""

from mlops.inference import app, run_server
from mlops.models.classifier import TextClassifier
from mlops.training import train_flow, train_model

__all__ = [
    "TextClassifier",
    "train_flow",
    "train_model",
    "app",
    "run_server",
]
