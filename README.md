# SMLM Aberrations Analysis Pipeline

This repository provides an automated pipeline for measuring optical aberrations in Single Molecule Localization Microscopy (SMLM) using TetraSpeck Microspheres. It acts as an automation suite and analysis wrapper for the external aberration measurement app.

## Prerequisites

### 1. External App Installation
- **Third-Party App:** This code serves as an automation wrapper for the **`aberration_measurement_automation`** app.
- **Licensing:** The app itself is an external dependency and is **not published here**. 
- **Setup:** Ensure the app is installed locally in MATLAB. The pipeline scripts (`GUI_automation/`) will call functions from this app via the MATLAB search path.

### 2. MATLAB Path Configuration
You must add the pipeline folders and the extracted app code to your MATLAB path:
```matlab
% Add this pipeline's code
addpath(genpath('C:\path\to\your\smlm-aberrations-analysis'));

% Add the external app's code (example path)
addpath(genpath('C:\Users\...\AppData\Roaming\MathWorks\MATLAB Add-Ons\Apps\AberrationMeasurementAutomationextractedtired'));
```

---

## Workflow Overview

The following diagram illustrates the sequential workflow from raw data to statistical reporting:

![SMLM Aberrations Workflow](Flow_chart_1.png)

---

## Project Structure

### 1. Bead Detection & Cropping (`/beads_cropping`)
This module extracts individual bead regions from whole FOV z-stacks. 

- **Adaptive Thresholding**: Detects beads based on a dynamic intensity threshold calculated as:
  ```matlab
  thresholdValue = meanIntensity + 7 * stdIntensity;
  ```
  *(Note: The multiplier can be adjusted to 2, 7, or 10 depending on noise levels).*

- **Centroid Filtering & Overlap Removal**: 
  To ensure high-quality data, detected beads are filtered based on boundary proximity. If two bead centroids fall within a defined **42x42 pixel ROI** (`roiSize = 42`), both are marked for removal to prevent overlapping signals from biasing the aberration measurement.

- **Output**: 
  - **`Figure_1.tif`**: A summary image showing detected beads overlaid on the full FOV.
  - **`Figure_2.tif`**: A multi-panel display showing the individual 42x42 cropped bead regions with annotations.
  - **MATLAB Table**: Stores centroid coordinates, mean intensities, and radial distances.


### 2. GUI Automation (`/GUI_automation`)
This module contains scripts that programmatically control the external **`aberration_measurement_automation`** app. This eliminates the need for manual GUI interaction and ensures consistent parameter application across large datasets.

- **Programmatic Control**: Scripts simulate user actions by interacting directly with the app object's properties and callbacks (e.g., `app.loadzstackButton.ButtonPushedFcn`).
- **Automated Workflow**: 
  - **Parameter Setup**: Automatically sets emission wavelengths (e.g., `0.525 µm` for blue, `0.685 µm` for red), z-increment (`0.2 µm`), and Zernike order (up to 10th degree).
  - **Fit Execution**: Triggers the 'Calculate Model' and 'Fit' buttons, monitoring the app's state (via the `app.Lamp.Color`) to detect when processing is complete.
  - **PSF Centering**: Automatically executes the centering routine and exports visual previews (`before_centering.png`, `after_centering.png`).
- **Error Handling & Logging**: Includes validation logic to ensure the Zernike structure is consistent and logs errors/warnings (like NaN detection in phase masks) to `aberration_log.txt`.
- **Modes Supported**: Dedicated automation scripts are provided for different hardware configurations:
  - `blue_bypass`, `red_bypass`, `blue_split`, and `red_split`.

### 3. Filtering & Zernike Analysis (`/filtering`)
Aggregates results and applies a Zernike polynomial model to the measured aberrations.

- **Zernike Model**: The analysis utilizes **Zernike polynomials up to the 10th degree**. 
- **Data Structure**: The pipeline prepares an array for **65 terms** (`aberration_names{1:65}`). Specific terms are assigned and filtered based on the first 37-term orthonormal Zernike circle polynomials, following the **Noll indices** as detailed in *Kuo Niu & Chao Tian (2022)*.
- **Workflow**: This step uses `process_all_folders.m` to apply user-defined filters to the raw data, relying on `wrapper_table.m` and `process_folder.m` to map the results into structured tables.

#### Applied Aberration Filters
The pipeline includes specialized filtering scripts to isolate the most significant optical distortions. Each filter selects the **top 50% extreme modes by magnitude** to reduce noise:

| Filter Script | Target Aberrations | Included Modes |
| :--- | :--- | :--- |
| `filter_astigmatism_aberrations.m` | **Astigmatism** | Primary, Secondary, and Tertiary (0° and 45°) |
| `filter_coma_aberrations.m` | **Coma** | Primary, Secondary, and Tertiary (x and y) |
| `filter_spherical_aberrations.m` | **Spherical** | Primary, Secondary, and Tertiary |

- **Dynamic Thresholding**: These filters calculate a `dynamic_thr` based on the median magnitude of the target modes, ensuring that only the most impactful aberrations are carried forward to the plotting and statistics modules.

### 4. Plotting & Statistics (`/plotting`, `/statistics`)
- **Radial Distance Plots**: Visualizes aberration metrics relative to the image center.
- **Statistical Summaries**: Generates binned summaries and exportable data tables.

## 📄 References
- Zernike polynomials basis: *Kuo Niu & Chao Tian (2022), "Zernike polynomials and their applications"*.
```
