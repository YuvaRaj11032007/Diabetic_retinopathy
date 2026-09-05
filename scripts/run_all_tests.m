% run_all_tests.m
% Test Suite Runner for the DR Screening Pipeline.
% Runs all test files in the tests/ directory and collects results.

import matlab.unittest.TestRunner;
import matlab.unittest.TestSuite;
import matlab.unittest.plugins.DiagnosticsValidationPlugin;
import matlab.unittest.plugins.TestReportPlugin;

testsDir = fullfile('d:', 'sih_project', 'tests');
suite = TestSuite.fromFolder(testsDir);

runner = TestRunner.withTextOutput;
runner.addPlugin(DiagnosticsValidationPlugin);

reportDir = fullfile('d:', 'sih_project', 'results', 'test_reports');
if ~exist(reportDir, 'dir')
    mkdir(reportDir);
end
runner.addPlugin(TestReportPlugin.producingHTML(reportDir));

results = runner.run(suite);

numTests = numel(results);
numPassed = sum([results.Passed]);
numFailed = sum([results.Failed]);
numErrors = sum([results.Incomplete]);

fprintf('--- Test Summary ---\n');
fprintf('Total tests: %d\n', numTests);
fprintf('Passed: %d\n', numPassed);
fprintf('Failed: %d\n', numFailed);
fprintf('Errors/Incomplete: %d\n', numErrors);

if numFailed > 0 || numErrors > 0
    exit(1);
else
    exit(0);
end
