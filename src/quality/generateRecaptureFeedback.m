function feedback = generateRecaptureFeedback(qualityResult)
%GENERATERECAPTUREFEEDBACK Generate human-readable recapture guidance.
%   FEEDBACK = GENERATERECAPTUREFEEDBACK(QUALITYRESULT) generates feedback
%   for the camera operator when an image is rejected by the quality gate.
%   Returns a struct with reason codes and bilingual (English/Hindi) text.
%
%   Output Fields:
%     feedback.reason_code     - Machine-readable code (e.g., 'too_dark')
%     feedback.reason_text_en  - English feedback string
%     feedback.reason_text_hi  - Hindi feedback string (for field workers)
%     feedback.priority        - 'high', 'medium', 'low'
%     feedback.suggestions     - Cell array of actionable suggestions
%
%   Supported Reason Codes:
%     'too_dark'            - Insufficient illumination
%     'too_bright'          - Overexposure / flash too strong
%     'blurry'              - Poor focus / camera movement
%     'small_fov'           - Incomplete field of view
%     'low_contrast'        - Poor contrast (media opacity, dirty lens)
%     'uneven_illumination' - Severe vignetting or partial illumination
%     'general_poor_quality'- Multiple issues, generic feedback
%
%   Example:
%       [decision, result, ~] = qualityGate(img);
%       if strcmp(decision, 'reject')
%           feedback = generateRecaptureFeedback(result);
%           disp(feedback.reason_text_en);
%           disp(feedback.reason_text_hi);
%       end
%
%   See also: QUALITYGATE, EXTRACTQUALITYFEATURES

