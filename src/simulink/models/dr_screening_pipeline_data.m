function data = dr_screening_pipeline_data()
% DR_SCREENING_PIPELINE_DATA Loads parameters for the SimEvents model.
%
% Configures base workspace variables and parameters required by the 
% dr_screening_pipeline Simulink model.
%
% Outputs:
%   data - Struct containing the configured parameters.
%
% Example:
%   modelData = dr_screening_pipeline_data();

data = struct();
data.arrivalLambda = 0.05;          % Patients per second
data.acquisitionTimePerPatient = 120; % Seconds
data.imageSizeMB = 15;              % MB per patient
data.uploadBandwidthMbps = 5;       % Mbps
data.uploadEfficiency = 0.8;        % 80% effective bandwidth
data.numGPUServers = 4;             % Number of parallel GPU servers
data.totalProcessingTimeSec = 45;   % Seconds per screening
data.numOphthalmologists = 5;       % Reviewers
data.referableRate = 0.3;           % 30% referable
data.reviewTimeNormalSec = 60;      % 1 min
data.reviewTimeReferableSec = 300;  % 5 mins

try
    % Try to load from simulink_params.m if it exists
    if exist('simulink_params', 'file')
        p = simulink_params();
        flds = fieldnames(p);
        for i=1:length(flds)
            data.(flds{i}) = p.(flds{i});
        end
    end
    
    % Assign to base workspace for Simulink to use
    assignin('base', 'arrivalLambda', data.arrivalLambda);
    assignin('base', 'acquisitionTimePerPatient', data.acquisitionTimePerPatient);
    assignin('base', 'imageSizeMB', data.imageSizeMB);
    assignin('base', 'uploadBandwidthMbps', data.uploadBandwidthMbps);
    assignin('base', 'uploadEfficiency', data.uploadEfficiency);
    assignin('base', 'numGPUServers', data.numGPUServers);
    assignin('base', 'totalProcessingTimeSec', data.totalProcessingTimeSec);
    assignin('base', 'numOphthalmologists', data.numOphthalmologists);
    assignin('base', 'referableRate', data.referableRate);
    assignin('base', 'reviewTimeNormalSec', data.reviewTimeNormalSec);
    assignin('base', 'reviewTimeReferableSec', data.reviewTimeReferableSec);
catch ME
    warning('DRPipeline:Simulink:DataLoadFailed', ...
        'Failed to load model data: %s', ME.message);
end

end
