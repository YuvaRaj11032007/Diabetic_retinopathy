function nvResult = detectNeovascularization(img, vesselMask, odResult)
%DETECTNEOVASCULARIZATION Detect neovascularization (NVD and NVE)
%
%   nvResult = detectNeovascularization(img, vesselMask, odResult) analyzes
%   vessel networks to identify abnormal proliferation typical in Proliferative DR.
%
%   INPUTS:
%       img        - Enhanced RGB retinal image (HxWx3 uint8 or double)
%       vesselMask - Binary mask of retinal vessels (HxW logical)
%       odResult   - Struct from localizeOpticDisc containing OD centroid
%
%   OUTPUTS:
%       nvResult - Struct with fields:
%                  .nvProbability : scalar [0-1] overall probability of NV
%                  .nvdFlag       : boolean indicating presence of NVD
%                  .nveRegions    : HxW logical mask of NVE regions
%                  .patches       : struct array with patch-level info
%
%   EXAMPLE:
%       nvResult = detectNeovascularization(img, vesselMask, odResult);
%       if nvResult.nvdFlag, disp('NVD Detected!'); end

    arguments
        img (:,:,3) {mustBeNumeric}
        vesselMask = []
        odResult = []
    end

    try
        [H, W, ~] = size(img);
        
        % Normalize in case caller swapped vesselMask and odResult
        if isstruct(vesselMask) && ~isstruct(odResult)
            temp = vesselMask;
            vesselMask = odResult;
            odResult = temp;
        end
        
        % Defaults
        if isempty(vesselMask) || ~islogical(vesselMask) || ~isequal(size(vesselMask), [H, W])
            vesselMask = false(H, W);
        end
        
        if isempty(odResult) || ~isstruct(odResult)
            odResult = struct('center', [round(W/2), round(H/2)], 'centroid', [round(W/2), round(H/2)], 'radius', round(min(H,W)/10));
        end
        if ~isfield(odResult, 'centroid')
            if isfield(odResult, 'center')
                odResult.centroid = odResult.center;
            else
                odResult.centroid = [round(W/2), round(H/2)];
            end
        end
        if ~isfield(odResult, 'radius') || isempty(odResult.radius) || odResult.radius <= 0
            odResult.radius = round(min(H,W)/10);
        end
        
        % Get vessel skeleton and branch points with fallbacks
        if any(vesselMask(:)) && exist('bwskel', 'file') == 2
            try
                skel = bwskel(vesselMask);
            catch
                skel = vesselMask;
            end
        else
            skel = vesselMask;
        end
        
        if any(skel(:)) && exist('bwmorph', 'file') == 2
            try
                branchPoints = bwmorph(skel, 'branchpoints');
            catch
                branchPoints = false(H, W);
            end
        else
            branchPoints = false(H, W);
        end
        
        % Define patch parameters
        patchSize = 128;
        overlap = 64;
        stride = patchSize - overlap;
        
        patches = struct('BoundingBox', {}, 'Density', {}, 'FractalDim', {}, 'BranchDensity', {}, 'IsNVD', {}, 'IsNVE', {});
        idx = 1;
        
        nvdFlag = false;
        nveMask = false(H, W);
        
        odCentroid = odResult.centroid;
        odRadius = odResult.radius;
        nvdZoneRadius = odRadius * 2; % Zone for NVD detection (1 disc diameter from margin)
        
        maxPatches = ceil(H/stride) * ceil(W/stride);
        % Preallocate
        patchDensity = zeros(maxPatches, 1);
        patchFD = zeros(maxPatches, 1);
        patchBranch = zeros(maxPatches, 1);
        
        % 1. Patch-wise analysis
        for y = 1:stride:H-patchSize+1
            for x = 1:stride:W-patchSize+1
                yEnd = y + patchSize - 1;
                xEnd = x + patchSize - 1;
                
                vesselPatch = vesselMask(y:yEnd, x:xEnd);
                skelPatch = skel(y:yEnd, x:xEnd);
                branchPatch = branchPoints(y:yEnd, x:xEnd);
                
                % Compute features
                density = sum(vesselPatch, 'all') / (patchSize^2);
                branchCount = sum(branchPatch, 'all');
                branchDensity = branchCount / (patchSize^2);
                
                % Only process patches with sufficient vessels
                if density > 0.01
                    fd = computeFractalDimension(skelPatch);
                else
                    fd = 0;
                end
                
                patchDensity(idx) = density;
                patchFD(idx) = fd;
                patchBranch(idx) = branchDensity;
                
                % Check if patch is in NVD zone (near OD)
                patchCentroid = [x + patchSize/2, y + patchSize/2];
                distToOD = norm(patchCentroid - odCentroid);
                inNVDZone = distToOD <= nvdZoneRadius;
                
                % Determine if abnormal (thresholds are illustrative)
                isNVD = false;
                isNVE = false;
                
                % Anomalously high density or complexity
                if density > 0.15 && branchDensity > 0.002 && fd > 1.3
                    if inNVDZone
                        isNVD = true;
                        nvdFlag = true;
                    else
                        isNVE = true;
                        nveMask(y:yEnd, x:xEnd) = true;
                    end
                end
                
                patches(idx).BoundingBox = [x, y, patchSize, patchSize];
                patches(idx).Density = density;
                patches(idx).FractalDim = fd;
                patches(idx).BranchDensity = branchDensity;
                patches(idx).IsNVD = isNVD;
                patches(idx).IsNVE = isNVE;
                
                idx = idx + 1;
            end
        end
        
        % 2. Aggregate image-level score
        % Use top 5% most complex patches to determine overall NV probability
        validFD = patchFD(patchFD > 0);
        if ~isempty(validFD)
            topFD = prctile(validFD, 95);
            nvProbability = min(1, max(0, (topFD - 1.1) / 0.4)); % Normalize roughly to 0-1
        else
            nvProbability = 0;
        end
        
        if nvdFlag
            nvProbability = max(nvProbability, 0.8);
        end
        
        nvResult = struct();
        nvResult.nvProbability = nvProbability;
        nvResult.nvdFlag = nvdFlag;
        nvResult.nveRegions = nveMask & fundusMaskApprox(H,W); % Mask out corners ideally
        nvResult.patches = patches;
        
    catch ME
        error('DRPipeline:segmentation:NeovascularizationDetectionError', ...
            'Failed to detect neovascularization: %s', ME.message);
    end