% -------------------------------------------------------------------------
%   DR Screening Pipeline — Quality Assessment Module
% -------------------------------------------------------------------------

    arguments
        qualityResult struct
    end

    % Extract failure reasons
    if isfield(qualityResult, 'failureReasons') && ~isempty(qualityResult.failureReasons)
        reasons = qualityResult.failureReasons;
    else
        % Determine reasons from features if not pre-computed
        reasons = {};
        if isfield(qualityResult, 'features')
            f = qualityResult.features;
            if f.focusScore < 0.3,       reasons{end+1} = 'blurry'; end
            if f.luminanceMean < 0.2,    reasons{end+1} = 'too_dark'; end
            if f.luminanceMean > 0.8,    reasons{end+1} = 'too_bright'; end
            if f.fovCoverage < 0.3,      reasons{end+1} = 'small_fov'; end
            if f.contrastScore < 0.2,    reasons{end+1} = 'low_contrast'; end
            if f.luminanceStd > 0.8,     reasons{end+1} = 'uneven_illumination'; end
        end
        if isempty(reasons)
            reasons = {'general_poor_quality'};
        end
    end

    % Use the most critical reason as primary
    priorityOrder = {'blurry', 'too_dark', 'too_bright', 'small_fov', ...
                     'low_contrast', 'uneven_illumination', 'general_poor_quality'};
    primaryReason = 'general_poor_quality';
    for i = 1:numel(priorityOrder)
        if ismember(priorityOrder{i}, reasons)
            primaryReason = priorityOrder{i};
            break;
        end
    end

    % Build feedback based on reason
    switch primaryReason
        case 'too_dark'
            feedback.reason_code = 'too_dark';
            feedback.reason_text_en = 'Image is too dark. Please increase flash intensity and ensure the room is not too bright (avoid direct sunlight on the eye).';
            feedback.reason_text_hi = 'छवि बहुत अंधेरी है। कृपया फ्लैश की तीव्रता बढ़ाएं और सुनिश्चित करें कि कमरे में सीधी धूप न हो।';
            feedback.priority = 'high';
            feedback.suggestions = {
                'Increase camera flash intensity by one level'
                'Ensure pupil is adequately dilated'
                'Reduce ambient light in the room'
                'Check if lens cap is removed'
            };

        case 'too_bright'
            feedback.reason_code = 'too_bright';
            feedback.reason_text_en = 'Image is overexposed. Please reduce flash intensity or increase the distance slightly.';
            feedback.reason_text_hi = 'छवि अत्यधिक चमकीली है। कृपया फ्लैश की तीव्रता कम करें या दूरी थोड़ी बढ़ाएं।';
            feedback.priority = 'high';
            feedback.suggestions = {
                'Decrease camera flash intensity by one level'
                'Slightly increase working distance'
                'Check for reflections from spectacles (remove if possible)'
            };

        case 'blurry'
            feedback.reason_code = 'blurry';
            feedback.reason_text_en = 'Image is out of focus. Please hold the camera steady, ask the patient to fixate on the target, and retake.';
            feedback.reason_text_hi = 'छवि धुंधली है। कृपया कैमरा स्थिर रखें, रोगी को लक्ष्य पर ध्यान केंद्रित करने को कहें, और पुनः फोटो लें।';
            feedback.priority = 'high';
            feedback.suggestions = {
                'Hold camera steady — use both hands or a mount'
                'Ask patient to fixate on the internal fixation target'
                'Ensure auto-focus has locked before capture'
                'Clean the camera lens with a microfiber cloth'
            };

        case 'small_fov'
            feedback.reason_code = 'small_fov';
            feedback.reason_text_en = 'Field of view is too small. Please align the camera properly so the full retina is visible.';
            feedback.reason_text_hi = 'दृश्य क्षेत्र बहुत छोटा है। कृपया कैमरे को सही तरीके से संरेखित करें ताकि पूरी रेटिना दिखाई दे।';
            feedback.priority = 'medium';
            feedback.suggestions = {
                'Align camera centrally with the pupil'
                'Reduce working distance slightly'
                'Ensure adequate pupil dilation (≥ 4mm)'
                'Ask patient to look straight at the fixation target'
            };

        case 'low_contrast'
            feedback.reason_code = 'low_contrast';
            feedback.reason_text_en = 'Image has poor contrast. This may indicate media opacity (cataract) or a dirty lens. Clean the lens and retry.';
            feedback.reason_text_hi = 'छवि में कम कंट्रास्ट है। यह लेंस गंदा होने या मोतियाबिंद के कारण हो सकता है। लेंस साफ करें और पुनः प्रयास करें।';
            feedback.priority = 'medium';
            feedback.suggestions = {
                'Clean camera lens with lens cleaning solution'
                'Note: poor contrast may indicate cataract — document and refer'
                'Try adjusting flash angle slightly'
            };

        case 'uneven_illumination'
            feedback.reason_code = 'uneven_illumination';
            feedback.reason_text_en = 'Illumination is uneven across the image. Ensure the camera flash is centered and the patient''s eyelid is fully open.';
            feedback.reason_text_hi = 'छवि में रोशनी असमान है। सुनिश्चित करें कि कैमरे का फ्लैश केंद्रित है और रोगी की पलक पूरी तरह खुली है।';
            feedback.priority = 'medium';
            feedback.suggestions = {
                'Ensure camera flash ring is clean and functioning'
                'Ask patient to open eye wider (use lid retractor if needed)'
                'Check camera alignment — should be coaxial with pupil'
            };

        otherwise  % 'general_poor_quality'
            feedback.reason_code = 'general_poor_quality';
            feedback.reason_text_en = 'Image quality is insufficient for reliable analysis. Please check camera settings, lens cleanliness, and patient positioning, then retake.';
            feedback.reason_text_hi = 'छवि की गुणवत्ता विश्लेषण के लिए अपर्याप्त है। कृपया कैमरा सेटिंग्स, लेंस की सफाई, और रोगी की स्थिति जांचें, फिर पुनः फोटो लें।';
            feedback.priority = 'high';
            feedback.suggestions = {
                'Check all camera settings (focus, flash, exposure)'
                'Clean the camera lens'
                'Ensure proper patient positioning'
                'Ensure adequate pupil dilation'
                'Retry in a darker room to improve pupil size'
            };
    end

    % Add all detected reasons for comprehensive feedback
    feedback.all_reasons = reasons;
    feedback.num_issues = numel(reasons);

    % Generate combined feedback if multiple issues
    if numel(reasons) > 1
        feedback.additional_issues = setdiff(reasons, {primaryReason});
        additionalTexts = cellfun(@(r) getShortDescription(r), ...
            feedback.additional_issues, 'UniformOutput', false);
        feedback.reason_text_en = [feedback.reason_text_en, ...
            ' Additional issues: ', strjoin(additionalTexts, '; '), '.'];
    end
end

function desc = getShortDescription(reason)
%GETSHORTDESCRIPTION Get a short English description for a reason code.
    switch reason
        case 'too_dark',            desc = 'image too dark';
        case 'too_bright',          desc = 'image overexposed';
        case 'blurry',              desc = 'image out of focus';
        case 'small_fov',           desc = 'incomplete field of view';
        case 'low_contrast',        desc = 'poor contrast';
        case 'uneven_illumination', desc = 'uneven illumination';
        otherwise,                  desc = 'general quality issue';
    end
end
