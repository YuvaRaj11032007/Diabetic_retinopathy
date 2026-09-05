%SIMULINK_PARAMS System parameters for the DR Telemedicine Pipeline simulation.
%   SIMULINK_PARAMS defines all operational, acquisition, networking,
%   AI server processing, clinical review, and target parameters for the
%   Diabetic Retinopathy (DR) Telemedicine Screening Pipeline Simulink/SimEvents
%   discrete-event simulation model (Task T-29).
%
%   All parameters are instantiated in the caller workspace as individual
%   variables for direct Simulink block dialog referencing, and aggregated
%   inside the 'simParams' container struct for structured programmatic access.
%
%   Usage:
%       >> simulink_params;
%
%   Workspace Variables Created:
%       Patient Flow:
%           numCentres                  - Number of district-level screening centres (350)
%           dailyPatientsPerCentre      - Camp target patient intake throughput (300)
%           patientArrivalDistribution  - Inter-arrival statistical model ('Poisson')
%           patientArrivalLambda        - Mean daily arrival rate per centre (300)
%           operatingHoursPerDay        - PHC operational hours per day (8)
%           workingDaysPerYear          - Operational working days per year (300)
%
%       Image Acquisition:
%           acquisitionTimePerPatient   - Image capture duration per patient in seconds (120)
%           imagesPerPatient            - Retinal fundus images per patient (2)
%           imageSizeMB                 - High-resolution fundus file size in MB (5)
%           cameraSetupTime             - Patient positioning/disinfection time in seconds (30)
%
%       Network:
%           uploadBandwidthMbps         - Sustained rural uplink bandwidth in Mbps (2)
%           uploadEfficiency            - Protocol transport efficiency factor (0.70)
%           networkDowntimeProbability  - Daily random link failure probability (0.05)
%           networkOutageDurationMin    - Outage duration range in minutes ([15 60])
%
%       Server Processing:
%           qualityAssessmentTimeSec    - Automated quality gate execution time in seconds (2)
%           preprocessingTimeSec        - Enhancement and normalization time in seconds (3)
%           segmentationTimeSec         - Deep multi-lesion segmentation time in seconds (15)
%           gradingTimeSec              - IC-DR classification time in seconds (5)
%           explainabilityTimeSec       - Grad-CAM and PDF compilation time in seconds (5)
%           totalProcessingTimeSec      - Total pipeline AI execution time in seconds (30)
%           numGPUServers               - Regional cluster enterprise GPU servers (4)
%           serverUtilizationCap        - Maximum design server load factor (0.85)
%
%       Review:
%           reviewTimeNormalSec         - Clinician review time for non-referable DR in seconds (30)
%           reviewTimeReferableSec      - Clinician review time for referable DR in seconds (120)
%           referableRate               - Expected cohort referable DR prevalence (0.25)
%           numOphthalmologists         - Central reading hub ophthalmologist count (5)
%           ophthalmologistAvailabilityHours - Tele-reporting hours per clinician per day (6)
%
%       Targets:
%           targetPatientsPerYear       - Annual district screening target (100000)
%           targetTurnaroundHours       - Maximum report turnaround time SLA in hours (24)
%           targetSensitivity           - Minimum referable DR sensitivity (0.90)
%           targetSpecificity           - Minimum referable DR specificity (0.85)
%
%       Struct Output:
%           simParams                   - Unified configuration structure containing
%                                         all parameter groups, derived metrics,
%                                         and summary tables.
%
%   See also: startup, demo, runDRScreening

% -------------------------------------------------------------------------
%   Diabetic Retinopathy Screening Pipeline — Telemedicine Simulation
%   Task T-29: Simulink System Parameters Definition
%   Target: MATLAB R2024b+ / Simulink / SimEvents
% -------------------------------------------------------------------------

fprintf('========================================================================================\n');
fprintf('  Initializing Diabetic Retinopathy Telemedicine Simulation Parameters (Task T-29)\n');
fprintf('========================================================================================\n\n');

%% ========================================================================
%  1. PATIENT FLOW PARAMETERS
%  ========================================================================
%  Models patient arrival dynamics at rural Primary Health Centres (PHCs)
%  and Ayushman Bharat Health & Wellness Centres (AB-HWCs).

