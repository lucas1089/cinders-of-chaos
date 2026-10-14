-- Name Shader Selection Module
-- Allows players to view, preview, and select name shaders
-- Data is received from onOpenOutfitWindow callback

local CODE = 96  -- ExtendedOPCodes.CODE_NAMESHADERS
local nameShaderWindow = nil
local nameShadersData = {}
local currentNameShaderId = 0
local previewShaderId = nil

local function normalizeTupleList(list)
    if type(list) ~= "table" then
        return {}
    end

    local indexedEntries = {}
    for key, value in pairs(list) do
        if type(key) == "number" and type(value) == "table" then
            table.insert(indexedEntries, { key = key, value = value })
        end
    end

    table.sort(indexedEntries, function(a, b)
        return a.key < b.key
    end)

    local normalized = {}
    for _, entry in ipairs(indexedEntries) do
        table.insert(normalized, entry.value)
    end

    if #normalized == 0 then
        for _, value in pairs(list) do
            if type(value) == "table" then
                table.insert(normalized, value)
            end
        end
    end

    return normalized
end

function init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onOpenOutfitWindow = onOpenOutfitWindow
    })

    if g_game.isOnline() then
        onGameStart()
    end

    ProtocolGame.registerExtendedOpcode(CODE, onExtendedOpcode)
end

function terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onOpenOutfitWindow = onOpenOutfitWindow
    })

    if g_game.isOnline() then
        onGameEnd()
    end

    ProtocolGame.unregisterExtendedOpcode(CODE, onExtendedOpcode)
end

function onGameStart()
    -- Window is created on demand when data arrives
end

function onGameEnd()
    destroyWindow()
    nameShadersData = {}
    currentNameShaderId = 0
    previewShaderId = nil
end

function createWindow()
    if nameShaderWindow then return end
    nameShaderWindow = g_ui.displayUI('nameshaders')
    nameShaderWindow:hide()

    -- Setup search field
    nameShaderWindow.searchField.onTextChange = function(widget, text)
        refreshShaderList(text)
    end
end

function destroyWindow()
    if nameShaderWindow then
        nameShaderWindow:destroy()
        nameShaderWindow = nil
    end
end

function toggle()
    if not nameShaderWindow then
        createWindow()
    end
    if not nameShaderWindow then return end

    if nameShaderWindow:isVisible() then
        hide()
    else
        show()
    end
end

function show()
    if not nameShaderWindow then
        createWindow()
    end
    if not nameShaderWindow then return end

    -- Reset preview
    previewShaderId = nil
    updatePreview()

    refreshShaderList("")
    nameShaderWindow:show()
    nameShaderWindow:raise()
    nameShaderWindow:focus()
end

function hide()
    if nameShaderWindow then
        nameShaderWindow:hide()
    end
    -- Reset preview when hiding
    previewShaderId = nil
    updatePreview()
end

-- Called from outfit window callback with name shader data
function onOpenOutfitWindow(currentOutfit, outfitList, mountList, wingList, auraList, shaderList, nameShaderList, currentNameShaderIdVal, currentNameShaderPreviewEnabled, currentNameShaderConsoleEnabled, healthBarList, manaBarList)
    nameShaderList = normalizeTupleList(nameShaderList)
    if not nameShaderList or #nameShaderList == 0 then
        return
    end

    -- Store the name shader data
    -- Format: { {id, name, descriptionId}, ... }
    nameShadersData = {}
    for _, shader in ipairs(nameShaderList) do
        local id = shader[1]
        local name = shader[2]
        local descriptionId = shader[3] or 0

        -- Parse name for availability (name:1 = available, name:0 = locked)
        local displayName = name:split(":")[1]
        local availableStr = name:split(":")[2]
        local available = availableStr and availableStr == "1" or false

        table.insert(nameShadersData, {
            id = id,
            name = displayName,
            available = available,
            descriptionId = descriptionId
        })
    end

    currentNameShaderId = currentNameShaderIdVal or 0
end

function onExtendedOpcode(protocol, opcode, buffer)
    local status, data = pcall(function()
        return json.decode(buffer)
    end)

    if not status or not data then
        g_logger.error("[NameShaders] Failed to parse server response: " .. tostring(buffer and buffer:sub(1, 100) or "nil"))
        return
    end

    if data.action == "open" then
        show()
    elseif data.action == "update" then
        -- Server sent updated name shader list
        if data.shaders then
            nameShadersData = {}
            for _, shader in ipairs(data.shaders) do
                table.insert(nameShadersData, {
                    id = shader.id,
                    name = shader.name,
                    available = shader.available or false,
                    descriptionId = shader.descriptionId or 0
                })
            end
        end
        if data.current then
            currentNameShaderId = data.current
        end
        if nameShaderWindow and nameShaderWindow:isVisible() then
            refreshShaderList("")
        end
    elseif data.action == "selected" then
        -- Server confirmed selection
        if data.id then
            currentNameShaderId = data.id
        end
        if nameShaderWindow and nameShaderWindow:isVisible() then
            refreshShaderList(nameShaderWindow.searchField:getText() or "")
        end
        if data.name then
            modules.game_textmessage.displayBroadcastMessage(tr('Name shader equipped: %s', data.name))
        end
    elseif data.action == "unlocked" then
        -- Name shader was unlocked
        if data.name then
            modules.game_textmessage.displayBroadcastMessage(tr('Name shader unlocked: %s', data.name))
        end
        -- Update availability
        if data.id then
            for _, shader in ipairs(nameShadersData) do
                if shader.id == data.id then
                    shader.available = true
                    break
                end
            end
        end
        if nameShaderWindow and nameShaderWindow:isVisible() then
            refreshShaderList(nameShaderWindow.searchField:getText() or "")
        end
    end
