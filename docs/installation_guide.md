# Installation Guide

## Prerequisites
- **MATLAB Version**: R2024b or newer.
- **Required Toolboxes**:
  - Image Processing Toolbox
  - Computer Vision Toolbox
  - Deep Learning Toolbox
  - Medical Imaging Toolbox
  - Statistics and Machine Learning Toolbox
  - Simulink

## Step-by-Step Installation

1. **Clone repository**
   ```bash
   git clone https://github.com/org/sih_project.git
   cd sih_project
   ```

2. **Download datasets**
   Ensure you have the Kaggle API installed.
   ```bash
   kaggle datasets download -d abdallahalwaer/aptos2019-blindness-detection
   unzip aptos2019-blindness-detection.zip -d data/raw
   ```

3. **Run startup.m**
   Open MATLAB and run the startup script in the project root:
   ```matlab
   cd d:\sih_project
   startup
   ```

4. **Run data preparation scripts**
   ```matlab
   prepareDataset('data/raw', 'data/processed');
   ```

5. **Train models (or download pre-trained)**
   ```matlab
   trainModels();
   ```

6. **Run demo.m to verify**
   ```matlab
   demo();
   ```

## Troubleshooting
- If encountering memory issues during training, reduce the batch size in `config/training_config.json`.
- Ensure paths are correctly set in `startup.m`.

## Hardware Requirements
- **CPU**: Quad-core Intel or AMD processor, 3.0 GHz or faster.
- **GPU**: NVIDIA GPU with at least 8GB VRAM (Compute Capability 6.0+).
- **RAM**: Minimum 16GB, 32GB recommended.
