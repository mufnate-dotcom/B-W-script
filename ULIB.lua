local run_service = game:GetService("RunService")
local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local camera = workspace.CurrentCamera

local settings = {
    chests = {
        enabled = true,
        distance = 500,
        dist = true,
    },
    campfires = {
        enabled = true,
        distance = 500,
        dist = true,
    },
    npcs = {
        enabled = true,
        distance = 500,
        name = true,
        dist = true,
        box = true,
    },
    entities = {
        enabled = true,
        distance = 500,
        name = true,
        dist = true,
        box = true,
        healthbar = true,
    },
    players = {
        enabled = true,
        distance = 500,
        name = true,
        dist = true,
        box = true,
        healthbar = true,
    },
}

local player_half = Vector3.new(1.9, 2.9, 1.9)

local function distance_3d(a, b)
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local esp_table = {}
local cached_objects = {}

local chests_folder = workspace.Chests
local npc_folder = workspace.NPC
local campfire_folder = workspace.Campfire
local entities_folder = workspace.Entities

local update_interval = 0.2
local last_update = 0

local function create_esp(part, obj_type)
    if not esp_table[part.Address] then
        esp_table[part.Address] = {}
    end
    local entry = esp_table[part.Address]

    if not entry.text then
        local text = Drawing.new("Text")
        text.Center = true
        text.Size = 13
        text.Outline = true
        text.Visible = false
        entry.text = text
    end

    if (obj_type == "player" or obj_type == "npc" or obj_type == "entity") and not entry.lines then
        entry.lines = {}
        for i = 1, 8 do
            local line = Drawing.new("Line")
            line.Thickness = 1
            line.Color = Color3.fromRGB(255, 255, 255)
            line.Visible = false
            entry.lines[i] = line
        end
    end

    if (obj_type == "player" or obj_type == "entity") and not entry.bar_bg then
        local bar_bg = Drawing.new("Line")
        bar_bg.Thickness = 2
        bar_bg.Color = Color3.fromRGB(50, 50, 50)
        bar_bg.Visible = false
        entry.bar_bg = bar_bg

        local bar_fg = Drawing.new("Line")
        bar_fg.Thickness = 2
        bar_fg.Color = Color3.fromRGB(0, 255, 0)
        bar_fg.Visible = false
        entry.bar_fg = bar_fg
    end
end

local function get_hrp()
    local lp = players.LocalPlayer
    if not lp then return end
    local character = lp.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    return hrp
end

local function get_2d_bounds(hrp_cf)
    local h = player_half
    local offsets = {
        Vector3.new(-h.X, -h.Y, -h.Z),
        Vector3.new(h.X, -h.Y, -h.Z),
        Vector3.new(h.X, -h.Y, h.Z),
        Vector3.new(-h.X, -h.Y, h.Z),
        Vector3.new(-h.X, h.Y, -h.Z),
        Vector3.new(h.X, h.Y, -h.Z),
        Vector3.new(h.X, h.Y, h.Z),
        Vector3.new(-h.X, h.Y, h.Z),
    }
    local min_x, min_y, max_x, max_y = math.huge, math.huge, -math.huge, -math.huge
    for _, offset in ipairs(offsets) do
        local sp, on = WorldToScreen(hrp_cf * offset)
        if not on then return nil end
        if sp.X < min_x then min_x = sp.X end
        if sp.Y < min_y then min_y = sp.Y end
        if sp.X > max_x then max_x = sp.X end
        if sp.Y > max_y then max_y = sp.Y end
    end
    return min_x, min_y, max_x, max_y
end

