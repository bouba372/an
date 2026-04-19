"""Training pipeline for text classification."""

import logging
from datetime import datetime
from pathlib import Path

import numpy as np
import mlflow
import pandas as pd
import torch
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    accuracy_score,
    f1_score,
    precision_score,
    recall_score,
    confusion_matrix,
    classification_report,
)
from transformers import (
    AutoTokenizer,
    AutoModelForSequenceClassification,
    TrainingArguments,
    Trainer,
    DataCollatorWithPadding,
)
from datasets import Dataset

from lib.bq_utils.client import create_bq_client
from lib.config import get_config
from mlops.config import (
    PRETRAINED_MODEL,
    NUM_LABELS,
    CATEGORIES,
    ID_TO_CATEGORY,
    MAX_LENGTH,
    BATCH_SIZE,
    LEARNING_RATE,
    NUM_EPOCHS,
    EVAL_STEPS,
    TRAIN_TEST_SPLIT,
    VAL_TEST_SPLIT,
    SEED,
    MIN_ACCURACY,
    MIN_F1_SCORE,
    MODEL_STORAGE_PATH,
    MLFLOW_EXPERIMENT_NAME,
    MLFLOW_TRACKING_URI,
)

logger = logging.getLogger(__name__)


def fetch_training_data(dataset: str) -> pd.DataFrame:
    """Fetch interventions from BigQuery for training.

    Args:
        dataset: BigQuery dataset name

    Returns:
        DataFrame with columns: ['text', 'label', 'orateur_id', 'date']
    """
    logger.info(f"Fetching training data from {dataset}")

    client = create_bq_client(get_config())

    def run_query(date_filter: bool) -> pd.DataFrame:
        date_clause = """
            AND SAFE_CAST(cr.date_seance AS DATE) IS NOT NULL
            AND SAFE_CAST(cr.date_seance AS DATE) >= DATE_SUB(CURRENT_DATE(), INTERVAL 2 YEAR)
        """ if date_filter else ""

        query = f"""
            SELECT
                i.texte as text,
                COALESCE(p.sommaire, 'autre') as topic,
                i.orateur_id,
                SAFE_CAST(cr.date_seance AS DATE) as date_seance
            FROM `{client.project}.{dataset}.interventions` i
            LEFT JOIN `{client.project}.{dataset}.points_seance` p
                ON i.point_id = p.point_id
            LEFT JOIN `{client.project}.{dataset}.comptes_rendus` cr
                ON i.compte_rendu_uid = cr.uid
            WHERE
                i.texte IS NOT NULL
                AND LENGTH(i.texte) > 50
                {date_clause}
            ORDER BY cr.date_seance DESC
            LIMIT 10000
        """

        query_job = client.query(query)
        rows = query_job.result()
        records = [dict(row.items()) for row in rows]
        return pd.DataFrame(
            records,
            columns=["text", "topic", "orateur_id", "date_seance"],
        )

    # Try recent-window training data first.
    df = run_query(date_filter=True)

    if df.empty:
        logger.warning(
            "No rows returned with 2-year date filter. "
            "Retrying without date filter."
        )
        df = run_query(date_filter=False)

    if df.empty:
        raise ValueError(
            "No training data returned from BigQuery even without date filter. "
            "Check dataset/table names and source data availability."
        )
    logger.info(f"Fetched {len(df)} interventions")

    return df


def prepare_labels(df: pd.DataFrame) -> pd.DataFrame:
    """Prepare labels for training.

    Maps topics to predefined categories.
    """
    # Define category keywords (simplified for demo)
    category_keywords = {
        "santé": ["santé", "médicament", "hôpital", "covid", "vaccination"],
        "économie": ["économie", "emploi", "chômage", "business", "commercial"],
        "éducation": [
            "éducation",
            "école",
            "universitaire",
            "formation",
            "pédagogie",
        ],
        "défense": ["défense", "armée", "militaire", "sécurité", "nato"],
        "justice": ["justice", "pénal", "civil", "tribunal", "droit"],
        "environnement": [
            "environnement",
            "pollution",
            "climat",
            "écologie",
            "nature",
        ],
        "culture": ["culture", "art", "musée", "patrimoine", "cinéma"],
        "transport": ["transport", "route", "train", "aviation", "mobilité"],
        "finances": ["finances", "budget", "impôt", "fiscal", "dépenses"],
    }

    def categorize(topic):
        """Categorize based on keywords."""
        if not topic or pd.isna(topic):
            return "autre"

        topic_lower = str(topic).lower()
        for category, keywords in category_keywords.items():
            if any(kw in topic_lower for kw in keywords):
                return category

        return "autre"

    df["label"] = df["topic"].apply(categorize)
    df = df[["text", "label"]].dropna()

    logger.info(f"Label distribution:\n{df['label'].value_counts()}")
    return df


def create_train_test_splits(
    df: pd.DataFrame,
) -> tuple[Dataset, Dataset, Dataset]:
    """Create train, validation, and test datasets.

    Returns:
        (train_dataset, val_dataset, test_dataset)
    """
    # Convert string labels to IDs
    df["label_id"] = df["label"].map(CATEGORIES)

    # First split: train+val vs test
    train_val, test = train_test_split(
        df,
        test_size=1 - TRAIN_TEST_SPLIT,
        random_state=SEED,
        stratify=df["label_id"],
    )

    # Second split: train vs val
    train, val = train_test_split(
        train_val,
        test_size=VAL_TEST_SPLIT,
        random_state=SEED,
        stratify=train_val["label_id"],
    )

    logger.info(
        f"Dataset sizes: train={len(train)}, val={len(val)}, test={len(test)}"
    )

    return (
        Dataset.from_pandas(train),
        Dataset.from_pandas(val),
        Dataset.from_pandas(test),
    )


