-- Sistema de Notificações Moderno para TFS 1.3 / OTClient - VERSÃO CORRIGIDA
-- CORREÇÕES: Party invite notifications integradas ao sistema de catacomb + POPUPS CORRIGIDOS

local opcode = 79
local gameRootPanel = modules.game_interface.getRootPanel()
local gameRightPanels = gameRootPanel and gameRootPanel:getChildById('gameRightPanels') or nil

local notificationQueue = {}
local activeNotifications = {}
local pinnedNotifications = {}
local maxNotifications = 3
local maxPinnedNotifications = 2
local notificationDuration = 30000 -- 30 segundos para convites
local isInitialized = false

-- Tipos de notificação com configurações melhoradas + CATACOMB
local NOTIFICATION_TYPES = {
    GM_BROADCAST = {
        icon = "images/notifications/gm.png",
        title = "GAMEMASTER NOTIFICATION",
        titleColor = "#a3844b",
        backgroundColor = "#ccbebb",
        borderColor = "#6a5632",
        duration = 30000, -- 10 segundos
    },
    TASK_COMPLETE = {
        icon = "images/notifications/task.png",
        title = "TASK COMPLETED",
        titleColor = "#a3844b",
        backgroundColor = "#ccbebb",
        borderColor = "#6a5632",
        duration = 10000, -- 10 segundos
    },
    BATTLE_PASS = {
        icon = "images/notifications/battlepass.png",
        title = "BATTLE PASS REWARD",
        titleColor = "#a3844b",
        backgroundColor = "#ccbebb",
        borderColor = "#6a5632",
        duration = 10000, -- 10 segundos
    },
    PARTY_INVITE = {
        icon = "images/toast/party_invite.png",
        title = "PARTY INVITATION",
        titleColor = "#a3844b",
        backgroundColor = "#ccbebb",
        borderColor = "#6a5632",
        duration = 30000, -- 30 segundos
    },
    BOUNTY = {
        icon = "images/notifications/task.png",
        title = "BOUNTY BOARD",
        titleColor = "#a3844b",
        backgroundColor = "#ccbebb",
        borderColor = "#6a5632",
        duration = 8000,
    },
    NEW_PLAYER = {
        icon = "images/notifications/gm.png",
        title = "NEW ADVENTURER",
        titleColor = "#a3844b",
        backgroundColor = "#ccbebb",
        borderColor = "#6a5632",
        duration = 12000,
    },
    -- bestiary and kill tasks (server data/scripts/chaos/bestiary.lua): new stages, completed tasks
    BESTIARY = {
        icon = "images/notifications/task.png",
        title = "BESTIARY",
        titleColor = "#b08a4a",
        backgroundColor = "#ccbebb",
        borderColor = "#6a5632",
        duration = 7000,
    },
    -- achievements (server data/scripts/chaos/achievements.lua): one toast per unlock (name, points, title, reward), one
    -- summary for the unlocks of the login check; the reward track and class unlocks
    ACHIEVEMENT = {
        icon = "/images/chaos/topbutton_ranking",
        title = "ACHIEVEMENT UNLOCKED",
        titleColor = "#5cc8c0",
        backgroundColor = "#ccbebb",
        borderColor = "#2c6e69",
        duration = 8000,
    },
    -- ascension quest (server data/scripts/chaos/ascension_quest.lua): Proof, Trial and the ascension itself
    ASCENSION = {
        icon = "images/notifications/gm.png",
        title = "ASCENSION",
        titleColor = "#c9a24a",
        backgroundColor = "#ccbebb",
        borderColor = "#6a5632",
        duration = 10000,
    },
    -- invasions and world events (server data/scripts/chaos/invasion.lua, worldevents.lua): warnings, waves, the end
    -- the market (server data/scripts/chaos/market.lua): a sale, a purchase, items and gold delivered
    MARKET = {
        icon = "images/notifications/gm.png",
        title = "MARKET",
        titleColor = "#e8b84a",
        backgroundColor = "#ccbebb",
        borderColor = "#6a5632",
        duration = 9000,
    },
    -- a listing of the player sold (server market.lua, orbexchange.lua; kind "sale"): item, price, fee and proceeds, or
    -- "While you were away: 3 items sold for 4.2M gold: ..." at login
    SALE = {
        icon = "/images/chaos/topbutton_market",
        title = "ITEM SOLD",
        titleColor = "#e8b84a",
        backgroundColor = "#ccbebb",
        borderColor = "#6a5632",
        duration = 12000,
    },
    INVASION = {
        icon = "images/notifications/gm.png",
        title = "INVASION",
        titleColor = "#d8452a",
        backgroundColor = "#ccbebb",
        borderColor = "#7a1a12",
        duration = 9000,
    },
    -- season pass (server data/scripts/chaos/seasonpass.lua): tier up, challenge done, premium and packs
    SEASON_PASS = {
        icon = "images/notifications/battlepass.png",
        title = "SEASON PASS",
        titleColor = "#ff9a3c",
        backgroundColor = "#ccbebb",
        borderColor = "#7a3a12",
        duration = 9000,
    },
    -- Seasonal Journey (server data/scripts/chaos/season_journey.lua): an objective done, a chapter complete
    JOURNEY = {
        icon = "images/notifications/task.png",
        title = "SEASONAL JOURNEY",
        titleColor = "#ff9a3c",
        backgroundColor = "#ccbebb",
        borderColor = "#7a3a12",
        duration = 8000,
    },
    -- boss passive points (server data/scripts/chaos/bosspoints.lua): first kill of a major boss, +1 passive point
    BOSS_POINT = {
        icon = "images/notifications/task.png",
        title = "BOSS PASSIVE POINT",
        titleColor = "#d8a03a",
        backgroundColor = "#ccbebb",
        borderColor = "#7a5410",
        duration = 10000,
    },
    CATACOMB_FREE = {
        icon = "images/toast/catacomb_invite.png",
        title = "CATACOMB AVAILABLE",
        titleColor = "#a3844b",
        backgroundColor = "#ccbebb",
        borderColor = "#6a5632",
        duration = 30000, -- 30 segundos
    }
}


