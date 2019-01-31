local sockets = {}

do
    local ljsocket = require("ljsocket")

    sockets.active = {}

    event.AddListener("Update", "sockets2", function()
        for _, socket in ipairs(sockets.active) do
            socket:Update()
        end
    end)

    do
        local META = prototype.CreateTemplate("socket2", "tcp")

        function META:assert(val, err)
            if not val then
                self:Error(err)
            end

            return val, err
        end

        function META:__tostring2()
            return "[" .. tostring(self.socket) .. "]"
        end

        function META:Initialize()
            self:SocketRestart()
            table.insert(sockets.active, self)
        end

        function META:SocketRestart()
            self.socket = ljsocket.create("inet", "stream", "tcp")
            self.socket:set_blocking(false)

            self.tls_setup = nil
            self.connected = nil
            self.connecting = nil
        end

        function META:SetupTLS()
            if self.tls_setup then return end

            self.tls_setup = true

            local SSL = require("libressl")
            local ffi = require("ffi")
            SSL.tls_init()

            local tls = SSL.tls_client()

            local config = SSL.tls_config_new()
            SSL.tls_config_insecure_noverifycert(config)
            SSL.tls_config_insecure_noverifyname(config)
            SSL.tls_configure(tls, config)

            local function last_error(code, what)
                local err = SSL.tls_error(tls)
                if err ~= nil then
                    return ffi.string(err)
                end
                return "unknown tls "..what.." error (" .. tonumber(code) .. ")"
            end

            function self.socket:on_connect(host, serivce)
                local code = SSL.tls_connect_socket(tls, self.fd, host)

                if code < 0 then
                    return nil, last_error(code, "connect")
                end

                return true
            end

            function self:DoHandshake()
                local ret = SSL.tls_handshake(tls)

                if ret == SSL.e.TLS_WANT_POLLOUT or ret == SSL.e.TLS_WANT_POLLIN then
                    return nil, "timeout"
                elseif ret < 0 then
                    return nil, last_error(ret, "handshake")
                end

                self.DoHandshake = nil

                return true
            end

            function self.socket:on_send(data, flags)
                local len = SSL.tls_write(tls, data, #data)
                if len < 0 then
                    if len == SSL.e.TLS_WANT_POLLOUT or len == SSL.e.TLS_WANT_POLLIN then
                        return nil, "timeout"
                    end
                    return nil, last_error(len, "write")
                end
                return len
            end

            function self.socket:on_receive(buffer, max_size, flags)
                local len = SSL.tls_read(tls, buffer, max_size)
                if len < 0 then
                    if len == SSL.e.TLS_WANT_POLLOUT or len == SSL.e.TLS_WANT_POLLIN then
                        return nil, "timeout"
                    end
                    return nil, last_error(len, "receive")
                end

                if len == 0 then
                    return nil, "closed"
                end

                return ffi.string(buffer, len)
            end

            function self.socket:on_close()
                SSL.tls_close(tls)
            end
        end

        function META:OnRemove()
            table.removevalue(sockets.active, self)
            self:assert(self.socket:close())
        end

        function META:Close(reason)
            if reason then print(reason) end
            self:Remove()
        end

        function META:Connect(host, service)
            if service == "https" then
                self:SetupTLS()
            end

            if self:assert(self.socket:connect(host, service)) then
                self.connecting = true
            end
        end

        function META:Send(data)
            local ok, err = self.socket:send(data)

            if not ok then
                if err == "timeout" then
                    self.buffered_send = self.buffered_send or {}
                    table.insert(self.buffered_send, data)
                    return true
                end

                self:Error(err)
            end

            return ok, err
        end

        function META:Update()
            if self.connecting then
                if self.socket:is_connected() then
                    if self.DoHandshake then
                        local ok, err = self:DoHandshake()

                        if not ok then
                            if err == "timeout" then
                                return
                            end

                            if err == "closed" then
                                self:OnClose()
                            else
                                self:Error(err)
                            end
                        end

                        self.DoHandshake = nil
                    end

                    self:OnConnect()
                    self.connected = true
                    self.connecting = false
                end
            elseif self.connected then

                if self.buffered_send then
                    while true do
                        local data = self.buffered_send[1]

                        if not data then break end

                        local ok, err = self.socket:send(data)

                        if ok then
                            table.remove(self.buffered_send)
                        elseif err ~= "timeout" then
                            self:Error("error while processing buffered queue: " .. err)
                        end
                    end
                end

                local chunk, err = self.socket:receive()

                if chunk then
                    self:OnReceiveChunk(chunk)
                elseif err == "closed" then
                    self:OnClose()
                elseif err ~= "timeout" then
                    self:Error(err)
                end
            end
        end

        function META:Error(message)
            self:OnError(message)
            return false
        end

        function META:OnError(str) debug.trace() print("ERROR: ", self, str) self:Remove() end
        function META:OnReceiveChunk(str) end
        function META:OnClose() print("socket closed", self) self:Close() end
        function META:OnConnect() end

        function sockets.TCPClient()
            local self = META:CreateObject()
            self:Initialize()
            return self
        end

        META:Register()
    end
end

local function default_header(header, key, val)
    if header[key] == nil then
        header[key] = val
    elseif header[key] == false then
        header[key] = nil
    end
end

do
    local META = prototype.CreateTemplate("socket2", "http/1.1")

    META.Base = "tcp"
    META.Stage = "none"
    META.MimeToExtension = {
        ["audio/aac"] = "aac",
        ["application/x-abiword"] = "abw",
        ["application/x-freearc"] = "arc",
        ["video/x-msvideo"] = "avi",
        ["application/vnd.amazon.ebook"] = "azw",
        ["application/octet-stream"] = "bin",
        ["image/bmp"] = "bmp",
        ["application/x-bzip"] = "bz",
        ["application/x-bzip2"] = "bz2",
        ["application/x-csh"] = "csh",
        ["text/css"] = "css",
        ["text/csv"] = "csv",
        ["application/msword"] = "doc",
        ["application/vnd.openxmlformats-officedocument.wordprocessingml.document"] = "docx",
        ["application/vnd.ms-fontobject"] = "eot",
        ["application/epub+zip"] = "epub",
        ["image/gif"] = "gif",
        ["text/html"] = "html",
        ["image/vnd.microsoft.icon"] = "ico",
        ["text/calendar"] = "ics",
        ["application/java-archive"] = "jar",
        ["image/jpeg"] = "jpg",
        ["text/javascript"] = "js",
        ["application/json"] = "json",
        ["audio/midi audio/x-midi"] = "mid",
        ["application/javascript"] = "mjs",
        ["audio/mpeg"] = "mp3",
        ["video/mpeg"] = "mpeg",
        ["application/vnd.apple.installer+xml"] = "mpkg",
        ["application/vnd.oasis.opendocument.presentation"] = "odp",
        ["application/vnd.oasis.opendocument.spreadsheet"] = "ods",
        ["application/vnd.oasis.opendocument.text"] = "odt",
        ["audio/ogg"] = "oga",
        ["video/ogg"] = "ogv",
        ["application/ogg"] = "ogx",
        ["font/otf"] = "otf",
        ["image/png"] = "png",
        ["application/pdf"] = "pdf",
        ["application/vnd.ms-powerpoint"] = "ppt",
        ["application/vnd.openxmlformats-officedocument.presentationml.presentation"] = "pptx",
        ["application/x-rar-compressed"] = "rar",
        ["application/rtf"] = "rtf",
        ["application/x-sh"] = "sh",
        ["image/svg+xml"] = "svg",
        ["application/x-shockwave-flash"] = "swf",
        ["application/x-tar"] = "tar",
        ["image/tiff"] = "tif",
        ["font/ttf"] = "ttf",
        ["text/plain"] = "txt",
        ["application/vnd.visio"] = "vsd",
        ["audio/wav"] = "wav",
        ["audio/webm"] = "weba",
        ["video/webm"] = "webm",
        ["image/webp"] = "webp",
        ["font/woff"] = "woff",
        ["font/woff2"] = "woff2",
        ["application/xhtml+xml"] = "xhtml",
        ["application/vnd.ms-excel"] = "xls",
        ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"] = "xlsx",
        ["application/xml if not readable from casual users (RFC 3023, section 3)"] = "xml",
        ["application/zip"] = "zip",
        ["video/3gpp"] = "3gp",
        ["video/3gpp2"] = "3g2",
        ["application/x-7z-compressed"] = "7z",
        ["application/vnd.microsoft.portable-executable"] = "exe",
    }

    -- maybe this should be a helper?
    function META:ParseURI(uri)
        local scheme
        local path
        local authority
        local host
        local port

        scheme, path = uri:match("^(%l[%l%d+.-]+):(.+)")

        if not scheme then
            return nil, "unable to parse URI: " .. uri
        end

        if path:startswith("//") then
            path = path:sub(3)

            host, rest = path:match("^(.-)/(.*)$")
            path = rest

            if host:find("@", 1, true) then
                local temp = host:split("@")
                authority = temp[1]
                host = temp[2]
            end

            local temp = host:split(":")
            host = temp[1]

            port = temp[2]
        end

        return {
            scheme = scheme,
            path = path,
            authority = authority,
            host = host,
            port = port,
        }
    end

    function META:Request(method, url, header, body)
        header = header or {}

        local uri = assert(self:ParseURI(url))

        assert(self.socket:set_option("nodelay", true, "tcp"))
        assert(self.socket:set_option("quickack", true, "tcp"))
        self:Connect(uri.host, uri.scheme)

        do
            local host = uri.host
            if uri.port then
                host = host .. ":" .. uri.port
            end

            header = header or {}
            default_header(header, "User-Agent", "goluwa/" .. jit.os)
            default_header(header, "Accept", "*/*")
            default_header(header, "Accept-Encoding", "identity")
            default_header(header, "Host", host)
            default_header(header, "Connection", "keep-alive")
            default_header(header, "DNT", "1")

            if body then
                default_header(header, "Content-Length", #body)
                default_header(header, "Content-Type", "application/octet-stream")
            end

            local str = ""

            for k, v in pairs(header) do
                str = str .. k .. ": " .. v .. "\r\n"
            end

            str = str .. "\r\n"

            if body then
                str = str .. body
            end

            self:Send(method .. " /"..uri.path.." HTTP/1.1\r\n" .. str)
        end

        self.RequestMethod = method
        self.RequestHeader = header
        self.RequestBody = body
        self.RequestURI = uri

        self.Stage = "connecting"
    end

    function META:OnConnect()
        self.Stage = "header"
        self.RawHeader = ""
        self.RawBody = ""
    end

    function META:DecodeChunkedBody(body)
        local temp = {}
        local pos = 1

        for i = 1, math.huge do
            if body:sub(pos, pos + #"0\r\n\r\n"):endswith("0\r\n\r\n") then
                break
            end

            -- find nearest \r\n
            local size_stop, chunk_start = body:find("\r\n", pos, true)
            local size = tonumber(body:sub(pos, size_stop), 16)

            pos = size_stop + 2

            temp[i] = body:sub(pos, pos + size - 1)

            pos = pos + size

            local eoc = body:sub(pos, pos + 1)

            if eoc ~= "\r\n" then
                return self:Error("chunk #" .. i .. " reports a size of " .. size .. " bytes but is not terminated with \\r\\n")
            end

            pos = pos + 2
        end

        return table.concat(temp)
    end

    function META:OnReceiveChunk(chunk)
        if self.Stage == "header" then
            if #self.RawHeader > 4 and not self.RawHeader:startswith("HTTP") then
                return self:Error("header does not start with HTTP (" .. self.RawHeader:sub(10) .. ")")
            end

            self.RawHeader = self.RawHeader .. chunk

            local start, stop = self.RawHeader:find("\r\n\r\n", 1, true)

            if start then
                local header = self.RawHeader:sub(1, stop)
                chunk = self.RawHeader:sub(stop+1) -- resume body here

                if not header:startswith("HTTP") then
                    return self:Error("header does not start with HTTP")
                end

                self.RawHeader = header

                do
                    local keyvalues = {}

                    for i, line in ipairs(header:split("\r\n")) do
                        if i == 1 then
                            local version, code, status = line:match("^(HTTP/%d+%.%d+) (%d+) (.+)$")

                            if not code:startswith("2") and not code:startswith("3") then
                                return self:Error(code .. " " .. status)
                            end

                            self.Version = version
                            self.Code = code
                            self.Status = status

                            if self:OnReceiveStatusLine(version, code, status) == false then
                                return
                            end
                        else
                            local keyval = line:split(": ")
                            local key, val = keyval[1], keyval[2]

                            keyvalues[key:lower()] = val
                        end
                    end

                    self.Header = keyvalues

                    -- normalize some values
                    do
                        local content_length = tonumber(keyvalues["content-length"])
                        if content_length == 0 then
                            content_length = nil
                        end

                        self.Header["content-length"] = content_length
                    end

                    self.Header["connection"] = self.Header["connection"] and self.Header["connection"]:lower() or nil
                    self.Header["content-encoding"] = self.Header["content-encoding"] or "identity"
                end

                if self.Code:startswith("3") and self.Header["location"] then

                    if self:OnReceiveRedirectHeader(self.Header) == false then
                        return
                    end

                    self:assert(self.socket:close())
                    self:SocketRestart()

                    local location = self.Header["location"]

                    if location:startswith("/") then
                        location = self.RequestURI.scheme .. "://" .. (self.RequestHeader.Host or self.RequestURI.host) .. location
                    else
                        self.RequestHeader.Host = nil
                    end

                    self:Request(self.RequestMethod, location, self.RequestHeader, self.RequestBody)
                    return
                end

                self.Stage = "body"

                if self:OnReceiveHeader(self.Header) == false then
                    return
                end

                if self.Header["connection"] == "close" then
                    return self:Close()
                end
           end
        end

        if self.Stage == "body" then
            if self:OnReceiveBodyChunk(chunk) == false then
                return
            end

            if self.HandleBodyReceive ~= false then
                self:WriteBody(chunk)

                local body = nil

                if self.Header["content-length"] and self:GetWrittenBodySize() >= self.Header["content-length"] then
                    body = self:GetWrittenBodyString()
                elseif self:GetWrittenBodyString():endswith("0\r\n\r\n") then
                    body = self:DecodeChunkedBody(self:GetWrittenBodyString())
                end

                if body then
                    local encoding = self.Header["content-encoding"]
                    if encoding ~= "identity" then
                        if encoding == "gzip" then
                            local ok, str = pcall(serializer.Decode, "gunzip", body)

                            if not ok then
                                return self:OnError("failed to parse " .. encoding .. " body: " .. str)
                            end

                            body = str
                        else
                            print("unknown content-encoding: " .. encoding)
                        end
                    end

                    self.Body = body

                    self:OnReceiveBody(body)

                    self:Close()
                end
            end
        end
    end

    function META:WriteBody(data)
        self.RawBody = self.RawBody .. data
    end

    function META:GetWrittenBodySize()
        return #self.RawBody
    end

    function META:GetWrittenBodyString()
        return self.RawBody
    end

    function META:OnReceiveBody()

    end

    function META:OnReceiveHeader()

    end

    function META:OnReceiveRedirectHeader()

    end

    function META:OnReceiveBodyChunk()

    end

    function META:OnReceiveStatusLine()

    end

    META:Register()

    function sockets.HTTPClient()
        local self = META:CreateObject()
        self:Initialize()
        return self
    end

    local function decode_data_uri(uri)
        local mime, encoding, data = uri:match("data:(.-);(.-),(.+)")
        if encoding == "" then
            encoding = "base64"
        end

        if encoding == "base64" then
            vfs.Write("test." .. META.MimeToExtension[mime], crypto.Base64Decode(data))
        else
            error("unknown encoding " .. encoding)
        end

        return
    end

    do
        local META = prototype.CreateTemplate("socket2", "downloader")

        META.Base = "http/1.1"

        local function posixtime2http(posix_time)
            return require("date")(posix_time):fmt("${http}")
        end

        local function http2posixtime(http_time)
            return (require("date")(http_time) - require("date").epoch()):spanseconds()
        end

        local time = vfs.GetLastModified("/home/caps/goluwa2/core/lua/modules/date.lua")
        local http_time = posixtime2http(time)

        print(http_time)

        do return end


        function META:Fetch(url, info, header)
            header = header or {}
            if info then
                if info.last_modified then
                    header["If-Modified-Since"] =
                end
                if info.etag then
                    header["etag"] = info.etag
                end
            end

            self:Request("GET", url, header)
        end

        function META:OnReceiveHeader(header)
            local hash = header["etag"]
            print(hash)
        end

        function sockets.Downloader()
            local self = META:CreateObject()
            self:Initialize()
            return self
        end

        META:Register()
    end




    local urls = {
        "https://puu.sh/qJZWP/febd7450cd.wav",
        "https://puu.sh/rMEGk/7b30e5c5a5.txt",
        "http://pastebin.com/raw/xmHZ2eb3",
        "https://dl.dropbox.com/s/9yac9ud6xu25i6b/DABDABDAB.txt?dl=0",
        "https://dl.dropboxusercontent.com/s/yex5xw5bvnvr7o8/Look%20at%20my%20dab.ogg",
        "http://puu.sh/pLvKh.obj",
        "http://www.fresher.ru/manager_content/images/10-faktov-o-flagax/10.jpg",
        "http://www.derpygamers.com/PAC_Content_Gmod/models/bodyfluff.obj",
        "https://www.dropbox.com/s/nczdyt33jcfky8f/talk%20(7).ogg?dl=1",
    }

    local dl = sockets.Downloader()
    dl:Fetch(urls[2])

    rofl = dl

    do return end

    print(url)
    local directory = "os:" .. e.SHARED_FOLDER .. "downloads2/"


    local http = sockets.HTTPClient()

    http.file = vfs.Open(directory .. "test", "write")
    http.file:SetPosition(http.file:GetSize())
    http.written_size = 0

    http:Request("GET", url)

    function http:OnReceiveStatusLine(...)
        print(...)
    end

    function http:OnReceiveHeader(header)
        if header["content-disposition"] then
            local file_name = header["content-disposition"]:match("filename=(%b\"\")")
            if file_name then
                file_name = file_name:sub(2, -2)
                local ext = vfs.GetExtensionFromPath(file_name)
                print(file_name)
            end
        else
            table.print(header)
        end
    end

    function http:WriteBody(chunk)
        self.file:Write(chunk)
        self.written_size = self.written_size + #chunk
    end

    function http:GetWrittenBodySize()
        return self.written_size
    end

    function http:GetWrittenBodyString()
        self.file:PushPosition(0)
        local data = self.file:ReadAll()
        self.file:PopPosition()
        return data or ""
    end

    function http:OnReceiveBody(body)
        print(self.written_size)
    end

    ASDF = http
    do return end
end

local directory = "os:" .. e.SHARED_FOLDER .. "downloads2/"
vfs.CreateDirectoriesFromPath(directory)
local url = "http://www.vidiani.com/maps/maps_of_asia/maps_of_uae/dubai/large_detailed_road_map_of_dubai_city.jpg"
local file_name = vfs.GetFileNameFromPath(url)

if false then
    local database = serializer.ReadFile("luadata", directory .. "database") or {}
    local path = directory .. file_name
    local file = vfs.Open(path .. ".part", "append")
    local existing_header = serializer.ReadFile("luadata", path .. ".meta")
    local size = 0

    local client = sockets.HTTPClient()

    client:Request(url, "GET", {
        ["accept-encoding"] = false,
        ["range"] = "bytes="..file:GetSize() .. "-"
    })

    client.HandleBodyReceive = false -- feels hacky

    function client:OnReceiveHeader(header)
        if existing_header then
            if
                (header["etag"] and header["etag"] ~= existing_header["etag"]) or
                (header["last-modified"] and header["last-modified"] ~= existing_header["last-modified"])
            then
                -- RESTART
                self:Remove()
                return false
            end
        end

        database[url] = {
            id = header["etag"] or header["last-modified"],
        }

        serializer.WriteFile("luadata", path .. ".meta", header)
    end

    function client:OnReceiveBodyChunk(chunk)
        file:Write(chunk)
        size = size + #chunk
        if size >= self.Header["content-length"] then
            assert(vfs.Rename(path .. ".part", file_name))
            vfs.Delete(path .. ".meta")
            self:Close()
            database[url].downloaded = true
            serializer.WriteFile("luadata", directory .. "database", database)
            return false
        end
    end

    do return end
end

do
    local max_connections = 8

    if not vfs.IsFile(directory .. file_name .. "_original") then
        sockets.HTTPRequest({
            method = "GET",
            url = url,
            on_body = function(body)
                vfs.Write(directory .. file_name .. "_original", body)
            end,
        })
    end

    sockets.HTTPRequest({
        method = "HEAD",
        url = url,
        header = {
            ["accept-encoding"] = false,
        },
        on_header = function(header)
            local length = header["content-length"]
            local chunk_size = math.ceil(length / max_connections) + 1

            print("download size is: " .. utility.FormatFileSize(length))
            print("chunk size is: " .. utility.FormatFileSize(chunk_size))
            print("opening " .. max_connections)

            local active = max_connections
            local total = 0

            for i = 1, max_connections do
                local chunk_path = file_name.."."..i .. "." .. chunk_size .. ".part"
                local full_path = vfs.GetFiles({path = directory, filter = chunk_path, full_path = true})[1]

                local chunk_received_size = full_path and vfs.GetSize(full_path) or 0
                local range = "bytes=" .. (chunk_received_size + ((i-1) * chunk_size)) .. "-" .. (i * chunk_size) - 1

                if chunk_received_size < chunk_size then
                    local file
                    local socket, resp
                    socket, resp = sockets.HTTPRequest({
                        method = "GET",
                        url = url,
                        header = {
                            range = range,
                        },
                        on_header = function(header)
                            if not header["content-range"] then
                                return socket:Error("server does not return content-range")
                            end

                            local remote_start, remote_stop = header["content-range"]:match("bytes (%d+)%-(%d+)/")
                            local requested_start, requested_stop = range:match("bytes=(%d+)%-(%d+)")

                            total = total + header["content-length"] - 1

                            if requested_start ~= remote_start then
                                return socket:Error("unexpected content-range: got " .. (remote_start .. " - " .. remote_stop) .. " expected " .. (requested_start .. " - " .. requested_stop))
                            end

                            file = assert(vfs.Open(directory .. chunk_path, chunk_received_size == 0 and "write" or "append"))
                        end,
                        on_body_chunk = function(data)
                            file:Write(data)
                        end,
                        on_body = function()
                            file:Close()

                            active = active - 1

                            if active == 0 then
                                local data = ""
                                for i = 1, max_connections do
                                    data = data .. (vfs.Read(directory .. file_name.."."..i .. "." .. chunk_size .. ".part") or "")
                                end
                                vfs.Write(directory .. file_name, data)

                                local a = vfs.Read(directory .. file_name .. "_original")
                                local b = data

                                if a and b and a ~= b then
                                    local function tohex(str)
                                        return str:gsub("(.)", function(str) str = ("%X"):format(str:byte()) if #str == 1 then str = "0" .. str end return str .. "\n" end)
                                    end
                                    utility.MeldDiff(tohex(a), tohex(b))
                                end

                                for i = 1, max_connections do
                                    vfs.Delete(directory .. file_name.."."..i .. "." .. chunk_size .. ".part")
                                end
                            end
                        end,
                    })
                else
                    print("chunk " .. i .. " is finished", chunk_received_size, chunk_size)
                end
            end
        end,
    })
end

function utility.MeldDiff(a, b)
	local name_a = os.tmpname()
	local name_b = os.tmpname()

	local f = io.open(name_a, "wb")
	f:write(a)
	f:close()

	local f = io.open(name_b, "wb")
	f:write(b)
	f:close()

	os.execute("meld " .. name_a .. " " .. name_b)
end