end

function selectNameShader(shaderId)
    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
        local msg = {action = "select", id = shaderId}
        protocolGame:sendExtendedOpcode(CODE, json.encode(msg))
    end
end

function removeNameShader()
    selectNameShader(0)
end

function previewShader(shaderId)
    previewShaderId = shaderId
    updatePreview()
end

function updatePreview()
    if not nameShaderWindow then return end

    local previewCreature = nameShaderWindow.previewCreature
    if not previewCreature then return end

    local player = g_game.getLocalPlayer()
    if not player then return end

    -- Set the creature outfit to match player
    previewCreature:setOutfit(player:getOutfit())
    previewCreature:setDirection(Enums.South)

    -- Update preview name label with shader effect
    local previewLabel = nameShaderWindow.previewNameLabel
    if previewLabel then
        previewLabel:setText(player:getName())

        -- Get shader to preview
        local shaderName = ""
        local shaderId = previewShaderId or currentNameShaderId

        if shaderId and shaderId > 0 then
            for _, shader in ipairs(nameShadersData) do
                if shader.id == shaderId then
                    shaderName = shader.name
                    break
                end
            end
        end

        -- Note: Actual shader application would require C++ side label shader support
        -- For now, we indicate the shader name
        if shaderName ~= "" and shaderName ~= "-" then
            nameShaderWindow.previewShaderLabel:setText(tr('Shader: %s', shaderName))
        else
            nameShaderWindow.previewShaderLabel:setText(tr("Shader: None"))
        end
    end
end

function refreshShaderList(searchText)
    if not nameShaderWindow then return end

    nameShaderWindow.shaderList:destroyChildren()

    local searchLower = searchText and searchText:lower() or ""

    -- Update current shader label
    local currentShaderName = "None"
    for _, shader in ipairs(nameShadersData) do
        if shader.id == currentNameShaderId then
            currentShaderName = shader.name
            break
        end
    end
    nameShaderWindow.currentShaderLabel:setText(tr('Current: %s', currentShaderName))

    -- Filter and sort shaders
    local sorted = {}
    for _, shader in ipairs(nameShadersData) do
        local matchesSearch = searchLower == "" or shader.name:lower():find(searchLower, 1, true)

        if matchesSearch then
            table.insert(sorted, shader)
        end
    end

    -- Sort: available first, then by id
    table.sort(sorted, function(a, b)
        if a.available ~= b.available then
            return a.available
        end
        return a.id < b.id
    end)

    -- Count available
    local availableCount = 0
    local totalCount = #nameShadersData
    for _, shader in ipairs(nameShadersData) do
        if shader.available then
            availableCount = availableCount + 1
        end
    end
    nameShaderWindow.statusLabel:setText(tr('Unlocked: %s/%s', availableCount, totalCount))

    -- Create shader widgets
    for _, shader in ipairs(sorted) do
        local widget = g_ui.createWidget('NameShaderItem', nameShaderWindow.shaderList)

        widget.shaderName:setText(shader.name)

        -- Get description from OutfitObtains if available
        local description = ""
        if shader.descriptionId and shader.descriptionId > 0 and OutfitObtains then
            description = OutfitObtains[shader.descriptionId] or ""
        end
        widget.description:setText(description)

        if shader.available then
            widget.lockIcon:setVisible(false)
            widget:setEnabled(true)

            -- Show selected mark for current shader
            if shader.id == currentNameShaderId then
                widget.selectedMark:setVisible(true)
                widget:setBackgroundColor('#2d4a2d')
            end

            -- Preview on hover
            widget.onHoverChange = function(self, hovered)
                if hovered then
                    previewShader(shader.id)
                else
                    -- Reset to current when not hovering
                    previewShader(nil)
                end
            end

            widget.onClick = function()
                selectNameShader(shader.id)
            end
        else
            widget.lockIcon:setVisible(true)
            widget:setEnabled(false)
            widget.shaderName:setMarginLeft(32)

            widget.onClick = function()
                if description ~= "" then
                    modules.game_textmessage.displayBroadcastMessage("Locked: " .. description)
                else
                    modules.game_textmessage.displayBroadcastMessage(tr("This name shader is locked."))
                end
            end
        end
    end
end

-- Public API for other modules
function getData()
    return nameShadersData
end

function getCurrentId()
    return currentNameShaderId
end

function isAvailable(shaderId)
    for _, shader in ipairs(nameShadersData) do
        if shader.id == shaderId then
            return shader.available
        end
    end
    return false
end
