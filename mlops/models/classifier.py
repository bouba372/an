"""Text classification model wrapper."""

from typing import Optional
from pathlib import Path

import numpy as np
import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification, pipeline

from mlops.config import (
    PRETRAINED_MODEL,
    MAX_LENGTH,
    NUM_LABELS,
    ID_TO_CATEGORY,
    INFERENCE_CONFIDENCE_THRESHOLD,
)


class TextClassifier:
    """Wrapper for text classification using transformers."""

    def __init__(
        self,
        model_path: Optional[str | Path] = None,
        device: str = "cpu",
    ):
        """Initialize classifier.

        Args:
            model_path: Path to fine-tuned model, or None for pretrained
            device: "cpu" or "cuda"
        """
        self.device = device
        self.model_path = model_path

        if model_path:
            self.tokenizer = AutoTokenizer.from_pretrained(model_path)
            self.model = AutoModelForSequenceClassification.from_pretrained(
                model_path,
                num_labels=NUM_LABELS,
            ).to(device)
        else:
            self.tokenizer = AutoTokenizer.from_pretrained(PRETRAINED_MODEL)
            self.model = AutoModelForSequenceClassification.from_pretrained(
                PRETRAINED_MODEL,
                num_labels=NUM_LABELS,
            ).to(device)

        self.model.eval()
        self.pipeline = pipeline(
            "text-classification",
            model=self.model,
            tokenizer=self.tokenizer,
            device=device if device == "cuda" else -1,
        )

    def predict(
        self,
        texts: str | list[str],
        return_confidence: bool = True,
    ) -> dict | list[dict]:
        """Predict categories for text(s).

        Args:
            texts: Single text or list of texts
            return_confidence: Whether to include confidence scores

        Returns:
            Single prediction dict or list of dict:
            {
                "text": str,
                "label": str,
                "score": float (if return_confidence=True),
                "confidence_above_threshold": bool
            }
        """
        is_single = isinstance(texts, str)
        texts_list = [texts] if is_single else texts

        results = []
        with torch.no_grad():
            for text in texts_list:
                # Tokenize
                inputs = self.tokenizer(
                    text,
                    max_length=MAX_LENGTH,
                    truncation=True,
                    padding=True,
                    return_tensors="pt",
                )

                # Move to device
                inputs = {k: v.to(self.device) for k, v in inputs.items()}

                # Forward pass
                outputs = self.model(**inputs)
                logits = outputs.logits

                # Get predictions
                probs = torch.softmax(logits, dim=-1)
                prediction_id = torch.argmax(probs, dim=-1).item()
                confidence = probs[0, prediction_id].item()
                label = ID_TO_CATEGORY.get(prediction_id, "unknown")

                result = {
                    "text": text[:100],  # Truncate for display
                    "label": label,
                }
                if return_confidence:
                    result["confidence"] = confidence
                    result["above_threshold"] = (
                        confidence >= INFERENCE_CONFIDENCE_THRESHOLD
                    )

                results.append(result)

        return results[0] if is_single else results

    def predict_batch(
        self,
        texts: list[str],
        batch_size: int = 64,
        return_confidence: bool = True,
    ) -> list[dict]:
        """Predict categories for a batch of texts.

        Args:
            texts: List of texts
            batch_size: Batch size for processing
            return_confidence: Whether to include confidence scores

        Returns:
            List of prediction dicts
        """
        results = []
        for i in range(0, len(texts), batch_size):
            batch = texts[i : i + batch_size]
            batch_results = self.predict(
                batch,
                return_confidence=return_confidence,
            )
            results.extend(batch_results)
        return results

    def save(self, path: str | Path):
        """Save model to path.

        Args:
            path: Directory to save model
        """
        path = Path(path)
        path.mkdir(parents=True, exist_ok=True)
        self.model.save_pretrained(path)
        self.tokenizer.save_pretrained(path)

    @classmethod
    def from_pretrained(cls, path: str | Path, device: str = "cpu"):
        """Load model from path.

        Args:
            path: Directory with model files
            device: "cpu" or "cuda"

        Returns:
            TextClassifier instance
        """
        return cls(model_path=path, device=device)
