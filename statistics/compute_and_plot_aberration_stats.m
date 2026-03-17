% compute_and_plot_aberration_stats.m
% Combined script/function that:
%  - uses the robust folder / centroid handling from plot_aberrations_by_R.m
%  - computes per-folder statistics (mean(|mag|), RMS, std), per-mode CSVs,
%    and radius-binned statistics (and saves CSVs + plots) from compute_and_plot_aberration_stats.m
%
% Defaults (call with no args to use these):
%   base_path = 'D:\projekt\aberrations_measurement\data\';
%   aberration_folders = { 'aberrations_blue_bypass', 'aberrations_blue_split', ...
%                         'aberrations_red_blue_split_dual', 'aberrations_red_bypass', ...
%                         'aberrations_red_split' };
%   centroid_folders = { 'beads_blue_bypass', 'beads_blue_split', ...
%                        'beads_red_blue_split_dual', 'beads_red_bypass', ...
%                        'beads_red_split' };
%   types = {'coma','astigmatism','spherical'};
%
% Usage:
%   stats = compute_and_plot_aberration_stats();          % use defaults
%   stats = compute_and_plot_aberration_stats(base_path, aberration_folders, centroid_folders, types, ...)
% Optional name/value pairs:
%   'nBins'    - number of R bins (default 6)
%   'binEdges' - explicit bin edges vector (overrides nBins)
%   'savePDF'  - logical, save PDFs (default true)
%   'closeFigs' - logical, close figures after saving (default false)
%
% Outputs under <base_path>/plots/stats_extended/:
%  - stats_per_mode_<type>.csv (combined per-mode summary across folders)
%  - stats_binned_<folder>_<type>.csv (per-folder binned stats)
%  - binned_summary_<type>_*.pdf/.fig (overlayed binned plots)
%  - stats_summary.csv (per-folder mean & RMS summary)
%
% Returns:
%  stats struct with combined_by_type, per-folder raw and binned results, binEdges, etc.

