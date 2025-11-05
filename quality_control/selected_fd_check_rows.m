clc;clear;
%% head-motion information of rest-1
% addpath(genpath('/ibmgpfs/cuizaixu_lab/congjing/toolbox/fileio-master'));
% addpath(genpath('/ibmgpfs/cuizaixu_lab/congjing/toolbox/jsonlab-master'))
fMRIprep_subjDir = dir(['/ibmgpfs/cuizaixu_lab/liyang/BrainProject25/EFI_data/results/fmriprep_nback/sub-*/fmriprep/sub-*']);
sesID = '';
taskID = 'task-nback';
runID = '';
threshold_meanfd = 0.2;
threshold_framefd = 0.2;
frameNum_threshould = 20;
threshold_framefdmax = 3;
headmotion_report_rest_1 = f_headmotion_Jenkinson(fMRIprep_subjDir, sesID, taskID, runID, threshold_meanfd, threshold_framefd, frameNum_threshould, threshold_framefdmax);
% -------------------------------------------------------------------------
% 函数定义
% -------------------------------------------------------------------------
function headmotion_report = f_headmotion_Jenkinson(fMRIprep_subjDir, sesID, taskID, runID, threshold_meanfd, threshold_framefd, frameNum_threshould, threshold_framefdmax)

%% main function (优化版本)
num_potential_subjects = length(fMRIprep_subjDir);
results_cell = cell(num_potential_subjects, 1); % 用于存储结果结构体
N = 0; % 实际处理的有效受试者计数

for SN = 1:num_potential_subjects
    if fMRIprep_subjDir(SN).isdir
        path = fullfile(fMRIprep_subjDir(SN).folder, fMRIprep_subjDir(SN).name);
        subjName = fMRIprep_subjDir(SN).name;
        
        % --- 简化和通用化的路径搜索逻辑 ---
        pattern = '*';
        if ~isempty(sesID), pattern = [pattern, sesID, '*']; end
        if ~isempty(taskID), pattern = [pattern, taskID, '*']; end
        if ~isempty(runID), pattern = [pattern, runID, '*']; end
        pattern = [pattern, 'desc-confounds_timeseries.tsv'];
        
        conft_DIR = dir(fullfile(path, 'func', pattern));
        
        if length(conft_DIR) == 0
            continue; 
        end
        
        % 读取混淆变量文件
        confd_tsv = readtable(fullfile(conft_DIR.folder, conft_DIR.name), 'Delimiter', '\t', 'FileType', 'text');
        
        %
        nrows = height(confd_tsv);
        if ~ismember(nrows, [219 204])
            fprintf('Skip %s: confounds rows = %d. Only rows are processed.\n', subjName, nrows); 
            continue; 
        end
        
        % 计数器只针对有效受试者增加
        N = N + 1;
        
        % --- 数据处理和转换 ---
        rmse_timeseries1 = confd_tsv.rmsd; % fd Jackson
        % 确保转换为 double，并处理可能的字符串/NaN
        if iscell(rmse_timeseries1)
             rmse_timeseries = str2double(rmse_timeseries1);
        else
             rmse_timeseries = rmse_timeseries1;
        end
        
        % meanfd 从第二帧开始计算 (忽略第一帧)
        meanfd = mean(rmse_timeseries(2:end), 'omitnan');
        maxfd = max(rmse_timeseries(2:end), [], 'omitnan'); % 计算最大 FD
        
        % 统计超出阈值的帧数
        outlier_count = sum(rmse_timeseries(2:end) >= threshold_framefd);
        outlier_count_max = sum(rmse_timeseries(2:end) >= threshold_framefdmax);
        
        % --- QC 逻辑判断 (使用逻辑数组，避免 if/else 块，更简洁) ---
        is_meanfd_outlier = (meanfd >= threshold_meanfd);
        is_fdframeNum_outlier = (outlier_count >= frameNum_threshould);
        is_maxfd_outlier = (outlier_count_max > 0); 
        
        % 整体判断：数据是否合格 (所有条件都满足)
        gooddata = ~is_meanfd_outlier && ~is_fdframeNum_outlier && ~is_maxfd_outlier;
        
        % --- 存储结果到结构体 (高效存储) ---
        subject_data = struct(...
            'subject_name', subjName, ...
            'good_data', gooddata, ...
            'if_meanfd_outlier', is_meanfd_outlier, ...
            'if_fdframeNum_outlier', is_fdframeNum_outlier, ...
            'if_maxfd_outlier', is_maxfd_outlier, ... % 统一字段名
            'threshold_mean_fd', threshold_meanfd, ...
            'mean_fd', meanfd, ...
            'threshold_fd_frame', threshold_framefd, ...
            'outlier_framecount', outlier_count, ...
            'threshould_fdframeNum', frameNum_threshould, ...
            'max_fd', maxfd, ... % 新增最大FD
            'total_frames', nrows ... % 新增总帧数
            );
        
        results_cell{N} = subject_data;
    end
end

%% 2. 构造最终表格
% 将结构体数组转换为 table
valid_results = results_cell(1:N);
if N > 0
    headmotion_report = struct2table(cell2mat(valid_results));
else
    % 如果没有有效数据，创建一个空表并继续
    warning('No valid subjects were processed.');
    headmotion_report = table(...
        'Size', [0, 12], ...
        'VariableTypes', {'string','logical','logical','logical','logical','double','double','double','double','double','double','double'}, ...
        'VariableNames', {'subject_name','good_data','if_meanfd_outlier','if_fdframeNum_outlier','if_maxfd_outlier','threshold_mean_fd','mean_fd','threshold_fd_frame','outlier_framecount','threshould_fdframeNum','max_fd','total_frames'} ...
    );
end

%% 3. 增加汇总行 (SUM)

if N > 0
    % 计算汇总数据
    sum_good_data = sum(headmotion_report.good_data);
    sum_if_meanfd_outlier = sum(headmotion_report.if_meanfd_outlier);
    sum_if_fdframeNum_outlier = sum(headmotion_report.if_fdframeNum_outlier);
    sum_if_maxfd_outlier = sum(headmotion_report.if_maxfd_outlier);
    
    % 创建汇总行
    summary_row = table(...
        {'SUM'}, sum_good_data, sum_if_meanfd_outlier, sum_if_fdframeNum_outlier, sum_if_maxfd_outlier, ...
        NaN, NaN, NaN, NaN, NaN, NaN, NaN, ... 
        'VariableNames', headmotion_report.Properties.VariableNames...
        );
    
    headmotion_report = [headmotion_report; summary_row];
end

%% 4. 保存文件
output_floder = '/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/EFI/QC_folder';
% 确保输出目录存在
if ~exist(output_floder, 'dir')
    mkdir(output_floder);
end
csvfilename = fullfile(output_floder, ['EFI_BOLDheadmotion_Jenkinson_251105', sesID, '_', taskID, '_', runID, '.csv']);
writetable(headmotion_report, csvfilename);

end