function filtered_table = filter_astigmatism_aberrations(input_table)
    % FILTER_ASTIGMATISM_ABERRATIONS Selects top 50% extreme astigmatism modes by magnitude
    astigmatism_terms = {
        '45 degree primary astigmatism', 
        '0 degree primary astigmatism', 
        '0 degree secondary astigmatism', 
        '45 degree secondary astigmatism', 
        '45 degree tertiary astigmatism', 
        '0 degree tertiary astigmatism'};
    is_astig = ismember(input_table.ModeName, astigmatism_terms);
    row_magnitudes = abs(input_table.Magnitude(is_astig));
    if isempty(row_magnitudes)
        filtered_table = input_table([],:);
        return;
    end
    sorted = sort(row_magnitudes, 'descend');
    dynamic_thr = sorted(ceil(numel(sorted)/2));
    threshold_range = abs(input_table.Magnitude) >= dynamic_thr;
    filtered_table = input_table(is_astig & threshold_range, :);
end