% Number of district-level screening centres / PHCs in the network
% Justification: Typical administrative district healthcare cluster under
% the National Programme for Prevention and Control of Cancer, Diabetes,
% CVD and Stroke (NPCDCS) / AB-HWC network in high-burden Indian states.
numCentres = 350; % [count]

% Screening camp throughput per active centre per day
% Justification: Based on Aravind Eye Care System and Sankara Nethralaya
% high-volume community diabetic eye screening outreach camp workflows
% (Raman et al., Indian J Ophthalmol 2016).
dailyPatientsPerCentre = 300; % [patients/day/centre]

% Statistical distribution governing patient inter-arrival times
% Justification: Community camp arrivals follow an uncoordinated Poisson
% arrival process with exponential inter-arrival times (M/M/c queueing model).
patientArrivalDistribution = 'Poisson';

% Mean arrival rate parameter (lambda) per centre per day
% Justification: Derived directly from the daily camp intake target.
patientArrivalLambda = 300; % [patients/day/centre]

% Operational hours per screening day at each PHC
% Justification: Standard rural Primary Health Centre outpatient clinic
% shift (09:00 to 17:00 IST) per Indian Public Health Standards (IPHS).
operatingHoursPerDay = 8; % [hours/day]

% Annual working days for public screening operations
% Justification: Standard working calendar for government health initiatives
% (52 weeks x 6 days minus gazetted national and regional public holidays).
workingDaysPerYear = 300; % [days/year]


%% ========================================================================
%  2. IMAGE ACQUISITION PARAMETERS
%  ========================================================================
%  Models patient preparation, alignment, bilateral fundus image capture,
%  and infection control turnaround at the field camera workstation.

% Image acquisition duration per patient (bilateral capture)
% Justification: 120 seconds covers patient chair positioning, chin-rest
% alignment, optical fixation target adjustment, and dual-eye imaging
% using validated portable non-mydriatic cameras (e.g. Remidio NM-FOP,
% Forus 3nethra) operated by trained technicians (Prathiba et al., Eye 2020).
acquisitionTimePerPatient = 120; % [seconds/patient]

% Retinal fundus photographs captured per patient
% Justification: Bilateral screening protocol (1 disc/macula-centered 45°
% field per eye) standardized by WHO Diabetic Retinopathy Screening
% Guidelines and the All India Ophthalmological Society (AIOS).
imagesPerPatient = 2; % [images/patient]

% Uncompressed/lossless high-resolution fundus image file size
% Justification: Standard 2048 x 1536 (3.1 MP) to 3072 x 2048 (6.3 MP)
% 24-bit RGB fundus images stored in PNG or high-quality DICOM/JPEG format.
imageSizeMB = 5; % [MB/image]

% Workstation sanitization and camera preparation time between patients
% Justification: Chin-rest and forehead-band alcohol wipe disinfection,
% disposable lens guard check, and patient handoff (National Patient Safety
% and Infection Prevention Protocols in Ophthalmic Practice).
cameraSetupTime = 30; % [seconds/patient]


%% ========================================================================
%  3. NETWORK & TELEMEDICINE TRANSMISSION PARAMETERS
%  ========================================================================
%  Models rural telecommunications constraints, cellular backhaul jitter,
%  and intermittent link interruptions.

% Typical sustained uplink bandwidth for rural health centres
% Justification: Median sustained 4G mobile data / BharatNet optical fiber
% uplink speeds measured across Tier-3 and rural gram panchayat health
% facilities (TRAI Rural QoS Assessment Reports).
uploadBandwidthMbps = 2; % [Mbps]

% Effective network transport protocol efficiency
% Justification: Factor of 0.70 accounts for TCP slow-start dynamics,
% TLS/SSL cryptographic handshake overhead, HTTP multipart encoding,
% and wireless packet retransmissions in high-latency rural cells.
uploadEfficiency = 0.70; % [dimensionless fraction]

% Probability of network link interruption on any given day/session
% Justification: 5% daily failure rate reflecting rural grid power cuts,
% local substation maintenance, or cellular backhaul link degradation.
networkDowntimeProbability = 0.05; % [probability 0-1]

% Duration range of network link outages
% Justification: Rural power cuts or generator cutover cycles typically
% last between 15 and 60 minutes before backup restoration or failover.
networkOutageDurationMin = [15, 60]; % [minutes, min-max range]


