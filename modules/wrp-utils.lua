module("utils", package.seeall)

local json, io, os, coroutine, string, table = 
      require('json'), require('io'), require('os'), require('coroutine'), require('string'), require('table')

local scapes, utils =
  {
    ["\\"] = "\\\\",
    ["\0"] = "\\0",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
    quote  = '"',
    quote2 = '"',
    ["["]  = '[',
    ["]"]  = ']'
  }, 
  {}

-- 
local function escape_it(scape) 
  return scapes[scape] or scape
end

-- 
local function sort_it(a, b)
  return a.k==b.k and (a.v<b.v) or (a.k<b.k)
end

-- 
local function dump(data, depth)
  local t = type(data)
  if t=='string' then
    return scapes.quote .. string.gsub(data, "%c", escape_it) .. scapes.quote2
  elseif t=='table' then 
    local indent, is_array, estimate, i, lines, source = string.rep(' ', depth), true, 0, 1, {}, ''
    for k,v in pairs(data) do 
      if not (k==i) then is_array=false end
      i = i+1 
    end
    i = 1
    for k,v in (is_array and ipairs or pairs)(data) do
      s        = is_array and '' or ((type(k)=='string' and 
        string.find(k, "^[%a_][%a%d_]*$")~=nil) and k..' = ' or 
        '['..dump(k, depth+2)..'] = ')
      s        = s..dump(v, depth+2)
      lines[i] = s
      estimate = estimate + #s
      i        = i + 1
    end
    return estimate>200 and 
        "{\n"..indent.. table.concat(lines, ",\n"..indent) .."\n".. string.rep(' ', depth-2) .."}" or 
        "{".. table.concat(lines, ", ") .."}"
  else
    return tostring(data)
  end
end

-- 
local function merge_tables(t, t2)
  for k,v in pairs(t2) do
    t[k] = v
  end
end

-- 
local function copy_table(tx)
  local copy = {}
  for k, v in pairs(tx) do
    if type(v)=='string' or type(v)=='number' or 
       type(v)=='boolean' or type(v)=='table' then
      copy[k] = v
    end
  end
  return copy
end