function fitGamePanel()
    if not gameRightPanels then return end
    -- Trigger repositioning so notifications move when right panels change
    repositionNotifications()
end

-- Função para verificar se widget é válido
local function isWidgetValid(widget)
    if not widget then return false end
    
    local success, result = pcall(function()
        return widget:getId() ~= nil
    end)
    
    return success and result
end

-- Função para detectar painéis laterais ativos
local function getActiveSidePanels()
    local panels = {}
    local gameRootPanel = modules.game_interface.getRootPanel()
    if not gameRootPanel then return panels end
    
    local parentSize = gameRootPanel:getSize()
    
    -- Lista de módulos que podem ter painéis laterais
    local sideModules = {
        'game_inventory',
        'game_skills', 
        'game_battle',
        'game_minimap',
        'game_outfit',
        'game_trade',
        'game_npctrade',
        'game_market',
        'game_questlog',
        'game_console',
        'game_textbooks',
        'game_ruleviolation'
    }
    
    local rightPanelCount = 0
    local rightmostX = parentSize.width
    
    for _, moduleName in ipairs(sideModules) do
        if modules[moduleName] then
            local modulePanel = nil
            
            -- Tentar diferentes formas de obter o painel do módulo
            if modules[moduleName].getPanel then
                modulePanel = modules[moduleName].getPanel()
            elseif modules[moduleName].window then
                modulePanel = modules[moduleName].window
            elseif modules[moduleName].panel then
                modulePanel = modules[moduleName].panel
            end
            
            if modulePanel and modulePanel:isVisible() then
                local pos = modulePanel:getPosition()
                local size = modulePanel:getSize()
                
                -- Se o painel está no lado direito da tela (mais de 60% da largura)
                if pos.x > parentSize.width * 0.6 then
                    rightPanelCount = rightPanelCount + 1
                    if pos.x < rightmostX then
                        rightmostX = pos.x
                    end
                    
                    table.insert(panels, {
                        x = pos.x,
                        y = pos.y,
                        width = size.width,
                        height = size.height,
                        module = moduleName
                    })
                end
            end
        end
    end
    
    return panels, rightPanelCount, rightmostX
end

-- Função para calcular posição ideal evitando sobreposição
local function calculateOptimalPosition()
    local gameRootPanel_local = modules.game_interface.getRootPanel()
    if not gameRootPanel_local then return {marginRight = 30, y = 35} end

    local parentSize = gameRootPanel_local:getSize()
    local notificationWidth = 340
    local notificationHeight = 100

    -- Primeiro tente a contagem simples de gameRightPanels (como tutorial)
    if gameRightPanels then
        local count = gameRightPanels:getChildCount()
        if count and count > 0 then
            local margin = (160 * count) + 40 * count + 30  -- margem base + 30 extra
            local baseY = 35
            return {marginRight = margin, y = baseY}
        end
    end

    -- Fallback: detectar painéis ativos à direita (módulos individuais)
    local activePanels, panelCount, rightmostX = getActiveSidePanels()
    if panelCount and panelCount > 0 and rightmostX then
        -- calcular marginRight para ancoragem à direita
        local marginRight = parentSize.width - rightmostX + 50
        if marginRight < 20 then marginRight = 20 end
        return {marginRight = marginRight, y = 35}
    end

    -- Nenhum painel ativo: margem padrão
    return {marginRight = 30, y = 35}
end

-- stack the shown toasts (notifyview.lua ChaosNotifyView.stack): pinned first, then by slot, each below the one above
-- by its own height, so toasts with buttons (140) and several toasts at once never overlap
function repositionNotifications()
    local basePos = calculateOptimalPosition()
    local margin = basePos.marginRight
    local groups = {pinned = {}, active = {}}
    local sources = {pinned = pinnedNotifications, active = activeNotifications}
    for name, list in pairs(sources) do
        for slot, data in pairs(list) do
            if data and data.widget and isWidgetValid(data.widget) then
                groups[name][slot] = {type = data.data and data.data.notificationType}
            end
        end
    end
    for _, place in ipairs(ChaosNotifyView.stack(groups.pinned, groups.active, basePos.y + 35)) do
        local data = sources[place.group][place.slot]
        pcall(function()
            data.widget:setMarginRight(margin)
            data.widget:setMarginTop(place.y)
            data.widget:raise()
        end)
    end