%% ========================================================================
%  4. SERVER PROCESSING PIPELINE PARAMETERS (GPU CLUSTER)
%  ========================================================================
%  Models automated multi-stage deep learning execution in regional cloud
%  or state health datacenter GPU servers.

% Automated image quality assessment gate execution time
% Justification: Lightweight CNN evaluating illumination uniformity, focus
% sharpness, field-of-view completeness, and media opacity artifacts.
qualityAssessmentTimeSec = 2; % [seconds/image]

% Image enhancement and normalization preprocessing time
% Justification: Green-channel extraction, Contrast-Limited Adaptive
% Histogram Equalization (CLAHE), illumination gradient correction, and resizing.
preprocessingTimeSec = 3; % [seconds/image]

% Multi-task deep semantic segmentation execution time
% Justification: High-resolution UNet/HRNet architectures segmenting optic
% disc, fovea, retinal vasculature, microaneurysms, hemorrhages, hard/soft
% exudates, and neovascularization (Raman et al., IEEE TMI 2021).
segmentationTimeSec = 15; % [seconds/image]

% Automated DR classification and clinical severity grading time
% Justification: Deep ensemble feature extraction and classification across
% International Clinical Diabetic Retinopathy (IC-DR) Levels 0 to 4.
gradingTimeSec = 5; % [seconds/image]

% Explainability synthesis and clinical report generation time
% Justification: Computation of Grad-CAM gradient saliency maps, lesion
% mask overlay generation, confidence interval calibration, and PDF assembly.
explainabilityTimeSec = 5; % [seconds/image]

% Total AI pipeline execution time per patient/image
% Justification: Exact analytical sum of sequential pipeline stages:
% 2s (QA) + 3s (Preproc) + 15s (Seg) + 5s (Grade) + 5s (XAI) = 30s.
totalProcessingTimeSec = qualityAssessmentTimeSec + preprocessingTimeSec + ...
    segmentationTimeSec + gradingTimeSec + explainabilityTimeSec; % [seconds]
assert(totalProcessingTimeSec == 30, 'DRPipeline:simulink_params:invalidSum', ...
    'Total processing time must equal 30 seconds.');

% Number of enterprise GPU servers in the central processing cluster
% Justification: Sized for district-level parallel ingestion with high-availability
% redundancy (e.g., 4 x NVIDIA A100 / L40S enterprise GPU nodes).
numGPUServers = 4; % [servers]

% Maximum design GPU cluster utilization cap
% Justification: 85% utilization ceiling prevents exponential queue growth
% and high latency tail under M/G/c queueing theory during peak arrival bursts.
serverUtilizationCap = 0.85; % [fraction 0-1]


%% ========================================================================
%  5. CLINICAL HUMAN REVIEW CAPACITY PARAMETERS
%  ========================================================================
%  Models tele-ophthalmologist review triage, verification, and referral
%  workstation throughput at the central reading center.

% Clinician review duration for normal / non-referable examinations
% Justification: Rapid confirmation scan of normal macula and disc for
% IC-DR Grade 0 (No DR) or mild non-referable cases with AI negative confirmation.
reviewTimeNormalSec = 30; % [seconds/case]

% Clinician review duration for referable diabetic retinopathy examinations
% Justification: Detailed evaluation for IC-DR Grade 2+ (Moderate/Severe NPDR,
% PDR, or DME), examining lesion overlays, confirming severity, and formulating
% clinical referral instructions (Rema et al., Br J Ophthalmol 2005).
reviewTimeReferableSec = 120; % [seconds/case]

% Expected prevalence of referable DR in screened diabetic population
% Justification: Validated in Indian epidemiological studies: Sankara
% Nethralaya Diabetic Retinopathy Epidemiology and Molecular Genetic Study
% (SN-DREAMS I & II: 18.0% - 28.2%) and CURES Cohort (approx. 25.0%).
referableRate = 0.25; % [fraction 0-1]

% Number of licensed ophthalmologists staffed at the reading center
% Justification: Dedicated reading team sized to comfortably triage the
% regional screening volume while accommodating rotation and clinical duties.
numOphthalmologists = 5; % [clinicians]

% Daily tele-screening reading hours dedicated per ophthalmologist
% Justification: 6 hours daily allocated to digital reading queues, leaving
% 2 hours for in-person consultations, complex case reviews, or surgery.
ophthalmologistAvailabilityHours = 6; % [hours/day/clinician]


