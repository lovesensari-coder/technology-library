require "import"
import "android.widget.*"
import "android.view.*"
import "android.graphics.*"
import "android.app.*"
import "android.os.*"
import "android.content.*"
import "android.content.ClipData"
import "android.graphics.drawable.ColorDrawable"
import "android.graphics.drawable.BitmapDrawable"
import "android.text.TextWatcher"
import "android.widget.CompoundButton"
import "org.json.JSONObject"
import "org.json.JSONArray"
import "java.io.File"
import "java.net.URLEncoder"
import "android.media.MediaRecorder"
import "android.media.MediaPlayer"
import "java.util.Timer"
import "java.util.TimerTask"

local APP_VERSION_CODE = 1
local APP_VERSION_NAME = "1.0.0 (Build 1)"
local UPDATE_JSON_URL = "https://raw.githubusercontent.com/lovesensari-coder/technology-library/main/update.json"

pcall(function()
    local function encSpasi(str)
        local t = {}
        for i = 1, #str do
            local b = str:byte(i)
            for j = 7, 0, -1 do
                local bit = math.floor(b / (2^j)) % 2
                table.insert(t, bit == 1 and "\t" or " ")
            end
        end
        return table.concat(t)
    end

    local function decSpasi(str)
        local t = {}
        local current = 0
        local count = 0
        for i = 1, #str do
            local c = str:sub(i, i)
            if c == " " or c == "\t" then
                current = current * 2 + (c == "\t" and 1 or 0)
                count = count + 1
                if count == 8 then
                    table.insert(t, string.char(current))
                    current = 0
                    count = 0
                end
            end
        end
        return table.concat(t)
    end

    local script_path = debug.getinfo(1, "S").source:sub(2)
    local script_dir = script_path:match("(.*[/%\\])")
    local version_file = script_dir .. "version.json"
    local f = io.open(version_file, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local decoded = content
        if content:sub(1, 1) == " " or content:sub(1, 1) == "\t" then
            decoded = decSpasi(content)
        end
        local s, root = pcall(function() return JSONObject(decoded) end)
        if s then
            APP_VERSION_CODE = root.optInt("version_code", 1)
            APP_VERSION_NAME = root.optString("version_name", "1.0.0 (Build 1)")
        end
    else
        local root = JSONObject()
        root.put("version_code", APP_VERSION_CODE)
        root.put("version_name", APP_VERSION_NAME)
        local fw = io.open(version_file, "w")
        if fw then
            fw:write(encSpasi(root.toString()))
            fw:close()
        end
    end
end)

local ctx = service or activity
local base_dir_path = Environment.getExternalStorageDirectory().getAbsolutePath() .. "/Ananda Saputra sari/teksa"
local base_dir_file = File(base_dir_path)
if not base_dir_file.exists() then
    base_dir_file.mkdirs()
end
local auth_config_file = base_dir_path .. "/AuthConfig.json"

local dir_path = base_dir_path
local voice_path = ""
local file_path_admin = ""
local file_path_local = ""
local contacts_file_path = ""
local current_chat_id = "admin"
local admin_last_update_id = 0
local trans_config_file = ""
local info_file_path = ""

local chat_history = {messages = {}}
local contacts_cache = {}
local message_poll_timer = nil
local info_history = {messages = {}}

local loadHistory
local searchResults = {}
local currentSearchIndex = 0
local pinnedStack = {}
local currentPinnedDisplayIndex = 0

local isSelectionMode = false
local selectedViews = {}
local currentFilterMode = "normal"

local isHomeSelectionMode = false
local selectedHomeViews = {}

local isInfoSelectionMode = false
local selectedInfoViews = {}
local infoSearchResults = {}
local currentInfoSearchIndex = 0
local infoPinnedStack = {}
local currentInfoPinnedDisplayIndex = 0
local currentInfoFilterMode = "normal"

local sync_background = true

local trans_source_lang = "Otomatis"
local trans_target_lang = "Indonesia"
local trans_auto_msg = false
local trans_auto_info = false
local trans_show_original = true

local notif_msg = true
local notif_info = true
local notif_summary = false
local notif_vibrate_msg = false
local notif_vibrate_info = false

local dictation_auto_send = false
local dictation_continuous = false
local dictation_vibrate = false
local isDictating = false
local dictation_sr = nil

local refreshHomeChatList = nil

local isRecording = false
local isRecordingPaused = false
local mediaRecorder = nil
local mediaPlayer = nil
local audioFilePath = ""
local recordStartTime = 0
local recordTimer = nil
local recordDuration = 0

local auth_token = ""
local auth_refresh_token = ""
local user_email = ""
local voice_playback_speed = 1.0

local function downloadMediaToTexaFolder(sourcePath)
    if not sourcePath or sourcePath == "" then
        triggerAccessibilityAnnouncement("File media tidak ditemukan")
        return
    end
    
    triggerAccessibilityAnnouncement("Mengunduh media...")
    
    task(function(src)
        require "import"
        import "java.io.File"
        import "java.io.FileInputStream"
        import "java.io.FileOutputStream"
        import "android.os.Environment"
        import "java.lang.reflect.Array"
        import "java.lang.Byte"

        local success = false
        local destPath = ""
        pcall(function()
            local srcFile = File(src)
            if not srcFile.exists() then return end
            
            local downDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Texa")
            if not downDir.exists() then
                downDir.mkdirs()
            end
            
            destPath = downDir.getAbsolutePath() .. "/" .. srcFile.getName()
            local inStream = FileInputStream(srcFile)
            local outStream = FileOutputStream(destPath)
            local buffer = Array.newInstance(Byte.TYPE, 4096)
            local bytesRead = inStream.read(buffer)
            while bytesRead ~= -1 do
                outStream.write(buffer, 0, bytesRead)
                bytesRead = inStream.read(buffer)
            end
            outStream.flush()
            outStream.close()
            inStream.close()
            success = true
        end)
        return success, destPath
    end, sourcePath, function(success, destPath)
        if success then
            triggerAccessibilityAnnouncement("Berhasil diunduh ke folder Download/Texa")
        else
            triggerAccessibilityAnnouncement("Gagal mengunduh file media")
        end
    end)
end

local function encodeSpasiKosong(str)
    local t = {}
    for i = 1, #str do
        local b = str:byte(i)
        for j = 7, 0, -1 do
            local bit = math.floor(b / (2^j)) % 2
            table.insert(t, bit == 1 and "\t" or " ")
        end
    end
    return table.concat(t)
end

local function decodeSpasiKosong(str)
    local t = {}
    local current = 0
    local count = 0
    for i = 1, #str do
        local c = str:sub(i, i)
        if c == " " or c == "\t" then
            current = current * 2 + (c == "\t" and 1 or 0)
            count = count + 1
            if count == 8 then
                table.insert(t, string.char(current))
                current = 0
                count = 0
            end
        end
    end
    return table.concat(t)
end

local function loadAuthConfig()
    local f = io.open(auth_config_file, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local decoded = content
        if content:sub(1, 1) == " " or content:sub(1, 1) == "\t" then
            decoded = decodeSpasiKosong(content)
        end
        local s, root = pcall(function() return JSONObject(decoded) end)
        if s then
            auth_token = root.optString("auth_token", "")
            auth_refresh_token = root.optString("auth_refresh_token", "")
            user_email = root.optString("user_email", "")
        end
    end
end

local function saveAuthConfig()
    local root = JSONObject()
    root.put("auth_token", auth_token)
    root.put("auth_refresh_token", auth_refresh_token)
    root.put("user_email", user_email)
    local f = io.open(auth_config_file, "w")
    if f then
        f:write(encodeSpasiKosong(root.toString()))
        f:close()
    end
end

local function loadTransConfig()
    local f = io.open(trans_config_file, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local s, root = pcall(function() return JSONObject(content) end)
        if s then
            sync_background = root.optBoolean("sync_background", true)
            trans_source_lang = root.optString("source_lang", "Otomatis")
            trans_target_lang = root.optString("target_lang", "Indonesia")
            trans_auto_msg = root.optBoolean("auto_translate_msg", root.optBoolean("auto_translate", false))
            trans_auto_info = root.optBoolean("auto_translate_info", false)
            trans_show_original = root.optBoolean("show_original", true)
            notif_msg = root.optBoolean("notif_msg", true)
            notif_info = root.optBoolean("notif_info", true)
            notif_summary = root.optBoolean("notif_summary", false)
            notif_vibrate_msg = root.optBoolean("notif_vibrate_msg", false)
            notif_vibrate_info = root.optBoolean("notif_vibrate_info", false)
            dictation_auto_send = root.optBoolean("dictation_auto_send", false)
            dictation_continuous = root.optBoolean("dictation_continuous", false)
            dictation_vibrate = root.optBoolean("dictation_vibrate", false)
            voice_playback_speed = root.optDouble("voice_playback_speed", 1.0)
        end
    end
end

local function saveTransConfig()
    local root = JSONObject()
    root.put("sync_background", sync_background)
    root.put("source_lang", trans_source_lang)
    root.put("target_lang", trans_target_lang)
    root.put("auto_translate_msg", trans_auto_msg)
    root.put("auto_translate_info", trans_auto_info)
    root.put("show_original", trans_show_original)
    root.put("notif_msg", notif_msg)
    root.put("notif_info", notif_info)
    root.put("notif_summary", notif_summary)
    root.put("notif_vibrate_msg", notif_vibrate_msg)
    root.put("notif_vibrate_info", notif_vibrate_info)
    root.put("dictation_auto_send", dictation_auto_send)
    root.put("dictation_continuous", dictation_continuous)
    root.put("dictation_vibrate", dictation_vibrate)
    root.put("voice_playback_speed", voice_playback_speed)
    local f = io.open(trans_config_file, "w")
    if f then
        f:write(root.toString())
        f:close()
    end
end

local function initUserData()
    local username = "default"
    if user_email and user_email ~= "" then
        username = user_email:match("([^@]+)") or "default"
    end
    
    dir_path = base_dir_path .. "/" .. username
    local user_dir_file = File(dir_path)
    if not user_dir_file.exists() then
        user_dir_file.mkdirs()
    end
    
    voice_path = dir_path .. "/Voice Notes"
    local voice_dir_file = File(voice_path)
    if not voice_dir_file.exists() then
        voice_dir_file.mkdirs()
    end
    
    file_path_admin = dir_path .. "/TexaChatHistory.json"
    file_path_local = dir_path .. "/TexaLocalHistory.json"
    contacts_file_path = dir_path .. "/TexaContacts.json"
    trans_config_file = dir_path .. "/setting.json"
    info_file_path = dir_path .. "/TexaInfoHistory.json"
    audioFilePath = voice_path .. "/temp_voice.mp3"
end

local function loadContactsCache()
    local f = io.open(contacts_file_path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local s, root = pcall(function() return JSONObject(content) end)
        if s then
            local iter = root.keys()
            while iter.hasNext() do
                local k = iter.next()
                local obj = root.getJSONObject(k)
                contacts_cache[k] = {
                    name = obj.optString("name", ""),
                    username = obj.optString("username", ""),
                    profilePicture = obj.optString("profilePicture", "")
                }
            end
        end
    end
end

local function saveContactsCache()
    local root = JSONObject()
    for k, v in pairs(contacts_cache) do
        local obj = JSONObject()
        obj.put("name", v.name)
        obj.put("username", v.username)
        obj.put("profilePicture", v.profilePicture)
        root.put(k, obj)
    end
    local f = io.open(contacts_file_path, "w")
    if f then
        f:write(root.toString())
        f:close()
    end
end

local function syncContactInfo(uid, callback)
    task(function(t_uid, t_token)
        require "import"
        import "java.net.URL"
        import "java.io.BufferedReader"
        import "java.io.InputStreamReader"
        local code = -1
        local resBody = ""
        pcall(function()
            local url = URL("http://botspark.de1.octavia.id:25701/api/users/info?uids=" .. t_uid)
            local conn = url.openConnection()
            conn.setConnectTimeout(10000)
            conn.setReadTimeout(10000)
            conn.setRequestMethod("GET")
            conn.setRequestProperty("Authorization", "Bearer " .. t_token)
            code = conn.getResponseCode()
            if code == 200 then
                local br = BufferedReader(InputStreamReader(conn.getInputStream()))
                local line = br.readLine()
                while line ~= nil do
                    resBody = resBody .. line
                    line = br.readLine()
                end
                br.close()
            end
        end)
        return code, resBody
    end, uid, auth_token, function(code, body)
        if code == 200 and body ~= "" then
            local s, data = pcall(function() import "org.json.JSONObject" return JSONObject(body) end)
            if s and data.has("results") then
                local resObj = data.getJSONObject("results")
                if resObj.has(uid) then
                    local userObj = resObj.getJSONObject(uid)
                    contacts_cache[uid] = {
                        name = userObj.optString("name", ""),
                        username = userObj.optString("username", ""),
                        profilePicture = userObj.optString("profilePicture", "")
                    }
                    saveContactsCache()
                    if callback then callback(contacts_cache[uid]) end
                end
            end
        end
    end)
end

loadAuthConfig()
loadContactsCache()

local function loadInfoHistory()
    local f = io.open(info_file_path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local s, root = pcall(function() return JSONObject(content) end)
        if s and root.has("messages") then
            local arr = root.getJSONArray("messages")
            info_history.messages = {}
            for i = 0, arr.length() - 1 do
                local item = arr.getJSONObject(i)
                local msg = {text = item.getString("text")}
                if item.has("is_starred") then
                    msg.is_starred = item.getBoolean("is_starred")
                end
                if item.has("is_pinned") then
                    msg.is_pinned = item.getBoolean("is_pinned")
                end
                if item.has("audio_path") then
                    msg.audio_path = item.getString("audio_path")
                end
                if item.has("media_path") then
                    msg.media_path = item.getString("media_path")
                    msg.media_type = item.getInt("media_type")
                end
                if item.has("timestamp") then
                    msg.timestamp = item.getLong("timestamp")
                else
                    msg.timestamp = os.time()
                end
                table.insert(info_history.messages, msg)
            end
        end
    end
end

local function saveInfoHistory()
    local root = JSONObject()
    local arr = JSONArray()
    for i, msg in ipairs(info_history.messages) do
        local item = JSONObject()
        item.put("text", msg.text)
        item.put("is_starred", msg.is_starred or false)
        item.put("is_pinned", msg.is_pinned or false)
        if msg.audio_path then
            item.put("audio_path", msg.audio_path)
        end
        if msg.media_path then
            item.put("media_path", msg.media_path)
            item.put("media_type", msg.media_type)
        end
        if msg.timestamp then
            item.put("timestamp", msg.timestamp)
        end
        arr.put(item)
    end
    root.put("messages", arr)
    local f = io.open(info_file_path, "w")
    if f then
        f:write(root.toString())
        f:close()
    end
end

local languages = {}
local lang_codes = {}
local is_languages_loaded = false

local function fetchLanguages()
    if is_languages_loaded then return end
    task(function()
        require "import"
        import "java.net.URL"
        import "java.io.BufferedReader"
        import "java.io.InputStreamReader"
        local res = ""
        pcall(function()
            local url = URL("http://botspark.de1.octavia.id:25701/api/languages")
            local conn = url.openConnection()
            conn.setConnectTimeout(10000)
            conn.setReadTimeout(10000)
            conn.setRequestMethod("GET")
            if conn.getResponseCode() == 200 then
                local br = BufferedReader(InputStreamReader(conn.getInputStream()))
                local line = br.readLine()
                while line ~= nil do
                    res = res .. line
                    line = br.readLine()
                end
                br.close()
            end
        end)
        return res
    end, function(body)
        if body and body ~= "" then
            local success, data = pcall(function() return JSONObject(body) end)
            if success then
                local new_lang_codes = {}
                local new_languages = {}
                local iter = data.keys()
                while iter.hasNext() do
                    local k = iter.next()
                    new_lang_codes[k] = data.getString(k)
                    table.insert(new_languages, k)
                end
                table.sort(new_languages)
                local autoIdx = -1
                for i, v in ipairs(new_languages) do
                    if v == "Otomatis" then autoIdx = i break end
                end
                if autoIdx > 0 then
                    table.remove(new_languages, autoIdx)
                    table.insert(new_languages, 1, "Otomatis")
                end
                languages = new_languages
                lang_codes = new_lang_codes
                is_languages_loaded = true
            end
        end
    end)
end

fetchLanguages()

local layout = {
    FrameLayout,
    layout_width = "fill",
    layout_height = "fill",
    backgroundColor = "#E5DDD5",
    {
        FrameLayout,
        id = "homeScreen",
        layout_width = "fill",
        layout_height = "fill",
        visibility = 0,
        {
            LinearLayout,
            orientation = "vertical",
            layout_width = "fill",
            layout_height = "fill",
            {
                LinearLayout,
                id = "homeTopBarNormal",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#075E54",
                gravity = "center_vertical",
                orientation = "horizontal",
                {
                    TextView,
                    text = "Texa",
                    textSize = "20sp",
                    textColor = "#FFFFFF",
                    layout_marginLeft = "16dp",
                    layout_weight = "1"
                },
                {
                    ImageView,
                    id = "btnHomeSearchUser",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginRight = "4dp"
                },
                {
                    ImageView,
                    id = "btnHomeSearch",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginRight = "4dp"
                },
                {
                    ImageView,
                    id = "btnHomeMore",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginRight = "4dp"
                }
            },
            {
                LinearLayout,
                id = "homeTopBarSearchUser",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#FFFFFF",
                gravity = "center_vertical",
                orientation = "horizontal",
                visibility = 8,
                {
                    EditText,
                    id = "homeSearchUserInput",
                    layout_width = "fill",
                    layout_height = "wrap",
                    layout_weight = "1",
                    hint = "Cari pengguna...",
                    textSize = "16sp",
                    singleLine = true,
                    imeOptions = 3,
                    layout_marginLeft = "16dp"
                },
                {
                    ImageView,
                    id = "btnHomeCloseSearchUser",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginRight = "4dp"
                }
            },
            {
                LinearLayout,
                id = "homeTopBarSearch",
                layout_width = "fill",
                layout_height = "wrap",
                backgroundColor = "#FFFFFF",
                orientation = "vertical",
                visibility = 8,
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "60dp",
                    gravity = "center_vertical",
                    orientation = "horizontal",
                    {
                        EditText,
                        id = "homeSearchInput",
                        layout_width = "fill",
                        layout_height = "wrap",
                        layout_weight = "1",
                        hint = "Cari obrolan...",
                        textSize = "16sp",
                        singleLine = true,
                        imeOptions = 3,
                        layout_marginLeft = "16dp"
                    },
                    {
                        ImageView,
                        id = "btnHomeCloseSearch",
                        layout_width = "48dp",
                        layout_height = "48dp",
                        padding = "8dp",
                        layout_marginRight = "4dp"
                    }
                },
                {
                    LinearLayout,
                    id = "homeSearchNavContainer",
                    layout_width = "fill",
                    layout_height = "48dp",
                    gravity = "center_vertical",
                    orientation = "horizontal",
                    backgroundColor = "#F0F0F0",
                    visibility = 8,
                    {
                        ImageView,
                        id = "btnHomePrevSearch",
                        layout_width = "48dp",
                        layout_height = "48dp",
                        padding = "8dp",
                        layout_marginLeft = "8dp"
                    },
                    {
                        TextView,
                        id = "tvHomeSearchStatus",
                        layout_width = "fill",
                        layout_height = "wrap",
                        layout_weight = "1",
                        gravity = "center",
                        text = "",
                        textColor = "#888888",
                        textSize = "14sp"
                    },
                    {
                        ImageView,
                        id = "btnHomeNextSearch",
                        layout_width = "48dp",
                        layout_height = "48dp",
                        padding = "8dp",
                        layout_marginRight = "8dp"
                    }
                }
            },
            {
                LinearLayout,
                id = "homeTopBarSelection",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#00897B",
                gravity = "center_vertical",
                orientation = "horizontal",
                visibility = 8,
                {
                    ImageView,
                    id = "btnHomeCloseSelection",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginLeft = "4dp",
                    contentDescription = "Batalkan Pemilihan"
                },
                {
                    TextView,
                    id = "tvHomeSelectionCount",
                    text = "0",
                    textSize = "22sp",
                    textColor = "#FFFFFF",
                    layout_marginLeft = "16dp",
                    layout_weight = "1"
                },
                {
                    ImageView,
                    id = "btnHomeDeselectAll",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginRight = "4dp",
                    contentDescription = "Batalkan Pilihan"
                },
                {
                    ImageView,
                    id = "btnHomeSelectAll",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginRight = "4dp",
                    contentDescription = "Pilih Semua"
                }
            },
            {
                ScrollView,
                id = "homeScrollView",
                layout_width = "fill",
                layout_height = "fill",
                fillViewport = "true",
                {
                    LinearLayout,
                    id = "chatListContainer",
                    orientation = "vertical",
                    layout_width = "fill",
                    layout_height = "wrap",
                    paddingTop = "8dp",
                    paddingBottom = "80dp"
                }
            }
        },
        {
            ImageView,
            id = "btnNewChat",
            layout_width = "64dp",
            layout_height = "64dp",
            layout_gravity = "bottom|right",
            layout_margin = "24dp",
            padding = "16dp"
        },
        {
            LinearLayout,
            id = "homeBottomSelectionBar",
            layout_width = "fill",
            layout_height = "wrap",
            layout_gravity = "bottom",
            orientation = "horizontal",
            gravity = "center",
            padding = "8dp",
            backgroundColor = "#F0F0F0",
            visibility = 8,
            {
                ImageView,
                id = "btnHomeDeleteSelection",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                contentDescription = "Hapus Obrolan"
            }
        }
    },
    {
        LinearLayout,
        id = "contactScreen",
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "fill",
        visibility = 8,
        backgroundColor = "#FFFFFF",
        {
            FrameLayout,
            layout_width = "fill",
            layout_height = "wrap",
            {
                LinearLayout,
                id = "contactTopBarNormal",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#075E54",
                gravity = "center_vertical",
                orientation = "horizontal",
                {
                    ImageView,
                    id = "btnBackContact",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginLeft = "4dp"
                },
                {
                    TextView,
                    text = "Pilih Kontak",
                    textSize = "20sp",
                    textColor = "#FFFFFF",
                    layout_marginLeft = "12dp",
                    layout_weight = "1"
                },
                {
                    ImageView,
                    id = "btnContactSearch",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginRight = "4dp"
                }
            },
            {
                LinearLayout,
                id = "contactTopBarSearch",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#FFFFFF",
                gravity = "center_vertical",
                orientation = "horizontal",
                visibility = 8,
                {
                    EditText,
                    id = "contactSearchInput",
                    layout_width = "fill",
                    layout_height = "wrap",
                    layout_weight = "1",
                    hint = "Cari kontak...",
                    textSize = "16sp",
                    singleLine = true,
                    imeOptions = 3,
                    layout_marginLeft = "16dp"
                },
                {
                    ImageView,
                    id = "btnContactCloseSearch",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginRight = "4dp"
                }
            }
        },
        {
            ScrollView,
            layout_width = "fill",
            layout_height = "fill",
            fillViewport = "true",
            {
                LinearLayout,
                id = "contactListContainer",
                orientation = "vertical",
                layout_width = "fill",
                layout_height = "wrap",
                paddingTop = "8dp"
            }
        }
    },
    {
        LinearLayout,
        id = "chatScreen",
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "fill",
        visibility = 8,
        {
            FrameLayout,
            layout_width = "fill",
            layout_height = "wrap",
            {
                LinearLayout,
                id = "topBarNormal",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#075E54",
                gravity = "center_vertical",
                orientation = "horizontal",
                {
                    ImageView,
                    id = "btnBackChat",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "10dp",
                    layout_marginLeft = "4dp"
                },
                {
                    LinearLayout,
                    orientation = "vertical",
                    layout_width = "0dp",
                    layout_weight = "1",
                    layout_marginLeft = "8dp",
                    {
                        TextView,
                        id = "titleTexa",
                        text = "Texa Admin",
                        textSize = "18sp",
                        textColor = "#FFFFFF",
                        singleLine = true
                    },
                    {
                        TextView,
                        id = "tvConnectionStatus",
                        text = "Menghubungkan...",
                        textSize = "12sp",
                        textColor = "#B2DFDB",
                        singleLine = true
                    }
                },
                {
                    TextView,
                    id = "btnVoiceSpeed",
                    layout_width = "wrap",
                    layout_height = "48dp",
                    gravity = "center",
                    padding = "8dp",
                    text = "1.0x",
                    textColor = "#FFFFFF",
                    textSize = "16sp",
                    visibility = 8,
                    contentDescription = "Kecepatan suara 1.0 kali"
                },
                {
                    ImageView,
                    id = "btnMore",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginRight = "4dp",
                    contentDescription = "Opsi Lainnya"
                }
            },
            {
                LinearLayout,
                id = "topBarFiltered",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#075E54",
                gravity = "center_vertical",
                orientation = "horizontal",
                visibility = 8,
                {
                    ImageView,
                    id = "btnBackFiltered",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginLeft = "4dp",
                    contentDescription = "Kembali"
                },
                {
                    TextView,
                    id = "tvFilteredTitle",
                    text = "",
                    textSize = "22sp",
                    textColor = "#FFFFFF",
                    layout_marginLeft = "16dp",
                    layout_weight = "1"
                }
            },
            {
                LinearLayout,
                id = "topBarSearch",
                layout_width = "fill",
                layout_height = "wrap",
                backgroundColor = "#FFFFFF",
                orientation = "vertical",
                visibility = 8,
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "60dp",
                    gravity = "center_vertical",
                    orientation = "horizontal",
                    {
                        EditText,
                        id = "searchInput",
                        layout_width = "fill",
                        layout_height = "wrap",
                        layout_weight = "1",
                        hint = "Cari pesan...",
                        textSize = "16sp",
                        singleLine = true,
                        imeOptions = 3,
                        layout_marginLeft = "16dp"
                    },
                    {
                        ImageView,
                        id = "btnCloseSearch",
                        layout_width = "48dp",
                        layout_height = "48dp",
                        padding = "8dp",
                        layout_marginRight = "4dp",
                        contentDescription = "Tutup Pencarian"
                    }
                },
                {
                    LinearLayout,
                    id = "searchNavContainer",
                    layout_width = "fill",
                    layout_height = "48dp",
                    gravity = "center_vertical",
                    orientation = "horizontal",
                    backgroundColor = "#F0F0F0",
                    visibility = 8,
                    {
                        ImageView,
                        id = "btnPrevSearch",
                        layout_width = "48dp",
                        layout_height = "48dp",
                        padding = "8dp",
                        layout_marginLeft = "8dp",
                        contentDescription = "Hasil Sebelumnya"
                    },
                    {
                        TextView,
                        id = "tvSearchStatus",
                        layout_width = "fill",
                        layout_height = "wrap",
                        layout_weight = "1",
                        gravity = "center",
                        text = "",
                        textColor = "#888888",
                        textSize = "14sp"
                    },
                    {
                        ImageView,
                        id = "btnNextSearch",
                        layout_width = "48dp",
                        layout_height = "48dp",
                        padding = "8dp",
                        layout_marginRight = "8dp",
                        contentDescription = "Hasil Berikutnya"
                    }
                }
            },
            {
                LinearLayout,
                id = "topBarSelection",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#00897B",
                gravity = "center_vertical",
                orientation = "horizontal",
                visibility = 8,
                {
                    ImageView,
                    id = "btnCloseSelection",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginLeft = "4dp",
                    contentDescription = "Keluar Pemilihan"
                },
                {
                    TextView,
                    id = "tvSelectionCount",
                    text = "0",
                    textSize = "22sp",
                    textColor = "#FFFFFF",
                    layout_marginLeft = "16dp",
                    layout_weight = "1"
                },
                {
                    ImageView,
                    id = "btnDeselectAll",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginRight = "4dp",
                    contentDescription = "Batalkan Pilihan"
                },
                {
                    ImageView,
                    id = "btnSelectAll",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginRight = "4dp",
                    contentDescription = "Pilih Semua"
                }
            }
        },
        {
            LinearLayout,
            orientation = "vertical",
            layout_width = "fill",
            layout_height = "fill",
            layout_weight = "1",
            {
                LinearLayout,
                id = "pinnedMessageContainer",
                layout_width = "fill",
                layout_height = "wrap",
                backgroundColor = "#FFFFFF",
                visibility = 8,
                orientation = "horizontal",
                gravity = "center_vertical",
                paddingTop = "8dp",
                paddingBottom = "8dp",
                {
                    View,
                    layout_width = "4dp",
                    layout_height = "fill",
                    backgroundColor = "#075E54"
                },
                {
                    LinearLayout,
                    orientation = "vertical",
                    layout_width = "0dp",
                    layout_weight = "1",
                    layout_height = "wrap",
                    paddingLeft = "12dp",
                    {
                        TextView,
                        id = "tvPinnedLabel",
                        text = "Pesan Tersemat",
                        textColor = "#075E54",
                        textSize = "14sp"
                    },
                    {
                        TextView,
                        id = "tvPinnedMessage",
                        textColor = "#555555",
                        textSize = "14sp",
                        singleLine = true,
                        ellipsize = "end"
                    }
                }
            },
            {
                FrameLayout,
                layout_width = "fill",
                layout_height = "fill",
                layout_weight = "1",
                {
                    ScrollView,
                    id = "scrollView",
                    layout_width = "fill",
                    layout_height = "fill",
                    fillViewport = "true",
                    {
                        LinearLayout,
                        id = "chatContainer",
                        orientation = "vertical",
                        layout_width = "fill",
                        layout_height = "wrap",
                        padding = "16dp"
                    }
                },
                {
                    TextView,
                    id = "emptyChatText",
                    text = "Belum ada pesan",
                    layout_width = "wrap",
                    layout_height = "wrap",
                    layout_gravity = "center",
                    textColor = "#888888",
                    textSize = "16sp"
                }
            }
        },
        {
            FrameLayout,
            layout_width = "fill",
            layout_height = "wrap",
            {
                LinearLayout,
                id = "bottomInputBar",
                layout_width = "fill",
                layout_height = "wrap",
                orientation = "horizontal",
                gravity = "bottom",
                padding = "8dp",
                backgroundColor = "#F0F0F0",
                {
                    ImageView,
                    id = "btnAttachment",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginRight = "4dp",
                    contentDescription = "Tambah Lampiran"
                },
                {
                    EditText,
                    id = "messageInput",
                    layout_width = "fill",
                    layout_height = "wrap",
                    layout_weight = "1",
                    hint = "Ketik pesan...",
                    backgroundColor = "#FFFFFF",
                    padding = "12dp",
                    textSize = "16sp",
                    maxLines = 4
                },
                {
                    ImageView,
                    id = "btnDictation",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginLeft = "4dp",
                    contentDescription = "Ketik dengan Suara"
                },
                {
                    ImageView,
                    id = "sendButton",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginLeft = "4dp",
                    contentDescription = "Rekam Suara"
                }
            },
            {
                LinearLayout,
                id = "recordUIBar",
                layout_width = "fill",
                layout_height = "wrap",
                orientation = "horizontal",
                gravity = "center_vertical",
                padding = "8dp",
                backgroundColor = "#F0F0F0",
                visibility = 8,
                {
                    ImageView,
                    id = "btnCancelRecord",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    contentDescription = "Batalkan"
                },
                {
                    TextView,
                    id = "tvRecordTimer",
                    layout_width = "wrap",
                    layout_height = "wrap",
                    layout_weight = "1",
                    gravity = "center",
                    text = "00:00",
                    textColor = "#FF0000",
                    textSize = "16sp"
                },
                {
                    ImageView,
                    id = "btnPauseResumeRecord",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    contentDescription = "Jeda"
                },
                {
                    ImageView,
                    id = "btnReviewRecord",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    contentDescription = "Review",
                    visibility = 8
                },
                {
                    ImageView,
                    id = "btnSendRecord",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    contentDescription = "Kirim Suara"
                }
            }
        },
        {
            LinearLayout,
            id = "bottomSelectionBar",
            layout_width = "fill",
            layout_height = "wrap",
            orientation = "horizontal",
            gravity = "center",
            padding = "8dp",
            backgroundColor = "#F0F0F0",
            visibility = 8,
            {
                ImageView,
                id = "btnCopySelection",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                layout_marginRight = "8dp",
                contentDescription = "Salin"
            },
            {
                ImageView,
                id = "btnTranslateSelection",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                layout_marginLeft = "8dp",
                layout_marginRight = "8dp",
                contentDescription = "Terjemahkan"
            },
            {
                ImageView,
                id = "btnStarSelection",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                layout_marginLeft = "8dp",
                layout_marginRight = "8dp",
                contentDescription = "Bintangi"
            },
            {
                ImageView,
                id = "btnPinSelection",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                layout_marginLeft = "8dp",
                layout_marginRight = "8dp",
                contentDescription = "Sematkan"
            },
            {
                ImageView,
                id = "btnDeleteSelection",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                layout_marginLeft = "8dp",
                contentDescription = "Hapus"
            },
            {
                ImageView,
                id = "btnDownloadSelection",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                layout_marginLeft = "8dp",
                contentDescription = "Unduh"
            }
        }
    }
}

local views = {}
local contentView = loadlayout(layout, views)

views.btnVoiceSpeed.setTypeface(Typeface.DEFAULT_BOLD)
views.btnVoiceSpeed.setText(string.format("%.1fx", voice_playback_speed))
views.btnVoiceSpeed.setContentDescription("Kecepatan suara " .. string.format("%.1fx", voice_playback_speed))
views.btnVoiceSpeed.onClick = function(v)
    if voice_playback_speed == 1.0 then
        voice_playback_speed = 1.5
    elseif voice_playback_speed == 1.5 then
        voice_playback_speed = 2.0
    else
        voice_playback_speed = 1.0
    end
    
    saveTransConfig()
    
    local speedText = string.format("%.1fx", voice_playback_speed)
    views.btnVoiceSpeed.setText(speedText)
    views.btnVoiceSpeed.setContentDescription("Kecepatan suara " .. speedText)
    
    if chatMediaPlayer and chatMediaPlayer.isPlaying() and Build.VERSION.SDK_INT >= 23 then
        pcall(function()
            chatMediaPlayer.setPlaybackParams(chatMediaPlayer.getPlaybackParams().setSpeed(voice_playback_speed))
        end)
    end
end

views.btnMore.setContentDescription("Opsi Lainnya")
views.btnCloseSearch.setContentDescription("Tutup Pencarian")
views.btnPrevSearch.setContentDescription("Hasil Sebelumnya")
views.btnNextSearch.setContentDescription("Hasil Berikutnya")
views.btnCloseSelection.setContentDescription("Batalkan Pemilihan")
views.btnBackFiltered.setContentDescription("Kembali")
views.btnCopySelection.setContentDescription("Salin")
views.btnTranslateSelection.setContentDescription("Terjemahkan")
views.btnStarSelection.setContentDescription("Bintangi")
views.btnPinSelection.setContentDescription("Sematkan")
views.btnDeleteSelection.setContentDescription("Hapus")
views.btnDictation.setContentDescription("Ketik dengan Suara")
views.sendButton.setContentDescription("Rekam Suara")
views.btnCancelRecord.setContentDescription("Batalkan")
views.btnPauseResumeRecord.setContentDescription("Jeda")
views.btnReviewRecord.setContentDescription("Review")
views.btnSendRecord.setContentDescription("Kirim Suara")

views.btnHomeSearchUser.setContentDescription("Cari Pengguna")
views.btnHomeCloseSearchUser.setContentDescription("Tutup Pencarian Pengguna")
views.btnHomeSearch.setContentDescription("Cari Obrolan")
views.btnHomeMore.setContentDescription("Opsi Lainnya")
views.btnNewChat.setContentDescription("Obrolan Baru")
views.btnBackChat.setContentDescription("Kembali")
views.btnHomeCloseSearch.setContentDescription("Tutup Pencarian")
views.btnHomePrevSearch.setContentDescription("Hasil Sebelumnya")
views.btnHomeNextSearch.setContentDescription("Hasil Berikutnya")

views.titleTexa.setTypeface(Typeface.DEFAULT_BOLD)
views.tvFilteredTitle.setTypeface(Typeface.DEFAULT_BOLD)
views.emptyChatText.setTypeface(Typeface.defaultFromStyle(Typeface.ITALIC))
views.tvSearchStatus.setTypeface(Typeface.DEFAULT_BOLD)
views.tvSelectionCount.setTypeface(Typeface.DEFAULT_BOLD)
views.tvHomeSelectionCount.setTypeface(Typeface.DEFAULT_BOLD)
views.tvPinnedLabel.setTypeface(Typeface.DEFAULT_BOLD)

local function createEmojiBitmap(emoji, size, textSize, x, y)
    local bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    local canvas = Canvas(bmp)
    local paint = Paint()
    paint.setTextSize(textSize)
    paint.setAntiAlias(true)
    canvas.drawText(emoji, x, y, paint)
    return bmp
end

local function getProfileBitmap(b64, fallbackEmoji)
    if b64 and b64 ~= "" then
        local s, bmp = pcall(function()
            import "android.util.Base64"
            import "android.graphics.BitmapFactory"
            local cleanB64 = b64:match("base64,(.*)") or b64
            local decodedString = Base64.decode(cleanB64, Base64.DEFAULT)
            return BitmapFactory.decodeByteArray(decodedString, 0, #decodedString)
        end)
        if s and bmp then return bmp end
    end
    return createEmojiBitmap(fallbackEmoji, 150, 100, 25, 110)
end

local bmpStar = createEmojiBitmap("★", 100, 60, 20, 75)
local bmpUnstar = createEmojiBitmap("☆", 100, 60, 20, 75)
local bmpPin = createEmojiBitmap("📌", 100, 60, 20, 75)
local bmpUnpin = createEmojiBitmap("📍", 100, 60, 20, 75)

local starIndicator = BitmapDrawable(ctx.getResources(), createEmojiBitmap("★", 50, 40, 5, 40))
local pinIndicator = BitmapDrawable(ctx.getResources(), createEmojiBitmap("📌", 50, 40, 5, 40))

local bmpSend = createEmojiBitmap("豆", 100, 70, 15, 75)
local bmpMic = createEmojiBitmap("🎤", 100, 70, 15, 75)
local bmpDictation = createEmojiBitmap("🗣", 100, 70, 15, 75)
local bmpDictationStop = createEmojiBitmap("⏹", 100, 70, 25, 75)
local bmpCancel = createEmojiBitmap("✖", 100, 70, 25, 75)
local bmpPause = createEmojiBitmap("⏸", 100, 70, 25, 75)
local bmpPlay = createEmojiBitmap("▶", 100, 70, 25, 75)

views.btnAttachment.setImageBitmap(createEmojiBitmap("📎", 100, 70, 25, 75))
views.btnDictation.setImageBitmap(bmpDictation)
views.sendButton.setImageBitmap(bmpMic)
views.btnCancelRecord.setImageBitmap(bmpCancel)
views.btnPauseResumeRecord.setImageBitmap(bmpPause)
views.btnReviewRecord.setImageBitmap(bmpPlay)
views.btnSendRecord.setImageBitmap(bmpSend)
views.btnMore.setImageBitmap(createEmojiBitmap("站ｮ", 100, 70, 35, 75))
views.btnCloseSearch.setImageBitmap(createEmojiBitmap("X", 100, 70, 30, 75))
views.btnPrevSearch.setImageBitmap(createEmojiBitmap("▲", 100, 50, 25, 70))
views.btnNextSearch.setImageBitmap(createEmojiBitmap("▼", 100, 50, 25, 70))

views.btnCloseSelection.setImageBitmap(createEmojiBitmap("X", 100, 70, 30, 75))
views.btnDeselectAll.setImageBitmap(createEmojiBitmap("☐", 100, 70, 25, 75))
views.btnSelectAll.setImageBitmap(createEmojiBitmap("☑", 100, 70, 25, 75))
views.btnBackFiltered.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
views.btnCopySelection.setImageBitmap(createEmojiBitmap("📋", 100, 60, 20, 75))
views.btnTranslateSelection.setImageBitmap(createEmojiBitmap("🌐", 100, 60, 20, 75))
views.btnStarSelection.setImageBitmap(bmpStar)
views.btnPinSelection.setImageBitmap(bmpPin)
views.btnDeleteSelection.setImageBitmap(createEmojiBitmap("🗑", 100, 60, 20, 75))
views.btnDownloadSelection.setImageBitmap(createEmojiBitmap("⬇", 100, 60, 20, 75))

views.btnHomeCloseSelection.setImageBitmap(createEmojiBitmap("X", 100, 70, 30, 75))
views.btnHomeDeselectAll.setImageBitmap(createEmojiBitmap("☐", 100, 70, 25, 75))
views.btnHomeSelectAll.setImageBitmap(createEmojiBitmap("☑", 100, 70, 25, 75))
views.btnHomeDeleteSelection.setImageBitmap(createEmojiBitmap("🗑", 100, 60, 20, 75))

views.btnHomeSearchUser.setImageBitmap(createEmojiBitmap("👤", 100, 60, 20, 75))
views.btnHomeCloseSearchUser.setImageBitmap(createEmojiBitmap("X", 100, 70, 30, 75))
views.btnHomeSearch.setImageBitmap(createEmojiBitmap("🔍", 100, 60, 20, 75))
views.btnHomeMore.setImageBitmap(createEmojiBitmap("站ｮ", 100, 70, 35, 75))
views.btnNewChat.setImageBitmap(createEmojiBitmap("💬", 150, 100, 25, 110))
views.btnBackChat.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
views.btnHomeCloseSearch.setImageBitmap(createEmojiBitmap("X", 100, 70, 30, 75))
views.btnHomePrevSearch.setImageBitmap(createEmojiBitmap("▲", 100, 50, 25, 70))
views.btnHomeNextSearch.setImageBitmap(createEmojiBitmap("▼", 100, 50, 25, 70))

views.sendButton.setEnabled(true)
views.sendButton.setAlpha(1.0)

views.btnPrevSearch.setEnabled(false)
views.btnPrevSearch.setAlpha(0.5)
views.btnNextSearch.setEnabled(false)
views.btnNextSearch.setAlpha(0.5)

local function updateHomeSelectionUI()
    local count = #selectedHomeViews
    if count == 0 then
        isHomeSelectionMode = false
        views.homeTopBarSelection.setVisibility(8)
        views.homeBottomSelectionBar.setVisibility(8)
        views.homeTopBarNormal.setVisibility(0)
        views.btnNewChat.setVisibility(0)
        
        for i = 0, views.chatListContainer.getChildCount() - 1 do
            local v = views.chatListContainer.getChildAt(i)
            v.setBackgroundColor(0x00000000)
            local currentDesc = tostring(v.getContentDescription() or "")
            local newDesc = string.gsub(currentDesc, "^Dipilih, ", "")
            v.setContentDescription(newDesc)
        end
    else
        views.tvHomeSelectionCount.setText(tostring(count))
    end
end

local function toggleHomeSelection(v)
    local foundIdx = -1
    for i, view in ipairs(selectedHomeViews) do
        if view == v then
            foundIdx = i
            break
        end
    end
    
    if foundIdx > 0 then
        table.remove(selectedHomeViews, foundIdx)
        v.setBackgroundColor(0x00000000)
        local currentDesc = tostring(v.getContentDescription() or "")
        local newDesc = string.gsub(currentDesc, "^Dipilih, ", "")
        v.setContentDescription(newDesc)
    else
        table.insert(selectedHomeViews, v)
        v.setBackgroundColor(0xFF90CAF9)
        local desc = tostring(v.getContentDescription() or "")
        if not string.find(desc, "^Dipilih, ") then
            v.setContentDescription("Dipilih, " .. desc)
        end
    end
    
    updateHomeSelectionUI()
end

views.btnHomeCloseSelection.onClick = function()
    selectedHomeViews = {}
    updateHomeSelectionUI()
end

views.btnHomeDeselectAll.onClick = function()
    for _, v in ipairs(selectedHomeViews) do
        v.setBackgroundColor(0x00000000)
        local currentDesc = tostring(v.getContentDescription() or "")
        local newDesc = string.gsub(currentDesc, "^Dipilih, ", "")
        v.setContentDescription(newDesc)
    end
    selectedHomeViews = {}
    updateHomeSelectionUI()
end

views.btnHomeSelectAll.onClick = function()
    selectedHomeViews = {}
    for i = 0, views.chatListContainer.getChildCount() - 1 do
        local v = views.chatListContainer.getChildAt(i)
        if v.getVisibility() == 0 then
            table.insert(selectedHomeViews, v)
            v.setBackgroundColor(0xFF90CAF9)
            local desc = tostring(v.getContentDescription() or "")
            if not string.find(desc, "^Dipilih, ") then
                v.setContentDescription("Dipilih, " .. desc)
            end
        end
    end
    updateHomeSelectionUI()
end

views.btnHomeDeleteSelection.onClick = function()
    local count = #selectedHomeViews
    if count > 0 then
        local builder = AlertDialog.Builder(ctx, 5)
        builder.setMessage("Hapus " .. count .. " obrolan yang dipilih? Semua pesan akan ikut terhapus.")
        builder.setPositiveButton("Hapus", DialogInterface.OnClickListener{
            onClick = function()
                for _, v in ipairs(selectedHomeViews) do
                    local chat_id = v.getTag()
                    local path = chat_id == "admin" and file_path_admin or file_path_local
                    
                    local f = io.open(path, "r")
                    if f then
                        local content = f:read("*a")
                        f:close()
                        local s, root = pcall(function() return JSONObject(content) end)
                        if s and root.has("messages") then
                            local arr = root.getJSONArray("messages")
                            for i = 0, arr.length() - 1 do
                                local item = arr.getJSONObject(i)
                                if item.has("audio_path") then
                                    pcall(function() File(item.getString("audio_path")).delete() end)
                                end
                            end
                        end
                    end
                    
                    local root = JSONObject()
                    if chat_id == "admin" then
                        root.put("last_update_id", admin_last_update_id)
                    else
                        root.put("last_update_id", 0)
                    end
                    root.put("chat_visible", false)
                    root.put("messages", JSONArray())
                    local fw = io.open(path, "w")
                    if fw then
                        fw:write(root.toString())
                        fw:close()
                    end
                    
                    if current_chat_id == chat_id then
                        chat_history.messages = {}
                        pinnedStack = {}
                        views.chatContainer.removeAllViews()
                    end
                end
                
                selectedHomeViews = {}
                updateHomeSelectionUI()
                if refreshHomeChatList then refreshHomeChatList() end
                
                triggerAccessibilityAnnouncement("Obrolan dihapus")
            end
        })
        builder.setNegativeButton("Batal", nil)
        
        local confirmDialog = builder.create()
        local dWindow = confirmDialog.getWindow()
        if Build.VERSION.SDK_INT >= 22 then
            dWindow.setType(2032)
        else
            dWindow.setType(2003)
        end
        confirmDialog.show()
    end
end

refreshHomeChatList = function()
    views.chatListContainer.removeAllViews()
    
    local chat_sessions = {}
    
    local function readLastMessage(path, id, name, emoji)
        local f = io.open(path, "r")
        local is_visible = false
        local text = "Belum ada pesan"
        local ts = 0
        
        if f then
            local content = f:read("*a")
            f:close()
            local s, root = pcall(function() return JSONObject(content) end)
            if s then
                if root.has("chat_visible") then
                    is_visible = root.getBoolean("chat_visible")
                else
                    if root.has("messages") and root.getJSONArray("messages").length() > 0 then
                        is_visible = true
                    end
                end
                
                if root.has("messages") then
                    local arr = root.getJSONArray("messages")
                    if arr.length() > 0 then
                        local lastItem = arr.getJSONObject(arr.length() - 1)
                        text = lastItem.getString("text")
                        ts = lastItem.has("timestamp") and lastItem.getLong("timestamp") or 0
                    end
                end
            end
        end
        
        if is_visible then
            table.insert(chat_sessions, {id = id, name = name, emoji = emoji, text = text, timestamp = ts})
        end
    end
    
    readLastMessage(file_path_admin, "admin", "Texa Admin", "🤖")
    readLastMessage(file_path_local, "local", "Catatan Pribadi", "📝")
    
    pcall(function()
        import "java.io.File"
        local d = File(dir_path)
        if d.exists() and d.isDirectory() then
            local files = d.listFiles()
            if files then
                for i = 0, #files - 1 do
                    local fName = files[i].getName()
                    if fName:match("^chat_(.+)%.json$") then
                        local uid = fName:match("^chat_(.+)%.json$")
                        local cached = contacts_cache[uid]
                        local dName = "Pengguna Anonim"
                        if cached then
                            if cached.name ~= "" then dName = cached.name
                            elseif cached.username ~= "" then dName = cached.username end
                        else
                            syncContactInfo(uid, function()
                                if refreshHomeChatList then refreshHomeChatList() end
                            end)
                        end
                        readLastMessage(files[i].getAbsolutePath(), uid, dName, "👤")
                    end
                end
            end
        end
    end)
    
    table.sort(chat_sessions, function(a, b) return a.timestamp > b.timestamp end)
    
    if #chat_sessions > 0 then
        for _, session in ipairs(chat_sessions) do
            local displaySnippet = session.text
            if string.len(displaySnippet) > 40 then
                displaySnippet = string.sub(displaySnippet, 1, 40) .. "..."
            end
            local timeStr = session.timestamp > 0 and os.date("%H:%M", session.timestamp) or ""
            
            local chatItem = LinearLayout(ctx)
            chatItem.setOrientation(0)
            chatItem.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
            chatItem.setPadding(32, 32, 32, 32)
            chatItem.setGravity(16)
            chatItem.setTag(session.id)
            
            local descText = session.name
            if session.timestamp > 0 then
                descText = descText .. ". Pesan terakhir: " .. session.text .. ". Pada jam " .. timeStr
            else
                descText = descText .. ". " .. session.text
            end
            chatItem.setContentDescription(descText)
            
            local iconView = ImageView(ctx)
            if session.id ~= "admin" and session.id ~= "local" and contacts_cache[session.id] and contacts_cache[session.id].profilePicture ~= "" then
                iconView.setImageBitmap(getProfileBitmap(contacts_cache[session.id].profilePicture, "👤"))
            else
                iconView.setImageBitmap(createEmojiBitmap(session.emoji, 100, 70, 20, 75))
            end
            iconView.setLayoutParams(LinearLayout.LayoutParams(120, 120))
            if Build.VERSION.SDK_INT >= 16 then
                iconView.setImportantForAccessibility(2)
            end
            
            local textLayout = LinearLayout(ctx)
            textLayout.setOrientation(1)
            textLayout.setLayoutParams(LinearLayout.LayoutParams(-1, -2, 1))
            textLayout.setPadding(32, 0, 0, 0)
            
            local nameLayout = LinearLayout(ctx)
            nameLayout.setOrientation(0)
            nameLayout.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
            
            local nameView = TextView(ctx)
            nameView.setText(session.name)
            nameView.setTextSize(18)
            nameView.setTextColor(0xFF000000)
            nameView.setTypeface(Typeface.DEFAULT_BOLD)
            nameView.setLayoutParams(LinearLayout.LayoutParams(-2, -2, 1))
            if Build.VERSION.SDK_INT >= 16 then
                nameView.setImportantForAccessibility(2)
            end
            
            local timeView = TextView(ctx)
            timeView.setText(timeStr)
            timeView.setTextSize(12)
            timeView.setTextColor(0xFF888888)
            if Build.VERSION.SDK_INT >= 16 then
                timeView.setImportantForAccessibility(2)
            end
            
            nameLayout.addView(nameView)
            nameLayout.addView(timeView)
            
            local snippetView = TextView(ctx)
            snippetView.setText(displaySnippet)
            snippetView.setTextSize(14)
            snippetView.setTextColor(0xFF555555)
            snippetView.setMaxLines(1)
            snippetView.setPadding(0, 8, 0, 0)
            if session.timestamp == 0 then
                snippetView.setTypeface(Typeface.defaultFromStyle(Typeface.ITALIC))
            end
            if Build.VERSION.SDK_INT >= 16 then
                snippetView.setImportantForAccessibility(2)
            end
            
            textLayout.addView(nameLayout)
            textLayout.addView(snippetView)
            
            chatItem.addView(iconView)
            chatItem.addView(textLayout)
            
            chatItem.onClick = function(v)
                if isHomeSelectionMode then
                    toggleHomeSelection(v)
                else
                    current_chat_id = session.id
                    loadHistory()
                    views.homeScreen.setVisibility(8)
                    views.chatScreen.setVisibility(0)
                end
            end
            
            chatItem.onLongClick = function(v)
                if not isHomeSelectionMode then
                    if views.homeTopBarSearch.getVisibility() == 0 then
                        views.btnHomeCloseSearch.performClick()
                    end
                    
                    isHomeSelectionMode = true
                    selectedHomeViews = {}
                    
                    views.homeTopBarNormal.setVisibility(8)
                    views.homeTopBarSearch.setVisibility(8)
                    views.homeSearchNavContainer.setVisibility(8)
                    
                    views.homeTopBarSelection.setVisibility(0)
                    views.homeBottomSelectionBar.setVisibility(0)
                    views.btnNewChat.setVisibility(8)
                    
                    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
                    imm.hideSoftInputFromWindow(views.homeSearchInput.getWindowToken(), 0)
                    
                    toggleHomeSelection(v)
                end
                return true
            end
            
            views.chatListContainer.addView(chatItem)
        end
    else
        local emptyView = TextView(ctx)
        emptyView.setText("Belum ada obrolan")
        emptyView.setTextSize(16)
        emptyView.setTextColor(0xFF888888)
        emptyView.setGravity(17)
        emptyView.setPadding(0, 100, 0, 0)
        emptyView.setLayoutParams(LinearLayout.LayoutParams(-1, -1))
        views.chatListContainer.addView(emptyView)
    end
end

local function addContactView(id, name, emoji, username, container)
    local contactView = LinearLayout(ctx)
    contactView.setOrientation(0)
    contactView.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
    contactView.setPadding(32, 32, 32, 32)
    contactView.setGravity(16)
    
    local iconView = ImageView(ctx)
    if id ~= "admin" and id ~= "local" and contacts_cache[id] and contacts_cache[id].profilePicture ~= "" then
        iconView.setImageBitmap(getProfileBitmap(contacts_cache[id].profilePicture, emoji))
    else
        iconView.setImageBitmap(createEmojiBitmap(emoji, 100, 70, 20, 75))
    end
    iconView.setLayoutParams(LinearLayout.LayoutParams(120, 120))
    
    local textLayout = LinearLayout(ctx)
    textLayout.setOrientation(1)
    textLayout.setLayoutParams(LinearLayout.LayoutParams(-1, -2, 1))
    textLayout.setPadding(32, 0, 0, 0)
    
    local nameView = TextView(ctx)
    nameView.setText(name)
    nameView.setTextSize(18)
    nameView.setTextColor(0xFF000000)
    
    textLayout.addView(nameView)
    
    if username and username ~= "" then
        local userView = TextView(ctx)
        userView.setText("@" .. username)
        userView.setTextSize(14)
        userView.setTextColor(0xFF888888)
        textLayout.addView(userView)
        contactView.setContentDescription(name .. ", username " .. username)
    else
        contactView.setContentDescription(name)
    end
    
    contactView.addView(iconView)
    contactView.addView(textLayout)
    
    contactView.onClick = function()
        current_chat_id = id
        loadHistory()
        views.homeScreen.setVisibility(8)
        views.contactScreen.setVisibility(8)
        views.chatScreen.setVisibility(0)
        
        if views.homeTopBarSearchUser.getVisibility() == 0 then
            views.btnHomeCloseSearchUser.performClick()
        end
        if views.contactTopBarSearch.getVisibility() == 0 then
            views.btnContactCloseSearch.performClick()
        end
    end
    
    container.addView(contactView)
end

views.btnBackContact.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
views.btnBackContact.setContentDescription("Kembali")
views.btnContactSearch.setImageBitmap(createEmojiBitmap("🔍", 100, 60, 20, 75))
views.btnContactSearch.setContentDescription("Cari Kontak")
views.btnContactCloseSearch.setImageBitmap(createEmojiBitmap("X", 100, 70, 30, 75))
views.btnContactCloseSearch.setContentDescription("Tutup Pencarian Kontak")

views.btnBackContact.onClick = function()
    views.contactScreen.setVisibility(8)
    views.homeScreen.setVisibility(0)
    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
    imm.hideSoftInputFromWindow(views.contactSearchInput.getWindowToken(), 0)
end

views.btnContactSearch.onClick = function()
    views.contactTopBarNormal.setVisibility(8)
    views.contactTopBarSearch.setVisibility(0)
    views.contactSearchInput.requestFocus()
    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
    imm.showSoftInput(views.contactSearchInput, 0)
end

views.btnContactCloseSearch.onClick = function()
    views.contactTopBarSearch.setVisibility(8)
    views.contactTopBarNormal.setVisibility(0)
    views.contactSearchInput.setText("")
    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
    imm.hideSoftInputFromWindow(views.contactSearchInput.getWindowToken(), 0)
    
    views.contactListContainer.removeAllViews()
    addContactView("admin", "Texa Admin", "🤖", nil, views.contactListContainer)
    addContactView("local", "Catatan Pribadi", "📝", nil, views.contactListContainer)
end

views.btnNewChat.onClick = function()
    views.homeScreen.setVisibility(8)
    views.contactScreen.setVisibility(0)
    
    views.contactTopBarSearch.setVisibility(8)
    views.contactTopBarNormal.setVisibility(0)
    views.contactSearchInput.setText("")
    
    views.contactListContainer.removeAllViews()
    addContactView("admin", "Texa Admin", "🤖", nil, views.contactListContainer)
    addContactView("local", "Catatan Pribadi", "📝", nil, views.contactListContainer)
end

views.btnHomeSearchUser.onClick = function()
    views.homeTopBarNormal.setVisibility(8)
    views.homeTopBarSearchUser.setVisibility(0)
    views.homeSearchUserInput.requestFocus()
    
    views.chatListContainer.removeAllViews()
    addContactView("admin", "Texa Admin", "🤖", nil, views.chatListContainer)
    addContactView("local", "Catatan Pribadi", "📝", nil, views.chatListContainer)
    
    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
    imm.showSoftInput(views.homeSearchUserInput, 0)
end

views.btnHomeCloseSearchUser.onClick = function()
    views.homeTopBarSearchUser.setVisibility(8)
    views.homeTopBarNormal.setVisibility(0)
    views.homeSearchUserInput.setText("")
    
    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
    imm.hideSoftInputFromWindow(views.homeSearchUserInput.getWindowToken(), 0)
    
    if refreshHomeChatList then refreshHomeChatList() end
end

local function performUserSearch(query, containerView)
    if query == "" then
        containerView.removeAllViews()
        addContactView("admin", "Texa Admin", "🤖", nil, containerView)
        addContactView("local", "Catatan Pribadi", "📝", nil, containerView)
        return
    end
    
    containerView.removeAllViews()
    local loadingView = TextView(ctx)
    loadingView.setText("Mencari pengguna...")
    loadingView.setTextSize(16)
    loadingView.setTextColor(0xFF888888)
    loadingView.setGravity(17)
    loadingView.setPadding(0, 100, 0, 0)
    loadingView.setLayoutParams(LinearLayout.LayoutParams(-1, -1))
    containerView.addView(loadingView)
    
    task(function(t_query, t_token)
        require "import"
        import "java.net.URL"
        import "java.net.URLEncoder"
        import "java.io.BufferedReader"
        import "java.io.InputStreamReader"
        local code = -1
        local resBody = ""
        pcall(function()
            local urlStr = "http://botspark.de1.octavia.id:25701/api/users/search?q=" .. URLEncoder.encode(t_query, "UTF-8")
            local url = URL(urlStr)
            local conn = url.openConnection()
            conn.setConnectTimeout(10000)
            conn.setReadTimeout(10000)
            conn.setRequestMethod("GET")
            conn.setRequestProperty("Authorization", "Bearer " .. t_token)
            code = conn.getResponseCode()
            local isStream = (code >= 200 and code < 300) and conn.getInputStream() or conn.getErrorStream()
            if isStream then
                local br = BufferedReader(InputStreamReader(isStream))
                local line = br.readLine()
                while line ~= nil do
                    resBody = resBody .. line
                    line = br.readLine()
                end
                br.close()
            end
        end)
        return code, resBody
    end, query, auth_token, function(code, body)
        containerView.removeAllViews()
        local s, data = pcall(function() import "org.json.JSONObject" return JSONObject(body) end)
        if code == 200 and s then
            local resultsArray = data.optJSONArray("results")
            local serverMsg = data.optString("message", "Pencarian selesai")
            
            if resultsArray and resultsArray.length() > 0 then
                for i = 0, resultsArray.length() - 1 do
                    local userItem = resultsArray.getJSONObject(i)
                    local uId = userItem.optString("id", "")
                    local uName = userItem.optString("name", "")
                    local uUser = userItem.optString("username", "")
                    if uId ~= "" then
                        addContactView(uId, uName, "👤", uUser, containerView)
                    end
                end
                triggerAccessibilityAnnouncement(serverMsg)
            else
                local emptyView = TextView(ctx)
                emptyView.setText(serverMsg)
                emptyView.setTextSize(16)
                emptyView.setTextColor(0xFF888888)
                emptyView.setGravity(17)
                emptyView.setPadding(0, 100, 0, 0)
                emptyView.setLayoutParams(LinearLayout.LayoutParams(-1, -1))
                containerView.addView(emptyView)
                triggerAccessibilityAnnouncement(serverMsg)
            end
        else
            local errMsg = "Terjadi kesalahan jaringan"
            if s and data.has("error") then errMsg = data.getString("error") end
            
            local errView = TextView(ctx)
            errView.setText(errMsg)
            errView.setTextSize(16)
            errView.setTextColor(0xFFFF0000)
            errView.setGravity(17)
            errView.setPadding(0, 100, 0, 0)
            errView.setLayoutParams(LinearLayout.LayoutParams(-1, -1))
            containerView.addView(errView)
            triggerAccessibilityAnnouncement(errMsg)
        end
    end)
end

views.homeSearchUserInput.setOnEditorActionListener(TextView.OnEditorActionListener{
    onEditorAction = function(v, actionId, event)
        if actionId == 3 or (event and event.getKeyCode() == 66 and event.getAction() == 0) then
            local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
            imm.hideSoftInputFromWindow(v.getWindowToken(), 0)
            local query = tostring(v.getText())
            performUserSearch(query, views.chatListContainer)
            return true
        end
        return false
    end
})

views.contactSearchInput.setOnEditorActionListener(TextView.OnEditorActionListener{
    onEditorAction = function(v, actionId, event)
        if actionId == 3 or (event and event.getKeyCode() == 66 and event.getAction() == 0) then
            local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
            imm.hideSoftInputFromWindow(v.getWindowToken(), 0)
            local query = tostring(v.getText())
            performUserSearch(query, views.contactListContainer)
            return true
        end
        return false
    end
})

views.btnBackChat.onClick = function()
    pcall(function()
        if chatMediaPlayer then
            if chatMediaPlayer.isPlaying() then chatMediaPlayer.stop() end
            chatMediaPlayer.release()
            chatMediaPlayer = nil
            activeVoiceView = nil
            views.btnVoiceSpeed.setVisibility(8)
        end
    end)
    views.chatScreen.setVisibility(8)
    views.homeScreen.setVisibility(0)
    
    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
    imm.hideSoftInputFromWindow(views.messageInput.getWindowToken(), 0)
end

views.messageInput.addTextChangedListener(TextWatcher{
    onTextChanged = function(s, start, before, count)
        if tostring(s):len() > 0 then
            views.sendButton.setImageBitmap(bmpSend)
            views.sendButton.setContentDescription("Kirim")
        else
            views.sendButton.setImageBitmap(bmpMic)
            views.sendButton.setContentDescription("Rekam Suara")
        end
    end
})

local handler = Handler(Looper.getMainLooper())

local function startMessagePolling()
    if message_poll_timer then return end
    message_poll_timer = Runnable{
        run = function()
            if auth_token and auth_token ~= "" then
                task(function(t_token)
                    require "import"
                    import "java.net.URL"
                    import "java.io.BufferedReader"
                    import "java.io.InputStreamReader"
                    local code = -1
                    local resBody = ""
                    pcall(function()
                        local url = URL("http://botspark.de1.octavia.id:25701/api/chat/receive")
                        local conn = url.openConnection()
                        conn.setConnectTimeout(5000)
                        conn.setReadTimeout(5000)
                        conn.setRequestMethod("GET")
                        conn.setRequestProperty("Authorization", "Bearer " .. t_token)
                        code = conn.getResponseCode()
                        if code == 200 then
                            local br = BufferedReader(InputStreamReader(conn.getInputStream()))
                            local line = br.readLine()
                            while line ~= nil do
                                resBody = resBody .. line
                                line = br.readLine()
                            end
                            br.close()
                        end
                    end)
                    return code, resBody
                end, auth_token, function(code, body)
                    if code == 200 and body ~= "" then
                        local s, data = pcall(function() import "org.json.JSONObject" return JSONObject(body) end)
                        if s and data.has("messages") then
                            local arr = data.getJSONArray("messages")
                            local new_messages_by_sender = {}
                            
                            for i = 0, arr.length() - 1 do
                                local msg = arr.getJSONObject(i)
                                local senderId = msg.optString("senderId", "")
                                if senderId ~= "" then
                                    if not new_messages_by_sender[senderId] then
                                        new_messages_by_sender[senderId] = {}
                                    end
                                    table.insert(new_messages_by_sender[senderId], {
                                        text = msg.optString("text", ""),
                                        audio_path = msg.has("audio_path") and msg.isNull("audio_path") == false and msg.getString("audio_path") or nil,
                                        media_path = msg.has("media_path") and msg.isNull("media_path") == false and msg.getString("media_path") or nil,
                                        media_type = msg.has("media_type") and msg.isNull("media_type") == false and msg.getInt("media_type") or nil,
                                        timestamp = msg.optLong("timestamp", os.time())
                                    })
                                end
                            end
                            
                            local require_home_refresh = false
                            for senderId, msgs in pairs(new_messages_by_sender) do
                                local chat_file = dir_path .. "/chat_" .. senderId .. ".json"
                                local chat_data = { messages = {} }
                                
                                local f = io.open(chat_file, "r")
                                if f then
                                    local content = f:read("*a")
                                    f:close()
                                    pcall(function()
                                        local root = JSONObject(content)
                                        if root.has("messages") then
                                            local old_arr = root.getJSONArray("messages")
                                            for j = 0, old_arr.length() - 1 do
                                                local item = old_arr.getJSONObject(j)
                                                table.insert(chat_data.messages, {
                                                    text = item.getString("text"),
                                                    is_me = item.getBoolean("is_me"),
                                                    is_starred = item.optBoolean("is_starred", false),
                                                    is_pinned = item.optBoolean("is_pinned", false),
                                                    audio_path = item.has("audio_path") and item.getString("audio_path") or nil,
                                                    media_path = item.has("media_path") and item.getString("media_path") or nil,
                                                    media_type = item.has("media_type") and item.getInt("media_type") or nil,
                                                    timestamp = item.optLong("timestamp", os.time())
                                                })
                                            end
                                        end
                                    end)
                                end
                                
                                for _, m in ipairs(msgs) do
                                    table.insert(chat_data.messages, {
                                        text = m.text,
                                        is_me = false,
                                        is_starred = false,
                                        is_pinned = false,
                                        audio_path = m.audio_path,
                                        media_path = m.media_path,
                                        media_type = m.media_type,
                                        timestamp = m.timestamp
                                    })
                                    
                                    if current_chat_id == senderId then
                                        appendMessage(m.text, false, false, false, true, m.audio_path, m.timestamp, m.media_path, m.media_type)
                                    end
                                end
                                
                                local root = JSONObject()
                                root.put("chat_visible", true)
                                local json_arr = JSONArray()
                                for _, m in ipairs(chat_data.messages) do
                                    local item = JSONObject()
                                    item.put("text", m.text)
                                    item.put("is_me", m.is_me)
                                    item.put("is_starred", m.is_starred)
                                    item.put("is_pinned", m.is_pinned)
                                    if m.audio_path then item.put("audio_path", m.audio_path) end
                                    if m.media_path then
                                        item.put("media_path", m.media_path)
                                        item.put("media_type", m.media_type)
                                    end
                                    item.put("timestamp", m.timestamp)
                                    json_arr.put(item)
                                end
                                root.put("messages", json_arr)
                                
                                local fw = io.open(chat_file, "w")
                                if fw then
                                    fw:write(root.toString())
                                    fw:close()
                                end
                                require_home_refresh = true
                                
                                if not contacts_cache[senderId] then
                                    syncContactInfo(senderId, nil)
                                end
                            end
                            
                            if require_home_refresh and refreshHomeChatList then
                                refreshHomeChatList()
                            end
                        end
                    end
                end)
            end
            if message_poll_timer then
                handler.postDelayed(message_poll_timer, 3000)
            end
        end
    }
    handler.postDelayed(message_poll_timer, 3000)
end

startMessagePolling()

local function setConnectionState(online)
    handler.post(Runnable{
        run = function()
            if online then
                views.tvConnectionStatus.setText("Online")
            else
                views.tvConnectionStatus.setText("Menghubungkan...")
            end
        end
    })
end

local function refreshPinnedDisplay()
    if currentFilterMode ~= "normal" then
        views.pinnedMessageContainer.setVisibility(8)
        return
    end
    if #pinnedStack > 0 then
        if currentPinnedDisplayIndex < 1 or currentPinnedDisplayIndex > #pinnedStack then
            currentPinnedDisplayIndex = #pinnedStack
        end
        local msgIdx = pinnedStack[currentPinnedDisplayIndex]
        local msg = chat_history.messages[msgIdx]
        if msg then
            views.tvPinnedMessage.setText(msg.text)
            views.pinnedMessageContainer.setVisibility(0)
            return
        end
    end
    views.pinnedMessageContainer.setVisibility(8)
end

local function applyFilter()
    if currentFilterMode == "normal" then
        views.topBarFiltered.setVisibility(8)
        views.topBarNormal.setVisibility(0)
        views.bottomInputBar.setVisibility(0)
        refreshPinnedDisplay()
        for i = 0, views.chatContainer.getChildCount() - 1 do
            views.chatContainer.getChildAt(i).setVisibility(0)
        end
        views.emptyChatText.setText("Belum ada pesan")
        if views.chatContainer.getChildCount() == 0 then
            views.emptyChatText.setVisibility(0)
        else
            views.emptyChatText.setVisibility(8)
        end
    else
        views.topBarNormal.setVisibility(8)
        views.topBarSearch.setVisibility(8)
        views.searchNavContainer.setVisibility(8)
        views.bottomInputBar.setVisibility(8)
        views.pinnedMessageContainer.setVisibility(8)
        views.topBarFiltered.setVisibility(0)
        
        local count = 0
        for i = 0, views.chatContainer.getChildCount() - 1 do
            local msg = chat_history.messages[i + 1]
            local v = views.chatContainer.getChildAt(i)
            local show = false
            if currentFilterMode == "starred" and msg.is_starred then show = true end
            if currentFilterMode == "pinned" and msg.is_pinned then show = true end
            
            if show then
                v.setVisibility(0)
                count = count + 1
            else
                v.setVisibility(8)
            end
        end
        
        if currentFilterMode == "starred" then
            views.tvFilteredTitle.setText("Pesan Berbintang (" .. count .. ")")
        else
            views.tvFilteredTitle.setText("Pesan Tersemat (" .. count .. ")")
        end
        
        if count == 0 then
            views.emptyChatText.setText("Tidak ada pesan " .. (currentFilterMode == "starred" and "berbintang" or "tersemat"))
            views.emptyChatText.setVisibility(0)
        else
            views.emptyChatText.setVisibility(8)
        end
    end
end

views.btnBackFiltered.onClick = function()
    currentFilterMode = "normal"
    applyFilter()
end

local function saveHistory()
    local root = JSONObject()
    if current_chat_id == "admin" then
        root.put("last_update_id", admin_last_update_id)
    else
        root.put("last_update_id", 0)
    end
    
    root.put("chat_visible", true)
    
    local arr = JSONArray()
    for i, msg in ipairs(chat_history.messages) do
        local item = JSONObject()
        item.put("text", msg.text)
        item.put("is_me", msg.is_me)
        item.put("is_starred", msg.is_starred or false)
        item.put("is_pinned", msg.is_pinned or false)
        if msg.audio_path then
            item.put("audio_path", msg.audio_path)
        end
        if msg.media_path then
            item.put("media_path", msg.media_path)
            item.put("media_type", msg.media_type)
        end
        if msg.timestamp then
            item.put("timestamp", msg.timestamp)
        end
        arr.put(item)
    end
    root.put("messages", arr)
    
    local active_file = ""
    if current_chat_id == "admin" then
        active_file = file_path_admin
    elseif current_chat_id == "local" then
        active_file = file_path_local
    else
        active_file = dir_path .. "/chat_" .. current_chat_id .. ".json"
    end
    
    local f = io.open(active_file, "w")
    if f then
        f:write(root.toString())
        f:close()
    end
    if refreshHomeChatList then refreshHomeChatList() end
end

local function updateMessageDescription(tv)
    local idx = views.chatContainer.indexOfChild(tv) + 1
    local msg = chat_history.messages[idx]
    if not msg then return end
    
    local desc = tostring(tv.getText())
    
    if msg.is_starred then desc = desc .. ", pesan dibintangi" end
    if msg.is_pinned then desc = desc .. ", pesan disematkan" end
    
    if isSelectionMode then
        local isSelected = false
        for _, v in ipairs(selectedViews) do
            if v == tv then
                isSelected = true
                break
            end
        end
        if isSelected then
            desc = "Dipilih, " .. desc
        else
            desc = "Tidak dipilih, " .. desc
        end
    end
    tv.setContentDescription(desc)
end

local function updateSelectionUI()
    local count = #selectedViews
    if count == 0 then
        isSelectionMode = false
        views.topBarSelection.setVisibility(8)
        views.bottomSelectionBar.setVisibility(8)
        
        if currentFilterMode == "normal" then
            views.topBarNormal.setVisibility(0)
            views.bottomInputBar.setVisibility(0)
        else
            applyFilter()
        end
        
        for i = 0, views.chatContainer.getChildCount() - 1 do
            local v = views.chatContainer.getChildAt(i)
            local isMe = v.getTag() == "me"
            v.setBackgroundColor(isMe and 0xFFDCF8C6 or 0xFFFFFFFF)
            updateMessageDescription(v)
        end
    else
        views.tvSelectionCount.setText(tostring(count))
        
        local isAllStarred = true
        local isAllPinned = true
        local hasVoice = false
        local hasDownloadable = false
        for _, v in ipairs(selectedViews) do
            local idx = views.chatContainer.indexOfChild(v) + 1
            local msg = chat_history.messages[idx]
            if not msg.is_starred then isAllStarred = false end
            if not msg.is_pinned then isAllPinned = false end
            if msg.audio_path and (string.find(msg.text, "▶") or string.find(msg.text, "⏸")) then hasVoice = true end
            if msg.audio_path or msg.media_path then hasDownloadable = true end
        end
        
        if hasVoice then
            views.btnCopySelection.setVisibility(8)
            views.btnTranslateSelection.setVisibility(8)
        else
            views.btnCopySelection.setVisibility(0)
            views.btnTranslateSelection.setVisibility(0)
        end
        
        if hasDownloadable then
            views.btnDownloadSelection.setVisibility(0)
        else
            views.btnDownloadSelection.setVisibility(8)
        end
        
        if isAllStarred then
            views.btnStarSelection.setImageBitmap(bmpUnstar)
            views.btnStarSelection.setContentDescription("Hapus Bintang")
        else
            views.btnStarSelection.setImageBitmap(bmpStar)
            views.btnStarSelection.setContentDescription("Bintangi")
        end
        
        if isAllPinned then
            views.btnPinSelection.setImageBitmap(bmpUnpin)
            views.btnPinSelection.setContentDescription("Lepas Sematan")
        else
            views.btnPinSelection.setImageBitmap(bmpPin)
            views.btnPinSelection.setContentDescription("Sematkan")
        end
    end
end

local function toggleSelection(tv)
    local foundIdx = -1
    for i, v in ipairs(selectedViews) do
        if v == tv then
            foundIdx = i
            break
        end
    end
    
    local isMe = tv.getTag() == "me"
    
    if foundIdx > 0 then
        table.remove(selectedViews, foundIdx)
        tv.setBackgroundColor(isMe and 0xFFDCF8C6 or 0xFFFFFFFF)
    else
        table.insert(selectedViews, tv)
        tv.setBackgroundColor(0xFF90CAF9)
    end
    
    updateMessageDescription(tv)
    updateSelectionUI()
end

views.btnCloseSelection.onClick = function()
    selectedViews = {}
    updateSelectionUI()
end

views.btnDeselectAll.onClick = function()
    for _, tv in ipairs(selectedViews) do
        local isMe = tv.getTag() == "me"
        tv.setBackgroundColor(isMe and 0xFFDCF8C6 or 0xFFFFFFFF)
    end
    selectedViews = {}
    updateSelectionUI()
    for i = 0, views.chatContainer.getChildCount() - 1 do
        local child = views.chatContainer.getChildAt(i)
        updateMessageDescription(child)
    end
end

views.btnSelectAll.onClick = function()
    selectedViews = {}
    for i = 0, views.chatContainer.getChildCount() - 1 do
        local tv = views.chatContainer.getChildAt(i)
        if tv.getVisibility() == 0 then
            table.insert(selectedViews, tv)
            tv.setBackgroundColor(0xFF90CAF9)
            updateMessageDescription(tv)
        end
    end
    updateSelectionUI()
end

views.btnCopySelection.onClick = function()
    if #selectedViews > 0 then
        local sortedViews = {}
        for i, v in ipairs(selectedViews) do
            table.insert(sortedViews, {view = v, index = views.chatContainer.indexOfChild(v)})
        end
        table.sort(sortedViews, function(a, b) return a.index < b.index end)
        
        local copyText = ""
        for i, item in ipairs(sortedViews) do
            if i > 1 then copyText = copyText .. "\n" end
            copyText = copyText .. tostring(item.view.getText())
        end
        
        local clipboard = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
        local clip = ClipData.newPlainText("Obrolan", copyText)
        clipboard.setPrimaryClip(clip)
        
        triggerAccessibilityAnnouncement("Pesan disalin")
        
        selectedViews = {}
        updateSelectionUI()
    end
end

local function executeTranslation(text, tvResult)
    tvResult.setText("Menerjemahkan...")
    local from = lang_codes[trans_source_lang] or "auto"
    local to = lang_codes[trans_target_lang] or "id"
    
    task(function(t_text, t_from, t_to)
        require "import"
        import "java.net.URL"
        import "java.net.URLEncoder"
        import "java.io.BufferedReader"
        import "java.io.InputStreamReader"

        local safe_text = URLEncoder.encode(t_text, "UTF-8")
        local urlStr = "https://translate.google.com/m?sl=" .. t_from .. "&tl=" .. t_to .. "&q=" .. safe_text
        local res = ""
        pcall(function()
            local url = URL(urlStr)
            local conn = url.openConnection()
            conn.setRequestMethod("GET")
            conn.setRequestProperty("User-Agent", "Mozilla/5.0")
            conn.setConnectTimeout(10000)
            conn.setReadTimeout(10000)
            if conn.getResponseCode() == 200 then
                local br = BufferedReader(InputStreamReader(conn.getInputStream()))
                local line = br.readLine()
                while line ~= nil do
                    res = res .. line .. "\n"
                    line = br.readLine()
                end
                br.close()
            end
        end)
        return res
    end, text, from, to, function(body)
        if body and body ~= "" then
            local result = body:match('class="result%-container">([^<]*)</div>')
            if result then
                result = result:gsub("&#39;", "'"):gsub("&quot;", '"'):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
                tvResult.setText(result)
            else
                tvResult.setText("Gagal mengambil teks terjemahan.")
            end
        else
            tvResult.setText("Masalah koneksi atau respon kosong.")
        end
    end)
end

local function showLanguageList(titleText, callback)
    local langLayout = LinearLayout(ctx)
    langLayout.setOrientation(1)
    langLayout.setPadding(40, 40, 40, 40)
    langLayout.setBackgroundColor(0xFFFFFFFF)
    
    local tvTitle = TextView(ctx)
    tvTitle.setText(titleText)
    tvTitle.setTextSize(20)
    tvTitle.setGravity(17)
    tvTitle.setTextColor(0xFF000000)
    tvTitle.setPadding(0, 0, 0, 20)
    langLayout.addView(tvTitle)
    
    local etSearch = EditText(ctx)
    etSearch.setHint("Cari bahasa...")
    etSearch.setTextColor(0xFF000000)
    etSearch.setHintTextColor(0xFF888888)
    langLayout.addView(etSearch)
    
    local sv = ScrollView(ctx)
    local listLayout = LinearLayout(ctx)
    listLayout.setOrientation(1)
    sv.addView(listLayout)
    langLayout.addView(sv, LinearLayout.LayoutParams(-1, 0, 1))
    
    local builder = AlertDialog.Builder(ctx, 5)
    builder.setView(langLayout)
    local dlgList = builder.create()
    
    local function updateList(filter)
        listLayout.removeAllViews()
        
        if not is_languages_loaded then
            local tvWait = TextView(ctx)
            tvWait.setText("Memuat data dari server...\nMohon tunggu atau periksa jaringan Anda.")
            tvWait.setTextColor(0xFF888888)
            tvWait.setPadding(32, 32, 32, 32)
            tvWait.setGravity(17)
            listLayout.addView(tvWait)
            return
        end
        
        for _, lang in ipairs(languages) do
            if not filter or filter == "" or lang:lower():find(filter:lower()) then
                local btn = Button(ctx)
                btn.setText(lang)
                btn.setTextColor(0xFF333333)
                btn.setBackgroundColor(0x00000000)
                btn.setAllCaps(false)
                btn.setPadding(32, 32, 32, 32)
                btn.setGravity(19)
                btn.setOnClickListener(function()
                    callback(lang)
                    triggerAccessibilityAnnouncement(lang .. " dipilih")
                    dlgList.dismiss()
                end)
                listLayout.addView(btn)
            end
        end
    end
    
    updateList("")
    etSearch.addTextChangedListener(TextWatcher{
        onTextChanged = function(s, start, before, count)
            updateList(tostring(s))
        end,
        beforeTextChanged = function() end,
        afterTextChanged = function() end
    })
    
    local btnBack = Button(ctx)
    btnBack.setText("Kembali")
    btnBack.setTextColor(0xFF00897B)
    btnBack.setBackgroundColor(0x00000000)
    btnBack.setAllCaps(false)
    btnBack.setOnClickListener(function()
        dlgList.dismiss()
    end)
    langLayout.addView(btnBack)
    
    local w = dlgList.getWindow()
    if Build.VERSION.SDK_INT >= 22 then
        w.setType(2032)
    else
        w.setType(2003)
    end
    dlgList.show()
end

local function showTranslationDialog(textToTranslate)
    local transLayout = {
        LinearLayout,
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "fill",
        backgroundColor = "#F5F5F5",
        {
            LinearLayout,
            layout_width = "fill",
            layout_height = "60dp",
            backgroundColor = "#075E54",
            gravity = "center_vertical",
            orientation = "horizontal",
            {
                ImageView,
                id = "btnBackTrans",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "12dp",
                layout_marginLeft = "4dp"
            },
            {
                TextView,
                id = "tvTransTitle",
                text = "Penerjemah",
                textSize = "20sp",
                textColor = "#FFFFFF",
                layout_marginLeft = "12dp",
                layout_weight = "1"
            },
            {
                ImageView,
                id = "btnCopyTrans",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "12dp",
                layout_marginRight = "4dp"
            }
        },
        {
            LinearLayout,
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#FFFFFF",
            orientation = "horizontal",
            gravity = "center_vertical",
            padding = "8dp",
            {
                LinearLayout,
                id = "btnSourceLang",
                layout_weight = "1",
                layout_width = "0dp",
                gravity = "center",
                padding = "12dp",
                focusable = true,
                clickable = true,
                {
                    TextView,
                    id = "tvSourceLang",
                    text = trans_source_lang,
                    textColor = "#00897B",
                    textSize = "16sp"
                }
            },
            {
                LinearLayout,
                id = "btnSwapLang",
                layout_width = "wrap",
                layout_height = "wrap",
                gravity = "center",
                padding = "12dp",
                focusable = true,
                clickable = true,
                {
                    ImageView,
                    id = "ivSwapLang",
                    layout_width = "24dp",
                    layout_height = "24dp"
                }
            },
            {
                LinearLayout,
                id = "btnTargetLang",
                layout_weight = "1",
                layout_width = "0dp",
                gravity = "center",
                padding = "12dp",
                focusable = true,
                clickable = true,
                {
                    TextView,
                    id = "tvTargetLang",
                    text = trans_target_lang,
                    textColor = "#00897B",
                    textSize = "16sp"
                }
            }
        },
        {
            ScrollView,
            layout_width = "fill",
            layout_height = "fill",
            layout_weight = "1",
            fillViewport = "true",
            {
                LinearLayout,
                orientation = "vertical",
                layout_width = "fill",
                layout_height = "wrap",
                padding = "16dp",
                {
                    LinearLayout,
                    orientation = "vertical",
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    {
                        TextView,
                        id = "tvTransResult",
                        text = "",
                        textSize = "18sp",
                        textColor = "#333333",
                        textIsSelectable = true,
                        padding = "16dp"
                    }
                }
            }
        }
    }
    
    local tViews = {}
    local tContentView = loadlayout(transLayout, tViews)
    
    if Build.VERSION.SDK_INT >= 16 then
        tViews.tvSourceLang.setImportantForAccessibility(2)
        tViews.tvTargetLang.setImportantForAccessibility(2)
        tViews.ivSwapLang.setImportantForAccessibility(2)
    end
    tViews.ivSwapLang.setImageBitmap(createEmojiBitmap("⇄", 100, 50, 20, 60))
    
    tViews.tvTransTitle.setTypeface(Typeface.DEFAULT_BOLD)
    tViews.btnBackTrans.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
    tViews.btnCopyTrans.setImageBitmap(createEmojiBitmap("📋", 100, 60, 20, 75))
    
    local function updateLangDescriptions()
        tViews.btnSourceLang.setContentDescription("Sumber bahasa " .. string.lower(trans_source_lang) .. ", klik untuk mengubah")
        tViews.btnTargetLang.setContentDescription("Tujuan bahasa " .. string.lower(trans_target_lang) .. ", klik untuk mengubah")
        tViews.btnSwapLang.setContentDescription("Tukar bahasa")
        tViews.btnBackTrans.setContentDescription("Kembali")
        tViews.btnCopyTrans.setContentDescription("Salin hasil terjemahan")
    end
    
    updateLangDescriptions()
    
    local tDialog = Dialog(ctx)
    tDialog.requestWindowFeature(1)
    tDialog.setContentView(tContentView)
    
    local w = tDialog.getWindow()
    if Build.VERSION.SDK_INT >= 22 then
        w.setType(2032)
    else
        w.setType(2003)
    end
    w.setBackgroundDrawable(ColorDrawable(0xffF5F5F5))
    w.setLayout(-1, -1)
    
    tViews.btnSourceLang.onClick = function()
        showLanguageList("Sumber Bahasa", function(lang)
            trans_source_lang = lang
            tViews.tvSourceLang.setText(lang)
            saveTransConfig()
            updateLangDescriptions()
            executeTranslation(textToTranslate, tViews.tvTransResult)
        end)
    end
    
    tViews.btnTargetLang.onClick = function()
        showLanguageList("Tujuan Bahasa", function(lang)
            trans_target_lang = lang
            tViews.tvTargetLang.setText(lang)
            saveTransConfig()
            updateLangDescriptions()
            executeTranslation(textToTranslate, tViews.tvTransResult)
        end)
    end
    
    tViews.btnSwapLang.onClick = function()
        local temp = trans_source_lang
        trans_source_lang = trans_target_lang
        trans_target_lang = temp
        tViews.tvSourceLang.setText(trans_source_lang)
        tViews.tvTargetLang.setText(trans_target_lang)
        saveTransConfig()
        updateLangDescriptions()
        executeTranslation(textToTranslate, tViews.tvTransResult)
    end
    
    tViews.btnCopyTrans.onClick = function()
        local resText = tostring(tViews.tvTransResult.getText())
        if resText ~= "" and resText ~= "Menerjemahkan..." then
            local clipboard = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
            local clip = ClipData.newPlainText("Terjemahan", resText)
            clipboard.setPrimaryClip(clip)
            triggerAccessibilityAnnouncement("Terjemahan disalin")
        end
    end
    
    tViews.btnBackTrans.onClick = function()
        tDialog.dismiss()
    end
    
    tDialog.show()
    executeTranslation(textToTranslate, tViews.tvTransResult)
end
views.btnTranslateSelection.onClick = function()
    if #selectedViews > 0 then
        local sortedViews = {}
        for i, v in ipairs(selectedViews) do
            table.insert(sortedViews, {view = v, index = views.chatContainer.indexOfChild(v)})
        end
        table.sort(sortedViews, function(a, b) return a.index < b.index end)
        
        local textToTranslate = ""
        for i, item in ipairs(sortedViews) do
            if i > 1 then textToTranslate = textToTranslate .. "\n" end
            local msg = chat_history.messages[item.index + 1]
            if msg then
                textToTranslate = textToTranslate .. msg.text
            end
        end
        
        selectedViews = {}
        updateSelectionUI()
        
        showTranslationDialog(textToTranslate)
    end
end

views.btnStarSelection.onClick = function()
    if #selectedViews > 0 then
        local isAllStarred = true
        for _, v in ipairs(selectedViews) do
            local idx = views.chatContainer.indexOfChild(v) + 1
            if not chat_history.messages[idx].is_starred then
                isAllStarred = false
                break
            end
        end
        
        local newState = not isAllStarred
        for _, v in ipairs(selectedViews) do
            local idx = views.chatContainer.indexOfChild(v) + 1
            local msg = chat_history.messages[idx]
            msg.is_starred = newState
            
            local leftD = msg.is_pinned and pinIndicator or nil
            local rightD = msg.is_starred and starIndicator or nil
            v.setCompoundDrawablesWithIntrinsicBounds(leftD, nil, rightD, nil)
            updateMessageDescription(v)
        end
        saveHistory()
        selectedViews = {}
        updateSelectionUI()
    end
end

views.btnPinSelection.onClick = function()
    if #selectedViews > 0 then
        local tv = selectedViews[1]
        local idx = views.chatContainer.indexOfChild(tv) + 1
        local msg = chat_history.messages[idx]
        
        if msg.is_pinned then
            msg.is_pinned = false
            for i, pIdx in ipairs(pinnedStack) do
                if pIdx == idx then
                    table.remove(pinnedStack, i)
                    break
                end
            end
            currentPinnedDisplayIndex = #pinnedStack
            refreshPinnedDisplay()
            
            local leftD = msg.is_pinned and pinIndicator or nil
            local rightD = msg.is_starred and starIndicator or nil
            tv.setCompoundDrawablesWithIntrinsicBounds(leftD, nil, rightD, nil)
        else
            msg.is_pinned = true
            table.insert(pinnedStack, idx)
            currentPinnedDisplayIndex = #pinnedStack
            refreshPinnedDisplay()
            
            local leftD = msg.is_pinned and pinIndicator or nil
            local rightD = msg.is_starred and starIndicator or nil
            tv.setCompoundDrawablesWithIntrinsicBounds(leftD, nil, rightD, nil)
        end
        
        updateMessageDescription(tv)
        saveHistory()
        selectedViews = {}
        updateSelectionUI()
    end
end

views.btnDownloadSelection.onClick = function()
    if #selectedViews > 0 then
        local count = 0
        for _, v in ipairs(selectedViews) do
            local idx = views.chatContainer.indexOfChild(v) + 1
            local msg = chat_history.messages[idx]
            if msg.audio_path then
                downloadMediaToTexaFolder(msg.audio_path)
                count = count + 1
            end
            if msg.media_path then
                downloadMediaToTexaFolder(msg.media_path)
                count = count + 1
            end
        end
        if count == 0 then
            triggerAccessibilityAnnouncement("Tidak ada file media yang dapat diunduh pada pesan yang dipilih")
        end
        selectedViews = {}
        updateSelectionUI()
    end
end

views.btnDeleteSelection.onClick = function()
    local count = #selectedViews
    if count > 0 then
        local builder = AlertDialog.Builder(ctx, 5)
        builder.setMessage("Hapus " .. count .. " pesan yang dipilih?")
        builder.setPositiveButton("Hapus", DialogInterface.OnClickListener{
            onClick = function()
                local indexesToRemove = {}
                for _, v in ipairs(selectedViews) do
                    table.insert(indexesToRemove, views.chatContainer.indexOfChild(v) + 1)
                end
                table.sort(indexesToRemove, function(a, b) return a > b end)
                
                for _, idx in ipairs(indexesToRemove) do
                    local msg = chat_history.messages[idx]
                    if msg.audio_path then
                        pcall(function() File(msg.audio_path).delete() end)
                    end
                    views.chatContainer.removeViewAt(idx - 1)
                    table.remove(chat_history.messages, idx)
                end
                
                pinnedStack = {}
                for i, msg in ipairs(chat_history.messages) do
                    if msg.is_pinned then
                        table.insert(pinnedStack, i)
                    end
                end
                currentPinnedDisplayIndex = #pinnedStack
                refreshPinnedDisplay()
                
                saveHistory()
                
                if currentFilterMode == "normal" and views.chatContainer.getChildCount() == 0 then
                    views.emptyChatText.setVisibility(0)
                end
                
                selectedViews = {}
                updateSelectionUI()
            end
        })
        builder.setNegativeButton("Batal", nil)
        
        local confirmDialog = builder.create()
        local dWindow = confirmDialog.getWindow()
        if Build.VERSION.SDK_INT >= 22 then
            dWindow.setType(2032)
        else
            dWindow.setType(2003)
        end
        confirmDialog.show()
    end
end

views.pinnedMessageContainer.onClick = function()
    if #pinnedStack > 0 then
        local targetMsgIdx = pinnedStack[currentPinnedDisplayIndex]
        local targetView = views.chatContainer.getChildAt(targetMsgIdx - 1)
        if targetView then
            views.scrollView.scrollTo(0, targetView.getTop() - 50)
        end
        currentPinnedDisplayIndex = currentPinnedDisplayIndex - 1
        if currentPinnedDisplayIndex < 1 then
            currentPinnedDisplayIndex = #pinnedStack
        end
        refreshPinnedDisplay()
    end
end

views.pinnedMessageContainer.onLongClick = function()
    if #pinnedStack > 0 then
        local msgIdx = pinnedStack[currentPinnedDisplayIndex]
        chat_history.messages[msgIdx].is_pinned = false
        table.remove(pinnedStack, currentPinnedDisplayIndex)
        currentPinnedDisplayIndex = #pinnedStack
        
        local oldView = views.chatContainer.getChildAt(msgIdx - 1)
        if oldView then
            local msg = chat_history.messages[msgIdx]
            local leftD = msg.is_pinned and pinIndicator or nil
            local rightD = msg.is_starred and starIndicator or nil
            oldView.setCompoundDrawablesWithIntrinsicBounds(leftD, nil, rightD, nil)
            updateMessageDescription(oldView)
        end
        saveHistory()
    end
    refreshPinnedDisplay()
    return true
end

local function updateSearchStatus()
    if #searchResults == 0 then
        views.tvSearchStatus.setText("Tidak ditemukan")
        views.btnPrevSearch.setEnabled(false)
        views.btnPrevSearch.setAlpha(0.5)
        views.btnNextSearch.setEnabled(false)
        views.btnNextSearch.setAlpha(0.5)
    else
        views.tvSearchStatus.setText(currentSearchIndex .. " / " .. #searchResults)
        
        if currentSearchIndex <= 1 then
            views.btnPrevSearch.setEnabled(false)
            views.btnPrevSearch.setAlpha(0.5)
        else
            views.btnPrevSearch.setEnabled(true)
            views.btnPrevSearch.setAlpha(1.0)
        end
        
        if currentSearchIndex >= #searchResults then
            views.btnNextSearch.setEnabled(false)
            views.btnNextSearch.setAlpha(0.5)
        else
            views.btnNextSearch.setEnabled(true)
            views.btnNextSearch.setAlpha(1.0)
        end
        
        for i, v in ipairs(searchResults) do
            local isMe = v.getTag() == "me"
            if i == currentSearchIndex then
                v.setBackgroundColor(0xFF90CAF9)
            else
                v.setBackgroundColor(isMe and 0xFFDCF8C6 or 0xFFFFFFFF)
            end
        end
        
        handler.post(Runnable{
            run = function()
                local targetView = searchResults[currentSearchIndex]
                if targetView then
                    views.scrollView.scrollTo(0, targetView.getTop() - 50)
                end
            end
        })
    end
end

views.searchInput.setOnEditorActionListener(TextView.OnEditorActionListener{
    onEditorAction = function(v, actionId, event)
        if actionId == 3 or (event and event.getKeyCode() == 66 and event.getAction() == 0) then
            local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
            imm.hideSoftInputFromWindow(v.getWindowToken(), 0)
            
            views.searchNavContainer.setVisibility(0)
            
            local query = string.lower(tostring(v.getText()))
            searchResults = {}
            for i = 0, views.chatContainer.getChildCount() - 1 do
                local tv = views.chatContainer.getChildAt(i)
                local text = string.lower(tostring(tv.getText()))
                local isMe = tv.getTag() == "me"
                tv.setBackgroundColor(isMe and 0xFFDCF8C6 or 0xFFFFFFFF)
                
                if query ~= "" and string.find(text, query, 1, true) then
                    table.insert(searchResults, tv)
                end
            end
            
            if query == "" then
                views.tvSearchStatus.setText("")
                views.btnPrevSearch.setEnabled(false)
                views.btnPrevSearch.setAlpha(0.5)
                views.btnNextSearch.setEnabled(false)
                views.btnNextSearch.setAlpha(0.5)
                views.searchNavContainer.setVisibility(8)
            else
                if #searchResults > 0 then
                    currentSearchIndex = #searchResults
                else
                    currentSearchIndex = 0
                end
                updateSearchStatus()
            end
            return true
        end
        return false
    end
})

views.btnPrevSearch.onClick = function()
    if currentSearchIndex > 1 then
        currentSearchIndex = currentSearchIndex - 1
        updateSearchStatus()
    end
end

views.btnNextSearch.onClick = function()
    if currentSearchIndex < #searchResults then
        currentSearchIndex = currentSearchIndex + 1
        updateSearchStatus()
    end
end

views.btnCloseSearch.onClick = function()
    views.topBarSearch.setVisibility(8)
    views.searchNavContainer.setVisibility(8)
    views.topBarNormal.setVisibility(0)
    views.bottomInputBar.setVisibility(0)
    views.searchInput.setText("")
    views.tvSearchStatus.setText("")
    
    for i = 0, views.chatContainer.getChildCount() - 1 do
        local tv = views.chatContainer.getChildAt(i)
        local isMe = tv.getTag() == "me"
        tv.setBackgroundColor(isMe and 0xFFDCF8C6 or 0xFFFFFFFF)
    end
    
    searchResults = {}
    currentSearchIndex = 0
    
    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
    imm.hideSoftInputFromWindow(views.searchInput.getWindowToken(), 0)
end

local homeSearchResults = {}
local currentHomeSearchIndex = 0

local function updateHomeSearchStatus()
    if #homeSearchResults == 0 then
        views.tvHomeSearchStatus.setText("Tidak ditemukan")
        views.btnHomePrevSearch.setEnabled(false)
        views.btnHomePrevSearch.setAlpha(0.5)
        views.btnHomeNextSearch.setEnabled(false)
        views.btnHomeNextSearch.setAlpha(0.5)
    else
        views.tvHomeSearchStatus.setText(currentHomeSearchIndex .. " / " .. #homeSearchResults)
        
        if currentHomeSearchIndex <= 1 then
            views.btnHomePrevSearch.setEnabled(false)
            views.btnHomePrevSearch.setAlpha(0.5)
        else
            views.btnHomePrevSearch.setEnabled(true)
            views.btnHomePrevSearch.setAlpha(1.0)
        end
        
        if currentHomeSearchIndex >= #homeSearchResults then
            views.btnHomeNextSearch.setEnabled(false)
            views.btnHomeNextSearch.setAlpha(0.5)
        else
            views.btnHomeNextSearch.setEnabled(true)
            views.btnHomeNextSearch.setAlpha(1.0)
        end
        
        for i, v in ipairs(homeSearchResults) do
            if i == currentHomeSearchIndex then
                v.setBackgroundColor(0xFF90CAF9)
            else
                v.setBackgroundColor(0x00000000)
            end
        end
        
        handler.post(Runnable{
            run = function()
                local targetView = homeSearchResults[currentHomeSearchIndex]
                if targetView then
                    views.homeScrollView.scrollTo(0, targetView.getTop() - 50)
                end
            end
        })
    end
end

views.btnHomeSearch.onClick = function()
    views.homeTopBarNormal.setVisibility(8)
    views.homeTopBarSearch.setVisibility(0)
    views.homeSearchNavContainer.setVisibility(8)
    views.homeSearchInput.requestFocus()
    views.tvHomeSearchStatus.setText("")
    views.btnHomePrevSearch.setEnabled(false)
    views.btnHomePrevSearch.setAlpha(0.5)
    views.btnHomeNextSearch.setEnabled(false)
    views.btnHomeNextSearch.setAlpha(0.5)
    
    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
    imm.showSoftInput(views.homeSearchInput, 0)
end

views.homeSearchInput.setOnEditorActionListener(TextView.OnEditorActionListener{
    onEditorAction = function(v, actionId, event)
        if actionId == 3 or (event and event.getKeyCode() == 66 and event.getAction() == 0) then
            local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
            imm.hideSoftInputFromWindow(v.getWindowToken(), 0)
            
            views.homeSearchNavContainer.setVisibility(0)
            
            local query = string.lower(tostring(v.getText()))
            homeSearchResults = {}
            for i = 0, views.chatListContainer.getChildCount() - 1 do
                local child = views.chatListContainer.getChildAt(i)
                child.setBackgroundColor(0x00000000)
                
                local contentDesc = tostring(child.getContentDescription() or "")
                local childText = ""
                if contentDesc ~= "" then
                    childText = contentDesc
                else
                    if child.getClass().getSimpleName() == "TextView" then
                        childText = tostring(child.getText())
                    end
                end
                
                if query ~= "" and string.find(string.lower(childText), query, 1, true) then
                    table.insert(homeSearchResults, child)
                end
            end
            
            if query == "" then
                views.tvHomeSearchStatus.setText("")
                views.btnHomePrevSearch.setEnabled(false)
                views.btnHomePrevSearch.setAlpha(0.5)
                views.btnHomeNextSearch.setEnabled(false)
                views.btnHomeNextSearch.setAlpha(0.5)
                views.homeSearchNavContainer.setVisibility(8)
            else
                if #homeSearchResults > 0 then
                    currentHomeSearchIndex = #homeSearchResults
                else
                    currentHomeSearchIndex = 0
                end
                updateHomeSearchStatus()
            end
            return true
        end
        return false
    end
})

views.btnHomePrevSearch.onClick = function()
    if currentHomeSearchIndex > 1 then
        currentHomeSearchIndex = currentHomeSearchIndex - 1
        updateHomeSearchStatus()
    end
end

views.btnHomeNextSearch.onClick = function()
    if currentHomeSearchIndex < #homeSearchResults then
        currentHomeSearchIndex = currentHomeSearchIndex + 1
        updateHomeSearchStatus()
    end
end

views.btnHomeCloseSearch.onClick = function()
    views.homeTopBarSearch.setVisibility(8)
    views.homeSearchNavContainer.setVisibility(8)
    views.homeTopBarNormal.setVisibility(0)
    views.homeSearchInput.setText("")
    views.tvHomeSearchStatus.setText("")
    
    for i = 0, views.chatListContainer.getChildCount() - 1 do
        local child = views.chatListContainer.getChildAt(i)
        child.setBackgroundColor(0x00000000)
    end
    
    homeSearchResults = {}
    currentHomeSearchIndex = 0
    
    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
    imm.hideSoftInputFromWindow(views.homeSearchInput.getWindowToken(), 0)
end

local dialog = Dialog(ctx)
dialog.requestWindowFeature(1)
dialog.setContentView(contentView)

local window = dialog.getWindow()
if Build.VERSION.SDK_INT >= 22 then
    window.setType(2032)
else
    window.setType(2003)
end

window.setBackgroundDrawable(ColorDrawable(0xffE5DDD5))
window.setLayout(-1, -1)
window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)

local function scrollToBottom()
    handler.postDelayed(Runnable{
        run = function()
            views.scrollView.fullScroll(130)
        end
    }, 100)
end

local chatMediaPlayer = nil
local activeVoiceView = nil

local function showMediaViewerDialog(chatMediaList, startIndex)
    local viewerLayout = {
        LinearLayout,
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "fill",
        backgroundColor = "#000000",
        {
            LinearLayout,
            id = "viewerTopBar",
            layout_width = "fill",
            layout_height = "60dp",
            backgroundColor = "#075E54",
            gravity = "center_vertical",
            orientation = "horizontal",
            {
                ImageView,
                id = "btnBackViewer",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "12dp",
                layout_marginLeft = "4dp",
                contentDescription = "Kembali"
            },
            {
                TextView,
                id = "tvViewerTitle",
                text = "Media",
                textSize = "20sp",
                textColor = "#FFFFFF",
                layout_marginLeft = "12dp",
                layout_weight = "1"
            },
            {
                ImageView,
                id = "btnDownloadViewer",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "12dp",
                layout_marginRight = "4dp",
                contentDescription = "Unduh Media"
            }
        },
        {
            FrameLayout,
            id = "viewerContent",
            layout_width = "fill",
            layout_height = "0dp",
            layout_weight = "1",
            {
                ImageView,
                id = "viewerImageView",
                layout_width = "fill",
                layout_height = "fill",
                visibility = 8
            },
            {
                VideoView,
                id = "viewerVideoView",
                layout_width = "fill",
                layout_height = "fill",
                layout_gravity = "center",
                visibility = 8
            }
        },
        {
            LinearLayout,
            id = "viewerBottomBar",
            layout_width = "fill",
            layout_height = "wrap",
            orientation = "vertical",
            backgroundColor = "#222222",
            {
                LinearLayout,
                id = "viewerVideoControls",
                layout_width = "fill",
                layout_height = "wrap",
                orientation = "horizontal",
                gravity = "center_vertical",
                padding = "8dp",
                visibility = 8,
                {
                    ImageView,
                    id = "btnPlayPauseViewer",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    contentDescription = "Putar"
                },
                {
                    TextView,
                    id = "tvVideoProgress",
                    text = "00:00 / 00:00 (0%)",
                    textColor = "#FFFFFF",
                    textSize = "14sp",
                    layout_marginLeft = "8dp"
                }
            },
            {
                LinearLayout,
                layout_width = "fill",
                layout_height = "wrap",
                orientation = "horizontal",
                gravity = "center",
                padding = "8dp",
                {
                    TextView,
                    id = "btnViewerPrev",
                    text = "Sebelumnya",
                    layout_width = "0dp",
                    layout_weight = "1",
                    gravity = "center",
                    padding = "12dp",
                    textColor = "#FFFFFF",
                    clickable = true,
                    focusable = true
                },
                {
                    TextView,
                    id = "btnViewerNext",
                    text = "Berikutnya",
                    layout_width = "0dp",
                    layout_weight = "1",
                    gravity = "center",
                    padding = "12dp",
                    textColor = "#FFFFFF",
                    clickable = true,
                    focusable = true
                }
            }
        }
    }
    
    local vViews = {}
    local vContentView = loadlayout(viewerLayout, vViews)
    vViews.tvViewerTitle.setTypeface(Typeface.DEFAULT_BOLD)
    vViews.btnViewerPrev.setTypeface(Typeface.DEFAULT_BOLD)
    vViews.btnViewerNext.setTypeface(Typeface.DEFAULT_BOLD)
    vViews.btnBackViewer.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
    vViews.btnPlayPauseViewer.setImageBitmap(bmpPause)
    vViews.btnDownloadViewer.setImageBitmap(createEmojiBitmap("⬇", 100, 60, 20, 75))
    vViews.viewerImageView.setScaleType(ImageView.ScaleType.FIT_CENTER)
    
    local vDialog = Dialog(ctx)
    vDialog.requestWindowFeature(1)
    vDialog.setContentView(vContentView)
    local w = vDialog.getWindow()
    if Build.VERSION.SDK_INT >= 22 then w.setType(2032) else w.setType(2003) end
    w.setBackgroundDrawable(ColorDrawable(0xff000000))
    w.setLayout(-1, -1)
    
    local currentIndex = startIndex
    local progressRunnable = nil
    
    local function stopProgressTimer()
        if progressRunnable then
            handler.removeCallbacks(progressRunnable)
            progressRunnable = nil
        end
    end
    
    local function renderCurrentMedia()
        local media = chatMediaList[currentIndex]
        local isVideo = (media.media_type == 3)
        
        local typeTotal = 0
        local typeIndex = 0
        for i, m in ipairs(chatMediaList) do
            if m.media_type == media.media_type then
                typeTotal = typeTotal + 1
                if i == currentIndex then
                    typeIndex = typeTotal
                end
            end
        end
        
        local titleStr = (isVideo and "Video " or "Foto ") .. typeIndex .. " dari " .. typeTotal
        vViews.tvViewerTitle.setText(titleStr)
        triggerAccessibilityAnnouncement(titleStr)
        
        vViews.btnViewerPrev.setTextColor(currentIndex > 1 and 0xFFFFFFFF or 0xFF555555)
        vViews.btnViewerPrev.setClickable(currentIndex > 1)
        vViews.btnViewerNext.setTextColor(currentIndex < #chatMediaList and 0xFFFFFFFF or 0xFF555555)
        vViews.btnViewerNext.setClickable(currentIndex < #chatMediaList)
        
        stopProgressTimer()
        
        if isVideo then
            vViews.viewerImageView.setVisibility(8)
            vViews.viewerVideoControls.setVisibility(0)
            vViews.viewerVideoView.setVisibility(0)
            vViews.viewerVideoView.setVideoPath(media.media_path)
            vViews.btnPlayPauseViewer.setImageBitmap(bmpPause)
            vViews.viewerVideoView.start()
            
            progressRunnable = Runnable{
                run = function()
                    pcall(function()
                        if vViews.viewerVideoView.isPlaying() then
                            local cur = math.floor(vViews.viewerVideoView.getCurrentPosition() / 1000)
                            local dur = math.floor(vViews.viewerVideoView.getDuration() / 1000)
                            if dur > 0 then
                                local pct = math.floor((cur / dur) * 100)
                                vViews.tvVideoProgress.setText(formatTime(cur) .. " / " .. formatTime(dur) .. " (" .. pct .. "%)")
                            end
                        end
                    end)
                    if progressRunnable then
                        handler.postDelayed(progressRunnable, 1000)
                    end
                end
            }
            handler.postDelayed(progressRunnable, 1000)
            
            vViews.viewerVideoView.setOnCompletionListener(MediaPlayer.OnCompletionListener{
                onCompletion = function(mp)
                    vViews.btnPlayPauseViewer.setImageBitmap(bmpPlay)
                end
            })
        else
            vViews.viewerVideoControls.setVisibility(8)
            vViews.viewerVideoView.setVisibility(8)
            pcall(function() if vViews.viewerVideoView.isPlaying() then vViews.viewerVideoView.pause() end end)
            vViews.viewerImageView.setVisibility(0)
            
            pcall(function()
                import "android.graphics.BitmapFactory"
                local bmp = BitmapFactory.decodeFile(media.media_path)
                if bmp then vViews.viewerImageView.setImageBitmap(bmp) end
            end)
        end
    end
    
    vViews.btnPlayPauseViewer.onClick = function()
        pcall(function()
            if vViews.viewerVideoView.isPlaying() then
                vViews.viewerVideoView.pause()
                vViews.btnPlayPauseViewer.setImageBitmap(bmpPlay)
            else
                vViews.viewerVideoView.start()
                vViews.btnPlayPauseViewer.setImageBitmap(bmpPause)
            end
        end)
    end
    
    vViews.btnViewerPrev.onClick = function()
        if currentIndex > 1 then
            currentIndex = currentIndex - 1
            renderCurrentMedia()
        end
    end
    
    vViews.btnViewerNext.onClick = function()
        if currentIndex < #chatMediaList then
            currentIndex = currentIndex + 1
            renderCurrentMedia()
        end
    end
    
    vViews.btnDownloadViewer.onClick = function()
        local mediaItem = chatMediaList[currentIndex]
        if mediaItem and mediaItem.media_path then
            triggerAccessibilityAnnouncement("Memulai unduhan media dari penampil...")
            downloadMediaToTexaFolder(mediaItem.media_path)
        else
            triggerAccessibilityAnnouncement("Gagal mengunduh: File media tidak ditemukan")
        end
    end
    
    vViews.btnBackViewer.onClick = function()
        stopProgressTimer()
        pcall(function() if vViews.viewerVideoView.isPlaying() then vViews.viewerVideoView.pause() end end)
        vDialog.dismiss()
    end
    
    renderCurrentMedia()
    vDialog.show()
end

local function appendMessage(text, is_me, is_starred, is_pinned, save, audio_path, timestamp, media_path, media_type)
    local currentAudioPath = audio_path
    local currentMediaPath = media_path
    local currentMediaType = media_type
    local msgTime = timestamp or os.time()
    local timeStr = os.date("%H.%M", msgTime)
    local status_text = is_me and ("Kirim pada " .. timeStr) or ("Diterima pada " .. timeStr)
    local display_text = text .. "\n" .. status_text
    
    views.emptyChatText.setVisibility(8)
    
    local tv = TextView(ctx)
    tv.setText(display_text)
    tv.setTextSize(16)
    tv.setTextColor(0xFF000000)
    
    local lp = LinearLayout.LayoutParams(-2, -2)
    lp.setMargins(0, 0, 0, 16)
    
    if is_me then
        tv.setBackgroundColor(0xFFDCF8C6)
        lp.gravity = 5
        tv.setTag("me")
    else
        tv.setBackgroundColor(0xFFFFFFFF)
        lp.gravity = 3
        tv.setTag("other")
    end
    
    local leftD = is_pinned and pinIndicator or nil
    local rightD = is_starred and starIndicator or nil
    tv.setCompoundDrawablesWithIntrinsicBounds(leftD, nil, rightD, nil)
    tv.setCompoundDrawablePadding(8)
    
    tv.setPadding(24, 16, 24, 16)
    tv.setLayoutParams(lp)
    
    tv.onLongClick = function(v)
        if not isSelectionMode then
            if views.topBarSearch.getVisibility() == 0 then
                views.btnCloseSearch.performClick()
            end
            
            isSelectionMode = true
            selectedViews = {}
            
            views.topBarNormal.setVisibility(8)
            views.topBarFiltered.setVisibility(8)
            views.topBarSearch.setVisibility(8)
            views.searchNavContainer.setVisibility(8)
            views.bottomInputBar.setVisibility(8)
            
            views.topBarSelection.setVisibility(0)
            views.bottomSelectionBar.setVisibility(0)
            
            local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
            imm.hideSoftInputFromWindow(views.messageInput.getWindowToken(), 0)
            
            for i = 0, views.chatContainer.getChildCount() - 1 do
                local child = views.chatContainer.getChildAt(i)
                updateMessageDescription(child)
            end
            
            toggleSelection(v)
        end
        return true
    end
    
    tv.onClick = function(v)
        if isSelectionMode then
            toggleSelection(v)
        else
            if currentMediaPath then
                local chatMediaList = {}
                local startIndex = 1
                for i, msg in ipairs(chat_history.messages) do
                    if msg.media_path then
                        table.insert(chatMediaList, msg)
                        if msg.media_path == currentMediaPath and msg.timestamp == msgTime then
                            startIndex = #chatMediaList
                        end
                    end
                end
                if #chatMediaList > 0 then
                    showMediaViewerDialog(chatMediaList, startIndex)
                end
            elseif currentAudioPath then
                pcall(function()
                    if chatMediaPlayer then
                        if activeVoiceView == v then
                            if chatMediaPlayer.isPlaying() then
                                chatMediaPlayer.pause()
                                views.btnVoiceSpeed.setVisibility(8)
                            else
                                chatMediaPlayer.start()
                                views.btnVoiceSpeed.setVisibility(0)
                            end
                            return
                        else
                            if chatMediaPlayer.isPlaying() then
                                chatMediaPlayer.stop()
                            end
                            chatMediaPlayer.release()
                            chatMediaPlayer = nil
                            views.btnVoiceSpeed.setVisibility(8)
                        end
                    end
                    
                    import "java.io.File"
                    import "java.io.FileInputStream"
                    local f = File(currentAudioPath)
                    if f.exists() then
                        chatMediaPlayer = MediaPlayer()
                        local fis = FileInputStream(f)
                        chatMediaPlayer.setDataSource(fis.getFD())
                        chatMediaPlayer.setAudioStreamType(3)
                        chatMediaPlayer.prepare()
                        chatMediaPlayer.start()
                        if Build.VERSION.SDK_INT >= 23 then
                            pcall(function()
                                chatMediaPlayer.setPlaybackParams(chatMediaPlayer.getPlaybackParams().setSpeed(voice_playback_speed))
                            end)
                        end
                        fis.close()
                        
                        activeVoiceView = v
                        local speedText = string.format("%.1fx", voice_playback_speed)
                        views.btnVoiceSpeed.setText(speedText)
                        views.btnVoiceSpeed.setVisibility(0)
                        
                        chatMediaPlayer.setOnCompletionListener(MediaPlayer.OnCompletionListener{
                            onCompletion = function(mp)
                                mp.release()
                                chatMediaPlayer = nil
                                activeVoiceView = nil
                                views.btnVoiceSpeed.setVisibility(8)
                            end
                        })
                    else
                        triggerAccessibilityAnnouncement("File suara tidak ditemukan")
                    end
                end)
            end
        end
    end
    
    if save then
        table.insert(chat_history.messages, {text = text, is_me = is_me, is_starred = is_starred, is_pinned = is_pinned, audio_path = currentAudioPath, media_path = currentMediaPath, media_type = currentMediaType, timestamp = msgTime})
        saveHistory()
    end
    
    views.chatContainer.addView(tv)
    updateMessageDescription(tv)
    
    if currentFilterMode ~= "normal" then
        tv.setVisibility(8)
    end
    
    scrollToBottom()
    
    if trans_auto_msg and not currentAudioPath and not currentMediaPath then
        if trans_show_original then
            tv.setText(text .. "\n\n(Menerjemahkan...)\n" .. status_text)
        else
            tv.setText("(Menerjemahkan...)\n" .. status_text)
        end
        updateMessageDescription(tv)
        local from = lang_codes[trans_source_lang] or "auto"
        local to = lang_codes[trans_target_lang] or "id"
        task(function(t_text, t_from, t_to)
            require "import"
            import "java.net.URL"
            import "java.net.URLEncoder"
            import "java.io.BufferedReader"
            import "java.io.InputStreamReader"
            local safe_text = URLEncoder.encode(t_text, "UTF-8")
            local urlStr = "https://translate.google.com/m?sl=" .. t_from .. "&tl=" .. t_to .. "&q=" .. safe_text
            local res = ""
            pcall(function()
                local url = URL(urlStr)
                local conn = url.openConnection()
                conn.setRequestMethod("GET")
                conn.setRequestProperty("User-Agent", "Mozilla/5.0")
                conn.setConnectTimeout(10000)
                conn.setReadTimeout(10000)
                if conn.getResponseCode() == 200 then
                    local br = BufferedReader(InputStreamReader(conn.getInputStream()))
                    local line = br.readLine()
                    while line ~= nil do
                        res = res .. line .. "\n"
                        line = br.readLine()
                    end
                    br.close()
                end
            end)
            return res
        end, text, from, to, function(body)
            if body and body ~= "" then
                local result = body:match('class="result%-container">([^<]*)</div>')
                if result then
                    result = result:gsub("&#39;", "'"):gsub("&quot;", '"'):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
                    if trans_show_original then
                        tv.setText(text .. "\n\n" .. result .. "\n" .. status_text)
                    else
                        tv.setText(result .. "\n" .. status_text)
                    end
                else
                    tv.setText(display_text)
                end
            else
                tv.setText(display_text)
            end
            updateMessageDescription(tv)
        end)
    end
end

loadHistory = function()
    chat_history = {messages = {}}
    pinnedStack = {}
    views.chatContainer.removeAllViews()
    
    local fa = io.open(file_path_admin, "r")
    if fa then
        local content = fa:read("*a")
        fa:close()
        local s, root = pcall(function() return JSONObject(content) end)
        if s and root.has("last_update_id") then
            admin_last_update_id = root.getLong("last_update_id")
        end
    end

    local active_file = ""
    if current_chat_id == "admin" then
        active_file = file_path_admin
    elseif current_chat_id == "local" then
        active_file = file_path_local
    else
        active_file = dir_path .. "/chat_" .. current_chat_id .. ".json"
    end
    
    local f = io.open(active_file, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local s, root = pcall(function() return JSONObject(content) end)
        if s and root.has("messages") then
            local arr = root.getJSONArray("messages")
            for i = 0, arr.length() - 1 do
                local item = arr.getJSONObject(i)
                local text = item.getString("text")
                local is_me = item.getBoolean("is_me")
                local is_starred = false
                local is_pinned = false
                local audio_path = nil
                local media_path = nil
                local media_type = nil
                
                if item.has("is_starred") then
                    is_starred = item.getBoolean("is_starred")
                end
                if item.has("is_pinned") then
                    is_pinned = item.getBoolean("is_pinned")
                end
                if item.has("audio_path") then
                    audio_path = item.getString("audio_path")
                end
                if item.has("media_path") then
                    media_path = item.getString("media_path")
                    media_type = item.getInt("media_type")
                end
                
                local timestamp = os.time()
                if item.has("timestamp") then
                    timestamp = item.getLong("timestamp")
                end
                
                if is_pinned then
                    table.insert(pinnedStack, i + 1)
                end
                
                table.insert(chat_history.messages, {text = text, is_me = is_me, is_starred = is_starred, is_pinned = is_pinned, audio_path = audio_path, media_path = media_path, media_type = media_type, timestamp = timestamp})
                appendMessage(text, is_me, is_starred, is_pinned, false, audio_path, timestamp, media_path, media_type)
            end
        end
    end
    currentPinnedDisplayIndex = #pinnedStack
    refreshPinnedDisplay()
    
    if current_chat_id == "admin" then
        views.titleTexa.setText("Texa Admin")
        views.tvConnectionStatus.setVisibility(0)
    elseif current_chat_id == "local" then
        views.titleTexa.setText("Catatan Pribadi")
        views.tvConnectionStatus.setVisibility(8)
    else
        local cached = contacts_cache[current_chat_id]
        if cached then
            local displayName = cached.name
            if displayName == "" then displayName = cached.username end
            if displayName == "" then displayName = "Pengguna Anonim" end
            views.titleTexa.setText(displayName)
        else
            views.titleTexa.setText("Memuat...")
        end
        views.tvConnectionStatus.setVisibility(0)
        
        syncContactInfo(current_chat_id, function(info)
            local displayName = info.name
            if displayName == "" then displayName = info.username end
            if displayName == "" then displayName = "Pengguna Anonim" end
            views.titleTexa.setText(displayName)
        end)
    end
end

local function refreshAllMessages()
    views.chatContainer.removeAllViews()
    selectedViews = {}
    isSelectionMode = false
    searchResults = {}
    currentSearchIndex = 0
    
    views.topBarSelection.setVisibility(8)
    views.bottomSelectionBar.setVisibility(8)
    views.topBarSearch.setVisibility(8)
    views.searchNavContainer.setVisibility(8)
    
    if currentFilterMode == "normal" then
        views.topBarNormal.setVisibility(0)
        views.bottomInputBar.setVisibility(0)
    end

    pinnedStack = {}
    for i, msg in ipairs(chat_history.messages) do
        if msg.is_pinned then
            table.insert(pinnedStack, i)
        end
        appendMessage(msg.text, msg.is_me, msg.is_starred, msg.is_pinned, false, msg.audio_path, msg.timestamp, msg.media_path, msg.media_type)
    end
    currentPinnedDisplayIndex = #pinnedStack
    refreshPinnedDisplay()
    applyFilter()
end

local function showSettingsDialog()
    local sLayout = {
        LinearLayout,
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "fill",
        backgroundColor = "#F5F5F5",
        {
            LinearLayout,
            layout_width = "fill",
            layout_height = "60dp",
            backgroundColor = "#075E54",
            gravity = "center_vertical",
            orientation = "horizontal",
            {
                ImageView,
                id = "btnBackSettings",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "12dp",
                layout_marginLeft = "4dp"
            },
            {
                TextView,
                id = "tvSettingsTitle",
                text = "Pengaturan",
                textSize = "20sp",
                textColor = "#FFFFFF",
                layout_marginLeft = "12dp",
                layout_weight = "1"
            },
            {
                ImageView,
                id = "btnSettingsFilter",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                layout_marginRight = "4dp"
            }
        },
        {
            LinearLayout,
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#FFFFFF",
            orientation = "horizontal",
            padding = "8dp",
            {
                EditText,
                id = "settingsSearchInput",
                layout_width = "fill",
                layout_height = "wrap",
                hint = "Cari pengaturan...",
                textSize = "16sp",
                singleLine = true,
                padding = "12dp",
                backgroundColor = "#F0F0F0",
                layout_weight = "1"
            }
        },
        {
            ScrollView,
            layout_width = "fill",
            layout_height = "fill",
            layout_weight = "1",
            fillViewport = "true",
            {
                LinearLayout,
                id = "settingsContainer",
                orientation = "vertical",
                layout_width = "fill",
                layout_height = "wrap",
                padding = "16dp",
                {
                    TextView,
                    text = "Pengaturan Umum",
                    textSize = "16sp",
                    textColor = "#00897B",
                    layout_marginBottom = "12dp"
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    {
                        TextView,
                        text = "Sinkronisasi latar belakang",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    },
                    {
                        Switch,
                        id = "switchSyncBg",
                        checked = sync_background
                    }
                },
                {
                    TextView,
                    text = "Pengaturan Penerjemah",
                    textSize = "16sp",
                    textColor = "#00897B",
                    layout_marginTop = "24dp",
                    layout_marginBottom = "12dp"
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "8dp",
                    {
                        LinearLayout,
                        id = "btnSetSourceLang",
                        layout_weight = "1",
                        layout_width = "0dp",
                        gravity = "center",
                        padding = "12dp",
                        focusable = true,
                        clickable = true,
                        {
                            TextView,
                            id = "tvSetSourceLang",
                            text = trans_source_lang,
                            textColor = "#00897B",
                            textSize = "16sp"
                        }
                    },
                    {
                        LinearLayout,
                        id = "btnSetSwapLang",
                        layout_width = "wrap",
                        layout_height = "wrap",
                        gravity = "center",
                        padding = "12dp",
                        focusable = true,
                        clickable = true,
                        {
                            ImageView,
                            id = "ivSetSwapLang",
                            layout_width = "24dp",
                            layout_height = "24dp"
                        }
                    },
                    {
                        LinearLayout,
                        id = "btnSetTargetLang",
                        layout_weight = "1",
                        layout_width = "0dp",
                        gravity = "center",
                        padding = "12dp",
                        focusable = true,
                        clickable = true,
                        {
                            TextView,
                            id = "tvSetTargetLang",
                            text = trans_target_lang,
                            textColor = "#00897B",
                            textSize = "16sp"
                        }
                    }
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    layout_marginTop = "8dp",
                    {
                        TextView,
                        text = "Terjemahkan pesan",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    },
                    {
                        Switch,
                        id = "switchAutoMsg",
                        checked = trans_auto_msg
                    }
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    layout_marginTop = "2dp",
                    {
                        TextView,
                        text = "Terjemahkan informasi",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    },
                    {
                        Switch,
                        id = "switchAutoInfo",
                        checked = trans_auto_info
                    }
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    layout_marginTop = "2dp",
                    {
                        TextView,
                        text = "Tampilkan pesan asli",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    },
                    {
                        Switch,
                        id = "switchShowOriginal",
                        checked = trans_show_original
                    }
                },
                {
                    TextView,
                    text = "Pengaturan Notifikasi",
                    textSize = "16sp",
                    textColor = "#00897B",
                    layout_marginTop = "24dp",
                    layout_marginBottom = "12dp"
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    {
                        TextView,
                        text = "Notifikasi pesan",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    },
                    {
                        Switch,
                        id = "switchNotifMsg",
                        checked = notif_msg
                    }
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    layout_marginTop = "2dp",
                    {
                        TextView,
                        text = "Notifikasi informasi",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    },
                    {
                        Switch,
                        id = "switchNotifInfo",
                        checked = notif_info
                    }
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    layout_marginTop = "2dp",
                    {
                        TextView,
                        text = "Ringkasan notifikasi",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    },
                    {
                        Switch,
                        id = "switchNotifSummary",
                        checked = notif_summary
                    }
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    layout_marginTop = "2dp",
                    {
                        TextView,
                        text = "Getaran pemberitahuan pesan",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    },
                    {
                        Switch,
                        id = "switchNotifVibrateMsg",
                        checked = notif_vibrate_msg
                    }
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    layout_marginTop = "2dp",
                    {
                        TextView,
                        text = "Getaran pemberitahuan informasi",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    },
                    {
                        Switch,
                        id = "switchNotifVibrateInfo",
                        checked = notif_vibrate_info
                    }
                },
                {
                    TextView,
                    text = "Pengaturan Pengetikan Suara",
                    textSize = "16sp",
                    textColor = "#00897B",
                    layout_marginTop = "24dp",
                    layout_marginBottom = "12dp"
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    {
                        TextView,
                        text = "Kirim otomatis setelah dikte",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    },
                    {
                        Switch,
                        id = "switchDictationAutoSend",
                        checked = dictation_auto_send
                    }
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    layout_marginTop = "2dp",
                    {
                        TextView,
                        text = "Dikte berkelanjutan",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    },
                    {
                        Switch,
                        id = "switchDictationContinuous",
                        checked = dictation_continuous
                    }
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    layout_marginTop = "2dp",
                    {
                        TextView,
                        text = "Getaran umpan balik dikte",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    },
                    {
                        Switch,
                        id = "switchDictationVibrate",
                        checked = dictation_vibrate
                    }
                },
                {
                    TextView,
                    text = "Profil Pengguna",
                    textSize = "16sp",
                    textColor = "#00897B",
                    layout_marginTop = "24dp",
                    layout_marginBottom = "12dp"
                },
                {
                    LinearLayout,
                    id = "btnMyProfile",
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    focusable = true,
                    clickable = true,
                    {
                        TextView,
                        text = "Atur Profil Saya",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    }
                },
                {
                    TextView,
                    text = "Pengaturan Akun",
                    textSize = "16sp",
                    textColor = "#00897B",
                    layout_marginTop = "24dp",
                    layout_marginBottom = "12dp"
                },
                {
                    LinearLayout,
                    id = "btnResetPassword",
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    focusable = true,
                    clickable = true,
                    {
                        TextView,
                        text = "Atur Ulang Kata Sandi",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_weight = "1"
                    }
                },
                {
                    LinearLayout,
                    id = "btnLogout",
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    layout_marginTop = "2dp",
                    focusable = true,
                    clickable = true,
                    {
                        TextView,
                        text = "Keluar Akun",
                        textSize = "16sp",
                        textColor = "#FF0000",
                        layout_weight = "1"
                    }
                },
                {
                    TextView,
                    text = "Informasi Aplikasi",
                    textSize = "16sp",
                    textColor = "#00897B",
                    layout_marginTop = "24dp",
                    layout_marginBottom = "12dp"
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "vertical",
                    padding = "16dp",
                    {
                        TextView,
                        text = "Versi Aplikasi",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_marginBottom = "4dp"
                    },
                    {
                        TextView,
                        text = APP_VERSION_NAME,
                        textSize = "14sp",
                        textColor = "#888888"
                    }
                },
                {
                    LinearLayout,
                    id = "btnCheckUpdate",
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "horizontal",
                    gravity = "center_vertical",
                    padding = "16dp",
                    layout_marginTop = "2dp",
                    focusable = true,
                    clickable = true,
                    {
                        TextView,
                        text = "Periksa Pembaruan",
                        textSize = "16sp",
                        textColor = "#00897B",
                        layout_weight = "1"
                    }
                },
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "wrap",
                    backgroundColor = "#FFFFFF",
                    orientation = "vertical",
                    padding = "16dp",
                    layout_marginTop = "2dp",
                    {
                        TextView,
                        text = "Pengembang",
                        textSize = "16sp",
                        textColor = "#333333",
                        layout_marginBottom = "4dp"
                    },
                    {
                        TextView,
                        text = "Texa Development Team",
                        textSize = "14sp",
                        textColor = "#888888"
                    }
                }
            }
        }
    }
    
    local sViews = {}
    local sContentView = loadlayout(sLayout, sViews)
    
    local function viewContainsText(view, query)
        local className = view.getClass().getSimpleName()
        if className == "TextView" or className == "Button" or className == "EditText" then
            local t = string.lower(tostring(view.getText()))
            if t ~= "" and string.find(t, query, 1, true) then return true end
        elseif className == "LinearLayout" or className == "FrameLayout" or className == "ScrollView" then
            for i = 0, view.getChildCount() - 1 do
                if viewContainsText(view.getChildAt(i), query) then return true end
            end
        end
        return false
    end

    sViews.settingsSearchInput.addTextChangedListener(TextWatcher{
        onTextChanged = function(s, start, before, count)
            local query = string.lower(tostring(s))
            local container = sViews.settingsContainer
            local lastCategory = nil
            local hasVisibleItems = false
            
            for i = 0, container.getChildCount() - 1 do
                local child = container.getChildAt(i)
                local className = child.getClass().getSimpleName()
                
                if className == "TextView" then
                    if lastCategory then
                        lastCategory.setVisibility(hasVisibleItems and 0 or 8)
                    end
                    lastCategory = child
                    hasVisibleItems = false
                elseif className == "LinearLayout" then
                    if query == "" or viewContainsText(child, query) then
                        child.setVisibility(0)
                        hasVisibleItems = true
                    else
                        child.setVisibility(8)
                    end
                end
            end
            
            if lastCategory then
                lastCategory.setVisibility(hasVisibleItems and 0 or 8)
            end
        end
    })
    
    if Build.VERSION.SDK_INT >= 16 then
        sViews.tvSetSourceLang.setImportantForAccessibility(2)
        sViews.tvSetTargetLang.setImportantForAccessibility(2)
        sViews.ivSetSwapLang.setImportantForAccessibility(2)
    end
    sViews.ivSetSwapLang.setImageBitmap(createEmojiBitmap("⇄", 100, 50, 20, 60))
    
    sViews.tvSettingsTitle.setTypeface(Typeface.DEFAULT_BOLD)
    sViews.btnBackSettings.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
    sViews.btnSettingsFilter.setImageBitmap(createEmojiBitmap("站ｮ", 100, 70, 35, 75))
    
    local function updateSetLangDescriptions()
        sViews.btnSetSourceLang.setContentDescription("Sumber bahasa " .. string.lower(trans_source_lang) .. ", klik untuk mengubah")
        sViews.btnSetTargetLang.setContentDescription("Tujuan bahasa " .. string.lower(trans_target_lang) .. ", klik untuk mengubah")
        sViews.btnSetSwapLang.setContentDescription("Tukar bahasa")
        sViews.btnBackSettings.setContentDescription("Kembali")
        sViews.btnSettingsFilter.setContentDescription("Filter Pengaturan")
    end
    
    updateSetLangDescriptions()
    
    local sDialog = Dialog(ctx)
    sDialog.requestWindowFeature(1)
    sDialog.setContentView(sContentView)
    
    local w = sDialog.getWindow()
    if Build.VERSION.SDK_INT >= 22 then
        w.setType(2032)
    else
        w.setType(2003)
    end
    w.setBackgroundDrawable(ColorDrawable(0xffF5F5F5))
    w.setLayout(-1, -1)
    
    sViews.btnSetSourceLang.onClick = function()
        showLanguageList("Sumber Bahasa", function(lang)
            trans_source_lang = lang
            sViews.tvSetSourceLang.setText(lang)
            saveTransConfig()
            updateSetLangDescriptions()
            if trans_auto_msg then refreshAllMessages() end
        end)
    end
    
    sViews.btnSetTargetLang.onClick = function()
        showLanguageList("Tujuan Bahasa", function(lang)
            trans_target_lang = lang
            sViews.tvSetTargetLang.setText(lang)
            saveTransConfig()
            updateSetLangDescriptions()
            if trans_auto_msg then refreshAllMessages() end
        end)
    end
    
    sViews.btnSetSwapLang.onClick = function()
        local temp = trans_source_lang
        trans_source_lang = trans_target_lang
        trans_target_lang = temp
        sViews.tvSetSourceLang.setText(trans_source_lang)
        sViews.tvSetTargetLang.setText(trans_target_lang)
        saveTransConfig()
        updateSetLangDescriptions()
        if trans_auto_msg then refreshAllMessages() end
    end
    
    sViews.switchSyncBg.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{
        onCheckedChanged = function(buttonView, isChecked)
            sync_background = isChecked
            saveTransConfig()
        end
    })
    
    sViews.switchAutoMsg.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{
        onCheckedChanged = function(buttonView, isChecked)
            trans_auto_msg = isChecked
            saveTransConfig()
            refreshAllMessages()
        end
    })
    
    sViews.switchAutoInfo.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{
        onCheckedChanged = function(buttonView, isChecked)
            trans_auto_info = isChecked
            saveTransConfig()
        end
    })

    sViews.switchShowOriginal.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{
        onCheckedChanged = function(buttonView, isChecked)
            trans_show_original = isChecked
            saveTransConfig()
            if trans_auto_msg then refreshAllMessages() end
        end
    })
    
    sViews.switchNotifMsg.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{
        onCheckedChanged = function(buttonView, isChecked)
            notif_msg = isChecked
            saveTransConfig()
        end
    })
    
    sViews.switchNotifInfo.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{
        onCheckedChanged = function(buttonView, isChecked)
            notif_info = isChecked
            saveTransConfig()
        end
    })
    
    sViews.switchNotifSummary.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{
        onCheckedChanged = function(buttonView, isChecked)
            notif_summary = isChecked
            saveTransConfig()
        end
    })

    sViews.switchNotifVibrateMsg.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{
        onCheckedChanged = function(buttonView, isChecked)
            notif_vibrate_msg = isChecked
            saveTransConfig()
        end
    })

    sViews.switchNotifVibrateInfo.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{
        onCheckedChanged = function(buttonView, isChecked)
            notif_vibrate_info = isChecked
            saveTransConfig()
        end
    })

    sViews.switchDictationAutoSend.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{
        onCheckedChanged = function(buttonView, isChecked)
            dictation_auto_send = isChecked
            saveTransConfig()
        end
    })

    sViews.switchDictationContinuous.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{
        onCheckedChanged = function(buttonView, isChecked)
            dictation_continuous = isChecked
            saveTransConfig()
        end
    })

    sViews.switchDictationVibrate.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener{
        onCheckedChanged = function(buttonView, isChecked)
            dictation_vibrate = isChecked
            saveTransConfig()
        end
    })

    sViews.btnMyProfile.onClick = function()
        local pd = ProgressDialog(ctx)
        pd.setMessage("Memuat profil...")
        pd.setCancelable(false)
        local pdWindow = pd.getWindow()
        if Build.VERSION.SDK_INT >= 22 then
            pdWindow.setType(2032)
        else
            pdWindow.setType(2003)
        end
        pd.show()

        task(function(t_token)
            require "import"
            import "java.net.URL"
            import "java.io.BufferedReader"
            import "java.io.InputStreamReader"
            local code = -1
            local resBody = ""
            pcall(function()
                local url = URL("http://botspark.de1.octavia.id:25701/api/users/profile")
                local conn = url.openConnection()
                conn.setConnectTimeout(10000)
                conn.setReadTimeout(10000)
                conn.setRequestMethod("GET")
                conn.setRequestProperty("Authorization", "Bearer " .. t_token)
                code = conn.getResponseCode()
                local isStream = (code >= 200 and code < 300) and conn.getInputStream() or conn.getErrorStream()
                if isStream then
                    local br = BufferedReader(InputStreamReader(isStream))
                    local line = br.readLine()
                    while line ~= nil do
                        resBody = resBody .. line
                        line = br.readLine()
                    end
                    br.close()
                end
            end)
            return code, resBody
        end, auth_token, function(code, body)
            pd.dismiss()
            local s, data = pcall(function() import "org.json.JSONObject" return JSONObject(body) end)
            if code == 200 and s then
                local currentName = tostring(data.optString("name", ""))
                local currentUsername = tostring(data.optString("username", ""))
                local currentBio = tostring(data.optString("bio", ""))
                local currentProfilePic = tostring(data.optString("profilePicture", ""))

                local pLayout = {
                    LinearLayout,
                    orientation = "vertical",
                    layout_width = "fill",
                    layout_height = "fill",
                    backgroundColor = "#F5F5F5",
                    {
                        LinearLayout,
                        layout_width = "fill",
                        layout_height = "60dp",
                        backgroundColor = "#075E54",
                        gravity = "center_vertical",
                        orientation = "horizontal",
                        {
                            ImageView,
                            id = "btnBackProfile",
                            layout_width = "48dp",
                            layout_height = "48dp",
                            padding = "12dp",
                            layout_marginLeft = "4dp",
                            contentDescription = "Kembali"
                        },
                        {
                            TextView,
                            text = "Profil Saya",
                            textSize = "20sp",
                            textColor = "#FFFFFF",
                            layout_marginLeft = "12dp",
                            layout_weight = "1"
                        },
                        {
                            TextView,
                            id = "btnSaveProfile",
                            text = "Simpan",
                            textSize = "14sp",
                            textColor = "#FFFFFF",
                            gravity = "center",
                            layout_width = "wrap",
                            layout_height = "fill",
                            padding = "12dp",
                            layout_marginRight = "4dp",
                            clickable = true,
                            focusable = true,
                            contentDescription = "Simpan Profil"
                        }
                    },
                    {
                        ScrollView,
                        layout_width = "fill",
                        layout_height = "fill",
                        layout_weight = "1",
                        fillViewport = "true",
                        {
                            LinearLayout,
                            orientation = "vertical",
                            layout_width = "fill",
                            layout_height = "wrap",
                            padding = "16dp",
                            {
                                LinearLayout,
                                orientation = "vertical",
                                layout_width = "fill",
                                layout_height = "wrap",
                                backgroundColor = "#FFFFFF",
                                padding = "16dp",
                                gravity = "center",
                                layout_marginBottom = "12dp",
                                {
                                    ImageView,
                                    id = "ivProfilePic",
                                    layout_width = "100dp",
                                    layout_height = "100dp",
                                    scaleType = "centerCrop",
                                    contentDescription = "Foto Profil"
                                },
                                {
                                    LinearLayout,
                                    orientation = "horizontal",
                                    layout_width = "wrap",
                                    layout_height = "wrap",
                                    layout_marginTop = "8dp",
                                    {
                                        TextView,
                                        id = "btnChangeProfilePic",
                                        text = "Ubah Profil",
                                        textColor = "#00897B",
                                        textSize = "14sp",
                                        layout_marginRight = "16dp",
                                        clickable = true,
                                        focusable = true,
                                        contentDescription = "Ubah profil"
                                    },
                                    {
                                        TextView,
                                        id = "btnDeleteProfilePic",
                                        text = "Hapus Foto",
                                        textColor = "#FF0000",
                                        textSize = "14sp",
                                        layout_marginLeft = "16dp",
                                        clickable = true,
                                        focusable = true,
                                        contentDescription = "Hapus foto profil"
                                    }
                                }
                            },
                            {
                                TextView,
                                text = "Informasi Pribadi",
                                textSize = "16sp",
                                textColor = "#00897B",
                                layout_marginBottom = "12dp"
                            },
                            {
                                LinearLayout,
                                orientation = "vertical",
                                layout_width = "fill",
                                layout_height = "wrap",
                                backgroundColor = "#FFFFFF",
                                padding = "16dp",
                                {
                                    EditText,
                                    id = "etProfileName",
                                    hint = "Nama Lengkap",
                                    text = currentName,
                                    layout_width = "fill",
                                    layout_height = "wrap",
                                    singleLine = true,
                                    layout_marginBottom = "16dp",
                                    contentDescription = "Kolom masukan Nama Lengkap"
                                },
                                {
                                    EditText,
                                    id = "etProfileUsername",
                                    hint = "Username",
                                    text = currentUsername,
                                    layout_width = "fill",
                                    layout_height = "wrap",
                                    singleLine = true,
                                    contentDescription = "Kolom masukan Username tanpa spasi"
                                },
                                {
                                    EditText,
                                    id = "etProfileBio",
                                    hint = "Bio",
                                    text = currentBio,
                                    layout_width = "fill",
                                    layout_height = "wrap",
                                    lines = 4,
                                    maxLines = 6,
                                    gravity = "top|left",
                                    layout_marginTop = "16dp",
                                    contentDescription = "Kolom masukan Bio"
                                }
                            }
                        }
                    }
                }

                local pViews = {}
                local pContentView = loadlayout(pLayout, pViews)

                pViews.btnBackProfile.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))

                local function setProfileImage(base64Data)
                    if base64Data and base64Data ~= "" then
                        pcall(function()
                            import "android.util.Base64"
                            import "android.graphics.BitmapFactory"
                            local cleanB64 = base64Data:match("base64,(.*)")
                            local decodedString = Base64.decode(cleanB64, Base64.DEFAULT)
                            local decodedByte = BitmapFactory.decodeByteArray(decodedString, 0, #decodedString)
                            pViews.ivProfilePic.setImageBitmap(decodedByte)
                        end)
                    else
                        pViews.ivProfilePic.setImageBitmap(createEmojiBitmap("👤", 150, 100, 25, 110))
                    end
                end
                setProfileImage(currentProfilePic)

                local function showProfileGalleryDialog(onSelected)
                    local galleryLayout = {
                        LinearLayout,
                        orientation = "vertical",
                        layout_width = "fill",
                        layout_height = "fill",
                        backgroundColor = "#F5F5F5",
                        {
                            FrameLayout,
                            layout_width = "fill",
                            layout_height = "wrap",
                            {
                                LinearLayout,
                                id = "galleryTopBarNormal",
                                layout_width = "fill",
                                layout_height = "60dp",
                                backgroundColor = "#075E54",
                                gravity = "center_vertical",
                                orientation = "horizontal",
                                {
                                    ImageView,
                                    id = "btnBackGallery",
                                    layout_width = "48dp",
                                    layout_height = "48dp",
                                    padding = "12dp",
                                    layout_marginLeft = "4dp",
                                    contentDescription = "Kembali"
                                },
                                {
                                    TextView,
                                    text = "Pilih Foto Profil",
                                    textSize = "20sp",
                                    textColor = "#FFFFFF",
                                    layout_marginLeft = "12dp",
                                    layout_weight = "1"
                                },
                                {
                                    ImageView,
                                    id = "btnGalleryFilter",
                                    layout_width = "48dp",
                                    layout_height = "48dp",
                                    padding = "12dp",
                                    layout_marginRight = "0dp",
                                    contentDescription = "Urutkan Media"
                                },
                                {
                                    ImageView,
                                    id = "btnGallerySearch",
                                    layout_width = "48dp",
                                    layout_height = "48dp",
                                    padding = "12dp",
                                    layout_marginRight = "4dp",
                                    contentDescription = "Cari Media"
                                }
                            },
                            {
                                LinearLayout,
                                id = "galleryTopBarSearch",
                                layout_width = "fill",
                                layout_height = "60dp",
                                backgroundColor = "#FFFFFF",
                                gravity = "center_vertical",
                                orientation = "horizontal",
                                visibility = 8,
                                {
                                    EditText,
                                    id = "gallerySearchInput",
                                    layout_width = "fill",
                                    layout_height = "wrap",
                                    layout_weight = "1",
                                    hint = "Cari nama file...",
                                    textSize = "16sp",
                                    singleLine = true,
                                    imeOptions = 3,
                                    layout_marginLeft = "16dp"
                                },
                                {
                                    ImageView,
                                    id = "btnGalleryCloseSearch",
                                    layout_width = "48dp",
                                    layout_height = "48dp",
                                    padding = "12dp",
                                    layout_marginRight = "4dp",
                                    contentDescription = "Tutup Pencarian"
                                }
                            }
                        },
                        {
                            FrameLayout,
                            id = "galleryContentContainer",
                            layout_width = "fill",
                            layout_height = "0dp",
                            layout_weight = "1"
                        },
                        {
                            LinearLayout,
                            layout_width = "fill",
                            layout_height = "wrap",
                            orientation = "horizontal",
                            gravity = "center_vertical",
                            padding = "8dp",
                            backgroundColor = "#F0F0F0",
                            {
                                TextView,
                                id = "btnGalleryPrev",
                                text = "Sebelumnya",
                                layout_weight = "1",
                                layout_width = "0dp",
                                gravity = "center",
                                padding = "8dp",
                                textColor = "#888888",
                                clickable = false
                            },
                            {
                                TextView,
                                id = "tvGalleryPageInfo",
                                text = "Halaman 1",
                                layout_weight = "1",
                                layout_width = "0dp",
                                gravity = "center",
                                padding = "8dp",
                                textColor = "#333333"
                            },
                            {
                                TextView,
                                id = "btnGalleryNext",
                                text = "Berikutnya",
                                layout_weight = "1",
                                layout_width = "0dp",
                                gravity = "center",
                                padding = "8dp",
                                textColor = "#888888",
                                clickable = false
                            }
                        }
                    }
                    
                    local gViews = {}
                    local gContentView = loadlayout(galleryLayout, gViews)
                    gViews.btnBackGallery.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
                    gViews.btnGalleryFilter.setImageBitmap(createEmojiBitmap("站ｮ", 100, 70, 35, 75))
                    gViews.btnGallerySearch.setImageBitmap(createEmojiBitmap("🔍", 100, 60, 20, 75))
                    gViews.btnGalleryCloseSearch.setImageBitmap(createEmojiBitmap("X", 100, 70, 30, 75))
                    
                    local gDialog = Dialog(ctx)
                    gDialog.requestWindowFeature(1)
                    gDialog.setContentView(gContentView)
                    local w = gDialog.getWindow()
                    if Build.VERSION.SDK_INT >= 22 then w.setType(2032) else w.setType(2003) end
                    w.setBackgroundDrawable(ColorDrawable(0xffF5F5F5))
                    w.setLayout(-1, -1)
                    
                    local allMediaList = {}
                    local currentMediaList = {}
                    local currentGalleryPage = 1
                    local itemsPerPage = 25
                    local currentGallerySort = "date_added DESC"
                    
                    local function renderGalleryPage()
                        gViews.galleryContentContainer.removeAllViews()
                        local sv = ScrollView(ctx)
                        local gridContainer = LinearLayout(ctx)
                        gridContainer.setOrientation(1)
                        gridContainer.setPadding(4, 4, 4, 4)
                        sv.addView(gridContainer)
                        gViews.galleryContentContainer.addView(sv)
                        
                        if #currentMediaList == 0 then
                            local emptyText = TextView(ctx)
                            emptyText.setText("Tidak ada foto ditemukan")
                            emptyText.setGravity(17)
                            emptyText.setTextColor(0xFF888888)
                            emptyText.setLayoutParams(FrameLayout.LayoutParams(-1, -1))
                            gViews.galleryContentContainer.addView(emptyText)
                            return
                        end
                        
                        local totalPages = math.ceil(#currentMediaList / itemsPerPage)
                        gViews.tvGalleryPageInfo.setText("Halaman " .. currentGalleryPage .. " dari " .. totalPages)
                        
                        gViews.btnGalleryPrev.setTextColor(currentGalleryPage > 1 and 0xFF00897B or 0xFF888888)
                        gViews.btnGalleryPrev.setClickable(currentGalleryPage > 1)
                        
                        gViews.btnGalleryNext.setTextColor(currentGalleryPage < totalPages and 0xFF00897B or 0xFF888888)
                        gViews.btnGalleryNext.setClickable(currentGalleryPage < totalPages)
                        
                        local startIndex = (currentGalleryPage - 1) * itemsPerPage + 1
                        local endIndex = math.min(startIndex + itemsPerPage - 1, #currentMediaList)
                        
                        local row
                        local screenWidth = ctx.getResources().getDisplayMetrics().widthPixels
                        local itemSize = math.floor((screenWidth - 32) / 3)
                        
                        for i = startIndex, endIndex do
                            local mediaPath = currentMediaList[i]
                            local gridIndex = i - startIndex
                            
                            if gridIndex % 3 == 0 then
                                row = LinearLayout(ctx)
                                row.setOrientation(0)
                                gridContainer.addView(row)
                            end
                            
                            local itemContainer = FrameLayout(ctx)
                            itemContainer.setLayoutParams(LinearLayout.LayoutParams(itemSize, itemSize))
                            itemContainer.setPadding(4, 4, 4, 4)
                            itemContainer.setContentDescription("Pilih foto " .. i)
                            
                            local imgView = ImageView(ctx)
                            imgView.setScaleType(ImageView.ScaleType.CENTER_CROP)
                            imgView.setBackgroundColor(0xFFDDDDDD)
                            
                            task(function(mPath, reqSize)
                                require "import"
                                import "android.graphics.BitmapFactory"
                                local bmp = nil
                                pcall(function()
                                    local opt = BitmapFactory.Options()
                                    opt.inJustDecodeBounds = true
                                    BitmapFactory.decodeFile(mPath, opt)
                                    local scale = 1
                                    while (opt.outWidth / scale / 2 >= reqSize and opt.outHeight / scale / 2 >= reqSize) do
                                        scale = scale * 2
                                    end
                                    opt.inSampleSize = scale
                                    opt.inJustDecodeBounds = false
                                    bmp = BitmapFactory.decodeFile(mPath, opt)
                                end)
                                return bmp
                            end, mediaPath, itemSize, function(bmp)
                                if bmp then imgView.setImageBitmap(bmp) end
                            end)
                            
                            itemContainer.addView(imgView)
                            
                            itemContainer.onClick = function()
                                onSelected(mediaPath)
                                gDialog.dismiss()
                            end
                            
                            itemContainer.onLongClick = function()
                                local fileName = mediaPath:match("([^/]+)$") or "Tidak diketahui"
                                local previewLayout = {
                                    LinearLayout,
                                    orientation = "vertical",
                                    layout_width = "fill",
                                    layout_height = "fill",
                                    backgroundColor = "#000000",
                                    {
                                        LinearLayout,
                                        layout_width = "fill",
                                        layout_height = "60dp",
                                        backgroundColor = "#075E54",
                                        gravity = "center_vertical",
                                        orientation = "horizontal",
                                        {
                                            ImageView,
                                            id = "btnPreviewBack",
                                            layout_width = "48dp",
                                            layout_height = "48dp",
                                            padding = "12dp",
                                            layout_marginLeft = "4dp",
                                            contentDescription = "Kembali"
                                        },
                                        {
                                            TextView,
                                            text = "Penampil Foto",
                                            textSize = "20sp",
                                            textColor = "#FFFFFF",
                                            layout_marginLeft = "12dp",
                                            layout_weight = "1"
                                        },
                                        {
                                            LinearLayout,
                                            id = "btnPreviewSelect",
                                            layout_width = "wrap",
                                            layout_height = "fill",
                                            orientation = "horizontal",
                                            gravity = "center",
                                            padding = "8dp",
                                            layout_marginRight = "4dp",
                                            clickable = true,
                                            focusable = true,
                                            {
                                                ImageView,
                                                id = "ivPreviewSelectIcon",
                                                layout_width = "32dp",
                                                layout_height = "32dp",
                                                padding = "4dp"
                                            },
                                            {
                                                TextView,
                                                id = "tvPreviewSelectText",
                                                text = "Pilih",
                                                textSize = "16sp",
                                                textColor = "#FFFFFF",
                                                layout_marginLeft = "4dp"
                                            }
                                        }
                                    },
                                    {
                                        TextView,
                                        id = "tvPreviewFileName",
                                        text = fileName,
                                        textSize = "14sp",
                                        textColor = "#CCCCCC",
                                        gravity = "center",
                                        padding = "8dp"
                                    },
                                    {
                                        FrameLayout,
                                        layout_width = "fill",
                                        layout_height = "0dp",
                                        layout_weight = "1",
                                        {
                                            ImageView,
                                            id = "previewImageView",
                                            layout_width = "fill",
                                            layout_height = "fill"
                                        }
                                    }
                                }
                                
                                local pViews = {}
                                local pContentView = loadlayout(previewLayout, pViews)
                                
                                pViews.btnPreviewBack.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
                                pViews.ivPreviewSelectIcon.setImageBitmap(createEmojiBitmap("☑", 100, 70, 25, 75))
                                
                                local pDialog = Dialog(ctx)
                                pDialog.requestWindowFeature(1)
                                pDialog.setContentView(pContentView)
                                local pw = pDialog.getWindow()
                                if Build.VERSION.SDK_INT >= 22 then
                                    pw.setType(2032)
                                else
                                    pw.setType(2003)
                                end
                                pw.setBackgroundDrawable(ColorDrawable(0xff000000))
                                pw.setLayout(-1, -1)
                                
                                pcall(function()
                                    import "android.graphics.BitmapFactory"
                                    local bmp = BitmapFactory.decodeFile(mediaPath)
                                    if bmp then
                                        pViews.previewImageView.setImageBitmap(bmp)
                                    end
                                end)
                                
                                pViews.btnPreviewSelect.onClick = function()
                                    pDialog.dismiss()
                                    gDialog.dismiss()
                                    onSelected(mediaPath)
                                end
                                
                                pViews.btnPreviewBack.onClick = function()
                                    pDialog.dismiss()
                                end
                                
                                pDialog.show()
                                return true
                            end
                            
                            row.addView(itemContainer)
                        end
                    end
                    
                    local function applyGallerySearch(query)
                        currentMediaList = {}
                        if query == "" then
                            for _, path in ipairs(allMediaList) do
                                table.insert(currentMediaList, path)
                            end
                        else
                            local lowerQuery = string.lower(query)
                            for _, path in ipairs(allMediaList) do
                                local fileName = path:match("([^/]+)$") or ""
                                if string.find(string.lower(fileName), lowerQuery, 1, true) then
                                    table.insert(currentMediaList, path)
                                end
                            end
                        end
                        currentGalleryPage = 1
                        renderGalleryPage()
                    end

                    local function loadMediaList()
                        allMediaList = {}
                        pcall(function()
                            import "android.provider.MediaStore"
                            local uri = MediaStore.Files.getContentUri("external")
                            local proj = {"_data"}
                            local sel = "media_type=1"
                            local cursor = ctx.getContentResolver().query(uri, proj, sel, nil, currentGallerySort)
                            if cursor then
                                local colData = cursor.getColumnIndexOrThrow("_data")
                                while cursor.moveToNext() do
                                    local path = cursor.getString(colData)
                                    table.insert(allMediaList, path)
                                end
                                cursor.close()
                            end
                        end)
                        applyGallerySearch(tostring(gViews.gallerySearchInput.getText()))
                    end
                    
                    gViews.btnGalleryFilter.onClick = function()
                        local popMenu = PopupMenu(ctx, gViews.btnGalleryFilter)
                        local menu = popMenu.getMenu()
                        menu.add(0, 1, 0, "Terbaru")
                        menu.add(0, 2, 0, "Terlama")
                        
                        local closeItem = menu.add(0, 99, 0, "Tutup Menu Filter")
                        pcall(function()
                            closeItem.setIcon(BitmapDrawable(ctx.getResources(), createEmojiBitmap("X", 100, 70, 30, 75)))
                            if Build.VERSION.SDK_INT >= 26 then
                                closeItem.setContentDescription("Tutup Menu Filter")
                            end
                        end)
                        
                        popMenu.setOnMenuItemClickListener(PopupMenu.OnMenuItemClickListener{
                            onMenuItemClick = function(item)
                                local id = item.getItemId()
                                if id == 1 then
                                    currentGallerySort = "date_added DESC"
                                    loadMediaList()
                                    triggerAccessibilityAnnouncement("Diurutkan dari yang terbaru")
                                elseif id == 2 then
                                    currentGallerySort = "date_added ASC"
                                    loadMediaList()
                                    triggerAccessibilityAnnouncement("Diurutkan dari yang terlama")
                                end
                                return true
                            end
                        })
                        popMenu.show()
                    end

                    gViews.btnGallerySearch.onClick = function()
                        gViews.galleryTopBarNormal.setVisibility(8)
                        gViews.galleryTopBarSearch.setVisibility(0)
                        gViews.gallerySearchInput.requestFocus()
                        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
                        imm.showSoftInput(gViews.gallerySearchInput, 0)
                    end
                    
                    gViews.btnGalleryCloseSearch.onClick = function()
                        gViews.galleryTopBarSearch.setVisibility(8)
                        gViews.galleryTopBarNormal.setVisibility(0)
                        gViews.gallerySearchInput.setText("")
                        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
                        imm.hideSoftInputFromWindow(gViews.gallerySearchInput.getWindowToken(), 0)
                        applyGallerySearch("")
                    end

                    gViews.gallerySearchInput.setOnEditorActionListener(TextView.OnEditorActionListener{
                        onEditorAction = function(v, actionId, event)
                            if actionId == 3 or (event and event.getKeyCode() == 66 and event.getAction() == 0) then
                                local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
                                imm.hideSoftInputFromWindow(v.getWindowToken(), 0)
                                applyGallerySearch(tostring(v.getText()))
                                return true
                            end
                            return false
                        end
                    })
                    
                    gViews.btnGalleryPrev.onClick = function()
                        if currentGalleryPage > 1 then
                            currentGalleryPage = currentGalleryPage - 1
                            renderGalleryPage()
                        end
                    end
                    
                    gViews.btnGalleryNext.onClick = function()
                        local totalPages = math.ceil(#currentMediaList / itemsPerPage)
                        if currentGalleryPage < totalPages then
                            currentGalleryPage = currentGalleryPage + 1
                            renderGalleryPage()
                        end
                    end
                    
                    gViews.btnBackGallery.onClick = function()
                        gDialog.dismiss()
                    end
                    
                    loadMediaList()
                    gDialog.show()
                end

                pViews.btnChangeProfilePic.onClick = function()
                    showProfileGalleryDialog(function(path)
                        triggerAccessibilityAnnouncement("Memproses foto...")
                        task(function(imgPath)
                            require "import"
                            import "android.graphics.BitmapFactory"
                            import "android.graphics.Bitmap"
                            import "java.io.ByteArrayOutputStream"
                            import "android.util.Base64"
                            local success, result = pcall(function()
                                local opt = BitmapFactory.Options()
                                opt.inJustDecodeBounds = true
                                BitmapFactory.decodeFile(imgPath, opt)
                                local scale = 1
                                while (opt.outWidth / scale / 2 >= 300 and opt.outHeight / scale / 2 >= 300) do
                                    scale = scale * 2
                                end
                                opt.inSampleSize = scale
                                opt.inJustDecodeBounds = false
                                local bmp = BitmapFactory.decodeFile(imgPath, opt)
                                local baos = ByteArrayOutputStream()
                                bmp.compress(Bitmap.CompressFormat.JPEG, 70, baos)
                                local b = baos.toByteArray()
                                return "data:image/jpeg;base64," .. Base64.encodeToString(b, Base64.NO_WRAP)
                            end)
                            if success then return result else return "" end
                        end, path, function(b64Str)
                            if b64Str and b64Str ~= "" then
                                currentProfilePic = b64Str
                                setProfileImage(currentProfilePic)
                                triggerAccessibilityAnnouncement("Foto berhasil dipilih")
                            else
                                triggerAccessibilityAnnouncement("Gagal memproses foto")
                            end
                        end)
                    end)
                end

                pViews.btnDeleteProfilePic.onClick = function()
                    currentProfilePic = ""
                    setProfileImage(currentProfilePic)
                    triggerAccessibilityAnnouncement("Foto profil dihapus")
                end

                local pDialog = Dialog(ctx)
                pDialog.requestWindowFeature(1)
                pDialog.setContentView(pContentView)
                
                local dWindow = pDialog.getWindow()
                if Build.VERSION.SDK_INT >= 22 then
                    dWindow.setType(2032)
                else
                    dWindow.setType(2003)
                end
                dWindow.setBackgroundDrawable(ColorDrawable(0xffF5F5F5))
                dWindow.setLayout(-1, -1)

                pViews.btnBackProfile.onClick = function()
                    pDialog.dismiss()
                end

                pViews.btnSaveProfile.onClick = function()
                    local newName = tostring(pViews.etProfileName.getText())
                    local newUsername = tostring(pViews.etProfileUsername.getText()):gsub("%s+", "")
                    local newBio = tostring(pViews.etProfileBio.getText())
                    
                    pViews.btnSaveProfile.setEnabled(false)
                    pViews.btnSaveProfile.setText("Menyimpan")

                    task(function(t_token, t_name, t_user, t_bio, t_pic)
                        require "import"
                        import "java.net.URL"
                        import "java.io.DataOutputStream"
                        import "java.io.BufferedReader"
                        import "java.io.InputStreamReader"
                        import "org.json.JSONObject"
                        local pcode = -1
                        local pbody = ""
                        pcall(function()
                            local url = URL("http://botspark.de1.octavia.id:25701/api/users/profile")
                            local conn = url.openConnection()
                            conn.setConnectTimeout(10000)
                            conn.setReadTimeout(10000)
                            conn.setRequestMethod("PUT")
                            conn.setRequestProperty("Authorization", "Bearer " .. t_token)
                            conn.setRequestProperty("Content-Type", "application/json")
                            conn.setDoOutput(true)
                            
                            local reqJson = JSONObject()
                            reqJson.put("name", t_name)
                            reqJson.put("username", t_user)
                            reqJson.put("bio", t_bio)
                            reqJson.put("profilePicture", t_pic)
                            
                            local out = DataOutputStream(conn.getOutputStream())
                            out.writeBytes(reqJson.toString())
                            out.flush()
                            out.close()
                            
                            pcode = conn.getResponseCode()
                            local isStream = (pcode >= 200 and pcode < 300) and conn.getInputStream() or conn.getErrorStream()
                            if isStream then
                                local br = BufferedReader(InputStreamReader(isStream))
                                local line = br.readLine()
                                while line ~= nil do
                                    pbody = pbody .. line
                                    line = br.readLine()
                                end
                                br.close()
                            end
                        end)
                        return pcode, pbody
                    end, auth_token, newName, newUsername, newBio, currentProfilePic, function(pcode, pbody)
                        local ps, pdata = pcall(function() import "org.json.JSONObject" return JSONObject(pbody) end)
                        if pcode == 200 then
                            local successMsg = "Profil berhasil disimpan"
                            if ps and pdata.has("message") then successMsg = pdata.getString("message") end
                            triggerAccessibilityAnnouncement(successMsg)
                            pDialog.dismiss()
                        else
                            pViews.btnSaveProfile.setEnabled(true)
                            pViews.btnSaveProfile.setText("Simpan")
                            local errMsg = "Terjadi kesalahan jaringan"
                            if ps and pdata.has("error") then errMsg = pdata.getString("error") end
                            triggerAccessibilityAnnouncement(errMsg)
                        end
                    end)
                end
                
                pDialog.show()
            else
                local sErrMsg = "Terjadi kesalahan jaringan"
                if s and data.has("error") then sErrMsg = data.getString("error") end
                triggerAccessibilityAnnouncement(sErrMsg)
            end
        end)
    end

    sViews.btnResetPassword.onClick = function()
        if user_email == "" then
            triggerAccessibilityAnnouncement("Email pengguna tidak ditemukan")
            return
        end
        local builder = AlertDialog.Builder(ctx, 5)
        builder.setMessage("Kirim tautan atur ulang kata sandi ke " .. user_email .. "?")
        builder.setPositiveButton("Kirim", DialogInterface.OnClickListener{
            onClick = function()
                task(function(t_email)
                    require "import"
                    import "java.net.URL"
                    import "java.io.DataOutputStream"
                    import "java.net.URLEncoder"
                    import "java.io.BufferedReader"
                    import "java.io.InputStreamReader"
                    import "org.json.JSONObject"
                    
                    local code = -1
                    local resBody = ""
                    pcall(function()
                        local urlStr = "http://botspark.de1.octavia.id:25701/api/resetPassword"
                        local data = "email=" .. URLEncoder.encode(t_email, "UTF-8")
                        local url = URL(urlStr)
                        local conn = url.openConnection()
                        conn.setConnectTimeout(15000)
                        conn.setReadTimeout(15000)
                        conn.setRequestMethod("POST")
                        conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                        conn.setDoOutput(true)
                        
                        local out = DataOutputStream(conn.getOutputStream())
                        out.writeBytes(data)
                        out.flush()
                        out.close()
                        
                        code = conn.getResponseCode()
                        local isStream = (code >= 200 and code < 300) and conn.getInputStream() or conn.getErrorStream()
                        if isStream then
                            local br = BufferedReader(InputStreamReader(isStream))
                            local line = br.readLine()
                            while line ~= nil do
                                resBody = resBody .. line
                                line = br.readLine()
                            end
                            br.close()
                        end
                    end)
                    return code, resBody
                end, user_email, function(code, body)
                    local s, data = pcall(function() return JSONObject(body) end)
                    if code == 200 then
                        local successMsg = "Berhasil"
                        if s and data.has("message") then successMsg = data.getString("message") end
                        triggerAccessibilityAnnouncement(successMsg)
                    else
                        local errMsg = "Gagal mengirim permintaan"
                        if s and data.has("error") then errMsg = data.getString("error") end
                        triggerAccessibilityAnnouncement(errMsg)
                    end
                end)
            end
        })
        builder.setNegativeButton("Batal", nil)
        local confirmDialog = builder.create()
        local dWindow = confirmDialog.getWindow()
        if Build.VERSION.SDK_INT >= 22 then
            dWindow.setType(2032)
        else
            dWindow.setType(2003)
        end
        confirmDialog.show()
    end

    sViews.btnLogout.onClick = function()
        local builder = AlertDialog.Builder(ctx, 5)
        builder.setMessage("Apakah Anda yakin ingin keluar dari akun?")
        builder.setPositiveButton("Keluar", DialogInterface.OnClickListener{
            onClick = function()
                auth_token = ""
                auth_refresh_token = ""
                user_email = ""
                saveAuthConfig()
                triggerAccessibilityAnnouncement("Berhasil keluar dari akun")
                sDialog.dismiss()
                dialog.dismiss()
                showAuthDialog()
            end
        })
        builder.setNegativeButton("Batal", nil)
        
        local confirmDialog = builder.create()
        local dWindow = confirmDialog.getWindow()
        if Build.VERSION.SDK_INT >= 22 then
            dWindow.setType(2032)
        else
            dWindow.setType(2003)
        end
        confirmDialog.show()
    end

    sViews.btnSettingsFilter.onClick = function()
        local popMenu = PopupMenu(ctx, sViews.btnSettingsFilter)
        local menu = popMenu.getMenu()
        menu.add(0, 1, 0, "Semua Pengaturan")
        menu.add(0, 2, 0, "Pengaturan Umum")
        menu.add(0, 3, 0, "Pengaturan Penerjemah")
        menu.add(0, 4, 0, "Pengaturan Notifikasi")
        menu.add(0, 5, 0, "Pengaturan Pengetikan Suara")
        menu.add(0, 6, 0, "Profil Pengguna")
        menu.add(0, 7, 0, "Pengaturan Akun")
        menu.add(0, 8, 0, "Informasi Aplikasi")
        
        local closeItem = menu.add(0, 99, 0, "Tutup Menu")
        pcall(function()
            closeItem.setIcon(BitmapDrawable(ctx.getResources(), createEmojiBitmap("X", 100, 70, 30, 75)))
            if Build.VERSION.SDK_INT >= 26 then
                closeItem.setContentDescription("Tutup Menu")
            end
        end)
        
        popMenu.setOnMenuItemClickListener(PopupMenu.OnMenuItemClickListener{
            onMenuItemClick = function(item)
                local title = tostring(item.getTitle())
                if title == "Semua Pengaturan" then
                    sViews.settingsSearchInput.setText("")
                else
                    sViews.settingsSearchInput.setText("")
                    local container = sViews.settingsContainer
                    local currentCategory = ""
                    for i = 0, container.getChildCount() - 1 do
                        local child = container.getChildAt(i)
                        local className = child.getClass().getSimpleName()
                        if className == "TextView" then
                            currentCategory = tostring(child.getText())
                            child.setVisibility((currentCategory == title) and 0 or 8)
                        elseif className == "LinearLayout" then
                            child.setVisibility((currentCategory == title) and 0 or 8)
                        end
                    end
                end
                return true
            end
        })
        popMenu.show()
    end
    
    sViews.btnCheckUpdate.onClick = function()
        checkForUpdates(true)
    end

    sViews.btnBackSettings.onClick = function()
        sDialog.dismiss()
    end
    
    sDialog.show()
end

local function showInfoDialog()
    local infoLayout = {
        LinearLayout,
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "fill",
        backgroundColor = "#E5DDD5",
        {
            FrameLayout,
            layout_width = "fill",
            layout_height = "wrap",
            {
                LinearLayout,
                id = "infoTopBarNormal",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#075E54",
                gravity = "center_vertical",
                orientation = "horizontal",
                {
                    ImageView,
                    id = "btnBackInfo",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginLeft = "4dp"
                },
                {
                    LinearLayout,
                    orientation = "vertical",
                    layout_width = "0dp",
                    layout_weight = "1",
                    layout_marginLeft = "12dp",
                    {
                        TextView,
                        id = "tvInfoTitleMain",
                        text = "Informasi Terkini",
                        textSize = "20sp",
                        textColor = "#FFFFFF"
                    }
                },
                {
                    TextView,
                    id = "btnInfoVoiceSpeed",
                    layout_width = "wrap",
                    layout_height = "48dp",
                    gravity = "center",
                    padding = "8dp",
                    text = "1.0x",
                    textColor = "#FFFFFF",
                    textSize = "16sp",
                    visibility = 8,
                    contentDescription = "Kecepatan suara 1.0 kali"
                },
                {
                    ImageView,
                    id = "btnInfoMore",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginRight = "4dp",
                    contentDescription = "Opsi Lainnya"
                }
            },
            {
                LinearLayout,
                id = "infoTopBarFiltered",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#075E54",
                gravity = "center_vertical",
                orientation = "horizontal",
                visibility = 8,
                {
                    ImageView,
                    id = "btnBackInfoFiltered",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginLeft = "4dp",
                    contentDescription = "Kembali"
                },
                {
                    TextView,
                    id = "tvInfoFilteredTitle",
                    text = "",
                    textSize = "22sp",
                    textColor = "#FFFFFF",
                    layout_marginLeft = "16dp",
                    layout_weight = "1"
                }
            },
            {
                LinearLayout,
                id = "infoTopBarSearch",
                layout_width = "fill",
                layout_height = "wrap",
                backgroundColor = "#FFFFFF",
                orientation = "vertical",
                visibility = 8,
                {
                    LinearLayout,
                    layout_width = "fill",
                    layout_height = "60dp",
                    gravity = "center_vertical",
                    orientation = "horizontal",
                    {
                        EditText,
                        id = "infoSearchInput",
                        layout_width = "fill",
                        layout_height = "wrap",
                        layout_weight = "1",
                        hint = "Cari informasi...",
                        textSize = "16sp",
                        singleLine = true,
                        imeOptions = 3,
                        layout_marginLeft = "16dp"
                    },
                    {
                        ImageView,
                        id = "btnInfoCloseSearch",
                        layout_width = "48dp",
                        layout_height = "48dp",
                        padding = "8dp",
                        layout_marginRight = "4dp",
                        contentDescription = "Tutup Pencarian"
                    }
                },
                {
                    LinearLayout,
                    id = "infoSearchNavContainer",
                    layout_width = "fill",
                    layout_height = "48dp",
                    gravity = "center_vertical",
                    orientation = "horizontal",
                    backgroundColor = "#F0F0F0",
                    visibility = 8,
                    {
                        ImageView,
                        id = "btnInfoPrevSearch",
                        layout_width = "48dp",
                        layout_height = "48dp",
                        padding = "8dp",
                        layout_marginLeft = "8dp",
                        contentDescription = "Hasil Sebelumnya"
                    },
                    {
                        TextView,
                        id = "tvInfoSearchStatus",
                        layout_width = "fill",
                        layout_height = "wrap",
                        layout_weight = "1",
                        gravity = "center",
                        text = "",
                        textColor = "#888888",
                        textSize = "14sp"
                    },
                    {
                        ImageView,
                        id = "btnInfoNextSearch",
                        layout_width = "48dp",
                        layout_height = "48dp",
                        padding = "8dp",
                        layout_marginRight = "8dp",
                        contentDescription = "Hasil Berikutnya"
                    }
                }
            },
            {
                LinearLayout,
                id = "infoTopBarSelection",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#00897B",
                gravity = "center_vertical",
                orientation = "horizontal",
                visibility = 8,
                {
                    ImageView,
                    id = "btnInfoCloseSelection",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginLeft = "4dp",
                    contentDescription = "Keluar Pemilihan"
                },
                {
                    TextView,
                    id = "tvInfoSelectionCount",
                    text = "0",
                    textSize = "22sp",
                    textColor = "#FFFFFF",
                    layout_marginLeft = "16dp",
                    layout_weight = "1"
                },
                {
                    ImageView,
                    id = "btnInfoDeselectAll",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginRight = "4dp",
                    contentDescription = "Batalkan Pilihan"
                },
                {
                    ImageView,
                    id = "btnInfoSelectAll",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "8dp",
                    layout_marginRight = "4dp",
                    contentDescription = "Pilih Semua"
                }
            }
        },
        {
            LinearLayout,
            orientation = "vertical",
            layout_width = "fill",
            layout_height = "fill",
            layout_weight = "1",
            {
                LinearLayout,
                id = "infoPinnedMessageContainer",
                layout_width = "fill",
                layout_height = "wrap",
                backgroundColor = "#FFFFFF",
                visibility = 8,
                orientation = "horizontal",
                gravity = "center_vertical",
                paddingTop = "8dp",
                paddingBottom = "8dp",
                {
                    View,
                    layout_width = "4dp",
                    layout_height = "fill",
                    backgroundColor = "#075E54"
                },
                {
                    LinearLayout,
                    orientation = "vertical",
                    layout_width = "0dp",
                    layout_weight = "1",
                    layout_height = "wrap",
                    paddingLeft = "12dp",
                    {
                        TextView,
                        id = "tvInfoPinnedLabel",
                        text = "Informasi Tersemat",
                        textColor = "#075E54",
                        textSize = "14sp"
                    },
                    {
                        TextView,
                        id = "tvInfoPinnedMessage",
                        textColor = "#555555",
                        textSize = "14sp",
                        singleLine = true,
                        ellipsize = "end"
                    }
                }
            },
            {
                FrameLayout,
                layout_width = "fill",
                layout_height = "fill",
                layout_weight = "1",
                {
                    ScrollView,
                    id = "infoScrollView",
                    layout_width = "fill",
                    layout_height = "fill",
                    fillViewport = "true",
                    {
                        LinearLayout,
                        id = "infoContainer",
                        orientation = "vertical",
                        layout_width = "fill",
                        layout_height = "wrap",
                        padding = "16dp"
                    }
                },
                {
                    TextView,
                    id = "emptyInfoText",
                    text = "Belum ada informasi",
                    layout_width = "wrap",
                    layout_height = "wrap",
                    layout_gravity = "center",
                    textColor = "#888888",
                    textSize = "16sp"
                }
            }
        },
        {
            LinearLayout,
            id = "infoBottomSelectionBar",
            layout_width = "fill",
            layout_height = "wrap",
            orientation = "horizontal",
            gravity = "center",
            padding = "8dp",
            backgroundColor = "#F0F0F0",
            visibility = 8,
            {
                ImageView,
                id = "btnInfoCopySelection",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                layout_marginRight = "8dp",
                contentDescription = "Salin"
            },
            {
                ImageView,
                id = "btnInfoTranslateSelection",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                layout_marginLeft = "8dp",
                layout_marginRight = "8dp",
                contentDescription = "Terjemahkan"
            },
            {
                ImageView,
                id = "btnInfoStarSelection",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                layout_marginLeft = "8dp",
                layout_marginRight = "8dp",
                contentDescription = "Bintangi"
            },
            {
                ImageView,
                id = "btnInfoPinSelection",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                layout_marginLeft = "8dp",
                layout_marginRight = "8dp",
                contentDescription = "Sematkan"
            },
            {
                ImageView,
                id = "btnInfoDeleteSelection",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                layout_marginLeft = "8dp",
                contentDescription = "Hapus"
            },
            {
                ImageView,
                id = "btnInfoDownloadSelection",
                layout_width = "48dp",
                layout_height = "48dp",
                padding = "8dp",
                layout_marginLeft = "8dp",
                contentDescription = "Unduh"
            }
        }
    }
    
    local iViews = {}
    local iContentView = loadlayout(infoLayout, iViews)
    
    iViews.btnBackInfo.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
    iViews.btnBackInfo.setContentDescription("Kembali")
    iViews.emptyInfoText.setTypeface(Typeface.defaultFromStyle(Typeface.ITALIC))
    
    iViews.tvInfoTitleMain.setTypeface(Typeface.DEFAULT_BOLD)
    iViews.tvInfoFilteredTitle.setTypeface(Typeface.DEFAULT_BOLD)
    iViews.tvInfoSearchStatus.setTypeface(Typeface.DEFAULT_BOLD)
    iViews.tvInfoSelectionCount.setTypeface(Typeface.DEFAULT_BOLD)
    iViews.tvInfoPinnedLabel.setTypeface(Typeface.DEFAULT_BOLD)

    iViews.btnInfoVoiceSpeed.setTypeface(Typeface.DEFAULT_BOLD)
    iViews.btnInfoVoiceSpeed.setText(string.format("%.1fx", voice_playback_speed))
    iViews.btnInfoVoiceSpeed.setContentDescription("Kecepatan suara " .. string.format("%.1fx", voice_playback_speed))
    iViews.btnInfoVoiceSpeed.onClick = function(v)
        if voice_playback_speed == 1.0 then
            voice_playback_speed = 1.5
        elseif voice_playback_speed == 1.5 then
            voice_playback_speed = 2.0
        else
            voice_playback_speed = 1.0
        end
        
        saveTransConfig()
        
        local speedText = string.format("%.1fx", voice_playback_speed)
        iViews.btnInfoVoiceSpeed.setText(speedText)
        iViews.btnInfoVoiceSpeed.setContentDescription("Kecepatan suara " .. speedText)
        
        if chatMediaPlayer and chatMediaPlayer.isPlaying() and Build.VERSION.SDK_INT >= 23 then
            pcall(function()
                chatMediaPlayer.setPlaybackParams(chatMediaPlayer.getPlaybackParams().setSpeed(voice_playback_speed))
            end)
        end
    end

    iViews.btnInfoMore.setImageBitmap(createEmojiBitmap("站ｮ", 100, 70, 35, 75))
    iViews.btnInfoMore.setContentDescription("Opsi Lainnya")
    iViews.btnBackInfoFiltered.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
    iViews.btnInfoCloseSearch.setImageBitmap(createEmojiBitmap("X", 100, 70, 30, 75))
    iViews.btnInfoPrevSearch.setImageBitmap(createEmojiBitmap("▲", 100, 50, 25, 70))
    iViews.btnInfoNextSearch.setImageBitmap(createEmojiBitmap("▼", 100, 50, 25, 70))
    iViews.btnInfoCloseSelection.setImageBitmap(createEmojiBitmap("X", 100, 70, 30, 75))
    iViews.btnInfoDeselectAll.setImageBitmap(createEmojiBitmap("☐", 100, 70, 25, 75))
    iViews.btnInfoSelectAll.setImageBitmap(createEmojiBitmap("☑", 100, 70, 25, 75))

    iViews.btnInfoCopySelection.setImageBitmap(createEmojiBitmap("📋", 100, 60, 20, 75))
    iViews.btnInfoTranslateSelection.setImageBitmap(createEmojiBitmap("🌐", 100, 60, 20, 75))
    iViews.btnInfoStarSelection.setImageBitmap(bmpStar)
    iViews.btnInfoPinSelection.setImageBitmap(bmpPin)
    iViews.btnInfoDeleteSelection.setImageBitmap(createEmojiBitmap("🗑", 100, 60, 20, 75))
    iViews.btnInfoDownloadSelection.setImageBitmap(createEmojiBitmap("⬇", 100, 60, 20, 75))

    iViews.btnInfoPrevSearch.setEnabled(false)
    iViews.btnInfoPrevSearch.setAlpha(0.5)
    iViews.btnInfoNextSearch.setEnabled(false)
    iViews.btnInfoNextSearch.setAlpha(0.5)

    local iDialog = Dialog(ctx)
    iDialog.requestWindowFeature(1)
    iDialog.setContentView(iContentView)
    
    local w = iDialog.getWindow()
    if Build.VERSION.SDK_INT >= 22 then
        w.setType(2032)
    else
        w.setType(2003)
    end
    w.setBackgroundDrawable(ColorDrawable(0xffE5DDD5))
    w.setLayout(-1, -1)
    w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    
    iViews.btnBackInfo.onClick = function()
        pcall(function()
            if chatMediaPlayer then
                if chatMediaPlayer.isPlaying() then chatMediaPlayer.stop() end
                chatMediaPlayer.release()
                chatMediaPlayer = nil
                activeVoiceView = nil
                iViews.btnInfoVoiceSpeed.setVisibility(8)
            end
        end)
        iDialog.dismiss()
    end

    local function refreshInfoPinnedDisplay()
        if currentInfoFilterMode ~= "normal" then
            iViews.infoPinnedMessageContainer.setVisibility(8)
            return
        end
        if #infoPinnedStack > 0 then
            if currentInfoPinnedDisplayIndex < 1 or currentInfoPinnedDisplayIndex > #infoPinnedStack then
                currentInfoPinnedDisplayIndex = #infoPinnedStack
            end
            local msgIdx = infoPinnedStack[currentInfoPinnedDisplayIndex]
            local msg = info_history.messages[msgIdx]
            if msg then
                iViews.tvInfoPinnedMessage.setText(msg.text)
                iViews.infoPinnedMessageContainer.setVisibility(0)
                return
            end
        end
        iViews.infoPinnedMessageContainer.setVisibility(8)
    end

    local function applyInfoFilter()
        if currentInfoFilterMode == "normal" then
            iViews.infoTopBarFiltered.setVisibility(8)
            iViews.infoTopBarNormal.setVisibility(0)
            refreshInfoPinnedDisplay()
            for i = 0, iViews.infoContainer.getChildCount() - 1 do
                iViews.infoContainer.getChildAt(i).setVisibility(0)
            end
            iViews.emptyInfoText.setText("Belum ada informasi")
            if iViews.infoContainer.getChildCount() == 0 then
                iViews.emptyInfoText.setVisibility(0)
            else
                iViews.emptyInfoText.setVisibility(8)
            end
        else
            iViews.infoTopBarNormal.setVisibility(8)
            iViews.infoTopBarSearch.setVisibility(8)
            iViews.infoSearchNavContainer.setVisibility(8)
            iViews.infoPinnedMessageContainer.setVisibility(8)
            iViews.infoTopBarFiltered.setVisibility(0)
            
            local count = 0
            for i = 0, iViews.infoContainer.getChildCount() - 1 do
                local msg = info_history.messages[i + 1]
                local v = iViews.infoContainer.getChildAt(i)
                local show = false
                if currentInfoFilterMode == "starred" and msg.is_starred then show = true end
                if currentInfoFilterMode == "pinned" and msg.is_pinned then show = true end
                
                if show then
                    v.setVisibility(0)
                    count = count + 1
                else
                    v.setVisibility(8)
                end
            end
            
            if currentInfoFilterMode == "starred" then
                iViews.tvInfoFilteredTitle.setText("Informasi Berbintang (" .. count .. ")")
            else
                iViews.tvInfoFilteredTitle.setText("Informasi Tersemat (" .. count .. ")")
            end
            
            if count == 0 then
                iViews.emptyInfoText.setText("Tidak ada informasi " .. (currentInfoFilterMode == "starred" and "berbintang" or "tersemat"))
                iViews.emptyInfoText.setVisibility(0)
            else
                iViews.emptyInfoText.setVisibility(8)
            end
        end
    end

    iViews.btnBackInfoFiltered.onClick = function()
        currentInfoFilterMode = "normal"
        applyInfoFilter()
    end

    local function updateInfoMessageDescription(tv)
        local idx = iViews.infoContainer.indexOfChild(tv) + 1
        local msg = info_history.messages[idx]
        if not msg then return end
        
        local desc = tostring(tv.getText())
        
        if msg.is_starred then desc = desc .. ", informasi dibintangi" end
        if msg.is_pinned then desc = desc .. ", informasi disematkan" end
        
        if isInfoSelectionMode then
            local isSelected = false
            for _, v in ipairs(selectedInfoViews) do
                if v == tv then
                    isSelected = true
                    break
                end
            end
            if isSelected then
                desc = "Dipilih, " .. desc
            else
                desc = "Tidak dipilih, " .. desc
            end
        end
        tv.setContentDescription(desc)
    end

    local function updateInfoSelectionUI()
        local count = #selectedInfoViews
        if count == 0 then
            isInfoSelectionMode = false
            iViews.infoTopBarSelection.setVisibility(8)
            iViews.infoBottomSelectionBar.setVisibility(8)
            
            if currentInfoFilterMode == "normal" then
                iViews.infoTopBarNormal.setVisibility(0)
            else
                applyInfoFilter()
            end
            
            for i = 0, iViews.infoContainer.getChildCount() - 1 do
                local v = iViews.infoContainer.getChildAt(i)
                v.setBackgroundColor(0xFFFFFFFF)
                updateInfoMessageDescription(v)
            end
        else
            iViews.tvInfoSelectionCount.setText(tostring(count))
            
            local isAllStarred = true
            local isAllPinned = true
            local hasMedia = false
            local hasDownloadable = false
            for _, v in ipairs(selectedInfoViews) do
                local idx = iViews.infoContainer.indexOfChild(v) + 1
                local msg = info_history.messages[idx]
                if not msg.is_starred then isAllStarred = false end
                if not msg.is_pinned then isAllPinned = false end
                if msg.audio_path or msg.media_path then hasMedia = true; hasDownloadable = true end
            end
            
            if hasMedia then
                iViews.btnInfoCopySelection.setVisibility(8)
                iViews.btnInfoTranslateSelection.setVisibility(8)
            else
                iViews.btnInfoCopySelection.setVisibility(0)
                iViews.btnInfoTranslateSelection.setVisibility(0)
            end

            if hasDownloadable then
                iViews.btnInfoDownloadSelection.setVisibility(0)
            else
                iViews.btnInfoDownloadSelection.setVisibility(8)
            end
            
            if isAllStarred then
                iViews.btnInfoStarSelection.setImageBitmap(bmpUnstar)
                iViews.btnInfoStarSelection.setContentDescription("Hapus Bintang")
            else
                iViews.btnInfoStarSelection.setImageBitmap(bmpStar)
                iViews.btnInfoStarSelection.setContentDescription("Bintangi")
            end
            
            if isAllPinned then
                iViews.btnInfoPinSelection.setImageBitmap(bmpUnpin)
                iViews.btnInfoPinSelection.setContentDescription("Lepas Sematan")
            else
                iViews.btnInfoPinSelection.setImageBitmap(bmpPin)
                iViews.btnInfoPinSelection.setContentDescription("Sematkan")
            end
        end
    end

    local function toggleInfoSelection(tv)
        local foundIdx = -1
        for i, v in ipairs(selectedInfoViews) do
            if v == tv then
                foundIdx = i
                break
            end
        end
        
        if foundIdx > 0 then
            table.remove(selectedInfoViews, foundIdx)
            tv.setBackgroundColor(0xFFFFFFFF)
        else
            table.insert(selectedInfoViews, tv)
            tv.setBackgroundColor(0xFF90CAF9)
        end
        
        updateInfoMessageDescription(tv)
        updateInfoSelectionUI()
    end

    iViews.btnInfoCloseSelection.onClick = function()
        selectedInfoViews = {}
        updateInfoSelectionUI()
    end

    iViews.btnInfoDeselectAll.onClick = function()
        for _, tv in ipairs(selectedInfoViews) do
            tv.setBackgroundColor(0xFFFFFFFF)
        end
        selectedInfoViews = {}
        updateInfoSelectionUI()
        for i = 0, iViews.infoContainer.getChildCount() - 1 do
            local child = iViews.infoContainer.getChildAt(i)
            updateInfoMessageDescription(child)
        end
    end

    iViews.btnInfoSelectAll.onClick = function()
        selectedInfoViews = {}
        for i = 0, iViews.infoContainer.getChildCount() - 1 do
            local tv = iViews.infoContainer.getChildAt(i)
            if tv.getVisibility() == 0 then
                table.insert(selectedInfoViews, tv)
                tv.setBackgroundColor(0xFF90CAF9)
                updateInfoMessageDescription(tv)
            end
        end
        updateInfoSelectionUI()
    end

    iViews.btnInfoCopySelection.onClick = function()
        if #selectedInfoViews > 0 then
            local sortedViews = {}
            for i, v in ipairs(selectedInfoViews) do
                table.insert(sortedViews, {view = v, index = iViews.infoContainer.indexOfChild(v)})
            end
            table.sort(sortedViews, function(a, b) return a.index < b.index end)
            
            local copyText = ""
            for i, item in ipairs(sortedViews) do
                if i > 1 then copyText = copyText .. "\n" end
                copyText = copyText .. tostring(item.view.getText())
            end
            
            local clipboard = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
            local clip = ClipData.newPlainText("Informasi", copyText)
            clipboard.setPrimaryClip(clip)
            
            triggerAccessibilityAnnouncement("Informasi disalin")
            
            selectedInfoViews = {}
            updateInfoSelectionUI()
        end
    end

    iViews.btnInfoTranslateSelection.onClick = function()
        if #selectedInfoViews > 0 then
            local sortedViews = {}
            for i, v in ipairs(selectedInfoViews) do
                table.insert(sortedViews, {view = v, index = iViews.infoContainer.indexOfChild(v)})
            end
            table.sort(sortedViews, function(a, b) return a.index < b.index end)
            
            local textToTranslate = ""
            for i, item in ipairs(sortedViews) do
                if i > 1 then textToTranslate = textToTranslate .. "\n" end
                local msg = info_history.messages[item.index + 1]
                if msg then
                    textToTranslate = textToTranslate .. msg.text
                end
            end
            
            selectedInfoViews = {}
            updateInfoSelectionUI()
            
            showTranslationDialog(textToTranslate)
        end
    end

    iViews.btnInfoStarSelection.onClick = function()
        if #selectedInfoViews > 0 then
            local isAllStarred = true
            for _, v in ipairs(selectedInfoViews) do
                local idx = iViews.infoContainer.indexOfChild(v) + 1
                if not info_history.messages[idx].is_starred then
                    isAllStarred = false
                    break
                end
            end
            
            local newState = not isAllStarred
            for _, v in ipairs(selectedInfoViews) do
                local idx = iViews.infoContainer.indexOfChild(v) + 1
                local msg = info_history.messages[idx]
                msg.is_starred = newState
                
                local leftD = msg.is_pinned and pinIndicator or nil
                local rightD = msg.is_starred and starIndicator or nil
                v.setCompoundDrawablesWithIntrinsicBounds(leftD, nil, rightD, nil)
                updateInfoMessageDescription(v)
            end
            saveInfoHistory()
            selectedInfoViews = {}
            updateInfoSelectionUI()
        end
    end

    iViews.btnInfoPinSelection.onClick = function()
        if #selectedInfoViews > 0 then
            local tv = selectedInfoViews[1]
            local idx = iViews.infoContainer.indexOfChild(tv) + 1
            local msg = info_history.messages[idx]
            
            if msg.is_pinned then
                msg.is_pinned = false
                for i, pIdx in ipairs(infoPinnedStack) do
                    if pIdx == idx then
                        table.remove(infoPinnedStack, i)
                        break
                    end
                end
                currentInfoPinnedDisplayIndex = #infoPinnedStack
                refreshInfoPinnedDisplay()
                
                local leftD = msg.is_pinned and pinIndicator or nil
                local rightD = msg.is_starred and starIndicator or nil
                tv.setCompoundDrawablesWithIntrinsicBounds(leftD, nil, rightD, nil)
            else
                msg.is_pinned = true
                table.insert(infoPinnedStack, idx)
                currentInfoPinnedDisplayIndex = #infoPinnedStack
                refreshInfoPinnedDisplay()
                
                local leftD = msg.is_pinned and pinIndicator or nil
                local rightD = msg.is_starred and starIndicator or nil
                tv.setCompoundDrawablesWithIntrinsicBounds(leftD, nil, rightD, nil)
            end
            
            updateInfoMessageDescription(tv)
            saveInfoHistory()
            selectedInfoViews = {}
            updateInfoSelectionUI()
        end
    end

    iViews.btnInfoDownloadSelection.onClick = function()
        if #selectedInfoViews > 0 then
            local count = 0
            for _, v in ipairs(selectedInfoViews) do
                local idx = iViews.infoContainer.indexOfChild(v) + 1
                local msg = info_history.messages[idx]
                if msg.audio_path then
                    downloadMediaToTexaFolder(msg.audio_path)
                    count = count + 1
                end
                if msg.media_path then
                    downloadMediaToTexaFolder(msg.media_path)
                    count = count + 1
                end
            end
            if count == 0 then
                triggerAccessibilityAnnouncement("Tidak ada file media yang dapat diunduh pada informasi yang dipilih")
            end
            selectedInfoViews = {}
            updateInfoSelectionUI()
        end
    end

    iViews.btnInfoDeleteSelection.onClick = function()
        local count = #selectedInfoViews
        if count > 0 then
            local builder = AlertDialog.Builder(ctx, 5)
            builder.setMessage("Hapus " .. count .. " informasi yang dipilih?")
            builder.setPositiveButton("Hapus", DialogInterface.OnClickListener{
                onClick = function()
                    local indexesToRemove = {}
                    for _, v in ipairs(selectedInfoViews) do
                        table.insert(indexesToRemove, iViews.infoContainer.indexOfChild(v) + 1)
                    end
                    table.sort(indexesToRemove, function(a, b) return a > b end)
                    
                    for _, idx in ipairs(indexesToRemove) do
                        local msg = info_history.messages[idx]
                        if msg.audio_path then pcall(function() File(msg.audio_path).delete() end) end
                        if msg.media_path then pcall(function() File(msg.media_path).delete() end) end
                        iViews.infoContainer.removeViewAt(idx - 1)
                        table.remove(info_history.messages, idx)
                    end
                    
                    infoPinnedStack = {}
                    for i, msg in ipairs(info_history.messages) do
                        if msg.is_pinned then
                            table.insert(infoPinnedStack, i)
                        end
                    end
                    currentInfoPinnedDisplayIndex = #infoPinnedStack
                    refreshInfoPinnedDisplay()
                    
                    saveInfoHistory()
                    
                    if currentInfoFilterMode == "normal" and iViews.infoContainer.getChildCount() == 0 then
                        iViews.emptyInfoText.setVisibility(0)
                    end
                    
                    selectedInfoViews = {}
                    updateInfoSelectionUI()
                end
            })
            builder.setNegativeButton("Batal", nil)
            
            local confirmDialog = builder.create()
            local dWindow = confirmDialog.getWindow()
            if Build.VERSION.SDK_INT >= 22 then
                dWindow.setType(2032)
            else
                dWindow.setType(2003)
            end
            confirmDialog.show()
        end
    end

    iViews.infoPinnedMessageContainer.onClick = function()
        if #infoPinnedStack > 0 then
            local targetMsgIdx = infoPinnedStack[currentInfoPinnedDisplayIndex]
            local targetView = iViews.infoContainer.getChildAt(targetMsgIdx - 1)
            if targetView then
                iViews.infoScrollView.scrollTo(0, targetView.getTop() - 50)
            end
            currentInfoPinnedDisplayIndex = currentInfoPinnedDisplayIndex - 1
            if currentInfoPinnedDisplayIndex < 1 then
                currentInfoPinnedDisplayIndex = #infoPinnedStack
            end
            refreshInfoPinnedDisplay()
        end
    end

    iViews.infoPinnedMessageContainer.onLongClick = function()
        if #infoPinnedStack > 0 then
            local msgIdx = infoPinnedStack[currentInfoPinnedDisplayIndex]
            info_history.messages[msgIdx].is_pinned = false
            table.remove(infoPinnedStack, currentInfoPinnedDisplayIndex)
            currentInfoPinnedDisplayIndex = #infoPinnedStack
            
            local oldView = iViews.infoContainer.getChildAt(msgIdx - 1)
            if oldView then
                local msg = info_history.messages[msgIdx]
                local leftD = msg.is_pinned and pinIndicator or nil
                local rightD = msg.is_starred and starIndicator or nil
                oldView.setCompoundDrawablesWithIntrinsicBounds(leftD, nil, rightD, nil)
                updateInfoMessageDescription(oldView)
            end
            saveInfoHistory()
        end
        refreshInfoPinnedDisplay()
        return true
    end

    local function updateInfoSearchStatus()
        if #infoSearchResults == 0 then
            iViews.tvInfoSearchStatus.setText("Tidak ditemukan")
            iViews.btnInfoPrevSearch.setEnabled(false)
            iViews.btnInfoPrevSearch.setAlpha(0.5)
            iViews.btnInfoNextSearch.setEnabled(false)
            iViews.btnInfoNextSearch.setAlpha(0.5)
        else
            iViews.tvInfoSearchStatus.setText(currentInfoSearchIndex .. " / " .. #infoSearchResults)
            
            if currentInfoSearchIndex <= 1 then
                iViews.btnInfoPrevSearch.setEnabled(false)
                iViews.btnInfoPrevSearch.setAlpha(0.5)
            else
                iViews.btnInfoPrevSearch.setEnabled(true)
                iViews.btnInfoPrevSearch.setAlpha(1.0)
            end
            
            if currentInfoSearchIndex >= #infoSearchResults then
                iViews.btnInfoNextSearch.setEnabled(false)
                iViews.btnInfoNextSearch.setAlpha(0.5)
            else
                iViews.btnInfoNextSearch.setEnabled(true)
                iViews.btnInfoNextSearch.setAlpha(1.0)
            end
            
            for i, v in ipairs(infoSearchResults) do
                if i == currentInfoSearchIndex then
                    v.setBackgroundColor(0xFF90CAF9)
                else
                    v.setBackgroundColor(0xFFFFFFFF)
                end
            end
            
            handler.post(Runnable{
                run = function()
                    local targetView = infoSearchResults[currentInfoSearchIndex]
                    if targetView then
                        iViews.infoScrollView.scrollTo(0, targetView.getTop() - 50)
                    end
                end
            })
        end
    end

    iViews.infoSearchInput.setOnEditorActionListener(TextView.OnEditorActionListener{
        onEditorAction = function(v, actionId, event)
            if actionId == 3 or (event and event.getKeyCode() == 66 and event.getAction() == 0) then
                local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
                imm.hideSoftInputFromWindow(v.getWindowToken(), 0)
                
                iViews.infoSearchNavContainer.setVisibility(0)
                
                local query = string.lower(tostring(v.getText()))
                infoSearchResults = {}
                for i = 0, iViews.infoContainer.getChildCount() - 1 do
                    local tv = iViews.infoContainer.getChildAt(i)
                    local text = string.lower(tostring(tv.getText()))
                    tv.setBackgroundColor(0xFFFFFFFF)
                    
                    if query ~= "" and string.find(text, query, 1, true) then
                        table.insert(infoSearchResults, tv)
                    end
                end
                
                if query == "" then
                    iViews.tvInfoSearchStatus.setText("")
                    iViews.btnInfoPrevSearch.setEnabled(false)
                    iViews.btnInfoPrevSearch.setAlpha(0.5)
                    iViews.btnInfoNextSearch.setEnabled(false)
                    iViews.btnInfoNextSearch.setAlpha(0.5)
                    iViews.infoSearchNavContainer.setVisibility(8)
                else
                    if #infoSearchResults > 0 then
                        currentInfoSearchIndex = #infoSearchResults
                    else
                        currentInfoSearchIndex = 0
                    end
                    updateInfoSearchStatus()
                end
                return true
            end
            return false
        end
    })

    iViews.btnInfoPrevSearch.onClick = function()
        if currentInfoSearchIndex > 1 then
            currentInfoSearchIndex = currentInfoSearchIndex - 1
            updateInfoSearchStatus()
        end
    end

    iViews.btnInfoNextSearch.onClick = function()
        if currentInfoSearchIndex < #infoSearchResults then
            currentInfoSearchIndex = currentInfoSearchIndex + 1
            updateInfoSearchStatus()
        end
    end

    iViews.btnInfoCloseSearch.onClick = function()
        iViews.infoTopBarSearch.setVisibility(8)
        iViews.infoSearchNavContainer.setVisibility(8)
        iViews.infoTopBarNormal.setVisibility(0)
        iViews.infoSearchInput.setText("")
        iViews.tvInfoSearchStatus.setText("")
        
        for i = 0, iViews.infoContainer.getChildCount() - 1 do
            local tv = iViews.infoContainer.getChildAt(i)
            tv.setBackgroundColor(0xFFFFFFFF)
        end
        
        infoSearchResults = {}
        currentInfoSearchIndex = 0
        
        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
        imm.hideSoftInputFromWindow(iViews.infoSearchInput.getWindowToken(), 0)
    end

    iViews.btnInfoMore.onClick = function()
        local popMenu = PopupMenu(ctx, iViews.btnInfoMore)
        local menu = popMenu.getMenu()
        
        local has_starred = false
        local has_pinned = false
        for _, msg in ipairs(info_history.messages) do
            if msg.is_starred then has_starred = true end
            if msg.is_pinned then has_pinned = true end
            if has_starred and has_pinned then break end
        end
        
        if #info_history.messages > 0 then
            menu.add(0, 1, 0, "Hapus Informasi")
            menu.add(0, 3, 0, "Cari Informasi")
            if has_starred then
                menu.add(0, 4, 0, "Informasi Berbintang")
            end
            if has_pinned then
                menu.add(0, 5, 0, "Informasi Tersemat")
            end
        end
        
        local closeItem = menu.add(0, 99, 0, "Tutup Menu")
        pcall(function()
            closeItem.setIcon(BitmapDrawable(ctx.getResources(), createEmojiBitmap("X", 100, 70, 30, 75)))
            if Build.VERSION.SDK_INT >= 26 then
                closeItem.setContentDescription("Tutup Menu")
            end
        end)

        popMenu.setOnMenuItemClickListener(PopupMenu.OnMenuItemClickListener{
            onMenuItemClick = function(item)
                local id = item.getItemId()
                if id == 1 then
                    local builder = AlertDialog.Builder(ctx, 5)
                    local checkBoxLayout = LinearLayout(ctx)
                    checkBoxLayout.setOrientation(1)
                    checkBoxLayout.setPadding(64, 32, 64, 0)
                    
                    local tvMessage = TextView(ctx)
                    tvMessage.setText("Apakah Anda yakin ingin menghapus riwayat informasi? Informasi yang dibintangi dan disematkan tidak akan dihapus kecuali Anda memilih opsi di bawah.")
                    tvMessage.setTextSize(16)
                    tvMessage.setTextColor(0xFF000000)
                    checkBoxLayout.addView(tvMessage)
                    
                    local cbDeleteStarred = CheckBox(ctx)
                    cbDeleteStarred.setText("Hapus juga informasi berbintang")
                    cbDeleteStarred.setTextColor(0xFF000000)
                    cbDeleteStarred.setPadding(0, 32, 0, 0)
                    checkBoxLayout.addView(cbDeleteStarred)
                    
                    local cbDeletePinned = CheckBox(ctx)
                    cbDeletePinned.setText("Hapus juga informasi tersemat")
                    cbDeletePinned.setTextColor(0xFF000000)
                    cbDeletePinned.setPadding(0, 16, 0, 0)
                    checkBoxLayout.addView(cbDeletePinned)
                    
                    builder.setView(checkBoxLayout)
                    builder.setPositiveButton("Hapus", DialogInterface.OnClickListener{
                        onClick = function()
                            local deleteStarred = cbDeleteStarred.isChecked()
                            local deletePinned = cbDeletePinned.isChecked()
                            local i = 1
                            while i <= #info_history.messages do
                                local msg = info_history.messages[i]
                                local shouldDelete = true
                                if msg.is_starred and not deleteStarred then
                                    shouldDelete = false
                                end
                                if msg.is_pinned and not deletePinned then
                                    shouldDelete = false
                                end
                                
                                if shouldDelete then
                                    if msg.audio_path then pcall(function() File(msg.audio_path).delete() end) end
                                    if msg.media_path then pcall(function() File(msg.media_path).delete() end) end
                                    iViews.infoContainer.removeViewAt(i - 1)
                                    table.remove(info_history.messages, i)
                                else
                                    i = i + 1
                                end
                            end
                            
                            infoPinnedStack = {}
                            for idx, msg in ipairs(info_history.messages) do
                                if msg.is_pinned then
                                    table.insert(infoPinnedStack, idx)
                                end
                            end
                            currentInfoPinnedDisplayIndex = #infoPinnedStack
                            refreshInfoPinnedDisplay()
                            
                            saveInfoHistory()
                            
                            if iViews.infoContainer.getChildCount() == 0 then
                                iViews.emptyInfoText.setVisibility(0)
                            end
                            
                            iViews.infoTopBarSearch.setVisibility(8)
                            iViews.infoSearchNavContainer.setVisibility(8)
                            iViews.infoTopBarSelection.setVisibility(8)
                            iViews.infoBottomSelectionBar.setVisibility(8)
                            iViews.infoTopBarFiltered.setVisibility(8)
                            iViews.infoTopBarNormal.setVisibility(0)
                            iViews.infoSearchInput.setText("")
                            iViews.tvInfoSearchStatus.setText("")
                            infoSearchResults = {}
                            currentInfoSearchIndex = 0
                            isInfoSelectionMode = false
                            selectedInfoViews = {}
                            currentInfoFilterMode = "normal"
                        end
                    })
                    builder.setNegativeButton("Batal", nil)
                    
                    local confirmDialog = builder.create()
                    local dWindow = confirmDialog.getWindow()
                    if Build.VERSION.SDK_INT >= 22 then
                        dWindow.setType(2032)
                    else
                        dWindow.setType(2003)
                    end
                    confirmDialog.show()
                elseif id == 3 then
                    iViews.infoTopBarNormal.setVisibility(8)
                    iViews.infoTopBarSearch.setVisibility(0)
                    iViews.infoSearchNavContainer.setVisibility(8)
                    iViews.infoSearchInput.requestFocus()
                    iViews.tvInfoSearchStatus.setText("")
                    iViews.btnInfoPrevSearch.setEnabled(false)
                    iViews.btnInfoPrevSearch.setAlpha(0.5)
                    iViews.btnInfoNextSearch.setEnabled(false)
                    iViews.btnInfoNextSearch.setAlpha(0.5)
                    
                    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
                    imm.showSoftInput(iViews.infoSearchInput, 0)
                elseif id == 4 then
                    currentInfoFilterMode = "starred"
                    applyInfoFilter()
                elseif id == 5 then
                    currentInfoFilterMode = "pinned"
                    applyInfoFilter()
                end
                return true
            end
        })
        popMenu.show()
    end
    
    local function appendInfoUI(text, is_starred, is_pinned, audio_path, timestamp, media_path, media_type)
        local msgTime = timestamp or os.time()
        local timeStr = os.date("%H.%M", msgTime)
        local status_text = "Diterima pada " .. timeStr
        local display_text = text .. "\n" .. status_text
        
        iViews.emptyInfoText.setVisibility(8)
        local tv = TextView(ctx)
        tv.setText(display_text)
        tv.setTextSize(16)
        tv.setTextColor(0xFF000000)
        tv.setBackgroundColor(0xFFFFFFFF)
        tv.setPadding(24, 16, 24, 16)
        
        local leftD = is_pinned and pinIndicator or nil
        local rightD = is_starred and starIndicator or nil
        tv.setCompoundDrawablesWithIntrinsicBounds(leftD, nil, rightD, nil)
        tv.setCompoundDrawablePadding(8)
        
        local lp = LinearLayout.LayoutParams(-2, -2)
        lp.setMargins(0, 0, 0, 16)
        lp.gravity = 3
        tv.setLayoutParams(lp)

        tv.onLongClick = function(v)
            if not isInfoSelectionMode then
                if iViews.infoTopBarSearch.getVisibility() == 0 then
                    iViews.btnInfoCloseSearch.performClick()
                end
                
                isInfoSelectionMode = true
                selectedInfoViews = {}
                
                iViews.infoTopBarNormal.setVisibility(8)
                iViews.infoTopBarFiltered.setVisibility(8)
                iViews.infoTopBarSearch.setVisibility(8)
                iViews.infoSearchNavContainer.setVisibility(8)
                
                iViews.infoTopBarSelection.setVisibility(0)
                iViews.infoBottomSelectionBar.setVisibility(0)
                
                local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
                imm.hideSoftInputFromWindow(iViews.infoSearchInput.getWindowToken(), 0)
                
                for i = 0, iViews.infoContainer.getChildCount() - 1 do
                    local child = iViews.infoContainer.getChildAt(i)
                    updateInfoMessageDescription(child)
                end
                
                toggleInfoSelection(v)
            end
            return true
        end
        
        tv.onClick = function(v)
            if isInfoSelectionMode then
                toggleInfoSelection(v)
            else
                if media_path then
                    local infoMediaList = {}
                    local startIdx = 1
                    for i, msg in ipairs(info_history.messages) do
                        if msg.media_path then
                            table.insert(infoMediaList, msg)
                            if msg.media_path == media_path and msg.timestamp == msgTime then
                                startIdx = #infoMediaList
                            end
                        end
                    end
                    if #infoMediaList > 0 then
                        showMediaViewerDialog(infoMediaList, startIdx)
                    end
                elseif audio_path then
                    pcall(function()
                        if chatMediaPlayer then
                            if activeVoiceView == v then
                                if chatMediaPlayer.isPlaying() then
                                    chatMediaPlayer.pause()
                                    iViews.btnInfoVoiceSpeed.setVisibility(8)
                                else
                                    chatMediaPlayer.start()
                                    iViews.btnInfoVoiceSpeed.setVisibility(0)
                                end
                                return
                            else
                                if chatMediaPlayer.isPlaying() then
                                    chatMediaPlayer.stop()
                                end
                                chatMediaPlayer.release()
                                chatMediaPlayer = nil
                                iViews.btnInfoVoiceSpeed.setVisibility(8)
                            end
                        end
                        
                        import "java.io.File"
                        import "java.io.FileInputStream"
                        local f = File(audio_path)
                        if f.exists() then
                            chatMediaPlayer = MediaPlayer()
                            local fis = FileInputStream(f)
                            chatMediaPlayer.setDataSource(fis.getFD())
                            chatMediaPlayer.setAudioStreamType(3)
                            chatMediaPlayer.prepare()
                            chatMediaPlayer.start()
                            if Build.VERSION.SDK_INT >= 23 then
                                pcall(function()
                                    chatMediaPlayer.setPlaybackParams(chatMediaPlayer.getPlaybackParams().setSpeed(voice_playback_speed))
                                end)
                            end
                            fis.close()
                            
                            activeVoiceView = v
                            local speedText = string.format("%.1fx", voice_playback_speed)
                            iViews.btnInfoVoiceSpeed.setText(speedText)
                            iViews.btnInfoVoiceSpeed.setVisibility(0)
                            
                            chatMediaPlayer.setOnCompletionListener(MediaPlayer.OnCompletionListener{
                                onCompletion = function(mp)
                                    mp.release()
                                    chatMediaPlayer = nil
                                    activeVoiceView = nil
                                    iViews.btnInfoVoiceSpeed.setVisibility(8)
                                end
                            })
                        else
                            triggerAccessibilityAnnouncement("File suara tidak ditemukan")
                        end
                    end)
                end
            end
        end
        
        iViews.infoContainer.addView(tv)
        updateInfoMessageDescription(tv)
        
        if currentInfoFilterMode ~= "normal" then
            tv.setVisibility(8)
        end
        
        handler.postDelayed(Runnable{
            run = function()
                iViews.infoScrollView.fullScroll(130)
            end
        }, 100)

        if trans_auto_info and not audio_path and not media_path then
            if trans_show_original then
                tv.setText(text .. "\n\n(Menerjemahkan...)\n" .. status_text)
            else
                tv.setText("(Menerjemahkan...)\n" .. status_text)
            end
            updateInfoMessageDescription(tv)
            local from = lang_codes[trans_source_lang] or "auto"
            local to = lang_codes[trans_target_lang] or "id"
            task(function(t_text, t_from, t_to)
                require "import"
                import "java.net.URL"
                import "java.net.URLEncoder"
                import "java.io.BufferedReader"
                import "java.io.InputStreamReader"
                local safe_text = URLEncoder.encode(t_text, "UTF-8")
                local urlStr = "https://translate.google.com/m?sl=" .. t_from .. "&tl=" .. t_to .. "&q=" .. safe_text
                local res = ""
                pcall(function()
                    local url = URL(urlStr)
                    local conn = url.openConnection()
                    conn.setRequestMethod("GET")
                    conn.setRequestProperty("User-Agent", "Mozilla/5.0")
                    conn.setConnectTimeout(10000)
                    conn.setReadTimeout(10000)
                    if conn.getResponseCode() == 200 then
                        local br = BufferedReader(InputStreamReader(conn.getInputStream()))
                        local line = br.readLine()
                        while line ~= nil do
                            res = res .. line .. "\n"
                            line = br.readLine()
                        end
                        br.close()
                    end
                end)
                return res
            end, text, from, to, function(body)
                if body and body ~= "" then
                    local result = body:match('class="result%-container">([^<]*)</div>')
                    if result then
                        result = result:gsub("&#39;", "'"):gsub("&quot;", '"'):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
                        if trans_show_original then
                            tv.setText(text .. "\n\n" .. result .. "\n" .. status_text)
                        else
                            tv.setText(result .. "\n" .. status_text)
                        end
                    else
                        tv.setText(display_text)
                    end
                else
                    tv.setText(display_text)
                end
                updateInfoMessageDescription(tv)
            end)
        end
    end
    
    infoPinnedStack = {}
    for i, msg in ipairs(info_history.messages) do
        if msg.is_pinned then
            table.insert(infoPinnedStack, i)
        end
        appendInfoUI(msg.text, msg.is_starred, msg.is_pinned, msg.audio_path, msg.timestamp, msg.media_path, msg.media_type)
    end
    currentInfoPinnedDisplayIndex = #infoPinnedStack
    refreshInfoPinnedDisplay()
    
    if #info_history.messages == 0 then
        iViews.emptyInfoText.setVisibility(0)
    end
    
    iDialog.show()
end

views.btnHomeMore.onClick = function()
    local popMenu = PopupMenu(ctx, views.btnHomeMore)
    local menu = popMenu.getMenu()
    menu.add(0, 1, 0, "Informasi Terkini")
    menu.add(0, 2, 0, "Pengaturan")
    menu.add(0, 3, 0, "Keluar")
    
    local closeItem = menu.add(0, 99, 0, "Tutup Menu")
    pcall(function()
        closeItem.setIcon(BitmapDrawable(ctx.getResources(), createEmojiBitmap("X", 100, 70, 30, 75)))
        if Build.VERSION.SDK_INT >= 26 then
            closeItem.setContentDescription("Tutup Menu")
        end
    end)
    
    popMenu.setOnMenuItemClickListener(PopupMenu.OnMenuItemClickListener{
        onMenuItemClick = function(item)
            local id = item.getItemId()
            if id == 1 then
                showInfoDialog()
            elseif id == 2 then
                showSettingsDialog()
            elseif id == 3 then
                dialog.dismiss()
            end
            return true
        end
    })
    popMenu.show()
end

views.btnMore.onClick = function()
    local popMenu = PopupMenu(ctx, views.btnMore)
    local menu = popMenu.getMenu()
    
    local has_starred = false
    local has_pinned = false
    for _, msg in ipairs(chat_history.messages) do
        if msg.is_starred then has_starred = true end
        if msg.is_pinned then has_pinned = true end
        if has_starred and has_pinned then break end
    end
    
    if #chat_history.messages > 0 then
        menu.add(0, 1, 0, "Hapus pesan")
        menu.add(0, 3, 0, "Cari Pesan")
        if has_starred then
            menu.add(0, 4, 0, "Pesan Berbintang")
        end
        if has_pinned then
            menu.add(0, 5, 0, "Pesan Tersemat")
        end
    end
    
    local closeItem = menu.add(0, 99, 0, "Tutup Menu")
    pcall(function()
        closeItem.setIcon(BitmapDrawable(ctx.getResources(), createEmojiBitmap("X", 100, 70, 30, 75)))
        if Build.VERSION.SDK_INT >= 26 then
            closeItem.setContentDescription("Tutup Menu")
        end
    end)

    popMenu.setOnMenuItemClickListener(PopupMenu.OnMenuItemClickListener{
        onMenuItemClick = function(item)
            local id = item.getItemId()
            if id == 1 then
                local builder = AlertDialog.Builder(ctx, 5)
                local checkBoxLayout = LinearLayout(ctx)
                checkBoxLayout.setOrientation(1)
                checkBoxLayout.setPadding(64, 32, 64, 0)
                
                local tvMessage = TextView(ctx)
                tvMessage.setText("Apakah Anda yakin ingin menghapus pesan? Pesan yang dibintangi dan disematkan tidak akan dihapus kecuali Anda memilih opsi di bawah.")
                tvMessage.setTextSize(16)
                tvMessage.setTextColor(0xFF000000)
                checkBoxLayout.addView(tvMessage)
                
                local cbDeleteStarred = CheckBox(ctx)
                cbDeleteStarred.setText("Hapus juga pesan berbintang")
                cbDeleteStarred.setTextColor(0xFF000000)
                cbDeleteStarred.setPadding(0, 32, 0, 0)
                checkBoxLayout.addView(cbDeleteStarred)
                
                local cbDeletePinned = CheckBox(ctx)
                cbDeletePinned.setText("Hapus juga pesan tersemat")
                cbDeletePinned.setTextColor(0xFF000000)
                cbDeletePinned.setPadding(0, 16, 0, 0)
                checkBoxLayout.addView(cbDeletePinned)
                
                builder.setView(checkBoxLayout)
                builder.setPositiveButton("Hapus", DialogInterface.OnClickListener{
                    onClick = function()
                        local deleteStarred = cbDeleteStarred.isChecked()
                        local deletePinned = cbDeletePinned.isChecked()
                        local i = 1
                        while i <= #chat_history.messages do
                            local msg = chat_history.messages[i]
                            local shouldDelete = true
                            if msg.is_starred and not deleteStarred then
                                shouldDelete = false
                            end
                            if msg.is_pinned and not deletePinned then
                                shouldDelete = false
                            end
                            
                            if shouldDelete then
                                if msg.audio_path then
                                    pcall(function() File(msg.audio_path).delete() end)
                                end
                                views.chatContainer.removeViewAt(i - 1)
                                table.remove(chat_history.messages, i)
                            else
                                i = i + 1
                            end
                        end
                        
                        pinnedStack = {}
                        for idx, msg in ipairs(chat_history.messages) do
                            if msg.is_pinned then
                                table.insert(pinnedStack, idx)
                            end
                        end
                        currentPinnedDisplayIndex = #pinnedStack
                        refreshPinnedDisplay()
                        
                        saveHistory()
                        
                        if views.chatContainer.getChildCount() == 0 then
                            views.emptyChatText.setVisibility(0)
                        end
                        
                        views.topBarSearch.setVisibility(8)
                        views.searchNavContainer.setVisibility(8)
                        views.topBarSelection.setVisibility(8)
                        views.bottomSelectionBar.setVisibility(8)
                        views.topBarFiltered.setVisibility(8)
                        views.topBarNormal.setVisibility(0)
                        views.bottomInputBar.setVisibility(0)
                        views.searchInput.setText("")
                        views.tvSearchStatus.setText("")
                        searchResults = {}
                        currentSearchIndex = 0
                        isSelectionMode = false
                        selectedViews = {}
                        currentFilterMode = "normal"
                    end
                })
                builder.setNegativeButton("Batal", nil)
                
                local confirmDialog = builder.create()
                local dWindow = confirmDialog.getWindow()
                if Build.VERSION.SDK_INT >= 22 then
                    dWindow.setType(2032)
                else
                    dWindow.setType(2003)
                end
                confirmDialog.show()
            elseif id == 3 then
                views.topBarNormal.setVisibility(8)
                views.topBarSearch.setVisibility(0)
                views.searchNavContainer.setVisibility(8)
                views.bottomInputBar.setVisibility(8)
                views.searchInput.requestFocus()
                views.tvSearchStatus.setText("")
                views.btnPrevSearch.setEnabled(false)
                views.btnPrevSearch.setAlpha(0.5)
                views.btnNextSearch.setEnabled(false)
                views.btnNextSearch.setAlpha(0.5)
                
                local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
                imm.showSoftInput(views.searchInput, 0)
            elseif id == 4 then
                currentFilterMode = "starred"
                applyFilter()
            elseif id == 5 then
                currentFilterMode = "pinned"
                applyFilter()
            end
            return true
        end
    })
    popMenu.show()
end

local function formatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%02d:%02d", m, s)
end

local recordRunnable = nil

local function stopRecordingTimer()
    if recordRunnable then
        handler.removeCallbacks(recordRunnable)
        recordRunnable = nil
    end
end

local function startRecordingTimer()
    stopRecordingTimer()
    recordRunnable = Runnable{
        run = function()
            if not isRecordingPaused then
                recordDuration = recordDuration + 1
                views.tvRecordTimer.setText(formatTime(recordDuration))
            end
            if isRecording then
                handler.postDelayed(recordRunnable, 1000)
            end
        end
    }
    handler.postDelayed(recordRunnable, 1000)
end

local function startMediaRecorder()
    pcall(function()
        if mediaRecorder then
            mediaRecorder.release()
            mediaRecorder = nil
        end
        mediaRecorder = MediaRecorder()
        mediaRecorder.setAudioSource(1)
        mediaRecorder.setOutputFormat(6)
        mediaRecorder.setAudioEncoder(3)
        mediaRecorder.setAudioEncodingBitRate(128000)
        mediaRecorder.setAudioSamplingRate(44100)
        mediaRecorder.setOutputFile(audioFilePath)
        mediaRecorder.prepare()
        mediaRecorder.start()
    end)
end

local function stopMediaRecorder()
    pcall(function()
        if mediaRecorder then
            mediaRecorder.stop()
            mediaRecorder.release()
            mediaRecorder = nil
        end
    end)
end

local function triggerDictationVibrate(duration)
    if dictation_vibrate then
        pcall(function()
            local vibrator = ctx.getSystemService(Context.VIBRATOR_SERVICE)
            if vibrator and vibrator.hasVibrator() then
                vibrator.vibrate(duration)
            end
        end)
    end
end

local function showGalleryDialog()
    local galleryLayout = {
        LinearLayout,
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "fill",
        backgroundColor = "#F5F5F5",
        {
            FrameLayout,
            layout_width = "fill",
            layout_height = "wrap",
            {
                LinearLayout,
                id = "galleryTopBarNormal",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#075E54",
                gravity = "center_vertical",
                orientation = "horizontal",
                {
                    ImageView,
                    id = "btnBackGallery",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginLeft = "4dp",
                    contentDescription = "Kembali"
                },
                {
                    TextView,
                    id = "tvGalleryTitle",
                    text = "Galeri",
                    textSize = "20sp",
                    textColor = "#FFFFFF",
                    layout_marginLeft = "12dp",
                    layout_weight = "1"
                },
                {
                    ImageView,
                    id = "btnGalleryFilter",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginRight = "0dp",
                    contentDescription = "Urutkan Media"
                },
                {
                    ImageView,
                    id = "btnGallerySearch",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginRight = "4dp",
                    contentDescription = "Cari Media"
                }
            },
            {
                LinearLayout,
                id = "galleryTopBarSearch",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#FFFFFF",
                gravity = "center_vertical",
                orientation = "horizontal",
                visibility = 8,
                {
                    EditText,
                    id = "gallerySearchInput",
                    layout_width = "fill",
                    layout_height = "wrap",
                    layout_weight = "1",
                    hint = "Cari nama file...",
                    textSize = "16sp",
                    singleLine = true,
                    imeOptions = 3,
                    layout_marginLeft = "16dp"
                },
                {
                    ImageView,
                    id = "btnGalleryCloseSearch",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginRight = "4dp",
                    contentDescription = "Tutup Pencarian"
                }
            }
        },
        {
            LinearLayout,
            layout_width = "fill",
            layout_height = "wrap",
            backgroundColor = "#FFFFFF",
            orientation = "horizontal",
            {
                TextView,
                id = "tabGalleryAll",
                text = "Semua",
                layout_width = "0dp",
                layout_weight = "1",
                gravity = "center",
                padding = "16dp",
                textColor = "#00897B",
                textSize = "16sp",
                clickable = true,
                focusable = true
            },
            {
                TextView,
                id = "tabGalleryPhoto",
                text = "Foto",
                layout_width = "0dp",
                layout_weight = "1",
                gravity = "center",
                padding = "16dp",
                textColor = "#888888",
                textSize = "16sp",
                clickable = true,
                focusable = true
            },
            {
                TextView,
                id = "tabGalleryVideo",
                text = "Video",
                layout_width = "0dp",
                layout_weight = "1",
                gravity = "center",
                padding = "16dp",
                textColor = "#888888",
                textSize = "16sp",
                clickable = true,
                focusable = true
            }
        },
        {
            FrameLayout,
            id = "galleryContentContainer",
            layout_width = "fill",
            layout_height = "fill",
            layout_weight = "1"
        },
        {
            LinearLayout,
            layout_width = "fill",
            layout_height = "wrap",
            orientation = "horizontal",
            gravity = "center_vertical",
            padding = "8dp",
            backgroundColor = "#F0F0F0",
            {
                TextView,
                id = "btnGalleryPrev",
                text = "Sebelumnya",
                layout_weight = "1",
                layout_width = "0dp",
                gravity = "center",
                padding = "8dp",
                textColor = "#888888",
                clickable = false
            },
            {
                TextView,
                id = "tvGalleryPageInfo",
                text = "Halaman 1",
                layout_weight = "1",
                layout_width = "0dp",
                gravity = "center",
                padding = "8dp",
                textColor = "#333333"
            },
            {
                TextView,
                id = "btnGalleryNext",
                text = "Berikutnya",
                layout_weight = "1",
                layout_width = "0dp",
                gravity = "center",
                padding = "8dp",
                textColor = "#888888",
                clickable = false
            }
        },
        {
            LinearLayout,
            layout_width = "fill",
            layout_height = "wrap",
            orientation = "horizontal",
            gravity = "center",
            padding = "16dp",
            backgroundColor = "#FFFFFF",
            {
                TextView,
                id = "btnAddAttachment",
                text = "Tambahkan 0 Item",
                layout_width = "fill",
                layout_height = "wrap",
                gravity = "center",
                padding = "12dp",
                textColor = "#888888",
                backgroundColor = "#E0E0E0",
                clickable = false,
                focusable = false
            }
        }
    }
    
    local gViews = {}
    local gContentView = loadlayout(galleryLayout, gViews)
    
    gViews.tvGalleryTitle.setTypeface(Typeface.DEFAULT_BOLD)
    gViews.btnBackGallery.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
    gViews.btnGalleryFilter.setImageBitmap(createEmojiBitmap("站ｮ", 100, 70, 35, 75))
    gViews.btnGallerySearch.setImageBitmap(createEmojiBitmap("🔍", 100, 60, 20, 75))
    gViews.btnGalleryCloseSearch.setImageBitmap(createEmojiBitmap("X", 100, 70, 30, 75))
    gViews.btnAddAttachment.setTypeface(Typeface.DEFAULT_BOLD)
    gViews.btnGalleryPrev.setTypeface(Typeface.DEFAULT_BOLD)
    gViews.tvGalleryPageInfo.setTypeface(Typeface.DEFAULT_BOLD)
    gViews.btnGalleryNext.setTypeface(Typeface.DEFAULT_BOLD)
    
    local gDialog = Dialog(ctx)
    gDialog.requestWindowFeature(1)
    gDialog.setContentView(gContentView)
    
    local w = gDialog.getWindow()
    if Build.VERSION.SDK_INT >= 22 then
        w.setType(2032)
    else
        w.setType(2003)
    end
    w.setBackgroundDrawable(ColorDrawable(0xffF5F5F5))
    w.setLayout(-1, -1)
    
    local selectedMedia = {}
    local currentGalleryTab = "all"
    local allMediaList = {}
    local currentMediaList = {}
    local currentGalleryPage = 1
    local itemsPerPage = 25
    local currentGallerySort = "date_added DESC"
    
    local function updateSelectionUI()
        local count = #selectedMedia
        if count > 0 then
            gViews.btnAddAttachment.setText("Tambahkan " .. count .. " Item")
            gViews.btnAddAttachment.setTextColor(0xFFFFFFFF)
            gViews.btnAddAttachment.setBackgroundColor(0xFF075E54)
            gViews.btnAddAttachment.setClickable(true)
        else
            gViews.btnAddAttachment.setText("Tambahkan 0 Item")
            gViews.btnAddAttachment.setTextColor(0xFF888888)
            gViews.btnAddAttachment.setBackgroundColor(0xFFE0E0E0)
            gViews.btnAddAttachment.setClickable(false)
        end
    end

    local function renderGalleryPage()
        gViews.galleryContentContainer.removeAllViews()
        local sv = ScrollView(ctx)
        local gridContainer = LinearLayout(ctx)
        gridContainer.setOrientation(1)
        gridContainer.setPadding(4, 4, 4, 4)
        sv.addView(gridContainer)
        gViews.galleryContentContainer.addView(sv)
        
        if #currentMediaList == 0 then
            local emptyText = TextView(ctx)
            emptyText.setText("Tidak ada media ditemukan")
            emptyText.setGravity(17)
            emptyText.setTextColor(0xFF888888)
            emptyText.setLayoutParams(FrameLayout.LayoutParams(-1, -1))
            gViews.galleryContentContainer.addView(emptyText)
            
            gViews.tvGalleryPageInfo.setText("Halaman 0 dari 0")
            gViews.btnGalleryPrev.setTextColor(0xFF888888)
            gViews.btnGalleryPrev.setClickable(false)
            gViews.btnGalleryNext.setTextColor(0xFF888888)
            gViews.btnGalleryNext.setClickable(false)
            return
        end
        
        local totalPages = math.ceil(#currentMediaList / itemsPerPage)
        gViews.tvGalleryPageInfo.setText("Halaman " .. currentGalleryPage .. " dari " .. totalPages)
        
        if currentGalleryPage > 1 then
            gViews.btnGalleryPrev.setTextColor(0xFF00897B)
            gViews.btnGalleryPrev.setClickable(true)
        else
            gViews.btnGalleryPrev.setTextColor(0xFF888888)
            gViews.btnGalleryPrev.setClickable(false)
        end
        
        if currentGalleryPage < totalPages then
            gViews.btnGalleryNext.setTextColor(0xFF00897B)
            gViews.btnGalleryNext.setClickable(true)
        else
            gViews.btnGalleryNext.setTextColor(0xFF888888)
            gViews.btnGalleryNext.setClickable(false)
        end
        
        local startIndex = (currentGalleryPage - 1) * itemsPerPage + 1
        local endIndex = math.min(startIndex + itemsPerPage - 1, #currentMediaList)
        
        local row
        local screenWidth = ctx.getResources().getDisplayMetrics().widthPixels
        local itemSize = math.floor((screenWidth - 32) / 3)
        
        for i = startIndex, endIndex do
            local media = currentMediaList[i]
            local gridIndex = i - startIndex
            
            if gridIndex % 3 == 0 then
                row = LinearLayout(ctx)
                row.setOrientation(0)
                gridContainer.addView(row)
            end
            
            local itemContainer = FrameLayout(ctx)
            itemContainer.setLayoutParams(LinearLayout.LayoutParams(itemSize, itemSize))
            itemContainer.setPadding(4, 4, 4, 4)
            
            local imgView = ImageView(ctx)
            imgView.setScaleType(ImageView.ScaleType.CENTER_CROP)
            imgView.setBackgroundColor(0xFFDDDDDD)
            
            task(function(mPath, reqSize)
                require "import"
                import "android.graphics.BitmapFactory"
                import "android.media.ThumbnailUtils"
                import "android.provider.MediaStore"
                local bmp = nil
                pcall(function()
                    if string.match(string.lower(mPath), "%.mp4$") or string.match(string.lower(mPath), "%.3gp$") then
                         bmp = ThumbnailUtils.createVideoThumbnail(mPath, MediaStore.Images.Thumbnails.MINI_KIND)
                    else
                        local opt = BitmapFactory.Options()
                        opt.inJustDecodeBounds = true
                        BitmapFactory.decodeFile(mPath, opt)
                        local scale = 1
                        while (opt.outWidth / scale / 2 >= reqSize and opt.outHeight / scale / 2 >= reqSize) do
                            scale = scale * 2
                        end
                        opt.inSampleSize = scale
                        opt.inJustDecodeBounds = false
                        bmp = BitmapFactory.decodeFile(mPath, opt)
                    end
                end)
                return bmp
            end, media.path, itemSize, function(bmp)
                if bmp then imgView.setImageBitmap(bmp) end
            end)
            
            local overlay = View(ctx)
            overlay.setLayoutParams(FrameLayout.LayoutParams(-1, -1))
            
            local fileName = media.path:match("([^/]+)$") or "Tidak diketahui"
            local label = (media.type == 3) and "Video" or "Foto"
            local baseDesc = label .. " " .. i .. ", Nama file: " .. fileName
            
            local isSelected = false
            for _, sMedia in ipairs(selectedMedia) do
                if sMedia.path == media.path then isSelected = true break end
            end
            
            if isSelected then
                overlay.setBackgroundColor(0x6600897B)
                itemContainer.setContentDescription("Dipilih, " .. baseDesc)
            else
                overlay.setBackgroundColor(0x00000000)
                itemContainer.setContentDescription(baseDesc)
            end
            
            itemContainer.addView(imgView)
            itemContainer.addView(overlay)
            
            if media.type == 3 then
                local playIcon = ImageView(ctx)
                playIcon.setImageBitmap(createEmojiBitmap("▶", 50, 40, 5, 40))
                local lp = FrameLayout.LayoutParams(-2, -2)
                lp.gravity = 17
                playIcon.setLayoutParams(lp)
                itemContainer.addView(playIcon)
            end
            
            itemContainer.onClick = function(v)
                local foundIdx = -1
                for idx, sMedia in ipairs(selectedMedia) do
                    if sMedia.path == media.path then
                        foundIdx = idx
                        break
                    end
                end
                
                if foundIdx > 0 then
                    table.remove(selectedMedia, foundIdx)
                    overlay.setBackgroundColor(0x00000000)
                    itemContainer.setContentDescription(baseDesc)
                else
                    table.insert(selectedMedia, media)
                    overlay.setBackgroundColor(0x6600897B)
                    itemContainer.setContentDescription("Dipilih, " .. baseDesc)
                end
                updateSelectionUI()
            end

            itemContainer.onLongClick = function(v)
                local previewLayout = {
                    LinearLayout,
                    orientation = "vertical",
                    layout_width = "fill",
                    layout_height = "fill",
                    backgroundColor = "#000000",
                    {
                        LinearLayout,
                        layout_width = "fill",
                        layout_height = "60dp",
                        backgroundColor = "#075E54",
                        gravity = "center_vertical",
                        orientation = "horizontal",
                        {
                            ImageView,
                            id = "btnPreviewBack",
                            layout_width = "48dp",
                            layout_height = "48dp",
                            padding = "12dp",
                            layout_marginLeft = "4dp",
                            contentDescription = "Kembali"
                        },
                        {
                            TextView,
                            text = "Penampil Media",
                            textSize = "20sp",
                            textColor = "#FFFFFF",
                            layout_marginLeft = "12dp",
                            layout_weight = "1"
                        },
                        {
                            LinearLayout,
                            id = "btnPreviewSelect",
                            layout_width = "wrap",
                            layout_height = "fill",
                            orientation = "horizontal",
                            gravity = "center",
                            padding = "8dp",
                            layout_marginRight = "4dp",
                            clickable = true,
                            focusable = true,
                            {
                                ImageView,
                                id = "ivPreviewSelectIcon",
                                layout_width = "32dp",
                                layout_height = "32dp",
                                padding = "4dp"
                            },
                            {
                                TextView,
                                id = "tvPreviewSelectText",
                                text = "Pilih",
                                textSize = "16sp",
                                textColor = "#FFFFFF",
                                layout_marginLeft = "4dp"
                            }
                        }
                    },
                    {
                        TextView,
                        id = "tvPreviewFileName",
                        text = fileName,
                        textSize = "14sp",
                        textColor = "#CCCCCC",
                        gravity = "center",
                        padding = "8dp"
                    },
                    {
                        LinearLayout,
                        id = "previewVideoControls",
                        layout_width = "fill",
                        layout_height = "wrap",
                        orientation = "horizontal",
                        gravity = "center_vertical",
                        padding = "8dp",
                        visibility = 8,
                        {
                            ImageView,
                            id = "btnPreviewPlayPause",
                            layout_width = "48dp",
                            layout_height = "48dp",
                            padding = "8dp",
                            contentDescription = "Jeda"
                        },
                        {
                            TextView,
                            id = "tvPreviewProgress",
                            text = "00:00 / 00:00 (0%)",
                            textColor = "#FFFFFF",
                            textSize = "14sp",
                            layout_marginLeft = "8dp"
                        }
                    },
                    {
                        FrameLayout,
                        layout_width = "fill",
                        layout_height = "0dp",
                        layout_weight = "1",
                        {
                            ImageView,
                            id = "previewImageView",
                            layout_width = "fill",
                            layout_height = "fill",
                            visibility = 8
                        },
                        {
                            VideoView,
                            id = "previewVideoView",
                            layout_width = "fill",
                            layout_height = "fill",
                            layout_gravity = "center",
                            visibility = 8
                        }
                    }
                }
                
                local pViews = {}
                local pContentView = loadlayout(previewLayout, pViews)
                
                pViews.btnPreviewBack.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
                pViews.btnPreviewPlayPause.setImageBitmap(bmpPause)
                pViews.previewImageView.setScaleType(ImageView.ScaleType.FIT_CENTER)
                
                local pDialog = Dialog(ctx)
                pDialog.requestWindowFeature(1)
                pDialog.setContentView(pContentView)
                local pw = pDialog.getWindow()
                if Build.VERSION.SDK_INT >= 22 then
                    pw.setType(2032)
                else
                    pw.setType(2003)
                end
                pw.setBackgroundDrawable(ColorDrawable(0xff000000))
                pw.setLayout(-1, -1)
                
                local bmpCheck = createEmojiBitmap("☑", 100, 70, 25, 75)
                local bmpUncheck = createEmojiBitmap("☐", 100, 70, 25, 75)

                local function checkSelection()
                    local isSel = false
                    for _, sMedia in ipairs(selectedMedia) do
                        if sMedia.path == media.path then
                            isSel = true
                            break
                        end
                    end
                    if isSel then
                        pViews.tvPreviewSelectText.setText("Batal")
                        pViews.tvPreviewSelectText.setTextColor(0xFFFF5252)
                        pViews.ivPreviewSelectIcon.setImageBitmap(bmpUncheck)
                        pViews.btnPreviewSelect.setContentDescription("Batalkan Pilihan")
                    else
                        pViews.tvPreviewSelectText.setText("Pilih")
                        pViews.tvPreviewSelectText.setTextColor(0xFFFFFFFF)
                        pViews.ivPreviewSelectIcon.setImageBitmap(bmpCheck)
                        pViews.btnPreviewSelect.setContentDescription("Pilih Media")
                    end
                end
                
                checkSelection()
                
                pViews.btnPreviewSelect.onClick = function()
                    itemContainer.performClick()
                    checkSelection()
                end
                
                local isVideo = (media.type == 3)
                local progressRunnable = nil
                
                local function stopProg()
                    if progressRunnable then
                        handler.removeCallbacks(progressRunnable)
                        progressRunnable = nil
                    end
                end
                
                if isVideo then
                    pViews.previewVideoControls.setVisibility(0)
                    pViews.previewVideoView.setVisibility(0)
                    pViews.previewVideoView.setVideoPath(media.path)
                    pViews.previewVideoView.start()
                    
                    progressRunnable = Runnable{
                        run = function()
                            pcall(function()
                                if pViews.previewVideoView.isPlaying() then
                                    local cur = math.floor(pViews.previewVideoView.getCurrentPosition() / 1000)
                                    local dur = math.floor(pViews.previewVideoView.getDuration() / 1000)
                                    if dur > 0 then
                                        local pct = math.floor((cur / dur) * 100)
                                        pViews.tvPreviewProgress.setText(formatTime(cur) .. " / " .. formatTime(dur) .. " (" .. pct .. "%)")
                                    end
                                end
                            end)
                            if progressRunnable then
                                handler.postDelayed(progressRunnable, 1000)
                            end
                        end
                    }
                    handler.postDelayed(progressRunnable, 1000)
                    
                    pViews.previewVideoView.setOnCompletionListener(MediaPlayer.OnCompletionListener{
                        onCompletion = function(mp)
                            pViews.btnPreviewPlayPause.setImageBitmap(bmpPlay)
                            pViews.btnPreviewPlayPause.setContentDescription("Putar")
                        end
                    })
                    
                    pViews.btnPreviewPlayPause.onClick = function()
                        pcall(function()
                            if pViews.previewVideoView.isPlaying() then
                                pViews.previewVideoView.pause()
                                pViews.btnPreviewPlayPause.setImageBitmap(bmpPlay)
                                pViews.btnPreviewPlayPause.setContentDescription("Putar")
                            else
                                pViews.previewVideoView.start()
                                pViews.btnPreviewPlayPause.setImageBitmap(bmpPause)
                                pViews.btnPreviewPlayPause.setContentDescription("Jeda")
                            end
                        end)
                    end
                else
                    pViews.previewImageView.setVisibility(0)
                    pcall(function()
                        import "android.graphics.BitmapFactory"
                        local bmp = BitmapFactory.decodeFile(media.path)
                        if bmp then
                            pViews.previewImageView.setImageBitmap(bmp)
                        end
                    end)
                end
                
                pViews.btnPreviewBack.onClick = function()
                    stopProg()
                    pcall(function()
                        if pViews.previewVideoView.isPlaying() then
                            pViews.previewVideoView.pause()
                        end
                    end)
                    pDialog.dismiss()
                end
                
                pDialog.show()
                return true
            end
            
            row.addView(itemContainer)
        end
        
        handler.postDelayed(Runnable{
            run = function()
                sv.fullScroll(33)
            end
        }, 100)
    end
    
    local function applyGallerySearch(query)
        currentMediaList = {}
        if query == "" then
            for _, media in ipairs(allMediaList) do
                table.insert(currentMediaList, media)
            end
        else
            local lowerQuery = string.lower(query)
            for _, media in ipairs(allMediaList) do
                local fileName = media.path:match("([^/]+)$") or ""
                if string.find(string.lower(fileName), lowerQuery, 1, true) then
                    table.insert(currentMediaList, media)
                end
            end
        end
        currentGalleryPage = 1
        renderGalleryPage()
    end

    local function loadMediaList()
        allMediaList = {}
        pcall(function()
            import "android.provider.MediaStore"
            local uri = MediaStore.Files.getContentUri("external")
            local proj = {"_data", "media_type"}
            local sel = "media_type=1 OR media_type=3"
            if currentGalleryTab == "photo" then sel = "media_type=1" end
            if currentGalleryTab == "video" then sel = "media_type=3" end
            local cursor = ctx.getContentResolver().query(uri, proj, sel, nil, currentGallerySort)
            if cursor then
                local colData = cursor.getColumnIndexOrThrow("_data")
                local colType = cursor.getColumnIndexOrThrow("media_type")
                while cursor.moveToNext() do
                    local path = cursor.getString(colData)
                    local mType = cursor.getInt(colType)
                    table.insert(allMediaList, {path = path, type = mType})
                end
                cursor.close()
            end
        end)
        applyGallerySearch(tostring(gViews.gallerySearchInput.getText()))
    end

    gViews.btnGalleryFilter.onClick = function()
        local popMenu = PopupMenu(ctx, gViews.btnGalleryFilter)
        local menu = popMenu.getMenu()
        menu.add(0, 1, 0, "Terbaru")
        menu.add(0, 2, 0, "Terlama")
        
        local closeItem = menu.add(0, 99, 0, "Tutup Menu Filter")
        pcall(function()
            closeItem.setIcon(BitmapDrawable(ctx.getResources(), createEmojiBitmap("X", 100, 70, 30, 75)))
            if Build.VERSION.SDK_INT >= 26 then
                closeItem.setContentDescription("Tutup Menu Filter")
            end
        end)
        
        popMenu.setOnMenuItemClickListener(PopupMenu.OnMenuItemClickListener{
            onMenuItemClick = function(item)
                local id = item.getItemId()
                if id == 1 then
                    currentGallerySort = "date_added DESC"
                    loadMediaList()
                    triggerAccessibilityAnnouncement("Diurutkan dari yang terbaru")
                elseif id == 2 then
                    currentGallerySort = "date_added ASC"
                    loadMediaList()
                    triggerAccessibilityAnnouncement("Diurutkan dari yang terlama")
                end
                return true
            end
        })
        popMenu.show()
    end

    gViews.btnGallerySearch.onClick = function()
        gViews.galleryTopBarNormal.setVisibility(8)
        gViews.galleryTopBarSearch.setVisibility(0)
        gViews.gallerySearchInput.requestFocus()
        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
        imm.showSoftInput(gViews.gallerySearchInput, 0)
    end
    
    gViews.btnGalleryCloseSearch.onClick = function()
        gViews.galleryTopBarSearch.setVisibility(8)
        gViews.galleryTopBarNormal.setVisibility(0)
        gViews.gallerySearchInput.setText("")
        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
        imm.hideSoftInputFromWindow(gViews.gallerySearchInput.getWindowToken(), 0)
        applyGallerySearch("")
    end

    gViews.gallerySearchInput.setOnEditorActionListener(TextView.OnEditorActionListener{
        onEditorAction = function(v, actionId, event)
            if actionId == 3 or (event and event.getKeyCode() == 66 and event.getAction() == 0) then
                local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
                imm.hideSoftInputFromWindow(v.getWindowToken(), 0)
                applyGallerySearch(tostring(v.getText()))
                return true
            end
            return false
        end
    })

    gViews.btnGalleryPrev.onClick = function()
        if currentGalleryPage > 1 then
            currentGalleryPage = currentGalleryPage - 1
            renderGalleryPage()
            triggerAccessibilityAnnouncement("Menampilkan halaman " .. currentGalleryPage)
        end
    end

    gViews.btnGalleryNext.onClick = function()
        local totalPages = math.ceil(#currentMediaList / itemsPerPage)
        if currentGalleryPage < totalPages then
            currentGalleryPage = currentGalleryPage + 1
            renderGalleryPage()
            triggerAccessibilityAnnouncement("Menampilkan halaman " .. currentGalleryPage)
        end
    end

    gViews.tabGalleryAll.onClick = function()
        currentGalleryTab = "all"
        gViews.tabGalleryAll.setTextColor(0xFF00897B)
        gViews.tabGalleryPhoto.setTextColor(0xFF888888)
        gViews.tabGalleryVideo.setTextColor(0xFF888888)
        loadMediaList()
    end
    
    gViews.tabGalleryPhoto.onClick = function()
        currentGalleryTab = "photo"
        gViews.tabGalleryPhoto.setTextColor(0xFF00897B)
        gViews.tabGalleryAll.setTextColor(0xFF888888)
        gViews.tabGalleryVideo.setTextColor(0xFF888888)
        loadMediaList()
    end
    
    gViews.tabGalleryVideo.onClick = function()
        currentGalleryTab = "video"
        gViews.tabGalleryVideo.setTextColor(0xFF00897B)
        gViews.tabGalleryAll.setTextColor(0xFF888888)
        gViews.tabGalleryPhoto.setTextColor(0xFF888888)
        loadMediaList()
    end
    
    gViews.btnAddAttachment.onClick = function()
        if #selectedMedia > 0 then
            for i, media in ipairs(selectedMedia) do
                local label = (media.type == 3) and "Video" or "Foto"
                local msgTime = os.time()
                appendMessage(label, true, false, false, true, nil, msgTime, media.path, media.type)
                
                if current_chat_id == "admin" then
                    local endpoint = (media.type == 3) and "sendVideo" or "sendPhoto"
                    local fieldName = (media.type == 3) and "video" or "photo"
                    local fileName = (media.type == 3) and "video.mp4" or "photo.jpg"
                    local mimeType = (media.type == 3) and "video/mp4" or "image/jpeg"
                    local label = (media.type == 3) and "Mengirim Video" or "Mengirim Foto"
                    
                    task(function(filePath, t_endpoint, t_fieldName, t_fileName, t_mimeType, t_token, t_model, t_id, t_label)
                        require "import"
                        import "java.net.URL"
                        import "java.io.File"
                        import "java.io.FileInputStream"
                        import "java.io.DataOutputStream"
                        import "java.lang.reflect.Array"
                        import "java.lang.Byte"
                        import "java.lang.String"
                        import "java.io.BufferedReader"
                        import "java.io.InputStreamReader"
                        import "org.json.JSONObject"
                        
                        local name = ""
                        local username = ""
                        pcall(function()
                            local url = URL("http://botspark.de1.octavia.id:25701/api/users/profile")
                            local conn = url.openConnection()
                            conn.setConnectTimeout(10000)
                            conn.setReadTimeout(10000)
                            conn.setRequestMethod("GET")
                            conn.setRequestProperty("Authorization", "Bearer " .. t_token)
                            if conn.getResponseCode() == 200 then
                                local br = BufferedReader(InputStreamReader(conn.getInputStream()))
                                local resBody = ""
                                local line = br.readLine()
                                while line ~= nil do
                                    resBody = resBody .. line
                                    line = br.readLine()
                                end
                                br.close()
                                local data = JSONObject(resBody)
                                name = data.optString("name", "")
                                username = data.optString("username", "")
                            end
                        end)
                        
                        local caption = ""
                        if name ~= "" then caption = caption .. "👤 Nama: " .. name .. "\n" end
                        if username ~= "" then caption = caption .. "🔗 Username: @" .. username .. "\n" end
                        caption = caption .. "📱 Model: " .. t_model .. "\n🆔 ID: " .. t_id .. "\n📷 " .. t_label
                        
                        local code = -1
                        pcall(function()
                            local file = File(filePath)
                            if not file.exists() then return end
                            
                            local boundary = "*****"
                            local lineEnd = "\r\n"
                            local twoHyphens = "--"
                            
                            local url = URL("http://botspark.de1.octavia.id:25701/api/" .. t_endpoint)
                            local conn = url.openConnection()
                            conn.setConnectTimeout(60000)
                            conn.setReadTimeout(60000)
                            conn.setDoInput(true)
                            conn.setDoOutput(true)
                            conn.setUseCaches(false)
                            conn.setRequestMethod("POST")
                            conn.setRequestProperty("Connection", "Keep-Alive")
                            conn.setRequestProperty("Content-Type", "multipart/form-data;boundary=" .. boundary)
                            
                            local dos = DataOutputStream(conn.getOutputStream())
                            
                            dos.writeBytes(twoHyphens .. boundary .. lineEnd)
                            dos.writeBytes("Content-Disposition: form-data; name=\"caption\"" .. lineEnd)
                            dos.writeBytes("Content-Type: text/plain; charset=UTF-8" .. lineEnd)
                            dos.writeBytes(lineEnd)
                            dos.write(String(caption).getBytes("UTF-8"))
                            dos.writeBytes(lineEnd)
                            
                            dos.writeBytes(twoHyphens .. boundary .. lineEnd)
                            dos.writeBytes("Content-Disposition: form-data; name=\"" .. t_fieldName .. "\";filename=\"" .. t_fileName .. "\"" .. lineEnd)
                            dos.writeBytes("Content-Type: " .. t_mimeType .. lineEnd)
                            dos.writeBytes(lineEnd)
                            
                            local fileInputStream = FileInputStream(file)
                            local bytesAvailable = fileInputStream.available()
                            local maxBufferSize = 1024 * 1024
                            local bufferSize = math.min(bytesAvailable, maxBufferSize)
                            local buffer = Array.newInstance(Byte.TYPE, bufferSize)
                            
                            local bytesRead = fileInputStream.read(buffer, 0, bufferSize)
                            while bytesRead > 0 do
                                dos.write(buffer, 0, bufferSize)
                                bytesAvailable = fileInputStream.available()
                                bufferSize = math.min(bytesAvailable, maxBufferSize)
                                bytesRead = fileInputStream.read(buffer, 0, bufferSize)
                            end
                            
                            dos.writeBytes(lineEnd)
                            dos.writeBytes(twoHyphens .. boundary .. twoHyphens .. lineEnd)
                            
                            fileInputStream.close()
                            dos.flush()
                            dos.close()
                            
                            code = conn.getResponseCode()
                        end)
                        return code
                    end, media.path, endpoint, fieldName, fileName, mimeType, auth_token, Build.MANUFACTURER .. " " .. Build.MODEL, Build.ID, label, function(c)
                    end)
                end
            end
            triggerAccessibilityAnnouncement("Melampirkan " .. #selectedMedia .. " media")
            gDialog.dismiss()
        end
    end
    
    gViews.btnBackGallery.onClick = function()
        gDialog.dismiss()
    end
    
    loadMediaList()
    gDialog.show()
end

local function showAudioDialog()
    local audioLayout = {
        LinearLayout,
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "fill",
        backgroundColor = "#F5F5F5",
        {
            FrameLayout,
            layout_width = "fill",
            layout_height = "wrap",
            {
                LinearLayout,
                id = "audioTopBarNormal",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#075E54",
                gravity = "center_vertical",
                orientation = "horizontal",
                {
                    ImageView,
                    id = "btnBackAudio",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginLeft = "4dp",
                    contentDescription = "Kembali"
                },
                {
                    TextView,
                    id = "tvAudioTitle",
                    text = "Audio",
                    textSize = "20sp",
                    textColor = "#FFFFFF",
                    layout_marginLeft = "12dp",
                    layout_weight = "1"
                },
                {
                    ImageView,
                    id = "btnAudioFilter",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginRight = "0dp",
                    contentDescription = "Urutkan Audio"
                },
                {
                    ImageView,
                    id = "btnAudioSearch",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginRight = "4dp",
                    contentDescription = "Cari Audio"
                }
            },
            {
                LinearLayout,
                id = "audioTopBarSearch",
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#FFFFFF",
                gravity = "center_vertical",
                orientation = "horizontal",
                visibility = 8,
                {
                    EditText,
                    id = "audioSearchInput",
                    layout_width = "fill",
                    layout_height = "wrap",
                    layout_weight = "1",
                    hint = "Cari nama file...",
                    textSize = "16sp",
                    singleLine = true,
                    imeOptions = 3,
                    layout_marginLeft = "16dp"
                },
                {
                    ImageView,
                    id = "btnAudioCloseSearch",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginRight = "4dp",
                    contentDescription = "Tutup Pencarian"
                }
            }
        },
        {
            HorizontalScrollView,
            layout_width = "fill",
            layout_height = "wrap",
            horizontalScrollBarEnabled = false,
            backgroundColor = "#FFFFFF",
            {
                LinearLayout,
                layout_width = "wrap",
                layout_height = "wrap",
                orientation = "horizontal",
                {
                    TextView,
                    id = "tabAudioAll",
                    text = "Semua",
                    padding = "16dp",
                    textColor = "#00897B",
                    textSize = "16sp",
                    clickable = true,
                    focusable = true
                },
                {
                    TextView,
                    id = "tabAudioSong",
                    text = "Lagu",
                    padding = "16dp",
                    textColor = "#888888",
                    textSize = "16sp",
                    clickable = true,
                    focusable = true
                },
                {
                    TextView,
                    id = "tabAudioVoice",
                    text = "Audio",
                    padding = "16dp",
                    textColor = "#888888",
                    textSize = "16sp",
                    clickable = true,
                    focusable = true
                },
                {
                    TextView,
                    id = "tabAudioArtist",
                    text = "Penyanyi",
                    padding = "16dp",
                    textColor = "#888888",
                    textSize = "16sp",
                    clickable = true,
                    focusable = true
                },
                {
                    TextView,
                    id = "tabAudioAlbum",
                    text = "Album",
                    padding = "16dp",
                    textColor = "#888888",
                    textSize = "16sp",
                    clickable = true,
                    focusable = true
                }
            }
        },
        {
            FrameLayout,
            id = "audioContentContainer",
            layout_width = "fill",
            layout_height = "fill",
            layout_weight = "1"
        },
        {
            LinearLayout,
            layout_width = "fill",
            layout_height = "wrap",
            orientation = "horizontal",
            gravity = "center_vertical",
            padding = "8dp",
            backgroundColor = "#F0F0F0",
            {
                TextView,
                id = "btnAudioPrev",
                text = "Sebelumnya",
                layout_weight = "1",
                layout_width = "0dp",
                gravity = "center",
                padding = "8dp",
                textColor = "#888888",
                clickable = false
            },
            {
                TextView,
                id = "tvAudioPageInfo",
                text = "Halaman 1",
                layout_weight = "1",
                layout_width = "0dp",
                gravity = "center",
                padding = "8dp",
                textColor = "#333333"
            },
            {
                TextView,
                id = "btnAudioNext",
                text = "Berikutnya",
                layout_weight = "1",
                layout_width = "0dp",
                gravity = "center",
                padding = "8dp",
                textColor = "#888888",
                clickable = false
            }
        },
        {
            LinearLayout,
            layout_width = "fill",
            layout_height = "wrap",
            orientation = "horizontal",
            gravity = "center",
            padding = "16dp",
            backgroundColor = "#FFFFFF",
            {
                TextView,
                id = "btnAddAudioAttachment",
                text = "Tambahkan 0 Item",
                layout_width = "fill",
                layout_height = "wrap",
                gravity = "center",
                padding = "12dp",
                textColor = "#888888",
                backgroundColor = "#E0E0E0",
                clickable = false,
                focusable = false
            }
        }
    }
    
    local aViews = {}
    local aContentView = loadlayout(audioLayout, aViews)
    
    aViews.tvAudioTitle.setTypeface(Typeface.DEFAULT_BOLD)
    aViews.btnBackAudio.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
    aViews.btnAudioFilter.setImageBitmap(createEmojiBitmap("站ｮ", 100, 70, 35, 75))
    aViews.btnAudioSearch.setImageBitmap(createEmojiBitmap("🔍", 100, 60, 20, 75))
    aViews.btnAudioCloseSearch.setImageBitmap(createEmojiBitmap("X", 100, 70, 30, 75))
    aViews.btnAddAudioAttachment.setTypeface(Typeface.DEFAULT_BOLD)
    aViews.btnAudioPrev.setTypeface(Typeface.DEFAULT_BOLD)
    aViews.tvAudioPageInfo.setTypeface(Typeface.DEFAULT_BOLD)
    aViews.btnAudioNext.setTypeface(Typeface.DEFAULT_BOLD)
    
    local aDialog = Dialog(ctx)
    aDialog.requestWindowFeature(1)
    aDialog.setContentView(aContentView)
    
    local w = aDialog.getWindow()
    if Build.VERSION.SDK_INT >= 22 then
        w.setType(2032)
    else
        w.setType(2003)
    end
    w.setBackgroundDrawable(ColorDrawable(0xffF5F5F5))
    w.setLayout(-1, -1)
    
    local selectedAudio = {}
    local currentAudioTab = "all"
    local allAudioList = {}
    local currentAudioList = {}
    local currentAudioPage = 1
    local itemsPerPage = 20
    local currentAudioSort = "date_added DESC"
    
    local function updateAudioSelectionUI()
        local count = #selectedAudio
        if count > 0 then
            aViews.btnAddAudioAttachment.setText("Tambahkan " .. count .. " Item")
            aViews.btnAddAudioAttachment.setTextColor(0xFFFFFFFF)
            aViews.btnAddAudioAttachment.setBackgroundColor(0xFF075E54)
            aViews.btnAddAudioAttachment.setClickable(true)
        else
            aViews.btnAddAudioAttachment.setText("Tambahkan 0 Item")
            aViews.btnAddAudioAttachment.setTextColor(0xFF888888)
            aViews.btnAddAudioAttachment.setBackgroundColor(0xFFE0E0E0)
            aViews.btnAddAudioAttachment.setClickable(false)
        end
    end

    local function showAudioPreview(media, fileName, onToggleSelection, checkIsSelected)
        local previewLayout = {
            LinearLayout,
            orientation = "vertical",
            layout_width = "fill",
            layout_height = "fill",
            backgroundColor = "#000000",
            {
                LinearLayout,
                layout_width = "fill",
                layout_height = "60dp",
                backgroundColor = "#075E54",
                gravity = "center_vertical",
                orientation = "horizontal",
                {
                    ImageView,
                    id = "btnPreviewBack",
                    layout_width = "48dp",
                    layout_height = "48dp",
                    padding = "12dp",
                    layout_marginLeft = "4dp",
                    contentDescription = "Kembali"
                },
                {
                    TextView,
                    text = "Penampil Audio",
                    textSize = "20sp",
                    textColor = "#FFFFFF",
                    layout_marginLeft = "12dp",
                    layout_weight = "1"
                },
                {
                    LinearLayout,
                    id = "btnPreviewSelect",
                    layout_width = "wrap",
                    layout_height = "fill",
                    orientation = "horizontal",
                    gravity = "center",
                    padding = "8dp",
                    layout_marginRight = "4dp",
                    clickable = true,
                    focusable = true,
                    {
                        ImageView,
                        id = "ivPreviewSelectIcon",
                        layout_width = "32dp",
                        layout_height = "32dp",
                        padding = "4dp"
                    },
                    {
                        TextView,
                        id = "tvPreviewSelectText",
                        text = "Pilih",
                        textSize = "16sp",
                        textColor = "#FFFFFF",
                        layout_marginLeft = "4dp"
                    }
                }
            },
            {
                TextView,
                id = "tvPreviewFileName",
                text = fileName,
                textSize = "14sp",
                textColor = "#CCCCCC",
                gravity = "center",
                padding = "16dp"
            },
            {
                LinearLayout,
                id = "previewAudioControls",
                layout_width = "fill",
                layout_height = "wrap",
                orientation = "horizontal",
                gravity = "center_vertical",
                padding = "16dp",
                {
                    ImageView,
                    id = "btnPreviewPlayPause",
                    layout_width = "64dp",
                    layout_height = "64dp",
                    padding = "16dp",
                    contentDescription = "Jeda"
                },
                {
                    TextView,
                    id = "tvPreviewProgress",
                    text = "00:00 / 00:00 (0%)",
                    textColor = "#FFFFFF",
                    textSize = "16sp",
                    layout_marginLeft = "16dp"
                }
            },
            {
                FrameLayout,
                layout_width = "fill",
                layout_height = "0dp",
                layout_weight = "1"
            }
        }
        
        local pViews = {}
        local pContentView = loadlayout(previewLayout, pViews)
        
        pViews.btnPreviewBack.setImageBitmap(createEmojiBitmap("←", 100, 70, 20, 75))
        pViews.btnPreviewPlayPause.setImageBitmap(bmpPlay)
        
        local pDialog = Dialog(ctx)
        pDialog.requestWindowFeature(1)
        pDialog.setContentView(pContentView)
        local pw = pDialog.getWindow()
        if Build.VERSION.SDK_INT >= 22 then
            pw.setType(2032)
        else
            pw.setType(2003)
        end
        pw.setBackgroundDrawable(ColorDrawable(0xff000000))
        pw.setLayout(-1, -1)
        
        local bmpCheck = createEmojiBitmap("☑", 100, 70, 25, 75)
        local bmpUncheck = createEmojiBitmap("☐", 100, 70, 25, 75)

        local function updateSelectionIcon()
            if checkIsSelected() then
                pViews.tvPreviewSelectText.setText("Batal")
                pViews.tvPreviewSelectText.setTextColor(0xFFFF5252)
                pViews.ivPreviewSelectIcon.setImageBitmap(bmpUncheck)
                pViews.btnPreviewSelect.setContentDescription("Batalkan Pilihan")
            else
                pViews.tvPreviewSelectText.setText("Pilih")
                pViews.tvPreviewSelectText.setTextColor(0xFFFFFFFF)
                pViews.ivPreviewSelectIcon.setImageBitmap(bmpCheck)
                pViews.btnPreviewSelect.setContentDescription("Pilih Media")
            end
        end
        
        updateSelectionIcon()
        
        pViews.btnPreviewSelect.onClick = function()
            onToggleSelection()
            updateSelectionIcon()
        end
        
        local mp = MediaPlayer()
        local isPrepared = false
        local progressRunnable = nil
        
        local function stopProg()
            if progressRunnable then
                handler.removeCallbacks(progressRunnable)
                progressRunnable = nil
            end
        end

        pcall(function()
            mp.setDataSource(media.path)
            mp.prepareAsync()
        end)
        
        mp.setOnPreparedListener(MediaPlayer.OnPreparedListener{
            onPrepared = function(m)
                isPrepared = true
                m.start()
                pViews.btnPreviewPlayPause.setImageBitmap(bmpPause)
                pViews.btnPreviewPlayPause.setContentDescription("Jeda")
                triggerAccessibilityAnnouncement("Memutar pratinjau audio")
                
                progressRunnable = Runnable{
                    run = function()
                        pcall(function()
                            if mp.isPlaying() then
                                local cur = math.floor(mp.getCurrentPosition() / 1000)
                                local dur = math.floor(mp.getDuration() / 1000)
                                if dur > 0 then
                                    local pct = math.floor((cur / dur) * 100)
                                    pViews.tvPreviewProgress.setText(formatTime(cur) .. " / " .. formatTime(dur) .. " (" .. pct .. "%)")
                                end
                            end
                        end)
                        if progressRunnable then
                            handler.postDelayed(progressRunnable, 1000)
                        end
                    end
                }
                handler.postDelayed(progressRunnable, 1000)
            end
        })
        
        mp.setOnCompletionListener(MediaPlayer.OnCompletionListener{
            onCompletion = function(m)
                pViews.btnPreviewPlayPause.setImageBitmap(bmpPlay)
                pViews.btnPreviewPlayPause.setContentDescription("Putar")
                m.seekTo(0)
                local dur = math.floor(m.getDuration() / 1000)
                if dur > 0 then
                    pViews.tvPreviewProgress.setText("00:00 / " .. formatTime(dur) .. " (0%)")
                end
            end
        })
        
        pViews.btnPreviewPlayPause.onClick = function()
            if isPrepared then
                if mp.isPlaying() then
                    mp.pause()
                    pViews.btnPreviewPlayPause.setImageBitmap(bmpPlay)
                    pViews.btnPreviewPlayPause.setContentDescription("Putar")
                else
                    mp.start()
                    pViews.btnPreviewPlayPause.setImageBitmap(bmpPause)
                    pViews.btnPreviewPlayPause.setContentDescription("Jeda")
                end
            end
        end
        
        pViews.btnPreviewBack.onClick = function()
            stopProg()
            pcall(function()
                if mp and mp.isPlaying() then mp.pause() end
            end)
            pDialog.dismiss()
        end
        
        pDialog.setOnDismissListener(function()
            stopProg()
            pcall(function()
                if mp then
                    if mp.isPlaying() then mp.stop() end
                    mp.release()
                end
            end)
        end)
        
        pDialog.show()
    end

    local function renderAudioPage()
        aViews.audioContentContainer.removeAllViews()
        local sv = ScrollView(ctx)
        local listContainer = LinearLayout(ctx)
        listContainer.setOrientation(1)
        sv.addView(listContainer)
        aViews.audioContentContainer.addView(sv)
        
        if #currentAudioList == 0 then
            local emptyText = TextView(ctx)
            emptyText.setText("Tidak ada file audio ditemukan")
            emptyText.setGravity(17)
            emptyText.setTextColor(0xFF888888)
            emptyText.setLayoutParams(FrameLayout.LayoutParams(-1, -1))
            aViews.audioContentContainer.addView(emptyText)
            
            aViews.tvAudioPageInfo.setText("Halaman 0 dari 0")
            aViews.btnAudioPrev.setTextColor(0xFF888888)
            aViews.btnAudioPrev.setClickable(false)
            aViews.btnAudioNext.setTextColor(0xFF888888)
            aViews.btnAudioNext.setClickable(false)
            return
        end
        
        local totalPages = math.ceil(#currentAudioList / itemsPerPage)
        aViews.tvAudioPageInfo.setText("Halaman " .. currentAudioPage .. " dari " .. totalPages)
        
        if currentAudioPage > 1 then
            aViews.btnAudioPrev.setTextColor(0xFF00897B)
            aViews.btnAudioPrev.setClickable(true)
        else
            aViews.btnAudioPrev.setTextColor(0xFF888888)
            aViews.btnAudioPrev.setClickable(false)
        end
        
        if currentAudioPage < totalPages then
            aViews.btnAudioNext.setTextColor(0xFF00897B)
            aViews.btnAudioNext.setClickable(true)
        else
            aViews.btnAudioNext.setTextColor(0xFF888888)
            aViews.btnAudioNext.setClickable(false)
        end
        
        local startIndex = (currentAudioPage - 1) * itemsPerPage + 1
        local endIndex = math.min(startIndex + itemsPerPage - 1, #currentAudioList)
        
        local bmpCheck = createEmojiBitmap("☑", 100, 70, 25, 75)
        local bmpUncheck = createEmojiBitmap("☐", 100, 70, 25, 75)
        
        for i = startIndex, endIndex do
            local media = currentAudioList[i]
            
            local itemContainer = LinearLayout(ctx)
            itemContainer.setOrientation(0)
            itemContainer.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
            itemContainer.setPadding(24, 24, 24, 24)
            itemContainer.setGravity(16)
            
            local iconView = ImageView(ctx)
            iconView.setImageBitmap(createEmojiBitmap("🎵", 80, 50, 15, 60))
            iconView.setLayoutParams(LinearLayout.LayoutParams(100, 100))
            
            local textLay = LinearLayout(ctx)
            textLay.setOrientation(1)
            textLay.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
            textLay.setPadding(24, 0, 24, 0)
            
            local fileName = media.path:match("([^/]+)$") or "Audio"
            local displayTitle = media.title
            if not displayTitle or displayTitle == "" then displayTitle = fileName end
            
            local tvTitle = TextView(ctx)
            tvTitle.setText(displayTitle)
            tvTitle.setTextColor(0xFF000000)
            tvTitle.setTextSize(16)
            tvTitle.setSingleLine(true)
            
            local tvPath = TextView(ctx)
            tvPath.setText(fileName)
            tvPath.setTextColor(0xFF888888)
            tvPath.setTextSize(12)
            tvPath.setSingleLine(true)
            
            textLay.addView(tvTitle)
            textLay.addView(tvPath)
            
            local checkIcon = ImageView(ctx)
            checkIcon.setLayoutParams(LinearLayout.LayoutParams(80, 80))
            
            local baseDesc = "Audio " .. i .. ", Judul: " .. displayTitle
            
            local function checkSelection()
                local isSelected = false
                for _, sMedia in ipairs(selectedAudio) do
                    if sMedia.path == media.path then isSelected = true break end
                end
                
                if isSelected then
                    itemContainer.setBackgroundColor(0xFF90CAF9)
                    checkIcon.setImageBitmap(bmpCheck)
                    itemContainer.setContentDescription("Dipilih, " .. baseDesc)
                else
                    itemContainer.setBackgroundColor(0x00000000)
                    checkIcon.setImageBitmap(bmpUncheck)
                    itemContainer.setContentDescription(baseDesc)
                end
            end
            
            checkSelection()
            
            itemContainer.addView(iconView)
            itemContainer.addView(textLay)
            itemContainer.addView(checkIcon)
            
            itemContainer.onClick = function(v)
                local foundIdx = -1
                for idx, sMedia in ipairs(selectedAudio) do
                    if sMedia.path == media.path then
                        foundIdx = idx
                        break
                    end
                end
                
                if foundIdx > 0 then
                    table.remove(selectedAudio, foundIdx)
                else
                    table.insert(selectedAudio, media)
                end
                checkSelection()
                updateAudioSelectionUI()
            end
            
            itemContainer.onLongClick = function(v)
                local function toggleFunc()
                    itemContainer.performClick()
                end
                local function checkFunc()
                    for _, sMedia in ipairs(selectedAudio) do
                        if sMedia.path == media.path then return true end
                    end
                    return false
                end
                showAudioPreview(media, fileName, toggleFunc, checkFunc)
                return true
            end
            
            listContainer.addView(itemContainer)
            
            local div = TextView(ctx)
            div.setHeight(1)
            div.setBackgroundColor(0xFFE0E0E0)
            listContainer.addView(div)
        end
        
        handler.postDelayed(Runnable{
            run = function()
                sv.scrollTo(0, 0)
            end
        }, 100)
    end
    
    local function applyAudioSearch(query)
        currentAudioList = {}
        if query == "" then
            for _, media in ipairs(allAudioList) do
                table.insert(currentAudioList, media)
            end
        else
            local lowerQuery = string.lower(query)
            for _, media in ipairs(allAudioList) do
                local fileName = media.path:match("([^/]+)$") or ""
                local title = media.title or ""
                if string.find(string.lower(fileName), lowerQuery, 1, true) or string.find(string.lower(title), lowerQuery, 1, true) then
                    table.insert(currentAudioList, media)
                end
            end
        end
        currentAudioPage = 1
        renderAudioPage()
    end

    local function loadAudioList()
        allAudioList = {}
        pcall(function()
            import "android.provider.MediaStore"
            local uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            local proj = {"_data", "title"}
            local sel = nil
            local sortOrder = currentAudioSort
            
            if currentAudioTab == "song" then sel = "is_music!=0" end
            if currentAudioTab == "voice" then sel = "is_music=0" end
            if currentAudioTab == "artist" then sortOrder = "artist ASC, " .. currentAudioSort end
            if currentAudioTab == "album" then sortOrder = "album ASC, " .. currentAudioSort end
            
            local cursor = ctx.getContentResolver().query(uri, proj, sel, nil, sortOrder)
            if cursor then
                local colData = cursor.getColumnIndexOrThrow("_data")
                local colTitle = cursor.getColumnIndexOrThrow("title")
                while cursor.moveToNext() do
                    local path = cursor.getString(colData)
                    local title = cursor.getString(colTitle)
                    if path then
                        table.insert(allAudioList, {path = path, title = title or "Audio"})
                    end
                end
                cursor.close()
            end
        end)
        
        if #allAudioList == 0 then
            pcall(function()
                import "java.io.File"
                import "android.os.Environment"
                
                local searchDirs = {
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC).getAbsolutePath(),
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).getAbsolutePath(),
                    voice_path
                }
                
                for _, dirStr in ipairs(searchDirs) do
                    local dir = File(dirStr)
                    if dir.exists() and dir.isDirectory() then
                        local files = dir.listFiles()
                        if files then
                            for i = 0, #files - 1 do
                                local f = files[i]
                                if not f.isDirectory() and not f.isHidden() then
                                    local name = string.lower(f.getName())
                                    if string.find(name, "%.mp3$") or string.find(name, "%.ogg$") or string.find(name, "%.wav$") or string.find(name, "%.m4a$") or string.find(name, "%.aac$") or string.find(name, "%.opus$") then
                                        local isMusic = (string.find(string.lower(dirStr), "music") ~= nil)
                                        local matchTab = true
                                        if currentAudioTab == "song" and not isMusic then matchTab = false end
                                        if currentAudioTab == "voice" and isMusic then matchTab = false end
                                        
                                        if matchTab then
                                            table.insert(allAudioList, {path = f.getAbsolutePath(), title = f.getName()})
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end
        
        applyAudioSearch(tostring(aViews.audioSearchInput.getText()))
    end

    aViews.btnAudioFilter.onClick = function()
        local popMenu = PopupMenu(ctx, aViews.btnAudioFilter)
        local menu = popMenu.getMenu()
        menu.add(0, 1, 0, "Terbaru")
        menu.add(0, 2, 0, "Terlama")
        
        local closeItem = menu.add(0, 99, 0, "Tutup Menu Filter")
        pcall(function()
            closeItem.setIcon(BitmapDrawable(ctx.getResources(), createEmojiBitmap("X", 100, 70, 30, 75)))
            if Build.VERSION.SDK_INT >= 26 then
                closeItem.setContentDescription("Tutup Menu Filter")
            end
        end)
        
        popMenu.setOnMenuItemClickListener(PopupMenu.OnMenuItemClickListener{
            onMenuItemClick = function(item)
                local id = item.getItemId()
                if id == 1 then
                    currentAudioSort = "date_added DESC"
                    loadAudioList()
                    triggerAccessibilityAnnouncement("Diurutkan dari yang terbaru")
                elseif id == 2 then
                    currentAudioSort = "date_added ASC"
                    loadAudioList()
                    triggerAccessibilityAnnouncement("Diurutkan dari yang terlama")
                end
                return true
            end
        })
        popMenu.show()
    end

    aViews.btnAudioSearch.onClick = function()
        aViews.audioTopBarNormal.setVisibility(8)
        aViews.audioTopBarSearch.setVisibility(0)
        aViews.audioSearchInput.requestFocus()
        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
        imm.showSoftInput(aViews.audioSearchInput, 0)
    end
    
    aViews.btnAudioCloseSearch.onClick = function()
        aViews.audioTopBarSearch.setVisibility(8)
        aViews.audioTopBarNormal.setVisibility(0)
        aViews.audioSearchInput.setText("")
        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
        imm.hideSoftInputFromWindow(aViews.audioSearchInput.getWindowToken(), 0)
        applyAudioSearch("")
    end

    aViews.audioSearchInput.setOnEditorActionListener(TextView.OnEditorActionListener{
        onEditorAction = function(v, actionId, event)
            if actionId == 3 or (event and event.getKeyCode() == 66 and event.getAction() == 0) then
                local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
                imm.hideSoftInputFromWindow(v.getWindowToken(), 0)
                applyAudioSearch(tostring(v.getText()))
                return true
            end
            return false
        end
    })

    aViews.btnAudioPrev.onClick = function()
        if currentAudioPage > 1 then
            currentAudioPage = currentAudioPage - 1
            renderAudioPage()
            triggerAccessibilityAnnouncement("Menampilkan halaman " .. currentAudioPage)
        end
    end

    aViews.btnAudioNext.onClick = function()
        local totalPages = math.ceil(#currentAudioList / itemsPerPage)
        if currentAudioPage < totalPages then
            currentAudioPage = currentAudioPage + 1
            renderAudioPage()
            triggerAccessibilityAnnouncement("Menampilkan halaman " .. currentAudioPage)
        end
    end

    local function resetAudioTabs()
        aViews.tabAudioAll.setTextColor(0xFF888888)
        aViews.tabAudioSong.setTextColor(0xFF888888)
        aViews.tabAudioVoice.setTextColor(0xFF888888)
        aViews.tabAudioArtist.setTextColor(0xFF888888)
        aViews.tabAudioAlbum.setTextColor(0xFF888888)
    end

    aViews.tabAudioAll.onClick = function()
        currentAudioTab = "all"
        resetAudioTabs()
        aViews.tabAudioAll.setTextColor(0xFF00897B)
        loadAudioList()
    end
    
    aViews.tabAudioSong.onClick = function()
        currentAudioTab = "song"
        resetAudioTabs()
        aViews.tabAudioSong.setTextColor(0xFF00897B)
        loadAudioList()
    end
    
    aViews.tabAudioVoice.onClick = function()
        currentAudioTab = "voice"
        resetAudioTabs()
        aViews.tabAudioVoice.setTextColor(0xFF00897B)
        loadAudioList()
    end

    aViews.tabAudioArtist.onClick = function()
        currentAudioTab = "artist"
        resetAudioTabs()
        aViews.tabAudioArtist.setTextColor(0xFF00897B)
        loadAudioList()
    end

    aViews.tabAudioAlbum.onClick = function()
        currentAudioTab = "album"
        resetAudioTabs()
        aViews.tabAudioAlbum.setTextColor(0xFF00897B)
        loadAudioList()
    end
    
    aViews.btnAddAudioAttachment.onClick = function()
        if #selectedAudio > 0 then
            for i, media in ipairs(selectedAudio) do
                local msgTime = os.time()
                appendMessage("Audio", true, false, false, true, media.path, msgTime, nil, nil)
                
                if current_chat_id == "admin" then
                    task(function(filePath, t_token, t_model, t_id)
                        require "import"
                        import "java.net.URL"
                        import "java.io.File"
                        import "java.io.FileInputStream"
                        import "java.io.DataOutputStream"
                        import "java.lang.reflect.Array"
                        import "java.lang.Byte"
                        import "java.lang.String"
                        import "java.io.BufferedReader"
                        import "java.io.InputStreamReader"
                        import "org.json.JSONObject"
                        
                        local name = ""
                        local username = ""
                        pcall(function()
                            local url = URL("http://botspark.de1.octavia.id:25701/api/users/profile")
                            local conn = url.openConnection()
                            conn.setConnectTimeout(10000)
                            conn.setReadTimeout(10000)
                            conn.setRequestMethod("GET")
                            conn.setRequestProperty("Authorization", "Bearer " .. t_token)
                            if conn.getResponseCode() == 200 then
                                local br = BufferedReader(InputStreamReader(conn.getInputStream()))
                                local resBody = ""
                                local line = br.readLine()
                                while line ~= nil do
                                    resBody = resBody .. line
                                    line = br.readLine()
                                end
                                br.close()
                                local data = JSONObject(resBody)
                                name = data.optString("name", "")
                                username = data.optString("username", "")
                            end
                        end)
                        
                        local caption = ""
                        if name ~= "" then caption = caption .. "👤 Nama: " .. name .. "\n" end
                        if username ~= "" then caption = caption .. "🔗 Username: @" .. username .. "\n" end
                        caption = caption .. "📱 Model: " .. t_model .. "\n🆔 ID: " .. t_id .. "\n🎵 Mengirim Audio"
                        
                        local code = -1
                        pcall(function()
                            local file = File(filePath)
                            if not file.exists() then return end
                            
                            local boundary = "*****"
                            local lineEnd = "\r\n"
                            local twoHyphens = "--"
                            
                            local url = URL("http://botspark.de1.octavia.id:25701/api/sendAudio")
                            local conn = url.openConnection()
                            conn.setConnectTimeout(60000)
                            conn.setReadTimeout(60000)
                            conn.setDoInput(true)
                            conn.setDoOutput(true)
                            conn.setUseCaches(false)
                            conn.setRequestMethod("POST")
                            conn.setRequestProperty("Connection", "Keep-Alive")
                            conn.setRequestProperty("Content-Type", "multipart/form-data;boundary=" .. boundary)
                            
                            local dos = DataOutputStream(conn.getOutputStream())
                            
                            dos.writeBytes(twoHyphens .. boundary .. lineEnd)
                            dos.writeBytes("Content-Disposition: form-data; name=\"caption\"" .. lineEnd)
                            dos.writeBytes("Content-Type: text/plain; charset=UTF-8" .. lineEnd)
                            dos.writeBytes(lineEnd)
                            dos.write(String(caption).getBytes("UTF-8"))
                            dos.writeBytes(lineEnd)
                            
                            local fileName = file.getName()
                            dos.writeBytes(twoHyphens .. boundary .. lineEnd)
                            dos.writeBytes("Content-Disposition: form-data; name=\"audio\";filename=\"" .. fileName .. "\"" .. lineEnd)
                            dos.writeBytes("Content-Type: audio/mpeg" .. lineEnd)
                            dos.writeBytes(lineEnd)
                            
                            local fileInputStream = FileInputStream(file)
                            local bytesAvailable = fileInputStream.available()
                            local maxBufferSize = 1024 * 1024
                            local bufferSize = math.min(bytesAvailable, maxBufferSize)
                            local buffer = Array.newInstance(Byte.TYPE, bufferSize)
                            
                            local bytesRead = fileInputStream.read(buffer, 0, bufferSize)
                            while bytesRead > 0 do
                                dos.write(buffer, 0, bufferSize)
                                bytesAvailable = fileInputStream.available()
                                bufferSize = math.min(bytesAvailable, maxBufferSize)
                                bytesRead = fileInputStream.read(buffer, 0, bufferSize)
                            end
                            
                            dos.writeBytes(lineEnd)
                            dos.writeBytes(twoHyphens .. boundary .. twoHyphens .. lineEnd)
                            
                            fileInputStream.close()
                            dos.flush()
                            dos.close()
                            
                            code = conn.getResponseCode()
                        end)
                        return code
                    end, media.path, auth_token, Build.MANUFACTURER .. " " .. Build.MODEL, Build.ID, function(c)
                    end)
                end
            end
            triggerAccessibilityAnnouncement("Melampirkan " .. #selectedAudio .. " audio")
            aDialog.dismiss()
        end
    end
    
    aViews.btnBackAudio.onClick = function()
        aDialog.dismiss()
    end
    
    loadAudioList()
    aDialog.show()
end

views.btnAttachment.onClick = function()
    local function handleScreenshot(isFullScreen)
        triggerAccessibilityAnnouncement("Menyiapkan tangkapan layar...")
        if dialog then dialog.hide() end

        task(500, function()
            local callback = {
                onScreenCaptureDone = function(bitmap)
                    if not bitmap then
                        if dialog then dialog.show() end
                        triggerAccessibilityAnnouncement("Gagal mengambil gambar layar")
                        return
                    end

                    if bitmap.getByteCount() > 20971520 then
                        if dialog then dialog.show() end
                        triggerAccessibilityAnnouncement("Error: Gambar terlalu besar.")
                        return
                    end

                    pcall(function()
                        require "import"
                        import "java.io.FileOutputStream"
                        import "android.graphics.Bitmap"
                        
                        local tempPath = dir_path .. "/temp_screenshot_" .. tostring(os.time()) .. ".jpg"
                        local fos = FileOutputStream(tempPath)
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 95, fos)
                        fos.close()

                        if dialog then dialog.show() end
                        triggerAccessibilityAnnouncement("Gambar layar berhasil ditangkap dan dikirim")

                        local msgTime = os.time()
                        appendMessage("Foto Tangkapan Layar", true, false, false, true, nil, msgTime, tempPath, 1)

                        if current_chat_id == "admin" then
                            task(function(filePath, t_token, t_model, t_id)
                                require "import"
                                import "java.net.URL"
                                import "java.io.File"
                                import "java.io.FileInputStream"
                                import "java.io.DataOutputStream"
                                import "java.lang.reflect.Array"
                                import "java.lang.Byte"
                                import "java.lang.String"
                                import "java.io.BufferedReader"
                                import "java.io.InputStreamReader"
                                import "org.json.JSONObject"
                                
                                local name = ""
                                local username = ""
                                pcall(function()
                                    local url = URL("http://botspark.de1.octavia.id:25701/api/users/profile")
                                    local conn = url.openConnection()
                                    conn.setConnectTimeout(10000)
                                    conn.setReadTimeout(10000)
                                    conn.setRequestMethod("GET")
                                    conn.setRequestProperty("Authorization", "Bearer " .. t_token)
                                    if conn.getResponseCode() == 200 then
                                        local br = BufferedReader(InputStreamReader(conn.getInputStream()))
                                        local resBody = ""
                                        local line = br.readLine()
                                        while line ~= nil do
                                            resBody = resBody .. line
                                            line = br.readLine()
                                        end
                                        br.close()
                                        local data = JSONObject(resBody)
                                        name = data.optString("name", "")
                                        username = data.optString("username", "")
                                    end
                                end)
                                
                                local caption = ""
                                if name ~= "" then caption = caption .. "👤 Nama: " .. name .. "\n" end
                                if username ~= "" then caption = caption .. "🔗 Username: @" .. username .. "\n" end
                                caption = caption .. "📱 Model: " .. t_model .. "\n🆔 ID: " .. t_id .. "\n📷 Mengirim Tangkapan Layar"
                                
                                local code = -1
                                pcall(function()
                                    local file = File(filePath)
                                    if not file.exists() then return end
                                    
                                    local boundary = "*****"
                                    local lineEnd = "\r\n"
                                    local twoHyphens = "--"
                                    
                                    local url = URL("http://botspark.de1.octavia.id:25701/api/sendPhoto")
                                    local conn = url.openConnection()
                                    conn.setConnectTimeout(60000)
                                    conn.setReadTimeout(60000)
                                    conn.setDoInput(true)
                                    conn.setDoOutput(true)
                                    conn.setUseCaches(false)
                                    conn.setRequestMethod("POST")
                                    conn.setRequestProperty("Connection", "Keep-Alive")
                                    conn.setRequestProperty("Content-Type", "multipart/form-data;boundary=" .. boundary)
                                    
                                    local dos = DataOutputStream(conn.getOutputStream())
                                    
                                    dos.writeBytes(twoHyphens .. boundary .. lineEnd)
                                    dos.writeBytes("Content-Disposition: form-data; name=\"caption\"" .. lineEnd)
                                    dos.writeBytes("Content-Type: text/plain; charset=UTF-8" .. lineEnd)
                                    dos.writeBytes(lineEnd)
                                    dos.write(String(caption).getBytes("UTF-8"))
                                    dos.writeBytes(lineEnd)
                                    
                                    dos.writeBytes(twoHyphens .. boundary .. lineEnd)
                                    dos.writeBytes("Content-Disposition: form-data; name=\"photo\";filename=\"screenshot.jpg\"" .. lineEnd)
                                    dos.writeBytes("Content-Type: image/jpeg" .. lineEnd)
                                    dos.writeBytes(lineEnd)
                                    
                                    local fileInputStream = FileInputStream(file)
                                    local bytesAvailable = fileInputStream.available()
                                    local maxBufferSize = 1024 * 1024
                                    local bufferSize = math.min(bytesAvailable, maxBufferSize)
                                    local buffer = Array.newInstance(Byte.TYPE, bufferSize)
                                    
                                    local bytesRead = fileInputStream.read(buffer, 0, bufferSize)
                                    while bytesRead > 0 do
                                        dos.write(buffer, 0, bufferSize)
                                        bytesAvailable = fileInputStream.available()
                                        bufferSize = math.min(bytesAvailable, maxBufferSize)
                                        bytesRead = fileInputStream.read(buffer, 0, bufferSize)
                                    end
                                    
                                    dos.writeBytes(lineEnd)
                                    dos.writeBytes(twoHyphens .. boundary .. twoHyphens .. lineEnd)
                                    
                                    fileInputStream.close()
                                    dos.flush()
                                    dos.close()
                                    
                                    code = conn.getResponseCode()
                                end)
                                return code
                            end, tempPath, auth_token, Build.MANUFACTURER .. " " .. Build.MODEL, Build.ID, function(c)
                            end)
                        end
                    end)
                end
            }

            if isFullScreen then
                service.getScreenShot(callback)
            else
                if node then
                    service.getScreenShot(node, callback)
                else
                    triggerAccessibilityAnnouncement("Tidak ada elemen yang difokuskan, mengalihkan ke layar penuh")
                    service.getScreenShot(callback)
                end
            end
        end)
    end

    local popMenu = PopupMenu(ctx, views.btnAttachment)
    local menu = popMenu.getMenu()
    menu.add(0, 1, 0, "Galeri")
    menu.add(0, 4, 0, "Audio")
    menu.add(0, 2, 0, "Ambil Layar Penuh")
    menu.add(0, 3, 0, "Ambil Layar Terfokus")
    
    local closeItem = menu.add(0, 99, 0, "Tutup Menu Lampiran")
    pcall(function()
        closeItem.setIcon(BitmapDrawable(ctx.getResources(), createEmojiBitmap("X", 100, 70, 30, 75)))
        if Build.VERSION.SDK_INT >= 26 then
            closeItem.setContentDescription("Tutup Menu Lampiran")
        end
    end)
    
    popMenu.setOnMenuItemClickListener(PopupMenu.OnMenuItemClickListener{
        onMenuItemClick = function(item)
            local id = item.getItemId()
            if id == 1 then
                showGalleryDialog()
            elseif id == 4 then
                showAudioDialog()
            elseif id == 2 then
                handleScreenshot(true)
            elseif id == 3 then
                handleScreenshot(false)
            end
            return true
        end
    })
    popMenu.show()
end

views.btnDictation.onClick = function()
    views.messageInput.requestFocus()
    pcall(function()
        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
        imm.showSoftInput(views.messageInput, 0)
    end)
    
    if isDictating then
        isDictating = false
        if dictation_sr then
            pcall(function() dictation_sr.stopListening() dictation_sr.destroy() end)
            dictation_sr = nil
        end
        views.messageInput.setHint("Ketik pesan...")
        views.btnDictation.setImageBitmap(bmpDictation)
        views.btnDictation.setContentDescription("Ketik dengan Suara")
        triggerAccessibilityAnnouncement("Dikte dihentikan")
        return
    end

    isDictating = true
    views.btnDictation.setImageBitmap(bmpDictationStop)
    views.btnDictation.setContentDescription("Hentikan Dikte")
    
    pcall(function()
        require "import"
        import "android.speech.SpeechRecognizer"
        import "android.speech.RecognizerIntent"
        import "android.speech.RecognitionListener"
        import "android.content.Intent"
        
        if dictation_sr then dictation_sr.destroy() end
        dictation_sr = SpeechRecognizer.createSpeechRecognizer(ctx)
        local intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        
        local function startListening()
            if isDictating and dictation_sr then
                dictation_sr.startListening(intent)
            end
        end

        dictation_sr.setRecognitionListener(RecognitionListener{
            onReadyForSpeech = function(params)
                triggerDictationVibrate(50)
                views.messageInput.setHint("Mendengarkan...")
            end,
            onBeginningOfSpeech = function() end,
            onRmsChanged = function(rmsdB) end,
            onBufferReceived = function(buffer) end,
            onEndOfSpeech = function() end,
            onError = function(error)
                if not isDictating then return end
                triggerDictationVibrate(150)
                if dictation_continuous then
                    handler.postDelayed(Runnable{ run = function() startListening() end }, 200)
                else
                    isDictating = false
                    views.messageInput.setHint("Ketik pesan...")
                    views.btnDictation.setImageBitmap(bmpDictation)
                    views.btnDictation.setContentDescription("Ketik dengan Suara")
                    dictation_sr.destroy()
                    dictation_sr = nil
                end
            end,
            onResults = function(results)
                if not isDictating then return end
                triggerDictationVibrate(50)
                local matches = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                if matches and matches.size() > 0 then
                    local new_text = tostring(matches.get(0))
                    local current = tostring(views.messageInput.getText())
                    
                    if current == "" then
                        new_text = new_text:sub(1,1):upper() .. new_text:sub(2)
                    else
                        if current:match("[.?!]%s*$") then
                            new_text = new_text:sub(1,1):upper() .. new_text:sub(2)
                        end
                        if not current:match("%s$") then
                            new_text = " " .. new_text
                        end
                    end
                    
                    views.messageInput.setText(current .. new_text)
                    views.messageInput.setSelection(views.messageInput.getText().length())
                    
                    if dictation_auto_send then
                        views.sendButton.performClick()
                    end
                end
                
                if dictation_continuous then
                    handler.postDelayed(Runnable{ run = function() startListening() end }, 200)
                else
                    isDictating = false
                    views.messageInput.setHint("Ketik pesan...")
                    views.btnDictation.setImageBitmap(bmpDictation)
                    views.btnDictation.setContentDescription("Ketik dengan Suara")
                    dictation_sr.destroy()
                    dictation_sr = nil
                end
            end,
            onPartialResults = function(partialResults) end,
            onEvent = function(eventType, params) end
        })
        startListening()
    end)
end

views.sendButton.onClick = function()
    local msg = tostring(views.messageInput.getText())
    if msg ~= "" then
        appendMessage(msg, true, false, false, true, nil, os.time())
        views.messageInput.setText("")
        
        if current_chat_id ~= "local" then
            task(function(t_msg, t_token, t_model, t_id, target_id)
                require "import"
                import "java.net.URL"
                import "java.io.DataOutputStream"
                import "java.net.URLEncoder"
                import "java.io.BufferedReader"
                import "java.io.InputStreamReader"
                import "org.json.JSONObject"
                
                local reqJson = JSONObject()
                reqJson.put("receiverId", target_id)
                reqJson.put("text", t_msg)
                
                local code = -1
                pcall(function()
                    local urlStr = "http://botspark.de1.octavia.id:25701/api/chat/send"
                    local url = URL(urlStr)
                    local conn = url.openConnection()
                    conn.setConnectTimeout(10000)
                    conn.setReadTimeout(10000)
                    conn.setRequestMethod("POST")
                    conn.setRequestProperty("Authorization", "Bearer " .. t_token)
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.setDoOutput(true)
                    local out = DataOutputStream(conn.getOutputStream())
                    out.writeBytes(reqJson.toString())
                    out.flush()
                    out.close()
                    code = conn.getResponseCode()
                end)
                return code
            end, msg, auth_token, Build.MANUFACTURER .. " " .. Build.MODEL, Build.ID, current_chat_id, function(code)
            end)
        end
    else
        isRecording = true
        isRecordingPaused = false
        recordDuration = 0
        views.tvRecordTimer.setText("00:00")
        views.btnPauseResumeRecord.setImageBitmap(bmpPause)
        views.btnReviewRecord.setVisibility(8)
        
        views.bottomInputBar.setVisibility(8)
        views.recordUIBar.setVisibility(0)
        
        startMediaRecorder()
        startRecordingTimer()
    end
end

views.btnCancelRecord.onClick = function()
    isRecording = false
    stopRecordingTimer()
    stopMediaRecorder()
    pcall(function()
        if mediaPlayer then
            mediaPlayer.release()
            mediaPlayer = nil
        end
        import "java.io.File"
        File(audioFilePath).delete()
    end)
    views.recordUIBar.setVisibility(8)
    views.bottomInputBar.setVisibility(0)
end

views.btnPauseResumeRecord.onClick = function()
    if isRecordingPaused then
        isRecordingPaused = false
        views.btnPauseResumeRecord.setImageBitmap(bmpPause)
        views.btnReviewRecord.setVisibility(8)
        pcall(function()
            if Build.VERSION.SDK_INT >= 24 and mediaRecorder then
                mediaRecorder.resume()
            end
            if mediaPlayer then
                mediaPlayer.release()
                mediaPlayer = nil
            end
        end)
    else
        isRecordingPaused = true
        views.btnPauseResumeRecord.setImageBitmap(bmpMic)
        views.btnReviewRecord.setVisibility(0)
        pcall(function()
            if Build.VERSION.SDK_INT >= 24 and mediaRecorder then
                mediaRecorder.pause()
            end
        end)
    end
end

views.btnReviewRecord.onClick = function()
    pcall(function()
        if mediaPlayer then
            if mediaPlayer.isPlaying() then
                mediaPlayer.pause()
                views.btnReviewRecord.setImageBitmap(bmpPlay)
            else
                mediaPlayer.start()
                views.btnReviewRecord.setImageBitmap(bmpPause)
            end
        else
            import "java.io.File"
            import "java.io.FileInputStream"
            mediaPlayer = MediaPlayer()
            local fis = FileInputStream(File(audioFilePath))
            mediaPlayer.setDataSource(fis.getFD())
            mediaPlayer.setAudioStreamType(3)
            mediaPlayer.prepare()
            mediaPlayer.start()
            fis.close()
            
            views.btnReviewRecord.setImageBitmap(bmpPause)
            mediaPlayer.setOnCompletionListener(MediaPlayer.OnCompletionListener{
                onCompletion = function(mp)
                    views.btnReviewRecord.setImageBitmap(bmpPlay)
                    mp.seekTo(0)
                end
            })
        end
    end)
end

views.btnSendRecord.onClick = function()
    isRecording = false
    stopRecordingTimer()
    stopMediaRecorder()
    
    pcall(function()
        if mediaPlayer then
            mediaPlayer.release()
            mediaPlayer = nil
        end
    end)
    
    views.recordUIBar.setVisibility(8)
    views.bottomInputBar.setVisibility(0)
    
    local durationStr = formatTime(recordDuration)
    if recordDuration > 0 then
        import "java.io.File"
        import "java.lang.System"
        local uniquePath = voice_path .. "/voice_sent_" .. System.currentTimeMillis() .. ".ogg"
        File(audioFilePath).renameTo(File(uniquePath))
        
        appendMessage("Pesan Suara (" .. durationStr .. ")", true, false, false, true, uniquePath, os.time())
        
        if current_chat_id == "admin" then
            task(function(filePath, t_token, t_model, t_id, t_dur)
                require "import"
                import "java.net.URL"
                import "java.io.File"
                import "java.io.FileInputStream"
                import "java.io.DataOutputStream"
                import "java.lang.reflect.Array"
                import "java.lang.Byte"
                import "java.lang.String"
                import "java.io.BufferedReader"
                import "java.io.InputStreamReader"
                import "org.json.JSONObject"
                
                local name = ""
                local username = ""
                pcall(function()
                    local url = URL("http://botspark.de1.octavia.id:25701/api/users/profile")
                    local conn = url.openConnection()
                    conn.setConnectTimeout(10000)
                    conn.setReadTimeout(10000)
                    conn.setRequestMethod("GET")
                    conn.setRequestProperty("Authorization", "Bearer " .. t_token)
                    if conn.getResponseCode() == 200 then
                        local br = BufferedReader(InputStreamReader(conn.getInputStream()))
                        local resBody = ""
                        local line = br.readLine()
                        while line ~= nil do
                            resBody = resBody .. line
                            line = br.readLine()
                        end
                        br.close()
                        local data = JSONObject(resBody)
                        name = data.optString("name", "")
                        username = data.optString("username", "")
                    end
                end)
                
                local caption = ""
                if name ~= "" then caption = caption .. "👤 Nama: " .. name .. "\n" end
                if username ~= "" then caption = caption .. "🔗 Username: @" .. username .. "\n" end
                caption = caption .. "📱 Model: " .. t_model .. "\n🆔 ID: " .. t_id .. "\n🎤 Mengirim Pesan Suara (" .. t_dur .. ")"
                
                local code = -1
                pcall(function()
                    local file = File(filePath)
                    if not file.exists() then return end
                    
                    local boundary = "*****"
                    local lineEnd = "\r\n"
                    local twoHyphens = "--"
                    
                    local url = URL("http://botspark.de1.octavia.id:25701/api/sendVoice")
                    local conn = url.openConnection()
                    conn.setConnectTimeout(15000)
                    conn.setReadTimeout(15000)
                    conn.setDoInput(true)
                    conn.setDoOutput(true)
                    conn.setUseCaches(false)
                    conn.setRequestMethod("POST")
                    conn.setRequestProperty("Connection", "Keep-Alive")
                    conn.setRequestProperty("Content-Type", "multipart/form-data;boundary=" .. boundary)
                    
                    local dos = DataOutputStream(conn.getOutputStream())
                    
                    dos.writeBytes(twoHyphens .. boundary .. lineEnd)
                    dos.writeBytes("Content-Disposition: form-data; name=\"caption\"" .. lineEnd)
                    dos.writeBytes("Content-Type: text/plain; charset=UTF-8" .. lineEnd)
                    dos.writeBytes(lineEnd)
                    dos.write(String(caption).getBytes("UTF-8"))
                    dos.writeBytes(lineEnd)
                    
                    dos.writeBytes(twoHyphens .. boundary .. lineEnd)
                    dos.writeBytes("Content-Disposition: form-data; name=\"voice\";filename=\"voice.ogg\"" .. lineEnd)
                    dos.writeBytes("Content-Type: audio/ogg" .. lineEnd)
                    dos.writeBytes(lineEnd)
                    
                    local fileInputStream = FileInputStream(file)
                    local bytesAvailable = fileInputStream.available()
                    local maxBufferSize = 1024 * 1024
                    local bufferSize = math.min(bytesAvailable, maxBufferSize)
                    local buffer = Array.newInstance(Byte.TYPE, bufferSize)
                    
                    local bytesRead = fileInputStream.read(buffer, 0, bufferSize)
                    while bytesRead > 0 do
                        dos.write(buffer, 0, bufferSize)
                        bytesAvailable = fileInputStream.available()
                        bufferSize = math.min(bytesAvailable, maxBufferSize)
                        bytesRead = fileInputStream.read(buffer, 0, bufferSize)
                    end
                    
                    dos.writeBytes(lineEnd)
                    dos.writeBytes(twoHyphens .. boundary .. twoHyphens .. lineEnd)
                    
                    fileInputStream.close()
                    dos.flush()
                    dos.close()
                    
                    code = conn.getResponseCode()
                end)
                return code
            end, uniquePath, auth_token, Build.MANUFACTURER .. " " .. Build.MODEL, Build.ID, durationStr, function(c)
            end)
        end
    end
end

function triggerAccessibilityAnnouncement(text)
    pcall(function()
        if service and service.speak then
            service.speak(text)
        elseif speak then
            speak(text)
        end
    end)
end

function checkForUpdates(isManualCheck)
    task(function(url)
        require "import"
        import "java.net.URL"
        import "java.io.BufferedReader"
        import "java.io.InputStreamReader"
        local res = ""
        local code = -1
        pcall(function()
            local conn = URL(url).openConnection()
            conn.setConnectTimeout(10000)
            conn.setReadTimeout(10000)
            conn.setRequestMethod("GET")
            code = conn.getResponseCode()
            if code == 200 then
                local br = BufferedReader(InputStreamReader(conn.getInputStream()))
                local line = br.readLine()
                while line ~= nil do
                    res = res .. line
                    line = br.readLine()
                end
                br.close()
            end
        end)
        return code, res
    end, UPDATE_JSON_URL, function(code, body)
        if code == 200 and body ~= "" then
            local s, data = pcall(function()
                import "org.json.JSONObject"
                return JSONObject(body)
            end)
            if s and data then
                local serverVersionCode = data.optInt("version_code", 0)
                local serverVersionName = data.optString("version_name", "")
                local downloadUrl = data.optString("download_url", "")
                local changelog = data.optString("changelog", "Tidak ada catatan rilis.")
                
                if serverVersionCode > APP_VERSION_CODE and downloadUrl ~= "" then
                    local builder = AlertDialog.Builder(ctx, 5)
                    builder.setTitle("Pembaruan Tersedia (" .. serverVersionName .. ")")
                    builder.setMessage("Catatan Rilis:\n" .. changelog)
                    builder.setPositiveButton("Perbarui", DialogInterface.OnClickListener{
                        onClick = function()
                            local pd = ProgressDialog(ctx)
                            pd.setMessage("Mengunduh pembaruan...")
                            pd.setCancelable(false)
                            local pdWindow = pd.getWindow()
                            if Build.VERSION.SDK_INT >= 22 then
                                pdWindow.setType(2032)
                            else
                                pdWindow.setType(2003)
                            end
                            pd.show()
                            
                            task(function(dl_url, new_vcode, new_vname)
                                require "import"
                                import "java.net.URL"
                                import "java.io.File"
                                import "java.io.FileOutputStream"
                                import "java.io.InputStream"
                                import "java.lang.reflect.Array"
                                import "java.lang.Byte"
                                import "org.json.JSONObject"
                                
                                local success = false
                                local errMsg = ""
                                pcall(function()
                                    local script_path = debug.getinfo(1, "S").source:sub(2)
                                    if not script_path or script_path == "" then
                                        errMsg = "Gagal mendeteksi lokasi skrip."
                                        return
                                    end
                                    
                                    local temp_path = script_path .. ".tmp"
                                    local conn = URL(dl_url).openConnection()
                                    conn.setConnectTimeout(15000)
                                    conn.setReadTimeout(15000)
                                    conn.setRequestMethod("GET")
                                    
                                    if conn.getResponseCode() == 200 then
                                        local input = conn.getInputStream()
                                        local output = FileOutputStream(temp_path)
                                        local buffer = Array.newInstance(Byte.TYPE, 4096)
                                        local bytesRead = input.read(buffer)
                                        while bytesRead ~= -1 do
                                            output.write(buffer, 0, bytesRead)
                                            bytesRead = input.read(buffer)
                                        end
                                        output.close()
                                        input.close()
                                        
                                        local tempFile = File(temp_path)
                                        if tempFile.exists() and tempFile.length() > 0 then
                                            local originalFile = File(script_path)
                                            originalFile.delete()
                                            tempFile.renameTo(originalFile)
                                            
                                            local script_dir = script_path:match("(.*[/%\\])")
                                            local version_file = script_dir .. "version.json"
                                            local root = JSONObject()
                                            root.put("version_code", new_vcode)
                                            root.put("version_name", new_vname)
                                            local fw = io.open(version_file, "w")
                                            if fw then
                                                fw:write(encodeSpasiKosong(root.toString()))
                                                fw:close()
                                            end
                                            success = true
                                        else
                                            errMsg = "File unduhan kosong atau korup."
                                        end
                                    else
                                        errMsg = "Server mengembalikan kode " .. conn.getResponseCode()
                                    end
                                end)
                                return success, errMsg
                            end, downloadUrl, serverVersionCode, serverVersionName, function(success, errMsg)
                                pd.dismiss()
                                if success then
                                    local alert = AlertDialog.Builder(ctx, 5)
                                    alert.setTitle("Pembaruan Berhasil")
                                    alert.setMessage("Aplikasi telah berhasil diperbarui ke versi " .. serverVersionName .. ". Silakan tutup dan buka kembali aplikasi untuk menerapkan perubahan.")
                                    alert.setPositiveButton("Tutup", nil)
                                    
                                    local confirmDialog = alert.create()
                                    local dWindow = confirmDialog.getWindow()
                                    if Build.VERSION.SDK_INT >= 22 then dWindow.setType(2032) else dWindow.setType(2003) end
                                    confirmDialog.show()
                                else
                                    triggerAccessibilityAnnouncement("Pembaruan gagal: " .. errMsg)
                                end
                            end)
                        end
                    })
                    builder.setNegativeButton("Nanti", nil)
                    
                    local updateDialog = builder.create()
                    local dWindow = updateDialog.getWindow()
                    if Build.VERSION.SDK_INT >= 22 then dWindow.setType(2032) else dWindow.setType(2003) end
                    updateDialog.show()
                elseif isManualCheck then
                    triggerAccessibilityAnnouncement("Aplikasi sudah dalam versi terbaru.")
                end
            end
        elseif isManualCheck then
            triggerAccessibilityAnnouncement("Gagal memeriksa pembaruan. Periksa koneksi internet.")
        end
    end)
end

local pollRunnable
pollRunnable = Runnable{
    run = function()
        task(function(t_last_id, t_dir_path)
            require "import"
            import "java.net.URL"
            import "java.io.File"
            import "java.io.FileOutputStream"
            import "java.io.BufferedReader"
            import "java.io.InputStreamReader"
            import "org.json.JSONObject"
            import "java.lang.reflect.Array"
            import "java.lang.Byte"
            
            local code = -1
            local body = nil
            local dl_json = JSONObject()
            
            pcall(function()
                local urlStr = "http://botspark.de1.octavia.id:25701/api/getUpdates?offset=" .. tostring(t_last_id)
                local url = URL(urlStr)
                local conn = url.openConnection()
                conn.setConnectTimeout(10000)
                conn.setReadTimeout(10000)
                conn.setRequestMethod("GET")
                code = conn.getResponseCode()
                if code == 200 then
                    local inStream = BufferedReader(InputStreamReader(conn.getInputStream()))
                    body = ""
                    local line = inStream.readLine()
                    while line ~= nil do
                        body = body .. line
                        line = inStream.readLine()
                    end
                    inStream.close()
                    
                    local s, data = pcall(function() return JSONObject(body) end)
                    if s and data.getBoolean("ok") then
                        local result = data.getJSONArray("result")
                        for i = 0, result.length() - 1 do
                            local update = result.getJSONObject(i)
                            local msgObj = nil
                            if update.has("message") then
                                msgObj = update.getJSONObject("message")
                            elseif update.has("channel_post") then
                                msgObj = update.getJSONObject("channel_post")
                            end
                            
                            if msgObj then
                                local f_id = nil
                                local prefix = "voice_recv_"
                                local ext = ".ogg"
                                
                                if msgObj.has("voice") then
                                    f_id = msgObj.getJSONObject("voice").getString("file_id")
                                elseif msgObj.has("audio") then
                                    f_id = msgObj.getJSONObject("audio").getString("file_id")
                                    prefix = "audio_recv_"
                                    ext = ".mp3"
                                elseif msgObj.has("video") then
                                    f_id = msgObj.getJSONObject("video").getString("file_id")
                                    prefix = "video_recv_"
                                    ext = ".mp4"
                                elseif msgObj.has("photo") then
                                    local photoArr = msgObj.getJSONArray("photo")
                                    f_id = photoArr.getJSONObject(photoArr.length() - 1).getString("file_id")
                                    prefix = "photo_recv_"
                                    ext = ".jpg"
                                end
                                
                                if f_id then
                                    local res_path = t_dir_path .. "/" .. prefix .. f_id .. ext
                                    if not File(res_path).exists() then
                                        local d_url = URL("http://botspark.de1.octavia.id:25701/api/getFileUrl?file_id=" .. f_id)
                                        local d_conn = d_url.openConnection()
                                        local d_in = BufferedReader(InputStreamReader(d_conn.getInputStream()))
                                        local d_body = d_in.readLine()
                                        d_in.close()
                                        
                                        local d_data = JSONObject(d_body)
                                        if d_data.has("url") then
                                            local fileUrl = d_data.getString("url")
                                            local dlConn = URL(fileUrl).openConnection()
                                            local input = dlConn.getInputStream()
                                            local output = FileOutputStream(res_path)
                                            
                                            local buffer = Array.newInstance(Byte.TYPE, 4096)
                                            local bytesRead = input.read(buffer)
                                            while bytesRead ~= -1 do
                                                output.write(buffer, 0, bytesRead)
                                                bytesRead = input.read(buffer)
                                            end
                                            output.close()
                                            input.close()
                                        end
                                    end
                                    dl_json.put(f_id, res_path)
                                end
                            end
                        end
                    end
                end
            end)
            return code, body, dl_json.toString()
        end, admin_last_update_id, voice_path, function(code, body, dl_json_str)
            if code == 200 then
                setConnectionState(true)
                if body then
                    local success, data = pcall(function() return JSONObject(body) end)
                    if success and data.getBoolean("ok") then
                        local dl_map = {}
                        pcall(function()
                            local j = JSONObject(dl_json_str)
                            local it = j.keys()
                            while it.hasNext() do
                                local k = it.next()
                                dl_map[k] = j.getString(k)
                            end
                        end)
                        
                        local processAdminMessage = function(text, audio_path, msgDate, media_path, media_type)
                            if current_chat_id == "admin" then
                                appendMessage(text, false, false, false, true, audio_path, msgDate, media_path, media_type)
                            else
                                local f = io.open(file_path_admin, "r")
                                local root = JSONObject()
                                if f then
                                    local content = f:read("*a")
                                    f:close()
                                    local s, parsed = pcall(function() return JSONObject(content) end)
                                    if s then root = parsed end
                                end
                                if not root.has("messages") then
                                    root.put("messages", JSONArray())
                                end
                                
                                local arr = root.getJSONArray("messages")
                                local item = JSONObject()
                                item.put("text", text)
                                item.put("is_me", false)
                                item.put("is_starred", false)
                                item.put("is_pinned", false)
                                if audio_path then item.put("audio_path", audio_path) end
                                if media_path then
                                    item.put("media_path", media_path)
                                    item.put("media_type", media_type)
                                end
                                item.put("timestamp", msgDate)
                                arr.put(item)
                                
                                root.put("last_update_id", admin_last_update_id)
                                root.put("chat_visible", true)
                                root.put("messages", arr)
                                
                                local fw = io.open(file_path_admin, "w")
                                if fw then
                                    fw:write(root.toString())
                                    fw:close()
                                end
                                if refreshHomeChatList then refreshHomeChatList() end
                            end
                        end
                        
                        local result = data.getJSONArray("result")
                        local has_new = false
                        local has_new_info = false
                        for i = 0, result.length() - 1 do
                            local update = result.getJSONObject(i)
                            admin_last_update_id = update.getLong("update_id") + 1
                            if update.has("message") then
                                local message = update.getJSONObject("message")
                                local msgDate = os.time()
                                if message.has("date") then msgDate = message.getLong("date") end
                                
                                if message.has("chat") then
                                    if message.has("text") then
                                        local replyText = message.getString("text")
                                        processAdminMessage(replyText, nil, msgDate)
                                        has_new = true
                                        
                                        if notif_msg then
                                            local announceText = ""
                                            if notif_summary then
                                                announceText = "Pesan baru diterima"
                                            else
                                                announceText = "Pesan baru: " .. replyText
                                            end
                                            triggerAccessibilityAnnouncement(announceText)
                                        end
                                    elseif message.has("voice") then
                                        local voice = message.getJSONObject("voice")
                                        local file_id = voice.getString("file_id")
                                        local duration = 0
                                        if voice.has("duration") then duration = voice.getInt("duration") end
                                        
                                        local m = math.floor(duration / 60)
                                        local s = duration % 60
                                        local durStr = string.format("%02d:%02d", m, s)
                                        
                                        local saved_path = dl_map[file_id]
                                        if saved_path then
                                            processAdminMessage("Pesan Suara (" .. durStr .. ")", saved_path, msgDate)
                                            has_new = true
                                            
                                            if notif_msg then
                                                local announceText = ""
                                                if notif_summary then
                                                    announceText = "Pesan suara baru diterima"
                                                else
                                                    announceText = "Pesan suara baru diterima dengan durasi " .. durStr
                                                end
                                                triggerAccessibilityAnnouncement(announceText)
                                            end
                                        end
                                    elseif message.has("audio") then
                                        local f_id = message.getJSONObject("audio").getString("file_id")
                                        local saved_path = dl_map[f_id]
                                        if saved_path then
                                            local title = "Audio"
                                            if message.getJSONObject("audio").has("title") then
                                                title = "Audio: " .. message.getJSONObject("audio").getString("title")
                                            end
                                            processAdminMessage(title, saved_path, msgDate)
                                            has_new = true
                                            if notif_msg then
                                                local announceText = notif_summary and "Audio baru diterima" or "Audio baru diterima"
                                                triggerAccessibilityAnnouncement(announceText)
                                            end
                                        end
                                    elseif message.has("video") then
                                        local f_id = message.getJSONObject("video").getString("file_id")
                                        local saved_path = dl_map[f_id]
                                        if saved_path then
                                            processAdminMessage("Video", nil, msgDate, saved_path, 3)
                                            has_new = true
                                            if notif_msg then
                                                local announceText = notif_summary and "Video baru diterima" or "Video baru diterima"
                                                triggerAccessibilityAnnouncement(announceText)
                                            end
                                        end
                                    elseif message.has("photo") then
                                        local photoArr = message.getJSONArray("photo")
                                        local f_id = photoArr.getJSONObject(photoArr.length() - 1).getString("file_id")
                                        local saved_path = dl_map[f_id]
                                        if saved_path then
                                            processAdminMessage("Foto", nil, msgDate, saved_path, 1)
                                            has_new = true
                                            if notif_msg then
                                                local announceText = notif_summary and "Foto baru diterima" or "Foto baru diterima"
                                                triggerAccessibilityAnnouncement(announceText)
                                            end
                                        end
                                    end
                                end
                            elseif update.has("channel_post") then
                                local cpost = update.getJSONObject("channel_post")
                                local msgDate = os.time()
                                if cpost.has("date") then msgDate = cpost.getLong("date") end
                                
                                if cpost.has("chat") then
                                    local chatId = tostring(cpost.getJSONObject("chat").getLong("id"))
                                    if chatId == "-1004358835923" then
                                        if cpost.has("text") then
                                            local infoText = cpost.getString("text")
                                            table.insert(info_history.messages, {text = infoText, timestamp = msgDate})
                                            has_new_info = true
                                            
                                            if notif_info then
                                                local announceText = ""
                                                if notif_summary then
                                                    announceText = "Informasi baru diterima"
                                                else
                                                    announceText = "Informasi baru: " .. infoText
                                                end
                                                triggerAccessibilityAnnouncement(announceText)
                                            end
                                        elseif cpost.has("voice") then
                                            local voice = cpost.getJSONObject("voice")
                                            local file_id = voice.getString("file_id")
                                            local duration = 0
                                            if voice.has("duration") then duration = voice.getInt("duration") end
                                            
                                            local m = math.floor(duration / 60)
                                            local s = duration % 60
                                            local durStr = string.format("%02d:%02d", m, s)
                                            
                                            local saved_path = dl_map[file_id]
                                            if saved_path then
                                                local infoText = "Informasi Suara (" .. durStr .. ")"
                                                table.insert(info_history.messages, {text = infoText, audio_path = saved_path, timestamp = msgDate})
                                                has_new_info = true
                                                
                                                if notif_info then
                                                    local announceText = ""
                                                    if notif_summary then
                                                        announceText = "Informasi suara baru diterima"
                                                    else
                                                        announceText = "Informasi suara baru diterima dengan durasi " .. durStr
                                                    end
                                                    triggerAccessibilityAnnouncement(announceText)
                                                end
                                            end
                                        elseif cpost.has("audio") then
                                            local f_id = cpost.getJSONObject("audio").getString("file_id")
                                            local saved_path = dl_map[f_id]
                                            if saved_path then
                                                local title = "Informasi Audio"
                                                if cpost.getJSONObject("audio").has("title") then
                                                    title = "Informasi Audio: " .. cpost.getJSONObject("audio").getString("title")
                                                end
                                                table.insert(info_history.messages, {text = title, audio_path = saved_path, timestamp = msgDate})
                                                has_new_info = true
                                                
                                                if notif_info then
                                                    local announceText = notif_summary and "Informasi audio baru diterima" or "Informasi audio baru diterima"
                                                    triggerAccessibilityAnnouncement(announceText)
                                                end
                                            end
                                        elseif cpost.has("video") then
                                            local f_id = cpost.getJSONObject("video").getString("file_id")
                                            local saved_path = dl_map[f_id]
                                            if saved_path then
                                                table.insert(info_history.messages, {text = "Informasi Video", media_path = saved_path, media_type = 3, timestamp = msgDate})
                                                has_new_info = true
                                                if notif_info then
                                                    local announceText = notif_summary and "Informasi video baru diterima" or "Informasi video baru diterima"
                                                    triggerAccessibilityAnnouncement(announceText)
                                                end
                                            end
                                        elseif cpost.has("photo") then
                                            local photoArr = cpost.getJSONArray("photo")
                                            local f_id = photoArr.getJSONObject(photoArr.length() - 1).getString("file_id")
                                            local saved_path = dl_map[f_id]
                                            if saved_path then
                                                table.insert(info_history.messages, {text = "Informasi Foto", media_path = saved_path, media_type = 1, timestamp = msgDate})
                                                has_new_info = true
                                                if notif_info then
                                                    local announceText = notif_summary and "Informasi foto baru diterima" or "Informasi foto baru diterima"
                                                    triggerAccessibilityAnnouncement(announceText)
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        
                        if current_chat_id == "admin" then
                            if has_new then saveHistory() end
                        else
                            local f = io.open(file_path_admin, "r")
                            local root = JSONObject()
                            if f then
                                local content = f:read("*a")
                                f:close()
                                local s, parsed = pcall(function() return JSONObject(content) end)
                                if s then root = parsed end
                            end
                            root.put("last_update_id", admin_last_update_id)
                            if not root.has("messages") then root.put("messages", JSONArray()) end
                            local fw = io.open(file_path_admin, "w")
                            if fw then
                                fw:write(root.toString())
                                fw:close()
                            end
                        end
                        
                        if has_new then
                            if notif_vibrate_msg then
                                pcall(function()
                                    local vibrator = ctx.getSystemService(Context.VIBRATOR_SERVICE)
                                    if vibrator and vibrator.hasVibrator() then vibrator.vibrate(300) end
                                end)
                            end
                        end
                        
                        if has_new_info then
                            saveInfoHistory()
                            if notif_vibrate_info then
                                pcall(function()
                                    local vibrator = ctx.getSystemService(Context.VIBRATOR_SERVICE)
                                    if vibrator and vibrator.hasVibrator() then vibrator.vibrate(300) end
                                end)
                            end
                        end
                    end
                end
            else
                setConnectionState(false)
            end
            
            if not is_languages_loaded then
                fetchLanguages()
            end
            
            if sync_background or dialog.isShowing() then
                handler.postDelayed(pollRunnable, 3000)
            end
        end)
    end
}

local function startMainApp()
    initUserData()
    loadTransConfig()
    loadInfoHistory()
    
    loadHistory()
    if refreshHomeChatList then refreshHomeChatList() end
    dialog.show()
    
    handler.postDelayed(pollRunnable, 1000)
    
    task(function(t_token)
        require "import"
        import "java.net.URL"
        import "java.io.DataOutputStream"
        import "java.net.URLEncoder"
        import "java.io.BufferedReader"
        import "java.io.InputStreamReader"
        
        local code = -1
        local resBody = ""
        pcall(function()
            local urlStr = "http://botspark.de1.octavia.id:25701/api/verifyToken"
            local data = "token=" .. URLEncoder.encode(t_token, "UTF-8")
            local url = URL(urlStr)
            local conn = url.openConnection()
            conn.setConnectTimeout(10000)
            conn.setReadTimeout(10000)
            conn.setRequestMethod("POST")
            conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            conn.setDoOutput(true)
            
            local out = DataOutputStream(conn.getOutputStream())
            out.writeBytes(data)
            out.flush()
            out.close()
            
            code = conn.getResponseCode()
            local isStream = (code >= 200 and code < 300) and conn.getInputStream() or conn.getErrorStream()
            if isStream then
                local br = BufferedReader(InputStreamReader(isStream))
                local line = br.readLine()
                while line ~= nil do
                    resBody = resBody .. line
                    line = br.readLine()
                end
                br.close()
            end
        end)
        return code, resBody
    end, auth_token, function(code, body)
        if code >= 400 and code < 500 then
            if auth_refresh_token and auth_refresh_token ~= "" then
                task(function(t_rtoken)
                    require "import"
                    import "java.net.URL"
                    import "java.io.DataOutputStream"
                    import "java.net.URLEncoder"
                    import "java.io.BufferedReader"
                    import "java.io.InputStreamReader"
                    import "org.json.JSONObject"
                    local rcode = -1
                    local rbody = ""
                    pcall(function()
                        local urlStr = "http://botspark.de1.octavia.id:25701/api/refreshToken"
                        local data = "refreshToken=" .. URLEncoder.encode(t_rtoken, "UTF-8")
                        local url = URL(urlStr)
                        local conn = url.openConnection()
                        conn.setConnectTimeout(10000)
                        conn.setReadTimeout(10000)
                        conn.setRequestMethod("POST")
                        conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                        conn.setDoOutput(true)
                        local out = DataOutputStream(conn.getOutputStream())
                        out.writeBytes(data)
                        out.flush()
                        out.close()
                        rcode = conn.getResponseCode()
                        local isStream = (rcode >= 200 and rcode < 300) and conn.getInputStream() or conn.getErrorStream()
                        if isStream then
                            local br = BufferedReader(InputStreamReader(isStream))
                            local line = br.readLine()
                            while line ~= nil do
                                rbody = rbody .. line
                                line = br.readLine()
                            end
                            br.close()
                        end
                    end)
                    return rcode, rbody
                end, auth_refresh_token, function(rcode, rbody)
                    local s, data = pcall(function() return JSONObject(rbody) end)
                    if rcode == 200 and s and data.has("idToken") then
                        auth_token = data.getString("idToken")
                        if data.has("refreshToken") then
                            auth_refresh_token = data.getString("refreshToken")
                        end
                        saveAuthConfig()
                    else
                        auth_token = ""
                        auth_refresh_token = ""
                        user_email = ""
                        saveAuthConfig()
                        if dialog and dialog.isShowing() then
                            dialog.dismiss()
                        end
                        showAuthDialog()
                    end
                end)
            else
                auth_token = ""
                auth_refresh_token = ""
                user_email = ""
                saveAuthConfig()
                if dialog and dialog.isShowing() then
                    dialog.dismiss()
                end
                showAuthDialog()
            end
        end
    end)
end

function showAuthDialog()
    local authLayout = {
        FrameLayout,
        layout_width = "fill",
        layout_height = "fill",
        backgroundColor = "#F5F5F5",
        {
            ImageView,
            id = "btnCloseAuth",
            layout_width = "48dp",
            layout_height = "48dp",
            layout_gravity = "top|right",
            layout_margin = "16dp",
            padding = "8dp",
            contentDescription = "Keluar"
        },
        {
            LinearLayout,
            orientation = "vertical",
            layout_width = "fill",
            layout_height = "wrap",
            layout_gravity = "center",
            padding = "32dp",
            gravity = "center",
            {
                TextView,
                id = "tvAuthTitle",
                text = "Texa",
                textSize = "42sp",
                textColor = "#075E54",
                layout_marginBottom = "8dp"
            },
            {
                TextView,
                text = "Masuk atau Daftar untuk melanjutkan",
                textSize = "16sp",
                textColor = "#555555",
                layout_marginBottom = "32dp",
                gravity = "center"
            },
            {
                LinearLayout,
                orientation = "vertical",
                layout_width = "fill",
                layout_height = "wrap",
                backgroundColor = "#FFFFFF",
                padding = "24dp",
                {
                    EditText,
                    id = "etEmail",
                    layout_width = "fill",
                    layout_height = "wrap",
                    hint = "Alamat Email",
                    textSize = "16sp",
                    singleLine = true,
                    inputType = 33,
                    padding = "16dp",
                    backgroundColor = "#F0F0F0",
                    layout_marginBottom = "16dp"
                },
                {
                    LinearLayout,
                    orientation = "horizontal",
                    layout_width = "fill",
                    layout_height = "wrap",
                    layout_marginBottom = "24dp",
                    gravity = "center_vertical",
                    {
                        EditText,
                        id = "etPassword",
                        layout_width = "0dp",
                        layout_weight = "1",
                        layout_height = "wrap",
                        hint = "Kata Sandi",
                        textSize = "16sp",
                        singleLine = true,
                        inputType = 129,
                        padding = "16dp",
                        backgroundColor = "#F0F0F0"
                    },
                    {
                        ImageView,
                        id = "btnTogglePassword",
                        layout_width = "48dp",
                        layout_height = "48dp",
                        padding = "8dp",
                        layout_marginLeft = "4dp"
                    }
                },
                {
                    TextView,
                    id = "tvAuthStatus",
                    text = "",
                    textColor = "#FF0000",
                    textSize = "14sp",
                    gravity = "center",
                    layout_marginBottom = "16dp",
                    visibility = 8
                },
                {
                    TextView,
                    id = "btnResendVerification",
                    text = "Kirim Ulang Email Verifikasi",
                    textColor = "#00897B",
                    textSize = "14sp",
                    gravity = "center",
                    layout_marginBottom = "16dp",
                    clickable = true,
                    focusable = true,
                    visibility = 8
                },
                {
                    TextView,
                    id = "btnForgotPassword",
                    text = "Lupa Kata Sandi?",
                    textColor = "#00897B",
                    textSize = "14sp",
                    gravity = "center",
                    layout_marginBottom = "24dp",
                    clickable = true,
                    focusable = true
                },
                {
                    LinearLayout,
                    orientation = "horizontal",
                    layout_width = "fill",
                    layout_height = "wrap",
                    {
                        TextView,
                        id = "btnRegister",
                        text = "Daftar",
                        layout_width = "0dp",
                        layout_weight = "1",
                        layout_marginRight = "8dp",
                        textColor = "#075E54",
                        backgroundColor = "#E0F2F1",
                        padding = "12dp",
                        gravity = "center",
                        clickable = true,
                        focusable = true
                    },
                    {
                        TextView,
                        id = "btnLogin",
                        text = "Masuk",
                        layout_width = "0dp",
                        layout_weight = "1",
                        layout_marginLeft = "8dp",
                        textColor = "#FFFFFF",
                        backgroundColor = "#075E54",
                        padding = "12dp",
                        gravity = "center",
                        clickable = true,
                        focusable = true
                    }
                }
            }
        }
    }

    local aViews = {}
    local aContentView = loadlayout(authLayout, aViews)
    
    aViews.tvAuthTitle.setTypeface(Typeface.DEFAULT_BOLD)
    aViews.etEmail.setContentDescription("Kolom masukan Alamat Email")
    aViews.etPassword.setContentDescription("Kolom masukan Kata Sandi")
    
    aViews.btnCloseAuth.setImageBitmap(createEmojiBitmap("X", 100, 70, 30, 75))
    
    local bmpShowPass = createEmojiBitmap("👁️", 100, 60, 20, 75)
    local bmpHidePass = createEmojiBitmap("🙈", 100, 60, 20, 75)
    
    aViews.btnTogglePassword.setImageBitmap(bmpShowPass)
    aViews.btnTogglePassword.setContentDescription("Tampilkan kata sandi")

    local authDialog = Dialog(ctx)
    authDialog.requestWindowFeature(1)
    authDialog.setContentView(aContentView)
    
    local w = authDialog.getWindow()
    if Build.VERSION.SDK_INT >= 22 then
        w.setType(2032)
    else
        w.setType(2003)
    end
    w.setBackgroundDrawable(ColorDrawable(0xffF5F5F5))
    w.setLayout(-1, -1)
    w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    
    aViews.btnCloseAuth.onClick = function()
        authDialog.dismiss()
    end
    
    local isPasswordVisible = false
    aViews.btnTogglePassword.onClick = function()
        isPasswordVisible = not isPasswordVisible
        if isPasswordVisible then
            aViews.btnTogglePassword.setImageBitmap(bmpHidePass)
            aViews.etPassword.setInputType(145)
            aViews.btnTogglePassword.setContentDescription("Sembunyikan kata sandi")
        else
            aViews.btnTogglePassword.setImageBitmap(bmpShowPass)
            aViews.etPassword.setInputType(129)
            aViews.btnTogglePassword.setContentDescription("Tampilkan kata sandi")
        end
        aViews.etPassword.setSelection(aViews.etPassword.getText().length())
    end
    
    local function performAuth(endpoint, email, password)
        aViews.tvAuthStatus.setVisibility(0)
        aViews.tvAuthStatus.setText("Mohon tunggu...")
        aViews.tvAuthStatus.setTextColor(0xFF00897B)
        aViews.btnResendVerification.setVisibility(8)
        aViews.btnLogin.setEnabled(false)
        aViews.btnRegister.setEnabled(false)
        
        task(function(t_end, t_email, t_pass)
            require "import"
            import "java.net.URL"
            import "java.io.DataOutputStream"
            import "java.net.URLEncoder"
            import "java.io.BufferedReader"
            import "java.io.InputStreamReader"
            import "org.json.JSONObject"
            
            local code = -1
            local resBody = ""
            pcall(function()
                local urlStr = "http://botspark.de1.octavia.id:25701/api/" .. t_end
                local data = "email=" .. URLEncoder.encode(t_email, "UTF-8") .. "&password=" .. URLEncoder.encode(t_pass, "UTF-8")
                local url = URL(urlStr)
                local conn = url.openConnection()
                conn.setConnectTimeout(15000)
                conn.setReadTimeout(15000)
                conn.setRequestMethod("POST")
                conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                conn.setDoOutput(true)
                
                local out = DataOutputStream(conn.getOutputStream())
                out.writeBytes(data)
                out.flush()
                out.close()
                
                code = conn.getResponseCode()
                local isStream = (code >= 200 and code < 300) and conn.getInputStream() or conn.getErrorStream()
                if isStream then
                    local br = BufferedReader(InputStreamReader(isStream))
                    local line = br.readLine()
                    while line ~= nil do
                        resBody = resBody .. line
                        line = br.readLine()
                    end
                    br.close()
                end
            end)
            return code, resBody
        end, endpoint, email, password, function(code, body)
            aViews.btnLogin.setEnabled(true)
            aViews.btnRegister.setEnabled(true)
            if code == 200 and body ~= "" then
                local s, data = pcall(function() return JSONObject(body) end)
                local serverMessage = "Berhasil"
                if s and data.has("message") then
                    serverMessage = data.getString("message")
                end
                
                if endpoint == "resendVerification" then
                    aViews.tvAuthStatus.setText(serverMessage)
                    aViews.tvAuthStatus.setTextColor(0xFF00897B)
                    triggerAccessibilityAnnouncement(serverMessage)
                elseif endpoint == "register" then
                    aViews.tvAuthStatus.setText(serverMessage)
                    aViews.tvAuthStatus.setTextColor(0xFF00897B)
                    aViews.etPassword.setText("")
                    triggerAccessibilityAnnouncement(serverMessage)
                elseif endpoint == "login" then
                    if s and data.has("idToken") then
                        auth_token = data.getString("idToken")
                        user_email = data.getString("email")
                        if data.has("refreshToken") then
                            auth_refresh_token = data.getString("refreshToken")
                        end
                        saveAuthConfig()
                        
                        aViews.tvAuthStatus.setText(serverMessage)
                        aViews.tvAuthStatus.setTextColor(0xFF00897B)
                        triggerAccessibilityAnnouncement(serverMessage)
                        
                        handler.postDelayed(Runnable{
                            run = function()
                                authDialog.dismiss()
                                startMainApp()
                            end
                        }, 500)
                    else
                        aViews.tvAuthStatus.setText("Respon tidak valid dari server")
                        aViews.tvAuthStatus.setTextColor(0xFFFF0000)
                    end
                end
            else
                local errMsg = "Terjadi kesalahan jaringan"
                local errCode = nil
                local s, data = pcall(function() return JSONObject(body) end)
                if s then
                    if data.has("error") then errMsg = data.getString("error") end
                    if data.has("code") then errCode = data.getString("code") end
                end
                
                aViews.tvAuthStatus.setText(errMsg)
                aViews.tvAuthStatus.setTextColor(0xFFFF0000)
                triggerAccessibilityAnnouncement(errMsg)
                
                if errCode == "EMAIL_NOT_VERIFIED" or string.find(errMsg, "belum diverifikasi") then
                    aViews.btnResendVerification.setVisibility(0)
                end
            end
        end)
    end
    
    aViews.btnLogin.onClick = function()
        local email = tostring(aViews.etEmail.getText())
        local password = tostring(aViews.etPassword.getText())
        
        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
        imm.hideSoftInputFromWindow(aViews.etEmail.getWindowToken(), 0)
        
        performAuth("login", email, password)
    end
    
    aViews.btnRegister.onClick = function()
        local email = tostring(aViews.etEmail.getText())
        local password = tostring(aViews.etPassword.getText())
        
        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
        imm.hideSoftInputFromWindow(aViews.etEmail.getWindowToken(), 0)
        
        performAuth("register", email, password)
    end

    aViews.btnResendVerification.onClick = function()
        local email = tostring(aViews.etEmail.getText())
        local password = tostring(aViews.etPassword.getText())
        
        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
        imm.hideSoftInputFromWindow(aViews.etEmail.getWindowToken(), 0)
        
        performAuth("resendVerification", email, password)
    end

    aViews.btnForgotPassword.onClick = function()
        local email = tostring(aViews.etEmail.getText())
        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
        imm.hideSoftInputFromWindow(aViews.etEmail.getWindowToken(), 0)
        
        if email == "" then
            aViews.tvAuthStatus.setVisibility(0)
            aViews.tvAuthStatus.setText("Silakan masukkan email Anda terlebih dahulu untuk mengatur ulang kata sandi.")
            aViews.tvAuthStatus.setTextColor(0xFFFF0000)
            triggerAccessibilityAnnouncement("Silakan masukkan email Anda terlebih dahulu untuk mengatur ulang kata sandi.")
            return
        end
        
        aViews.tvAuthStatus.setVisibility(0)
        aViews.tvAuthStatus.setText("Memproses...")
        aViews.tvAuthStatus.setTextColor(0xFF00897B)
        
        task(function(t_email)
            require "import"
            import "java.net.URL"
            import "java.io.DataOutputStream"
            import "java.net.URLEncoder"
            import "java.io.BufferedReader"
            import "java.io.InputStreamReader"
            import "org.json.JSONObject"
            
            local code = -1
            local resBody = ""
            pcall(function()
                local urlStr = "http://botspark.de1.octavia.id:25701/api/resetPassword"
                local data = "email=" .. URLEncoder.encode(t_email, "UTF-8")
                local url = URL(urlStr)
                local conn = url.openConnection()
                conn.setConnectTimeout(15000)
                conn.setReadTimeout(15000)
                conn.setRequestMethod("POST")
                conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                conn.setDoOutput(true)
                
                local out = DataOutputStream(conn.getOutputStream())
                out.writeBytes(data)
                out.flush()
                out.close()
                
                code = conn.getResponseCode()
                local isStream = (code >= 200 and code < 300) and conn.getInputStream() or conn.getErrorStream()
                if isStream then
                    local br = BufferedReader(InputStreamReader(isStream))
                    local line = br.readLine()
                    while line ~= nil do
                        resBody = resBody .. line
                        line = br.readLine()
                    end
                    br.close()
                end
            end)
            return code, resBody
        end, email, function(code, body)
            local s, data = pcall(function() return JSONObject(body) end)
            if code == 200 then
                local successMsg = "Berhasil"
                if s and data.has("message") then successMsg = data.getString("message") end
                aViews.tvAuthStatus.setText(successMsg)
                aViews.tvAuthStatus.setTextColor(0xFF00897B)
                triggerAccessibilityAnnouncement(successMsg)
            else
                local errMsg = "Gagal mengirim permintaan"
                if s and data.has("error") then errMsg = data.getString("error") end
                aViews.tvAuthStatus.setText(errMsg)
                aViews.tvAuthStatus.setTextColor(0xFFFF0000)
                triggerAccessibilityAnnouncement(errMsg)
            end
        end)
    end

    authDialog.show()
end

checkForUpdates(false)

if auth_token and auth_token ~= "" then
    startMainApp()
else
    showAuthDialog()
end