end

-- Função para processar fila de notificações
local function processNotificationQueue()
    if #notificationQueue == 0 then return end
    
    local slot = findFreeNotificationSlot()
    if not slot then return end
    
    local notificationData = table.remove(notificationQueue, 1)
    if notificationData then
        showNotification(notificationData, slot)
    end
end

-- Função para animar saída da notificação
local function animateNotificationOut(notificationData, slot, isPinned)
    if not notificationData or not notificationData.widget then return end
    
    if not isWidgetValid(notificationData.widget) then
        if isPinned then
            pinnedNotifications[slot] = nil
        else
            activeNotifications[slot] = nil
        end
        repositionNotifications()
        processNotificationQueue()
        return
    end
    
    -- Animar saída (mover para fora da tela)
    local parentSize = modules.game_interface.getRootPanel():getSize()
    
    pcall(function()
        notificationData.widget:setX(parentSize.width + 50)
    end)
    
    -- Remover após animação
    scheduleEvent(function()
        if isWidgetValid(notificationData.widget) then
            pcall(function()
                notificationData.widget:destroy()
            end)
        end
        
        if isPinned then
            pinnedNotifications[slot] = nil
        else
            activeNotifications[slot] = nil
        end
        
        repositionNotifications()
        processNotificationQueue()
    end, 300)
end

-- Função para inicializar o módulo
function init()
    if isInitialized then
        return
    end
    
    -- Conectar eventos do jogo
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })
    -- Conectar gameRightPanels para ajustar posição das notificações
    gameRootPanel = modules.game_interface.getRootPanel()
    gameRightPanels = gameRootPanel and gameRootPanel:getChildById('gameRightPanels') or nil
    if gameRightPanels then
        connect(gameRightPanels, {onGeometryChange = fitGamePanel})
    end

    
    -- the answer button styles (ChaosToastAccept / ChaosToastDecline)
    pcall(function() g_ui.importStyle('toastbuttons') end)

    -- Registrar opcode
    if ProtocolGame and ProtocolGame.registerExtendedOpcode then
        ProtocolGame.registerExtendedOpcode(opcode, onExtendedOpcode)
    end
    
    isInitialized = true
end

-- Função para finalizar o módulo
function terminate()
    if gameRightPanels then
        disconnect(gameRightPanels, {onGeometryChange = fitGamePanel})
    end

    if not isInitialized then return end
    
    -- Esconder todas as notificações
    hideAllNotifications()
    
    -- Desconectar eventos
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })
    
    -- Desregistrar opcode
    if ProtocolGame and ProtocolGame.unregisterExtendedOpcode then
        ProtocolGame.unregisterExtendedOpcode(opcode)
    end
    
    -- Limpar variáveis
    notificationQueue = {}
    activeNotifications = {}
    pinnedNotifications = {}
    isInitialized = false
end

-- Função chamada quando o jogo inicia
function onGameStart()
    hideAllNotifications()
end

-- Função chamada quando o jogo termina
function onGameEnd()
    hideAllNotifications()
end

-- Função para esconder todas as notificações
function hideAllNotifications()
    notificationQueue = {}
    
    -- Remover todas as notificações ativas
    for slot, data in pairs(activeNotifications) do
        if data and data.widget then
            pcall(function()
                data.widget:destroy()
            end)
        end
    end
    activeNotifications = {}
    
    -- Remover todas as notificações fixadas
    for slot, data in pairs(pinnedNotifications) do
        if data and data.widget then
            pcall(function()
                data.widget:destroy()
            end)
        end
    end
    pinnedNotifications = {}
end

-- the toast title: the Chaos heading font (client_chaos_theme ChaosTheme.fonts) when the client has it, stock Verdana otherwise
local function titleFont()
    local theme = modules.client_chaos_theme and modules.client_chaos_theme.ChaosTheme
    return theme and theme.font and theme.font('heading', 'verdana-11px-antialised') or 'verdana-11px-antialised'
end

-- the answer buttons of the invitation toasts: generated plates (client/tools/gen_toast_art.py, styles in
-- toastbuttons.otui) with normal / hover / pressed / disabled states. kind 'yes' (Accept, Start) sits left of the
-- middle of the text column, 'no' (Decline, Cancel) right of it; both 80 x 24, ANSWER_GAP apart
local ANSWER_W, ANSWER_GAP, ANSWER_BOTTOM = 80, 12, 33
local TEXT_LEFT, TEXT_RIGHT, TOAST_W = 80, 30, 340 -- the message label's margins and the toast width

