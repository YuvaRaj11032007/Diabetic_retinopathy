classdef testSimulinkParams < matlab.unittest.TestCase
    %TESTSIMULINKPARAMS Unit tests for Simulink system parameters definition.
    %   Validates that simulink_params.m defines all expected workspace variables,
    %   populates the simParams structured container, computes derived queueing
    %   metrics accurately, and generates the summary parameter table.
    %
    %   Usage:
    %       results = runtests('testSimulinkParams');
    %
    %   See also: simulink_params, matlab.unittest.TestCase

    properties
        OriginalPath
    end

    methods (TestMethodSetup)
        function addParamsPath(testCase)
            %ADDPARAMSPATH Ensure the simulink params directory is on the path.
            projectRoot = getappdata(0, 'DRPipeline_ProjectRoot');
            if isempty(projectRoot)
                projectRoot = fileparts(fileparts(mfilename('fullpath')));
            end
            paramsDir = fullfile(projectRoot, 'src', 'simulink', 'params');
            testCase.OriginalPath = path;
            addpath(paramsDir);
        end
    end

    methods (TestMethodTeardown)
        function restorePath(testCase)
            %RESTOREPATH Restore the original MATLAB search path.
            path(testCase.OriginalPath);
        end
    end

    methods (Test)
        function testScriptExecution(testCase)
            %TESTSCRIPTEXECUTION Verify script executes cleanly without error.
            testCase.verifyWarningFree(@() simulink_params, ...
                'simulink_params script should execute without warnings or errors.');
        end

        function testPatientFlowParameters(testCase)
            %TESTPATIENTFLOWPARAMETERS Validate patient flow constants.
            simulink_params;
            
            testCase.verifyEqual(numCentres, 350, 'numCentres mismatch');
            testCase.verifyEqual(dailyPatientsPerCentre, 300, 'dailyPatientsPerCentre mismatch');
            testCase.verifyEqual(string(patientArrivalDistribution), "Poisson", 'Arrival distribution mismatch');
            testCase.verifyEqual(patientArrivalLambda, 300, 'Arrival lambda mismatch');
            testCase.verifyEqual(operatingHoursPerDay, 8, 'Operating hours mismatch');
            testCase.verifyEqual(workingDaysPerYear, 300, 'Working days mismatch');
        end

        function testImageAcquisitionParameters(testCase)
            %TESTIMAGEACQUISITIONPARAMETERS Validate image acquisition constants.
            simulink_params;
            
            testCase.verifyEqual(acquisitionTimePerPatient, 120, 'Acquisition time mismatch');
            testCase.verifyEqual(imagesPerPatient, 2, 'Images per patient mismatch');
            testCase.verifyEqual(imageSizeMB, 5, 'Image size mismatch');
            testCase.verifyEqual(cameraSetupTime, 30, 'Camera setup time mismatch');
        end

        function testNetworkParameters(testCase)
            %TESTNETWORKPARAMETERS Validate network & uplink constants.
            simulink_params;
            
            testCase.verifyEqual(uploadBandwidthMbps, 2, 'Upload bandwidth mismatch');
            testCase.verifyEqual(uploadEfficiency, 0.70, 'AbsTol', 1e-6, 'Upload efficiency mismatch');
            testCase.verifyEqual(networkDowntimeProbability, 0.05, 'AbsTol', 1e-6, 'Downtime probability mismatch');
            testCase.verifyEqual(networkOutageDurationMin, [15, 60], 'Outage duration range mismatch');
        end

        function testServerProcessingParameters(testCase)
            %TESTSERVERPROCESSINGPARAMETERS Validate server GPU pipeline constants.
            simulink_params;
            
            testCase.verifyEqual(qualityAssessmentTimeSec, 2, 'QA time mismatch');
            testCase.verifyEqual(preprocessingTimeSec, 3, 'Preprocessing time mismatch');
            testCase.verifyEqual(segmentationTimeSec, 15, 'Segmentation time mismatch');
            testCase.verifyEqual(gradingTimeSec, 5, 'Grading time mismatch');
            testCase.verifyEqual(explainabilityTimeSec, 5, 'Explainability time mismatch');
            testCase.verifyEqual(totalProcessingTimeSec, 30, 'Total processing time mismatch');
            testCase.verifyEqual(numGPUServers, 4, 'Number of GPU servers mismatch');
            testCase.verifyEqual(serverUtilizationCap, 0.85, 'AbsTol', 1e-6, 'Server utilization cap mismatch');
        end

        function testReviewParameters(testCase)
            %TESTREVIEWPARAMETERS Validate human clinical review constants.
            simulink_params;
            
            testCase.verifyEqual(reviewTimeNormalSec, 30, 'Normal review time mismatch');
            testCase.verifyEqual(reviewTimeReferableSec, 120, 'Referable review time mismatch');
            testCase.verifyEqual(referableRate, 0.25, 'AbsTol', 1e-6, 'Referable rate mismatch');
            testCase.verifyEqual(numOphthalmologists, 5, 'Number of ophthalmologists mismatch');
            testCase.verifyEqual(ophthalmologistAvailabilityHours, 6, 'Availability hours mismatch');
        end

        function testTargetParameters(testCase)
            %TESTTARGETPARAMETERS Validate mission clinical & operational targets.
            simulink_params;
            
            testCase.verifyEqual(targetPatientsPerYear, 100000, 'Target annual patients mismatch');
            testCase.verifyEqual(targetTurnaroundHours, 24, 'Turnaround hours SLA mismatch');
            testCase.verifyEqual(targetSensitivity, 0.90, 'AbsTol', 1e-6, 'Sensitivity target mismatch');
            testCase.verifyEqual(targetSpecificity, 0.85, 'AbsTol', 1e-6, 'Specificity target mismatch');
        end

        function testDerivedMetrics(testCase)
            %TESTDERIVEDMETRICS Validate mathematical derivations and queue metrics.
            simulink_params;
            
            testCase.verifyEqual(effectiveBandwidthMbps, 1.40, 'AbsTol', 1e-6, 'Effective bandwidth mismatch');
            testCase.verifyEqual(totalDataPerPatientMB, 10, 'Total data per patient mismatch');
            testCase.verifyEqual(uploadTimePerPatientSec, 80 / 1.40, 'AbsTol', 1e-4, 'Upload duration mismatch');
            testCase.verifyEqual(acquisitionCycleTimePerPatientSec, 150, 'Cycle time mismatch');
            testCase.verifyEqual(expectedReviewTimeSec, 52.5, 'AbsTol', 1e-6, 'Expected review time mismatch');
            testCase.verifyEqual(gpuClusterCapacityPerHour, 480, 'GPU hourly capacity mismatch');
            testCase.verifyEqual(ophthalmologistDailyCapacityPatients, 2057, 'Reading center capacity mismatch');
            testCase.verifyEqual(requiredDailyScreeningRate, 100000 / 300, 'AbsTol', 1e-4, 'Daily screening rate mismatch');
        end

        function testSimParamsStructure(testCase)
            %TESTSIMPARAMSSTRUCTURE Validate container struct fields and types.
            simulink_params;
            
            testCase.verifyTrue(isstruct(simParams), 'simParams must be a struct.');
            testCase.verifyTrue(isfield(simParams, 'patientFlow'), 'simParams.patientFlow missing.');
            testCase.verifyTrue(isfield(simParams, 'acquisition'), 'simParams.acquisition missing.');
            testCase.verifyTrue(isfield(simParams, 'network'), 'simParams.network missing.');
            testCase.verifyTrue(isfield(simParams, 'server'), 'simParams.server missing.');
            testCase.verifyTrue(isfield(simParams, 'review'), 'simParams.review missing.');
            testCase.verifyTrue(isfield(simParams, 'targets'), 'simParams.targets missing.');
            testCase.verifyTrue(isfield(simParams, 'derived'), 'simParams.derived missing.');
            testCase.verifyTrue(isfield(simParams, 'table'), 'simParams.table missing.');
            
            % Check table properties
            testCase.verifyTrue(istable(simParams.table), 'simParams.table must be a table.');
            testCase.verifyEqual(height(simParams.table), 31, 'Summary table must contain 31 parameter rows.');
            testCase.verifyEqual(width(simParams.table), 5, 'Summary table must have 5 columns.');
        end
    end
end
