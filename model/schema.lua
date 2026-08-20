local schema = {};

schema.version = 1;
schema.situations = {
    'General Physical', 'Leveling', 'Skillchain', 'Magic Burst',
    'Boss Survival', 'Multiple Enemies', 'Status Heavy', 'Avoid AoE',
};
schema.player_sc_policies = { 'Either', 'Trust Opens', 'Trust Closes' };
schema.confidence = {
    verified = true,
    documented = true,
    observed = true,
    estimated = true,
    unknown = true,
};

function schema.normalize_name(name)
    return tostring(name or ''):lower():gsub('[^%w]', '');
end

function schema.contains(values, wanted)
    for _, value in ipairs(values or {}) do
        if (value == wanted) then return true; end
    end
    return false;
end

function schema.clamp_integer(value, minimum, maximum, fallback)
    value = tonumber(value);
    if (value == nil) then return fallback; end
    value = math.floor(value);
    return math.max(minimum, math.min(maximum, value));
end

function schema.validate_behavior(record)
    local errors = {};
    if (type(record) ~= 'table') then
        return false, { 'behavior record is not a table' };
    end
    if (record.confidence ~= nil and not schema.confidence[record.confidence]) then
        table.insert(errors, 'invalid confidence');
    end
    if (record.sc_reliability ~= nil and (tonumber(record.sc_reliability) == nil
        or record.sc_reliability < 0 or record.sc_reliability > 1)) then
        table.insert(errors, 'sc_reliability must be between 0 and 1');
    end
    return #errors == 0, errors;
end

return schema;