local function createAnswerButton(parent, kind, id, text)
    local style = kind == 'yes' and 'ChaosToastAccept' or 'ChaosToastDecline'
    local ok, button = pcall(g_ui.createWidget, style, parent)
    if not ok or not button then
        return nil
    end
    pcall(function()
        local mid = TEXT_LEFT + math.floor((TOAST_W - TEXT_LEFT - TEXT_RIGHT) / 2)
        button:setId(id)
        button:setText(text)
        button:setFont(titleFont())
        button:setMarginBottom(ANSWER_BOTTOM)
        button:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        if kind == 'yes' then
            button:setMarginLeft(mid - math.floor(ANSWER_GAP / 2) - ANSWER_W)
            button:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        else
            button:setMarginRight(TOAST_W - mid - math.ceil(ANSWER_GAP / 2) - ANSWER_W)
            button:addAnchor(AnchorRight, 'parent', AnchorRight)
        end
    end)
    return button
end

-- FUNÇÃO CORRIGIDA: Criar notificação com botões para party invite e catacomb free
local function createCompactNotification(data, isPinned)
    local gameRootPanel = modules.game_interface.getRootPanel()
    if not gameRootPanel then
        return nil
    end
    
    -- Criar painel principal da notificação
    local notification = g_ui.createWidget('Panel', gameRootPanel)
    if not notification then
        return nil
    end
    
    -- Variáveis de controle de pause
    local isPaused = false
    local pauseStartTime = 0
    local totalPausedTime = 0
    
    -- Altura maior para notificações com botões
    local notificationHeight = ChaosNotifyView.heightOf(data.notificationType)
    
    -- Configurar o painel principal
    pcall(function()
        notification:setId('notificationPanel')
        notification:setSize({width = 340, height = notificationHeight})
        notification:setImageSource('images/Background')
        notification:setImageColor('#ccbebb')
        notification:setBorderWidth(1)
        notification:setBorderColor('#6a5632')
        notification:setVisible(true)
        notification:raise()
        -- Ancorar notificação no topo e na direita para usar margins (como tutorial)
        notification:addAnchor(AnchorTop, 'parent', AnchorTop)
        notification:addAnchor(AnchorRight, 'parent', AnchorRight)
        notification:focus()
    end)
    
    -- Criar container do ícone (esquerda)
    local iconContainer = g_ui.createWidget('Panel', notification)
    if iconContainer then
        pcall(function()
            iconContainer:setId('iconContainer')
            iconContainer:setSize({width = 60, height = 60})
            iconContainer:setImageSource('images/Box Categories')
            iconContainer:setImageColor('#a78c87')
            iconContainer:setBorderWidth(1)
            iconContainer:setBorderColor('#6a5632')
            iconContainer:setMarginLeft(10)
            iconContainer:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            iconContainer:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        end)
        
        -- Criar ícone do módulo
        local moduleIcon = g_ui.createWidget('UIWidget', iconContainer)
        if moduleIcon then
            pcall(function()
                moduleIcon:setId('moduleIcon')
                moduleIcon:setSize({width = 48, height = 48})
                moduleIcon:setImageSource(data.icon or 'images/notifications/gm.png')
                moduleIcon:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
                moduleIcon:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
            end)
        end
        
        -- CRIAR LOOKTYPE SOBREPOSTO (APENAS PARA TASKS DE MONSTRO)
        if data.monsterLookType then
            local monsterOutfit = g_ui.createWidget('UICreature', iconContainer)
            if monsterOutfit then
                pcall(function()
                    monsterOutfit:setId('monsterOutfit')
                    monsterOutfit:setSize({width = 48, height = 48})
                    monsterOutfit:setOutfit({type = data.monsterLookType}) -- the engine reads "type"
                    monsterOutfit:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
                    monsterOutfit:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
                end)
            end
        end
    end
    
    -- Criar botão de fechar (topo direito)
    local closeButton = g_ui.createWidget('UIButton', notification)
    if closeButton then
        pcall(function()
            closeButton:setId('closeButton')
            closeButton:setSize({width = 20, height = 20})
            closeButton:setImageSource('images/Icon Close')
            closeButton:setTooltip("Close notification")
            closeButton:setMarginTop(5)
            closeButton:setMarginRight(5)
            closeButton:addAnchor(AnchorTop, 'parent', AnchorTop)
            closeButton:addAnchor(AnchorRight, 'parent', AnchorRight)
        end)
        
        -- Função de fechar
        closeButton.onClick = function()
            -- Encontrar e remover a notificação das ativas
            for slot, notifData in pairs(activeNotifications) do
                if notifData.widget == notification then
                    animateNotificationOut(notifData, slot, false)
                    return
                end
            end
            
            -- Encontrar e remover a notificação das fixadas
            for slot, notifData in pairs(pinnedNotifications) do
                if notifData.widget == notification then
                    animateNotificationOut(notifData, slot, true)
                    return
                end
            end
        end
    end
    
    -- Criar título principal
    local titleLabel = g_ui.createWidget('Label', notification)
    if titleLabel then
        pcall(function()
            titleLabel:setId('titleLabel')
            titleLabel:setText(data.title or 'NOTIFICATION')
            titleLabel:setFont(titleFont())
            titleLabel:setColor(data.titleColor or '#a3844b')
            titleLabel:setTextAlign(AlignCenter)
            titleLabel:setHeight(18)
            titleLabel:setMarginLeft(80)
            titleLabel:setMarginTop(8)
            titleLabel:setMarginRight(30)
            titleLabel:addAnchor(AnchorTop, 'parent', AnchorTop)
            titleLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            titleLabel:addAnchor(AnchorRight, 'parent', AnchorRight)
        end)
    end
    
    -- Criar texto da mensagem
    local messageLabel = g_ui.createWidget('Label', notification)
    if messageLabel then
        pcall(function()
            messageLabel:setId('messageLabel')
            messageLabel:setText(data.message or 'Notification message')
            messageLabel:setFont('verdana-11px-antialised')
            messageLabel:setColor('#FFD700')
            messageLabel:setTextAlign(AlignLeft)
            messageLabel:setTextWrap(true)
            -- four wrapped lines fit above the timer bar; two where Accept/Start buttons sit below the text
            local hasButtons = ChaosNotifyView.hasButtons(data.notificationType)
            messageLabel:setHeight(hasButtons and 35 or 64)
            messageLabel:setMarginLeft(80)
            messageLabel:setMarginTop(28)
            messageLabel:setMarginRight(30)
            messageLabel:addAnchor(AnchorTop, 'parent', AnchorTop)
            messageLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            messageLabel:addAnchor(AnchorRight, 'parent', AnchorRight)
        end)
    end
    
    -- NOVO: Criar botões para party invite
    if data.notificationType == "PARTY_INVITE" and data.inviteData then
        -- Botão Aceitar
        local acceptButton = createAnswerButton(notification, 'yes', 'acceptButton', 'Accept')
        if acceptButton then
            acceptButton.onClick = function()
                -- CRÍTICO: Aceitar convite de party usando sistema customizado integrado
                if g_game and g_game.getLocalPlayer then
                    local localPlayer = g_game.getLocalPlayer()
                    if localPlayer then
                        local success, result = pcall(function()
                            -- CORRIGIDO: Enviar comando para servidor aceitar party customizada
                            g_game.getProtocolGame():sendExtendedOpcode(151, "accept_invite|" .. data.inviteData.inviterName)
                        end)
                        if not success then

                        end
                    end
                end
                
                -- Fechar notificação
                for slot, notifData in pairs(activeNotifications) do
                    if notifData.widget == notification then
                        animateNotificationOut(notifData, slot, false)
                        return
                    end
                end
            end
        end
        
        -- Botão Recusar
        local declineButton = createAnswerButton(notification, 'no', 'declineButton', 'Decline')
        if declineButton then
            declineButton.onClick = function()
                -- CRÍTICO: Recusar convite de party usando sistema customizado integrado
                if g_game and g_game.getLocalPlayer then
                    local localPlayer = g_game.getLocalPlayer()
                    if localPlayer then
                        local success, result = pcall(function()
                            -- CORRIGIDO: Enviar comando para servidor recusar party customizada
                            g_game.getProtocolGame():sendExtendedOpcode(151, "decline_invite|" .. data.inviteData.inviterName)
                        end)
                        if not success then

                        end
                    end
                end
                
                -- Fechar notificação
                for slot, notifData in pairs(activeNotifications) do
                    if notifData.widget == notification then
                        animateNotificationOut(notifData, slot, false)
                        return
                    end
                end
            end
        end
    end
    
    -- NOVO: Criar botões para catacomb free
    if data.notificationType == "CATACOMB_FREE" and data.catacombData then
        -- Botão Start
        local startButton = createAnswerButton(notification, 'yes', 'startButton', 'Start')
        if startButton then
            startButton.onClick = function()
                -- Verificar se está em PZ antes de iniciar
                local localPlayer = g_game.getLocalPlayer()
                if localPlayer then
                    local tile = localPlayer:getTile()
                    if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
                        -- Iniciar catacomb automaticamente
                        if g_game and g_game.getProtocolGame then
                            local success, result = pcall(function()
                                local message = string.format("start_catacomb|solo|%s|%s", 
                                    data.catacombData.level, data.catacombData.element)
                                g_game.getProtocolGame():sendExtendedOpcode(151, message)
                            end)
                            if not success then

                            end
                        end
                    else

                    end
                end
                
                -- Fechar notificação
                for slot, notifData in pairs(activeNotifications) do
                    if notifData.widget == notification then
                        animateNotificationOut(notifData, slot, false)
                        return
                    end
                end
            end
        end
        
        -- Botão Cancel
        local cancelButton = createAnswerButton(notification, 'no', 'cancelButton', 'Cancel')
        if cancelButton then
            cancelButton.onClick = function()
                -- Remover da fila
                if g_game and g_game.getProtocolGame then
                    local success, result = pcall(function()
                        g_game.getProtocolGame():sendExtendedOpcode(152, "leave_queue")
                    end)
                    if not success then

                    end
                end
                
                -- Fechar notificação
                for slot, notifData in pairs(activeNotifications) do
                    if notifData.widget == notification then
                        animateNotificationOut(notifData, slot, false)
                        return
                    end
                end
            end
        end
    end
    
    -- Criar barra de tempo - apenas para notificações temporárias
    local timerBarContainer = nil
    local timerBarFill = nil
    local timerLabel = nil
    
    if not isPinned then
        timerBarContainer = g_ui.createWidget('Panel', notification)
        if timerBarContainer then
            pcall(function()
                timerBarContainer:setId('timerBarContainer')
                timerBarContainer:setSize({width = 330, height = 6})
                timerBarContainer:setBackgroundColor('#34495E')
                timerBarContainer:setBorderWidth(1)
                timerBarContainer:setBorderColor('#2c3e50')
                timerBarContainer:setMarginBottom(5)
                timerBarContainer:setMarginLeft(5)
                timerBarContainer:setMarginRight(5)
                timerBarContainer:addAnchor(AnchorBottom, 'parent', AnchorBottom)
                timerBarContainer:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                timerBarContainer:addAnchor(AnchorRight, 'parent', AnchorRight)
            end)
            
            -- Criar preenchimento da barra
            timerBarFill = g_ui.createWidget('Panel', timerBarContainer)
            if timerBarFill then
                pcall(function()
                    timerBarFill:setId('timerBarFill')
                    timerBarFill:setSize({width = 328, height = 4})
                    timerBarFill:setBackgroundColor('#00FF7F')
                    timerBarFill:setBorderWidth(0)
                    timerBarFill:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                    timerBarFill:addAnchor(AnchorTop, 'parent', AnchorTop)
                    timerBarFill:addAnchor(AnchorBottom, 'parent', AnchorBottom)
                end)
            end
            
            -- Criar label do timer
            timerLabel = g_ui.createWidget('Label', timerBarContainer)
            if timerLabel then
                pcall(function()
                    timerLabel:setId('timerLabel')
                    timerLabel:setText('30')
                    timerLabel:setFont('verdana-11px-antialised')
                    timerLabel:setColor('#FFFFFF')
                    timerLabel:setTextAlign(AlignCenter)
                    timerLabel:setMarginRight(155)
                    timerLabel:setMarginTop(-9)
                    timerLabel:addAnchor(AnchorRight, 'parent', AnchorRight)
                    timerLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
                end)
            end
        end
    end
    
    -- Sistema de pause
    notification.onMousePress = function(widget, mousePos, mouseButton)
        if mouseButton == MouseLeftButton then
            isPaused = true
            pauseStartTime = g_clock.millis()
            return true
        end
        return false
    end
    
    notification.onMouseRelease = function(widget, mousePos, mouseButton)
        if mouseButton == MouseLeftButton and isPaused then
            isPaused = false
            local pauseDuration = g_clock.millis() - pauseStartTime
            totalPausedTime = totalPausedTime + pauseDuration
            
            return true
        end
        return false
    end
    
    return {
        widget = notification,
        timerBarFill = timerBarFill,
        timerLabel = timerLabel,
        timerBarContainer = timerBarContainer,
        data = data,
        isPaused = function() return isPaused end,
        getTotalPausedTime = function() return totalPausedTime end
    }
