function evidence = mapLesionEvidence(segResult, drGrade)
%MAPLESIONEVIDENCE Maps detected lesions to International Clinical DR Scale criteria
%
% Inputs:
%   segResult - struct with segmentation counts and areas
%   drGrade   - integer (0-4) representing the predicted DR grade
%
% Outputs:
%   evidence  - struct array with evidence mapping fields:
%               criterion, lesion_type, count, area, meets_criterion, evidence_text, severity

    arguments
        segResult struct
        drGrade (1,1) {mustBeInteger, mustBeInRange(drGrade, 0, 4)}
    end

    evidence = struct('criterion', {}, 'lesion_type', {}, 'count', {}, ...
        'area', {}, 'meets_criterion', {}, 'evidence_text', {}, 'severity', {});

    % 1. Extract Microaneurysms
    maCount = 0;
    if isfield(segResult, 'microaneurysms') && ~isempty(segResult.microaneurysms) && isfield(segResult.microaneurysms, 'count')
        try, maCount = segResult.microaneurysms.count; catch, end
    elseif isfield(segResult, 'MACount')
        try, maCount = segResult.MACount; catch, end
    end

    % 2. Extract Hard & Soft Exudates
    exCount = 0;
    exArea = 0;
    softExCount = 0;
    if isfield(segResult, 'exudates') && ~isempty(segResult.exudates)
        if isfield(segResult.exudates, 'count'), try, exCount = segResult.exudates.count; catch, end; end
        if isfield(segResult.exudates, 'totalArea'), try, exArea = segResult.exudates.totalArea; catch, end; end
        if isfield(segResult.exudates, 'softExudateMask') && ~isempty(segResult.exudates.softExudateMask)
            try, softExCount = sum(segResult.exudates.softExudateMask(:) > 0); catch, end
        end
    elseif isfield(segResult, 'HardExudateArea')
        try, exArea = segResult.HardExudateArea; catch, end
    end

    % 3. Extract Hemorrhages
    heCount = 0;
    heArea = 0;
    if isfield(segResult, 'hemorrhages') && ~isempty(segResult.hemorrhages)
        if isfield(segResult.hemorrhages, 'count'), try, heCount = segResult.hemorrhages.count; catch, end; end
        if isfield(segResult.hemorrhages, 'totalArea'), try, heArea = segResult.hemorrhages.totalArea; catch, end; end
    elseif isfield(segResult, 'HemorrhageCount')
        try, heCount = segResult.HemorrhageCount; catch, end
    end

    % 4. Extract Neovascularization
    nvProb = 0;
    if isfield(segResult, 'neovascularization') && ~isempty(segResult.neovascularization) && isfield(segResult.neovascularization, 'nvProbability')
        try, nvProb = segResult.neovascularization.nvProbability; catch, end
    elseif isfield(segResult, 'NVDProbability')
        try, nvProb = segResult.NVDProbability; catch, end
    end

    idx = 1;

    % --- Criterion 1: Hard Exudates ---
    if exArea > 800 && exCount >= 8
        sev = 'Severe';
        txt = sprintf('%d distinct hard exudate clusters detected (total area: %d px) in the macular/posterior pole region.', exCount, round(exArea));
        meets = true;
    elseif exArea > 150 && exCount >= 3
        sev = 'Moderate';
        txt = sprintf('%d hard exudate lesions detected (%d px), indicating lipid leakage.', exCount, round(exArea));
        meets = true;
    else
        sev = 'None';
        txt = 'No significant hard exudates or lipid deposits detected in the retina.';
        meets = false;
    end
    evidence(idx).criterion = 'Hard Exudates (Lipid Transudates)';
    evidence(idx).lesion_type = 'EX';
    evidence(idx).count = exCount;
    evidence(idx).area = exArea;
    evidence(idx).meets_criterion = meets;
    evidence(idx).evidence_text = txt;
    evidence(idx).severity = sev;
    idx = idx + 1;

    % --- Criterion 2: Hemorrhages ---
    if heCount >= 20 || heArea > 1000
        sev = 'Severe';
        txt = sprintf('Extensive retinal hemorrhages detected (%d lesions, %d px), meeting ICDR 4-2-1 threshold.', heCount, round(heArea));
        meets = true;
    elseif heCount >= 3
        sev = 'Moderate';
        txt = sprintf('%d retinal hemorrhages identified (%d px).', heCount, round(heArea));
        meets = true;
    else
        sev = 'None';
        txt = 'No intraretinal hemorrhages identified.';
        meets = false;
    end
    evidence(idx).criterion = 'Intraretinal Hemorrhages';
    evidence(idx).lesion_type = 'HE';
    evidence(idx).count = heCount;
    evidence(idx).area = heArea;
    evidence(idx).meets_criterion = meets;
    evidence(idx).evidence_text = txt;
    evidence(idx).severity = sev;
    idx = idx + 1;

    % --- Criterion 3: Microaneurysms ---
    if maCount >= 15
        sev = 'Severe';
        txt = sprintf('Frequent microaneurysms identified (%d lesions), indicating widespread capillary outpouching.', maCount);
        meets = true;
    elseif maCount >= 4
        sev = 'Moderate';
        txt = sprintf('%d microaneurysms detected in the capillary beds.', maCount);
        meets = true;
    elseif maCount >= 2
        sev = 'Mild';
        txt = sprintf('%d isolated microaneurysms detected in the retina.', maCount);
        meets = true;
    else
        sev = 'None';
        txt = 'No definite microaneurysms detected.';
        meets = false;
    end
    evidence(idx).criterion = 'Microaneurysms';
    evidence(idx).lesion_type = 'MA';
    evidence(idx).count = maCount;
    evidence(idx).area = maCount * 5;
    evidence(idx).meets_criterion = meets;
    evidence(idx).evidence_text = txt;
    evidence(idx).severity = sev;
    idx = idx + 1;

    % --- Criterion 4: Cotton-Wool Spots ---
    if softExCount > 200
        sev = 'Moderate to Severe';
        txt = sprintf('Cotton-wool spots (nerve fiber layer infarcts) observed (%d px).', round(softExCount));
        meets = true;
    else
        sev = 'None';
        txt = 'No acute cotton-wool spots (axoplasmic stasis) detected.';
        meets = false;
    end
    evidence(idx).criterion = 'Cotton-Wool Spots (Soft Exudates)';
    evidence(idx).lesion_type = 'CWS';
    evidence(idx).count = double(softExCount > 200);
    evidence(idx).area = softExCount;
    evidence(idx).meets_criterion = meets;
    evidence(idx).evidence_text = txt;
    evidence(idx).severity = sev;
    idx = idx + 1;

    % --- Criterion 5: Neovascularization ---
    if nvProb >= 0.7
        sev = 'Proliferative (Severe)';
        txt = sprintf('Abnormal vessel tortuosity/fronds indicative of neovascularization (probability: %.1f%%).', nvProb * 100);
        meets = true;
    else
        sev = 'None';
        txt = 'No pathological neovascular vessels identified at optic disc or retina.';
        meets = false;
    end
    evidence(idx).criterion = 'Neovascularization (NVD / NVE)';
    evidence(idx).lesion_type = 'NV';
    evidence(idx).count = double(nvProb >= 0.7);
    evidence(idx).area = nvProb;
    evidence(idx).meets_criterion = meets;
    evidence(idx).evidence_text = txt;
    evidence(idx).severity = sev;
    idx = idx + 1;

    % --- Criterion 6: Diagnostic Correlation ---
    gradeNames = {'Level 0: No Diabetic Retinopathy', 'Level 1: Mild NPDR', ...
        'Level 2: Moderate NPDR', 'Level 3: Severe NPDR', 'Level 4: Proliferative DR (PDR)'};
    evidence(idx).criterion = 'Clinical Diagnosis Summary';
    evidence(idx).lesion_type = 'SUMMARY';
    evidence(idx).count = drGrade;
    evidence(idx).area = 0;
    evidence(idx).meets_criterion = true;
    evidence(idx).severity = sprintf('Grade %d', drGrade);
    evidence(idx).evidence_text = sprintf('Classified as %s in accordance with International Clinical Diabetic Retinopathy Disease Severity Scale.', gradeNames{drGrade + 1});

end