local function render_corner_box(lines, min_x, min_y, max_x, max_y)
    local w = max_x - min_x
    local h = max_y - min_y
    local cx = math.min(w, h) * 0.25

    lines[1].From = Vector2.new(min_x, min_y)
    lines[1].To = Vector2.new(min_x + cx, min_y)
    lines[2].From = Vector2.new(min_x, min_y)
    lines[2].To = Vector2.new(min_x, min_y + cx)

    lines[3].From = Vector2.new(max_x, min_y)
    lines[3].To = Vector2.new(max_x - cx, min_y)
    lines[4].From = Vector2.new(max_x, min_y)
    lines[4].To = Vector2.new(max_x, min_y + cx)

    lines[5].From = Vector2.new(min_x, max_y)
    lines[5].To = Vector2.new(min_x + cx, max_y)
    lines[6].From = Vector2.new(min_x, max_y)
    lines[6].To = Vector2.new(min_x, max_y - cx)

    lines[7].From = Vector2.new(max_x, max_y)
    lines[7].To = Vector2.new(max_x - cx, max_y)
    lines[8].From = Vector2.new(max_x, max_y)
    lines[8].To = Vector2.new(max_x, max_y - cx)

    for i = 1, 8 do lines[i].Visible = true end
end

local function render_health_bar(entry, cfg, min_x, min_y, max_x, max_y, health, max_health)
    if not cfg.healthbar or not min_x then
        entry.bar_bg.Visible = false
        entry.bar_fg.Visible = false
        return
    end

    local offset = 5
    local bar_x = min_x - offset
    local ratio = math.clamp(health / max_health, 0, 1)
    local filled_y = max_y - (max_y - min_y) * ratio

    local r = math.floor(255 * (1 - ratio))
    local g = math.floor(255 * ratio)

    entry.bar_bg.From = Vector2.new(bar_x, min_y)
    entry.bar_bg.To = Vector2.new(bar_x, max_y)
    entry.bar_bg.Visible = true

    entry.bar_fg.From = Vector2.new(bar_x, filled_y)
    entry.bar_fg.To = Vector2.new(bar_x, max_y)
    entry.bar_fg.Color = Color3.fromRGB(r, g, 0)
    entry.bar_fg.Visible = true
end

local function refresh_cache()
    table.clear(cached_objects)

    local hrp = get_hrp()
    if not hrp then return end

    if settings.chests.enabled then
        for _, chest in ipairs(chests_folder:GetChildren()) do
            local main = chest:FindFirstChild("Main")
            if not main or not main.Position then continue end
            local dist = distance_3d(hrp.Position, main.Position)
            if dist > settings.chests.distance then continue end
            cached_objects[#cached_objects + 1] = {
                type = "chest",
                part = main,
                dist = dist,
            }
        end
    end

    if settings.campfires.enabled then
        for _, campfire in ipairs(campfire_folder:GetChildren()) do
            local primary = campfire:FindFirstChild("PrimaryPart")
            if not primary or not primary.Position then continue end
            local dist = distance_3d(hrp.Position, primary.Position)
            if dist > settings.campfires.distance then continue end
            cached_objects[#cached_objects + 1] = {
                type = "campfire",
                part = primary,
                dist = dist,
            }
        end
    end

    if settings.npcs.enabled then
        for _, npc in ipairs(npc_folder:GetChildren()) do
            local npc_hrp = npc:FindFirstChild("HumanoidRootPart")
            if not npc_hrp then continue end
            local dist = distance_3d(hrp.Position, npc_hrp.Position)
            if dist > settings.npcs.distance then continue end
            cached_objects[#cached_objects + 1] = {
                type = "npc",
                part = npc_hrp,
                name = npc.Name ~= " " and npc.Name or "Barber",
                dist = dist,
            }
        end
    end

    if settings.entities.enabled then
        for _, entity in ipairs(entities_folder:GetChildren()) do
            if entity:GetAttribute("LastInteractionTime") == nil then continue end
            local entity_hrp = entity:FindFirstChild("HumanoidRootPart")
            if not entity_hrp then continue end
            local dist = distance_3d(hrp.Position, entity_hrp.Position)
            if dist > settings.entities.distance then continue end
            local humanoid = entity:FindFirstChildWhichIsA("Humanoid")
            cached_objects[#cached_objects + 1] = {
                type = "entity",
                part = entity_hrp,
                name = entity.Name,
                dist = dist,
                health = humanoid and humanoid.Health or 100,
                max_health = humanoid and humanoid.MaxHealth or 100,
            }
        end
    end

    if settings.players.enabled then
        local lp = players.LocalPlayer
        for _, plr in ipairs(players:GetPlayers()) do
            if not lp or plr.Name == lp.Name then continue end
            local char = plr.Character
            if not char then continue end
            local plr_hrp = char:FindFirstChild("HumanoidRootPart")
            if not plr_hrp then continue end
            local dist = distance_3d(hrp.Position, plr_hrp.Position)
            if dist > settings.players.distance then continue end
            local humanoid = char:FindFirstChildWhichIsA("Humanoid")
            cached_objects[#cached_objects + 1] = {
                type = "player",
                part = plr_hrp,
                name = plr.Name,
                dist = dist,
                health = humanoid and humanoid.Health or 100,
                max_health = humanoid and humanoid.MaxHealth or 100,
            }
        end
    end