end

-- Função para fixar notificação
function pinNotification(notificationWidget, data)
    if not notificationWidget or not data then return end
    
    -- Verificar se já temos muitas notificações fixadas
    local pinnedCount = 0
    for _ in pairs(pinnedNotifications) do
        pinnedCount = pinnedCount + 1
    end
    
    if pinnedCount >= maxPinnedNotifications then
        return
    end
    
    -- Encontrar slot livre para fixada
    local slot = nil
    for i = 1, maxPinnedNotifications do
        if not pinnedNotifications[i] then
            slot = i
            break
        end
    end
    
    if not slot then return end
    
    -- Remover das notificações temporárias se estiver lá
    for tempSlot, tempData in pairs(activeNotifications) do
        if tempData.widget == notificationWidget then
            activeNotifications[tempSlot] = nil
            break
        end
    end
    
    -- Adicionar às fixadas
    pinnedNotifications[slot] = {
        widget = notificationWidget,
        data = data
    }
    
    -- Remover timer se houver
    local timerBarContainer = notificationWidget:getChildById('timerBarContainer')
    if timerBarContainer then
        pcall(function()
            timerBarContainer:setVisible(false)
        end)
    end
    
    repositionNotifications()
    processNotificationQueue()
end

-- Função para desfixar notificação
function unpinNotification(notificationWidget)
    if not notificationWidget then return end
    
    -- Encontrar e remover das fixadas
    for slot, data in pairs(pinnedNotifications) do
        if data.widget == notificationWidget then
            pinnedNotifications[slot] = nil
            
            -- Animar saída
            animateNotificationOut({widget = notificationWidget}, slot, true)
            break
        end
    end
    
    repositionNotifications()
