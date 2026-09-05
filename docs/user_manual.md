# User Manual

## Quick Start Guide
Run the screening pipeline on a single image using the `demo.m` script or programmatically via `runDRScreening`.

## Single Image Processing Walkthrough
1. Load image using `imread`.
2. Pass to `runDRScreening`:
   ```matlab
   img = imread('test_fundus.png');
   result = runDRScreening(img);
   disp(result);
   ```

## Batch Processing Guide
Process a directory of images:
```matlab
results = batchProcessImages('path/to/images');
```

## Reading Reports Guide
The generated reports contain the overall DR grade (0-4), probability of referable DR, and localized regions of interest (MA, Hemorrhages).

## Quality Assessment Interpretation
- **Accept**: Image quality is sufficient for grading.
- **Reject**: Image is too blurry, overexposed, or underexposed. The system will provide a reason code and feedback (e.g., in Hindi/English).

## DR Grading Explanation
- 0: No DR
- 1: Mild Non-Proliferative DR (NPDR)
- 2: Moderate NPDR
- 3: Severe NPDR
- 4: Proliferative DR (PDR)

## Simulink Simulation Usage
Open the `models/dr_pipeline.slx` file to simulate real-time processing and analyze latency.

## Configuration Options
All configurable parameters are located in the `config/` directory. Modify `config.json` to change thresholds and paths.
