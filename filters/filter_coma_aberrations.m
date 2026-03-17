function filtered_table = filter_coma_aberrations(input_table)
    % FILTER_COMA_ABERRATIONS Selects top 50% extreme coma modes by magnitude
    coma_terms = {
        'primary x-coma', 
        'primary y-coma', 
        'secondary x-coma', 
        'secondary y-coma', 
        'tertiary x-coma', 
        'tertiary y-coma'};
    is_coma = ismember(input_table.ModeName, coma_terms);
    row_magnitudes = abs(input_table.Magnitude(is_coma));
    if isempty(row_magnitudes)
        filtered_table = input_table([],:);
        return;
    end
    sorted = sort(row_magnitudes, 'descend');
    dynamic_thr = sorted(ceil(numel(sorted)/2)); % halfway point
    threshold_range = abs(input_table.Magnitude) >= dynamic_thr;
    filtered_table = input_table(is_coma & threshold_range, :);
end
