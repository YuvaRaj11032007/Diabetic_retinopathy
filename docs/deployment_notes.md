# Deployment Notes

## Target Deployment
Rural Indian Primary Health Centres (PHCs) via telemedicine.

## Hardware Specifications for Field Units
- **Camera**: Handheld or tabletop fundus camera (e.g., Remidio).
- **Tablet**: Android/Windows tablet, 10-inch screen.
- **Network**: 4G/3G connectivity.

## Server Requirements
- **GPU Specs**: NVIDIA T4 or better for inference.
- **Storage**: Minimum 1TB SSD for logging and anonymized image storage.

## Network Requirements
- **Minimum Bandwidth**: 1 Mbps.
- **Offline Capability**: The pipeline can run locally on capable field units and sync when online.

## Data Privacy Compliance
Fully compliant with the Digital Personal Data Protection (DPDP) Act. All images are anonymized before leaving the field unit.

## Maintenance and Update Procedures
Over-the-air (OTA) updates deployed securely via authenticated API endpoints.

## Training for Field Operators
1-day training module provided for ASHA/health workers on image capture and application usage.

## Integration with ABDM
Integrated with the Ayushman Bharat Digital Mission via FHIR HL7 standards for sharing health records.
