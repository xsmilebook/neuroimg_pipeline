clc;clear;
%% head-motion information of diffusion
addpath(genpath('/ibmgpfs/cuizaixu_lab/congjing/toolbox/fileio-master'));
addpath(genpath('/ibmgpfs/cuizaixu_lab/congjing/toolbox/jsonlab-master'))
% qsiprep_subjDir = dir(['/ibmgpfs/cuizaixu_lab/jiahai/tsinghua/results/qsiprep/sub-*/qsiprep/sub-*']);
qsiprep_subjDir = dir(['/ibmgpfs/cuizaixu_lab/liyang/BrainProject25/EFI_data/results/qsiprep/sub-*/qsiprep/sub-*']);
headmotion_report_rest_1 = f_headmotion_power(qsiprep_subjDir);


function headmotion_report = f_headmotion_power(qsiprep_subjDir)
%%
%% main function
headmotion_report = table;
N = 0;
for SN = 1:length(qsiprep_subjDir)
    if qsiprep_subjDir(SN).isdir
        
        path = fullfile(qsiprep_subjDir(SN).folder, qsiprep_subjDir(SN).name);
        subjName = qsiprep_subjDir(SN).name;
        conft_DIR = dir(fullfile(path, 'dwi', ['*confounds.tsv']));
        
        
        if isempty(conft_DIR)
            continue;
        end
        N = N + 1;
        
        confd_tsv = readtable(fullfile(conft_DIR.folder, conft_DIR.name), 'Delimiter', '\t', 'FileType', 'text');
        rmse_timeseries1 = confd_tsv.framewise_displacement; % fd Jackson
        rmse_timeseries = str2double(rmse_timeseries1);
        rmse_timeseries(isnan(rmse_timeseries)) = NaN;
        meanfd = mean(rmse_timeseries(2:end));
        
        % report
        headmotion_report.subject_name{N} = subjName;
        headmotion_report.mean_fd{N} = meanfd;
    end
    
end
headmotion_report.subject_name{N+1} = 'SUM';

%% save the file
output_floder = '/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/EFI/QC_folder';
% mkdir(output_floder);
csvfilename = fullfile(output_floder, ['thu_Diffusionheadmotion_THU251105.csv']);
writetable(headmotion_report, csvfilename);
end
