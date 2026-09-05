# Diabetic Retinopathy Screening Pipeline

**Automated DR screening for rural Indian primary healthcare centres**

A MATLAB-based retinal image analysis pipeline that provides end-to-end diabetic retinopathy detection, grading, and explainable clinical reporting — designed for telemedicine deployment in resource-limited settings.

---

## Features

| Module | Capability |
|--------|-----------|
| **Quality Assessment** | Automated image quality evaluation (focus, illumination, FOV); CLAHE + denoising enhancement; recapture feedback in English & Hindi |
| **Retinal Segmentation** | Optic disc/fovea localization, vessel segmentation, microaneurysm detection, exudate segmentation, hemorrhage classification, neovascularization detection |
| **DR Grading** | International Clinical DR Scale (Levels 0–4); hybrid clinical + deep learning features; ≥90% sensitivity / ≥85% specificity for referable DR |
| **Explainability** | Grad-CAM attention maps, lesion-level evidence, calibrated confidence scores, annotated PDF reports (< 30 sec ophthalmologist review) |
| **Workflow Simulation** | Simulink/SimEvents model for district-level telemedicine resource optimization (100K+ patients/year) |

## Requirements

### MATLAB Toolboxes
- Image Processing Toolbox
- Computer Vision Toolbox
- Deep Learning Toolbox
- Medical Imaging Toolbox
- Statistics and Machine Learning Toolbox
- Simulink (with SimEvents)
- Parallel Computing Toolbox (recommended for GPU training)

### Datasets
- [IDRiD](https://ieee-dataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid)
- [APTOS 2019](https://www.kaggle.com/c/aptos2019-blindness-detection)
- [EyePACS](https://www.kaggle.com/c/diabetic-retinopathy-detection)
- [Messidor-2](https://www.adcis.net/en/third-party/messidor2/)
- [DIARETDB1](https://www.it.lut.fi/project/imageret/diaretdb1/)

## Quick Start

```matlab
% 1. Clone the repository and navigate to it
cd('d:\sih_project');

% 2. Initialize the pipeline
startup;

% 3. Run the demo on a sample image
demo;

% 4. Process a single image
result = runDRScreening('path/to/fundus_image.jpg');
fprintf('DR Grade: %d | Confidence: %.1f%%\n', result.grade, result.confidence*100);

% 5. Batch processing
batchProcessImages('data/raw/idrid/images/', 'results/reports/');
```

## Architecture

```
Raw Image → Quality Gate → Enhancement → Segmentation → Feature Fusion → DR Grading → Explainability → Report
                                              ↓
                                    Optic Disc | Fovea | Vessels | MA | Exudates | Hemorrhages | NV
```

## Performance Targets

| Metric | Target | Status |
|--------|--------|--------|
| Referable DR Sensitivity | ≥ 90% | 🔲 |
| Referable DR Specificity | ≥ 85% | 🔲 |
| 5-Class Quadratic Kappa | ≥ 0.80 | 🔲 |
| Pipeline AUC vs. Baseline | Hybrid > Single | 🔲 |
| Processing Time | < 60 sec/image (GPU) | 🔲 |

## Documentation

- [Installation Guide](docs/installation_guide.md)
- [User Manual](docs/user_manual.md)
- [API Reference](docs/api_reference.md)
- [Deployment Notes](docs/deployment_notes.md)

## License

This project is developed for the Smart India Hackathon (SIH) 2026.