end

-- Função para atualizar timer da notificação
local function updateNotificationTimer(notificationData, timeLeft, totalTime)
    if not notificationData then return end
    
    -- Verificar se está pausado
    if notificationData.isPaused and notificationData.isPaused() then
        return
    end
    
    -- Verificar se os widgets ainda são válidos
    if notificationData.timerBarFill and isWidgetValid(notificationData.timerBarFill) then
        -- Atualizar barra de progresso
        local percentage = timeLeft / totalTime
        local fillWidth = math.floor(328 * percentage)
        pcall(function()
            notificationData.timerBarFill:setWidth(fillWidth)
        end)
    end
    
    if notificationData.timerLabel and isWidgetValid(notificationData.timerLabel) then
        -- Atualizar label do timer
        pcall(function()
            notificationData.timerLabel:setText(tostring(math.ceil(timeLeft / 1000)))
        end)
    end
end

-- Função para animar entrada da notificação
local function animateNotificationIn(notificationData)
    if not notificationData or not notificationData.widget then return end
    
    if not isWidgetValid(notificationData.widget) then return end
    
    local gameRootPanel = modules.game_interface.getRootPanel()
    local parentSize = gameRootPanel:getSize()
    
    -- Começar fora da tela (direita)
    pcall(function()
        notificationData.widget:setX(parentSize.width + 50)
        notificationData.widget:setVisible(true)
        notificationData.widget:raise()
    end)
    
    -- Animar para posição final
    scheduleEvent(function()
        if isWidgetValid(notificationData.widget) then
            repositionNotifications()
        end
    end, 50)