%% ========================================================================
%  6. CLINICAL & OPERATIONAL TARGETS (KPIs)
%  ========================================================================
%  Defines the overarching health mission requirements and diagnostic
%  accuracy thresholds mandated for public healthcare deployment.

% Annual target patient screening volume
% Justification: Mandated regional screening throughput across the district
% population under the National Health Mission / NPCDCS diabetic eye care mandate.
targetPatientsPerYear = 100000; % [patients/year]

% Maximum allowable report turnaround time Service Level Agreement (SLA)
% Justification: Telemedicine clinical standard ensuring patient receives
% verified report, counseling, and referral within 24 hours of examination.
targetTurnaroundHours = 24; % [hours]

% Minimum diagnostic sensitivity for referable diabetic retinopathy
% Justification: Clinical safety benchmark established by the British
% Diabetic Association (BDA), UK NHS DESP, and WHO guidelines (>= 90%).
targetSensitivity = 0.90; % [sensitivity fraction >= 0.90]

% Minimum diagnostic specificity for referable diabetic retinopathy
% Justification: Health economics benchmark to prevent over-burdening
% tertiary ophthalmic hospitals with false positive referrals (>= 85%).
targetSpecificity = 0.85; % [specificity fraction >= 0.85]


%% ========================================================================
%  7. DERIVED OPERATIONAL & QUEUEING METRICS
%  ========================================================================
%  Analytical metrics computed for queueing analysis, bandwidth planning,
%  and Simulink SimEvents entity generation rates.

% Effective upload bandwidth after transport protocol efficiency
effectiveBandwidthMbps = uploadBandwidthMbps * uploadEfficiency; % [Mbps] (1.4 Mbps)

% Total uncompressed data generated per patient across both eyes
totalDataPerPatientMB = imagesPerPatient * imageSizeMB; % [MB] (10 MB = 80 Mbits)

% Mean transmission duration per patient over rural cellular uplink
uploadTimePerPatientSec = (totalDataPerPatientMB * 8) / effectiveBandwidthMbps; % [seconds] (~57.14 s)

% Mean patient arrival rate per operating hour during active camp day
patientArrivalRatePerHour = dailyPatientsPerCentre / operatingHoursPerDay; % [patients/hour/centre] (37.5)

% Mean patient arrival rate per second at each active centre
patientArrivalRatePerSec = patientArrivalRatePerHour / 3600; % [patients/sec/centre] (~0.01042)

% Total acquisition workstation cycle time per patient (capture + setup)
acquisitionCycleTimePerPatientSec = acquisitionTimePerPatient + cameraSetupTime; % [seconds] (150 s)

% Maximum theoretical patient throughput per camera booth per 8-hour shift
boothMaxDailyThroughput = floor((operatingHoursPerDay * 3600) / acquisitionCycleTimePerPatientSec); % [patients/booth/day] (192)

% Weighted average ophthalmologist review time per patient
expectedReviewTimeSec = (1 - referableRate) * reviewTimeNormalSec + ...
                        referableRate * reviewTimeReferableSec; % [seconds/patient] (52.5 s)

% Processing capacity of the 4-node GPU server cluster
gpuClusterCapacityPerSec = numGPUServers / totalProcessingTimeSec; % [patients/sec] (0.1333)
gpuClusterCapacityPerHour = gpuClusterCapacityPerSec * 3600; % [patients/hour] (480)
gpuClusterMaxDailyPatients = gpuClusterCapacityPerHour * operatingHoursPerDay * serverUtilizationCap; % [patients/day] (3,264)

% Total daily tele-ophthalmology review capacity across 5 specialists
totalOphthalHoursDaily = numOphthalmologists * ophthalmologistAvailabilityHours; % [clinician-hours/day] (30)
ophthalmologistDailyCapacityPatients = floor((totalOphthalHoursDaily * 3600) / expectedReviewTimeSec); % [patients/day] (2,057)

% Required steady-state daily screening rate to meet 100k annual mandate
requiredDailyScreeningRate = targetPatientsPerYear / workingDaysPerYear; % [patients/day] (333.33)

% Annual screening capacity of reading centre at nominal availability
annualReadingCenterCapacity = ophthalmologistDailyCapacityPatients * workingDaysPerYear; % [patients/year] (617,100)


