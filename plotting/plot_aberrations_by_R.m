% plot_aberrations_by_R.m
% Same as your plotting script but plots signed magnitudes (keeps sign)
% instead of absolute values. Also adds a horizontal y=0 reference line and
% updates y-labels/titles accordingly.
%
% Usage: adjust base_path / folder lists if needed and run.

clearvars; close all;

% If you ever want to toggle back to absolute values, set useSigned = false
useSigned = true;

base_path = 'D:\projekt\aberrations_measurement\data\';
aberration_folders = { ...
    'aberrations_blue_bypass', ...
    'aberrations_blue_split', ...
    'aberrations_red_blue_split_dual', ...
    'aberrations_red_bypass', ...
    'aberrations_red_split' };

centroid_folders = { ...
    'beads_blue_bypass', ...
    'beads_blue_split', ...
    'beads_red_blue_split_dual', ...
    'beads_red_bypass', ...
    'beads_red_split' };

types = {'coma', 'astigmatism', 'spherical'};

% Toggle: if true and number of plotted points < labelThreshold, label each point with its ModeName
labelPoints = true;
labelThreshold = 80;

% Where to save plots (inside the base_path)
plots_root = fullfile(base_path, 'plots');

for idx = 1:numel(aberration_folders)
    aberr_folder = aberration_folders{idx};
    centroid_folder = centroid_folders{idx};

    aberr_file = fullfile(base_path, aberr_folder, ...
        ['all_filtered_aberrations_' aberr_folder '.mat']);
    if ~isfile(aberr_file)
        warning('Aggregated aberration file not found: %s', aberr_file);
        continue;
    end

    S = load(aberr_file, 'all_results');
    if ~isfield(S, 'all_results')
        warning('File %s did not contain ''all_results'' variable.', aberr_file);
        continue;
    end
    all_results = S.all_results;

    % --- Load centroid files in centroid_folder into centroid_data struct ---
    centroid_dir = fullfile(base_path, centroid_folder);
    if ~isfolder(centroid_dir)
        warning('Centroid folder not found: %s', centroid_dir);
        continue;
    end
    centroid_files = dir(fullfile(centroid_dir, '*.mat'));
    centroid_data = struct();
    for k = 1:numel(centroid_files)
        [~, base] = fileparts(centroid_files(k).name);
        tmp = load(fullfile(centroid_dir, centroid_files(k).name));
        f = fieldnames(tmp);
        if isempty(f)
            warning('No variables in centroid file: %s', centroid_files(k).name);
            continue;
        end
        centroid_data.(base) = tmp.(f{1});
    end

    % Prepare storage for each aberration type
    types_list = types;
    Y = struct(); Rvals = struct(); modeNames = struct(); labels = struct();
    for t = 1:numel(types_list)
        Y.(types_list{t}) = [];          % numeric vector of (signed) magnitudes
        Rvals.(types_list{t}) = [];      % numeric vector of bead R
        modeNames.(types_list{t}) = {};  % cell array of ModeName strings
        labels.(types_list{t}) = {};     % optional textual labels (pos color bead)
    end

    all_fieldnames = fieldnames(all_results);
    if isempty(all_fieldnames)
        warning('No entries in all_results for %s', aberr_folder);
    end

    for fidx = 1:numel(all_fieldnames)
        fname = all_fieldnames{fidx};
        res = all_results.(fname);

        % Accept keys like:
        %   filtered_<usedFile>_pos2_blue_Bead1
        %   pos2_blue_Bead1
        tokens = regexp(fname, '(?:filtered_[^_]+_)?(?<pos>pos\d+)_(?<color>\w+)_Bead(?<bead>\d+)', 'names');
        if isempty(tokens)
            tokens = regexp(fname, '(?<pos>pos\d+)_(?<color>[a-zA-Z]+)_Bead(?<bead>\d+)', 'names');
            if isempty(tokens)
                warning('Skipping all_results entry because name did not match expected pattern: "%s"', fname);
                continue;
            end
        end

        pos = tokens.pos;      % e.g. 'pos2'
        color = tokens.color;  % e.g. 'blue'
        bead = str2double(tokens.bead);

        % Find centroid table in centroid_data
        centroid_field_names = fieldnames(centroid_data);
        centroid_key = '';
        for cfn = 1:numel(centroid_field_names)
            kname = centroid_field_names{cfn};
            if contains(lower(kname), lower(pos), 'IgnoreCase', true) && ...
               contains(lower(kname), lower(color), 'IgnoreCase', true) && ...
               contains(lower(kname), 'centroid', 'IgnoreCase', true)
                centroid_key = kname;
                break;
            end
        end

        if isempty(centroid_key)
            warning('No centroid file matching pos="%s" color="%s" for entry "%s"', pos, color, fname);
            continue;
        end

        centroids_table = centroid_data.(centroid_key);
        if ~istable(centroids_table)
            warning('Centroid data "%s" is not a table. Skipping.', centroid_key);
            continue;
        end
        if ~ismember('BeadNumber', centroids_table.Properties.VariableNames) || ...
           ~ismember('R', centroids_table.Properties.VariableNames)
            warning('Centroid table "%s" missing expected columns (BeadNumber, R). Skipping.', centroid_key);
            continue;
        end

        bead_R_row = find(centroids_table.BeadNumber == bead, 1);
        if isempty(bead_R_row)
            warning('No centroid row for Bead %d in centroid table %s', bead, centroid_key);
            continue;
        end
        bead_R = centroids_table.R(bead_R_row);

        % For each aberration type, append signed data for every row in table
        for t = 1:numel(types_list)
            type = types_list{t};
            if ~isfield(res, type)
                continue;
            end
            ab_table = res.(type);
            if ~istable(ab_table) || isempty(ab_table)
                continue;
            end
            if ~ismember('Magnitude', ab_table.Properties.VariableNames)
                warning('Aberration table for "%s" does not contain "Magnitude" column. Skipping.', type);
                continue;
            end

            % Attempt to extract ModeName column; fallback to empty if missing
            if ismember('ModeName', ab_table.Properties.VariableNames)
                mn = ab_table.ModeName;
                % convert to cellstr
                if isstring(mn), mn = cellstr(mn); end
                if iscell(mn), mn = mn(:)'; else mn = arrayfun(@(x) char(x), mn, 'UniformOutput', false); end
            else
                mn = repmat({''}, 1, height(ab_table));
            end

            % >>> CHANGE HERE: keep signed magnitudes instead of absolute values
            if useSigned
                mags = double(ab_table.Magnitude);    % preserve sign
            else
                mags = abs(double(ab_table.Magnitude));% old behaviour
            end
            mags = mags(:)'; % row vector
            n = numel(mags);
            Y.(type)(end+1:end+n) = mags;
            Rvals.(type)(end+1:end+n) = repmat(double(bead_R), 1, n);
            modeNames.(type)(end+1:end+n) = mn;
            labels.(type)(end+1:end+n) = repmat({sprintf('%s %s bead%d', pos, color, bead)}, 1, n);
        end
    end

    % Prepare output directory for this aberr_folder
    output_dir = fullfile(plots_root, aberr_folder);
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end

    % Plot for each aberration type (grouped by ModeName, colored) and save
    for t = 1:numel(types_list)
        type = types_list{t};
        Ys = Y.(type);
        Rs = Rvals.(type);
        MN = modeNames.(type);

        if isempty(Ys) || isempty(Rs) || numel(Ys) ~= numel(Rs)
            fprintf('No data to plot for %s - %s (folder %s)\n', aberr_folder, type, centroid_folder);
            continue;
        end

        % Normalize/clean ModeName entries
        MN = cellfun(@(s) char(s), MN, 'UniformOutput', false);
        MN = cellfun(@(s) strtrim(s), MN, 'UniformOutput', false);
        MN(cellfun(@isempty, MN)) = {'<unnamed>'};

        % Unique ModeNames and colors
        uniqueModes = unique(MN, 'stable');
        cmap = lines(numel(uniqueModes)); % distinct colors

        % Create figure
        fig = figure('Name', sprintf('%s - %s', aberr_folder, type), 'Visible', 'on');
        set(fig,'Units','inches','Position',[1 1 7 5]); % adjust size if desired
        hold on;
        h = gobjects(numel(uniqueModes),1);
        for mIdx = 1:numel(uniqueModes)
            um = uniqueModes{mIdx};
            idx_mask = strcmp(MN, um);
            if ~any(idx_mask), continue; end
            % scatter with signed Y values
            h(mIdx) = scatter(Rs(idx_mask), Ys(idx_mask), 60, 'MarkerFaceColor', cmap(mIdx,:), ...
                'MarkerEdgeColor', 'k', 'DisplayName', um);
        end

        % Add horizontal zero line for reference
        h0 = yline(0, '--', 'Color', [0.2 0.2 0.2], 'LineWidth', 0.9);
        h0.DisplayName = '0';

        % Update y-label and title to reflect signed values
        ylabel(sprintf('%s Magnitude', type));
        title(sprintf('%s: %s vs. R (colored by ModeName)', strrep(aberr_folder,'_','\_'), type));
        xlabel('Radius from center (R)');
        grid on;

        % Clean legend labels (remove underscores, prefix) and show literal text
        lg = legend('Location','bestoutside');
        if isgraphics(lg)
            % replace underscores with spaces and strip common prefix
            labels = lg.String;
            if iscell(labels)
                labels = strrep(labels, '_', ' ');
                labels = regexprep(labels, '^aberrations_', '', 'ignorecase');
                lg.String = labels;
            end
            lg.Interpreter = 'none';
            lg.FontSize = 9;
        end
        hold off;

        % Optionally add textual labels next to each point (only for small sets)
        if labelPoints && numel(Ys) <= labelThreshold
            ax = gca;
            hold(ax, 'on');
            for iPt = 1:numel(Ys)
                % show signed value in the text if desired (uncomment numeric label)
                % txtVal = sprintf('%.3g', Ys(iPt));
                % text(Rs(iPt) + 0.5, Ys(iPt), txtVal, 'FontSize', 8, 'Color', [0 0 0], 'Interpreter', 'none');

                text(Rs(iPt) + 0.5, Ys(iPt), MN{iPt}, 'FontSize', 8, 'Color', [0 0 0], 'Interpreter', 'none');
            end
            hold(ax, 'off');
        end

        % Build sanitized filename base
        ts = datestr(now,'yyyymmdd_HHMMSS');
        safe_aberr = regexprep(aberr_folder,'[^a-zA-Z0-9\-]','_');
        safe_type = regexprep(type,'[^a-zA-Z0-9\-]','_');
        fname_base = sprintf('%s_%s_%s', safe_aberr, safe_type, ts);

        % Save figure: PDF and FIG. Use exportgraphics if available.
        pdf_file = fullfile(output_dir, [fname_base '.pdf']);
        fig_file = fullfile(output_dir, [fname_base '.fig']);

        try
            % Vector PDF if possible
            exportgraphics(fig, pdf_file, 'ContentType', 'vector');
            % Save MATLAB figure for later editing
            savefig(fig, fig_file);
        catch saveErr
            % Use the exception identifier if available, otherwise a generic id
            if isfield(saveErr, 'identifier') && ~isempty(saveErr.identifier)
                warnId = saveErr.identifier;
            else
                warnId = 'plot:exportgraphicsFailed';
            end

            % Emit a properly formatted warning using the identifier
            warning(warnId, '%s. Using print/saveas fallback.', saveErr.message);

            % Fallback saving for older MATLAB versions
            print(fig, pdf_file, '-dpdf');
            saveas(fig, fig_file);
        end

        fprintf('Saved plots for %s - %s -> %s (pdf/fig)\n', aberr_folder, type, output_dir);
        % optionally close the figure if you don't want them open
        % close(fig);
    end
end