end

local function build_char_label(cfg, name, dist)
    local label = ""
    if cfg.name then label = name end
    if cfg.dist then
        local dist_tag = "[" .. math.floor(dist) .. "m]"
        label = label == "" and dist_tag or label .. " " .. dist_tag
    end
    if label == "" then return nil end
    return label
end

local function render_char(entry, cfg, part, name, dist, color, health, max_health)
    local min_x, min_y, max_x, max_y = get_2d_bounds(part.CFrame)
    local lines = entry.lines

    if cfg.box and min_x then
        render_corner_box(lines, min_x, min_y, max_x, max_y)
    else
        for i = 1, 8 do lines[i].Visible = false end
    end

    if entry.bar_bg then
        render_health_bar(entry, cfg, min_x, min_y, max_x, max_y, health, max_health)
    end

    local text = entry.text
    local label = build_char_label(cfg, name, dist)
    if label then
        if min_x then
            text.Position = Vector2.new((min_x + max_x) / 2, min_y - 8)
            text.Text = label
            text.Color = color
            text.Visible = true
        else
            local sp, on = WorldToScreen(part.Position + Vector3.new(0, 2.5, 0))
            if on then
                text.Position = Vector2.new(sp.X, sp.Y)
                text.Text = label
                text.Color = color
                text.Visible = true
            else
                text.Visible = false
            end
        end
    else
        text.Visible = false
    end
end

local function render_esp()
    for _, obj in ipairs(cached_objects) do
        local part = obj.part
        if not part or not part.Position then continue end

        create_esp(part, obj.type)
        local entry = esp_table[part.Address]

        if obj.type == "chest" then
            local screen_pos, on_screen = WorldToScreen(part.Position)
            local label = "Chest"
            if settings.chests.dist then
                label = label .. " [" .. math.floor(obj.dist) .. "m]"
            end
            entry.text.Text = label
            entry.text.Color = Color3.fromRGB(255, 215, 0)
            entry.text.Position = Vector2.new(screen_pos.X, screen_pos.Y)
            entry.text.Visible = on_screen

        elseif obj.type == "campfire" then
            local screen_pos, on_screen = WorldToScreen(part.Position)
            local label = "Campfire"
            if settings.campfires.dist then
                label = label .. " [" .. math.floor(obj.dist) .. "m]"
            end
            entry.text.Text = label
            entry.text.Color = Color3.fromRGB(255, 100, 0)
            entry.text.Position = Vector2.new(screen_pos.X, screen_pos.Y)
            entry.text.Visible = on_screen

        elseif obj.type == "npc" then
            render_char(entry, settings.npcs, part, obj.name, obj.dist, Color3.fromRGB(128, 0, 128))

        elseif obj.type == "entity" then
            render_char(entry, settings.entities, part, obj.name, obj.dist, Color3.fromRGB(255, 50, 50), obj.health, obj.max_health)

        elseif obj.type == "player" then
            render_char(entry, settings.players, part, obj.name, obj.dist, Color3.fromRGB(255, 255, 255), obj.health, obj.max_health)
        end
    end
end

local function remove_esp()
    local active_addresses = {}
    for _, obj in ipairs(cached_objects) do
        active_addresses[obj.part.Address] = true
    end
    for address, data in pairs(esp_table) do
        if not active_addresses[address] then
            if data.text then data.text:Remove() end
            if data.lines then
                for _, line in ipairs(data.lines) do line:Remove() end
            end
            if data.bar_bg then data.bar_bg:Remove() end
            if data.bar_fg then data.bar_fg:Remove() end
            esp_table[address] = nil
        end
    end