function stats = compute_and_plot_aberration_stats_v2(base_path, aberration_folders, centroid_folders, types, varargin)

    % ----------------------------
    % Defaults
    % ----------------------------
    if nargin < 1 || isempty(base_path)
        base_path = 'D:\projekt\aberrations_measurement\data\';
    end
    if nargin < 2 || isempty(aberration_folders)
        aberration_folders = { ...
            'aberrations_blue_bypass', ...
            'aberrations_blue_split', ...
            'aberrations_red_blue_split_dual', ...
            'aberrations_red_bypass', ...
            'aberrations_red_split' };
    end
    if nargin < 3 || isempty(centroid_folders)
        centroid_folders = { ...
            'beads_blue_bypass', ...
            'beads_blue_split', ...
            'beads_red_blue_split_dual', ...
            'beads_red_bypass', ...
            'beads_red_split' };
    end
    if nargin < 4 || isempty(types)
        types = {'coma','astigmatism','spherical'};
    end

    % parse optional name/value pairs
    p = inputParser;
    addParameter(p, 'nBins', 6, @(x) isnumeric(x) && isscalar(x) && x>0);
    addParameter(p, 'binEdges', [], @(x) isempty(x) || (isnumeric(x) && isvector(x)));
    addParameter(p, 'savePDF', true, @islogical);
    addParameter(p, 'closeFigs', false, @islogical); % keep figures open by default
    parse(p, varargin{:});
    nBins = p.Results.nBins;
    binEdgesUser = p.Results.binEdges;
    savePDF = p.Results.savePDF;
    closeFigs = p.Results.closeFigs;

    % ----------------------------
    % Prepare output structure/dirs
    % ----------------------------
    out_root = fullfile(base_path, 'plots', 'stats_extended');
    if ~exist(out_root,'dir'), mkdir(out_root); end
    permode_dir = fullfile(out_root, 'per_mode_csv'); if ~exist(permode_dir,'dir'), mkdir(permode_dir); end
    binned_dir = fullfile(out_root, 'binned_csv');   if ~exist(binned_dir,'dir'), mkdir(binned_dir); end
    plots_dir = fullfile(out_root, 'plots');         if ~exist(plots_dir,'dir'), mkdir(plots_dir); end
    summary_dir = fullfile(out_root, 'summary');     if ~exist(summary_dir,'dir'), mkdir(summary_dir); end

    nFolders = numel(aberration_folders);

    % initialize outputs (stats stays scalar)
    stats = struct();
    stats.base_path = base_path;
    stats.folders = aberration_folders;
    stats.types = types;
    combined_by_type = struct();
    for t = 1:numel(types)
        combined_by_type.(types{t}) = table([], [], [], [], 'VariableNames', {'folder','ModeName','R','Magnitude'});
    end

    % raw per-folder storage (cell array)
    folder_raw_all = cell(1, nFolders);
    % binned per-folder storage (cell array)
    folder_binned_all = cell(1, nFolders);

    % ----------------------------
    % Main loop: load and aggregate per-folder
    % ----------------------------
    for idx = 1:nFolders
        aberr_folder = aberration_folders{idx};
        % find matching centroid folder by index if available, else empty
        centroid_folder = '';
        if idx <= numel(centroid_folders)
            centroid_folder = centroid_folders{idx};
        end
        fprintf('Processing folder %d/%d: %s\n', idx, nFolders, aberr_folder);

        aberr_file = fullfile(base_path, aberr_folder, sprintf('all_filtered_aberrations_%s.mat', aberr_folder));
        if ~isfile(aberr_file)
            warning('plot:missingAggregatedFile', 'Aggregated file not found: %s — skipping folder', aberr_file);
            folder_raw_all{idx} = struct(); % placeholder
            continue;
        end

        S = load(aberr_file,'all_results');
        if ~isfield(S,'all_results')
            warning('plot:missingAllResults', 'File %s missing variable all_results — skipping folder', aberr_file);
            folder_raw_all{idx} = struct();
            continue;
        end
        all_results = S.all_results;

        % Load centroid files for this centroid_folder (robust handling)
        centroid_data = struct();
        if ~isempty(centroid_folder)
            centroid_dir = fullfile(base_path, centroid_folder);
            if isfolder(centroid_dir)
                centroid_files = dir(fullfile(centroid_dir, '*.mat'));
                for k = 1:numel(centroid_files)
                    [~, base] = fileparts(centroid_files(k).name);
                    C = load(fullfile(centroid_dir, centroid_files(k).name));
                    fn = fieldnames(C);
                    if isempty(fn), continue; end
                    centroid_data.(base) = C.(fn{1});
                end
            else
                warning('plot:missingCentroidFolder', 'Centroid folder not found: %s — R values will be missing for this folder', fullfile(base_path, centroid_folder));
            end
        end

        % Initialize folder_raw tables per type
        folder_raw = struct();
        for t = 1:numel(types)
            folder_raw.(types{t}) = table([], [], [], 'VariableNames', {'ModeName','R','Magnitude'});
        end

        fnames = fieldnames(all_results);
        for f = 1:numel(fnames)
            entry_name = fnames{f};
            res = all_results.(entry_name);

            % parse pos/color/bead from entry_name (per plotting code)
            tokens = regexp(entry_name, '(?:filtered_[^_]+_)?(?<pos>pos\d+)_(?<color>\w+)_Bead(?<bead>\d+)', 'names');
            if isempty(tokens)
                tokens = regexp(entry_name, '(?<pos>pos\d+)_(?<color>[a-zA-Z]+)_Bead(?<bead>\d+)', 'names');
            end
            if isempty(tokens)
                pos = ''; color = ''; bead = NaN;
            else
                pos = tokens.pos;
                color = tokens.color;
                bead = str2double(tokens.bead);
            end

            % Find bead R using centroid_data. Use permissive matching of centroid filename keys.
            bead_R = NaN;
            if ~isempty(pos) && ~isempty(fieldnames(centroid_data))
                keys = fieldnames(centroid_data);
                for k = 1:numel(keys)
                    kname = keys{k};
                    if contains(kname, pos, 'IgnoreCase', true) && contains(kname, color, 'IgnoreCase', true) && contains(kname, 'centroid', 'IgnoreCase', true)
                        ctab = centroid_data.(kname);
                        if istable(ctab) && ismember('BeadNumber', ctab.Properties.VariableNames) && ismember('R', ctab.Properties.VariableNames)
                            row = find(ctab.BeadNumber == bead, 1);
                            if ~isempty(row)
                                bead_R = ctab.R(row);
                                break;
                            end
                        end
                    end
                end
            end

            % iterate types and append rows
            for tt = 1:numel(types)
                type = types{tt};
                if ~isfield(res, type), continue; end
                ab_table = res.(type);
                if ~istable(ab_table) || isempty(ab_table), continue; end
                if ~ismember('Magnitude', ab_table.Properties.VariableNames), continue; end

                % ModeName extraction (robust)
                if ismember('ModeName', ab_table.Properties.VariableNames)
                    mn = ab_table.ModeName;
                    if isstring(mn), mn = cellstr(mn); end
                    if iscell(mn)
                        mn_cell = mn(:);
                    else
                        % fallback: force char conversion
                        mn_cell = arrayfun(@(x) char(x), mn, 'UniformOutput', false);
                        mn_cell = mn_cell(:);
                    end
                else
                    mn_cell = repmat({'<unnamed>'}, height(ab_table), 1);
                end

                mags = abs(double(ab_table.Magnitude(:)));
                valid = ~isnan(mags);
                if ~any(valid), continue; end
                mags = mags(valid);
                mn_cell = mn_cell(valid);

                n = numel(mags);
                Rcol = repmat(bead_R, n, 1);
                Tnew = table(mn_cell, Rcol, mags, 'VariableNames', {'ModeName','R','Magnitude'});
                folder_raw.(type) = [folder_raw.(type); Tnew]; %#ok<AGROW>

                folderCol = repmat({aberr_folder}, n, 1);
                Tcombined = table(folderCol, mn_cell, Rcol, mags, 'VariableNames', {'folder','ModeName','R','Magnitude'});
                combined_by_type.(type) = [combined_by_type.(type); Tcombined]; %#ok<AGROW>
            end
        end

        folder_raw_all{idx} = folder_raw;
    end

    % Save raw and combined into stats scalar
    stats.folder_raw = folder_raw_all;
    stats.combined_by_type = combined_by_type;

    % ----------------------------
    % Per-folder summary statistics (mean_abs, std_abs, rms)
    % ----------------------------
    stats_summary = cell(0,7); % folder, type, count, mean_abs, std_abs, rms, std_mag
    for idx = 1:nFolders
        aberr_folder = aberration_folders{idx};
        folder_raw = folder_raw_all{idx};
        if isempty(folder_raw) || ~isstruct(folder_raw)
            for tt = 1:numel(types)
                stats_summary(end+1,:) = {aberr_folder, types{tt}, 0, NaN, NaN, NaN, NaN}; %#ok<AGROW>
            end
            continue;
        end
        for tt = 1:numel(types)
            type = types{tt};
            Traw = folder_raw.(type);
            if isempty(Traw)
                stats_summary(end+1,:) = {aberr_folder, type, 0, NaN, NaN, NaN, NaN}; %#ok<AGROW>
                continue;
            end
            mags = double(Traw.Magnitude);
            mags = mags(~isnan(mags));
            if isempty(mags)
                stats_summary(end+1,:) = {aberr_folder, type, 0, NaN, NaN, NaN, NaN}; %#ok<AGROW>
                continue;
            end
            cnt = numel(mags);
            mean_abs = mean(mags);
            std_abs = std(mags);
            rms_val = sqrt(mean(mags.^2));
            std_mag = std(mags);
            stats_summary(end+1,:) = {aberr_folder, type, cnt, mean_abs, std_abs, rms_val, std_mag}; %#ok<AGROW>
        end
    end

    % write the summary CSV
    Tsum = cell2table(stats_summary, 'VariableNames', {'folder','type','count','mean_abs','std_abs','rms','std_mag'});
    summary_csv = fullfile(summary_dir, 'stats_summary.csv');
    try
        writetable(Tsum, summary_csv);
        fprintf('Wrote per-folder summary CSV to %s\n', summary_csv);
    catch E
        warnId = 'plot:writeCSVFailed';
        if isfield(E,'identifier') && ~isempty(E.identifier), warnId = E.identifier; end
        warning(warnId, 'Failed writing CSV %s: %s', summary_csv, E.message);
    end

    stats.summary_table = Tsum;  % include table in returned struct
    stats.summary_csv = summary_csv;

    % ----------------------------
    % Per-mode CSVs (combined across folders)
    % ----------------------------
    for tt = 1:numel(types)
        type = types{tt};
        Tcomb = combined_by_type.(type);
        if isempty(Tcomb)
            fprintf('No combined data for type %s — skipping per-mode CSV\n', type);
            continue;
        end

        % normalize ModeName column
        modeCol = Tcomb.ModeName;
        if iscell(modeCol)
            ModeNames = cellfun(@char, modeCol, 'UniformOutput', false);
        elseif isstring(modeCol)
            ModeNames = cellstr(modeCol);
        else
            ModeNames = cellfun(@char, modeCol, 'UniformOutput', false);
        end
        Tcomb.ModeName = ModeNames;

        uniqueModes = unique(ModeNames, 'stable');
        rows = {};
        for m = 1:numel(uniqueModes)
            mode = uniqueModes{m};
            sel = strcmp(Tcomb.ModeName, mode);
            if ~any(sel), continue; end
            sub = Tcomb(sel,:);
            cnt = height(sub);
            mags = double(sub.Magnitude);
            mean_abs = mean(mags);
            std_abs = std(mags);
            rms_val = sqrt(mean(mags.^2));
            rows(end+1,:) = {mode, cnt, mean_abs, std_abs, rms_val}; %#ok<AGROW>
        end

        if ~isempty(rows)
            Tout = cell2table(rows, 'VariableNames', {'ModeName','count','mean_abs','std_abs','rms'});
            outfn = fullfile(permode_dir, sprintf('stats_per_mode_%s.csv', type));
            try
                writetable(Tout, outfn);
                fprintf('Wrote per-mode CSV for %s -> %s\n', type, outfn);
            catch E
                warnId = 'plot:writeCSVFailed';
                if isfield(E,'identifier') && ~isempty(E.identifier), warnId = E.identifier; end
                warning(warnId, 'Failed to write %s: %s', outfn, E.message);
            end
        end
    end

    % ----------------------------
    % Radius-binned statistics
    % ----------------------------
    % gather all R values to determine bins if needed
    allR = [];
    for tt = 1:numel(types)
        Tcomb = combined_by_type.(types{tt});
        if ~isempty(Tcomb)
            allR = [allR; double(Tcomb.R)]; %#ok<AGROW>
        end
    end
    allR = allR(~isnan(allR));
    if isempty(allR)
        maxR = 0;
    else
        maxR = max(allR);
    end

    if isempty(binEdgesUser)
        if maxR <= 0
            binEdges = linspace(0, 1, nBins+1);
        else
            binEdges = linspace(0, maxR, nBins+1);
        end
    else
        binEdges = binEdgesUser(:)';
    end
    binCenters = (binEdges(1:end-1) + binEdges(2:end))/2;
    nBinsActual = numel(binCenters);

    % For each folder and type compute binned stats and save CSV
    for idx = 1:nFolders
        aberr_folder = aberration_folders{idx};
        folder_raw = folder_raw_all{idx};
        if isempty(folder_raw) || ~isstruct(folder_raw)
            % write empty placeholder CSVs to indicate absence
            for tt = 1:numel(types)
                type = types{tt};
                outfn = fullfile(binned_dir, sprintf('stats_binned_%s_%s.csv', aberr_folder, type));
                Tout = table(binEdges(1:end-1)', binEdges(2:end)', binCenters', zeros(nBinsActual,1), nan(nBinsActual,1), nan(nBinsActual,1), nan(nBinsActual,1), ...
                    'VariableNames', {'binStart','binEnd','binCenter','count','mean_abs','std_abs','rms'});
                try
                    writetable(Tout, outfn);
                catch
                    % ignore
                end
            end
            folder_binned_all{idx} = struct(); % placeholder
            continue;
        end

        folder_binned = struct();
        for tt = 1:numel(types)
            type = types{tt};
            Traw = folder_raw.(type);
            if isempty(Traw)
                outfn = fullfile(binned_dir, sprintf('stats_binned_%s_%s.csv', aberr_folder, type));
                Tout = table(binEdges(1:end-1)', binEdges(2:end)', binCenters', zeros(nBinsActual,1), nan(nBinsActual,1), nan(nBinsActual,1), nan(nBinsActual,1), ...
                    'VariableNames', {'binStart','binEnd','binCenter','count','mean_abs','std_abs','rms'});
                try writetable(Tout, outfn); catch, end
                folder_binned.(type) = Tout;
                continue;
            end

            % normalize ModeName
            if iscell(Traw.ModeName)
                ModeNames = cellfun(@char, Traw.ModeName, 'UniformOutput', false);
            elseif isstring(Traw.ModeName)
                ModeNames = cellstr(Traw.ModeName);
            else
                ModeNames = cellfun(@char, Traw.ModeName, 'UniformOutput', false);
            end
            Rcol = double(Traw.R);
            mags = double(Traw.Magnitude);

            bin_count = zeros(nBinsActual,1);
            bin_mean = nan(nBinsActual,1);
            bin_std = nan(nBinsActual,1);
            bin_rms = nan(nBinsActual,1);

            for b = 1:nBinsActual
                sel = Rcol >= binEdges(b) & Rcol < binEdges(b+1);
                if b == nBinsActual
                    sel = Rcol >= binEdges(b) & Rcol <= binEdges(b+1);
                end
                if ~any(sel)
                    bin_count(b) = 0;
                    continue;
                end
                d = mags(sel);
                d = d(~isnan(d));
                if isempty(d)
                    bin_count(b) = 0;
                    continue;
                end
                bin_count(b) = numel(d);
                bin_mean(b) = mean(d);
                bin_std(b) = std(d);
                bin_rms(b) = sqrt(mean(d.^2));
            end

            Tout = table(binEdges(1:end-1)', binEdges(2:end)', binCenters', bin_count, bin_mean, bin_std, bin_rms, ...
                'VariableNames', {'binStart','binEnd','binCenter','count','mean_abs','std_abs','rms'});
            outfn = fullfile(binned_dir, sprintf('stats_binned_%s_%s.csv', aberr_folder, type));
            try
                writetable(Tout, outfn);
                fprintf('Wrote binned CSV: %s\n', outfn);
            catch E
                warnId = 'plot:writeCSVFailed';
                if isfield(E,'identifier') && ~isempty(E.identifier), warnId = E.identifier; end
                warning(warnId, 'Failed to write %s: %s', outfn, E.message);
            end
            folder_binned.(type) = Tout;
        end
        folder_binned_all{idx} = folder_binned;
    end

    % ----------------------------
    % Corrected block: Plot binned results per type (overlay folders)
    % - Shows per-folder mean±std numbers in the legend (colors preserved)
    % - Cleans folder names (underscores -> spaces, removes "aberrations_" prefix)
    % - Uses plotted handles when creating legend so colors/markers match
    % - Honors closeFigs flag (fig remains open if closeFigs == false)
    
    colors = lines(nFolders);
    for tt = 1:numel(types)
        type = types{tt};
        plot_means = nan(nBinsActual, nFolders);
        plot_stem = nan(nBinsActual, nFolders);
        plot_counts = zeros(nBinsActual, nFolders);
    
        % Collect binned values into matrices
        for idx = 1:nFolders
            folder_binned = folder_binned_all{idx};
            if ~isempty(folder_binned) && isstruct(folder_binned) && isfield(folder_binned, type)
                Tout = folder_binned.(type);
                plot_means(:,idx) = Tout.mean_abs;
                plot_stem(:,idx) = Tout.std_abs ./ sqrt(max(1, Tout.count)); % SEM for errorbars
                plot_counts(:,idx) = Tout.count;
            end
        end
    
        if all(all(isnan(plot_means)))
            fprintf('No binned data for type %s, skipping combined plot\n', type);
            continue;
        end
    
        % Create figure
        fig = figure('Name', sprintf('Binned_summary_%s', type), 'Visible', 'on');
        set(fig, 'Units','inches', 'Position', [1 1 10 6]);
        hold on;
    
        % Prepare storage for plotted handles and legend labels
        hLines = gobjects(nFolders,1);
        leg = cell(1, nFolders);
    
        for idx = 1:nFolders
            y = plot_means(:,idx);
            if all(isnan(y)), continue; end
    
            % Plot mean with errorbars (SEM)
            hLines(idx) = errorbar(binCenters, y, plot_stem(:,idx), 'o-', ...
                'Color', colors(idx,:), 'LineWidth', 1.2, 'MarkerFaceColor', colors(idx,:));
    
            % Compute overall mean & std for this folder/type from folder_raw_all (match CSV)
            overall_mean = NaN;
            overall_std  = NaN;
            if idx <= numel(folder_raw_all) && isstruct(folder_raw_all{idx}) && isfield(folder_raw_all{idx}, type)
                Mvec = double(folder_raw_all{idx}.(type).Magnitude);
                Mvec = Mvec(~isnan(Mvec));
                if ~isempty(Mvec)
                    overall_mean = mean(Mvec);
                    overall_std  = std(Mvec);
                end
            end
    
            % Build cleaned short name (remove prefix and convert underscores)
            shortname = regexprep(aberration_folders{idx}, '^aberrations_', '', 'ignorecase');
            shortname = strrep(shortname, '_', ' ');
    
            % Compose label with numeric mean ± std (compact format)
            if ~isnan(overall_mean)
                meanStr = sprintf('%.3g', overall_mean);
                stdStr  = sprintf('%.3g', overall_std);
                leg{idx} = sprintf('%s: %s ± %s', shortname, meanStr, stdStr);
            else
                leg{idx} = shortname;
            end
        end
    
        % Keep only valid handles/labels so legend matches plotted items
        isValidHandle = arrayfun(@(h) isgraphics(h), hLines);
        hValid = hLines(isValidHandle);
        labels = leg(isValidHandle);
    
        xlabel('Radius (R)');
        ylabel(sprintf('mean(|%s|) per bin', type));
        title(sprintf('Binned mean(|%s|) vs R — folders overlay', type));
        grid on;
    
        if ~isempty(hValid)
            % Show literal labels (no TeX interpretation of underscores etc.)
            lg = legend(hValid, labels, 'Location', 'bestoutside', 'Interpreter', 'none', 'FontSize', 9);
            % Optionally make legend multi-column to reduce height:
            % lg.NumColumns = 1;  % set to 2 if you prefer two columns
        end
    
        hold off;
    
        % Save plot (PDF + FIG) with robust fallback
        safe_type = regexprep(type, '[^a-zA-Z0-9\-]', '_');
        ts = datestr(now, 'yyyymmdd_HHMMSS');
        fname_base = sprintf('binned_summary_%s_%s', safe_type, ts);
        pdf_file = fullfile(plots_dir, [fname_base '.pdf']);
        fig_file = fullfile(plots_dir, [fname_base '.fig']);
        try
            if savePDF
                exportgraphics(fig, pdf_file, 'ContentType', 'vector');
            end
            savefig(fig, fig_file);
            fprintf('Saved binned plot for %s -> %s\n', type, plots_dir);
        catch E
            warnId = 'plot:exportFailed';
            if isfield(E,'identifier') && ~isempty(E.identifier), warnId = E.identifier; end
            warning(warnId, '%s. Falling back to print/saveas.', E.message);
            try
                if savePDF
                    print(fig, pdf_file, '-dpdf');
                end
                saveas(fig, fig_file);
            catch E2
                warnId2 = 'plot:saveFailed';
                if isfield(E2,'identifier') && ~isempty(E2.identifier), warnId2 = E2.identifier; end
                warning(warnId2, 'Failed to save plot: %s', E2.message);
            end
        end
    
        % Close figure only if requested
        if closeFigs
            close(fig);
        end
    end

    % Finalize stats struct and return
    stats.combined_by_type = combined_by_type;
    stats.folder_raw = folder_raw_all;
    stats.folder_binned = folder_binned_all;
    stats.binEdges = binEdges;
    stats.binCenters = binCenters;
    stats.permode_dir = permode_dir;
    stats.binned_dir = binned_dir;
    stats.plots_dir = plots_dir;
    stats.summary_csv = summary_csv;

    fprintf('Extended combined stats complete. Outputs under: %s\n', out_root);
end
