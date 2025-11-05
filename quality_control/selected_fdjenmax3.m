clc;clear;
%% head-motion information of rest-1
% addpath(genpath('/ibmgpfs/cuizaixu_lab/congjing/toolbox/fileio-master'));
% addpath(genpath('/ibmgpfs/cuizaixu_lab/congjing/toolbox/jsonlab-master'))
% fMRIprep_subjDir = dir(['/ibmgpfs/cuizaixu_lab/jiahai/tsinghua/results/fmriprep_rest/sub-*/fmriprep/sub-*']);
fMRIprep_subjDir = dir(['/ibmgpfs/cuizaixu_lab/xuhaoshu/QC_folder/results/fmriprep_rest/sub-*/fmriprep/sub-*']);
sesID = '';
% taskID = 'task-switch';
taskID = 'task-rest';
runID = '3';
threshold_meanfd = 0.2;
threshold_framefd = 0.25;
frameNum_threshould = 20;
threshold_framefdmax = 3;
headmotion_report_rest_1 = f_headmotion_Jenkinson(fMRIprep_subjDir, sesID, taskID, runID, threshold_meanfd, threshold_framefd, frameNum_threshould, threshold_framefdmax);


function headmotion_report = f_headmotion_Jenkinson(fMRIprep_subjDir, sesID, taskID, runID, threshold_meanfd, threshold_framefd, frameNum_threshould, threshold_framefdmax)
%%
%% main function
headmotion_report = table;
N = 0;
%% initialize
gooddata = false(1, length(fMRIprep_subjDir));
ifoutlier_maxfd = false(1, length(fMRIprep_subjDir));
ifoutlier_meanfd = false(1, length(fMRIprep_subjDir));
ifoutlier_fdframeNum = false(1, length(fMRIprep_subjDir));
for SN = 1:length(fMRIprep_subjDir)
    if fMRIprep_subjDir(SN).isdir

        path = fullfile(fMRIprep_subjDir(SN).folder, fMRIprep_subjDir(SN).name);
        subjName = fMRIprep_subjDir(SN).name;

        if isempty(sesID) && ~isempty(taskID) && isempty(runID)
            conft_DIR = dir(fullfile(path, 'func', ['*', taskID, '*desc-confounds_timeseries.tsv']));
        elseif isempty(sesID) && ~isempty(taskID) && ~isempty(runID)
            conft_DIR = dir(fullfile(path, 'func', ['*', taskID, '*', runID, '*desc-confounds_timeseries.tsv']));
        elseif ~isempty(sesID) && ~isempty(taskID) && ~isempty(runID)
            conft_DIR = dir(fullfile(path, 'func', ['*', sesID, '*', taskID, '*', runID, '*desc-confounds_timeseries.tsv']));
        end

        if length(conft_DIR) == 0
            continue;
        end
        N = N + 1;

        confd_tsv = readtable(fullfile(conft_DIR.folder, conft_DIR.name), 'Delimiter', '\t', 'FileType', 'text');
        rmse_timeseries1 = confd_tsv.rmsd; % fd Jackson
       rmse_timeseries = str2double(rmse_timeseries1);
       rmse_timeseries(isnan(rmse_timeseries)) = NaN;
       meanfd = mean(rmse_timeseries(2:end));
        outlier_count = sum(rmse_timeseries>=threshold_framefd);
        outlier_count_max = sum(rmse_timeseries>=threshold_framefdmax);

        if outlier_count_max ~= 0
            ifoutlier_maxfd(N) = true;
        else
            ifoutlier_maxfd(N) = false;
        end

        if meanfd >= threshold_meanfd
            ifoutlier_meanfd(N) = true;
        else
            ifoutlier_meanfd(N) = false;
        end

        if outlier_count >= frameNum_threshould
            ifoutlier_fdframeNum(N)  = true;
        else
            ifoutlier_fdframeNum(N) = false;
        end
        if ~ifoutlier_meanfd(N)  && ~ifoutlier_fdframeNum(N) && ~ifoutlier_maxfd(N)
            gooddata(N) = true;
        else
            gooddata(N) = false;
        end
        % report
        headmotion_report.subject_name{N} = subjName;
        headmotion_report.good_data{N} = gooddata(N);
        headmotion_report.if_meanfd_outlier{N} = ifoutlier_meanfd(N);
        headmotion_report.if_fdframeNum_outlier{N} = ifoutlier_fdframeNum(N);

        headmotion_report.if_meanfd_max{N} = ifoutlier_maxfd(N);

        headmotion_report.threshold_mean_fd{N} = threshold_meanfd;
        headmotion_report.mean_fd{N} = meanfd;

        headmotion_report.threshold_fd_frame{N} = threshold_framefd;
        headmotion_report.outlier_framecount{N} = outlier_count;
        headmotion_report.threshould_fdframeNum{N} = frameNum_threshould;

    end
end
headmotion_report.subject_name{N+1} = 'SUM';
headmotion_report.good_data{N+1} = sum(gooddata);
headmotion_report.if_meanfd_outlier{N+1} = sum(ifoutlier_meanfd);
headmotion_report.if_fdframeNum_outlier{N+1} = sum(ifoutlier_fdframeNum);
headmotion_report.if_fdframeNum_max{N+1} = sum(ifoutlier_maxfd);
%% save the file
% output_floder = '/ibmgpfs/cuizaixu_lab/jiahai/tsinghua/results_fd';
output_floder = '/ibmgpfs/cuizaixu_lab/xuhaoshu/QC_folder/results_fd';
csvfilename = fullfile(output_floder, ['thu_BOLDheadmotion_Jenkinson_all_241116', sesID, '_', taskID, '_', runID, '.csv']);
writetable(headmotion_report, csvfilename);
end
