function process_folder(dataFolder, bead_numbers, positions, colors)
    if ~isfolder(dataFolder)
        error('Data folder does not exist: %s', dataFolder);
    end
    [~, folderBase] = fileparts(dataFolder);
    saveAggregatedName = fullfile(dataFolder, sprintf('all_filtered_aberrations_%s.mat', folderBase));
    all_results = struct();
    

    % --- Auto-detect positions and beads from filenames ---
    files_all = dir(fullfile(dataFolder, '*.mat'));
    posCells = cell(size(files_all));
    beadCells = cell(size(files_all));
    for fi = 1:numel(files_all)
        mpos = regexp(files_all(fi).name, 'pos\d+', 'match', 'once');
        mbead = regexp(files_all(fi).name, 'Bead(\d+)', 'tokens', 'once');
        if ~isempty(mpos)
            posCells{fi} = mpos;
        end
        if ~isempty(mbead)
            beadCells{fi} = mbead{1}; % always string, not cell
        end
    end
    detected_positions = unique(posCells(~cellfun('isempty', posCells)));
    beads_flat = beadCells(~cellfun('isempty', beadCells));
    detected_beads = unique(cellfun(@(x) str2double(x), beads_flat));
    if isempty(detected_positions)
        use_positions = positions;
    else
        use_positions = detected_positions;
    end
    if isempty(detected_beads)
        use_beads = bead_numbers;
    else
        use_beads = detected_beads(:)'; % row vector, always numeric scalars
    end

    summary_rows = {}; % filename, position, color, bead, n_coma, n_astig, n_sph, notes
    for p = 1:numel(use_positions)
        position = use_positions{p};
        for b = 1:numel(use_beads)
            bead = use_beads(b); % Ensure scalar
            for c = 1:numel(colors)
                color = colors{c};
                sample_tag = sprintf('%s_%s_Bead%d', position, color, bead);
                try
                    [aberration_table, usedFile] = wrapper_table(position, color, bead, dataFolder);
                catch ME
                    % --- No warning for missing files: only capture in summary ---
                    if ischar(ME.message)
                        note_str = ['missing: ' ME.message];
                    elseif isstring(ME.message)
                        note_str = ['missing: ' char(ME.message)];
                    elseif iscell(ME.message) && numel(ME.message)==1
                        note_str = ['missing: ' char(ME.message{1})];
                    else
                        note_str = 'missing: [non-scalar error message]';
                    end
                    summary_rows(end+1,:) = { '', position, color, bead, 0, 0, 0, note_str };
                    continue;
                end
                filtered_results = struct();
                try
                    filtered_results.coma = filter_coma_aberrations(aberration_table);
                catch
                    filtered_results.coma = table([],[],[],'VariableNames',{'NollIndex','ModeName','Magnitude'});
                end
                try
                    filtered_results.astigmatism = filter_astigmatism_aberrations(aberration_table);
                catch
                    filtered_results.astigmatism = table([],[],[],'VariableNames',{'NollIndex','ModeName','Magnitude'});
                end
                try
                    filtered_results.spherical = filter_spherical_aberrations(aberration_table);
                catch
                    filtered_results.spherical = table([],[],[],'VariableNames',{'NollIndex','ModeName','Magnitude'});
                end
                fprintf('\nProcessing %s (folder %s):\n', sample_tag, folderBase);
                disp('Source file:'); disp(usedFile);
                disp('Coma Aberrations:'); disp(filtered_results.coma);
                disp('Astigmatism Aberrations:'); disp(filtered_results.astigmatism);
                disp('Spherical Aberrations:'); disp(filtered_results.spherical);
                [~, usedBase] = fileparts(usedFile);
                safe_base = matlab.lang.makeValidName(sprintf('filtered_%s_%s', usedBase, sample_tag));
                outfn = fullfile(dataFolder, [safe_base '.mat']);
                try
                    save(outfn, 'filtered_results', '-v7.3');
                    fprintf('Saved %s\n', outfn);
                catch ME2
                    warning(ME2.identifier, 'Failed to save %s: %s', outfn, char(ME2.message));
                end
                all_results.(matlab.lang.makeValidName(sample_tag)) = filtered_results;
                n_coma = 0; n_astig = 0; n_sph = 0;
                if istable(filtered_results.coma), n_coma = height(filtered_results.coma); end
                if istable(filtered_results.astigmatism), n_astig = height(filtered_results.astigmatism); end
                if istable(filtered_results.spherical), n_sph = height(filtered_results.spherical); end
                summary_rows(end+1,:) = { usedBase, position, color, bead, n_coma, n_astig, n_sph, 'ok' };
            end
        end
    end
    try
        save(saveAggregatedName, 'all_results', '-v7.3');
        fprintf('Saved aggregated results to %s\n', saveAggregatedName);
    catch ME
        warning(ME.identifier, 'Failed to save aggregated results: %s', char(ME.message));
    end
    try
        timestamp = datestr(now,'yyyymmdd_HHMMSS');
        summaryCsvName = fullfile(dataFolder, sprintf('annotation_summary_%s_%s.csv', folderBase, timestamp));
        T = cell2table(summary_rows, 'VariableNames', {'filename','position','color','bead','n_coma','n_astig','n_sph','notes'});
        writetable(T, summaryCsvName);
        fprintf('Wrote annotation summary to %s\n', summaryCsvName);
    catch ME
        warning(ME.identifier, 'Failed to write summary CSV for %s: %s', dataFolder, char(ME.message));
    end
end