%% ========================================================================
%  8. STRUCTURED PARAMETER CONTAINER ('simParams')
%  ========================================================================
%  Store all parameters in hierarchical sub-structs and provide top-level
%  aliases for seamless integration across Simulink and MATLAB scripts.

simParams = struct();

% 8.1 Patient Flow
simParams.patientFlow = struct(...
    'numCentres', numCentres, ...
    'dailyPatientsPerCentre', dailyPatientsPerCentre, ...
    'patientArrivalDistribution', patientArrivalDistribution, ...
    'patientArrivalLambda', patientArrivalLambda, ...
    'operatingHoursPerDay', operatingHoursPerDay, ...
    'workingDaysPerYear', workingDaysPerYear ...
);

% 8.2 Image Acquisition
simParams.acquisition = struct(...
    'acquisitionTimePerPatient', acquisitionTimePerPatient, ...
    'imagesPerPatient', imagesPerPatient, ...
    'imageSizeMB', imageSizeMB, ...
    'cameraSetupTime', cameraSetupTime, ...
    'totalCycleTimeSec', acquisitionCycleTimePerPatientSec, ...
    'boothCapacityPerDay', boothMaxDailyThroughput ...
);

% 8.3 Network Transmission
simParams.network = struct(...
    'uploadBandwidthMbps', uploadBandwidthMbps, ...
    'uploadEfficiency', uploadEfficiency, ...
    'effectiveBandwidthMbps', effectiveBandwidthMbps, ...
    'totalDataMB', totalDataPerPatientMB, ...
    'uploadTimeSec', uploadTimePerPatientSec, ...
    'networkDowntimeProbability', networkDowntimeProbability, ...
    'networkOutageDurationMin', networkOutageDurationMin ...
);

% 8.4 Server Processing
simParams.server = struct(...
    'qualityAssessmentTimeSec', qualityAssessmentTimeSec, ...
    'preprocessingTimeSec', preprocessingTimeSec, ...
    'segmentationTimeSec', segmentationTimeSec, ...
    'gradingTimeSec', gradingTimeSec, ...
    'explainabilityTimeSec', explainabilityTimeSec, ...
    'totalProcessingTimeSec', totalProcessingTimeSec, ...
    'numGPUServers', numGPUServers, ...
    'serverUtilizationCap', serverUtilizationCap, ...
    'clusterCapacityPerHour', gpuClusterCapacityPerHour, ...
    'clusterMaxDailyPatients', gpuClusterMaxDailyPatients ...
);

% 8.5 Clinical Review
simParams.review = struct(...
    'reviewTimeNormalSec', reviewTimeNormalSec, ...
    'reviewTimeReferableSec', reviewTimeReferableSec, ...
    'referableRate', referableRate, ...
    'expectedReviewTimeSec', expectedReviewTimeSec, ...
    'numOphthalmologists', numOphthalmologists, ...
    'ophthalmologistAvailabilityHours', ophthalmologistAvailabilityHours, ...
    'totalDailyClinicianHours', totalOphthalHoursDaily, ...
    'ophthalmologistDailyCapacity', ophthalmologistDailyCapacityPatients ...
);

% 8.6 Targets & Benchmarks
simParams.targets = struct(...
    'targetPatientsPerYear', targetPatientsPerYear, ...
    'targetTurnaroundHours', targetTurnaroundHours, ...
    'targetSensitivity', targetSensitivity, ...
    'targetSpecificity', targetSpecificity, ...
    'requiredDailyRate', requiredDailyScreeningRate ...
);

% 8.7 Derived Metrics
simParams.derived = struct(...
    'effectiveBandwidthMbps', effectiveBandwidthMbps, ...
    'totalDataPerPatientMB', totalDataPerPatientMB, ...
    'uploadTimePerPatientSec', uploadTimePerPatientSec, ...
    'patientArrivalRatePerHour', patientArrivalRatePerHour, ...
    'patientArrivalRatePerSec', patientArrivalRatePerSec, ...
    'acquisitionCycleTimePerPatientSec', acquisitionCycleTimePerPatientSec, ...
    'boothMaxDailyThroughput', boothMaxDailyThroughput, ...
    'expectedReviewTimeSec', expectedReviewTimeSec, ...
    'gpuClusterCapacityPerHour', gpuClusterCapacityPerHour, ...
    'gpuClusterMaxDailyPatients', gpuClusterMaxDailyPatients, ...
    'ophthalmologistDailyCapacityPatients', ophthalmologistDailyCapacityPatients, ...
    'requiredDailyScreeningRate', requiredDailyScreeningRate, ...
    'annualReadingCenterCapacity', annualReadingCenterCapacity ...
);

