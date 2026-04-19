# MLOps ParlemAN - Document unique

## 1) Objectif

Ce document regroupe et synthétise l’ensemble de la documentation MLOps du projet ParlemAN.

Le système permet de classifier automatiquement les interventions parlementaires en 11 catégories métier, avec :
- entraînement régulier du modèle,
- API d’inférence temps réel,
- suivi des performances et dérive,
- intégration Airflow, BigQuery, MLflow et Docker.

## 2) Périmètre fonctionnel

### Classification de texte
- Modèle de base : DistilBERT multilingual.
- Sortie : catégorie + score de confiance.
- Modes : prédiction unitaire et batch.

### Catégories
1. santé
2. économie
3. éducation
4. défense
5. justice
6. environnement
7. culture
8. transport
9. finances
10. administrative
11. autre

## 3) Architecture globale

Flux principal :
BigQuery (interventions) -> Pipeline d'entraînement (Airflow) -> Registry/Tracking (MLflow) -> API d'inférence (FastAPI) -> Logs de prédictions (BigQuery)

Composants clés :
- mlops/config.py : catégories, hyperparamètres, variables d’environnement.
- mlops/models/classifier.py : classe TextClassifier.
- mlops/training/__init__.py : pipeline d’entraînement et tracking.
- mlops/inference/__init__.py : serveur FastAPI.
- flows/train_text_classification.py : DAG Airflow d’entraînement hebdomadaire.

## 4) Démarrage rapide local

Pré-requis :
- dépendances Python installées,
- Docker disponible,
- variables d’environnement configurées (.env).

Lancer les services :

```bash
make mlflow_up
make inference_up
```

Vérifier :

```bash
curl http://localhost:5000
curl http://localhost:8000/health
curl http://localhost:8000/
```

Documentation API :
- http://localhost:8000/docs

## 5) Entraînement du modèle

En local :

```bash
make mlops_train
```

En orchestration :
- DAG : text_classification_train
- Fréquence : hebdomadaire (dimanche)
- Source de données : BigQuery (historique interventions)

## 6) API d’inférence

Endpoints principaux :
- GET /health
- GET /
- GET /labels
- POST /predict
- POST /predict/single
- GET /docs

Exemple batch :

```bash
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"texts": ["La santé publique est prioritaire", "Le budget de la défense augmente"], "return_confidence": true}'
```

## 7) Monitoring et qualité

### Suivi
- Tracking d’entraînement : MLflow.
- Journalisation prédictions : BigQuery (table model_predictions).
- Détection de dérive : analyses BigQuery/BI sur les prédictions historisées.

### Indicateurs cibles (ordre de grandeur)
- Accuracy : ~0.75+
- F1 : ~0.70+
- Latence inférence CPU : ~50 ms / texte (selon charge)

## 8) Commandes utiles

```bash
# Training
make mlops_train

# MLflow
make mlflow_up
make mlflow_down
make mlflow_logs

# Inference
make inference_up
make inference_down
make inference_logs

# Build / Deploy
make build_inference_image
make push_inference_image
make inference_deploy

# Tests rapides
make mlops_test_predict
make mlops_test_classify
```

## 9) Configuration minimale

Variables importantes :
- MLOPS_PRETRAINED_MODEL
- MLOPS_MAX_LENGTH
- MLOPS_BATCH_SIZE
- MLOPS_NUM_EPOCHS
- MLFLOW_TRACKING_URI
- INFERENCE_HOST
- INFERENCE_PORT
- MODEL_PATH
- USE_GPU

## 10) Incidents connus et correctifs appliqués

### API inaccessible sur localhost:8000 (corrigé)
Cause : commande de démarrage du conteneur d’inférence invalide.

Correctifs appliqués :
- Commande de lancement explicite via uvicorn.
- Ajout de curl dans l’image d’inférence pour le healthcheck.
- Vérification de réponse HTTP 200 sur la racine de l’API.

## 11) Checklist opérationnelle

- MLflow répond sur : http://localhost:5000
- Inference répond sur : http://localhost:8000/health
- Swagger disponible : http://localhost:8000/docs
- Prédiction batch valide sur /predict
- DAG Airflow présent : text_classification_train

## 12) Résumé exécutif

L’intégration MLOps est opérationnelle de bout en bout :
- ingestion données BigQuery,
- entraînement orchestré,
- tracking MLflow,
- service d’inférence FastAPI,
- monitoring des prédictions.

Ce fichier est la référence synthétique unique pour l’usage quotidien.
