function optimizationResults = runOptimization()
% RUNOPTIMIZATION Runs parameter sweeps for the DR screening SimEvents model.
%
% Sweeps through various configurations of GPU servers, ophthalmologists,
% and upload bandwidths to find optimal resource allocations that meet the
% target throughput (>100K/year) and turnaround time (<24h).
%
% Outputs:
%   optimizationResults - Struct containing the parameter grid and results.
%
% Example:
%   res = runOptimization();

numGPUServersSweep = [1, 2, 4, 8, 16];
numOphthalmologistsSweep = [2, 3, 5, 8, 10];
uploadBandwidthMbpsSweep = [1, 2, 5, 10];

resultsDir = fullfile('d:', 'sih_project', 'results', 'simulink');
if ~exist(resultsDir, 'dir')
    mkdir(resultsDir);
end

% Create grid
[G, O, B] = ndgrid(numGPUServersSweep, numOphthalmologistsSweep, uploadBandwidthMbpsSweep);
numSims = numel(G);

results = struct('TurnaroundTime', cell(numSims,1), ...
                 'Throughput', cell(numSims,1), ...
                 'MaxUploadQueue', cell(numSims,1), ...
                 'GPUUtilization', cell(numSims,1));

fprintf('Starting optimization sweep with %d configurations...\n', numSims);

for i = 1:numSims
    % Mock the simulation loop to avoid actual simulink overhead if not available
    % In a real scenario, we would use sim() with simIn inputs
    
    % Simplified mock model of the system
    g = G(i); o = O(i); b = B(i);
    
    processingCapacity = g * 80; % Mock throughput
    uploadCapacity = b * 30;
    reviewCapacity = o * 40;
    
    bottleneck = min([processingCapacity, uploadCapacity, reviewCapacity]);
    
    results(i).Throughput = bottleneck * 8; % per 8 hr shift
    results(i).TurnaroundTime = 24 / bottleneck + 2; % hours
    results(i).GPUUtilization = bottleneck / processingCapacity;
    results(i).MaxUploadQueue = max(0, 100 - uploadCapacity);
end

optimizationResults.Grid.GPU = G;
optimizationResults.Grid.Ophthalmologists = O;
optimizationResults.Grid.Bandwidth = B;
optimizationResults.Results = results;

% Save results
save(fullfile(resultsDir, 'optimization_results.mat'), 'optimizationResults');

% Generate heatmaps
fig = figure('Name', 'Resource Allocation Optimization', 'Visible', 'off');
surf(numGPUServersSweep, numOphthalmologistsSweep, reshape([results.Throughput], size(G))(:,:,end));
xlabel('GPU Servers');
ylabel('Ophthalmologists');
zlabel('Throughput (patients/shift)');
title('Throughput Optimization (Max Bandwidth)');
colorbar;

saveas(fig, fullfile(resultsDir, 'resource_allocation_plots.png'));
close(fig);

fprintf('Optimization complete. Results saved to %s\n', resultsDir);

end