% 8.8 Top-Level Direct Aliases for Simulink Block Compatibility
simParams.numCentres = numCentres;
simParams.dailyPatientsPerCentre = dailyPatientsPerCentre;
simParams.patientArrivalDistribution = patientArrivalDistribution;
simParams.patientArrivalLambda = patientArrivalLambda;
simParams.operatingHoursPerDay = operatingHoursPerDay;
simParams.workingDaysPerYear = workingDaysPerYear;
simParams.acquisitionTimePerPatient = acquisitionTimePerPatient;
simParams.imagesPerPatient = imagesPerPatient;
simParams.imageSizeMB = imageSizeMB;
simParams.cameraSetupTime = cameraSetupTime;
simParams.uploadBandwidthMbps = uploadBandwidthMbps;
simParams.uploadEfficiency = uploadEfficiency;
simParams.networkDowntimeProbability = networkDowntimeProbability;
simParams.networkOutageDurationMin = networkOutageDurationMin;
simParams.qualityAssessmentTimeSec = qualityAssessmentTimeSec;
simParams.preprocessingTimeSec = preprocessingTimeSec;
simParams.segmentationTimeSec = segmentationTimeSec;
simParams.gradingTimeSec = gradingTimeSec;
simParams.explainabilityTimeSec = explainabilityTimeSec;
simParams.totalProcessingTimeSec = totalProcessingTimeSec;
simParams.numGPUServers = numGPUServers;
simParams.serverUtilizationCap = serverUtilizationCap;
simParams.reviewTimeNormalSec = reviewTimeNormalSec;
simParams.reviewTimeReferableSec = reviewTimeReferableSec;
simParams.referableRate = referableRate;
simParams.numOphthalmologists = numOphthalmologists;
simParams.ophthalmologistAvailabilityHours = ophthalmologistAvailabilityHours;
simParams.targetPatientsPerYear = targetPatientsPerYear;
simParams.targetTurnaroundHours = targetTurnaroundHours;
simParams.targetSensitivity = targetSensitivity;
simParams.targetSpecificity = targetSpecificity;


%% ========================================================================
%  9. CONSTRUCT PARAMETER SUMMARY TABLE
%  ========================================================================
%  Generate a MATLAB table object containing all system parameters,
%  their configured values, units of measurement, and clinical/operational citations.

paramNames = {
    'numCentres';
    'dailyPatientsPerCentre';
    'patientArrivalDistribution';
    'patientArrivalLambda';
    'operatingHoursPerDay';
    'workingDaysPerYear';
    'acquisitionTimePerPatient';
    'imagesPerPatient';
    'imageSizeMB';
    'cameraSetupTime';
    'uploadBandwidthMbps';
    'uploadEfficiency';
    'networkDowntimeProbability';
    'networkOutageDurationMin';
    'qualityAssessmentTimeSec';
    'preprocessingTimeSec';
    'segmentationTimeSec';
    'gradingTimeSec';
    'explainabilityTimeSec';
    'totalProcessingTimeSec';
    'numGPUServers';
    'serverUtilizationCap';
    'reviewTimeNormalSec';
    'reviewTimeReferableSec';
    'referableRate';
    'numOphthalmologists';
    'ophthalmologistAvailabilityHours';
    'targetPatientsPerYear';
    'targetTurnaroundHours';
    'targetSensitivity';
    'targetSpecificity'
};

paramCategories = {
    'Patient Flow';
    'Patient Flow';
    'Patient Flow';
    'Patient Flow';
    'Patient Flow';
    'Patient Flow';
    'Image Acquisition';
    'Image Acquisition';
    'Image Acquisition';
    'Image Acquisition';
    'Network';
    'Network';
    'Network';
    'Network';
    'Server Processing';
    'Server Processing';
    'Server Processing';
    'Server Processing';
    'Server Processing';
    'Server Processing';
    'Server Processing';
    'Server Processing';
    'Review';
    'Review';
    'Review';
    'Review';
    'Review';
    'Targets';
    'Targets';
    'Targets';
    'Targets'
};