end

function fd = computeFractalDimension(bw)
% Helper function to compute fractal dimension using box-counting
    if ~any(bw, 'all')
        fd = 0;
        return;
    end
    
    maxSize = min(size(bw));
    boxSizes = 2.^(floor(log2(maxSize)):-1:1);
    counts = zeros(size(boxSizes));
    
    for i = 1:length(boxSizes)
        bs = boxSizes(i);
        fun = @(x) any(x(:));
        % Using blockproc or custom sum for speed
        % For simplicity, resize and find non-zero blocks
        numRows = ceil(size(bw,1)/bs);
        numCols = ceil(size(bw,2)/bs);
        padded = false(numRows*bs, numCols*bs);
        padded(1:size(bw,1), 1:size(bw,2)) = bw;
        
        reshaped = reshape(padded, bs, numRows, bs, numCols);
        blocks = any(any(reshaped, 1), 3);
        counts(i) = sum(blocks, 'all');
    end
    
    % Linear fit log(count) vs log(1/boxSize)
    x = log(1 ./ boxSizes);
    y = log(counts);
    
    valid = counts > 0;
    if sum(valid) > 2
        p = polyfit(x(valid), y(valid), 1);
        fd = p(1);
    else
        fd = 0;
    end
end

function fm = fundusMaskApprox(H, W)
    % Simple circular mask to approximate fundus for NVE region cleanup
    [X, Y] = meshgrid(1:W, 1:H);
    R = min(H,W)/2 * 0.95;
    cx = W/2; cy = H/2;
    fm = ((X - cx).^2 + (Y - cy).^2) <= R^2;
end