end

-- Função para encontrar slot livre para notificação
function findFreeNotificationSlot()
    for i = 1, maxNotifications do
        if not activeNotifications[i] then
            return i
        end
    end
    return nil
end

-- Função para exibir notificação
function showNotification(data, slot)
    if not data or not slot then 
        return 
    end
    
    -- Determinar duração baseada no tipo (usa field 'duration' dentro de NOTIFICATION_TYPES se presente)
    local duration = notificationDuration
    local typeData = NOTIFICATION_TYPES[data.notificationType]
    if typeData and typeData.duration then
        duration = typeData.duration
    end
    
    -- Criar widget da notificação
    local notificationWidget = createCompactNotification(data, false)
    if not notificationWidget then
        return
    end
    
    -- Registrar notificação ativa
    activeNotifications[slot] = {
        widget = notificationWidget.widget,
        timerBarFill = notificationWidget.timerBarFill,
        timerLabel = notificationWidget.timerLabel,
        timerBarContainer = notificationWidget.timerBarContainer,
        startTime = g_clock.millis(),
        duration = duration,
        data = data,
        isPaused = notificationWidget.isPaused,
        getTotalPausedTime = notificationWidget.getTotalPausedTime
    }
    
    -- Ajustar label inicial do timer baseado na duração definida
    local timerLabelWidget = notificationWidget and notificationWidget.timerLabel
    if timerLabelWidget and isWidgetValid(timerLabelWidget) then
        pcall(function()
            timerLabelWidget:setText(tostring(math.ceil(duration / 1000)))
        end)
    end

    -- Animar entrada
    animateNotificationIn(activeNotifications[slot])
    
    -- Timer para considerar pausas
    local function updateTimer()
        if not activeNotifications[slot] then return end
        
        local currentTime = g_clock.millis()
        local totalPausedTime = activeNotifications[slot].getTotalPausedTime()
        local elapsed = currentTime - activeNotifications[slot].startTime - totalPausedTime
        local timeLeft = duration - elapsed
        
        -- Se está pausado, não decrementar o tempo
        if activeNotifications[slot].isPaused() then
            scheduleEvent(updateTimer, 100)
            return
        end
        
        if timeLeft <= 0 then
            animateNotificationOut(activeNotifications[slot], slot, false)
            return
        end
        
        updateNotificationTimer(activeNotifications[slot], timeLeft, duration)
        scheduleEvent(updateTimer, 100)
    end
    
    updateTimer()
end

-- Função para adicionar notificação à fila
function addNotification(notificationType, message, customIcon, monsterLookType, inviteData, catacombData)
    if not isInitialized then
        return
    end
    
    local typeData = NOTIFICATION_TYPES[notificationType]
    if not typeData then
        return
    end
    
    local notificationData = {
        notificationType = notificationType,
        icon = customIcon or typeData.icon,
        title = typeData.title,
        titleColor = typeData.titleColor,
        message = message,
        monsterLookType = monsterLookType,
        inviteData = inviteData,
        catacombData = catacombData
    }
    
    -- three shown at once, the rest wait in a capped queue (notifyview.lua ChaosNotifyView.enqueue)
    ChaosNotifyView.enqueue(notificationQueue, notificationData)
    processNotificationQueue()
end

-- Função para fechar notificação manualmente
function closeNotification()
    for slot, data in pairs(activeNotifications) do
        if data then
            animateNotificationOut(data, slot, false)
            break
        end
    end
end