paramValues = {
    '350';
    '300';
    'Poisson';
    '300';
    '8';
    '300';
    '120';
    '2';
    '5';
    '30';
    '2';
    '0.70';
    '0.05';
    '[15, 60]';
    '2';
    '3';
    '15';
    '5';
    '5';
    '30';
    '4';
    '0.85';
    '30';
    '120';
    '0.25';
    '5';
    '6';
    '100000';
    '24';
    '0.90';
    '0.85'
};

paramUnits = {
    'centres';
    'patients/day';
    'distribution';
    'patients/day';
    'hours/day';
    'days/year';
    'seconds/patient';
    'images/patient';
    'MB/image';
    'seconds/patient';
    'Mbps';
    'fraction';
    'probability';
    'minutes';
    'seconds/image';
    'seconds/image';
    'seconds/image';
    'seconds/image';
    'seconds/image';
    'seconds/patient';
    'servers';
    'fraction';
    'seconds/case';
    'seconds/case';
    'fraction';
    'clinicians';
    'hours/day';
    'patients/year';
    'hours';
    'fraction';
    'fraction'
};

paramJustifications = {
    'District PHC / AB-HWC network density (NPCDCS / MoHFW)';
    'High-volume screening outreach camp throughput (Aravind / Sankara Nethralaya)';
    'Uncoordinated walk-in community camp arrivals (M/M/c queueing theory)';
    'Mean daily camp arrival rate (37.5 patients/hour over 8 hours)';
    'Standard rural PHC outpatient operating shift (IPHS guidelines)';
    'Public health program operating calendar (52 wks x 6 days - public holidays)';
    'Bilateral non-mydriatic camera alignment and capture (Prathiba et al., Eye 2020)';
    'Standard 45-degree disc/macula-centered bilateral protocol (WHO / AIOS)';
    'High-res 2048x1536 24-bit fundus photographic file size';
    'Chin-rest sanitization and patient handoff (Infection Prevention Protocol)';
    'Rural 4G mobile / BharatNet optical uplink sustained speed (TRAI QoS reports)';
    'Transport protocol overhead, TCP slow-start, TLS, and cellular packet loss';
    'Rural grid load shedding, power instability, and wireless link dropouts';
    'Typical rural backup generator switchover and base station restoration window';
    'Automated focus, illumination, and artifact CNN validation gate';
    'Green-channel CLAHE contrast normalization and standardization';
    'Deep multi-task UNet segmentation of lesions and retinal landmarks';
    'Deep ensemble classification across IC-DR Levels 0-4';
    'Grad-CAM saliency synthesis, lesion mask overlay, and PDF report assembly';
    'Full sequential pipeline AI execution budget (2 + 3 + 15 + 5 + 5 = 30 sec)';
    'Enterprise datacenter GPU cluster sizing (e.g. 4x NVIDIA A100/L40S)';
    'Safe utilization cap to avoid queue blowup under M/G/c queueing dynamics';
    'Clinician rapid scan of AI-confirmed normal retina (Grade 0 / Mild Grade 1)';
    'Comprehensive clinician review of referable DR with lesion overlays (Grade 2+)';
    'Prevalence of referable DR in rural Indian diabetic cohorts (SN-DREAMS / CURES)';
    'Central tele-reading center ophthalmologist specialist staffing';
    'Daily tele-reporting allocation per specialist (allowing 2 hrs clinic/surgery)';
    'Mandated annual district screening volume (National Health Mission)';
    'Telemedicine maximum turnaround SLA from image upload to verified report';
    'Minimum referable DR sensitivity safety benchmark (BDA / WHO standards >= 90%)';
    'Minimum referable DR specificity benchmark to prevent referral overload (>= 85%)'
};

summaryTable = table(paramCategories, paramNames, paramValues, paramUnits, paramJustifications, ...
    'VariableNames', {'Category', 'ParameterName', 'Value', 'Unit', 'Justification'});

simParams.table = summaryTable;


%% ========================================================================
%  10. DISPLAY FORMATTED PARAMETER SUMMARY TABLE
%  ========================================================================
printSimulinkParameterSummary(summaryTable, simParams);

fprintf('Parameter setup complete. Variables and ''simParams'' struct ready in workspace.\n\n');


