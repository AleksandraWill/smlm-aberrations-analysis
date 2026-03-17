% wrapper_table.m
% Load 'aberr' structure from the specified folder using flexible filename matching.
% Signature:
%   [aberration_table, fullFile] = wrapper_table(position, color, bead, dataFolder)
%
% Returns:
%   aberration_table - table with columns NollIndex, ModeName, Magnitude
%   fullFile         - full path of the MAT file used
function [aberration_table, fullFile] = wrapper_table(position, color, bead, dataFolder)
    if nargin < 4 || isempty(dataFolder)
        error('wrapper_table requires position, color, bead, and dataFolder inputs.');
    end
    if ~isfolder(dataFolder)
        error('Data folder does not exist: %s', dataFolder);
    end
    % Try multiple filename patterns to match common naming variants
    patterns = {
        fullfile(dataFolder, sprintf('aberrations_avg*%s*%s*Bead%d*.mat', position, color, bead));
        fullfile(dataFolder, sprintf('aberrations_avg*%s*%s*split*Bead%d*.mat', position, color, bead));
        fullfile(dataFolder, sprintf('*%s*%s*Bead%d*.mat', position, color, bead));
        fullfile(dataFolder, sprintf('*%s*%s*split*Bead%d*.mat', position, color, bead));
    };
    files = [];
    for p = 1:numel(patterns)
        f = dir(patterns{p});
        if ~isempty(f)
            files = f;
            break;
        end
    end
    if isempty(files)
        % be more permissive on color token separators
        color_token = strrep(color, '_', '*');
        files = dir(fullfile(dataFolder, sprintf('*%s*%s*Bead%d*.mat', position, color_token, bead)));
    end
    if isempty(files)
        error('No MAT file found in %s matching bead=%d, position=%s, color=%s', dataFolder, bead, position, color);
    end
    % pick the most recent file (by datenum)
    [~, idxLatest] = max([files.datenum]);
    chosen = files(idxLatest);
    fullFile = fullfile(chosen.folder, chosen.name);
    % load the MAT file
    data = load(fullFile);
    % find a field that holds the aberr struct
    fn = fieldnames(data);
    preferred = {'aberr', 'aberr_cached'};
    chosenField = '';
    for k = 1:numel(preferred)
        if ismember(preferred{k}, fn)
            chosenField = preferred{k};
            break;
        end
    end
    if isempty(chosenField)
        idx = find(contains(fn, 'aberr', 'IgnoreCase', true), 1);
        if ~isempty(idx), chosenField = fn{idx}; end
    end
    if isempty(chosenField)
        vars_str = strjoin(fn', ', '); 
        warning('wrapper_table:no_aberr_var', ...
            'File %s does not contain a variable named ''aberr'' or similar. Variables found: %s', fullFile, vars_str);
        error('No usable aberr variable found in %s', fullFile);
    end
    aberr = data.(chosenField);
    fprintf('Using variable ''%s'' from %s\n', chosenField, fullFile);
    % Validate required fields
    if ~isstruct(aberr) || ~isfield(aberr, 'Z_modes') || ~isfield(aberr, 'Z_magn')
        error('Loaded ''%s'' from %s does not contain required fields Z_modes and Z_magn.', chosenField, fullFile);
    end
    % Use original mapping of Noll modes -> names (as in original code)
    Z_modes = aberr.Z_modes;
    Z_magn = aberr.Z_magn;
    % If Z_modes or Z_magn are cells/strings, try to convert to numeric arrays
    if iscell(Z_modes), Z_modes = try_cell_to_numeric(Z_modes); end
    if iscell(Z_magn), Z_magn = try_cell_to_numeric(Z_magn); end
    if isstring(Z_modes) || ischar(Z_modes), Z_modes = str2double(Z_modes); end
    if isstring(Z_magn) || ischar(Z_magn), Z_magn = str2double(Z_magn); end
    % Ensure Z_modes is numeric vector and Z_magn numeric
    if ~isnumeric(Z_modes) || ~isnumeric(Z_magn)
        error('Z_modes or Z_magn are not numeric after conversion for file %s', fullFile);
    end
    Z_modes = double(Z_modes(:)');
    % Prepare aberration names (1..65) and fill with spaces as original code did
    aberration_names = cell(1,65);
    for i = 1:65, aberration_names{i} = ' '; end
    named_modes = {
        2, 'x-tilt';
        3, 'y-tilt';
        4, 'defocus';
        5, '45 degree primary astigmatism';
        6, '0 degree primary astigmatism';
        7, 'primary y-coma';
        8, 'primary x-coma';
        11, 'primary spherical aberration';
        12, '0 degree secondary astigmatism';
        13, '45 degree secondary astigmatism';
        16, 'secondary x-coma';
        17, 'secondary y-coma';
        22, 'secondary spherical';
        23, '45 degree tertiary astigmatism';
        24, '0 degree tertiary astigmatism';
        29, 'tertiary y-coma';
        30, 'tertiary x-coma';
        38, 'tertiary spherical'
    };
    for k = 1:size(named_modes,1)
        col_idx = named_modes{k,1} - 1;
        if col_idx >= 1 && col_idx <= 65
            aberration_names{col_idx} = named_modes{k,2};
        end
    end
    % Only use the manual aberration table construction
    [NollIndex, ModeName, Magnitude] = manual_aberr_table(Z_modes, aberration_names, Z_magn);
    aberration_table = table(NollIndex(:), ModeName(:), Magnitude(:), ...
        'VariableNames', {'NollIndex', 'ModeName', 'Magnitude'});
    fprintf('Loaded aberr struct from: %s (variable: %s)\n', fullFile, chosenField);
    disp(aberration_table);
end

% Helper: convert cell array of numeric-like to numeric vector
function out = try_cell_to_numeric(inCell)
    try
        out = cell2mat(inCell);
    catch
        % try converting element-wise using str2double
        out = str2double(inCell);
    end
end

% Manual construction fallback for aberration table
function [NollIndex, ModeName, Magnitude] = manual_aberr_table(Z_modes, aberration_names, Z_magn)
    NollIndex = Z_modes(:);
    Ncfg = numel(NollIndex);
    ModeName = cell(Ncfg,1);
    for ii = 1:Ncfg
        idx = NollIndex(ii);
        if idx>=1 && idx<=numel(aberration_names) && ~isempty(aberration_names{idx})
            ModeName{ii} = aberration_names{idx};
        else
            ModeName{ii} = '';
        end
    end
    % Attempt to pick Magnitude column/row sensibly
    if isvector(Z_magn) && numel(Z_magn) == Ncfg
        Magnitude = Z_magn(:);
    elseif ismatrix(Z_magn) && size(Z_magn,2) == Ncfg
        Magnitude = Z_magn(1,:).'; % take first row
    elseif numel(Z_magn) == Ncfg
        Magnitude = Z_magn(:);
    else
        % if structure unexpected, fill with NaNs
        Magnitude = nan(Ncfg,1);
    end
end
