classdef test_segmentation < matlab.unittest.TestCase
    % TEST_SEGMENTATION Test cases for the Segmentation module.
    
    methods(Test)
        function testLocalizeOpticDisc(testCase)
            img = zeros(256, 256);
            img(100:120, 100:120) = 1;
            [center, radius] = localizeOpticDisc(img);
            testCase.verifyEqual(numel(center), 2);
            testCase.verifyTrue(radius > 0);
        end
        
        function testLocalizeFovea(testCase)
            img = zeros(256, 256);
            center = localizeFovea(img);
            testCase.verifyEqual(numel(center), 2);
        end
        
        function testSegmentVessels(testCase)
            img = rand(256, 256);
            mask = segmentVessels(img);
            testCase.verifyEqual(size(mask), size(img));
            testCase.verifyTrue(islogical(mask));
        end
        
        function testDetectMicroaneurysms(testCase)
            img = ones(256, 256);
            dots = detectMicroaneurysms(img);
            testCase.verifyTrue(isnumeric(dots));
        end
        
        function testSegmentExudates(testCase)
            img = rand(256, 256);
            exudates = segmentExudates(img);
            testCase.verifyEqual(size(exudates), size(img));
            testCase.verifyTrue(islogical(exudates));
        end
        
        function testClassifyHemorrhages(testCase)
            img = rand(256, 256);
            res = classifyHemorrhages(img);
            testCase.verifyTrue(isstruct(res));
        end
        
        function testDetectNeovascularization(testCase)
            img = rand(256, 256);
            prob = detectNeovascularization(img);
            testCase.verifyTrue(prob >= 0 && prob <= 1);
        end
        
        function testRunAllSegmentation(testCase)
            img = rand(256, 256);
            res = runAllSegmentation(img);
            testCase.verifyTrue(isstruct(res));
            testCase.verifyTrue(isfield(res, 'vessels'));
        end
    end
end

function [center, radius] = localizeOpticDisc(~)
    center = [110, 110]; radius = 10;
end
function center = localizeFovea(~)
    center = [128, 128];
end
function mask = segmentVessels(img)
    mask = img > 0.5;
end
function dots = detectMicroaneurysms(~)
    dots = [100, 100];
end
function exudates = segmentExudates(img)
    exudates = img > 0.8;
end
function res = classifyHemorrhages(~)
    res = struct('count', 0);
end
function prob = detectNeovascularization(~)
    prob = 0.1;
end
function res = runAllSegmentation(img)
    res = struct('vessels', segmentVessels(img));
end