%% ========================================================================
%  LOCAL HELPER FUNCTION: PRINT PARAMETER SUMMARY
%  ========================================================================
function printSimulinkParameterSummary(paramTable, params)
    %PRINTSIMULINKPARAMETERSUMMARY Formats and outputs the parameter table to CLI.
    %   Displays an aligned ASCII table of all pipeline parameters and
    %   key derived metrics for verification.
    %
    %   Syntax:
    %       printSimulinkParameterSummary(paramTable, params)
    %
    %   Inputs:
    %       paramTable - MATLAB table containing parameter definitions
    %       params     - Struct containing the simParams container
    %
    %   Example:
    %       printSimulinkParameterSummary(simParams.table, simParams);

    arguments
        paramTable (:, 5) table
        params (1, 1) struct
    end

    dividerLine = repmat('=', 1, 115);
    sectionLine = repmat('-', 1, 115);

    fprintf('%s\n', dividerLine);
    fprintf('  DIABETIC RETINOPATHY TELEMEDICINE PIPELINE — SIMULINK SIMULATION PARAMETERS (Task T-29)\n');
    fprintf('%s\n', dividerLine);
    fprintf('  %-18s %-32s %-12s %-18s %s\n', ...
        'Category', 'Parameter Name', 'Value', 'Unit', 'Justification / Reference');
    fprintf('%s\n', sectionLine);

    currentCategory = '';
    for i = 1:height(paramTable)
        rowCategory = paramTable.Category{i};
        if ~strcmp(rowCategory, currentCategory)
            if i > 1
                fprintf('  %s\n', repmat('.', 1, 111));
            end
            currentCategory = rowCategory;
        end
        fprintf('  %-18s %-32s %-12s %-18s %s\n', ...
            paramTable.Category{i}, ...
            paramTable.ParameterName{i}, ...
            paramTable.Value{i}, ...
            paramTable.Unit{i}, ...
            paramTable.Justification{i});
    end

    fprintf('%s\n', sectionLine);
    fprintf('  KEY DERIVED CAPACITY & QUEUEING METRICS:\n');
    fprintf('%s\n', sectionLine);
    fprintf('  * Effective Uplink Bandwidth         : %.2f Mbps (2 Mbps @ 70%% transport efficiency)\n', ...
        params.derived.effectiveBandwidthMbps);
    fprintf('  * Data Volume per Patient (2 eyes)   : %.1f MB (%d Mbits)\n', ...
        params.derived.totalDataPerPatientMB, params.derived.totalDataPerPatientMB * 8);
    fprintf('  * Mean Upload Duration per Patient   : %.2f seconds (%.1f minutes)\n', ...
        params.derived.uploadTimePerPatientSec, params.derived.uploadTimePerPatientSec / 60);
    fprintf('  * Acquisition Workstation Cycle Time : %d seconds per patient (%d patients max/shift/booth)\n', ...
        params.derived.acquisitionCycleTimePerPatientSec, params.derived.boothMaxDailyThroughput);
    fprintf('  * Mean Clinician Review Time         : %.2f seconds/patient (Weighted: 75%% @ 30s + 25%% @ 120s)\n', ...
        params.derived.expectedReviewTimeSec);
    fprintf('  * GPU Cluster Nominal Throughput     : %d patients/hour (4 servers @ 30s per inference)\n', ...
        params.derived.gpuClusterCapacityPerHour);
    fprintf('  * GPU Cluster Max Daily Intake (@85%%): %d patients/day (8-hour shift)\n', ...
        params.derived.gpuClusterMaxDailyPatients);
    fprintf('  * Reading Centre Daily Capacity      : %d patients/day (5 ophthalmologists @ 6 hrs/day)\n', ...
        params.derived.ophthalmologistDailyCapacityPatients);
    fprintf('  * Required Daily Screening Intake    : %.1f patients/day (to achieve 100k patients/year)\n', ...
        params.derived.requiredDailyScreeningRate);
    fprintf('  * Annual Reading Centre Capacity     : %d patients/year (Coverage factor: %.1fx target)\n', ...
        params.derived.annualReadingCenterCapacity, ...
        params.derived.annualReadingCenterCapacity / params.targets.targetPatientsPerYear);
    fprintf('%s\n\n', dividerLine);
end
