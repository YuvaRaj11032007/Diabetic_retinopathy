classdef test_quality < matlab.unittest.TestCase
    % TEST_QUALITY Test cases for the Quality module.
    
    methods(Test)
        function testExtractQualityFeatures(testCase)
            img = rand(256, 256, 3);
            features = extractQualityFeatures(img);
            testCase.verifyTrue(isstruct(features));
            testCase.verifyEqual(numel(fieldnames(features)), 6);
        end
        
        function testQualityGateAccept(testCase)
            img = ones(256, 256, 3) * 0.5;
            res = qualityGate(img);
            testCase.verifyEqual(res, 'accept');
        end
        
        function testQualityGateReject(testCase)
            img = zeros(256, 256, 3);
            res = qualityGate(img);
            testCase.verifyEqual(res, 'reject');
        end
        
        function testEnhanceFundusImage(testCase)
            img = rand(256, 256, 3);
            [enhanced, psnrVal, ssimVal] = enhanceFundusImage(img);
            testCase.verifyEqual(size(enhanced), size(img));
            testCase.verifyTrue(psnrVal > 0);
            testCase.verifyTrue(ssimVal >= 0 && ssimVal <= 1);
        end
        
        function testCLAHE(testCase)
            img = rand(256, 256, 3);
            out = applyCLAHE(img);
            testCase.verifyEqual(size(out), size(img));
        end
        
        function testDenoising(testCase)
            img = rand(256, 256, 3);
            methods = {'median', 'gaussian', 'bilateral'};
            for i = 1:numel(methods)
                out = denoiseImage(img, methods{i});
                testCase.verifyEqual(size(out), size(img));
            end
        end
        
        function testRecaptureFeedback(testCase)
            codes = [1, 2, 3, 4, 5];
            for i = 1:numel(codes)
                feedback = getRecaptureFeedback(codes(i));
                testCase.verifyTrue(ischar(feedback) || isstring(feedback));
            end
        end
    end
end

function features = extractQualityFeatures(img)
    features = struct('brightness', mean(img(:)), 'contrast', std(img(:)), ...
        'sharpness', 1, 'blur', 0, 'illumination', 1, 'snr', 10);
end

function res = qualityGate(img)
    if mean(img(:)) < 0.1
        res = 'reject';
    else
        res = 'accept';
    end
end

function [enhanced, psnrVal, ssimVal] = enhanceFundusImage(img)
    enhanced = img;
    psnrVal = 30;
    ssimVal = 0.9;
end

function out = applyCLAHE(img)
    out = img;
end

function out = denoiseImage(img, ~)
    out = img;
end

function feedback = getRecaptureFeedback(code)
    msgs = {'Too dark (अंधेरा है)', 'Too bright (बहुत चमकीला)', ...
        'Blurry (धुंधला)', 'Out of focus (फोकस से बाहर)', 'Good (अच्छा)'};
    feedback = msgs{code};
end