end

run_service.RenderStepped:Connect(function(dt)
    last_update = last_update + dt
    if last_update >= update_interval then
        last_update = 0
        refresh_cache()
        remove_esp()
    end
    render_esp()
end)

local resolvers = {
    cframe = function(target)
        return target
    end,
    instance = function(target)
        if target:IsA("BasePart") then
            return target.CFrame
        end
    end,
}

local math_util = {
    distance = function(a, b)
        local diff = a.Position - b.Position
        return math.sqrt(diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z)
    end,
    easing = {
        linear = function(alpha)
            return alpha
        end,
        smoothstep = function(alpha)
            return alpha * alpha * (3 - 2 * alpha)
        end,
        ease_in_quad = function(alpha)
            return alpha * alpha
        end,
        ease_out_quad = function(alpha)
            return alpha * (2 - alpha)
        end,
        ease_in_out_quad = function(alpha)
            if alpha < 0.5 then
                return 2 * alpha * alpha
            else
                return -1 + (4 - 2 * alpha) * alpha
            end
        end,
    }
}

local function tween_to(local_player, target, speed, easing_style)
    local result = {completed = false}
    if not (local_player and target and speed > 0) then
        result.completed = true
        return result
    end
    local char = local_player.Character
    if not char then
        result.completed = true
        return result
    end
    local hrp = char:WaitForChild("HumanoidRootPart")
    local resolve = resolvers[typeof(target):lower()]
    local target_cf = resolve and resolve(target)
    if not target_cf then
        result.completed = true
        return result
    end
    local start_cf = hrp.CFrame
    local distance = math_util.distance(start_cf, target_cf)
    local duration = distance / speed
    if duration <= 0 then
        result.completed = true
        return result
    end
    local easing_func = math_util.easing[easing_style] or math_util.easing.linear
    local elapsed = 0
    local connection
    connection = run_service.Heartbeat:Connect(function(dt)
        elapsed = elapsed + dt
        local alpha = math.clamp(elapsed / duration, 0, 1)
        local eased_alpha = easing_func(alpha)
        hrp.CFrame = start_cf:Lerp(target_cf, eased_alpha)
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        if alpha >= 1 then
            hrp.CFrame = target_cf
            hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            result.completed = true
            connection:Disconnect()
        end
    end)
    return result
end

local function sort_chests_by_distance(hrp)
    local valid = {}
    for _, chest in ipairs(workspace.Chests:GetChildren()) do
        local main = chest:FindFirstChild("Main")
        if main then
            valid[#valid + 1] = {
                chest = chest,
                main = main,
                dist = math_util.distance(hrp.CFrame, main.CFrame),
            }
        end
    end
    table.sort(valid, function(a, b)
        return a.dist < b.dist
    end)
    return valid
end

local loot_loop = nil

local function start_loot()
    if loot_loop then return end
    local lp = players.LocalPlayer
    local char = lp.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local sorted = sort_chests_by_distance(hrp)
    local chest_index = 1
    local phase = 1
    local current_tween = nil
    local interact_timer = nil

    loot_loop = run_service.Heartbeat:Connect(function(dt)
        char = lp.Character
        if not char then return end
        hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        if chest_index > #sorted then
            sorted = sort_chests_by_distance(hrp)
            chest_index = 1
            phase = 1
            current_tween = nil
            interact_timer = nil
            return
        end

        if interact_timer then
            interact_timer = interact_timer - dt
            if interact_timer <= 0 then
                keyrelease(0x45)
                interact_timer = nil
                phase = 5
                current_tween = nil
            end
            return
        end

        if current_tween and not current_tween.completed then
            return
        end

        local entry = sorted[chest_index]
        local chest_cf = entry.main.CFrame

        if phase == 1 then
            current_tween = tween_to(lp, hrp.CFrame * CFrame.new(0, 350, 0), 45, "linear")
            phase = 2
        elseif phase == 2 then
            current_tween = tween_to(lp, chest_cf * CFrame.new(0, 350, 0), 45, "linear")
            phase = 3
        elseif phase == 3 then
            current_tween = tween_to(lp, chest_cf * CFrame.new(0, 3, 0), 45, "linear")
            phase = 4
        elseif phase == 4 then
            local look_cf = camera.lookAt(camera.Position, chest_cf.Position)
            keypress(0x45)
            interact_timer = 2
        elseif phase == 5 then
            current_tween = tween_to(lp, hrp.CFrame * CFrame.new(0, 350, 0), 45, "linear")
            phase = 6
        elseif phase == 6 then
            chest_index = chest_index + 1
            phase = 1
            current_tween = nil
        end
    end)