def tokenize_function(examples, tokenizer):
    """Tokenize text examples."""
    return tokenizer(
        examples["text"],
        padding="max_length",
        max_length=MAX_LENGTH,
        truncation=True,
    )


def train_model(dataset: str) -> dict:
    """Train text classification model.

    Args:
        dataset: BigQuery dataset name

    Returns:
        Metrics dictionary
    """
    mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)
    mlflow.set_experiment(MLFLOW_EXPERIMENT_NAME)

    with mlflow.start_run(run_name=f"training-{datetime.now().isoformat()}"):
        # 1. Fetch data
        df = fetch_training_data(dataset)
        df = prepare_labels(df)

        # 2. Create datasets
        train_dataset, val_dataset, test_dataset = create_train_test_splits(df)

        # 3. Tokenize
        tokenizer = AutoTokenizer.from_pretrained(PRETRAINED_MODEL)
        train_dataset = train_dataset.map(
            lambda x: tokenize_function(x, tokenizer),
            batched=True,
        )
        val_dataset = val_dataset.map(
            lambda x: tokenize_function(x, tokenizer),
            batched=True,
        )
        test_dataset = test_dataset.map(
            lambda x: tokenize_function(x, tokenizer),
            batched=True,
        )

        # Keep only model inputs + numeric labels for Trainer.
        allowed_columns = {"input_ids", "attention_mask", "token_type_ids", "label_id"}

        def prune_columns(ds: Dataset) -> Dataset:
            removable = [c for c in ds.column_names if c not in allowed_columns]
            if removable:
                ds = ds.remove_columns(removable)
            return ds.rename_column("label_id", "labels")

        train_dataset = prune_columns(train_dataset)
        val_dataset = prune_columns(val_dataset)
        test_dataset = prune_columns(test_dataset)

        # 4. Prepare model
        model = AutoModelForSequenceClassification.from_pretrained(
            PRETRAINED_MODEL,
            num_labels=NUM_LABELS,
        )

        # 5. Training arguments
        training_args = TrainingArguments(
            output_dir=str(MODEL_STORAGE_PATH / "checkpoints"),
            eval_strategy="steps",
            eval_steps=EVAL_STEPS,
            learning_rate=LEARNING_RATE,
            per_device_train_batch_size=BATCH_SIZE,
            per_device_eval_batch_size=BATCH_SIZE,
            num_train_epochs=NUM_EPOCHS,
            weight_decay=0.01,
            save_strategy="steps",
            save_steps=EVAL_STEPS,
            seed=SEED,
            push_to_hub=False,
        )

        # 6. Train
        trainer = Trainer(
            model=model,
            args=training_args,
            train_dataset=train_dataset,
            eval_dataset=val_dataset,
            data_collator=DataCollatorWithPadding(tokenizer),
        )

        trainer.train()

        # 7. Evaluate on test set
        logger.info("Evaluating on test set...")
        test_results = trainer.predict(test_dataset)
        test_preds = np.argmax(test_results.predictions, axis=1)
        test_labels = np.array(test_dataset["labels"])

        metrics = {
            "accuracy": accuracy_score(test_labels, test_preds),
            "f1": f1_score(test_labels, test_preds, average="weighted"),
            "precision": precision_score(test_labels, test_preds, average="weighted"),
            "recall": recall_score(test_labels, test_preds, average="weighted"),
        }

        logger.info(f"Test metrics: {metrics}")

        # 8. Log to MLflow
        mlflow.log_metrics(metrics)
        mlflow.log_param("model_name", PRETRAINED_MODEL)
        mlflow.log_param("learning_rate", LEARNING_RATE)
        mlflow.log_param("batch_size", BATCH_SIZE)
        mlflow.log_param("num_epochs", NUM_EPOCHS)
        mlflow.log_param("max_length", MAX_LENGTH)

        # 9. Save model
        model_output_path = MODEL_STORAGE_PATH / "final_model"
        model_output_path.mkdir(parents=True, exist_ok=True)
        trainer.save_model(str(model_output_path))

        logger.info(f"Model saved to {model_output_path}")

        # 10. Check thresholds
        if metrics["accuracy"] < MIN_ACCURACY:
            logger.warning(
                f"Accuracy {metrics['accuracy']:.2%} below threshold "
                f"{MIN_ACCURACY:.2%}"
            )
        if metrics["f1"] < MIN_F1_SCORE:
            logger.warning(
                f"F1 score {metrics['f1']:.2%} below threshold {MIN_F1_SCORE:.2%}"
            )

        mlflow.log_dict(
            classification_report(
                test_labels,
                test_preds,
                output_dict=True,
            ),
            artifact_file="classification_report.json",
        )

        return metrics


def train_flow(dataset: str | None = None) -> None:
    """Airflow-compatible training flow.

    Args:
        dataset: BigQuery dataset name (uses BQ_DATASET from config if not set)
    """
    if not dataset:
        dataset = get_config().bq_dataset

    logger.info(f"Starting training on dataset: {dataset}")
    metrics = train_model(dataset)
    logger.info(f"Training complete. Metrics: {metrics}")
