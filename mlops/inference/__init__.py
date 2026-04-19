"""FastAPI inference service for text classification."""

import logging
import os
from pathlib import Path

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
import uvicorn

from mlops.models.classifier import TextClassifier
from mlops.config import MODEL_STORAGE_PATH, INFERENCE_BATCH_SIZE

logger = logging.getLogger(__name__)

app = FastAPI(
    title="ParlemAN Text Classification API",
    description="Classify French parliamentary interventions by topic",
    version="1.0.0",
)

# Global classifier instance
classifier = None


class PredictionRequest(BaseModel):
    """Request body for prediction."""

    texts: str | list[str] = Field(
        ...,
        description="Single text or list of texts to classify",
    )
    return_confidence: bool = Field(
        True,
        description="Include confidence scores in response",
    )


class PredictionResponse(BaseModel):
    """Response body for prediction."""

    text: str
    label: str
    confidence: float | None = None
    above_threshold: bool | None = None


class BatchPredictionResponse(BaseModel):
    """Response body for batch prediction."""

    predictions: list[PredictionResponse]
    count: int


@app.on_event("startup")
async def startup_event():
    """Load model on startup."""
    global classifier

    logger.info("Loading classifier model...")

    model_path = os.getenv(
        "MODEL_PATH",
        str(MODEL_STORAGE_PATH / "final_model"),
    )
    device = "cuda" if int(os.getenv("USE_GPU", "0")) else "cpu"

    if not Path(model_path).exists():
        logger.warning(
            f"Model not found at {model_path}, using pretrained model"
        )
        classifier = TextClassifier(device=device)
    else:
        classifier = TextClassifier.from_pretrained(model_path, device=device)

    logger.info(f"Classifier loaded. Device: {device}")


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "model_loaded": classifier is not None,
    }


@app.post("/predict", response_model=BatchPredictionResponse)
async def predict(request: PredictionRequest):
    """Classify text(s).

    Args:
        request: PredictionRequest with texts

    Returns:
        BatchPredictionResponse with predictions
    """
    if not classifier:
        raise HTTPException(
            status_code=503,
            detail="Model not loaded",
        )

    try:
        is_single = isinstance(request.texts, str)
        texts = [request.texts] if is_single else request.texts

        # Get predictions
        predictions = classifier.predict_batch(
            texts,
            batch_size=INFERENCE_BATCH_SIZE,
            return_confidence=request.return_confidence,
        )

        # Convert to response format
        responses = [
            PredictionResponse(
                text=p.get("text", ""),
                label=p.get("label", "unknown"),
                confidence=p.get("confidence"),
                above_threshold=p.get("above_threshold"),
            )
            for p in predictions
        ]

        return BatchPredictionResponse(
            predictions=responses,
            count=len(responses),
        )

    except Exception as e:
        logger.exception("Prediction error")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/predict/single", response_model=PredictionResponse)
async def predict_single(request: str):
    """Classify a single text (simplified endpoint).

    Args:
        request: Text to classify

    Returns:
        PredictionResponse
    """
    if not classifier:
        raise HTTPException(
            status_code=503,
            detail="Model not loaded",
        )

    try:
        prediction = classifier.predict(request, return_confidence=True)
        return PredictionResponse(**prediction)
    except Exception as e:
        logger.exception("Prediction error")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/labels")
async def get_labels():
    """Get available classification labels."""
    from mlops.config import CATEGORIES

    return {
        "labels": list(CATEGORIES.keys()),
        "count": len(CATEGORIES),
    }


@app.get("/")
async def root():
    """Root endpoint with API info."""
    return {
        "name": "ParlemAN Text Classification API",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "predict": "/predict",
            "predict_single": "/predict/single",
            "labels": "/labels",
            "docs": "/docs",
        },
    }


def run_server(
    host: str = "0.0.0.0",
    port: int = 8000,
    workers: int = 1,
):
    """Run the inference server.

    Args:
        host: Server host
        port: Server port
        workers: Number of worker processes
    """
    uvicorn.run(
        app,
        host=host,
        port=port,
        workers=workers,
    )


if __name__ == "__main__":
    run_server()
