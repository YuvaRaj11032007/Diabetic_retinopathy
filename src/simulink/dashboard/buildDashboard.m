function fig = buildDashboard()
% BUILDDASHBOARD Creates a figure-based dashboard for the DR screening simulation.
%
% Creates a UI figure with sliders for key parameters and a button to run
% the simulation. Updates plots representing queue depths, throughput, and
% utilization based on the current parameters.
%
% Outputs:
%   fig - Handle to the created UIFigure.
%
% Example:
%   uiFig = buildDashboard();

fig = uifigure('Name', 'DR Screening Pipeline Dashboard', 'Position', [100, 100, 800, 600]);

% UI Controls
uilabel(fig, 'Position', [20, 550, 150, 22], 'Text', 'GPU Servers:');
gSlider = uislider(fig, 'Position', [150, 560, 200, 3], 'Limits', [1, 16], 'Value', 4);

uilabel(fig, 'Position', [20, 510, 150, 22], 'Text', 'Ophthalmologists:');
oSlider = uislider(fig, 'Position', [150, 520, 200, 3], 'Limits', [1, 20], 'Value', 5);

uilabel(fig, 'Position', [20, 470, 150, 22], 'Text', 'Bandwidth (Mbps):');
bSlider = uislider(fig, 'Position', [150, 480, 200, 3], 'Limits', [1, 100], 'Value', 10);

runBtn = uibutton(fig, 'Position', [20, 420, 120, 30], 'Text', 'Run Simulation');

% Status Labels
throughputLbl = uilabel(fig, 'Position', [400, 550, 300, 22], 'Text', 'Throughput: -- patients/day');
turnaroundLbl = uilabel(fig, 'Position', [400, 520, 300, 22], 'Text', 'Avg Turnaround: -- hours');
bottleneckLbl = uilabel(fig, 'Position', [400, 490, 300, 22], 'Text', 'Bottleneck: --');

% Axes for plots
ax1 = uiaxes(fig, 'Position', [20, 20, 350, 350]);
title(ax1, 'Queue Depths');
ax2 = uiaxes(fig, 'Position', [400, 20, 350, 350]);
title(ax2, 'Utilization');

% Button Callback
runBtn.ButtonPushedFcn = @(btn, event) runSimulationCallback();

% Initial draw
runSimulationCallback();

    function runSimulationCallback()
        % Mock simulation run based on slider values
        g = gSlider.Value;
        o = oSlider.Value;
        b = bSlider.Value;
        
        % Simple model
        procCap = g * 150;
        revCap = o * 80;
        upCap = b * 50;
        
        [minCap, idx] = min([procCap, revCap, upCap]);
        bottlenecks = {'GPU Processing', 'Clinical Review', 'Upload Bandwidth'};
        
        throughput = minCap;
        turnaround = 24 / (throughput/100 + 1);
        
        throughputLbl.Text = sprintf('Throughput: %.0f patients/day', throughput);
        turnaroundLbl.Text = sprintf('Avg Turnaround: %.1f hours', turnaround);
        bottleneckLbl.Text = sprintf('Bottleneck: %s', bottlenecks{idx});
        
        % Update plots
        bar(ax1, [max(0, 100-upCap), max(0, 200-procCap), max(0, 150-revCap)]);
        ax1.XTickLabel = {'Upload', 'Processing', 'Review'};
        ylabel(ax1, 'Queue Depth');
        
        bar(ax2, [throughput/upCap, throughput/procCap, throughput/revCap]*100);
        ax2.XTickLabel = {'Network', 'GPU', 'Reviewers'};
        ylabel(ax2, 'Utilization (%)');
        ylim(ax2, [0, 110]);
    end

end
