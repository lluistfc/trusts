local graph = {};

graph.version = 1;
graph.property_order = {
    'Liquefaction', 'Induration', 'Detonation', 'Scission',
    'Impaction', 'Reverberation', 'Transfixion', 'Compression',
    'Fusion', 'Fragmentation', 'Distortion', 'Gravitation',
    'Light', 'Darkness',
};
graph.element_order = { 'Fire', 'Ice', 'Wind', 'Earth', 'Lightning', 'Water', 'Light', 'Dark' };
graph.level = {
    Liquefaction = 1, Induration = 1, Detonation = 1, Scission = 1,
    Impaction = 1, Reverberation = 1, Transfixion = 1, Compression = 1,
    Fusion = 2, Fragmentation = 2, Distortion = 2, Gravitation = 2,
    Light = 3, Darkness = 3,
};
graph.elements = {
    Liquefaction = { 'Fire' }, Induration = { 'Ice' }, Detonation = { 'Wind' },
    Scission = { 'Earth' }, Impaction = { 'Lightning' }, Reverberation = { 'Water' },
    Transfixion = { 'Light' }, Compression = { 'Dark' },
    Fusion = { 'Fire', 'Light' }, Fragmentation = { 'Wind', 'Lightning' },
    Distortion = { 'Ice', 'Water' }, Gravitation = { 'Earth', 'Dark' },
    Light = { 'Fire', 'Wind', 'Lightning', 'Light' },
    Darkness = { 'Ice', 'Earth', 'Water', 'Dark' },
};
graph.combinations = {
    Light = { Light = 'Light' }, Darkness = { Darkness = 'Darkness' },
    Fragmentation = { Fusion = 'Light', Distortion = 'Distortion' },
    Fusion = { Fragmentation = 'Light', Gravitation = 'Gravitation' },
    Distortion = { Gravitation = 'Darkness', Fusion = 'Fusion' },
    Gravitation = { Distortion = 'Darkness', Fragmentation = 'Fragmentation' },
    Liquefaction = { Impaction = 'Fusion', Scission = 'Scission' },
    Induration = { Reverberation = 'Fragmentation', Impaction = 'Impaction' },
    Detonation = { Compression = 'Gravitation', Scission = 'Scission' },
    Scission = { Liquefaction = 'Liquefaction', Reverberation = 'Reverberation', Detonation = 'Detonation' },
    Impaction = { Liquefaction = 'Liquefaction', Detonation = 'Detonation' },
    Reverberation = { Induration = 'Induration', Impaction = 'Impaction' },
    Transfixion = { Scission = 'Distortion', Reverberation = 'Reverberation' },
    Compression = { Transfixion = 'Transfixion', Induration = 'Compression', Detonation = 'Detonation' },
};

function graph.canonical(property)
    property = tostring(property or '');
    if (property:find('Light', 1, true) == 1) then return 'Light'; end
    if (property:find('Darkness', 1, true) == 1) then return 'Darkness'; end
    return property;
end

function graph.result(opening, closing)
    opening = graph.canonical(opening);
    closing = graph.canonical(closing);
    return graph.combinations[opening] and graph.combinations[opening][closing] or nil;
end

function graph.result_has_element(result, wanted)
    for _, element in ipairs(graph.elements[result] or {}) do
        if (element == wanted) then return true; end
    end
    return false;
end

return graph;
