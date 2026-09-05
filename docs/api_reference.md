# API Reference

## Module: Utils
### `prepareDataset(inDir, outDir)`
- **Description**: Prepares raw dataset for training.
- **Inputs**: `inDir` (string), `outDir` (string).
- **Outputs**: None.

## Module: Quality
### `extractQualityFeatures(img)`
- **Description**: Extracts image quality metrics.
- **Inputs**: `img` (RGB image matrix).
- **Outputs**: Struct containing brightness, contrast, blur, etc.

## Module: Segmentation
### `runAllSegmentation(img)`
- **Description**: Orchestrates all segmentation tasks (vessels, optic disc, lesions).
- **Inputs**: `img` (matrix).
- **Outputs**: Struct with binary masks and features.

## Module: Grading
### `evaluateDRClassifier(Y, Pred)`
- **Description**: Computes accuracy, AUC, and confusion matrix.
- **Inputs**: Ground truth `Y`, predictions `Pred`.
- **Outputs**: Struct of metrics.

## Module: Pipeline
### `runDRScreening(img)`
- **Description**: End-to-end processing pipeline for a single image.
- **Inputs**: `img` (matrix).
- **Outputs**: Struct containing final grade, probability, and intermediate results.
