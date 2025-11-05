
clc;
clear;
close all;

addpath(genpath('/ibmgpfs/cuizaixu_lab/congjing/toolbox/fileio-master'));
addpath(genpath('/ibmgpfs/cuizaixu_lab/congjing/toolbox/jsonlab-master'))

subjDir = dir(['/ibmgpfs/cuizaixu_lab/liyang/BrainProject25/Tsinghua_data/QC/sub-*/sub-*']);

anat_report = table;
N = 0;
for SN = 1:length(subjDir)
    if subjDir(SN).isdir
        path = fullfile(subjDir(SN).folder, subjDir(SN).name);
        subjName = subjDir(SN).name;
        T2jsonPath = dir(fullfile(path, 'anat', '*T2w.json'));
        T1jsonPath = dir(fullfile(path, 'anat', '*T1w.json'));
        
        % Check if T2jsonPath or T1jsonPath is empty
        if isempty(T2jsonPath) || isempty(T1jsonPath)
            % If either T2jsonPath or T1jsonPath is empty, continue to the next iteration
            continue;
        end
        
        N = N + 1;
        
        % Load JSON data
        T2jsonData = loadjson(fullfile(T2jsonPath.folder, T2jsonPath.name));
        T2w_snrTotal = T2jsonData.snr_total;
        T1jsonData = loadjson(fullfile(T1jsonPath.folder, T1jsonPath.name));
        T1w_snrTotal = T1jsonData.snr_total;
        
        % Assign NaN if data is empty
        if isempty(T2w_snrTotal)
            T2w_snrTotal = NaN;
        end
        if isempty(T1w_snrTotal)
            T1w_snrTotal = NaN;
        end
        
        % Report
        anat_report.subject_name{N} = subjName;
        anat_report.T1w{N} = T1w_snrTotal;
        anat_report.T2w{N} = T2w_snrTotal;
       
    end
end

%% Save the file
output_folder = '/ibmgpfs/cuizaixu_lab/tanlirou1/BP/Tsinghua/Check_EFNY_fd';
csvfilename = fullfile(output_folder, 'Tsinghua_anat_snr_1029.csv');
writetable(anat_report, csvfilename);
