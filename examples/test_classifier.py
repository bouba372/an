"""Sample script to test the text classifier."""

if __name__ == "__main__":
    from mlops.models.classifier import TextClassifier

    # Example interventions from French National Assembly
    test_texts = [
        "La politique de santé publique doit être renforcée pour les populations fragiles.",
        "Le budget de la défense augmente en raison des tensions géopolitiques.",
        "L'éducation est un pilier fondamental pour l'avenir des jeunes français.",
        "La croissance économique dépend de la consommation interne.",
        "La protection de l'environnement est une priorité climatique.",
        "La justice doit être plus accessible à tous les citoyens.",
        "Le transport ferroviaire nécessite des investissements importants.",
        "La culture française est un bien à préserver.",
        "Les finances publiques doivent être mieux gérées.",
    ]

    print("=" * 60)
    print("ParlemAN Text Classification Demo")
    print("=" * 60)

    # Load classifier (with pretrained model if no fine-tuned model exists)
    classifier = TextClassifier()

    # Single prediction
    print("\n1. Single Prediction Example:")
    print("-" * 60)
    result = classifier.predict(test_texts[0])
    print(f"Text: {result['text']}")
    print(f"Category: {result['label']}")
    print(f"Confidence: {result.get('confidence', 'N/A'):.2%}")

    # Batch prediction
    print("\n2. Batch Predictions:")
    print("-" * 60)
    results = classifier.predict_batch(test_texts[:5])
    for i, result in enumerate(results, 1):
        print(
            f"{i}. {result['label'].upper():15} "
            f"(confidence: {result.get('confidence', 0):.1%})"
        )

    print("\n" + "=" * 60)
    print("Demo complete!")
    print("=" * 60)
