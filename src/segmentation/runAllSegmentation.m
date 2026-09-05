function segResult = runAllSegmentation(img, modelsInput)
%RUNALLSEGMENTATION Master orchestrator that runs all segmentation sub-modules.
%
%   segResult = runAllSegmentation(img) runs all segmentation modules on the 
%   input RGB image and returns a struct containing results from each module.
%
%   segResult = runAllSegmentation(img, 'models', modelsStruct) optionally
%   provides a struct of pre-loaded models to speed up execution.
%
%   The order of execution handles dependencies:
%   1. Optic disc (independent)
%   2. Vessels (independent)
%   3. Fovea (depends on Optic Disc)
%   4. Microaneurysms (depends on Vessels)
%   5. Hemorrhages (depends on Vessels)
%   6. Exudates (depends on Optic Disc, Vessels)
%   7. Neovascularization (depends on Optic Disc, Vessels)
%
%   Inputs:
%       img     - M-by-N-by-3 RGB uint8 image.
%       options - Name-Value pair for optional arguments.
%
%   Outputs:
%       segResult - Struct containing sub-results and processing times.
%
%   Example:
%       img = imread('fundus.png');
%       result = runAllSegmentation(img);
%       imshow(result.vesselMask);

    arguments
        img (:,:,3) uint8 {mustBeNonempty}
        modelsInput = struct()
    end

    % Normalize models input
    if isstruct(modelsInput) && isfield(modelsInput, 'models')
        models = modelsInput.models;
    elseif isstruct(modelsInput)
        models = modelsInput;
    else
        models = struct();
    end
    options.models = models;

    % Initialize output struct
    segResult = struct();
    segResult.processingTime = struct();
    
    totalTimer = tic;

    %% 1. Optic Disc Localization
    tOD = tic;
    try
        % Pass options.models.opticDisc if it exists
        if isfield(options.models, 'opticDisc')
            odRes = localizeOpticDisc(img, 'model', options.models.opticDisc);
        else
            odRes = localizeOpticDisc(img);
        end
        segResult.opticDisc = odRes;
        odCenter = odRes.center;
        odRadius = odRes.radius;
        odMask = odRes.mask;
    catch ME
        warning('DRPipeline:Segmentation:OpticDiscFailed', 'Optic disc localization failed: %s', ME.message);
        segResult.opticDisc = struct('error', ME.message, 'center', [], 'radius', [], 'mask', []);
        odCenter = [];
        odRadius = [];
        odMask = [];
    end
    segResult.processingTime.opticDisc = toc(tOD);

    %% 2. Blood Vessel Segmentation
    tVes = tic;
    try
        if isfield(options.models, 'vessels')
            vesRes = segmentVessels(img, 'model', options.models.vessels);
        else
            vesRes = segmentVessels(img);
        end
        segResult.vessels = vesRes;
        vesselMask = vesRes.binaryMask;
    catch ME
        warning('DRPipeline:Segmentation:VesselsFailed', 'Vessel segmentation failed: %s', ME.message);
        segResult.vessels = struct('error', ME.message, 'binaryMask', []);
        vesselMask = [];
    end
    segResult.processingTime.vessels = toc(tVes);
    
    % Alias
    segResult.vesselMask = vesselMask;

    %% 3. Fovea Localization (depends on OD)
    tFov = tic;
    try
        if ~isempty(segResult.opticDisc) && isfield(segResult.opticDisc, 'center') && ~isempty(segResult.opticDisc.center)
            fovRes = localizeFovea(img, segResult.opticDisc);
        else
            error('Optic disc information missing.');
        end
        segResult.fovea = fovRes;
    catch ME
        warning('DRPipeline:Segmentation:FoveaFailed', 'Fovea localization failed: %s', ME.message);
        segResult.fovea = struct('error', ME.message);
    end
    segResult.processingTime.fovea = toc(tFov);

    %% 4. Microaneurysm Detection (depends on vessels)
    tMA = tic;
    try
        if isfield(options.models, 'microaneurysms')
            maRes = detectMicroaneurysms(img, vesselMask, 'model', options.models.microaneurysms);
        else
            maRes = detectMicroaneurysms(img, vesselMask);
        end
        segResult.microaneurysms = maRes;
    catch ME
        warning('DRPipeline:Segmentation:MAFailed', 'Microaneurysm detection failed: %s', ME.message);
        segResult.microaneurysms = struct('error', ME.message);
    end
    segResult.processingTime.microaneurysms = toc(tMA);

    %% 5. Hemorrhage Classification (depends on vessels)
    tHem = tic;
    try
        if isfield(options.models, 'hemorrhages')
            hemRes = classifyHemorrhages(img, vesselMask, 'model', options.models.hemorrhages);
        else
            hemRes = classifyHemorrhages(img, vesselMask);
        end
        segResult.hemorrhages = hemRes;
    catch ME
        warning('DRPipeline:Segmentation:HemorrhagesFailed', 'Hemorrhage classification failed: %s', ME.message);
        segResult.hemorrhages = struct('error', ME.message);
    end
    segResult.processingTime.hemorrhages = toc(tHem);

    %% 6. Exudates Segmentation (depends on OD + vessels)
    tExu = tic;
    try
        if isfield(options.models, 'exudates')
            exuRes = segmentExudates(img, odMask, vesselMask, 'model', options.models.exudates);
        else
            exuRes = segmentExudates(img, odMask, vesselMask);
        end
        segResult.exudates = exuRes;
    catch ME
        warning('DRPipeline:Segmentation:ExudatesFailed', 'Exudates segmentation failed: %s', ME.message);
        segResult.exudates = struct('error', ME.message);
    end
    segResult.processingTime.exudates = toc(tExu);

    %% 7. Neovascularization Detection (depends on OD + vessels)
    tNeo = tic;
    try
        if isfield(options.models, 'neovascularization')
            neoRes = detectNeovascularization(img, vesselMask, segResult.opticDisc, 'model', options.models.neovascularization);
        else
            neoRes = detectNeovascularization(img, vesselMask, segResult.opticDisc);
        end
        segResult.neovascularization = neoRes;
    catch ME
        warning('DRPipeline:Segmentation:NeovascularizationFailed', 'Neovascularization detection failed: %s', ME.message);
        segResult.neovascularization = struct('error', ME.message);
    end
    segResult.processingTime.neovascularization = toc(tNeo);

    %% Wrap up
    segResult.processingTime.total = toc(totalTimer);
    
    fprintf('Segmentation complete in %.3f seconds.\n', segResult.processingTime.total);
    fprintf('  OD: %.3fs | Vessels: %.3fs | Fovea: %.3fs\n', ...
        segResult.processingTime.opticDisc, segResult.processingTime.vessels, segResult.processingTime.fovea);
    fprintf('  MA: %.3fs | Hem: %.3fs | Exu: %.3fs | Neo: %.3fs\n', ...
        segResult.processingTime.microaneurysms, segResult.processingTime.hemorrhages, ...
        segResult.processingTime.exudates, segResult.processingTime.neovascularization);

end