-- Handler para opcodes do servidor
function onExtendedOpcode(protocol, opcode, buffer)
    if opcode ~= 79 or not buffer then 
        return 
    end
    
    local success, data = pcall(json.decode, buffer)
    if not success or not data or not data.action then 
        return 
    end
    
    -- Handlers para diferentes tipos de notificação
    local handlers = {
        gmBroadcast = function(data)
            if data.message then
                addNotification("GM_BROADCAST", data.message)
            end
        end,
        
        taskComplete = function(data)
            if data.taskName and data.taskPoints and data.killCount then
                local message = string.format("Task Complete: of %s, killed %d and received %d task points", 
                                            data.taskName, data.killCount, data.taskPoints)
                addNotification("TASK_COMPLETE", message, data.customIcon, data.monsterLookType)
            end
        end,
        
        -- bounty board (server data/scripts/chaos/bounty.lua): milestones, completion, weekly chest
        bounty = function(data)
            if data.message then
                addNotification("BOUNTY", data.message, nil, data.monsterLookType)
            end
        end,

        -- new players (server data/scripts/chaos/newplayer*.lua): welcome, tutorial stations, milestone gifts
        newplayer = function(data)
            if data.message then
                addNotification("NEW_PLAYER", data.message)
            end
        end,

        -- bestiary and kill tasks (server data/scripts/chaos/bestiary.lua)
        bestiary = function(data)
            if data.message then
                addNotification("BESTIARY", data.message, nil, data.monsterLookType)
            end
        end,

        -- achievements (server data/scripts/chaos/achievements.lua)
        achievement = function(data)
            if data.message then
                addNotification("ACHIEVEMENT", data.message)
            end
        end,

        -- boss passive points (server data/scripts/chaos/bosspoints.lua)
        bosspoints = function(data)
            if data.message then
                addNotification("BOSS_POINT", data.message)
            end
        end,

        -- ascension quest (server data/scripts/chaos/ascension_quest.lua)
        ascension = function(data)
            if data.message then
                addNotification("ASCENSION", data.message)
            end
        end,

        -- the market (server data/scripts/chaos/market.lua)
        market = function(data)
            if data.message then
                addNotification("MARKET", data.message)
            end
        end,

        -- a listing of the player sold (server data/scripts/chaos/market.lua, orbexchange.lua)
        sale = function(data)
            if data.message then
                addNotification("SALE", data.message)
            end
        end,

        -- season pass (server data/scripts/chaos/seasonpass.lua)
        seasonpass = function(data)
            if data.message then
                addNotification("SEASON_PASS", data.message)
            end
        end,

        -- Seasonal Journey (server data/scripts/chaos/season_journey.lua)
        journey = function(data)
            if data.message then
                addNotification("JOURNEY", data.message)
            end
        end,

        -- invasions and world events (server data/scripts/chaos/invasion.lua)
        invasion = function(data)
            if data.message then
                addNotification("INVASION", data.message)
            end
        end,

        battlePassComplete = function(data)
            if data.missionName and data.expPoints then
                local message = string.format("Mission Complete: %s and received %d battle pass exp", 
                                            data.missionName, data.expPoints)
                addNotification("BATTLE_PASS", message, nil, data.monsterLookType)
            end
        end,
        
        -- NOVO: Handler para convite de party
        partyInvite = function(data)
            if data.inviterName then
                -- example = Lury [30] invited you to join their party for catacomb ice  level 1!
                local message = string.format("%s [%d] invited you to join their party for catacomb %s level %d!", 
                    data.inviterName, data.inviterResets or 0, 
                    data.element and data.element:gsub("^%l", string.upper) or "unknown", 
                    data.level or 0)
                
                local inviteData = {
                    inviterName = data.inviterName,
                    inviterResets = data.inviterResets or 0,
                    level = data.level or 0,
                    element = data.element
                }
                
                addNotification("PARTY_INVITE", message, nil, nil, inviteData)
            end
        end,
        
        -- Handler para catacomb livre
        catacombFree = function(data)
            if data.element and data.level then
                local message = string.format("The %s Catacomb Level %s is now free!", 
                    data.element:gsub("^%l", string.upper), data.level)
                
                local catacombData = {
                    element = data.element,
                    level = data.level
                }
                
                addNotification("CATACOMB_FREE", message, nil, nil, nil, catacombData)
            end
        end
    }
    
    local handler = handlers[data.action]
    if handler then
        handler(data)
    end
end

-- Função de teste para debug
function testNotifications()
    addNotification("GM_BROADCAST", "Test GM notification!")
    scheduleEvent(function()
        addNotification("TASK_COMPLETE", "You completed the Dragon task and received 100 points!", nil, 718)
    end, 2000)
    scheduleEvent(function()
        addNotification("BATTLE_PASS", "You completed the Kill 50 Demons mission and received 500 exp points!")
    end, 4000)
    scheduleEvent(function()
        -- Teste de convite de party
        local inviteData = {
            inviterName = "TestPlayer",
            level = 1,
            element = "ice"
        }
        addNotification("PARTY_INVITE", "TestPlayer invited you to join their party for catacomb!", nil, nil, inviteData)
    end, 6000)
    scheduleEvent(function()
        addNotification("SALE", "While you were away: 3 items sold for 4.2M gold: Doombringer, 20x Orb of Fate, plate armor.")
        addNotification("ACHIEVEMENT", "The Thousandth Step: +50 points. Title: the Unbroken. Reward: mount Doombringer.")
    end, 1000)
    scheduleEvent(function()
        -- Teste de catacomb livre
        local catacombData = {
            element = "fire",
            level = 1
        }
        addNotification("CATACOMB_FREE", "The Fire Catacomb Level 1 is now free!", nil, nil, nil, catacombData)
    end, 8000)
end