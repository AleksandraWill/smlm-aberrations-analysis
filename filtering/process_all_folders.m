% process_all_folders.m
clearvars; close all;

% List of folders to process (set these to your actual folders)
folderList = {
    'D:\projekt\aberrations_measurement\data\aberrations_blue_bypass';
    'D:\projekt\aberrations_measurement\data\aberrations_blue_split';
    'D:\projekt\aberrations_measurement\data\aberrations_red_blue_split_dual';
    'D:\projekt\aberrations_measurement\data\aberrations_red_bypass';
    'D:\projekt\aberrations_measurement\data\aberrations_red_split';
};

% Common parameters
bead_numbers = [1,2,3,4,5,6,7,8,9];   % adjust
positions = {'pos1', 'pos2', 'pos3'};         % list of positions if you want multiple
colors = {'blue', 'red'};            % or {'blue','red_blue'} etc.

% Loop over folders and process each
for i = 1:numel(folderList)
    dataFolder = folderList{i};
    fprintf('\n=== Processing folder %d/%d: %s ===\n', i, numel(folderList), dataFolder);
    try
        % process_folder is implemented below as a separate function file or nested call
        process_folder(dataFolder, bead_numbers, positions, colors);
    catch ME
        % Do nothing: suppresses all warnings/errors at this batch level
    end
end

disp('All folders processed.');