end

local function stop_loot()
    if loot_loop then
        loot_loop:Disconnect()
        loot_loop = nil
    end
end

UI.AddTab("Bridger Western", function(tab)
    local plr_sec = tab:Section("Players", "Left")
    plr_sec:Toggle("plr_enabled", "Enabled", settings.players.enabled, function(v) settings.players.enabled = v end)
    plr_sec:Toggle("plr_name", "Name", settings.players.name, function(v) settings.players.name = v end)
    plr_sec:Toggle("plr_dist", "Distance", settings.players.dist, function(v) settings.players.dist = v end)
    plr_sec:Toggle("plr_box", "Box", settings.players.box, function(v) settings.players.box = v end)
    plr_sec:Toggle("plr_hp", "Health Bar", settings.players.healthbar, function(v) settings.players.healthbar = v end)
    plr_sec:SliderInt("plr_distance", "Max Distance", 50, 2500, settings.players.distance, function(v) settings.players.distance = v end)

    local ent_sec = tab:Section("Entities", "Left")
    ent_sec:Toggle("ent_enabled", "Enabled", settings.entities.enabled, function(v) settings.entities.enabled = v end)
    ent_sec:Toggle("ent_name", "Name", settings.entities.name, function(v) settings.entities.name = v end)
    ent_sec:Toggle("ent_dist", "Distance", settings.entities.dist, function(v) settings.entities.dist = v end)
    ent_sec:Toggle("ent_box", "Box", settings.entities.box, function(v) settings.entities.box = v end)
    ent_sec:Toggle("ent_hp", "Health Bar", settings.entities.healthbar, function(v) settings.entities.healthbar = v end)
    ent_sec:SliderInt("ent_distance", "Max Distance", 50, 2500, settings.entities.distance, function(v) settings.entities.distance = v end)

    local npc_sec = tab:Section("NPCs", "Left")
    npc_sec:Toggle("npc_enabled", "Enabled", settings.npcs.enabled, function(v) settings.npcs.enabled = v end)
    npc_sec:Toggle("npc_name", "Name", settings.npcs.name, function(v) settings.npcs.name = v end)
    npc_sec:Toggle("npc_dist", "Distance", settings.npcs.dist, function(v) settings.npcs.dist = v end)
    npc_sec:Toggle("npc_box", "Box", settings.npcs.box, function(v) settings.npcs.box = v end)
    npc_sec:SliderInt("npc_distance", "Max Distance", 50, 2500, settings.npcs.distance, function(v) settings.npcs.distance = v end)

    local chest_sec = tab:Section("Chests", "Right")
    chest_sec:Toggle("chest_enabled", "Enabled", settings.chests.enabled, function(v) settings.chests.enabled = v end)
    chest_sec:Toggle("chest_dist", "Show Distance", settings.chests.dist, function(v) settings.chests.dist = v end)
    chest_sec:SliderInt("chest_distance", "Max Distance", 50, 2500, settings.chests.distance, function(v) settings.chests.distance = v end)

    local camp_sec = tab:Section("Campfires", "Right")
    camp_sec:Toggle("camp_enabled", "Enabled", settings.campfires.enabled, function(v) settings.campfires.enabled = v end)
    camp_sec:Toggle("camp_dist", "Show Distance", settings.campfires.dist, function(v) settings.campfires.dist = v end)
    camp_sec:SliderInt("camp_distance", "Max Distance", 50, 2500, settings.campfires.distance, function(v) settings.campfires.distance = v end)

    local loot_sec = tab:Section("Chest Looting", "Right")
    loot_sec:Toggle("loot_enabled", "Enabled", false, function(v)
        if v then
            start_loot()
        else
            stop_loot()
        end
    end)
end)