function utils:new()
  local this

  this = {
      last_fm = {
        key        = '71e3c271bf0cb0f938a996628566b546',
        secret     = '1e1400c452cf23f95c1992b6a7af92be',
        base_point = 'http://ws.audioscrobbler.com/2.0/',
        auth_point = 'http://www.last.fm/api/auth/',
        token      = '',
        authorized = false,
        busy_state = false,
        session    = {
          user = '',
          key  = ''
        }
      },

      pidgin = {
        status        = '',
        message       = '',
        should_change = false
      },

      meta   = {  
        last    = {
          artist     = '',
          song       = '',
          started_at = 0
        },
        current = {
          artist = '',
          song   = '',
          loved  = false
        },
        correct = {
          artist   = '',
          song     = '',
          duration = 0
        }
      },

      debug = function(self, ...)
        local args, i = {...}, 1
        for i=1, #args do
          args[i] = dump(args[i], 2)
        end
        vlc.msg.warn(table.concat(args, "\t"))
      end,

      escape = function(self, str)
        if not str then
          return ''
        end
        return string.gsub(
                  string.gsub(str, '\n', '\r\n'), 
                  '([^%w%.])', 
                  function(c) return string.format('%%%02X', string.byte(c)) end
                )
      end,

      unescape = function(self, str)
        if not str then
          return ''
        end
        return string.gsub(
                  str, 
                  "%%(%x%x)", 
                  function(h) return string.char(tonumber(h, 16)) end
                )
      end,

      md5 = function(self, string)
        local handler = io.popen('printf "'.. string ..'" | md5sum')
        return string.sub(handler:read("*a"), 1, 32)
      end,

      -- build query string for last.fm: order query keys, escape values and generate md5 of its contents
      build_query = function(self, ...)
        local args = {...}
        local query, secret, a_query, sig, st_query = args[1], args[2], {}, '', ''

        for key, val in pairs(query) do
          table.insert(a_query, {k=key, v=val})
        end

        table.sort(a_query, sort_it)

        for i=1, #a_query do
          st_query = string.format('%s%s=%s&', st_query, a_query[i].k, self:escape(a_query[i].v))
          if a_query[i].k~='format' then
            sig = string.format('%s%s%s',   sig, a_query[i].k, a_query[i].v)
          end
        end

        return secret~=nil and
               string.format('%s%s=%s', st_query, 'api_sig', self:md5(sig .. secret)) or
               string.sub(st_query, 1, -2)
      end,

      fetch = function(self, url, callback)
        self:debug('fetch url')
        local async_stream = coroutine.create(
          function(url)
            local handler, err, output, read, parsed_json, _ =
              nil, nil, nil, nil, nil, false

            handler, err = vlc.stream(url)
            if not handler then
              callback(nil, err)
            else
              -- check if it is json, xml? ... not yet
              output  = handler:read(65653)
              handler = nil

              _, parsed_json = pcall(
                                  function(rs) return json:decode(rs) end,
                                  string.gsub(output, "^[%c%s]*(.-)[%c%s]*$", "%1")
                                )
              if _==false then
                callback(nil, parsed_json)
              else
                callback(parsed_json, nil)
              end
            end
          end)

        coroutine.resume(async_stream, url)
      end,

      post = function(self, url, data, callback)
        self:debug('post data to url')
        -- post coroutine
        local async_stream = coroutine.create(
            function(url)
              local hnd, result, _ = nil, nil, false
              
              -- open handler
              hnd = io.popen(
                        string.format(
                          'wget -O - --post-data "" "%s" 2>/dev/null || curl -i -X POST "%s" 2>/dev/null', url, url
                        )
                      )
              
              -- read trim and close handler
              result = string.gsub(hnd:read("*a"), "^[%c%s]*(.-)[%c%s]*$", "%1")
              hnd:close()

              -- safe call to json decoder, callback results
              _, result = pcall(function(rs) return json:decode(rs) end, result)
              if _==false then
                callback(nil, _)
              else
                callback(result, nil)
              end
            end)

        -- 
        url = url ..'?'.. (type(data)=='string' and data or self:build_query(data))

        -- call coroutine
        coroutine.resume(async_stream, url)
      end,

      unload = function(self)
        local cfg, err = io.open(vlc.config.configdir() .. "/.wrp", "w")
        if not cfg then
          self:debug("error opening .wrp for writing: " .. err) return
        end
        cfg:write(
            json:encode(
              copy_table(self)
            )
          )
        cfg:close()
      end,

      get_pidgin_defaults = function(self)
        -- gather pidgin message
        local hnd = nil
        hnd = io.popen("purple-remote getstatus")
        self.pidgin.status = string.gsub(hnd:read("*a"), '[%c]*', '')
        hnd:close()

        hnd = io.popen("purple-remote getstatusmessage")
        self.pidgin.message = self:unescape(
                                    string.match(hnd:read("*a"), '[%c%s]*([^\n?%c]*)[%c]*')
                                  )
        hnd:close()
      end,

      set_pidgin = function(self, ...)
        local message, status = ...
        if message~=nil and status~=nil then
          os.execute(
              string.format('purple-remote "setstatus?status=%s&message=%s"', status, self:escape(message))
            )
        elseif message~=nil and status==nil then
          os.execute(
              string.format('purple-remote "setstatus?message=%s"', self:escape(message))
            )
        else
          os.execute(
              string.format('purple-remote "setstatus?status=%s"', status)
            )
        end
      end,

      scrobbler_action = function(self, params, callback)
        local query_table = {
            api_key = self.last_fm.key,
            sk      = self.last_fm.session.key,
            format  = 'json'
          }

        merge_tables(query_table, params)

        self:post(
            self.last_fm.base_point,
            self:build_query(query_table, self.last_fm.secret),
            callback
          )
      end,

      set_pidgin_defaults = function(self)
        os.execute(
          string.format(
              'purple-remote "setstatus?status=%s&message=%s"',
              self.pidgin.status,
              self:escape(self.pidgin.message)
            )
          )
      end,

      scrobbler_now_playing = function(self, callback)
        -- 
        self:scrobbler_action(
            {
              artist = self.meta.current.artist,
              track  = self.meta.current.song,
              method = 'track.updateNowPlaying'
            },
            callback
          )
      end,

      scrobbler_scrobble = function(self, callback)
        -- 
        self:scrobbler_action(
            {
              ['artist[0]']    = self.meta.last.artist,
              ['track[0]']     = self.meta.last.song,
              ['timestamp[0]'] = os.time(),
              method           = 'track.scrobble'
            },
            callback
          )
      end,

      scrobbler_love = function(self, callback)
        --
        self:scrobbler_action(
            {
              artist = self.meta.current.artist,
              track  = self.meta.current.song,
              method = 'track.love'
            },
            callback
          )
      end,

      scrobbler_unlove = function(self, callback)
        --
        self:scrobbler_action(
            {
              artist = self.meta.current.artist,
              track  = self.meta.current.song,
              method = 'track.unlove'
            },
            callback
          )
      end
    }

  local cfg, err = io.open(vlc.config.configdir() .. "/.wrp", "r")
  if cfg then
    local _, data = pcall(function(str) return json:decode(str) end, cfg:read("*a"))
    if _ then
      merge_tables(this, data)
    end
    cfg:close()
  else
    this.debug("error opening .wrp for reding: " .. err)
  end

  setmetatable(this, utils)
  return this
end

return utils