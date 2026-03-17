function filtered_table = filter_spherical_aberrations(input_table)
    % FILTER_SPHERICAL_ABERRATIONS Selects top 50% extreme spherical modes by magnitude
    spherical_terms = {
        'primary spherical aberration', 
        'secondary spherical', 
        'tertiary spherical'};
    is_spherical = ismember(input_table.ModeName, spherical_terms);
    row_magnitudes = abs(input_table.Magnitude(is_spherical));
    if isempty(row_magnitudes)
        filtered_table = input_table([],:);
        return;
    end
    sorted = sort(row_magnitudes, 'descend');
    dynamic_thr = sorted(ceil(numel(sorted)/2));
    threshold_range = abs(input_table.Magnitude) >= dynamic_thr;
    filtered_table = input_table(is_spherical & threshold_range, :);
end
