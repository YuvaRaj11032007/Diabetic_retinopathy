function featuresStruct = aggregateFeatures(segResult, foveaLocation)
%AGGREGATEFEATURES Extract clinical feature vector from segmentation results.
%
%   featuresStruct = AGGREGATEFEATURES(segResult, foveaLocation)
%
%   Inputs:
%       segResult - Struct containing segmentation results with fields such as
%                   MACount, HardExudateArea, HardExudatesMask, SoftExudateCount,
%                   HemorrhageCount, HemorrhageArea, DotBlotCount, FlameCount,
%                   NVDProbability, NVDFlag, VesselDensity, VesselTortuosity,
%                   VesselBranchPoints, FundusArea.
%       foveaLocation - 1x2 numeric array [x, y] of fovea center coordinates.
%
%   Outputs:
%       featuresStruct - Struct containing 'vector' (1xD normalized feature vector)
%                        and named fields for each extracted clinical feature.
%
%   Example:
%       segRes.MACount = 12;
%       segRes.FundusArea = 50000;
%       fovea = [256, 256];
%       feats = aggregateFeatures(segRes, fovea);

    arguments
        segResult (1,1) struct
        foveaLocation (1,2) double {mustBeReal, mustBeFinite}
    end
    
    % Initialize default values for features
    feat.maCount = 0;
    feat.maDensity = 0;
    feat.hardExudateArea = 0;
    feat.hardExudateDistFovea = 1000; % Default large distance
    feat.softExudateCount = 0;
    feat.hemorrhageCount = 0;
    feat.hemorrhageArea = 0;
    feat.dotBlotCount = 0;
    feat.flameCount = 0;
    feat.nvdProbability = 0;
    feat.nvdFlag = 0;
    feat.vesselDensity = 0;
    feat.vesselTortuosity = 0;
    feat.vesselBranchPoints = 0;
    
    % 1. MA Count
    if isfield(segResult, 'microaneurysms') && ~isempty(segResult.microaneurysms) && isfield(segResult.microaneurysms, 'count')
        feat.maCount = segResult.microaneurysms.count;
    elseif isfield(segResult, 'MACount')
        feat.maCount = segResult.MACount;
    end
    
    % 2. MA Density
    fundusArea = 1;
    if isfield(segResult, 'FundusArea') && segResult.FundusArea > 0
        fundusArea = segResult.FundusArea;
    elseif isfield(segResult, 'vesselMask') && ~isempty(segResult.vesselMask)
        fundusArea = numel(segResult.vesselMask);
    end
    feat.maDensity = feat.maCount / fundusArea;
    
    % 3. Hard Exudate Area
    if isfield(segResult, 'exudates') && ~isempty(segResult.exudates) && isfield(segResult.exudates, 'totalArea')
        feat.hardExudateArea = segResult.exudates.totalArea;
    elseif isfield(segResult, 'HardExudateArea')
        feat.hardExudateArea = segResult.HardExudateArea;
    end
    
    % 4. Hard exudate distance to fovea
    exMask = [];
    if isfield(segResult, 'exudates') && ~isempty(segResult.exudates) && isfield(segResult.exudates, 'hardExudateMask')
        exMask = segResult.exudates.hardExudateMask;
    elseif isfield(segResult, 'HardExudatesMask')
        exMask = segResult.HardExudatesMask;
    end
    if ~isempty(exMask) && any(exMask(:)) && ~isempty(foveaLocation)
        [r, c] = find(exMask);
        distances = sqrt((c - foveaLocation(1)).^2 + (r - foveaLocation(2)).^2);
        feat.hardExudateDistFovea = min(distances);
    end
    
    % 5. Soft exudate count
    if isfield(segResult, 'exudates') && ~isempty(segResult.exudates) && isfield(segResult.exudates, 'softExudateMask') && ~isempty(segResult.exudates.softExudateMask)
        feat.softExudateCount = max(0, sum(segResult.exudates.softExudateMask(:) > 0));
    elseif isfield(segResult, 'SoftExudateCount')
        feat.softExudateCount = segResult.SoftExudateCount;
    end
    
    % 6. Hemorrhage count
    if isfield(segResult, 'hemorrhages') && ~isempty(segResult.hemorrhages) && isfield(segResult.hemorrhages, 'count')
        feat.hemorrhageCount = segResult.hemorrhages.count;
    elseif isfield(segResult, 'HemorrhageCount')
        feat.hemorrhageCount = segResult.HemorrhageCount;
    end
    
    % 7. Hemorrhage area
    if isfield(segResult, 'hemorrhages') && ~isempty(segResult.hemorrhages) && isfield(segResult.hemorrhages, 'binaryMask') && ~isempty(segResult.hemorrhages.binaryMask)
        feat.hemorrhageArea = sum(segResult.hemorrhages.binaryMask(:) > 0);
    elseif isfield(segResult, 'HemorrhageArea')
        feat.hemorrhageArea = segResult.HemorrhageArea;
    end
    
    % 8. Dot/blot hemorrhage count
    if isfield(segResult, 'DotBlotCount')
        feat.dotBlotCount = segResult.DotBlotCount;
    end
    
    % 9. Flame hemorrhage count
    if isfield(segResult, 'FlameCount')
        feat.flameCount = segResult.FlameCount;
    end
    
    % 10. Neovascularization probability
    if isfield(segResult, 'neovascularization') && ~isempty(segResult.neovascularization) && isfield(segResult.neovascularization, 'nvProbability')
        feat.nvdProbability = segResult.neovascularization.nvProbability;
    elseif isfield(segResult, 'NVDProbability')
        feat.nvdProbability = segResult.NVDProbability;
    end
    
    % 11. NVD flag
    if isfield(segResult, 'neovascularization') && ~isempty(segResult.neovascularization) && isfield(segResult.neovascularization, 'nvdFlag')
        feat.nvdFlag = double(segResult.neovascularization.nvdFlag);
    elseif isfield(segResult, 'NVDFlag')
        feat.nvdFlag = segResult.NVDFlag;
    end
    
    % 12. Vessel density
    if isfield(segResult, 'vessels') && ~isempty(segResult.vessels) && isfield(segResult.vessels, 'vesselDensity')
        feat.vesselDensity = segResult.vessels.vesselDensity;
    elseif isfield(segResult, 'VesselDensity')
        feat.vesselDensity = segResult.VesselDensity;
    end
    
    % 13. Vessel tortuosity
    if isfield(segResult, 'VesselTortuosity')
        feat.vesselTortuosity = segResult.VesselTortuosity;
    end
    
    % 14. Vessel branch points
    if isfield(segResult, 'VesselBranchPoints')
        feat.vesselBranchPoints = segResult.VesselBranchPoints;
    end
    
    % Creating the raw vector
    rawVector = [ ...
        feat.maCount, ...
        feat.maDensity, ...
        feat.hardExudateArea, ...
        feat.hardExudateDistFovea, ...
        feat.softExudateCount, ...
        feat.hemorrhageCount, ...
        feat.hemorrhageArea, ...
        feat.dotBlotCount, ...
        feat.flameCount, ...
        feat.nvdProbability, ...
        feat.nvdFlag, ...
        feat.vesselDensity, ...
        feat.vesselTortuosity, ...
        feat.vesselBranchPoints ...
    ];

    % Empirical max values for normalization [0, 1]
    empiricalMax = [ ...
        100, ...      % maCount
        0.001, ...    % maDensity
        10000, ...    % hardExudateArea
        2000, ...     % hardExudateDistFovea
        50, ...       % softExudateCount
        50, ...       % hemorrhageCount
        20000, ...    % hemorrhageArea
        30, ...       % dotBlotCount
        20, ...       % flameCount
        1.0, ...      % nvdProbability
        1.0, ...      % nvdFlag
        0.2, ...      % vesselDensity
        1.5, ...      % vesselTortuosity
        300 ...       % vesselBranchPoints
    ];
    
    normVector = min(rawVector ./ empiricalMax, 1.0); % Cap at 1.0
    
    featuresStruct = feat;
    featuresStruct.vector = normVector;
end
